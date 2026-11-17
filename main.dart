import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const brandGreen = Color(0xFF176B3A);
const brandGold = Color(0xFFD6A52D);
const tajirBackendConfigured = String.fromEnvironment('SUPABASE_URL') != '' && String.fromEnvironment('SUPABASE_ANON_KEY') != '';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const previewMode = bool.fromEnvironment('TAJIR_PREVIEW');
  const url = String.fromEnvironment('SUPABASE_URL');
  const anon = String.fromEnvironment('SUPABASE_ANON_KEY');
  if (previewMode && (url.isEmpty || anon.isEmpty)) {
    runApp(const TajirApp());
    return;
  }
  if (url.isEmpty || anon.isEmpty) {
    runApp(const SetupRequiredApp());
    return;
  }
  await Supabase.initialize(url: url, anonKey: anon);
  runApp(const TajirApp());
}

class SetupRequiredApp extends StatelessWidget {
  const SetupRequiredApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'TAJIR', theme: appTheme,
    home: const Scaffold(body: Center(child: Padding(
      padding: EdgeInsets.all(28),
      child: Text('TAJIR setup required\\n\\nBuild with SUPABASE_URL and SUPABASE_ANON_KEY. See README.md.',
        textAlign: TextAlign.center, style: TextStyle(fontSize: 18)),
    ))),
  );
}

final appTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: brandGreen, primary: brandGreen, secondary: brandGold),
  scaffoldBackgroundColor: const Color(0xFFF6F8F5),
  appBarTheme: const AppBarTheme(backgroundColor: brandGreen, foregroundColor: Colors.white),
  useMaterial3: true,
);

class TajirApp extends StatelessWidget {
  const TajirApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'TAJIR', debugShowCheckedModeBanner: false, theme: appTheme,
    home: const AuthGate(),
  );
}


class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  static const previewMode =
      bool.fromEnvironment('TAJIR_PREVIEW');

  @override
  Widget build(BuildContext context) {
    if (previewMode) {
      return const DemoLoginPage();
    }

    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (Supabase.instance.client.auth.currentSession == null) {
          return const LoginPage();
        }
        return const AccountRouter();
      },
    );
  }
}


class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override State<LoginPage> createState() => _LoginPageState();
}

String staffAuthPassword(String pin) => 'TAJIR-PIN-$pin-Account#2026';
String tajirLoginEmail(String phone) => 'u${phone.replaceAll(RegExp(r'[^0-9]'), '')}@login.tajir.app';

class _LoginPageState extends State<LoginPage> {
  final phone = TextEditingController();
  final pin = TextEditingController();
  final confirmPin = TextEditingController();
  bool busy = false, setupDirector = false;
  String? error;

  @override
  void dispose() {
    phone.dispose();
    pin.dispose();
    confirmPin.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() { busy = true; error = null; });
    try {
      final db = Supabase.instance.client;
      {
        final normalized = normalizeKenyanPhone(phone.text);
        if (!RegExp(r'^\d{4}$').hasMatch(pin.text)) {
          throw const FormatException('Enter a four-digit PIN.');
        }
        if (setupDirector) {
          if (pin.text != confirmPin.text) {
            throw const FormatException('The PIN entries do not match.');
          }
          final response = await db.functions.invoke(
            'tajir-director-setup',
            body: {'phone': phone.text.trim(), 'pin': pin.text},
          );
          if (response.status != 200) {
            final data = response.data;
            throw FormatException(data is Map ? (data['error']?.toString() ?? 'Director setup failed.') : 'Director setup failed.');
          }
        }
        await db.auth.signInWithPassword(
          email: tajirLoginEmail(normalized),
          password: staffAuthPassword(pin.text),
        );
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => error = e.message);
    } on FunctionException catch (e) {
      final details = e.details;
      if (mounted) setState(() => error = details is Map ? (details['error']?.toString() ?? e.reasonPhrase ?? 'Director setup failed.') : (e.reasonPhrase ?? 'Director setup failed.'));
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('FormatException: ', ''));
    }
    if (mounted) setState(() => busy = false);
  }

  @override Widget build(BuildContext context) => Scaffold(
    body: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420),
        child: Card(child: Padding(padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const BrandMark(),
            const SizedBox(height: 24),
            Text(setupDirector ? 'Set up director access' : 'Sign in to TAJIR',
              style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 18),
            TextField(controller: phone, keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Director phone number', hintText: '0700020140', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: pin, keyboardType: TextInputType.number, obscureText: true, maxLength: 4,
                decoration: const InputDecoration(labelText: 'Four-digit PIN', border: OutlineInputBorder(), counterText: '')),
              if (setupDirector) ...[
                const SizedBox(height: 12),
                TextField(controller: confirmPin, keyboardType: TextInputType.number, obscureText: true, maxLength: 4,
                  decoration: const InputDecoration(labelText: 'Confirm four-digit PIN', border: OutlineInputBorder(), counterText: '')),
              ],
              const SizedBox(height: 6),
              Text(setupDirector
                ? 'One-time setup for the pre-approved TAJIR Director account. No OTP or email confirmation is needed.'
                : 'Sign in with your registered phone number and director PIN.',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.black54)),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 12),
              child: Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red))),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: FilledButton(
              onPressed: busy ? null : submit,
              child: Text(busy ? 'Please wait…' : setupDirector ? 'Set up and sign in' : 'Sign in'),
            )),
            TextButton(onPressed: busy ? null : () => setState(() { setupDirector = !setupDirector; error = null; }),
              child: Text(setupDirector ? 'I already set up my PIN — sign in' : 'First time? Set up director PIN')),
            TextButton(onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CustomerAuthPage())),
              child: const Text('Customer? Register or sign in with phone number')),
          ]),
        )),
      ),
    )),
  );
}

String normalizeKenyanPhone(String input) {
  var digits = input.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length == 10 && digits.startsWith('0')) digits = '254' + digits.substring(1);
  if (digits.length == 12 && digits.startsWith('254')) return '+' + digits;
  throw const FormatException('Enter a valid Kenyan phone number, e.g. 0712345678.');
}

class CustomerAuthPage extends StatefulWidget {
  const CustomerAuthPage({super.key});
  @override State<CustomerAuthPage> createState() => _CustomerAuthPageState();
}
class _CustomerAuthPageState extends State<CustomerAuthPage> {
  final name = TextEditingController();
  final phone = TextEditingController();
  final pin = TextEditingController();
  final confirmPin = TextEditingController();
  bool createAccount = true, busy = false;
  String? message;
  @override void dispose() {
    name.dispose(); phone.dispose(); pin.dispose(); confirmPin.dispose(); super.dispose();
  }

  Future<void> submit() async {
    setState(() { busy = true; message = null; });
    try {
      final db = Supabase.instance.client;
      final normalized = normalizeKenyanPhone(phone.text);
      if (pin.text.length != 6 || int.tryParse(pin.text) == null) {
        throw const FormatException('PIN must contain exactly six digits.');
      }
      if (createAccount) {
        if (name.text.trim().length < 2) throw const FormatException('Enter your full name.');
        if (pin.text != confirmPin.text) throw const FormatException('The PIN entries do not match.');
        final response = await db.functions.invoke(
          'tajir-customer-register',
          body: {'full_name': name.text.trim(), 'phone': normalized, 'pin': pin.text},
        );
        final resultData = response.data;
        if (response.status != 200 || resultData is! Map || resultData['success'] != true) {
          final data = resultData;
          throw FormatException(data is Map ? (data['error']?.toString() ?? 'Customer registration failed.') : 'Customer registration failed.');
        }
        await db.auth.signInWithPassword(email: tajirLoginEmail(normalized), password: pin.text);
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const CustomerPendingPage()), (route) => false);
      } else {
        await db.auth.signInWithPassword(email: tajirLoginEmail(normalized), password: pin.text);
        final result = await db.rpc('get_my_account_status');
        final rows = List<Map<String,dynamic>>.from(result);
        if (rows.isEmpty || rows.first['is_customer'] != true) {
          throw const FormatException('No customer account is linked to this phone number. Please register first.');
        }
        final row = rows.first;
        if (!mounted) return;
        if (row['account_status'] == 'active' && row['customer_active'] == true) {
          Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const CustomerPortalPage()), (route) => false);
        } else {
          Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const CustomerPendingPage()), (route) => false);
        }
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => message = e.message);
    } catch (e) {
      if (mounted) setState(() => message = e.toString().replaceFirst('FormatException: ', ''));
    }
    if (mounted) setState(() => busy = false);
  }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('TAJIR customer account')),
    body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(20),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440),
        child: Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(
          mainAxisSize: MainAxisSize.min, children: [
            const BrandMark(), const SizedBox(height: 18),
            Text(createAccount ? 'Create customer account' : 'Customer sign in',
              style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('No OTP or SMS is used. Your phone number is not verified.', textAlign: TextAlign.center,
              style: TextStyle(color: Colors.deepOrange, fontSize: 12)),
            const SizedBox(height: 16),
            if (createAccount) TextField(controller: name, textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Full name', border: OutlineInputBorder())),
            if (createAccount) const SizedBox(height: 12),
            TextField(controller: phone, keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone number', hintText: '07XXXXXXXX', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: pin, keyboardType: TextInputType.number, obscureText: true, maxLength: 6,
              decoration: const InputDecoration(labelText: 'Six-digit PIN', border: OutlineInputBorder(), counterText: '')),
            if (createAccount) const SizedBox(height: 12),
            if (createAccount) TextField(controller: confirmPin, keyboardType: TextInputType.number, obscureText: true, maxLength: 6,
              decoration: const InputDecoration(labelText: 'Confirm six-digit PIN', border: OutlineInputBorder(), counterText: '')),
            if (message != null) Padding(padding: const EdgeInsets.only(top: 12),
              child: Text(message!, style: const TextStyle(color: Colors.red))),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: FilledButton(onPressed: busy ? null : submit,
              child: Text(busy ? 'Please wait…' : createAccount ? 'Create account' : 'Sign in'))),
            TextButton(onPressed: busy ? null : () => setState(() { createAccount = !createAccount; message = null; }),
              child: Text(createAccount ? 'Already registered? Sign in' : 'New customer? Register')),
          ],
        ))),
      )),
    ),
  );
}

class CustomerPendingPage extends StatelessWidget {
  const CustomerPendingPage({super.key});
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('TAJIR account approval')),
    body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
      mainAxisSize: MainAxisSize.min, children: const [
        Icon(Icons.hourglass_top, size: 64, color: brandGold),
        SizedBox(height: 16),
        Text('Registration received', style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
        SizedBox(height: 10),
        Text('Your customer account is waiting for approval by TAJIR staff. You can sign in again after your account is activated.', textAlign: TextAlign.center),
      ],
    ))),
  );
}

class CustomerPortalPage extends StatelessWidget {
  const CustomerPortalPage({super.key});
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('TAJIR customer')),
    body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
      mainAxisSize: MainAxisSize.min, children: [
        const BrandMark(), const SizedBox(height: 18),
        const Text('Your customer account is active.', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        const Text('Customer orders and account history will appear here as those features are connected.'),
        const SizedBox(height: 16),
        FilledButton(onPressed: () => Supabase.instance.client.auth.signOut(), child: const Text('Sign out')),
      ],
    ))),
  );
}

class AccountRouter extends StatelessWidget {
  const AccountRouter({super.key});
  @override Widget build(BuildContext context) => FutureBuilder<dynamic>(
    future: Supabase.instance.client.rpc('get_my_account_status'),
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) return const Scaffold(body: Center(child: CircularProgressIndicator()));
      if (snapshot.hasError) return const HomeShell();
      final rows = List<Map<String,dynamic>>.from(snapshot.data ?? const []);
      if (rows.isNotEmpty && rows.first['is_customer'] == true) {
        final row = rows.first;
        if (row['account_status'] == 'active' && row['customer_active'] == true) return const CustomerPortalPage();
        return const CustomerPendingPage();
      }
      return const HomeShell();
    },
  );
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key});
  @override Widget build(BuildContext context) => Column(children: [
    Container(width: 64, height: 64, decoration: BoxDecoration(color: brandGreen, borderRadius: BorderRadius.circular(18)),
      child: const Icon(Icons.agriculture, color: brandGold, size: 38)),
    const SizedBox(height: 8),
    const Text('TAJIR', style: TextStyle(fontSize: 30, letterSpacing: 4, fontWeight: FontWeight.w900, color: brandGreen)),
    const Text('GROWING TRADE, CONNECTING FARMERS', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, letterSpacing: 1.1)),
  ]);
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override State<HomeShell> createState() => _HomeShellState();
}
class _HomeShellState extends State<HomeShell> {
  int index = 0;
  final pages = const [DashboardPage(), PurchasePage(), SalePage(), StockPage(), CustomersPage(), TractorServicesPage()];
  final labels = const ['Dashboard','Purchases','Sales','Stock','Customers','Tractor Services'];
  final icons = const [Icons.dashboard, Icons.add_shopping_cart, Icons.point_of_sale, Icons.inventory_2, Icons.people, Icons.agriculture];
  @override Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 800;
    return Scaffold(
      appBar: AppBar(title: const Text('TAJIR'), actions: [
        IconButton(tooltip: 'Sign out', onPressed: () => Supabase.instance.client.auth.signOut(), icon: const Icon(Icons.logout))
      ]),
      body: Row(children: [
        if (wide) NavigationRail(
          selectedIndex: index, onDestinationSelected: (v) => setState(() => index = v),
          labelType: NavigationRailLabelType.all,
          destinations: List.generate(labels.length, (i) => NavigationRailDestination(icon: Icon(icons[i]), label: Text(labels[i]))),
        ),
        Expanded(child: IndexedStack(index: index, children: pages)),
      ]),
      bottomNavigationBar: wide ? null : NavigationBar(selectedIndex: index, onDestinationSelected: (v) => setState(() => index = v),
        destinations: List.generate(labels.length, (i) => NavigationDestination(icon: Icon(icons[i]), label: labels[i]))),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override State<DashboardPage> createState() => _DashboardPageState();
}
class _DashboardPageState extends State<DashboardPage> {
  String role = 'Loading role…'; List<Map<String,dynamic>> stock = []; String? error;
  @override void initState() { super.initState(); load(); }
  Future<void> load() async {
    try {
      final db = Supabase.instance.client;
      final p = await db.from('profiles').select('full_name,role').eq('id', db.auth.currentUser!.id).single();
      final s = await db.rpc('get_stock_balances');
      setState(() { role = '${p['full_name']} • ${p['role']}'; stock = List<Map<String,dynamic>>.from(s); });
    } catch(e) { setState(() => error = e.toString()); }
  }
  @override Widget build(BuildContext context) => RefreshIndicator(onRefresh: load, child: ListView(padding: const EdgeInsets.all(18), children: [
    const Text('Business overview', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
    Text(role, style: const TextStyle(color: Colors.black54)),
    const SizedBox(height: 18),
    const Wrap(spacing: 12, runSpacing: 12, children: [
      MetricCard(title: 'Location', value: 'Ntulele', icon: Icons.location_on),
      MetricCard(title: 'Products', value: 'Maize, Beans & Fertilizer', icon: Icons.grain),
      MetricCard(title: 'Payments', value: 'M-Pesa • Cash • Bank • Credit', icon: Icons.payments),
    ]),
    const SizedBox(height: 24),
    const Text('Current stock', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
    if (stock.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No stock balance available yet. Pull down to refresh.')),
    ...stock.map((r) => Card(child: ListTile(leading: const Icon(Icons.inventory), title: Text('${r['product_name'] ?? r['name'] ?? 'Product'}'), trailing: Text('${r['quantity_available'] ?? ''} ${r['unit'] ?? ''}')))),
    const SizedBox(height: 16),
    const Text('Quick guide', style: TextStyle(fontWeight: FontWeight.bold)),
    const Text('Record each delivery as a purchase. Record customer orders as sales. Stock is reduced automatically using FIFO batches. Financial details are restricted by the signed-in user role.'),
  ]));
}
class MetricCard extends StatelessWidget {
  final String title, value; final IconData icon;
  const MetricCard({super.key, required this.title, required this.value, required this.icon});
  @override Widget build(BuildContext context) => SizedBox(width: 250, child: Card(child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
    Icon(icon, color: brandGreen, size: 30), const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: Colors.black54)), Text(value, style: const TextStyle(fontWeight: FontWeight.bold))])),
  ]))));
}

class PurchasePage extends StatefulWidget {
  const PurchasePage({super.key});
  @override
  State<PurchasePage> createState() => _PurchasePageState();
}

class _PurchasePageState extends State<PurchasePage> {
  final qty = TextEditingController();
  final cost = TextEditingController();
  final supplier = TextEditingController();
  final notes = TextEditingController();

  String product = 'Maize';
  String payer = 'Mercy';
  String? productId;
  String? selectedVariantId;
  List<Map<String, dynamic>> variants = [];
  bool busy = false;
  bool loadingVariants = false;
  String message = '';

  @override
  void initState() {
    super.initState();
    loadProductVariants();
  }

  @override
  void dispose() {
    qty.dispose();
    cost.dispose();
    supplier.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> loadProductVariants() async {
    setState(() {
      loadingVariants = true;
      variants = [];
      selectedVariantId = null;
      productId = null;
      message = '';
    });
    try {
      final db = Supabase.instance.client;
      final category = await db
          .from('product_categories')
          .select('id')
          .eq('code', product.toLowerCase())
          .single();
      final products = await db
          .from('products')
          .select('id,name')
          .eq('category_id', category['id'])
          .eq('is_active', true);
      final productRows = List<Map<String, dynamic>>.from(products);
      if (productRows.isEmpty) throw Exception('No active product is configured for ' + product + '.');
      final row = productRows.firstWhere(
        (item) => item['name'] == product,
        orElse: () => productRows.first,
      );
      final loaded = await db
          .from('product_variants')
          .select('id,variant_name,base_unit')
          .eq('product_id', row['id'])
          .eq('is_active', true)
          .order('variant_name');
      final loadedRows = List<Map<String, dynamic>>.from(loaded);
      if (!mounted) return;
      setState(() {
        productId = row['id'] as String;
        variants = loadedRows;
        selectedVariantId = loadedRows.isNotEmpty ? loadedRows.first['id'] as String : null;
        if (loadedRows.isEmpty) message = 'No active stock option is configured for ' + product + '.';
      });
    } catch (e) {
      if (mounted) setState(() => message = 'Could not load ' + product + ' options: ' + e.toString());
    } finally {
      if (mounted) setState(() => loadingVariants = false);
    }
  }

  Future<void> addVariant() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(product == 'Beans' ? 'Add bean variety' : 'Add fertilizer type'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: product == 'Beans' ? 'Variety name' : 'Fertilizer type',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Add')),
        ],
      ),
    );
    controller.dispose();
    final cleanName = name?.trim() ?? '';
    if (cleanName.isEmpty || productId == null) return;
    try {
      final inserted = await Supabase.instance.client
          .from('product_variants')
          .insert({
            'product_id': productId,
            'variant_name': cleanName,
            'grade_or_formulation': product == 'Fertilizer' ? cleanName : null,
            'base_unit': 'bag',
            'is_active': true,
          })
          .select('id,variant_name,base_unit')
          .single();
      if (!mounted) return;
      setState(() {
        variants.add(Map<String, dynamic>.from(inserted));
        variants.sort((a, b) => (a['variant_name'] as String).compareTo(b['variant_name'] as String));
        selectedVariantId = inserted['id'] as String;
        message = 'Added ' + cleanName + '.';
      });
    } catch (e) {
      if (mounted) setState(() => message = 'Could not add this option. Only an authorised director can add product varieties/types. ' + e.toString());
    }
  }

  Future<void> save() async {
    final q = double.tryParse(qty.text);
    final c = double.tryParse(cost.text);
    if (q == null || c == null || q <= 0 || c < 0 || selectedVariantId == null) {
      setState(() => message = 'Choose a product option and enter a valid quantity and buying price.');
      return;
    }
    setState(() { busy = true; message = ''; });
    try {
      final db = Supabase.instance.client;
      final branch = await db.from('branches').select('id').eq('code', 'NTULELE').single();
      await db.rpc('record_purchase', params: {
        'p_payload': {
          'branch_id': branch['id'],
          'purchase_date': DateTime.now().toIso8601String().substring(0, 10),
          'payer': payer,
          'notes': notes.text,
          'items': [
            {
              'product_variant_id': selectedVariantId,
              'quantity': q,
              'unit_cost': c,
            }
          ],
        }
      });
      setState(() => message = 'Purchase saved. Stock is awaiting quality approval.');
      qty.clear();
      cost.clear();
      supplier.clear();
      notes.clear();
    } catch (e) {
      setState(() => message = 'Could not save purchase: ' + e.toString());
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => FormPage(
    title: 'Record purchase',
    children: [
      DropdownButtonFormField<String>(
        value: product,
        items: const ['Maize', 'Beans', 'Fertilizer']
            .map((x) => DropdownMenuItem(value: x, child: Text(x)))
            .toList(),
        onChanged: (v) {
          if (v == null) return;
          setState(() => product = v);
          loadProductVariants();
        },
        decoration: const InputDecoration(labelText: 'Product'),
      ),
      if (loadingVariants) const LinearProgressIndicator(),
      if (product != 'Maize') ...[
        DropdownButtonFormField<String>(
          value: variants.any((v) => v['id'] == selectedVariantId) ? selectedVariantId : null,
          items: variants.map((v) => DropdownMenuItem<String>(
            value: v['id'] as String,
            child: Text(v['variant_name'] as String),
          )).toList(),
          onChanged: (v) => setState(() => selectedVariantId = v),
          decoration: InputDecoration(labelText: product == 'Beans' ? 'Bean variety' : 'Fertilizer type'),
        ),
        TextButton.icon(
          onPressed: loadingVariants ? null : addVariant,
          icon: const Icon(Icons.add),
          label: Text(product == 'Beans' ? 'Add bean variety' : 'Add fertilizer type'),
        ),
      ],
      field(qty, 'Quantity (bags)', number: true),
      field(cost, 'Buying price per bag (KES)', number: true),
      field(supplier, 'Supplier name'),
      DropdownButtonFormField<String>(
        value: payer,
        items: const ['Mercy', 'Edu']
            .map((x) => DropdownMenuItem(value: x, child: Text(x)))
            .toList(),
        onChanged: (v) => setState(() => payer = v ?? 'Mercy'),
        decoration: const InputDecoration(labelText: 'Paid by'),
      ),
      field(notes, 'Notes / extra details'),
      actionButton('Save purchase', busy || loadingVariants, save),
      if (message.isNotEmpty) Text(message),
      const Text(
        'Maize has no variety. Beans and fertilizer use their own saved variety/type options.',
        style: TextStyle(fontSize: 12, color: Colors.black54),
      ),
    ],
  );
}

class SalePage extends StatefulWidget {
  const SalePage({super.key});
  @override
  State<SalePage> createState() => _SalePageState();
}

class _SalePageState extends State<SalePage> {
  final qty = TextEditingController();
  final price = TextEditingController();
  final address = TextEditingController();
  final fee = TextEditingController();
  final customer = TextEditingController();
  final customerPhone = TextEditingController();
  final paid = TextEditingController();
  final reference = TextEditingController();

  String product = 'Maize';
  String mode = 'collection';
  String method = 'cash';
  String? productId;
  String? selectedVariantId;
  List<Map<String, dynamic>> variants = [];
  bool busy = false;
  bool loadingVariants = false;
  String message = '';

  @override
  void initState() {
    super.initState();
    loadProductVariants();
  }

  @override
  void dispose() {
    qty.dispose();
    price.dispose();
    address.dispose();
    fee.dispose();
    customer.dispose();
    customerPhone.dispose();
    paid.dispose();
    reference.dispose();
    super.dispose();
  }

  Future<void> loadProductVariants() async {
    setState(() {
      loadingVariants = true;
      variants = [];
      selectedVariantId = null;
      productId = null;
      message = '';
    });
    try {
      final db = Supabase.instance.client;
      final category = await db
          .from('product_categories')
          .select('id')
          .eq('code', product.toLowerCase())
          .single();
      final products = await db
          .from('products')
          .select('id,name')
          .eq('category_id', category['id'])
          .eq('is_active', true);
      final productRows = List<Map<String, dynamic>>.from(products);
      if (productRows.isEmpty) throw Exception('No active product is configured for ' + product + '.');
      final row = productRows.firstWhere(
        (item) => item['name'] == product,
        orElse: () => productRows.first,
      );
      final loaded = await db
          .from('product_variants')
          .select('id,variant_name,base_unit')
          .eq('product_id', row['id'])
          .eq('is_active', true)
          .order('variant_name');
      final loadedRows = List<Map<String, dynamic>>.from(loaded);
      if (!mounted) return;
      setState(() {
        productId = row['id'] as String;
        variants = loadedRows;
        selectedVariantId = loadedRows.isNotEmpty ? loadedRows.first['id'] as String : null;
        if (loadedRows.isEmpty) message = 'No active stock option is configured for ' + product + '.';
      });
    } catch (e) {
      if (mounted) setState(() => message = 'Could not load ' + product + ' options: ' + e.toString());
    } finally {
      if (mounted) setState(() => loadingVariants = false);
    }
  }

  Future<void> addVariant() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(product == 'Beans' ? 'Add bean variety' : 'Add fertilizer type'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: product == 'Beans' ? 'Variety name' : 'Fertilizer type',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Add')),
        ],
      ),
    );
    controller.dispose();
    final cleanName = name?.trim() ?? '';
    if (cleanName.isEmpty || productId == null) return;
    try {
      final inserted = await Supabase.instance.client
          .from('product_variants')
          .insert({
            'product_id': productId,
            'variant_name': cleanName,
            'grade_or_formulation': product == 'Fertilizer' ? cleanName : null,
            'base_unit': 'bag',
            'is_active': true,
          })
          .select('id,variant_name,base_unit')
          .single();
      if (!mounted) return;
      setState(() {
        variants.add(Map<String, dynamic>.from(inserted));
        variants.sort((a, b) => (a['variant_name'] as String).compareTo(b['variant_name'] as String));
        selectedVariantId = inserted['id'] as String;
        message = 'Added ' + cleanName + '.';
      });
    } catch (e) {
      if (mounted) setState(() => message = 'Could not add this option. Only an authorised director can add product varieties/types. ' + e.toString());
    }
  }

  Future<void> save() async {
    final q = double.tryParse(qty.text);
    final p = double.tryParse(price.text);
    final amount = double.tryParse(paid.text) ?? 0;
    final deliveryFee = double.tryParse(fee.text) ?? 0;
    if (q == null || p == null || q <= 0 || p < 0 || selectedVariantId == null ||
        customer.text.trim().isEmpty ||
        (mode == 'delivery' && address.text.trim().isEmpty)) {
      setState(() => message = 'Choose a product option and check the customer name, quantity, selling price and delivery address.');
      return;
    }
    setState(() { busy = true; message = ''; });
    try {
      final db = Supabase.instance.client;
      final branch = await db.from('branches').select('id').eq('code', 'NTULELE').single();
      String? customerId;
      final matches = await db
          .from('customers')
          .select('id')
          .ilike('full_name', customer.text.trim())
          .limit(1);
      if (matches.isNotEmpty) customerId = matches.first['id'] as String;
      if (customerId == null && customerPhone.text.trim().isEmpty) {
        throw Exception('Enter the customer phone number for a new customer.');
      }
      final payload = <String, dynamic>{
        'branch_id': branch['id'],
        'customer_id': customerId,
        'customer_name': customer.text.trim(),
        'customer_phone': customerPhone.text.trim(),
        'sale_date': DateTime.now().toIso8601String().substring(0, 10),
        'fulfilment_mode': mode,
        'delivery_address': address.text,
        'delivery_fee': deliveryFee,
        'items': [
          {
            'product_variant_id': selectedVariantId,
            'quantity': q,
            'unit_price': p,
          }
        ],
      };
      if (amount > 0) payload['payment'] = {'amount': amount, 'method': method, 'reference': reference.text};
      final result = await db.rpc('record_sale', params: {'p_payload': payload});
      setState(() => message = 'Sale saved. Reference: ' + result['sale_id'].toString() + '. Balance: KES ' + result['balance'].toString());
      qty.clear();
      price.clear();
      paid.clear();
      reference.clear();
    } catch (e) {
      setState(() => message = 'Could not save sale: ' + e.toString());
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => FormPage(
    title: 'Record sale / customer order',
    children: [
      DropdownButtonFormField<String>(
        value: product,
        items: const ['Maize', 'Beans', 'Fertilizer']
            .map((x) => DropdownMenuItem(value: x, child: Text(x)))
            .toList(),
        onChanged: (v) {
          if (v == null) return;
          setState(() => product = v);
          loadProductVariants();
        },
        decoration: const InputDecoration(labelText: 'Product'),
      ),
      if (loadingVariants) const LinearProgressIndicator(),
      if (product != 'Maize') ...[
        DropdownButtonFormField<String>(
          value: variants.any((v) => v['id'] == selectedVariantId) ? selectedVariantId : null,
          items: variants.map((v) => DropdownMenuItem<String>(
            value: v['id'] as String,
            child: Text(v['variant_name'] as String),
          )).toList(),
          onChanged: (v) => setState(() => selectedVariantId = v),
          decoration: InputDecoration(labelText: product == 'Beans' ? 'Bean variety' : 'Fertilizer type'),
        ),
        TextButton.icon(
          onPressed: loadingVariants ? null : addVariant,
          icon: const Icon(Icons.add),
          label: Text(product == 'Beans' ? 'Add bean variety' : 'Add fertilizer type'),
        ),
      ],
      field(qty, 'Quantity (bags)', number: true),
      field(price, 'Selling price per bag (KES)', number: true),
      field(customer, 'Customer name'),
      field(customerPhone, 'Customer phone (required for a new customer)'),
      DropdownButtonFormField<String>(
        value: mode,
        items: const [
          DropdownMenuItem(value: 'collection', child: Text('Collect at Ntulele')),
          DropdownMenuItem(value: 'delivery', child: Text('Deliver to customer')),
        ],
        onChanged: (v) => setState(() => mode = v ?? 'collection'),
        decoration: const InputDecoration(labelText: 'Fulfilment'),
      ),
      if (mode == 'delivery') field(address, 'Delivery address'),
      if (mode == 'delivery') field(fee, 'Delivery fee (KES)', number: true),
      const Divider(),
      const Text('Payment (optional)', style: TextStyle(fontWeight: FontWeight.bold)),
      field(paid, 'Amount received (KES)', number: true),
      DropdownButtonFormField<String>(
        value: method,
        items: const [
          DropdownMenuItem(value: 'mpesa', child: Text('M-Pesa')),
          DropdownMenuItem(value: 'cash', child: Text('Cash')),
          DropdownMenuItem(value: 'bank_transfer', child: Text('Bank transfer')),
          DropdownMenuItem(value: 'other', child: Text('Other')),
        ],
        onChanged: (v) => setState(() => method = v ?? 'cash'),
        decoration: const InputDecoration(labelText: 'Payment method'),
      ),
      field(reference, 'Payment reference'),
      actionButton('Save sale', busy || loadingVariants, save),
      if (message.isNotEmpty) Text(message),
      const Text(
        'Maize has no variety. Beans and fertilizer use their own saved variety/type options.',
        style: TextStyle(fontSize: 12, color: Colors.black54),
      ),
    ],
  );
}

class StockPage extends StatefulWidget {const StockPage({super.key});@override State<StockPage> createState()=>_StockPageState();}
class _StockPageState extends State<StockPage>{
  List<dynamic> products=[];String message='';
  Future<void> load()async{try{final r=await Supabase.instance.client.rpc('get_stock_balances');setState(()=>products=List<dynamic>.from(r));}catch(e){setState(()=>message=e.toString());}}
  @override void initState(){super.initState();load();}
  @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(18),children:[
    const Text('Stock balances',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold)),
    Align(alignment:Alignment.centerLeft,child:OutlinedButton.icon(onPressed:load,icon:const Icon(Icons.refresh),label:const Text('Refresh'))),
    if(message.isNotEmpty)Text(message),
    ...products.map((p)=>Card(child:ListTile(leading:const Icon(Icons.inventory_2,color:brandGreen),title:Text('${p['product_name']??p['name']??'Product'}'),subtitle:Text('Branch: ${p['branch_name']??'Ntulele'}'),trailing:Text('${p['quantity_available']??''} ${p['unit']??''}')))),
  ]);
}
class CustomersPage extends StatefulWidget { const CustomersPage({super.key}); @override State<CustomersPage> createState()=>_CustomersPageState(); }
class _CustomersPageState extends State<CustomersPage> {
  List<Map<String,dynamic>> rows=[];
  String message='';
  bool busy=false;
  final search=TextEditingController();

  @override void initState(){ super.initState(); load(); }
  @override void dispose(){ search.dispose(); super.dispose(); }

  Future<void> load() async {
    setState(() { busy=true; message=''; });
    try {
      final r=await Supabase.instance.client.from('customers')
        .select('id,customer_type,full_name,phone,email,default_branch_id,active,created_at')
        .order('full_name');
      if(!mounted)return;
      setState(()=>rows=List<Map<String,dynamic>>.from(r));
    } catch(e) {
      if(!mounted)return;
      setState(()=>message='Could not load customers. Customer access is limited to authorized director accounts. Details: $e');
    }
    if(mounted)setState(()=>busy=false);
  }

  Future<void> editCustomer([Map<String,dynamic>? row]) async {
    final name=TextEditingController(text:row?['full_name']?.toString()??'');
    final phone=TextEditingController(text:row?['phone']?.toString()??'');
    final email=TextEditingController(text:row?['email']?.toString()??'');
    String type=row?['customer_type']?.toString()??'buyer';
    String? error;
    final result=await showDialog<bool>(context:context,builder:(dialogContext)=>StatefulBuilder(builder:(context,refresh)=>AlertDialog(
      title:Text(row==null?'Add customer':'Edit customer'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:name,decoration:const InputDecoration(labelText:'Customer name')),
        TextField(controller:phone,keyboardType:TextInputType.phone,decoration:const InputDecoration(labelText:'Phone number')),
        TextField(controller:email,keyboardType:TextInputType.emailAddress,decoration:const InputDecoration(labelText:'Email (optional)')),
        DropdownButtonFormField<String>(value:type,decoration:const InputDecoration(labelText:'Customer type'),
          items:const [DropdownMenuItem(value:'buyer',child:Text('Buyer')),DropdownMenuItem(value:'seller',child:Text('Seller'))],
          onChanged:(v)=>refresh(()=>type=v??'buyer')),
        if(error!=null)Text(error!,style:const TextStyle(color:Colors.red)),
      ])),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('Cancel')),
        FilledButton(onPressed:()async{
          if(name.text.trim().isEmpty||phone.text.trim().isEmpty){refresh(()=>error='Name and phone number are required.');return;}
          Navigator.pop(dialogContext,true);
        },child:const Text('Save')),
      ],
    )));
    if(result==true){
      try {
        final db=Supabase.instance.client;
        final values=<String,dynamic>{'customer_type':type,'full_name':name.text.trim(),'phone':phone.text.trim(),
          'email':email.text.trim().isEmpty?null:email.text.trim()};
        if(row==null){
          final branch=await db.from('branches').select('id').eq('code','NTULELE').maybeSingle();
          if(branch!=null)values['default_branch_id']=branch['id'];
          await db.from('customers').insert(values);
        } else {
          await db.from('customers').update(values).eq('id',row['id']);
        }
        await load();
      } catch(e) { if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Customer could not be saved: $e'))); }
    }
    name.dispose();phone.dispose();email.dispose();
  }

  Future<void> showCustomer(Map<String,dynamic> customer) async {
    final db=Supabase.instance.client;
    try {
      final id=customer['id'];
      final results=await Future.wait([
        db.from('sales').select('id,sale_number,sale_date,total_amount').eq('customer_id',id).order('sale_date',ascending:false),
        db.from('customer_payments').select('id,payment_number,amount,method,status,received_at,created_at').eq('customer_id',id).order('created_at',ascending:false),
      ]);
      final sales=List<Map<String,dynamic>>.from(results[0]);
      final payments=List<Map<String,dynamic>>.from(results[1]);
      final totalSales=sales.fold<double>(0,(s,r)=>s+((r['total_amount'] as num?)?.toDouble()??0));
      final verified=payments.where((p)=>p['status']=='verified').fold<double>(0,(s,r)=>s+((r['amount'] as num?)?.toDouble()??0));
      final balance=totalSales-verified;
      if(!mounted)return;
      await showDialog<void>(context:context,builder:(context)=>AlertDialog(
        title:Text(customer['full_name']?.toString()??'Customer'),
        content:SizedBox(width:480,child:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('Phone: ${customer['phone']??'—'}'),
          Text('Email: ${customer['email']??'—'}'),
          const SizedBox(height:12),
          Text('Total purchases: KES ${totalSales.toStringAsFixed(2)}'),
          Text('Verified payments: KES ${verified.toStringAsFixed(2)}'),
          Text('Outstanding balance: KES ${balance.toStringAsFixed(2)}',style:TextStyle(fontWeight:FontWeight.bold,color:balance>0?Colors.red:brandGreen)),
          const Divider(),
          const Text('Purchase history',style:TextStyle(fontWeight:FontWeight.bold)),
          if(sales.isEmpty)const Text('No sales recorded for this customer.'),
          ...sales.map((s)=>ListTile(contentPadding:EdgeInsets.zero,title:Text('${s['sale_number']}'),subtitle:Text('${s['sale_date']}'),trailing:Text('KES ${((s['total_amount'] as num?)?.toDouble()??0).toStringAsFixed(2)}'))),
          const Divider(),
          const Text('Payments',style:TextStyle(fontWeight:FontWeight.bold)),
          if(payments.isEmpty)const Text('No payments recorded.'),
          ...payments.map((p)=>ListTile(contentPadding:EdgeInsets.zero,title:Text('KES ${((p['amount'] as num?)?.toDouble()??0).toStringAsFixed(2)} • ${p['method']}'),subtitle:Text('${p['status']} • ${p['payment_number']}'))),
        ]))),
        actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Close'))],
      ));
    } catch(e) {
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Customer financial history is not available for this account: $e')));
    }
  }

  Future<void> setActive(Map<String,dynamic> row,bool active) async {
    try {
      final db = Supabase.instance.client;
      await db.from('customers').update({
        'active': active,
        if (active) 'approved_at': DateTime.now().toUtc().toIso8601String(),
        if (active) 'approved_by': db.auth.currentUser!.id,
      }).eq('id',row['id']);
      final profileId = row['profile_id'];
      if (profileId != null) {
        await db.from('profiles').update({'status': active ? 'active' : 'suspended'}).eq('id',profileId);
      }
      await load();
    } catch(e){ if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Could not update customer: $e'))); }
  }

  @override Widget build(BuildContext context) {
    final query=search.text.trim().toLowerCase();
    final filtered=rows.where((r)=>(r['full_name']??'').toString().toLowerCase().contains(query)||(r['phone']??'').toString().toLowerCase().contains(query)).toList();
    return ListView(padding:const EdgeInsets.all(18),children:[
      Row(children:[const Expanded(child:Text('Customers',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold))),
        IconButton(onPressed:busy?null:load,icon:const Icon(Icons.refresh),tooltip:'Refresh'),
        FilledButton.icon(onPressed:()=>editCustomer(),icon:const Icon(Icons.person_add),label:const Text('Add'))]),
      TextField(controller:search,onChanged:(_)=>setState((){}),decoration:const InputDecoration(prefixIcon:Icon(Icons.search),labelText:'Search by name or phone',border:OutlineInputBorder())),
      const SizedBox(height:10),
      if(message.isNotEmpty)Padding(padding:const EdgeInsets.all(12),child:Text(message,style:const TextStyle(color:Colors.red))),
      if(busy)const Center(child:Padding(padding:EdgeInsets.all(20),child:CircularProgressIndicator())),
      if(!busy&&message.isEmpty&&filtered.isEmpty)const Padding(padding:EdgeInsets.all(20),child:Text('No customers found. Add your first customer.')),
      ...filtered.map((r)=>Card(child:ListTile(
        leading:CircleAvatar(child:Icon(r['customer_type']=='seller'?Icons.store:Icons.person)),
        title:Text(r['full_name']?.toString()??''),
        subtitle:Text('${r['phone']??''} • ${r['customer_type']??''}${r['active']==false?' • Inactive':''}'),
        onTap:()=>showCustomer(r),
        trailing:PopupMenuButton<String>(onSelected:(v){if(v=='edit')editCustomer(r);if(v=='deactivate')setActive(r,false);if(v=='activate')setActive(r,true);},
          itemBuilder:(context)=>[
            const PopupMenuItem(value:'edit',child:Text('Edit details')),
            if(r['active']==true)const PopupMenuItem(value:'deactivate',child:Text('Deactivate')),
            if(r['active']==false)const PopupMenuItem(value:'activate',child:Text('Approve / activate account')),
          ]),
      ))),
      const Padding(padding:EdgeInsets.only(top:8),child:Text('Customer balances count verified payments only. Pending, rejected and reversed payments are not treated as money received.',style:TextStyle(fontSize:12,color:Colors.black54))),
    ]);
  }
}


class TractorServicesPage extends StatefulWidget {
  const TractorServicesPage({super.key});
  @override State<TractorServicesPage> createState() => _TractorServicesPageState();
}
class _TractorServicesPageState extends State<TractorServicesPage> with SingleTickerProviderStateMixin {
  late final TabController tabs = TabController(length: 3, vsync: this);
  final db = Supabase.instance.client;
  List<Map<String,dynamic>> tractors = [], jobs = [];
  String? branchId, selectedTractor, selectedJob;
  bool loading = true, saving = false;
  String message = '', ownership = 'company', service = 'ploughing', paymentMethod = 'cash', payer = 'Edu', expenseType = 'fuel';
  final code=TextEditingController(), reg=TextEditingController(), model=TextEditingController(), owner=TextEditingController();
  final farmer=TextEditingController(), phone=TextEditingController(), location=TextEditingController(), acres=TextEditingController(), rate=TextEditingController(), notes=TextEditingController();
  final pay=TextEditingController(), reference=TextEditingController(), expense=TextEditingController(), expenseNote=TextEditingController(), maintenance=TextEditingController(), maintenanceCost=TextEditingController();
  @override void initState(){super.initState();load();}
  @override void dispose(){tabs.dispose();for(final c in [code,reg,model,owner,farmer,phone,location,acres,rate,notes,pay,reference,expense,expenseNote,maintenance,maintenanceCost]){c.dispose();}super.dispose();}
  Future<void> load() async {
    setState((){loading=true;message='';});
    try{
      final b=await db.from('branches').select('id').eq('code','NTULELE').single(); branchId=b['id'].toString();
      final a=await db.from('tractor_assets').select().eq('branch_id',branchId!).order('created_at',ascending:false);
      final j=await db.from('tractor_service_jobs').select().eq('branch_id',branchId!).order('created_at',ascending:false);
      if(!mounted)return; setState((){tractors=List<Map<String,dynamic>>.from(a);jobs=List<Map<String,dynamic>>.from(j);loading=false;});
      if(selectedTractor==null&&tractors.isNotEmpty)selectedTractor=tractors.first['id'].toString();
      if(selectedJob==null&&jobs.isNotEmpty)selectedJob=jobs.first['id'].toString();
    }catch(e){if(mounted)setState((){loading=false;message='Could not load tractor records: '+e.toString();});}
  }
  Future<void> registerTractor() async {
    if(code.text.trim().isEmpty||model.text.trim().isEmpty){setState(()=>message='Enter tractor code and make/model.');return;}
    setState(()=>saving=true);
    try{await db.from('tractor_assets').insert({'branch_id':branchId,'tractor_code':code.text.trim(),'registration_number':reg.text.trim().isEmpty?null:reg.text.trim(),'make_model':model.text.trim(),'ownership_type':ownership,'owner_name':owner.text.trim().isEmpty?null:owner.text.trim(),'created_by':db.auth.currentUser!.id});
      code.clear();reg.clear();model.clear();owner.clear();setState(()=>message='Tractor registered.');await load();
    }catch(e){setState(()=>message='Could not register tractor: '+e.toString());}if(mounted)setState(()=>saving=false);
  }
  Future<void> bookJob() async {
    final a=double.tryParse(acres.text), r=double.tryParse(rate.text);
    if(selectedTractor==null||farmer.text.trim().isEmpty||location.text.trim().isEmpty||r==null||r<0||(acres.text.isNotEmpty&&(a==null||a<=0))){setState(()=>message='Select a tractor and enter farmer, location, acres and rate.');return;}
    setState(()=>saving=true);
    try{await db.from('tractor_service_jobs').insert({'job_number':'TRJ-'+DateTime.now().millisecondsSinceEpoch.toString(),'branch_id':branchId,'tractor_id':selectedTractor,'farmer_name':farmer.text.trim(),'farmer_phone':phone.text.trim().isEmpty?null:phone.text.trim(),'service_type':service,'service_location':location.text.trim(),'area_acres':a,'rate':r,'total_charge':(a??1)*r,'status':'booked','notes':notes.text.trim(),'recorded_by':db.auth.currentUser!.id});
      farmer.clear();phone.clear();location.clear();acres.clear();rate.clear();notes.clear();setState(()=>message='Tractor booking saved.');await load();
    }catch(e){setState(()=>message='Could not save booking: '+e.toString());}if(mounted)setState(()=>saving=false);
  }
  Future<void> recordPayment() async {
    final amount=double.tryParse(pay.text);if(selectedJob==null||amount==null||amount<=0){setState(()=>message='Select a job and enter a valid payment.');return;}
    setState(()=>saving=true);
    try{final result=await db.rpc('record_tractor_job_payment',params:{'p_job_id':selectedJob,'p_amount':amount,'p_method':paymentMethod,'p_reference':reference.text.trim().isEmpty?null:reference.text.trim()});pay.clear();reference.clear();setState(()=>message='Payment recorded: '+result['payment_number'].toString()+' ('+result['status'].toString()+').');}
    catch(e){setState(()=>message='Could not record payment: '+e.toString());}if(mounted)setState(()=>saving=false);
  }
  Future<void> recordExpense() async {
    final amount=double.tryParse(expense.text);if(selectedJob==null||amount==null||amount<=0){setState(()=>message='Select a job and enter a valid expense.');return;}
    setState(()=>saving=true);
    try{await db.from('tractor_job_expenses').insert({'job_id':selectedJob,'branch_id':branchId,'expense_type':expenseType,'description':expenseNote.text.trim(),'amount':amount,'paid_by_owner':payer,'recorded_by':db.auth.currentUser!.id});expense.clear();expenseNote.clear();setState(()=>message='Expense recorded.');}
    catch(e){setState(()=>message='Could not record expense: '+e.toString());}if(mounted)setState(()=>saving=false);
  }
  Future<void> saveMaintenance() async {
    final cost=double.tryParse(maintenanceCost.text)??0;if(selectedTractor==null||maintenance.text.trim().isEmpty||cost<0){setState(()=>message='Select a tractor and describe maintenance.');return;}
    setState(()=>saving=true);
    try{await db.from('tractor_maintenance_records').insert({'tractor_id':selectedTractor,'branch_id':branchId,'maintenance_type':'service','description':maintenance.text.trim(),'cost':cost,'recorded_by':db.auth.currentUser!.id});await db.from('tractor_assets').update({'status':'maintenance'}).eq('id',selectedTractor!);maintenance.clear();maintenanceCost.clear();setState(()=>message='Maintenance saved; tractor marked for maintenance.');await load();}
    catch(e){setState(()=>message='Could not save maintenance: '+e.toString());}if(mounted)setState(()=>saving=false);
  }
  Widget field(TextEditingController c,String label,{bool number=false})=>Padding(padding:const EdgeInsets.only(bottom:10),child:TextField(controller:c,keyboardType:number?const TextInputType.numberWithOptions(decimal:true):TextInputType.text,decoration:InputDecoration(labelText:label,border:const OutlineInputBorder())));
  Widget dropdown(String label,String value,List<String> values,ValueChanged<String?> change)=>Padding(padding:const EdgeInsets.only(bottom:10),child:DropdownButtonFormField<String>(value:value,decoration:InputDecoration(labelText:label,border:const OutlineInputBorder()),items:values.map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:change));
  Widget button(String label,VoidCallback fn)=>SizedBox(width:double.infinity,child:FilledButton(onPressed:saving?null:fn,child:Text(saving?'Saving…':label)));
  Widget tractorPicker()=>Padding(padding:const EdgeInsets.only(bottom:10),child:DropdownButtonFormField<String>(value:selectedTractor,decoration:const InputDecoration(labelText:'Tractor',border:OutlineInputBorder()),items:tractors.map((t)=>DropdownMenuItem(value:t['id'].toString(),child:Text(t['tractor_code'].toString()+' • '+t['make_model'].toString()))).toList(),onChanged:(v)=>setState(()=>selectedTractor=v)));
  Widget jobPicker()=>Padding(padding:const EdgeInsets.only(bottom:10),child:DropdownButtonFormField<String>(value:selectedJob,decoration:const InputDecoration(labelText:'Job',border:OutlineInputBorder()),items:jobs.map((j)=>DropdownMenuItem(value:j['id'].toString(),child:Text(j['job_number'].toString()+' • '+j['farmer_name'].toString()))).toList(),onChanged:(v)=>setState(()=>selectedJob=v)));
  Widget tractorTab()=>ListView(padding:const EdgeInsets.all(14),children:[
    const Text('Register tractor',style:TextStyle(fontSize:19,fontWeight:FontWeight.bold)),
    field(code,'Tractor code'),field(reg,'Registration number'),field(model,'Make / model'),dropdown('Ownership',ownership,['company','leased','third_party'],(v)=>setState(()=>ownership=v!)),field(owner,'Owner name'),button('Register tractor',registerTractor),
    const Divider(height:30),Text('Tractors ('+tractors.length.toString()+')',style:const TextStyle(fontWeight:FontWeight.bold)),
    ...tractors.map((t)=>Card(child:ListTile(leading:const Icon(Icons.agriculture,color:brandGreen),title:Text(t['tractor_code'].toString()+' • '+t['make_model'].toString()),subtitle:Text((t['registration_number']??'No registration').toString()+' • '+t['ownership_type'].toString()),trailing:Text((t['status']??'').toString())))),
    const Divider(height:30),const Text('Maintenance',style:TextStyle(fontWeight:FontWeight.bold)),tractorPicker(),field(maintenance,'Maintenance / repair details'),field(maintenanceCost,'Cost (KES)',number:true),button('Save maintenance',saveMaintenance)
  ]);
  Widget bookingsTab()=>ListView(padding:const EdgeInsets.all(14),children:[
    const Text('Book tractor service',style:TextStyle(fontSize:19,fontWeight:FontWeight.bold)),tractorPicker(),field(farmer,'Farmer / customer name'),field(phone,'Phone number'),
    dropdown('Service',service,['ploughing','planting','harrowing','transport','other'],(v)=>setState(()=>service=v!)),field(location,'Farm location'),field(acres,'Area (acres)',number:true),field(rate,'Rate per acre (KES)',number:true),field(notes,'Notes'),button('Save booking',bookJob),
    const Divider(height:30),Text('Service jobs ('+jobs.length.toString()+')',style:const TextStyle(fontWeight:FontWeight.bold)),
    ...jobs.map((j)=>Card(child:ListTile(leading:const Icon(Icons.event_available),title:Text(j['job_number'].toString()+' • '+j['farmer_name'].toString()),subtitle:Text(j['service_type'].toString()+' • '+j['service_location'].toString()+' • '+(j['area_acres']??'-').toString()+' acres'),trailing:Text('KES '+j['total_charge'].toString()+'\n'+j['status'].toString(),textAlign:TextAlign.end))))
  ]);
  Widget financeTab()=>ListView(padding:const EdgeInsets.all(14),children:[
    const Text('Payments and expenses',style:TextStyle(fontSize:19,fontWeight:FontWeight.bold)),jobPicker(),field(pay,'Payment amount (KES)',number:true),dropdown('Payment method',paymentMethod,['cash','mpesa','bank_transfer','other'],(v)=>setState(()=>paymentMethod=v!)),field(reference,'M-Pesa / bank reference'),button('Record payment',recordPayment),
    const Divider(height:30),dropdown('Expense type',expenseType,['fuel','labour','transport','repair','other'],(v)=>setState(()=>expenseType=v!)),field(expenseNote,'Expense details'),field(expense,'Expense amount (KES)',number:true),dropdown('Paid by',payer,['Edu','Mercy'],(v)=>setState(()=>payer=v!)),button('Record expense',recordExpense),
    const Padding(padding:EdgeInsets.only(top:14),child:Text('Non-cash payments remain pending until verified. Supabase applies branch and role restrictions to financial records.',style:TextStyle(fontSize:12,color:Colors.black54)))
  ]);
  @override Widget build(BuildContext context)=>Column(children:[
    const Padding(padding:EdgeInsets.fromLTRB(16,12,16,2),child:Align(alignment:Alignment.centerLeft,child:Text('Tractor Services',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold)))),
    TabBar(controller:tabs,isScrollable:true,labelColor:brandGreen,tabs:const[Tab(icon:Icon(Icons.agriculture),text:'Tractors'),Tab(icon:Icon(Icons.event),text:'Bookings'),Tab(icon:Icon(Icons.payments),text:'Payments & costs')]),
    if(message.isNotEmpty)Padding(padding:const EdgeInsets.all(8),child:Text(message,style:TextStyle(color:message.startsWith('Could not')?Colors.red:brandGreen))),
    Expanded(child:loading?const Center(child:CircularProgressIndicator()):TabBarView(controller:tabs,children:[tractorTab(),bookingsTab(),financeTab()])),
    Align(alignment:Alignment.centerRight,child:TextButton.icon(onPressed:load,icon:const Icon(Icons.refresh),label:const Text('Refresh')))
  ]);
}


class FormPage extends StatelessWidget {
  final String title; final List<Widget> children;
  const FormPage({super.key,required this.title,required this.children});
  @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(18),children:[
    Text(title,style:const TextStyle(fontSize:24,fontWeight:FontWeight.bold)),const SizedBox(height:12),
    Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(children:[...children.map((w)=>Padding(padding:const EdgeInsets.only(bottom:12),child:w))]))),
  ]);
}
Widget field(TextEditingController c,String label,{bool number=false})=>TextField(controller:c,keyboardType:number?const TextInputType.numberWithOptions(decimal:true):TextInputType.text,decoration:InputDecoration(labelText:label,border:const OutlineInputBorder()));
Widget actionButton(String label,bool busy,VoidCallback fn)=>SizedBox(width:double.infinity,child:FilledButton(onPressed:busy?null:fn,child:Text(busy?'Saving…':label)));

class DemoLoginPage extends StatefulWidget {
  const DemoLoginPage({super.key});
  @override
  State<DemoLoginPage> createState() => _DemoLoginPageState();
}

class _DemoLoginPageState extends State<DemoLoginPage> {
  final phone = TextEditingController();
  final pin = TextEditingController();
  String? error;

  @override
  void dispose() {
    phone.dispose();
    pin.dispose();
    super.dispose();
  }

  void signIn() {
    final digits = phone.text.replaceAll(RegExp(r'[^0-9]'), '');
    final validPhone = (digits.length == 10 && digits.startsWith('0')) ||
        (digits.length == 12 && digits.startsWith('254'));
    if (!validPhone) {
      setState(() => error = 'Enter a valid Kenyan phone number, e.g. 07XXXXXXXX.');
      return;
    }
    if (pin.text.trim().length != 6 || int.tryParse(pin.text.trim()) == null) {
      setState(() => error = 'Enter a six-digit demo PIN.');
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const PreviewHome()),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BrandMark(),
                  const SizedBox(height: 22),
                  Text('TAJIR demo sign in', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  const Text('Use a phone number and any six-digit PIN to explore the demo.', textAlign: TextAlign.center),
                  const SizedBox(height: 18),
                  TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone number', hintText: '07XXXXXXXX', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(controller: pin, keyboardType: TextInputType.number, obscureText: true, maxLength: 6, decoration: const InputDecoration(labelText: 'Six-digit demo PIN', border: OutlineInputBorder(), counterText: '')),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(width: double.infinity, child: FilledButton(onPressed: signIn, child: const Text('Enter demo'))),
                  const SizedBox(height: 8),
                  if (tajirBackendConfigured)
                    TextButton(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CustomerAuthPage())),
                      child: const Text('New customer? Create an account with phone number'),
                    ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                    child: const Text('DEMO ONLY: This screen does not send an SMS, verify ownership of the phone number, create an account, or save a PIN. Demo entries stay on this device screen and are not sent to the live database.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class PreviewHome extends StatefulWidget {
  const PreviewHome({super.key});
  @override
  State<PreviewHome> createState() => _PreviewHomeState();
}

class _PreviewHomeState extends State<PreviewHome> {
  int index = 0;
  DateTime selectedDate = DateTime.now();
  String product = 'Maize';
  String beanVariety = 'Rosecoco';
  String fertilizerType = 'DAP';
  final beanVarieties = <String>['Rosecoco', 'Wairimu', 'Canadian Wonder', 'Mwitemania', 'Mwezi Moja', 'Nyayo'];
  final fertilizerTypes = <String>['DAP', 'CAN', 'NPK', 'Urea', 'Planting fertilizer', 'Top-dressing fertilizer'];
  final quantity = TextEditingController();
  final price = TextEditingController();
  final purchases = <Map<String, String>>[];
  final sales = <Map<String, String>>[];
  final openingStocks = <Map<String, String>>[];
  String message = '';

  @override
  void dispose() {
    quantity.dispose();
    price.dispose();
    super.dispose();
  }

  Future<void> addChoice(List<String> choices, bool isBean) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isBean ? 'Add bean variety' : 'Add fertilizer type'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            final text = controller.text.trim();
            if (text.isNotEmpty) Navigator.pop(context, text);
          }, child: const Text('Add')),
        ],
      ),
    );
    controller.dispose();
    if (value != null && value.trim().isNotEmpty && !choices.contains(value.trim())) {
      setState(() {
        choices.add(value.trim());
        if (isBean) { beanVariety = value.trim(); } else { fertilizerType = value.trim(); }
      });
    }
  }

  Future<void> chooseDate() async {
    final picked = await showDatePicker(context: context, initialDate: selectedDate,
        firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (picked != null) setState(() => selectedDate = picked);
  }

  void saveEntry(bool isSale) {
    final q = double.tryParse(quantity.text.trim());
    final p = double.tryParse(price.text.trim());
    if (q == null || q <= 0 || p == null || p < 0) {
      setState(() => message = 'Enter a valid quantity and price.');
      return;
    }
    final item = <String, String>{
      'date': '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}',
      'product': product,
      'variety': product == 'Beans' ? beanVariety : product == 'Fertilizer' ? fertilizerType : '—',
      'quantity': q.toString(),
      'price': p.toStringAsFixed(2),
    };
    setState(() {
      (isSale ? sales : purchases).insert(0, item);
      message = isSale ? 'Sale added to this preview.' : 'Purchase added to this preview.';
      quantity.clear();
      price.clear();
    });
  }

  Widget entryPage(bool isSale) {
    final records = isSale ? sales : purchases;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(isSale ? 'Record a sale' : 'Record a purchase',
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Preview mode: entries stay on this screen and are not saved to the live database.',
            style: TextStyle(color: Colors.deepOrange, fontSize: 12)),
        const SizedBox(height: 16),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
          SizedBox(width: double.infinity, child: OutlinedButton.icon(
            onPressed: chooseDate, icon: const Icon(Icons.calendar_month),
            label: Text('Date: ${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}'),
          )),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: product,
            decoration: const InputDecoration(labelText: 'Product', border: OutlineInputBorder()),
            items: const ['Maize', 'Beans', 'Fertilizer'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (v) => setState(() { product = v ?? 'Maize'; message = ''; }),
          ),
          if (product == 'Beans') ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: beanVariety,
              decoration: const InputDecoration(labelText: 'Bean variety', border: OutlineInputBorder()),
              items: beanVarieties.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) => setState(() => beanVariety = v ?? beanVarieties.first),
            ),
            TextButton.icon(onPressed: () => addChoice(beanVarieties, true),
                icon: const Icon(Icons.add), label: const Text('Add another bean variety')),
          ],
          if (product == 'Fertilizer') ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: fertilizerType,
              decoration: const InputDecoration(labelText: 'Fertilizer type', border: OutlineInputBorder()),
              items: fertilizerTypes.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (v) => setState(() => fertilizerType = v ?? fertilizerTypes.first),
            ),
            TextButton.icon(onPressed: () => addChoice(fertilizerTypes, false),
                icon: const Icon(Icons.add), label: const Text('Add another fertilizer type')),
          ],
          const SizedBox(height: 12),
          TextField(controller: quantity, keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Quantity (bags)', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: isSale ? 'Selling price per bag (KES)' : 'Buying price per bag (KES)',
                  border: const OutlineInputBorder())),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: FilledButton.icon(
              onPressed: () => saveEntry(isSale), icon: const Icon(Icons.save),
              label: Text(isSale ? 'Add sale' : 'Add purchase'))),
          if (message.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10),
              child: Text(message, style: const TextStyle(color: Colors.green))),
        ]))),
        const SizedBox(height: 16),
        Text(isSale ? 'Preview sales (${records.length})' : 'Preview purchases (${records.length})',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        if (records.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('No entries added yet.')),
        ...records.map((r) => Card(child: ListTile(
          title: Text('${r['product']} • ${r['variety']}'),
          subtitle: Text('${r['date']}  |  ${r['quantity']} bags'),
          trailing: Text('KES ${r['price']}'),
        ))),
      ],
    );
  }

  Future<void> addOpeningStock() async {
    final qtyController = TextEditingController();
    final costController = TextEditingController();
    String selectedProduct = 'Maize';
    String selectedBean = beanVarieties.first;
    String selectedFertilizer = fertilizerTypes.first;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, refreshDialog) => AlertDialog(
        title: const Text('Enter opening stock'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            value: selectedProduct,
            decoration: const InputDecoration(labelText: 'Product'),
            items: const ['Maize', 'Beans', 'Fertilizer'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (v) => refreshDialog(() => selectedProduct = v ?? 'Maize'),
          ),
          if (selectedProduct == 'Beans') DropdownButtonFormField<String>(
            value: selectedBean, decoration: const InputDecoration(labelText: 'Bean variety'),
            items: beanVarieties.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (v) => refreshDialog(() => selectedBean = v ?? beanVarieties.first),
          ),
          if (selectedProduct == 'Fertilizer') DropdownButtonFormField<String>(
            value: selectedFertilizer, decoration: const InputDecoration(labelText: 'Fertilizer type'),
            items: fertilizerTypes.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (v) => refreshDialog(() => selectedFertilizer = v ?? fertilizerTypes.first),
          ),
          TextField(controller: qtyController, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Quantity already in store (bags)')),
          TextField(controller: costController, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Original buying cost per bag (KES)')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            final q = double.tryParse(qtyController.text.trim());
            final cost = double.tryParse(costController.text.trim());
            if (q == null || q <= 0 || cost == null || cost < 0) return;
            Navigator.pop(dialogContext, true);
          }, child: const Text('Save opening stock')),
        ],
      )),
    );
    final q = double.tryParse(qtyController.text.trim());
    final cost = double.tryParse(costController.text.trim());
    qtyController.dispose();
    costController.dispose();
    if (saved == true && q != null && q > 0 && cost != null && cost >= 0) {
      final variety = selectedProduct == 'Beans' ? selectedBean : selectedProduct == 'Fertilizer' ? selectedFertilizer : '—';
      final now = DateTime.now();
      setState(() {
        openingStocks.insert(0, {
          'date': '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
          'product': selectedProduct, 'variety': variety, 'quantity': q.toString(), 'price': cost.toStringAsFixed(2)
        });
        message = 'Opening stock added to this preview.';
      });
    }
  }

  Widget stockPage() {
    final balances = <String, Map<String, dynamic>>{};
    for (final entry in openingStocks) {
      final key = '${entry['product']} • ${entry['variety']}';
      final row = balances.putIfAbsent(key, () => {'product': entry['product'], 'variety': entry['variety'], 'quantity': 0.0});
      row['quantity'] = (row['quantity'] as double) + (double.tryParse(entry['quantity'] ?? '0') ?? 0);
    }
    for (final entry in purchases) {
      final key = '${entry['product']} • ${entry['variety']}';
      final row = balances.putIfAbsent(key, () => {'product': entry['product'], 'variety': entry['variety'], 'quantity': 0.0});
      row['quantity'] = (row['quantity'] as double) + (double.tryParse(entry['quantity'] ?? '0') ?? 0);
    }
    for (final entry in sales) {
      final key = '${entry['product']} • ${entry['variety']}';
      final row = balances.putIfAbsent(key, () => {'product': entry['product'], 'variety': entry['variety'], 'quantity': 0.0});
      row['quantity'] = (row['quantity'] as double) - (double.tryParse(entry['quantity'] ?? '0') ?? 0);
    }
    final rows = balances.values.toList()
      ..sort((a, b) => (a['product'] as String).compareTo(b['product'] as String));
    final total = rows.fold<double>(0, (sum, row) => sum + (row['quantity'] as double));

    // Preview valuation uses weighted-average purchase cost for each product/variety.
    final boughtQty = <String, double>{};
    final boughtCost = <String, double>{};
    final soldQty = <String, double>{};
    final salesRevenue = <String, double>{};
    for (final e in [...openingStocks, ...purchases]) {
      final key = '${e['product']} • ${e['variety']}';
      final q = double.tryParse(e['quantity'] ?? '0') ?? 0;
      final p = double.tryParse(e['price'] ?? '0') ?? 0;
      boughtQty[key] = (boughtQty[key] ?? 0) + q;
      boughtCost[key] = (boughtCost[key] ?? 0) + q * p;
    }
    for (final e in sales) {
      final key = '${e['product']} • ${e['variety']}';
      final q = double.tryParse(e['quantity'] ?? '0') ?? 0;
      final p = double.tryParse(e['price'] ?? '0') ?? 0;
      soldQty[key] = (soldQty[key] ?? 0) + q;
      salesRevenue[key] = (salesRevenue[key] ?? 0) + q * p;
    }
    final totalPurchaseValue = boughtCost.values.fold<double>(0, (a, b) => a + b);
    final totalSalesRevenue = salesRevenue.values.fold<double>(0, (a, b) => a + b);
    double costOfGoodsSold = 0;
    double grossProfit = 0;
    final financialRows = <Map<String, dynamic>>[];
    for (final key in {...boughtQty.keys, ...soldQty.keys}) {
      final qtyBought = boughtQty[key] ?? 0;
      final costBought = boughtCost[key] ?? 0;
      final averageCost = qtyBought > 0 ? costBought / qtyBought : 0.0;
      final qtySold = soldQty[key] ?? 0;
      final revenue = salesRevenue[key] ?? 0;
      final costSold = qtySold * averageCost;
      final profit = revenue - costSold;
      costOfGoodsSold += costSold;
      grossProfit += profit;
      financialRows.add({'key': key, 'revenue': revenue, 'cost': costSold, 'profit': profit});
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Stock overview', style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      const Text('Preview stock is calculated from the purchases and sales entered in this demo. It is not yet saved to the live database.',
          style: TextStyle(color: Colors.deepOrange, fontSize: 12)),
      const SizedBox(height: 14),
      const Text('Business financial summary', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
        _moneyLine('Total stock bought (including opening stock)', totalPurchaseValue),
        _moneyLine('Total sales revenue', totalSalesRevenue),
        _moneyLine('Cost of stock sold', costOfGoodsSold),
        const Divider(),
        _moneyLine(grossProfit >= 0 ? 'Gross profit' : 'Gross loss', grossProfit, emphasize: true),
      ]))),
      const SizedBox(height: 8),
      const Text('Profit / loss by product', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      if (financialRows.isEmpty) const Text('Add purchases and sales to see profit or loss.'),
      ...financialRows.map((r) => Card(child: ListTile(
        title: Text(r['key'] as String),
        subtitle: Text('Sales: KES ${(r['revenue'] as double).toStringAsFixed(2)} • Cost sold: KES ${(r['cost'] as double).toStringAsFixed(2)}'),
        trailing: Text('KES ${(r['profit'] as double).toStringAsFixed(2)}',
          style: TextStyle(fontWeight: FontWeight.bold, color: (r['profit'] as double) >= 0 ? brandGreen : Colors.red)),
      ))),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Items tracked'), Text('${rows.length}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        ])))),
        Expanded(child: Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Net bags in stock'), Text(total.toStringAsFixed(2), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        ])))),
      ]),
      const SizedBox(height: 8),
      FilledButton.icon(onPressed: addOpeningStock, icon: const Icon(Icons.add_box), label: const Text('Add opening stock')),
      const SizedBox(height: 8),
      const Text('Available stock by product', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      if (rows.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('No stock yet. Add a purchase from the Buy screen to see stock here.'))),
      ...rows.map((row) {
        final quantity = row['quantity'] as double;
        final isLow = quantity <= 5;
        return Card(child: ListTile(
          leading: Icon(Icons.inventory_2, color: quantity <= 0 ? Colors.red : isLow ? Colors.orange : brandGreen),
          title: Text('${row['product']} • ${row['variety']}'),
          subtitle: Text(quantity <= 0 ? 'Out of stock' : isLow ? 'Low stock' : 'Available'),
          trailing: Text('${quantity.toStringAsFixed(2)} bags', style: const TextStyle(fontWeight: FontWeight.bold)),
        ));
      }),
      const SizedBox(height: 14),
      const Text('Recent stock movements', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ...[...openingStocks.map((e) => {...e, 'movement': 'Opening stock'}), ...purchases.map((e) => {...e, 'movement': 'Stock in'}), ...sales.map((e) => {...e, 'movement': 'Stock out'})]
        .take(12).map((e) => Card(child: ListTile(
          leading: Icon(e['movement'] == 'Stock out' ? Icons.arrow_upward : Icons.arrow_downward,
              color: e['movement'] == 'Stock out' ? Colors.deepOrange : brandGreen),
          title: Text('${e['movement']} • ${e['product']} • ${e['variety']}'),
          subtitle: Text('${e['date']}'),
          trailing: Text('${e['quantity']} bags'),
        ))),
    ]);
  }

  Widget _moneyLine(String label, double value, {bool emphasize = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      Expanded(child: Text(label, style: TextStyle(fontWeight: emphasize ? FontWeight.bold : FontWeight.normal))),
      Text('KES ${value.toStringAsFixed(2)}', style: TextStyle(
        fontWeight: emphasize ? FontWeight.bold : FontWeight.w600,
        color: emphasize ? (value >= 0 ? brandGreen : Colors.red) : null,
      )),
    ]),
  );

  Widget homePage() => ListView(padding: EdgeInsets.all(20), children: [
    BrandMark(), SizedBox(height: 24),
    Text('Welcome to TAJIR', textAlign: TextAlign.center,
        style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
    SizedBox(height: 12),
    Text('Use Purchases and Sales to try the entry forms. This is a demonstration preview; records are temporary and are not sent to the live database.',
        textAlign: TextAlign.center),
  ]);

  @override
  Widget build(BuildContext context) {
    final pages = [
      homePage(), entryPage(false), entryPage(true),
      stockPage(),
      const Center(child: Text('Customer preview — live customer records are not connected in preview mode.')),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('TAJIR - INTERACTIVE PREVIEW')),
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() { index = value; message = ''; }),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.shopping_cart), label: 'Buy'),
          NavigationDestination(icon: Icon(Icons.point_of_sale), label: 'Sell'),
          NavigationDestination(icon: Icon(Icons.inventory), label: 'Stock'),
          NavigationDestination(icon: Icon(Icons.people), label: 'Customers'),
        ],
      ),
    );
  }
}
