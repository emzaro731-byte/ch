import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const supabaseUrl='https://vihbsfrwnslnmheowkhy.supabase.co';
const supabasePublishableKey='sb_publishable_HIMGxb-O6fj9O7OzT4ukuQ_jm5W8mWz';
const bybit='https://api.bybit.com';

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
 static Future<dynamic> get(String path)async{
  final cl=HttpClient();
  try{
   final res=await cl.getUrl(Uri.parse(bybit+path)).then((x)=>x.close());
   final body=await res.transform(utf8.decoder).join();
   if(res.statusCode!=200)throw Exception('Bybit HTTP '+res.statusCode.toString());
   final data=jsonDecode(body);
   if(data is Map && data['retCode']!=0)throw Exception('Bybit API '+data['retCode'].toString()+': '+data['retMsg'].toString());
   return data is Map && data.containsKey('result') ? data['result'] : data;
  }finally{cl.close(force:true);}
 }
 static Future<Map<String,dynamic>> ticker(String s)=>get('/v5/market/tickers?category=spot&symbol='+s).then((x){
  final list=List<dynamic>.from((x as Map)['list'] as List);
  return list.isEmpty?<String,dynamic>{}:Map<String,dynamic>.from(list.first);
 });
 static Future<List<dynamic>> all()=>get('/v5/market/tickers?category=spot').then((x)=>List<dynamic>.from((x as Map)['list'] as List));
 static String change(Map<String,dynamic> x)=>x['price24hPcnt']?.toString()??'—';
}

class BybitSecure {
 static Future<dynamic> call(String action,{Map<String,dynamic> data=const{}}) async {
  final r=await supabase.functions.invoke('bybit',body:{'action':action,...data});
  final d=r.data;
  if(d is Map && d['error']!=null) throw Exception(d['error'].toString());
  return d;
 }
 static Future<void> connect(String key,String secret)=>call('connect',data:{'apiKey':key,'apiSecret':secret});
 static Future<Map<String,dynamic>> balance()=>call('balance').then((x)=>Map<String,dynamic>.from(x as Map));
 static Future<List<dynamic>> orders()=>call('orders').then((x)=>List<dynamic>.from((x as Map)['list'] as List));
 static Future<dynamic> order({required String symbol,required String side,required String type,required String qty,String? price})=>call('order',data:{'symbol':symbol,'side':side,'orderType':type,'qty':qty,if(price!=null)'price':price});
}
class BybitConnect extends StatefulWidget{const BybitConnect({super.key});State<BybitConnect>createState()=>_BybitConnectState();}
class _BybitConnectState extends State<BybitConnect>{
 final k=TextEditingController(),s=TextEditingController();bool busy=false;String msg='';
 Future<void> save() async {if(k.text.trim().isEmpty||s.text.trim().isEmpty){setState(()=>msg='Enter both your Bybit API key and API secret.');return;}setState(()=>busy=true);try{await BybitSecure.connect(k.text.trim(),s.text.trim());if(mounted)Navigator.pop(context,true);}catch(e){if(mounted)setState(()=>msg=e.toString().replaceFirst('Exception: ',''));}finally{if(mounted)setState(()=>busy=false);}}
 Widget build(BuildContext c)=>Scaffold(appBar:AppBar(title:const Text('Connect Bybit')),body:ListView(padding:const EdgeInsets.all(20),children:[const Text('Connect your Bybit account',style:TextStyle(fontSize:24,fontWeight:FontWeight.w800)),const SizedBox(height:8),const Text('Use a Bybit API key. The secret is sent to the secure backend and is not stored in the Flutter app.',style:TextStyle(color:Colors.white70)),const SizedBox(height:18),TextField(controller:k,decoration:const InputDecoration(labelText:'Bybit API key',border:OutlineInputBorder())),const SizedBox(height:12),TextField(controller:s,obscureText:true,decoration:const InputDecoration(labelText:'Bybit API secret',border:OutlineInputBorder())),const SizedBox(height:16),FilledButton(onPressed:busy?null:save,child:Text(busy?'Connecting…':'Connect account')),if(msg.isNotEmpty)Padding(padding:const EdgeInsets.only(top:12),child:Text(msg,style:const TextStyle(color:Colors.redAccent))) ]));
}
class BybitOrders extends StatefulWidget{const BybitOrders({super.key});State<BybitOrders>createState()=>_BybitOrdersState();}
class _BybitOrdersState extends State<BybitOrders> {
  List<dynamic> rows = [];
  bool loading = true;
  String msg = '';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      rows = await BybitSecure.orders();
      if (mounted) {
        setState(() { msg = ''; });
      }
    } catch (e) {
      if (mounted) {
        setState(() { msg = e.toString().replaceFirst('Exception: ', ''); });
      }
    } finally {
      if (mounted) {
        setState(() { loading = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Order history')),
      body: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (loading) const LinearProgressIndicator(),
            if (msg.isNotEmpty)
              Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(msg))),
            if (!loading && rows.isEmpty)
              const Card(
                child: ListTile(
                  title: Text('No orders'),
                  subtitle: Text('Your Bybit spot order history will appear here.'),
                ),
              ),
            ...rows.map((x) {
              final m = Map<String, dynamic>.from(x as Map);
              final details = (m['side'] ?? '').toString() + ' • ' +
                  (m['orderType'] ?? '').toString() + ' • ' +
                  (m['orderStatus'] ?? '').toString();
              return Card(
                child: ListTile(
                  title: Text((m['symbol'] ?? '—').toString()),
                  subtitle: Text(details),
                  trailing: Text(m['qty']?.toString() ?? '—'),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
class Home extends StatefulWidget{const Home({super.key});State<Home>createState()=>_HomeState();}
class _HomeState extends State<Home>{final sy=['BTCUSDT','ETHUSDT','BNBUSDT','SOLUSDT'];final d=<String,Map<String,dynamic>>{};Timer? timer;
 initState(){super.initState();load();timer=Timer.periodic(const Duration(seconds:8),(_)=>load());}
 Future<void>load()async{try{for(final s in sy)d[s]=await Api.ticker(s);if(mounted)setState((){});}catch(_){}}void dispose(){timer?.cancel();super.dispose();}
 Widget build(BuildContext c)=>SafeArea(child:RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.all(16),children:[
 Row(children:[const CircleAvatar(backgroundColor:Color(0xfff0b90b),child:Icon(Icons.currency_bitcoin,color:Colors.black)),const SizedBox(width:10),const Expanded(child:Text('Veylola',style:TextStyle(fontSize:23,fontWeight:FontWeight.w800))),IconButton(onPressed:()=>supabase.auth.signOut(),icon:const Icon(Icons.logout))]),
 const SizedBox(height:16),TextField(decoration:InputDecoration(hintText:'Search coins, pairs and features',prefixIcon:const Icon(Icons.search),filled:true,fillColor:const Color(0xff181a20),border:OutlineInputBorder(borderSide:BorderSide.none,borderRadius:BorderRadius.circular(14)))),
 const SizedBox(height:18),const Text('Estimated balance',style:TextStyle(color:Colors.white60)),const Text('10,000.00 USDT',style:TextStyle(fontSize:30,fontWeight:FontWeight.w800)),const Text('Paper account • real-money trading disabled',style:TextStyle(color:Colors.white54)),
 const SizedBox(height:18),Row(children:[Q(Icons.add,'Deposit'),Q(Icons.send,'Withdraw'),Q(Icons.swap_horiz,'Convert'),Q(Icons.qr_code,'Pay')]),const SizedBox(height:22),const Text('Markets',style:TextStyle(fontSize:20,fontWeight:FontWeight.w800)),const SizedBox(height:8),
 ...sy.map((s)=>Tile(symbol:s,price:d[s]?['lastPrice']?.toString()??'—',change:d[s]==null?'—':Api.change(d[s]!))),
 const SizedBox(height:10),Feature('Earn','Savings, staking and yield products',Icons.savings_outlined),Feature('P2P','Buy and sell with local payment methods',Icons.people_outline),Feature('Copy Trading','Track strategies and paper-test them',Icons.copy_all_outlined)
 ])));
}
class Q extends StatelessWidget{final IconData i;final String s;const Q(this.i,this.s,{super.key});Widget build(BuildContext c)=>Expanded(child:Column(children:[CircleAvatar(backgroundColor:const Color(0xff2b2f36),child:Icon(i)),const SizedBox(height:5),Text(s,style:const TextStyle(fontSize:11))]));}
class Tile extends StatelessWidget{final String symbol,price,change;const Tile({required this.symbol,required this.price,required this.change,super.key});Widget build(BuildContext c){final up=!change.startsWith('-');return Card(child:ListTile(leading:CircleAvatar(backgroundColor:const Color(0xff2b2f36),child:Text(symbol[0])),title:Text(symbol.replaceAll('USDT','/USDT'),style:const TextStyle(fontWeight:FontWeight.bold)),subtitle:const Text('24h'),trailing:Column(mainAxisAlignment:MainAxisAlignment.center,crossAxisAlignment:CrossAxisAlignment.end,children:[Text(price),Text(change=='—'?'—':change+'%',style:TextStyle(color:up?Colors.greenAccent:Colors.redAccent))])));}}
class Feature extends StatelessWidget{final String a,b;final IconData i;const Feature(this.a,this.b,this.i,{super.key});Widget build(BuildContext c)=>Card(child:ListTile(leading:CircleAvatar(backgroundColor:const Color(0xff2b2f36),child:Icon(i)),title:Text(a,style:const TextStyle(fontWeight:FontWeight.bold)),subtitle:Text(b),trailing:const Icon(Icons.chevron_right)));}

class Markets extends StatefulWidget{const Markets({super.key});State<Markets>createState()=>_MarketsState();}
class _MarketsState extends State<Markets>{List<dynamic> rows=[];String q='';bool loading=true;initState(){super.initState();load();}
 Future<void>load()async{try{final a=await Api.all();rows=a.where((x){final s=x['symbol'].toString();return s.endsWith('USDT')&&['BTC','ETH','BNB','SOL','XRP','DOGE','ADA','TRX','AVAX','LINK'].any((p)=>s.startsWith(p));}).toList();}catch(_){}if(mounted)setState(()=>loading=false);}
 Widget build(BuildContext c)=>SafeArea(child:RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.all(16),children:[const Text('Markets',style:TextStyle(fontSize:28,fontWeight:FontWeight.w800)),const SizedBox(height:12),TextField(onChanged:(x)=>setState(()=>q=x.toUpperCase()),decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'Search pair',border:OutlineInputBorder())),const SizedBox(height:12),const Row(children:[Expanded(child:Text('Favorites',textAlign:TextAlign.center)),Expanded(child:Text('Spot',textAlign:TextAlign.center)),Expanded(child:Text('Futures',textAlign:TextAlign.center)),Expanded(child:Text('New',textAlign:TextAlign.center))]),const SizedBox(height:10),if(loading)const LinearProgressIndicator(),...rows.where((x)=>x['symbol'].toString().contains(q)).map((x)=>Tile(symbol:x['symbol'].toString(),price:x['lastPrice'].toString(),change:Api.change(Map<String,dynamic>.from(x as Map))))])));}
class Trade extends StatefulWidget{const Trade({super.key});State<Trade>createState()=>_TradeState();}
class _TradeState extends State<Trade>{String s='BTCUSDT',side='BUY',type='LIMIT';Map<String,dynamic>? t;final p=TextEditingController(),a=TextEditingController();String msg='Paper trading mode';initState(){super.initState();load();}Future<void>load()async{try{t=await Api.ticker(s);if(mounted)setState((){});}catch(_){}}Widget build(BuildContext c)=>SafeArea(child:ListView(padding:const EdgeInsets.all(16),children:[
 Row(children:[const Text('Trade',style:TextStyle(fontSize:28,fontWeight:FontWeight.w800)),const Spacer(),DropdownButton<String>(value:s,items:const['BTCUSDT','ETHUSDT','BNBUSDT','SOLUSDT'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(x){if(x!=null){setState(()=>s=x);load();}})]),
 Card(child:ListTile(title:const Text('Last price'),trailing:Text(t?['lastPrice']?.toString()??'—',style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)))),const SizedBox(height:12),
 SegmentedButton<String>(segments:const[ButtonSegment(value:'BUY',label:Text('Buy')),ButtonSegment(value:'SELL',label:Text('Sell'))],selected:{side},onSelectionChanged:(x)=>setState(()=>side=x.first)),const SizedBox(height:12),
 DropdownButtonFormField<String>(value:type,decoration:const InputDecoration(labelText:'Order type',border:OutlineInputBorder()),items:const['LIMIT','MARKET','STOP-LIMIT'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(x){if(x!=null)setState(()=>type=x);}),const SizedBox(height:12),
 TextField(controller:p,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:type=='MARKET'?'Market price':'Price (USDT)',border:const OutlineInputBorder())),const SizedBox(height:12),
 TextField(controller:a,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Amount',border:OutlineInputBorder())),const SizedBox(height:16),
 FilledButton(onPressed:()async{if(a.text.trim().isEmpty){setState(()=>msg='Enter an amount.');return;}try{await BybitSecure.order(symbol:s,side:side,type:type=='LIMIT'?'LIMIT':'MARKET',qty:a.text.trim(),price:type=='LIMIT'?p.text.trim():null);setState(()=>msg='Bybit '+side+' order submitted.');}catch(e){setState(()=>msg='Order failed: '+e.toString().replaceFirst('Exception: ',''));}},child:Text('Place '+side+' order')),const SizedBox(height:12),Card(child:Padding(padding:const EdgeInsets.all(14),child:Text(msg))),const SizedBox(height:18),const Text('Open orders',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const Card(child:ListTile(title:Text('No open orders'),subtitle:Text('Real execution is disabled')))
 ]));}

class Futures extends StatelessWidget {
  const Futures({super.key});

  @override
  Widget build(BuildContext c) => SafeArea(
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Futures', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        const Text('Perpetual futures workspace'),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('BTCUSDT Perpetual', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                const Text('1x leverage • USDT margin • Paper mode'),
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

class Assets extends StatefulWidget{const Assets({super.key});State<Assets>createState()=>_AssetsState();}
class _AssetsState extends State<Assets>{Map<String,dynamic>? data;bool loading=true;String msg='';initState(){super.initState();load();}Future<void>load()async{try{data=await BybitSecure.balance();if(mounted)setState(()=>msg='');}catch(e){if(mounted)setState(()=>msg=e.toString().replaceFirst('Exception: ',''));}finally{if(mounted)setState(()=>loading=false);}}Widget build(BuildContext c){final list=data==null?const[]:List<dynamic>.from(data!['list']??const[]);final account=list.isEmpty?null:Map<String,dynamic>.from(list.first as Map);final coins=account==null?const[]:List<dynamic>.from(account['coin']??const[]);final equity=account==null?'—':(account['totalEquity']?.toString()??'—');return SafeArea(child:RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.all(16),children:[const Text('Assets',style:TextStyle(fontSize:28,fontWeight:FontWeight.w800)),const SizedBox(height:8),const Text('Bybit Unified account',style:TextStyle(color:Colors.white60)),Text(equity,style:const TextStyle(fontSize:30,fontWeight:FontWeight.w800)),const SizedBox(height:14),Row(children:[Expanded(child:FilledButton(onPressed:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>const BybitConnect())).then((_){load();}),child:const Text('Connect / reconnect'))),const SizedBox(width:10),Expanded(child:OutlinedButton(onPressed:()=>Navigator.push(c,MaterialPageRoute(builder:(_)=>const BybitOrders())),child:const Text('Order history')))]),const SizedBox(height:12),if(msg.isNotEmpty)Card(child:Padding(padding:const EdgeInsets.all(14),child:Text(msg))),if(loading)const LinearProgressIndicator(),const SizedBox(height:12),const Text('Wallets',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const SizedBox(height:8),if(coins.isEmpty&&!loading)const Card(child:ListTile(title:Text('No wallet data'),subtitle:Text('Connect your Bybit account to load balances.'))),...coins.map((x){final m=Map<String,dynamic>.from(x as Map);return Bal(m['coin']?.toString()??'—',m['walletBalance']?.toString()??'0',m['usdValue']?.toString()??'0 USD');})])));}}

class Bal extends StatelessWidget{final String c,a,v;const Bal(this.c,this.a,this.v,{super.key});Widget build(BuildContext x)=>Card(child:ListTile(leading:CircleAvatar(backgroundColor:const Color(0xff2b2f36),child:Text(c[0])),title:Text(c,style:const TextStyle(fontWeight:FontWeight.bold)),subtitle:Text(v),trailing:Text(a)));}
