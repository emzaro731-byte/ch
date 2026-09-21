import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
const BYBIT = Deno.env.get("BYBIT_BASE_URL") ?? "https://api.bybit.com";
const ENC_KEY = Deno.env.get("BYBIT_ENCRYPTION_KEY") ?? "";
const cors = {"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type"};
function hex(buf:ArrayBuffer){return [...new Uint8Array(buf)].map(b=>b.toString(16).padStart(2,"0")).join("")}
function bytes(s:string){return new TextEncoder().encode(s)}
async function hmac(secret:string,message:string){const k=await crypto.subtle.importKey("raw",bytes(secret),{name:"HMAC",hash:"SHA-256"},false,["sign"]);return hex(await crypto.subtle.sign("HMAC",k,bytes(message)))}
async function aesKey(){if(!ENC_KEY)throw new Error("BYBIT_ENCRYPTION_KEY is not configured");const d=await crypto.subtle.digest("SHA-256",bytes(ENC_KEY));return crypto.subtle.importKey("raw",d,{name:"AES-GCM"},false,["encrypt","decrypt"])}
async function encryptSecret(secret:string){const iv=crypto.getRandomValues(new Uint8Array(12));const e=await crypto.subtle.encrypt({name:"AES-GCM",iv},await aesKey(),bytes(secret));return {cipher:btoa(String.fromCharCode(...new Uint8Array(e))),iv:btoa(String.fromCharCode(...iv))}}
async function decryptSecret(cipher:string,iv:string){const d=Uint8Array.from(atob(cipher),c=>c.charCodeAt(0));const n=Uint8Array.from(atob(iv),c=>c.charCodeAt(0));const p=await crypto.subtle.decrypt({name:"AES-GCM",iv:n},await aesKey(),d);return new TextDecoder().decode(p)}
async function bybitRequest(apiKey:string,secret:string,method:string,path:string,query="",body:Record<string,unknown>|null=null){
 const ts=Date.now().toString(),recv="5000",bodyText=body?JSON.stringify(body):"",payload=ts+apiKey+recv+(method==="GET"?query:bodyText),signature=await hmac(secret,payload);
 const res=await fetch(BYBIT+path+(method==="GET"&&query?"?"+query:""),{method,headers:{"Content-Type":"application/json","X-BAPI-API-KEY":apiKey,"X-BAPI-TIMESTAMP":ts,"X-BAPI-RECV-WINDOW":recv,"X-BAPI-SIGN":signature},body:method==="POST"?bodyText:undefined});
 const data=await res.json(); if(!res.ok||data.retCode!==0)throw new Error(data.retMsg??"Bybit request failed"); return data.result;
}
Deno.serve(async req=>{
 if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
 try{
  const auth=req.headers.get("Authorization");if(!auth)throw new Error("Not authenticated");
  const supabase=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_ANON_KEY")!,{global:{headers:{Authorization:auth}}});
  const {data:{user},error:userError}=await supabase.auth.getUser();if(userError||!user)throw new Error("Not authenticated");
  const input=await req.json(),action=String(input.action??""),table="bybit_connections";
  if(action==="connect"){
   const apiKey=String(input.apiKey??"").trim(),secret=String(input.apiSecret??"").trim();if(!apiKey||!secret)throw new Error("API key and API secret are required");
   await bybitRequest(apiKey,secret,"GET","/v5/user/query-api");const enc=await encryptSecret(secret);
   const {error}=await supabase.from(table).upsert({user_id:user.id,api_key:apiKey,secret_cipher:enc.cipher,secret_iv:enc.iv,updated_at:new Date().toISOString()});if(error)throw error;
   return Response.json({connected:true},{headers:cors});
  }
  const {data:conn,error:connError}=await supabase.from(table).select("api_key,secret_cipher,secret_iv").eq("user_id",user.id).maybeSingle();if(connError)throw connError;if(!conn)throw new Error("Bybit account is not connected");
  if(action==="disconnect"){const {error}=await supabase.from(table).delete().eq("user_id",user.id);if(error)throw error;return Response.json({connected:false},{headers:cors})}
  const secret=await decryptSecret(conn.secret_cipher,conn.secret_iv),apiKey=conn.api_key;
  if(action==="balance")return Response.json(await bybitRequest(apiKey,secret,"GET","/v5/account/wallet-balance","accountType=UNIFIED"),{headers:cors});
  if(action==="orders")return Response.json(await bybitRequest(apiKey,secret,"GET","/v5/order/history","category=spot&limit=50"),{headers:cors});
  if(action==="order"){
   const symbol=String(input.symbol??"").toUpperCase(),side=String(input.side)==="SELL"?"Sell":"Buy",orderType=String(input.orderType)==="LIMIT"?"Limit":"Market",qty=String(input.qty??"");
   if(!symbol||!qty||Number(qty)<=0)throw new Error("Invalid order");const body:Record<string,unknown>={category:"spot",symbol,side,orderType,qty};
   if(orderType==="Limit"){const price=String(input.price??"");if(!price||Number(price)<=0)throw new Error("Limit price is required");body.price=price;body.timeInForce="GTC"}
   return Response.json(await bybitRequest(apiKey,secret,"POST","/v5/order/create","",body),{headers:cors});
  }
  throw new Error("Unknown action");
 }catch(e){return Response.json({error:String(e instanceof Error?e.message:e)},{status:400,headers:cors})}
});