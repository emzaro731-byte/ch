import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const supabaseUrl = 'https://vihbsfrwnslnmheowkhy.supabase.co';
const supabasePublishableKey = 'sb_publishable_HIMGxb-O6fj9O7OzT4ukuQ_jm5W8mWz';
const bushaBaseUrl = 'https://api.busha.co';
const bushaPublicKey = 'pub_ECNKDDyz5oRdJxB8bfanV';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Object? initError;
  try {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabasePublishableKey,
    ).timeout(const Duration(seconds: 20));
  } catch (e) {
    initError = e;
  }
  runApp(Veylola(initError: initError));
}

final supabase = Supabase.instance.client;

class Veylola extends StatelessWidget {
  final Object? initError;
  const Veylola({super.key, this.initError});

  @override
  Widget build(BuildContext c) => MaterialApp(
        title: 'Veylola Trade',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true).copyWith(
          scaffoldBackgroundColor: const Color(0xff0b0e11),
          cardColor: const Color(0xff181a20),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xfff0b90b),
            brightness: Brightness.dark,
          ),
        ),
        home: initError == null
            ? const Gate()
            : StartupError(error: initError.toString()),
      );
}

class StartupError extends StatelessWidget {
  final String error;
  const StartupError({super.key, required this.error});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off, size: 64, color: Color(0xfff0b90b)),
                  const SizedBox(height: 16),
                  const Text('Connection problem',
                      style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  const Text(
                    'Veylola Trade could not connect to Supabase. Check your internet connection and try again.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: () => main(),
                    child: const Text('Retry connection'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    error.contains('SocketException') || error.contains('Failed host lookup')
                        ? 'DNS/network lookup failed.'
                        : 'Supabase initialization failed.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class Gate extends StatelessWidget {
  const Gate({super.key});

  @override
  Widget build(BuildContext c) => StreamBuilder<AuthState>(
        stream: supabase.auth.onAuthStateChange,
        builder: (_, s) {
          final session = s.data?.session ?? supabase.auth.currentSession;
          return session == null ? const Login() : const Exchange();
        },
      );
}

class Login extends StatefulWidget {
  const Login({super.key});
  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final e = TextEditingController();
  final p = TextEditingController();
  bool busy = false;
  String msg = '';

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
    setState(() {
      busy = true;
      msg = '';
    });
    try {
      if (create) {
        await supabase.auth.signUp(email: email, password: password)
            .timeout(const Duration(seconds: 20));
        if (mounted) {
          setState(() => msg = 'Account created. Check your email if confirmation is enabled.');
        }
      } else {
        await supabase.auth.signInWithPassword(email: email, password: password)
            .timeout(const Duration(seconds: 20));
      }
    } on TimeoutException {
      if (mounted) setState(() => msg = 'Connection timed out. Check your internet/DNS.');
    } on AuthException catch (x) {
      if (mounted) setState(() => msg = 'Authentication failed: ${x.message}');
    } catch (x) {
      if (mounted) setState(() => msg = 'Authentication failed: $x');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  children: [
                    const Icon(Icons.currency_bitcoin, size: 56, color: Color(0xfff0b90b)),
                    const SizedBox(height: 10),
                    const Text('Veylola Trade',
                        style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
                    const Text('Busha-powered crypto workspace'),
                    const SizedBox(height: 28),
                    TextField(
                      controller: e,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: p,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: busy ? null : () => go(false),
                      child: Text(busy ? 'Please wait…' : 'Sign in'),
                    ),
                    OutlinedButton(
                      onPressed: busy ? null : () => go(true),
                      child: const Text('Create account'),
                    ),
                    if (msg.isNotEmpty) Text(msg),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class Exchange extends StatefulWidget {
  const Exchange({super.key});
  @override
  State<Exchange> createState() => _ExchangeState();
}

class _ExchangeState extends State<Exchange> {
  int i = 0;
  final pages = const [Home(), Markets(), Trade(), Futures(), Assets()];

  @override
  Widget build(BuildContext c) => Scaffold(
        body: IndexedStack(index: i, children: pages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: i,
          onDestinationSelected: (x) => setState(() => i = x),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.show_chart), label: 'Markets'),
            NavigationDestination(icon: Icon(Icons.swap_horiz), label: 'Trade'),
            NavigationDestination(icon: Icon(Icons.candlestick_chart), label: 'Futures'),
            NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), label: 'Assets'),
          ],
        ),
      );
}

class Api {
  static Future<dynamic> get(String path) async {
    final cl = HttpClient();
    try {
      final res = await cl.getUrl(Uri.parse(bushaBaseUrl + path)).then((x) => x.close());
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) throw Exception('Busha HTTP ${res.statusCode}');
      final data = jsonDecode(body);
      if (data is Map && data['status'] == 'error') {
        throw Exception(data['message']?.toString() ?? 'Busha API error');
      }
      return data is Map && data.containsKey('data') ? data['data'] : data;
    } finally {
      cl.close(force: true);
    }
  }

  static Future<List<dynamic>> pairs() =>
      get('/v1/pairs').then((x) => List<dynamic>.from(x as List));

  static Future<Map<String, dynamic>> pair(String s) => pairs().then((list) {
        final hit = list.cast<dynamic>().firstWhere(
          (x) => x is Map && x['id'].toString().toUpperCase() == s.toUpperCase(),
          orElse: () => null,
        );
        return hit == null ? <String, dynamic>{} : Map<String, dynamic>.from(hit as Map);
      });

  static String change(Map<String, dynamic> x) {
    final buy = x['buy_price'] is Map ? x['buy_price']['amount']?.toString() : null;
    final sell = x['sell_price'] is Map ? x['sell_price']['amount']?.toString() : null;
    return buy != null && sell != null ? 'Buy $buy • Sell $sell' : '—';
  }
}

Future<void> openBushaRamp({
  required String side,
  String? cryptoAsset,
  String? fiatCurrency,
  String? cryptoAmount,
  String? fiatAmount,
}) async {
  final base = side == 'buy' ? 'https://buy.busha.io/' : 'https://sell.busha.io/';
  final params = <String, String>{
    'publicKey': bushaPublicKey,
    'side': side,
  };
  if (cryptoAsset != null && cryptoAsset.isNotEmpty) params['cryptoAsset'] = cryptoAsset;
  if (fiatCurrency != null && fiatCurrency.isNotEmpty) params['fiatCurrency'] = fiatCurrency;
  if (cryptoAmount != null && cryptoAmount.isNotEmpty) params['cryptoAmount'] = cryptoAmount;
  if (fiatAmount != null && fiatAmount.isNotEmpty) params['fiatAmount'] = fiatAmount;

  final uri = Uri.parse(base).replace(queryParameters: params);
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    throw Exception('Could not open Busha.');
  }
}

class BushaRampButton extends StatelessWidget {
  final String side;
  final String label;
  final IconData icon;
  const BushaRampButton(this.side, this.label, this.icon, {super.key});

  @override
  Widget build(BuildContext context) => Expanded(
        child: FilledButton.icon(
          onPressed: () async {
            try {
              await openBushaRamp(side: side, fiatCurrency: 'NGN');
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(e.toString())));
              }
            }
          },
          icon: Icon(icon),
          label: Text(label),
        ),
      );
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final sy = ['BTCUSDT', 'ETHUSDT', 'BTCNGN', 'ETHNGN'];
  final d = <String, Map<String, dynamic>>{};
  Timer? timer;

  @override
  void initState() {
    super.initState();
    load();
    timer = Timer.periodic(const Duration(seconds: 8), (_) => load());
  }

  Future<void> load() async {
    try {
      for (final s in sy) d[s] = await Api.pair(s);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => SafeArea(
        child: RefreshIndicator(
          onRefresh: load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: Color(0xfff0b90b),
                    child: Icon(Icons.currency_bitcoin, color: Colors.black),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Veylola', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    onPressed: () => supabase.auth.signOut(),
                    icon: const Icon(Icons.logout),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Busha Public Integration',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                      SizedBox(height: 6),
                      Text('Buy and sell crypto securely with Busha. Veylola uses only the Public API Key.'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  BushaRampButton('buy', 'Buy Crypto', Icons.add),
                  const SizedBox(width: 10),
                  BushaRampButton('sell', 'Sell Crypto', Icons.sell),
                ],
              ),
              const SizedBox(height: 22),
              const Text('Markets', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              ...sy.map((s) => Tile(
                    symbol: s,
                    price: d[s]?['buy_price']?['amount']?.toString() ?? '—',
                    change: d[s] == null ? '—' : Api.change(d[s]!),
                  )),
              const SizedBox(height: 10),
              Feature('Buy with NGN', 'Open Busha On-Ramp', Icons.account_balance),
              Feature('Sell to NGN', 'Open Busha Off-Ramp', Icons.payments_outlined),
              Feature('Security', 'No Secret API Key is stored in this app', Icons.lock_outline),
            ],
          ),
        ),
      );
}

class Tile extends StatelessWidget {
  final String symbol, price, change;
  const Tile({required this.symbol, required this.price, required this.change, super.key});

  @override
  Widget build(BuildContext c) {
    final up = !change.startsWith('-');
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xff2b2f36),
          child: Text(symbol[0]),
        ),
        title: Text(symbol.replaceAll('USDT', '/USDT'),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('Busha market'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(price),
            Text(change,
                style: TextStyle(color: up ? Colors.greenAccent : Colors.redAccent)),
          ],
        ),
      ),
    );
  }
}

class Markets extends StatefulWidget {
  const Markets({super.key});
  @override
  State<Markets> createState() => _MarketsState();
}

class _MarketsState extends State<Markets> {
  List<dynamic> rows = [];
  String q = '';
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final a = await Api.pairs();
      rows = a.where((x) {
        final s = x['id'].toString();
        return s.endsWith('USDT') || s.endsWith('NGN');
      }).toList();
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext c) => SafeArea(
        child: RefreshIndicator(
          onRefresh: load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Markets',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              TextField(
                onChanged: (x) => setState(() => q = x.toUpperCase()),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search pair',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              if (loading) const LinearProgressIndicator(),
              ...rows
                  .where((x) => x['id'].toString().contains(q))
                  .map((x) => Tile(
                        symbol: x['id'].toString(),
                        price: x['buy_price']?['amount']?.toString() ?? '—',
                        change: Api.change(Map<String, dynamic>.from(x as Map)),
                      )),
            ],
          ),
        ),
      );
}

class Trade extends StatefulWidget {
  const Trade({super.key});
  @override
  State<Trade> createState() => _TradeState();
}

class _TradeState extends State<Trade> {
  String asset = 'BTC';
  final amount = TextEditingController();

  @override
  Widget build(BuildContext c) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Trade',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            const Text('Busha On-Ramp / Off-Ramp'),
            const SizedBox(height: 18),
            DropdownButtonFormField<String>(
              value: asset,
              decoration: const InputDecoration(
                labelText: 'Crypto',
                border: OutlineInputBorder(),
              ),
              items: const ['BTC', 'ETH', 'USDT', 'USDC']
                  .map((x) => DropdownMenuItem(value: x, child: Text(x)))
                  .toList(),
              onChanged: (x) => setState(() => asset = x ?? 'BTC'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount in NGN',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () async {
                await openBushaRamp(
                  side: 'buy',
                  cryptoAsset: asset,
                  fiatCurrency: 'NGN',
                  fiatAmount: amount.text.trim(),
                );
              },
              icon: const Icon(Icons.shopping_cart),
              label: const Text('Buy with Busha'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                await openBushaRamp(
                  side: 'sell',
                  cryptoAsset: asset,
                  fiatCurrency: 'NGN',
                  cryptoAmount: amount.text.trim(),
                );
              },
              icon: const Icon(Icons.sell),
              label: const Text('Sell with Busha'),
            ),
            const SizedBox(height: 16),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Veylola does not collect or store a Busha Secret API Key. The Busha widget handles the secure transaction flow.',
                ),
              ),
            ),
          ],
        ),
      );
}

class Futures extends StatelessWidget {
  const Futures({super.key});

  @override
  Widget build(BuildContext c) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Futures',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            const Text('Busha Public-Key mode'),
            const SizedBox(height: 18),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text(
                  'Live futures orders are not available through Busha Public API Key integration. Use the Buy/Sell Busha widgets for supported transactions.',
                ),
              ),
            ),
            Feature('Markets', 'Live public market information', Icons.show_chart),
            Feature('Risk', 'No live leverage or margin controls', Icons.security),
          ],
        ),
      );
}

class Assets extends StatelessWidget {
  const Assets({super.key});

  @override
  Widget build(BuildContext c) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Assets',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Busha Public-Key Mode',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    Text(
                      'This version intentionally does not request your Busha Secret API Key. '
                      'Private account balances and privileged transfers are therefore not displayed here.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => openBushaRamp(side: 'buy', fiatCurrency: 'NGN'),
              icon: const Icon(Icons.add),
              label: const Text('Buy Crypto'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => openBushaRamp(side: 'sell', fiatCurrency: 'NGN'),
              icon: const Icon(Icons.sell),
              label: const Text('Sell Crypto'),
            ),
          ],
        ),
      );
}

class Feature extends StatelessWidget {
  final String a, b;
  final IconData i;
  const Feature(this.a, this.b, this.i, {super.key});

  @override
  Widget build(BuildContext c) => Card(
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: const Color(0xff2b2f36),
            child: Icon(i),
          ),
          title: Text(a, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(b),
          trailing: const Icon(Icons.chevron_right),
        ),
      );
}
