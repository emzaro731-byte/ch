import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const supabaseUrl='https://vihbsfrwnslnmheowkhy.supabase.co';
const supabasePublishableKey='sb_publishable_HIMGxb-O6fj9O7OzT4ukuQ_jm5W8mWz';
const bushaBaseUrl='https://api.busha.co';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Object? initError;
  try {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabasePublishableKey)
        .timeout(const Duration(seconds: 20));
  } catch (e) {
    initError = e;
  }
  runApp(Veylola(initError: initError));
}
final supabase=Supabase.instance.client;

class Veylola extends StatelessWidget {
 final Object? initError;
 const Veylola({super.key, this.initError});
 Widget build(BuildContext c)=>MaterialApp(title:'Veylola Trade',debugShowCheckedModeBanner:false,
  theme:ThemeData.dark(useMaterial3:true).copyWith(scaffoldBackgroundColor:const Color(0xff0b0e11),cardColor:const Color(0xff181a20),colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xfff0b90b),brightness:Brightness.dark)),
  home: initError == null ? const Gate() : StartupError(error: initError.toString()));
}
class StartupError extends StatelessWidget {
  final String error;
  const StartupError({super.key, required this.error});
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_off, size: 64, color: Color(0xfff0b90b)),
        const SizedBox(height: 16),
        const Text('Connection problem', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        const Text('Veylola Trade could not connect to Supabase. Check your internet connection and try again.', textAlign: TextAlign.center),
        const SizedBox(height: 18),
        FilledButton(onPressed: () => main(), child: const Text('Retry connection')),
        const SizedBox(height: 12),
        Text(error.contains('SocketException') || error.contains('Failed host lookup')
          ? 'DNS/network lookup failed for the Supabase server.'
          : 'Supabase initialization failed.',
          textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)),
      ]),
    ))),
  );
}
class Gate extends StatelessWidget {
 const Gate({super.key});
 Widget build(BuildContext c)=>StreamBuilder<AuthState>(stream:supabase.auth.onAuthStateChange,builder:(_,s)=>(s.data?.session??supabase.auth.currentSession)==null?const Login():const Exchange());
}
class Login extends StatefulWidget { const Login({super.key}); State<Login> createState()=>_LoginState(); }
class _LoginState extends State<Login>{
 final e=TextEditingController(),p=TextEditingController(); bool busy=false; String msg='';
 Future<void> go(bool create) async {
  final email = e.text.trim();
  final password = p.text;
  if (email.isEmpty || !email.contains('@')) {
    setState(() => msg = 'Enter a valid email address.');
    return;
  }
  if (password.length < 6) {
    setState(() => msg = 'Password must be at least 6 characters.');
    return;
  }
  setState(() { busy = true; msg = ''; });
  try {
    if (create) {
      await supabase.auth.signUp(email: email, password: password)
          .timeout(const Duration(seconds: 20));
      if (mounted) setState(() => msg = 'Account created. Check your email if confirmation is enabled.');
    } else {
      await supabase.auth.signInWithPassword(email: email, password: password)
          .timeout(const Duration(seconds: 20));
    }
  } on TimeoutException {
    if (mounted) setState(() => msg = 'Connection timed out. Check your internet/DNS and try again.');
  } on SocketException catch (x) {
    if (mounted) setState(() => msg = 'Network/DNS error: ${x.message}. Make sure your phone can reach Supabase.');
  } on AuthException catch (x) {
    if (mounted) setState(() => msg = 'Authentication failed: ${x.message}');
  } catch (x) {
    final text = x.toString();
    if (mounted) setState(() => msg = text.contains('Failed host lookup')
        ? 'Cannot resolve the Supabase server. Check DNS/network and retry.'
        : 'Authentication failed: $text');
  } finally {
    if (mounted) setState(() => busy = false);
  }
}
 Widget build(BuildContext c)=>Scaffold(body:SafeArea(child:Center(child:SingleChildScrollView(padding:const EdgeInsets.all(24),child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:480),child:Column(children:[
 const Icon(Icons.currency_bitcoin,size:56,color:Color(0xfff0b90b)),const SizedBox(height:10),const Text('Veylola Trade',style:TextStyle(fontSize:34,fontWeight:FontWeight.w800)),const Text('Full crypto exchange workspace'),const SizedBox(height:28),
 TextField(controller:e,decoration:const InputDecoration(labelText:'Email',border:OutlineInputBorder())),const SizedBox(height:12),TextField(controller:p,obscureText:true,decoration:const InputDecoration(labelText:'Password',border:OutlineInputBorder())),const SizedBox(height:16),
 FilledButton(onPressed:busy?null:()=>go(false),child:Text(busy?'Please wait…':'Sign in')),OutlinedButton(onPressed:busy?null:()=>go(true),child:const Text('Create account')),if(msg.isNotEmpty)Text(msg)
]))))));
}
class Exchange extends StatefulWidget{const Exchange({super.key});State<Exchange>createState()=>_ExchangeState();}
class _ExchangeState extends State<Exchange>{int i=0;final pages=const[Home(),Markets(),Trade(),Futures(),Assets()];Widget build(BuildContext c)=>Scaffold(body:IndexedStack(index:i,children:pages),bottomNavigationBar:NavigationBar(selectedIndex:i,onDestinationSelected:(x)=>setState(()=>i=x),destinations:const[
 NavigationDestination(icon:Icon(Icons.home_outlined),selectedIcon:Icon(Icons.home),label:'Home'),NavigationDestination(icon:Icon(Icons.show_chart),label:'Markets'),NavigationDestination(icon:Icon(Icons.swap_horiz),label:'Trade'),NavigationDestination(icon:Icon(Icons.candlestick_chart),label:'Futures'),NavigationDestination(icon:Icon(Icons.account_balance_wallet_outlined),label:'Assets')]));}

class Api{
 static Future<dynamic> get(String path)async{final cl=HttpClient();try{final res=await cl.getUrl(Uri.parse(bushaBaseUrl+path)).then((x)=>x.close());final body=await res.transform(utf8.decoder).join();if(res.statusCode!=200)throw Exception('Busha HTTP '+res.statusCode.toString());final data=jsonDecode(body);if(data is Map&&data['status']=='error')throw Exception(data['message']?.toString()??'Busha API error');return data is Map&&data.containsKey('data')?data['data']:data;}finally{cl.close(force:true);}}
 static Future<List<dynamic>> pairs()=>get('/v1/pairs').then((x)=>List<dynamic>.from(x as List));
 static Future<Map<String,dynamic>> pair(String s)=>pairs().then((list){final hit=list.cast<dynamic>().firstWhere((x)=>x is Map&&x['id'].toString().toUpperCase()==s.toUpperCase(),orElse:()=>null);return hit==null?<String,dynamic>{}:Map<String,dynamic>.from(hit as Map);});
 static String change(Map<String,dynamic> x){final buy=x['buy_price'] is Map?x['buy_price']['amount']?.toString():null;final sell=x['sell_price'] is Map?x['sell_price']['amount']?.toString():null;return buy!=null&&sell!=null?'Buy '+buy+' • Sell '+sell:'—';}
}
class BushaSecure{
 static Future<dynamic> call(String action,{Map<String,dynamic> data=const{}})async{final r=await supabase.functions.invoke('busha',body:{'action':action,...data});final d=r.data;if(d is Map&&d['error']!=null)throw Exception(d['error'].toString());return d;}
 static Future<void> connect(String secret)=>call('connect',data:{'secretApiKey':secret});
 static Future<List<dynamic>> balances()=>call('balances').then((x)=>List<dynamic>.from(x as List));
 static Future<List<dynamic>> transfers()=>call('transfers').then((x)=>List<dynamic>.from(x as List));
 static Future<Map<String,dynamic>> quote({required String source,required String target,required String amount})=>call('quote',data:{'sourceCurrency':source,'targetCurrency':target,'sourceAmount':amount}).then((x)=>Map<String,dynamic>.from(x as Map));
 static Future<dynamic> execute(String quoteId)=>call('execute',data:{'quoteId':quoteId});
}class BushaConnect extends StatefulWidget{const BushaConnect({super.key});State<BushaConnect>createState()=>_BushaConnectState();}
class _BushaConnectState extends State<BushaConnect>{
 final s=TextEditingController();bool busy=false;String msg='';
 Future<void> save()async{if(s.text.trim().isEmpty){setState(()=>msg='Enter your Busha Secret API key.');return;}setState(()=>busy=true);try{await BushaSecure.connect(s.text.trim());if(mounted)Navigator.pop(context,true);}catch(e){if(mounted)setState(()=>msg=e.toString().replaceFirst('Exception: ',''));}finally{if(mounted)setState(()=>busy=false);}}
 Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('Connect Busha')),body:ListView(padding:const EdgeInsets.all(20),children:[const Text('Connect your Busha Business account',style:TextStyle(fontSize:24,fontWeight:FontWeight.w800)),const SizedBox(height:8),const Text('Use a Busha Secret API key. It stays on the secure backend and is encrypted at rest.',style:TextStyle(color:Colors.white70)),const SizedBox(height:18),TextField(controller:s,obscureText:true,decoration:const InputDecoration(labelText:'Busha Secret API key',border:OutlineInputBorder())),const SizedBox(height:16),FilledButton(onPressed:busy?null:save,child:Text(busy?'Connecting…':'Connect account')),if(msg.isNotEmpty)Padding(padding:const EdgeInsets.only(top:12),child:Text(msg,style:const TextStyle(color:Colors.redAccent)))]));
}class BushaTransfers extends StatefulWidget{const BushaTransfers({super.key});State<BushaTransfers>createState()=>_BushaTransfersState();}
class _BushaTransfersState extends State<BushaTransfers>{List<dynamic> rows=[];bool loading=true;String msg='';initState(){super.initState();load();}Future<void>load()async{try{rows=await BushaSecure.transfers();if(mounted)setState(()=>msg='');}catch(e){if(mounted)setState(()=>msg=e.toString().replaceFirst('Exception: ',''));}finally{if(mounted)setState(()=>loading=false);}}Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('Transaction history')),body:RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.all(16),children:[if(loading)const LinearProgressIndicator(),if(msg.isNotEmpty)Card(child:Padding(padding:const EdgeInsets.all(16),child:Text(msg))),if(!loading&&rows.isEmpty)const Card(child:ListTile(title:Text('No transactions'),subtitle:Text('Your Busha transfer history will appear here.'))),...rows.map((x){final m=Map<String,dynamic>.from(x as Map);return Card(child:ListTile(title:Text((m['source_currency']??'—').toString()+' → '+(m['target_currency']??'—').toString()),subtitle:Text((m['status']??'—').toString()),trailing:Text(m['source_amount']?.toString()??'—')));})])));}
class Home extends StatefulWidget{const Home({super.key});State<Home>createState()=>_HomeState();}
class _HomeState extends State<Home>{final sy=['BTCUSDT','ETHUSDT','BTCNGN','ETHNGN'];final d=<String,Map<String,dynamic>>{};Timer? timer;
 initState(){super.initState();load();timer=Timer.periodic(const Duration(seconds:8),(_)=>load());}
 Future<void>load()async{try{for(final s in sy)d[s]=await Api.pair(s);if(mounted)setState((){});}catch(_){}}void dispose(){timer?.cancel();super.dispose();}
 Widget build(BuildContext c)=>SafeArea(child:RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.all(16),children:[
 Row(children:[const CircleAvatar(backgroundColor:Color(0xfff0b90b),child:Icon(Icons.currency_bitcoin,color:Colors.black)),const SizedBox(width:10),const Expanded(child:Text('Veylola',style:TextStyle(fontSize:23,fontWeight:FontWeight.w800))),IconButton(onPressed:()=>supabase.auth.signOut(),icon:const Icon(Icons.logout))]),
 const SizedBox(height:16),TextField(decoration:InputDecoration(hintText:'Search coins, pairs and features',prefixIcon:const Icon(Icons.search),filled:true,fillColor:const Color(0xff181a20),border:OutlineInputBorder(borderSide:BorderSide.none,borderRadius:BorderRadius.circular(14)))),
 const SizedBox(height:18),const Text('Busha account',style:TextStyle(color:Colors.white60)),const Text('Live balances available in Assets',style:TextStyle(fontSize:22,fontWeight:FontWeight.w800)),const Text('Connected Busha Business account',style:TextStyle(color:Colors.white54)),
 const SizedBox(height:18),Row(children:[Q(Icons.add,'Deposit'),Q(Icons.send,'Withdraw'),Q(Icons.swap_horiz,'Convert'),Q(Icons.qr_code,'Pay')]),const SizedBox(height:22),const Text('Markets',style:TextStyle(fontSize:20,fontWeight:FontWeight.w800)),const SizedBox(height:8),
 ...sy.map((s)=>Tile(symbol:s,price:d[s]?['buy_price']?['amount']?.toString()??'—',change:d[s]==null?'—':Api.change(d[s]!))),
 const SizedBox(height:10),Feature('Earn','Savings, staking and yield products',Icons.savings_outlined),Feature('P2P','Buy and sell with local payment methods',Icons.people_outline),Feature('Copy Trading','Track strategies and paper-test them',Icons.copy_all_outlined)
 ])));
}
class Q extends StatelessWidget{final IconData i;final String s;const Q(this.i,this.s,{super.key});Widget build(BuildContext c)=>Expanded(child:Column(children:[CircleAvatar(backgroundColor:const Color(0xff2b2f36),child:Icon(i)),const SizedBox(height:5),Text(s,style:const TextStyle(fontSize:11))]));}
class Tile extends StatelessWidget{final String symbol,price,change;const Tile({required this.symbol,required this.price,required this.change,super.key});Widget build(BuildContext c){final up=!change.startsWith('-');return Card(child:ListTile(leading:CircleAvatar(backgroundColor:const Color(0xff2b2f36),child:Text(symbol[0])),title:Text(symbol.replaceAll('USDT','/USDT'),style:const TextStyle(fontWeight:FontWeight.bold)),subtitle:const Text('24h'),trailing:Column(mainAxisAlignment:MainAxisAlignment.center,crossAxisAlignment:CrossAxisAlignment.end,children:[Text(price),Text(change=='—'?'—':change+'%',style:TextStyle(color:up?Colors.greenAccent:Colors.redAccent))])));}}
class Feature extends StatelessWidget{final String a,b;final IconData i;const Feature(this.a,this.b,this.i,{super.key});Widget build(BuildContext c)=>Card(child:ListTile(leading:CircleAvatar(backgroundColor:const Color(0xff2b2f36),child:Icon(i)),title:Text(a,style:const TextStyle(fontWeight:FontWeight.bold)),subtitle:Text(b),trailing:const Icon(Icons.chevron_right)));}

class Markets extends StatefulWidget{const Markets({super.key});State<Markets>createState()=>_MarketsState();}
class _MarketsState extends State<Markets>{List<dynamic> rows=[];String q='';bool loading=true;initState(){super.initState();load();}
 Future<void>load()async{try{final a=await Api.pairs();rows=a.where((x){final s=x['id'].toString();return s.endsWith('USDT')||s.endsWith('NGN');}).toList();}catch(_){}if(mounted)setState(()=>loading=false);}
 Widget build(BuildContext c)=>SafeArea(child:RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.all(16),children:[const Text('Markets',style:TextStyle(fontSize:28,fontWeight:FontWeight.w800)),const SizedBox(height:12),TextField(onChanged:(x)=>setState(()=>q=x.toUpperCase()),decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'Search pair',border:OutlineInputBorder())),const SizedBox(height:12),const Row(children:[Expanded(child:Text('Favorites',textAlign:TextAlign.center)),Expanded(child:Text('Spot',textAlign:TextAlign.center)),Expanded(child:Text('Futures',textAlign:TextAlign.center)),Expanded(child:Text('New',textAlign:TextAlign.center))]),const SizedBox(height:10),if(loading)const LinearProgressIndicator(),...rows.where((x)=>x['id'].toString().contains(q)).map((x)=>Tile(symbol:x['id'].toString(),price:x['buy_price']?['amount']?.toString()??'—',change:Api.change(Map<String,dynamic>.from(x as Map))))])));}
class Trade extends StatefulWidget{const Trade({super.key});State<Trade>createState()=>_TradeState();}
class _TradeState extends State<Trade>{String s='BTCUSDT',side='BUY';Map<String,dynamic>? t;final a=TextEditingController();String msg='Get a quote before confirming a trade.';bool busy=false;initState(){super.initState();load();}Future<void>load()async{try{t=await Api.pair(s);if(mounted)setState((){});}catch(_){}}Future<void>trade()async{if(a.text.trim().isEmpty){setState(()=>msg='Enter an amount.');return;}if(t==null||t!.isEmpty){setState(()=>msg='Market pair unavailable.');return;}final source=side=='BUY'?t!['counter'].toString():t!['base'].toString();final target=side=='BUY'?t!['base'].toString():t!['counter'].toString();setState(()=>busy=true);try{final q=await BushaSecure.quote(source:source,target:target,amount:a.text.trim());final id=q['id']?.toString()??'';if(id.isEmpty)throw Exception('No Busha quote ID returned.');if(!mounted)return;final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:Text('Confirm $side trade'),content:Text(source+' '+a.text.trim()+' → '+target+' '+(q['target_amount']??'—').toString()),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Confirm'))]))??false;if(!ok){setState(()=>msg='Trade cancelled.');return;}await BushaSecure.execute(id);setState(()=>msg='Busha trade submitted successfully.');}catch(e){setState(()=>msg='Trade failed: '+e.toString().replaceFirst('Exception: ',''));}finally{if(mounted)setState(()=>busy=false);}}Widget build(BuildContext c)=>SafeArea(child:ListView(padding:const EdgeInsets.all(16),children:[Row(children:[const Text('Trade',style:TextStyle(fontSize:28,fontWeight:FontWeight.w800)),const Spacer(),DropdownButton<String>(value:s,items:const['BTCUSDT','ETHUSDT','BTCNGN','ETHNGN'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(x){if(x!=null){setState(()=>s=x);load();}})]),Card(child:ListTile(title:const Text('Buy price'),trailing:Text(t?['buy_price']?['amount']?.toString()??'—'))),Card(child:ListTile(title:const Text('Sell price'),trailing:Text(t?['sell_price']?['amount']?.toString()??'—'))),const SizedBox(height:12),SegmentedButton<String>(segments:const[ButtonSegment(value:'BUY',label:Text('Buy')),ButtonSegment(value:'SELL',label:Text('Sell'))],selected:{side},onSelectionChanged:(x)=>setState(()=>side=x.first)),const SizedBox(height:12),TextField(controller:a,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:side=='BUY'?'Amount in '+(t?['counter']??'quote').toString():'Amount in '+(t?['base']??'base').toString(),border:const OutlineInputBorder())),const SizedBox(height:16),FilledButton(onPressed:busy?null:trade,child:Text(busy?'Processing…':'Get quote & trade')),const SizedBox(height:12),Card(child:Padding(padding:const EdgeInsets.all(14),child:Text(msg)))]));}

class Futures extends StatelessWidget {
  const Futures({super.key});

  @override
  Widget build(BuildContext c) => SafeArea(
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Futures', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        const Text('Busha spot trading workspace'),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('BTCUSDT Perpetual', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                const Text('Futures are disabled in this Busha integration.'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: FilledButton(onPressed: () {}, child: const Text('Long'))),
                    const SizedBox(width: 10),
                    Expanded(child: OutlinedButton(onPressed: () {}, child: const Text('Short'))),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Feature('Positions', 'No live futures positions', Icons.bar_chart),
        Feature('Order history', 'Paper order history', Icons.history),
        Feature('Risk controls', 'Margin, leverage and liquidation controls', Icons.security),
      ],
    ),
  );
}

class Assets extends StatefulWidget{const Assets({super.key});State<Assets>createState()=>_AssetsState();}class _AssetsState extends State<Assets>{List<dynamic> data=[];bool loading=true;String msg='';initState(){super.initState();load();}Future<void>load()async{try{data=await BushaSecure.balances();if(mounted)setState(()=>msg='');}catch(e){if(mounted)setState(()=>msg=e.toString().replaceFirst('Exception: ',''));}finally{if(mounted)setState(()=>loading=false);}}Widget build(BuildContext c)=>SafeArea(child:RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.all(16),children:[const Text('Assets',style:TextStyle(fontSize:28,fontWeight:FontWeight.w800)),const SizedBox(height:8),const Text('Busha Business balances',style:TextStyle(color:Colors.white60)),const SizedBox(height:14),Row(children:[Expanded(child:FilledButton(onPressed:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>const BushaConnect())).then((_){load();}),child:const Text('Connect / reconnect'))),const SizedBox(width:10),Expanded(child:OutlinedButton(onPressed:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>const BushaTransfers())),child:const Text('Transaction history')))]),const SizedBox(height:12),if(msg.isNotEmpty)Card(child:Padding(padding:const EdgeInsets.all(14),child:Text(msg))),if(loading)const LinearProgressIndicator(),const SizedBox(height:12),const Text('Wallets',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const SizedBox(height:8),if(data.isEmpty&&!loading)const Card(child:ListTile(title:Text('No wallet data'),subtitle:Text('Connect your Busha Business account to load balances.'))),...data.map((x){final m=Map<String,dynamic>.from(x as Map);final amount=m['available'] is Map?m['available']['amount']?.toString()??'0':'0';return Bal(m['currency']?.toString()??'—',amount,m['type']?.toString()??'');})])));} 

class Bal extends StatelessWidget{final String c,a,v;const Bal(this.c,this.a,this.v,{super.key});Widget build(BuildContext x)=>Card(child:ListTile(leading:CircleAvatar(backgroundColor:const Color(0xff2b2f36),child:Text(c.isEmpty?'?':c[0])),title:Text(c,style:const TextStyle(fontWeight:FontWeight.bold)),subtitle:Text(v),trailing:Text(a)));}
