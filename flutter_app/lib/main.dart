import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const supabaseUrl = 'https://vihbsfrwnslnmheowkhy.supabase.co';
const supabasePublishableKey = 'sb_publishable_HIMGxb-O6fj9O7OzT4ukuQ_jm5W8mWz';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabasePublishableKey);
  runApp(const VeylolaTradeApp());
}
final supabase = Supabase.instance.client;

class VeylolaTradeApp extends StatelessWidget {
  const VeylolaTradeApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(
    title: 'Veylola Trade', debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true),
    home: const AuthGate(),
  );
}
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override Widget build(BuildContext context) => StreamBuilder<AuthState>(
    stream: supabase.auth.onAuthStateChange,
    builder: (_, s) => (s.data?.session ?? supabase.auth.currentSession) == null
      ? const LoginScreen() : const Dashboard(),
  );
}
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override State<LoginScreen> createState()=>_LoginScreenState();
}
class _LoginScreenState extends State<LoginScreen> {
  final email=TextEditingController(), password=TextEditingController();
  bool busy=false; String message='';
  Future<void> signIn() async {
    setState(()=>busy=true);
    try { await supabase.auth.signInWithPassword(email:email.text.trim(),password:password.text); }
    catch(e){if(mounted)setState(()=>message='Sign in failed: '+e.toString());}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> signUp() async {
    setState(()=>busy=true);
    try { await supabase.auth.signUp(email:email.text.trim(),password:password.text); if(mounted)setState(()=>message='Account created.');}
    catch(e){if(mounted)setState(()=>message='Sign up failed: '+e.toString());}
    finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext c)=>Scaffold(body:SafeArea(child:Center(child:SingleChildScrollView(
    padding:const EdgeInsets.all(24),child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:520),child:Column(
      crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        const Text('Veylola Trade',style:TextStyle(fontSize:36,fontWeight:FontWeight.bold)),
        const SizedBox(height:8),const Text('AI trading command center'),
        const SizedBox(height:32),
        TextField(controller:email,decoration:const InputDecoration(labelText:'Email',border:OutlineInputBorder())),
        const SizedBox(height:12),
        TextField(controller:password,obscureText:true,decoration:const InputDecoration(labelText:'Password',border:OutlineInputBorder())),
        const SizedBox(height:16),
        FilledButton(onPressed:busy?null:signIn,child:Text(busy?'Please wait…':'Sign in')),
        OutlinedButton(onPressed:busy?null:signUp,child:const Text('Create account')),
        if(message.isNotEmpty)Text(message)
      ],
    )),
  ))));
}
class Dashboard extends StatefulWidget {
  const Dashboard({super.key});
  @override State<Dashboard> createState()=>_DashboardState();
}
class _DashboardState extends State<Dashboard> {
  String symbol='BTCUSDT',mode='PAPER',action='HOLD',state='WAITING',reason='Waiting for bot analysis.',message='Connecting…';
  double confidence=0; double? price;
  @override void initState(){super.initState();loadStatus();}
  Future<void> loadStatus() async {
    final uid=supabase.auth.currentUser?.id;if(uid==null)return;
    try{
      final row=await supabase.from('trading_bot_status').select().eq('user_id',uid).maybeSingle();
      if(row!=null&&mounted)setState((){
        symbol=row['symbol']?.toString()??symbol;mode=row['mode']?.toString()??mode;
        action=row['action']?.toString()??action;state=row['state']?.toString()??state;
        reason=row['reason']?.toString()??reason;price=(row['price'] as num?)?.toDouble();
        confidence=(row['confidence'] as num?)?.toDouble()??0;message='Status synced';
      });
      else if(mounted)setState(()=>message='No bot status yet');
    }catch(_){if(mounted)setState(()=>message='Status sync waiting');}
  }
  @override Widget build(BuildContext c)=>Scaffold(
    appBar:AppBar(title:const Text('Veylola Trade'),actions:[IconButton(onPressed:()=>supabase.auth.signOut(),icon:const Icon(Icons.logout))]),
    body:RefreshIndicator(onRefresh:loadStatus,child:ListView(padding:const EdgeInsets.all(16),children:[
      Card(child:Padding(padding:const EdgeInsets.all(18),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
          Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('AI market status',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),Text(symbol)]),
          Text(action,style:const TextStyle(fontWeight:FontWeight.bold))
        ]),
        const SizedBox(height:12),
        Text('Mode: '+mode+'    State: '+state),
        Text('Price: '+(price==null?'—':price!.toStringAsFixed(4))),
        Text('Confidence: '+confidence.toStringAsFixed(0)+'%'),
        const SizedBox(height:8),Text(reason)
      ]))),
      const SizedBox(height:12),
      const Card(child:Padding(padding:EdgeInsets.all(18),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('Risk controls',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
        SizedBox(height:8),Text('AI confirmation: 75% minimum'),Text('Position limit: 5 USDT'),Text('Execution: practice / paper'),Text('No guaranteed profit')
      ]))),
      const SizedBox(height:12),
      Card(child:Padding(padding:const EdgeInsets.all(18),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('Security',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
        const SizedBox(height:8),const Text('✓ Supabase publishable key only'),const Text('✓ Trading secrets stay server-side'),const Text('✓ Real-money execution is disabled'),
        const SizedBox(height:10),Text(message)
      ])))
    ]))
  );
}
