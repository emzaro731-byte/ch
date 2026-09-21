import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const BUSHA_BASE = Deno.env.get("BUSHA_BASE_URL") ?? "https://api.busha.co";
const ENC_KEY = Deno.env.get("BUSHA_ENCRYPTION_KEY") ?? "";
const cors = {"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type"};

function bytes(s:string){return new TextEncoder().encode(s)}
async function aesKey(){
  if(!ENC_KEY) throw new Error("BUSHA_ENCRYPTION_KEY is not configured");
  const d=await crypto.subtle.digest("SHA-256",bytes(ENC_KEY));
  return crypto.subtle.importKey("raw",d,{name:"AES-GCM"},false,["encrypt","decrypt"]);
}
async function encryptSecret(secret:string){
  const iv=crypto.getRandomValues(new Uint8Array(12));
  const e=await crypto.subtle.encrypt({name:"AES-GCM",iv},await aesKey(),bytes(secret));
  return {cipher:btoa(String.fromCharCode(...new Uint8Array(e))),iv:btoa(String.fromCharCode(...iv))};
}
async function decryptSecret(cipher:string,iv:string){
  const d=Uint8Array.from(atob(cipher),c=>c.charCodeAt(0));
  const n=Uint8Array.from(atob(iv),c=>c.charCodeAt(0));
  const p=await crypto.subtle.decrypt({name:"AES-GCM",iv:n},await aesKey(),d);
  return new TextDecoder().decode(p);
}
async function bushaRequest(secret:string,method:string,path:string,body:Record<string,unknown>|null=null){
  const bodyText=body?JSON.stringify(body):undefined;
  const res=await fetch(BUSHA_BASE+path,{method,headers:{"Authorization":"Bearer "+secret,"Content-Type":"application/json","Accept":"application/json"},body:bodyText});
  const text=await res.text();
  let data:any={};
  try{data=text?JSON.parse(text):{};}catch{throw new Error("Busha returned an invalid response");}
  if(!res.ok||data.status==="error") throw new Error(data.message??data.error??("Busha HTTP "+res.status));
  return data.data??data;
}

Deno.serve(async req=>{
  if(req.method==="OPTIONS") return new Response("ok",{headers:cors});
  try{
    const auth=req.headers.get("Authorization");
    if(!auth) throw new Error("Not authenticated");
    const supabase=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_ANON_KEY")!,{global:{headers:{Authorization:auth}}});
    const {data:{user},error:userError}=await supabase.auth.getUser();
    if(userError||!user) throw new Error("Not authenticated");

    const input=await req.json();
    const action=String(input.action??"");
    const table="busha_connections";

    if(action==="connect"){
      const secret=String(input.secretApiKey??"").trim();
      if(!secret) throw new Error("Busha Secret API key is required");
      await bushaRequest(secret,"GET","/v1/balances");
      const enc=await encryptSecret(secret);
      const {error}=await supabase.from(table).upsert({user_id:user.id,secret_cipher:enc.cipher,secret_iv:enc.iv,updated_at:new Date().toISOString()});
      if(error) throw error;
      return Response.json({connected:true},{headers:cors});
    }

    const {data:conn,error:connError}=await supabase.from(table).select("secret_cipher,secret_iv").eq("user_id",user.id).maybeSingle();
    if(connError) throw connError;
    if(!conn) throw new Error("Busha account is not connected");
    const secret=await decryptSecret(conn.secret_cipher,conn.secret_iv);

    if(action==="balances"){
      return Response.json(await bushaRequest(secret,"GET","/v1/balances"),{headers:cors});
    }
    if(action==="pairs"){
      return Response.json(await bushaRequest(secret,"GET","/v1/pairs"),{headers:cors});
    }
    if(action==="quote"){
      const source=String(input.sourceCurrency??"").toUpperCase();
      const target=String(input.targetCurrency??"").toUpperCase();
      const amount=String(input.sourceAmount??"");
      if(!source||!target||!amount||Number(amount)<=0) throw new Error("Invalid quote request");
      return Response.json(await bushaRequest(secret,"POST","/v1/quotes",{source_currency:source,target_currency:target,source_amount:amount,type:"convert"}),{headers:cors});
    }
    if(action==="execute"){
      const quoteId=String(input.quoteId??"");
      if(!quoteId) throw new Error("Quote ID is required");
      return Response.json(await bushaRequest(secret,"POST","/v1/transfers",{quote_id:quoteId}),{headers:cors});
    }
    if(action==="transfer"){
      const transferId=String(input.transferId??"");
      if(!transferId) throw new Error("Transfer ID is required");
      return Response.json(await bushaRequest(secret,"GET","/v1/transfers/"+encodeURIComponent(transferId)),{headers:cors});
    }
    if(action==="transfers"){
      return Response.json(await bushaRequest(secret,"GET","/v1/transfers"),{headers:cors});
    }
    if(action==="disconnect"){
      const {error}=await supabase.from(table).delete().eq("user_id",user.id);
      if(error) throw error;
      return Response.json({connected:false},{headers:cors});
    }
    throw new Error("Unknown action");
  }catch(e){
    return Response.json({error:String(e instanceof Error?e.message:e)},{status:400,headers:cors});
  }
});