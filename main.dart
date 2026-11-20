import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const brandGreen = Color(0xFF176B3A);
const brandGold = Color(0xFFD6A52D);
 
/// Turns technical backend/network failures into clear messages for everyday users.
/// Never display raw HTTP/database error codes in the app.
String friendlyError(Object error) {
  final raw = error.toString().replaceFirst(
    RegExp(r'^(Exception|FormatException|AuthException|PostgrestException|FunctionException):\s*'),
    '',
  ).trim();
  final value = raw.toLowerCase();

  // Lockout and throttling messages must be checked before generic PIN errors.
  // The server's lockout message contains "incorrect PIN", but it is not a bad-PIN
  // response; preserve the retry guidance instead of misleading every user.
  if (RegExp(r'\b429\b').hasMatch(value) ||
      value.contains('too many incorrect pin attempts') ||
      value.contains('too many attempts') ||
      value.contains('try again in') ||
      value.contains('temporarily locked')) {
    final waitMatch = RegExp(r'try again in ([^.]+)').firstMatch(raw);
    return waitMatch != null
        ? 'Your account is temporarily locked. Please try again in ${waitMatch.group(1)}.'
        : 'Your account is temporarily locked after several attempts. Please wait before trying again.';
  }

  // Only show Wrong PIN for an actual credential mismatch.
  if (value.contains('wrong pin') || value.contains('incorrect pin') ||
      value.contains('invalid pin') || value.contains('pin does not match')) {
    return 'Wrong PIN. Please check your PIN and try again.';
  }
  if (value.contains('invalid login credentials') || value.contains('invalid credentials')) {
    return 'The phone number or PIN is incorrect. Please check and try again.';
  }
  if (value.contains('phone') && (value.contains('already registered') ||
      value.contains('already exists') || value.contains('duplicate'))) {
    return 'This phone number is already registered. Please sign in or use another number.';
  }
  if (value.contains('phone') && (value.contains('not found') ||
      value.contains('not registered') || value.contains('no account'))) {
    return 'We could not find an account with this phone number. Check the number or register first.';
  }
  if (value.contains('pin') && (value.contains('four') || value.contains('4 digit') ||
      value.contains('4-digit') || value.contains('length'))) {
    return 'Your PIN must contain exactly four digits.';
  }
  if (value.contains('pin') && value.contains('match')) {
    return 'The PINs do not match. Enter the same PIN in both boxes.';
  }
  if (value.contains('session') && (value.contains('expired') || value.contains('missing'))) {
    return 'Your session has expired. Please sign in again.';
  }
  if (RegExp(r'\b401\b').hasMatch(value) || value.contains('unauthorized') || value.contains('jwt')) {
    return 'Your session has expired. Please sign in again and try once more.';
  }
  if (RegExp(r'\b403\b').hasMatch(value) || value.contains('permission denied') || value.contains('not allowed')) {
    return 'You do not have permission to do this. Please contact the Director if you need access.';
  }
  if (RegExp(r'\b404\b').hasMatch(value) || value.contains('not found')) {
    return 'We could not find that record. Refresh the page and try again.';
  }
  if (RegExp(r'\b409\b').hasMatch(value) || value.contains('duplicate') || value.contains('already exists') || value.contains('conflict')) {
    return 'This information is already registered or has changed. Refresh and check the details.';
  }
  if (RegExp(r'\b429\b').hasMatch(value) || value.contains('too many requests') || value.contains('rate limit')) {
    return 'Too many attempts were made. Please wait a little and try again.';
  }
  if (RegExp(r'\b400\b').hasMatch(value) || value.contains('bad request')) {
    return 'Some details are missing or incorrect. Check the information and try again.';
  }
  if (RegExp(r'\b(500|502|503|504)\b').hasMatch(value) || value.contains('server error')) {
    return 'The service is temporarily unavailable. Please try again in a few minutes.';
  }
  if (value.contains('socketexception') || value.contains('failed host lookup') ||
      value.contains('network is unreachable') || value.contains('connection refused')) {
    return 'There is a connection problem. Check your internet and try again.';
  }
  if (value.contains('timed out') || value.contains('timeout')) {
    return 'The request took too long. Check your connection and try again.';
  }
  if (raw.isEmpty || RegExp(r'\b(code|status)\s*[:=]?\s*\d{3}\b', caseSensitive: false).hasMatch(raw)) {
    return 'Something went wrong. Please try again. If the problem continues, contact the Director.';
  }
  return raw;
}

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

class TajirApp extends StatefulWidget {
  const TajirApp({super.key});
  @override
  State<TajirApp> createState() => _TajirAppState();
}

class _TajirAppState extends State<TajirApp> {
  // Keep the authenticated session when a client switches apps, locks the
  // phone, or closes TAJIR. Supabase persists and refreshes the session.
  // A user is signed out only by choosing the app's explicit Sign out action
  // or when the authentication provider invalidates the session.
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
          return const AuthChoicePage();
        }
        return const AccountRouter();
      },
    );
  }
}


class AuthChoicePage extends StatelessWidget {
  const AuthChoicePage({super.key});

  Widget _choice(BuildContext context, {required IconData icon,
    required String title, required String subtitle, required String button,
    required VoidCallback onPressed}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Icon(icon, size: 42, color: brandGreen),
          const SizedBox(height: 8),
          Text(title, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(subtitle, textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Colors.black54)),
          const SizedBox(height: 12),
          FilledButton(onPressed: onPressed, child: Text(button)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const BrandMark(),
          const SizedBox(height: 12),
          const Text('Welcome to TAJIR',
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('Choose the account that describes how you use TAJIR.',
            textAlign: TextAlign.center),
          const SizedBox(height: 18),
          _choice(context, icon: Icons.admin_panel_settings_outlined,
            title: 'DIRECTORS & WORKERS',
            subtitle: 'For both Directors and all authorised TAJIR staff. Each person signs in with their own registered phone number and PIN. Workers must get an account from a Director.',
            button: 'Staff login',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LoginPage()))),
          const SizedBox(height: 10),
          _choice(context, icon: Icons.agriculture,
            title: 'CLIENTS & FARM SERVICES',
            subtitle: 'For farmers, buyers, sellers, tractor and machinery owners, and drivers. Tractor owners and drivers can also use the marketplace to buy or sell farm products.',
            button: 'Client login / register',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CustomerAuthPage()))),
          const SizedBox(height: 8),
          const Text('Not sure? Choose Client if you are using farm services or buying and selling farm products.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.black54)),
        ]),
      ),
    ))),
  );
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

  Future<void> showForgotPinHelp() async {
    await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Forgot your PIN?'),
      content: const Text('For your security, a forgotten staff PIN must be reset by the TAJIR Director after checking your identity. Contact the Director or an authorised account administrator. Do not share your old PIN with anyone.'),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close'))],
    ));
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
            throw FormatException(data is Map ? (friendlyError(data['error'] ?? 'Something went wrong.') ?? 'Director setup failed.') : 'Director setup failed.');
          }
        }
        await db.auth.signInWithPassword(
          email: tajirLoginEmail(normalized),
          password: staffAuthPassword(pin.text),
        );
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } on FunctionException catch (e) {
      final details = e.details;
      if (mounted) setState(() => error = details is Map ? (friendlyError(details['error'] ?? 'Something went wrong.') ?? e.reasonPhrase ?? 'Director setup failed.') : (e.reasonPhrase ?? 'Director setup failed.'));
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e).replaceFirst('FormatException: ', ''));
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
            Text(setupDirector ? 'Set up Director access' : 'Staff sign in',
              style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 18),
            TextField(controller: phone, keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Your registered staff phone number', hintText: '07XXXXXXXX', border: OutlineInputBorder())),
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
                ? 'One-time setup is only for a pre-approved Director. Workers must ask a Director to create their staff account.'
                : 'Both Directors and authorised workers sign in here using their own registered phone number and four-digit PIN.',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.black54)),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 12),
              child: Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red))),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: FilledButton(
              onPressed: busy ? null : submit,
              child: Text(busy ? 'Please wait…' : setupDirector ? 'Set up and sign in' : 'Sign in'),
            )),
            TextButton(onPressed: busy ? null : showForgotPinHelp,
              child: const Text('Forgot PIN?')),
            TextButton(onPressed: busy ? null : () => setState(() { setupDirector = !setupDirector; error = null; }),
              child: Text(setupDirector ? 'I already set up my PIN — sign in' : 'First time? Set up director PIN')),
            TextButton(onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CustomerAuthPage())),
              child: const Text('Are you a client, tractor owner or driver?')),
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

  Future<void> showForgotPinHelp() async {
    await showDialog<void>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Forgot your PIN?'),
      content: const Text('Contact the TAJIR Director. The Director will confirm your identity and reset your customer PIN from the Customers section. Never share your old PIN.'),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close'))],
    ));
  }

  Future<void> signInCustomerWithPin(SupabaseClient db, String normalizedPhone, String customerPin) async {
    final response = await db.functions.invoke(
      'tajir-customer-login',
      body: {'phone': normalizedPhone, 'pin': customerPin},
    );
    final data = response.data;
    if (response.status != 200 || data is! Map || data['success'] != true || data['token_hash'] == null) {
      throw FormatException(data is Map ? (friendlyError(data['error'] ?? 'Something went wrong.') ?? 'Customer sign-in failed.') : 'Customer sign-in failed.');
    }
    await db.auth.verifyOTP(tokenHash: data['token_hash'].toString(), type: OtpType.magiclink);
  }

  Future<void> submit() async {
    setState(() { busy = true; message = null; });
    try {
      final db = Supabase.instance.client;
      final normalized = normalizeKenyanPhone(phone.text);
      if (createAccount && !RegExp(r'^\d{4}$').hasMatch(pin.text)) {
        throw const FormatException('New customer PIN must contain exactly four digits.');
      }
      if (!createAccount && !RegExp(r'^\d{4}$').hasMatch(pin.text)) {
        throw const FormatException('Enter your four-digit PIN.');
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
          throw FormatException(data is Map ? (friendlyError(data['error'] ?? 'Something went wrong.') ?? 'Customer registration failed.') : 'Customer registration failed.');
        }
        await signInCustomerWithPin(db, normalized, pin.text);
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const CustomerPortalPage()), (route) => false);
      } else {
        await signInCustomerWithPin(db, normalized, pin.text);
        final result = await db.rpc('get_my_account_status');
        final rows = List<Map<String,dynamic>>.from(result);
        if (rows.isEmpty || rows.first['is_customer'] != true) {
          throw const FormatException('No customer account is linked to this phone number. Please register first.');
        }
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const CustomerPortalPage()), (route) => false);
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => message = friendlyError(e));
    } catch (e) {
      if (mounted) setState(() => message = friendlyError(e).replaceFirst('FormatException: ', ''));
    }
    if (mounted) setState(() => busy = false);
  }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('TAJIR client account')),
    body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(20),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440),
        child: Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(
          mainAxisSize: MainAxisSize.min, children: [
            const BrandMark(), const SizedBox(height: 18),
            Text(createAccount ? 'Register as a TAJIR client' : 'Client sign in',
              style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('For farmers, buyers, sellers, tractor and machinery owners, and drivers. Tractor owners and drivers can also buy or sell farm products using this same client account.', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.black54)),
            const SizedBox(height: 10),
            const Text('No OTP or SMS is used. Your phone number is not verified.', textAlign: TextAlign.center,
              style: TextStyle(color: Colors.deepOrange, fontSize: 12)),
            const SizedBox(height: 16),
            if (createAccount) TextField(controller: name, textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Full name', border: OutlineInputBorder())),
            if (createAccount) const SizedBox(height: 12),
            TextField(controller: phone, keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone number', hintText: '07XXXXXXXX', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: pin, keyboardType: TextInputType.number, obscureText: true, maxLength: 4,
              decoration: InputDecoration(labelText: createAccount ? 'Four-digit PIN' : 'PIN', border: const OutlineInputBorder(), counterText: '')),
            if (createAccount) const SizedBox(height: 12),
            if (createAccount) TextField(controller: confirmPin, keyboardType: TextInputType.number, obscureText: true, maxLength: 4,
              decoration: const InputDecoration(labelText: 'Confirm four-digit PIN', border: OutlineInputBorder(), counterText: '')),
            if (message != null) Padding(padding: const EdgeInsets.only(top: 12),
              child: Text(message!, style: const TextStyle(color: Colors.red))),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: FilledButton(onPressed: busy ? null : submit,
              child: Text(busy ? 'Please wait…' : createAccount ? 'Create account' : 'Sign in'))),
            if (!createAccount)
              TextButton(onPressed: busy ? null : showForgotPinHelp,
                child: const Text('Forgot PIN?')),
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
        Text('Customer account unavailable', style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
        SizedBox(height: 10),
        Text('This customer account is not active. Please contact TAJIR support for assistance.', textAlign: TextAlign.center),
      ],
    ))),
  );
}


class BranchRequestPanel extends StatefulWidget {
  const BranchRequestPanel({super.key});
  @override State<BranchRequestPanel> createState() => _BranchRequestPanelState();
}
class _BranchRequestPanelState extends State<BranchRequestPanel> {
  final db=Supabase.instance.client;
  List<Map<String,dynamic>> branches=[],requests=[];
  String? selected,error; bool loading=true,saving=false;
  @override void initState(){super.initState();load();}
  Future<void> load() async {
    if(mounted)setState(()=>loading=true);
    try {
      final r=await Future.wait([
        db.from('branches').select('id,code,name').eq('is_active',true).order('name'),
        db.from('branch_requests').select('id,proposed_name,address,status,rejection_reason').order('created_at',ascending:false).limit(30),
      ]);
      branches=List<Map<String,dynamic>>.from(r[0]);requests=List<Map<String,dynamic>>.from(r[1]);
      if(selected==null||!branches.any((b)=>b['id'].toString()==selected))selected=branches.isEmpty?null:branches.first['id'].toString();
      error=null;
    } catch(e){error=friendlyError(e);}
    if(mounted)setState(()=>loading=false);
  }
  Future<void> choose(String? v) async {
    if(v==null)return;setState(()=>saving=true);
    try {await db.rpc('set_my_default_branch',params:{'p_branch_id':v});selected=v;if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Branch selection saved.')));}
    catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Could not save branch: '+friendlyError(e))));}
    if(mounted)setState(()=>saving=false);
  }
  Future<void> request() async {
    final name=TextEditingController(),code=TextEditingController(),address=TextEditingController(),notes=TextEditingController();
    final ok=await showDialog<bool>(context:context,builder:(d)=>AlertDialog(title:const Text('Request a new branch'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
      TextField(controller:name,decoration:const InputDecoration(labelText:'Branch name *')),
      TextField(controller:code,decoration:const InputDecoration(labelText:'Suggested code (optional)')),
      TextField(controller:address,decoration:const InputDecoration(labelText:'Town / area / address')),
      TextField(controller:notes,maxLines:2,decoration:const InputDecoration(labelText:'Additional details')),
      const Text('A director must approve the request before the branch becomes selectable.',style:TextStyle(fontSize:12)),
    ])),actions:[TextButton(onPressed:()=>Navigator.pop(d,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(d,true),child:const Text('Submit'))]));
    if(ok==true){
      try{
        if(name.text.trim().length<2)throw const FormatException('Enter a branch name.');
        await db.from('branch_requests').insert({'proposed_name':name.text.trim(),'proposed_code':code.text.trim().isEmpty?null:code.text.trim().toUpperCase(),'address':address.text.trim().isEmpty?null:address.text.trim(),'notes':notes.text.trim().isEmpty?null:notes.text.trim(),'submitted_by':db.auth.currentUser!.id});
        if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Branch request sent to the directors.')));
        await load();
      }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Request failed: '+friendlyError(e))));}
    }
    name.dispose();code.dispose();address.dispose();notes.dispose();
  }
  @override Widget build(BuildContext context)=>RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.all(16),children:[
    const Text('Your branch',style:TextStyle(fontSize:21,fontWeight:FontWeight.bold)),
    const Text('Choose the approved branch where you operate.'),
    if(loading)const LinearProgressIndicator(),
    if(branches.isNotEmpty)DropdownButtonFormField<String>(value:selected,decoration:const InputDecoration(labelText:'Select branch',border:OutlineInputBorder()),items:branches.map((b)=>DropdownMenuItem(value:b['id'].toString(),child:Text(b['name'].toString()+' ('+b['code'].toString()+')'))).toList(),onChanged:saving?null:choose),
    OutlinedButton.icon(onPressed:request,icon:const Icon(Icons.add_location_alt),label:const Text('Request a new branch')),
    if(error!=null)Text(error!,style:const TextStyle(color:Colors.red)),
    const Divider(height:28),const Text('Your branch requests',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
    if(!loading&&requests.isEmpty)const Text('No branch requests submitted.'),
    ...requests.map((r)=>Card(child:ListTile(title:Text(r['proposed_name'].toString()),subtitle:Text((r['address']??'Address not provided').toString()+(r['rejection_reason']==null?'':' • '+r['rejection_reason'].toString())),trailing:Text(r['status'].toString().toUpperCase())))),
  ]));
}

class AccountSecurityPage extends StatefulWidget {
  const AccountSecurityPage({super.key});
  @override State<AccountSecurityPage> createState() => _AccountSecurityPageState();
}
class _AccountSecurityPageState extends State<AccountSecurityPage> {
  final currentPin = TextEditingController(), newPin = TextEditingController(), confirmPin = TextEditingController();
  bool isCustomer = false, loading = true, busy = false;
  String? error;
  @override void initState() { super.initState(); loadAccount(); }
  @override void dispose() { currentPin.dispose(); newPin.dispose(); confirmPin.dispose(); super.dispose(); }
  Future<void> loadAccount() async {
    try {
      final db = Supabase.instance.client;
      final row = await db.from('customers').select('id').eq('profile_id', db.auth.currentUser!.id).maybeSingle();
      if (mounted) setState(() { isCustomer = row != null; loading = false; });
    } catch (e) { if (mounted) setState(() { error = friendlyError(e); loading = false; }); }
  }
  Future<void> savePin() async {
    final oldPin = currentPin.text.trim(), nextPin = newPin.text.trim();
    if (oldPin.length != 4 || int.tryParse(oldPin) == null || nextPin.length != 4 || int.tryParse(nextPin) == null) { setState(() => error = 'Enter your current PIN and a new four-digit PIN.'); return; }
    if (nextPin != confirmPin.text.trim()) { setState(() => error = 'The new PIN entries do not match.'); return; }
    if (oldPin == nextPin) { setState(() => error = 'Choose a different PIN from your current PIN.'); return; }
    setState(() { busy = true; error = null; });
    try {
      final db = Supabase.instance.client;
      if (isCustomer) {
        final response = await db.functions.invoke('tajir-customer-change-pin', body: {'current_pin': oldPin, 'new_pin': nextPin});
        final data = response.data;
        if (response.status != 200 || data is! Map || data['success'] != true) throw FormatException(data is Map ? (friendlyError(data['error'] ?? 'Something went wrong.') ?? 'PIN update failed.') : 'PIN update failed.');
      } else {
        await db.auth.updateUser(UserAttributes(password: staffAuthPassword(nextPin), currentPassword: staffAuthPassword(oldPin)));
      }
      if (!mounted) return;
      currentPin.clear(); newPin.clear(); confirmPin.clear();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Your PIN has been changed successfully.')));
    } on AuthException catch (e) { if (mounted) setState(() => error = friendlyError(e)); }
      catch (e) { if (mounted) setState(() => error = friendlyError(e).replaceFirst('FormatException: ', '')); }
    if (mounted) setState(() => busy = false);
  }
  Future<void> forgotPin() async {
    await showDialog<void>(context: context, builder: (d) => AlertDialog(
      title: const Text('Forgot your PIN?'),
      content: Text(isCustomer ? 'Contact the TAJIR Director to verify your identity and reset your customer PIN from Customers. Never share your old PIN.' : 'Contact the TAJIR Director or authorised account administrator for identity verification and a secure PIN reset. Do not share your current PIN.'),
      actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Close'))],
    ));
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Account security')),
    body: loading ? const Center(child: CircularProgressIndicator()) : ListView(padding: const EdgeInsets.all(20), children: [
      const Icon(Icons.shield_outlined, size: 52, color: brandGreen),
      const Text('Change your four-digit PIN', textAlign: TextAlign.center, style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
      const Text('Your PIN is private. Do not share it with anyone.', textAlign: TextAlign.center),
      const SizedBox(height: 20),
      TextField(controller: currentPin, obscureText: true, keyboardType: TextInputType.number, maxLength: 4, decoration: const InputDecoration(labelText: 'Current PIN', border: OutlineInputBorder(), counterText: '')),
      const SizedBox(height: 10),
      TextField(controller: newPin, obscureText: true, keyboardType: TextInputType.number, maxLength: 4, decoration: const InputDecoration(labelText: 'New four-digit PIN', border: OutlineInputBorder(), counterText: '')),
      const SizedBox(height: 10),
      TextField(controller: confirmPin, obscureText: true, keyboardType: TextInputType.number, maxLength: 4, decoration: const InputDecoration(labelText: 'Confirm new PIN', border: OutlineInputBorder(), counterText: '')),
      if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
      const SizedBox(height: 14),
      FilledButton(onPressed: busy ? null : savePin, child: Text(busy ? 'Saving…' : 'Change PIN')),
      TextButton(onPressed: busy ? null : forgotPin, child: const Text('Forgot PIN?')),
    ]),
  );
}
class CustomerPortalPage extends StatefulWidget {
 const CustomerPortalPage({super.key});
 @override State<CustomerPortalPage> createState()=>_CustomerPortalPageState();
}
class _CustomerPortalPageState extends State<CustomerPortalPage>{
 Map<String,dynamic>? c;
 bool busy=true;
 String? error;
 int? selectedSection;

 @override void initState(){super.initState();load();}

 Future<void> load()async{
  if(mounted)setState(()=>busy=true);
  try{
   final db=Supabase.instance.client;
   final userId=db.auth.currentUser!.id;
   final r=await db.from('customers').select('id,full_name,active,marketplace_can_buy,marketplace_can_sell').eq('profile_id',userId).maybeSingle();
   if(r==null||r['active']!=true)throw const FormatException('Customer account unavailable or inactive.');
   if(mounted)setState(()=>c=Map<String,dynamic>.from(r));
  }catch(e){if(mounted)setState(()=>error=friendlyError(e));}
  if(mounted)setState(()=>busy=false);
 }

 String sectionTitle(int section)=>const [
  'Buy Tajir Products','Sell Products','Purchase Requests',
  'Tractor & Machinery Services','My Bookings','My Branch'
 ][section];

 Widget sectionPage(int section){
  final buy=c!['marketplace_can_buy']==true;
  final sell=c!['marketplace_can_sell']==true;
  switch(section){
   case 0:
    // Show every active marketplace listing. Do not silently restrict buyers
    // to fertilizer when their account's general buying permission is off.
    return CustomerMarketPage(customer:c!,mode:'buy',fertilizerOnly:false);
   case 1:
    return sell
     ?CustomerMarketPage(customer:c!,mode:'sell')
     :const CustomerLockedPage(title:'Sell products',message:'The Director has not enabled selling on your account yet.',imageUrl:TajirPictures.sell,icon:Icons.storefront_outlined);
   case 2:
    return CustomerMarketPage(customer:c!,mode:'requests');
   case 3:
    return CustomerTractorPage();
   case 4:
    return CustomerTractorBookingsPage();
   case 5:
    return const BranchRequestPanel();
   default:
    return const SizedBox.shrink();
  }
 }

 Widget homeTile({required String title,required String subtitle,required String imageUrl,required IconData icon,required int section,bool locked=false,bool large=false}){
  return TajirImageTile(
   title:title,subtitle:subtitle,imageUrl:imageUrl,icon:icon,locked:locked,large:large,
   onTap:()=>setState(()=>selectedSection=section),
  );
 }

 @override Widget build(BuildContext context){
  if(busy)return const Scaffold(body:Center(child:CircularProgressIndicator()));
  if(c==null)return Scaffold(
   appBar:AppBar(title:const Text('TAJIR')),
   body:Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
    Text(error??'Account unavailable'),
    FilledButton(onPressed:load,child:const Text('Retry')),
    TextButton(onPressed:()=>Supabase.instance.client.auth.signOut(),child:const Text('Sign out'))
   ]))
  );

  final sell=c!['marketplace_can_sell']==true;
  final onSection=selectedSection!=null;
  return Scaffold(
   appBar:AppBar(
    leading:onSection?IconButton(
     tooltip:'Back to dashboard',
     icon:const Icon(Icons.arrow_back),
     onPressed:()=>setState(()=>selectedSection=null),
    ):null,
    title:Text(onSection?sectionTitle(selectedSection!):'TAJIR - '+c!['full_name'].toString()),
    actions:[
     IconButton(tooltip:'Account security',onPressed:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>const AccountSecurityPage())),icon:const Icon(Icons.lock_reset)),
     IconButton(tooltip:'Refresh',onPressed:onSection?()=>setState((){}):load,icon:const Icon(Icons.refresh)),
     IconButton(tooltip:'Sign out',onPressed:()=>Supabase.instance.client.auth.signOut(),icon:const Icon(Icons.logout))
    ],
   ),
   body:onSection
    ?sectionPage(selectedSection!)
    :ListView(padding:const EdgeInsets.all(12),children:[
      Row(children:[
       Expanded(child:homeTile(title:'BUY TAJIR PRODUCTS',subtitle:'Browse all products available in the marketplace',imageUrl:TajirPictures.buy,icon:Icons.shopping_basket_outlined,section:0)),
       const SizedBox(width:8),
       Expanded(child:homeTile(title:'SELL PRODUCTS',subtitle:sell?'List any product and set your price':'Access locked',imageUrl:TajirPictures.sell,icon:Icons.storefront_outlined,section:1,locked:!sell))
      ]),
      const SizedBox(height:10),
      homeTile(title:'TRACTOR & MACHINERY SERVICES',subtitle:'Book ploughing, planting, harvesting and more',imageUrl:TajirPictures.tractor,icon:Icons.agriculture,section:3,large:true),
      const SizedBox(height:10),
      Row(children:[
       Expanded(child:homeTile(title:'MY BOOKINGS',subtitle:'Track farm jobs',imageUrl:TajirPictures.bookings,icon:Icons.calendar_month_outlined,section:4)),
       const SizedBox(width:8),
       Expanded(child:homeTile(title:'MY BRANCH',subtitle:'Choose your branch',imageUrl:TajirPictures.branch,icon:Icons.location_on_outlined,section:5))
      ]),
      const SizedBox(height:10),
      homeTile(title:'PURCHASE REQUESTS',subtitle:'View and follow up your product requests',imageUrl:TajirPictures.orders,icon:Icons.receipt_long_outlined,section:2)
    ])
  );
 }
}

class RepairMarketplacePage extends StatefulWidget {
 const RepairMarketplacePage({super.key});
 @override State<RepairMarketplacePage> createState()=>_RepairMarketplacePageState();
}
class _RepairMarketplacePageState extends State<RepairMarketplacePage> with SingleTickerProviderStateMixin {
 late final TabController tabs=TabController(length:2,vsync:this);
 final db=Supabase.instance.client;
 List<Map<String,dynamic>> mechanics=[],parts=[];
 bool busy=true;String? error;
 @override void initState(){super.initState();load();}
 @override void dispose(){tabs.dispose();super.dispose();}
 Future<void> load() async {
  setState(()=>busy=true);
  try {
   final results=await Future.wait([
    db.from('mechanic_profiles').select('id,business_name,phone,location,services').eq('status','approved').order('business_name'),
    db.from('auto_spares_inventory').select('id,shop_id,part_name,part_reference,description,quantity,unit,price_kes,auto_spares_profiles(shop_name,phone,location)').eq('status','active').gt('quantity',0).order('part_name')
   ]);
   mechanics=List<Map<String,dynamic>>.from(results[0]);
   parts=List<Map<String,dynamic>>.from(results[1]);
   error=null;
  } catch(e){error=friendlyError(e);}
  if(mounted)setState(()=>busy=false);
 }
 Future<void> requestRepair(Map<String,dynamic> mechanic) async {
  final issue=TextEditingController(),place=TextEditingController();
  final ok=await showDialog<bool>(context:context,builder:(x)=>AlertDialog(
   title:Text("Request ${mechanic['business_name']}"),
   content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
    TextField(controller:issue,maxLines:3,decoration:const InputDecoration(labelText:'Describe the tractor problem')),
    TextField(controller:place,decoration:const InputDecoration(labelText:'Tractor location'))
   ])),
   actions:[TextButton(onPressed:()=>Navigator.pop(x,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(x,true),child:const Text('Send request'))]
  ));
  if(ok==true) {
   try {
    final owner=await db.from('tractor_owner_profiles').select('id').eq('profile_id',db.auth.currentUser!.id).maybeSingle();
    if(owner==null) throw const FormatException('This login is not registered as a tractor owner. Please register the tractor-owner profile first.');
    if(issue.text.trim().isEmpty||place.text.trim().isEmpty) throw const FormatException('Enter the problem and tractor location.');
    final job='TR-${DateTime.now().millisecondsSinceEpoch}';
    await db.from('tractor_repair_jobs').insert({'job_number':job,'owner_profile_id':owner['id'],'owner_user_id':db.auth.currentUser!.id,'mechanic_id':mechanic['id'],'issue_description':issue.text.trim(),'location':place.text.trim()});
    if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Repair request sent. Reference: $job')));
   } catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(friendlyError(e))));}
  }
  issue.dispose();place.dispose();
 }
 @override Widget build(BuildContext context)=>Column(children:[
  Material(color:Colors.white,child:TabBar(controller:tabs,labelColor:brandGreen,tabs:const [Tab(icon:Icon(Icons.build),text:'Find a mechanic'),Tab(icon:Icon(Icons.store),text:'Auto spares')])),
  if(busy)const LinearProgressIndicator(),
  if(error!=null)Padding(padding:const EdgeInsets.all(12),child:Text(error!,style:const TextStyle(color:Colors.red))),
  Expanded(child:TabBarView(controller:tabs,children:[
   RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.all(12),children:[
    const Text('Choose a mechanic',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
    const Text('Browse approved mechanics and request help for your tractor.'),
    if(!busy&&mechanics.isEmpty)const Padding(padding:EdgeInsets.all(20),child:Text('No approved mechanics are listed yet.')),
    ...mechanics.map((m)=>Card(child:ListTile(isThreeLine:true,leading:const CircleAvatar(child:Icon(Icons.handyman)),title:Text(m['business_name'].toString()),subtitle:Text('${m['location']} • ${m['phone']}\\n${(m['services'] as List).join(', ')}'),trailing:FilledButton(onPressed:()=>requestRepair(m),child:const Text('Choose')))))
   ])),
   RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.all(12),children:[
    const Text('Available spare parts',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
    const Text('Parts listed by approved auto-spares shops.'),
    if(!busy&&parts.isEmpty)const Padding(padding:EdgeInsets.all(20),child:Text('No spare parts are listed yet.')),
    ...parts.map((p){final shop=(p['auto_spares_profiles'] as Map?)?.cast<String,dynamic>()??{};return Card(child:ListTile(leading:const CircleAvatar(child:Icon(Icons.settings)),title:Text(p['part_name'].toString()),subtitle:Text('${shop['shop_name']??'Auto spares'} • ${shop['location']??''}\\nRef: ${p['part_reference']??'Not supplied'} • Stock: ${p['quantity']} ${p['unit']}'),trailing:Text('KES ${p['price_kes']}',style:const TextStyle(fontWeight:FontWeight.bold))));})
   ]))
  ]))
 ]);
}

class TajirPictures {
 static const buy='https://images.unsplash.com/photo-1500382017468-9049fed747ef?w=900&auto=format&fit=crop&q=75';
 static const sell='https://images.unsplash.com/photo-1574323347407-f5e1ad6d020b?w=900&auto=format&fit=crop&q=75';
 static const tractor='https://images.unsplash.com/photo-1592982537447-6f2a6a0c6f6b?w=1200&auto=format&fit=crop&q=75';
 static const bookings='https://images.unsplash.com/photo-1506784983877-45594efa4cbe?w=900&auto=format&fit=crop&q=75';
 static const branch='https://images.unsplash.com/photo-1500382017468-9049fed747ef?w=900&auto=format&fit=crop&q=75';
 static const orders='https://images.unsplash.com/photo-1542838132-92c53300491e?w=900&auto=format&fit=crop&q=75';
}
class TajirImageTile extends StatelessWidget {
 final String title,subtitle,imageUrl; final IconData icon; final VoidCallback onTap; final bool locked,large;
 const TajirImageTile({super.key,required this.title,required this.subtitle,required this.imageUrl,required this.icon,required this.onTap,this.locked=false,this.large=false});
 @override Widget build(BuildContext context)=>Material(
  color:Colors.white,borderRadius:BorderRadius.circular(18),clipBehavior:Clip.antiAlias,
  child:InkWell(onTap:onTap,child:Container(
   height:large?132:112,
   decoration:BoxDecoration(borderRadius:BorderRadius.circular(18),boxShadow:[BoxShadow(color:Colors.black.withOpacity(.08),blurRadius:8)]),
   child:Stack(fit:StackFit.expand,children:[
    Image.network(imageUrl,fit:BoxFit.cover,errorBuilder:(_,__,___)=>Container(color:const Color(0xFFE4EEE5),child:Icon(icon,size:42,color:brandGreen))),
    Container(decoration:BoxDecoration(gradient:LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Colors.black.withOpacity(.08),Colors.black.withOpacity(.78)]))),
    Positioned(left:12,right:10,bottom:10,child:Row(crossAxisAlignment:CrossAxisAlignment.end,children:[
     Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
      Text(title,style:TextStyle(color:Colors.white,fontWeight:FontWeight.w900,fontSize:large?16:14,letterSpacing:.3)),
      const SizedBox(height:3),Text(subtitle,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Colors.white,fontSize:11,fontWeight:FontWeight.w500))
     ])),
     if(locked)const Icon(Icons.lock,color:Colors.white,size:22) else const Icon(Icons.arrow_forward_rounded,color:Colors.white,size:22)
    ])),
   ])
  ))
 );
}
class CustomerLockedPage extends StatelessWidget {
 final String title,message,imageUrl; final IconData icon;
 const CustomerLockedPage({super.key,required this.title,required this.message,required this.imageUrl,required this.icon});
 @override Widget build(BuildContext context)=>Center(child:SingleChildScrollView(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[
  ClipRRect(borderRadius:BorderRadius.circular(22),child:Image.network(imageUrl,height:190,width:double.infinity,fit:BoxFit.cover,errorBuilder:(_,__,___)=>Container(height:190,color:const Color(0xFFEAF4EC),child:Icon(icon,size:64,color:brandGreen)))),
  const SizedBox(height:20),Text(title,style:const TextStyle(fontSize:23,fontWeight:FontWeight.bold)),
  const SizedBox(height:8),Text(message,textAlign:TextAlign.center,style:const TextStyle(fontSize:15,color:Colors.black54)),
  const SizedBox(height:14),const Row(mainAxisAlignment:MainAxisAlignment.center,children:[Icon(Icons.admin_panel_settings_outlined,color:brandGreen),SizedBox(width:7),Text('Please contact the TAJIR Director to request access.',textAlign:TextAlign.center,style:TextStyle(color:brandGreen,fontWeight:FontWeight.w600))])
 ])));
}
class CustomerMarketPage extends StatefulWidget{
 final Map<String,dynamic> customer;final String mode;final bool fertilizerOnly;
 const CustomerMarketPage({super.key,required this.customer,required this.mode,this.fertilizerOnly=false});
 @override State<CustomerMarketPage> createState()=>_CustomerMarketPageState();
}
class _CustomerMarketPageState extends State<CustomerMarketPage>{
 List<Map<String,dynamic>> rows=[];bool busy=true;String? error;
 @override void initState(){super.initState();load();}
 Future<void> load()async{
  if(mounted)setState(()=>busy=true);
  try{
   final db=Supabase.instance.client;
   dynamic r;
   if(widget.mode=='buy'){
    // The buyer catalogue is TAJIR's actual branch stock, not seller listings.
    r=await db.rpc('customer_list_tajir_products');
   }else if(widget.mode=='sell'){
    r=await db.from('marketplace_listings').select('id,seller_customer_id,product_name,description,quantity,unit,price_per_unit,location,status').eq('seller_customer_id',widget.customer['id']).order('created_at',ascending:false);
   }else{
    final marketplaceRows=await db.from('marketplace_purchase_requests').select('id,buyer_customer_id,listing_id,quantity,message,status,created_at,listing:marketplace_listings!marketplace_purchase_requests_listing_id_fkey(product_name,unit,seller_customer_id)').order('created_at',ascending:false);
    final tajirRows=await db.from('customer_product_requests').select('id,quantity_requested,note,status,created_at,products(name),product_variants(variant_name)').order('created_at',ascending:false);
    r=[
     ...List<Map<String,dynamic>>.from(marketplaceRows),
     ...List<Map<String,dynamic>>.from(tajirRows).map((x)=>{...x,'_is_tajir_request':true}),
    ]..sort((a,b)=>DateTime.parse(b['created_at'].toString()).compareTo(DateTime.parse(a['created_at'].toString())));
   }
   if(mounted){
    var loaded=List<Map<String,dynamic>>.from(r);
    if(widget.mode=='buy'){
     final unique=<String,Map<String,dynamic>>{};
     for(final item in loaded){
      final key=(item['product_variant_id']??'').toString();
      if(key.isNotEmpty)unique.putIfAbsent(key,()=>item);
     }
     loaded=unique.values.toList()..sort((x,y)=>(x['product_name']??'').toString().compareTo((y['product_name']??'').toString()));
    }
    setState(()=>{rows=loaded,error=null});
   }
  }catch(e){if(mounted)setState(()=>error=friendlyError(e));}
  if(mounted)setState(()=>busy=false);
 }
 Future<void> requestTajirProduct(Map<String,dynamic> item)async{
  final quantity=TextEditingController(text:'1');
  final note=TextEditingController();
  final variant=(item['variant_name']??'').toString();
  final product=(item['product_name']??'Product').toString();
  final title=variant.isNotEmpty&&variant.toLowerCase()!=product.toLowerCase()?product+' • '+variant:product;
  final ok=await showDialog<bool>(context:context,builder:(x)=>AlertDialog(
   title:Text('Select $title'),
   content:Column(mainAxisSize:MainAxisSize.min,children:[
    TextField(controller:quantity,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Quantity you need')),
    const SizedBox(height:8),
    TextField(controller:note,maxLines:2,decoration:const InputDecoration(labelText:'Note (optional)')),
   ]),
   actions:[TextButton(onPressed:()=>Navigator.pop(x,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(x,true),child:const Text('Send request'))],
  ));
  if(ok==true){
   try{
    final amount=double.tryParse(quantity.text.trim());
    if(amount==null||amount<=0)throw const FormatException('Enter a quantity greater than zero.');
    await Supabase.instance.client.from('customer_product_requests').insert({
     'customer_id':widget.customer['id'],
     'product_id':item['product_id'],
     'product_variant_id':item['product_variant_id'],
     'quantity_requested':amount,
     'note':note.text.trim().isEmpty?null:note.text.trim(),
    });
    if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Your product request has been sent. TAJIR will confirm availability.')));
   }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(friendlyError(e))));}
  }
  quantity.dispose();note.dispose();
 }
 Future<void> createListing()async{final p=TextEditingController(),q=TextEditingController(),u=TextEditingController(text:'bag'),v=TextEditingController(),l=TextEditingController(),d=TextEditingController();final ok=await showDialog<bool>(context:context,builder:(x)=>AlertDialog(title:const Text('List product'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:p,decoration:const InputDecoration(labelText:'Product')),TextField(controller:d,decoration:const InputDecoration(labelText:'Description')),TextField(controller:q,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Quantity')),TextField(controller:u,decoration:const InputDecoration(labelText:'Unit')),TextField(controller:v,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Price per unit KES')),TextField(controller:l,decoration:const InputDecoration(labelText:'Location'))])),actions:[TextButton(onPressed:()=>Navigator.pop(x,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(x,true),child:const Text('Publish'))]));if(ok==true){try{await Supabase.instance.client.from('marketplace_listings').insert({'seller_customer_id':widget.customer['id'],'product_name':p.text.trim(),'description':d.text.trim(),'quantity':double.parse(q.text),'unit':u.text.trim().isEmpty?'bag':u.text.trim(),'price_per_unit':double.parse(v.text),'location':l.text.trim(),'status':'active'});await load();}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(friendlyError(e))));}}p.dispose();q.dispose();u.dispose();v.dispose();l.dispose();d.dispose();}
 Future<void> requestBuy(Map<String,dynamic> item)async{final q=TextEditingController(text:'1');final ok=await showDialog<bool>(context:context,builder:(x)=>AlertDialog(title:Text('Buy '+item['product_name'].toString()),content:TextField(controller:q,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Quantity')),actions:[TextButton(onPressed:()=>Navigator.pop(x,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(x,true),child:const Text('Send request'))]));if(ok==true){try{final n=double.parse(q.text);if(n<=0||n>(item['quantity'] as num).toDouble())throw const FormatException('Quantity exceeds available stock.');await Supabase.instance.client.from('marketplace_purchase_requests').insert({'listing_id':item['id'],'buyer_customer_id':widget.customer['id'],'quantity':n});if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Purchase request sent.')));}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(friendlyError(e))));}}q.dispose();}
 Future<void> change(Map<String,dynamic> r,String value,bool listing)async{try{await Supabase.instance.client.from(listing?'marketplace_listings':'marketplace_purchase_requests').update({'status':value}).eq('id',r['id']);await load();}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(friendlyError(e))));}}
 @override Widget build(BuildContext context)=>RefreshIndicator(
  onRefresh:load,
  child:ListView(padding:const EdgeInsets.all(16),children:[
   Row(children:[
    Expanded(child:Text(widget.mode=='buy'?'TAJIR products available':widget.mode=='sell'?'Your listings':'Purchase requests',style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold))),
    if(widget.mode=='sell')FilledButton(onPressed:createListing,child:const Text('Add listing'))
   ]),
   if(busy)const LinearProgressIndicator(),
   if(error!=null)Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Text(error!,style:const TextStyle(color:Colors.red))),
   if(!busy&&rows.isEmpty)Padding(padding:const EdgeInsets.symmetric(vertical:20),child:Text(widget.mode=='buy'?'No TAJIR stock is currently available. Please check again or contact your branch.':'No marketplace records yet.')),
   ...rows.map((r){
    if(widget.mode=='buy'){
     final variant=(r['variant_name']??'').toString();
     final product=(r['product_name']??'Product').toString();
     final title=variant.isNotEmpty&&variant.toLowerCase()!=product.toLowerCase()?product+' • '+variant:product;
     return Card(child:ListTile(
      leading:const CircleAvatar(child:Icon(Icons.inventory_2_outlined)),
      title:Text(title),
      subtitle:Text('Choose this product to send a request'),
      trailing:FilledButton.tonal(onPressed:()=>requestTajirProduct(r),child:const Text('Select'))
     ));
    }
    if(widget.mode=='requests'){
     if(r['_is_tajir_request']==true){
      final p=(r['products'] as Map?)?.cast<String,dynamic>()??{};
      final v=(r['product_variants'] as Map?)?.cast<String,dynamic>()??{};
      final name=(p['name']??'TAJIR product').toString();
      final variant=(v['variant_name']??'').toString();
      return Card(child:ListTile(
       leading:const Icon(Icons.inventory_2_outlined),
       title:Text(variant.isEmpty?name:'$name • $variant'),
       subtitle:Text('Quantity requested: '+r['quantity_requested'].toString()+' • '+r['status'].toString()),
       trailing:const Icon(Icons.hourglass_top),
      ));
     }
     final l=(r['listing'] as Map?)?.cast<String,dynamic>()??{};
     final seller=l['seller_customer_id']==widget.customer['id'];
     return Card(child:ListTile(
      title:Text((l['product_name']??'Purchase request').toString()),
      subtitle:Text(r['quantity'].toString()+' '+(l['unit']??'').toString()+' • '+r['status'].toString()),
      trailing:seller&&r['status']=='pending'?PopupMenuButton<String>(onSelected:(v)=>change(r,v,false),itemBuilder:(_)=>const [PopupMenuItem(value:'accepted',child:Text('Accept')),PopupMenuItem(value:'declined',child:Text('Decline'))]):seller&&r['status']=='accepted'?TextButton(onPressed:()=>change(r,'completed',false),child:const Text('Complete')):null
     ));
    }
    return Card(child:ListTile(
     title:Text(r['product_name'].toString()),
     subtitle:Text(r['quantity'].toString()+' '+r['unit'].toString()+' • KES '+r['price_per_unit'].toString()+' • '+r['location'].toString()),
     trailing:PopupMenuButton<String>(onSelected:(v)=>change(r,v,true),itemBuilder:(_)=>const [PopupMenuItem(value:'active',child:Text('Active')),PopupMenuItem(value:'paused',child:Text('Pause')),PopupMenuItem(value:'sold',child:Text('Sold'))])
    ));
   })
  ])
 );
}
class CustomerTractorPage extends StatefulWidget{@override State<CustomerTractorPage> createState()=>_CustomerTractorPageState();}
class _CustomerTractorPageState extends State<CustomerTractorPage>{
 List<Map<String,dynamic>> tractors=[];bool busy=true;String? tractor;String service='ploughing';final location=TextEditingController(),acres=TextEditingController();DateTime date=DateTime.now().add(const Duration(days:1));
 @override void initState(){super.initState();load();}
 @override void dispose(){location.dispose();acres.dispose();super.dispose();}
 Future<void> load()async{try{final r=await Supabase.instance.client.rpc('customer_list_tractor_services');tractors=List<Map<String,dynamic>>.from(r);tractor=tractors.isEmpty?null:tractors.first['tractor_id'].toString();}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(friendlyError(e))));}if(mounted)setState(()=>busy=false);}
 Future<void> book()async{try{if(tractor==null)throw const FormatException('No tractor available.');if(location.text.trim().length<3)throw const FormatException('Enter farm location.');final r=await Supabase.instance.client.rpc('customer_book_tractor_service',params:{'p_tractor_id':tractor,'p_service_type':service,'p_service_location':location.text.trim(),'p_area_acres':acres.text.trim().isEmpty?null:double.parse(acres.text),'p_booked_for':date.toUtc().toIso8601String(),'p_notes':null});if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Booking submitted: '+(r as List).first['job_number'].toString())));}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(friendlyError(e))));}}
 @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(18),children:[const Text('Book tractor service',style:TextStyle(fontSize:21,fontWeight:FontWeight.bold)),if(busy)const LinearProgressIndicator(),if(tractors.isNotEmpty)DropdownButtonFormField<String>(value:tractor,items:tractors.map((t)=>DropdownMenuItem(value:t['tractor_id'].toString(),child:Text(t['selection_label'].toString()))).toList(),onChanged:(v)=>setState(()=>tractor=v),decoration:const InputDecoration(labelText:'Available tractor')),if(tractors.isEmpty&&!busy)const Text('No tractors available.'),DropdownButtonFormField<String>(value:service,items:const [DropdownMenuItem(value:'ploughing',child:Text('Ploughing')),DropdownMenuItem(value:'planting',child:Text('Planting')),DropdownMenuItem(value:'harrowing',child:Text('Harrowing')),DropdownMenuItem(value:'transport',child:Text('Transport')),DropdownMenuItem(value:'other',child:Text('Other'))],onChanged:(v)=>setState(()=>service=v??'ploughing'),decoration:const InputDecoration(labelText:'Service')),TextField(controller:location,decoration:const InputDecoration(labelText:'Farm location')),TextField(controller:acres,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Acres')),ListTile(title:Text('Booking date: '+date.toLocal().toString().split(' ')[0]),trailing:TextButton(onPressed:()async{final d=await showDatePicker(context:context,initialDate:date,firstDate:DateTime.now(),lastDate:DateTime.now().add(const Duration(days:365)));if(d!=null)setState(()=>date=d);},child:const Text('Choose'))),FilledButton(onPressed:busy||tractors.isEmpty?null:book,child:const Text('Book service'))]);
}
class CustomerTractorBookingsPage extends StatefulWidget{@override State<CustomerTractorBookingsPage> createState()=>_CustomerTractorBookingsPageState();}
class _CustomerTractorBookingsPageState extends State<CustomerTractorBookingsPage>{
 List<Map<String,dynamic>> rows=[];bool busy=true;
 @override void initState(){super.initState();load();}
 Future<void> load()async{try{final r=await Supabase.instance.client.rpc('customer_list_tractor_bookings');if(mounted)setState(()=>rows=List<Map<String,dynamic>>.from(r));}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(friendlyError(e))));}if(mounted)setState(()=>busy=false);}
 @override Widget build(BuildContext context)=>RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.all(16),children:[const Text('Tractor booking history',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),if(busy)const LinearProgressIndicator(),if(!busy&&rows.isEmpty)const Text('No bookings yet.'),...rows.map((r)=>Card(child:ListTile(title:Text(r['service_type'].toString()+' • '+r['job_number'].toString()),subtitle:Text(r['service_location'].toString()+' • '+r['status'].toString()),trailing:Text('KES '+r['total_charge'].toString()))))]));
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
        return const CustomerPortalPage();
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
  bool director = false;
  List<Widget> get pages => [DashboardPage(onOpenTractor: () => selectPage(5), onOpenItems: () => selectPage(3)), const PurchasePage(), const SalePage(), const StockPage(), const CustomersPage(), const TractorServicesPage(), const FinancialRecordsPage()];
  List<String> get labels => ['Dashboard','Purchases','Sales','Stock','Customers','Tractor Services', if (director) 'Financial Records'];
  List<IconData> get icons => [Icons.dashboard,Icons.add_shopping_cart,Icons.point_of_sale,Icons.inventory_2,Icons.people,Icons.agriculture, if (director) Icons.account_balance];
  @override void initState() { super.initState(); loadAccess(); }
  Future<void> loadAccess() async {
    try {
      final rows = await Supabase.instance.client.from('user_role_assignments').select('app_roles(code)').eq('user_id', Supabase.instance.client.auth.currentUser!.id).eq('is_active', true);
      final allowed = rows.any((r) => r['app_roles'] is Map && (r['app_roles'] as Map)['code'] == 'director');
      if (mounted) setState(() { director = allowed; if (!allowed && index == 6) index = 0; });
    } catch (_) { if (mounted) setState(() => director = false); }
  }
  void selectPage(int value) { if (value >= 0 && value < pages.length) setState(() => index = value); }
  void openMoreMenu() {
    showModalBottomSheet<void>(context: context, builder: (sheetContext) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.people), title: const Text('Customers'), selected: index == 4, onTap: () { Navigator.pop(sheetContext); selectPage(4); }),
      ListTile(leading: const Icon(Icons.agriculture), title: const Text('Tractor Services'), selected: index == 5, onTap: () { Navigator.pop(sheetContext); selectPage(5); }),
      if (director) ListTile(leading: const Icon(Icons.account_balance), title: const Text('Financial Records'), selected: index == 6, onTap: () { Navigator.pop(sheetContext); selectPage(6); }),
      const SizedBox(height: 8),
    ])));
  }
  @override Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 800;
    return Scaffold(
      appBar: AppBar(title: const Text('TAJIR'), actions: [IconButton(tooltip: 'Account security', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AccountSecurityPage())), icon: const Icon(Icons.lock_reset)), IconButton(tooltip: 'Sign out', onPressed: () => Supabase.instance.client.auth.signOut(), icon: const Icon(Icons.logout))]),
      body: Row(children: [
        if (wide) NavigationRail(selectedIndex: index, onDestinationSelected: selectPage, labelType: NavigationRailLabelType.all, destinations: List.generate(labels.length, (i) => NavigationRailDestination(icon: Icon(icons[i]), label: Text(labels[i])))),
        Expanded(child: IndexedStack(index: index, children: pages)),
      ]),
      bottomNavigationBar: wide ? null : NavigationBar(
        selectedIndex: index < 4 ? index : 4,
        onDestinationSelected: (v) { if (v == 4) { openMoreMenu(); } else { selectPage(v); } },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.add_shopping_cart), label: 'Purchases'),
          NavigationDestination(icon: Icon(Icons.point_of_sale), label: 'Sales'),
          NavigationDestination(icon: Icon(Icons.inventory_2), label: 'Stock'),
          NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
        ],
      ),
    );
  }
}

void _noDashboardAction() {}

class DashboardPage extends StatefulWidget {
  final VoidCallback? onOpenTractor;
  final VoidCallback? onOpenItems;
  const DashboardPage({super.key, this.onOpenTractor, this.onOpenItems});
  @override State<DashboardPage> createState() => _DashboardPageState();
}
class _DashboardPageState extends State<DashboardPage> {
  String role = 'Loading role…'; List<Map<String,dynamic>> stock = [], branches = [], pendingRequests = []; String? error, selectedBranch; bool director = false;
  @override void initState() { super.initState(); load(); }
  Future<void> load() async {
    try {
      final db = Supabase.instance.client;
      final userId = db.auth.currentUser!.id;
      final p = await db.from('profiles').select('display_name').eq('id', userId).single();
      final assigned = await db.from('user_role_assignments').select('app_roles(name,code)').eq('user_id', userId).eq('is_active', true);
      final roleData = assigned.isNotEmpty ? assigned.first['app_roles'] : null;
      final roleName = roleData is Map ? (roleData['name'] ?? roleData['code'] ?? 'User').toString() : 'User';
      director = assigned.any((r) => r['app_roles'] is Map && (r['app_roles'] as Map)['code']=='director');
      final s = await db.rpc('get_stock_balances');
      final branchRows = await db.from('branches').select('id,code,name').eq('is_active',true).order('name');
      branches=List<Map<String,dynamic>>.from(branchRows);
      if(selectedBranch==null||!branches.any((b)=>b['id'].toString()==selectedBranch))selectedBranch=branches.isEmpty?null:branches.first['id'].toString();
      if(director){final q=await db.from('branch_requests').select('id,proposed_name,proposed_code,address,notes').eq('status','pending').order('created_at');pendingRequests=List<Map<String,dynamic>>.from(q);}
      if(mounted)setState(() { role = '${p['display_name'] ?? 'User'} • $roleName'; stock = List<Map<String,dynamic>>.from(s); });
    } catch(e) { setState(() => error = friendlyError(e)); }
  }
  @override Widget build(BuildContext context) => RefreshIndicator(onRefresh: load, child: ListView(padding: const EdgeInsets.all(18), children: [
    Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF0E5630), Color(0xFF269653)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: brandGreen.withOpacity(.18), blurRadius: 16, offset: const Offset(0, 7))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withOpacity(.16), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.agriculture, color: Colors.white, size: 30)),
          const Spacer(),
          const Icon(Icons.wb_sunny_outlined, color: Colors.white70, size: 25),
        ]),
        const SizedBox(height: 18),
        const Text('WELCOME TO TAJIR', style: TextStyle(color: Colors.white70, fontSize: 11, letterSpacing: 1.6, fontWeight: FontWeight.w700)),
        const SizedBox(height: 5),
        const Text('Growing trade.\nConnecting farmers.', style: TextStyle(color: Colors.white, fontSize: 25, height: 1.15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Text(role, style: const TextStyle(color: Colors.white70, fontSize: 13)),
      ]),
    ),
    const SizedBox(height: 16),
    Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: widget.onOpenItems ?? _noDashboardAction,
        child: const Padding(
          padding: EdgeInsets.all(18),
          child: Row(children: [
            CircleAvatar(radius: 25, backgroundColor: Color(0xFFEAF4EC), child: Icon(Icons.inventory_2_outlined, color: brandGreen, size: 28)),
            SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('ITEMS', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              SizedBox(height: 3),
              Text('Open product items and stock records', style: TextStyle(color: Colors.black54)),
            ])),
            Icon(Icons.chevron_right, color: brandGreen),
          ]),
        ),
      ),
    ),
    const SizedBox(height: 12),
    TajirImageTile(
      title:'TRACTOR & MACHINERY SERVICES',
      subtitle:'Manage machines, providers, bookings, operators and payments',
      imageUrl:TajirPictures.tractor,
      icon:Icons.agriculture,
      large:true,
      onTap:widget.onOpenTractor ?? _noDashboardAction,
    ),
    const SizedBox(height: 18),
    const Text('Your business at a glance', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
    const SizedBox(height: 4),
    const Text('A simple view of your products and daily operations', style: TextStyle(color: Colors.black54)),
    const SizedBox(height: 12),
    Wrap(spacing: 10, runSpacing: 10, children: [
      MetricCard(title: 'Stock records', value: stock.length.toString(), icon: Icons.inventory_2),
      const MetricCard(title: 'Product groups', value: '3', icon: Icons.category_outlined),
      const MetricCard(title: 'Branches', value: 'Manage', icon: Icons.storefront),
    ]),
    const SizedBox(height: 12),
    if(branches.isNotEmpty) DropdownButtonFormField<String>(value:selectedBranch,decoration:const InputDecoration(labelText:'Dashboard branch',border:OutlineInputBorder()),items:branches.map((b)=>DropdownMenuItem(value:b['id'].toString(),child:Text(b['name'].toString()+' ('+b['code'].toString()+')'))).toList(),onChanged:(v)=>setState(()=>selectedBranch=v)),
    OutlinedButton.icon(onPressed:()=>showDialog<void>(context:context,builder:(_)=>const Dialog(child:SizedBox(width:520,height:560,child:BranchRequestPanel()))),icon:const Icon(Icons.add_location_alt),label:const Text('Request a new branch')),
    if(director) ...[
      Text('Branch requests awaiting approval ('+pendingRequests.length.toString()+')',style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
      if(pendingRequests.isEmpty)const Text('No pending branch requests.'),
      ...pendingRequests.map((r)=>Card(child:ListTile(title:Text(r['proposed_name'].toString()),subtitle:Text((r['address']??'No address').toString()+' • Code: '+(r['proposed_code']??'Automatic').toString()),trailing:PopupMenuButton<String>(onSelected:(v)async{try{if(v=='approve')await Supabase.instance.client.rpc('approve_branch_request',params:{'p_request_id':r['id'],'p_code':r['proposed_code']});else await Supabase.instance.client.rpc('reject_branch_request',params:{'p_request_id':r['id'],'p_reason':'Rejected by director'});await load();}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(friendlyError(e))));}},itemBuilder:(_)=>const [PopupMenuItem(value:'approve',child:Text('Approve branch')),PopupMenuItem(value:'reject',child:Text('Reject'))])))),
    ],
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
    const SizedBox(height: 12),
    Card(elevation: 0, color: const Color(0xFFEAF4EC), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: const Padding(padding: EdgeInsets.all(16), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.lightbulb_outline, color: brandGreen, size: 27), SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Quick guide', style: TextStyle(fontWeight: FontWeight.bold, color: brandGreen)), SizedBox(height: 5),
          Text('Record every delivery under Purchases and customer orders under Sales. Stock updates through approved purchase batches. Financial details remain restricted by your account role.'),
        ])),
      ])),
    ),
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
  final transportCost = TextEditingController();
  final loadingCost = TextEditingController();
  final labourCost = TextEditingController();
  final dryingCost = TextEditingController();
  final List<Map<String, TextEditingController>> otherExpenses = [];

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
    addOtherExpense();
    loadProductVariants();
  }

  void addOtherExpense() {
    otherExpenses.add({'name': TextEditingController(), 'amount': TextEditingController()});
  }

  void removeOtherExpense(int index) {
    final item = otherExpenses.removeAt(index);
    item['name']!.dispose();
    item['amount']!.dispose();
    setState(() {});
  }

  @override
  void dispose() {
    qty.dispose();
    cost.dispose();
    supplier.dispose();
    notes.dispose();
    transportCost.dispose(); loadingCost.dispose(); labourCost.dispose(); dryingCost.dispose();
    for (final item in otherExpenses) {
      item['name']!.dispose();
      item['amount']!.dispose();
    }
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
          .select('id,variant_name,base_unit,sku')
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
      if (mounted) setState(() => message = 'Could not load ' + product + ' options: ' + friendlyError(e));
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
          .select('id,variant_name,base_unit,sku')
          .single();
      if (!mounted) return;
      setState(() {
        variants.add(Map<String, dynamic>.from(inserted));
        variants.sort((a, b) => (a['variant_name'] as String).compareTo(b['variant_name'] as String));
        selectedVariantId = inserted['id'] as String;
        message = 'Added ' + cleanName + '.';
      });
    } catch (e) {
      if (mounted) setState(() => message = 'Could not add this option. Only an authorised director can add product varieties/types. ' + friendlyError(e));
    }
  }

  Future<void> save() async {
    final q = double.tryParse(qty.text);
    final c = double.tryParse(cost.text);
    final transport = double.tryParse(transportCost.text.trim().isEmpty ? '0' : transportCost.text.trim());
    final loading = double.tryParse(loadingCost.text.trim().isEmpty ? '0' : loadingCost.text.trim());
    final labour = double.tryParse(labourCost.text.trim().isEmpty ? '0' : labourCost.text.trim());
    final drying = double.tryParse(dryingCost.text.trim().isEmpty ? '0' : dryingCost.text.trim());
    final customExpenses = <Map<String, dynamic>>[];
    var invalidCustomExpense = false;
    for (final item in otherExpenses) {
      final name = item['name']!.text.trim();
      final rawAmount = item['amount']!.text.trim();
      if (name.isEmpty && rawAmount.isEmpty) continue;
      final amount = double.tryParse(rawAmount);
      if (name.isEmpty || amount == null || amount < 0) {
        invalidCustomExpense = true;
        break;
      }
      if (amount > 0) customExpenses.add({'cost_type': 'other', 'description': name, 'amount': amount});
    }
    if (q == null || c == null || q <= 0 || c < 0 || selectedVariantId == null || transport == null || loading == null || labour == null || drying == null || [transport,loading,labour,drying].any((v)=>v<0) || invalidCustomExpense) {
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
              'expenses': [
                {'cost_type':'transport','amount':transport},
                {'cost_type':'loading','amount':loading},
                {'cost_type':'labour','amount':labour},
                {'cost_type':'drying','amount':drying},
                ...customExpenses,
              ].where((x)=>(x['amount'] as num)>0).toList(),
            }
          ],
        }
      });
      setState(() => message = 'Purchase saved. Stock is awaiting quality approval.');
      qty.clear();
      cost.clear();
      supplier.clear();
      notes.clear(); transportCost.clear(); loadingCost.clear(); labourCost.clear(); dryingCost.clear();
      for (final item in otherExpenses) {
        item['name']!.clear();
        item['amount']!.clear();
      }
    } catch (e) {
      setState(() => message = 'Could not save purchase: ' + friendlyError(e));
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
      DropdownButtonFormField<String>(
        value: variants.any((v) => v['id'] == selectedVariantId) ? selectedVariantId : null,
        items: variants.map((v) => DropdownMenuItem<String>(
          value: v['id'] as String,
          child: Text('${v['sku'] ?? 'NO-ID'} • ${v['variant_name']}'),
        )).toList(),
        onChanged: (v) => setState(() => selectedVariantId = v),
        decoration: InputDecoration(
          labelText: product == 'Maize' ? 'Maize product ID' : (product == 'Beans' ? 'Bean variety and ID' : 'Fertilizer type and ID'),
        ),
      ),
      if (product != 'Maize')
        TextButton.icon(
          onPressed: loadingVariants ? null : addVariant,
          icon: const Icon(Icons.add),
          label: Text(product == 'Beans' ? 'Add bean variety' : 'Add fertilizer type'),
        ),
      field(qty, 'Quantity (bags)', number: true),
      field(cost, 'Buying price per bag (KES)', number: true),
      const Text('Additional costs for this purchase (KES)',style:TextStyle(fontWeight:FontWeight.bold)),
      field(transportCost, 'Transport', number: true),
      field(loadingCost, 'Loading / offloading', number: true),
      field(labourCost, 'Labour', number: true),
      if (product == 'Maize') field(dryingCost, 'Drying', number: true),
      const SizedBox(height: 8),
      Row(children: [
        const Expanded(child: Text('Other costs (add as many as needed)', style: TextStyle(fontWeight: FontWeight.bold))),
        IconButton(onPressed: () => setState(addOtherExpense), icon: const Icon(Icons.add_circle, color: brandGreen), tooltip: 'Add another cost'),
      ]),
      ...List.generate(otherExpenses.length, (i) {
        final item = otherExpenses[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Expanded(flex: 3, child: TextField(controller: item['name'], textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: 'Expense ${i + 1} (e.g. packaging)', border: const OutlineInputBorder()))),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: TextField(controller: item['amount'], keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Price (KES)', border: OutlineInputBorder()))),
            IconButton(onPressed: () => removeOtherExpense(i), icon: const Icon(Icons.delete_outline, color: Colors.red), tooltip: 'Remove cost'),
          ]),
        );
      }),
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
          .select('id,variant_name,base_unit,sku')
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
      if (mounted) setState(() => message = 'Could not load ' + product + ' options: ' + friendlyError(e));
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
          .select('id,variant_name,base_unit,sku')
          .single();
      if (!mounted) return;
      setState(() {
        variants.add(Map<String, dynamic>.from(inserted));
        variants.sort((a, b) => (a['variant_name'] as String).compareTo(b['variant_name'] as String));
        selectedVariantId = inserted['id'] as String;
        message = 'Added ' + cleanName + '.';
      });
    } catch (e) {
      if (mounted) setState(() => message = 'Could not add this option. Only an authorised director can add product varieties/types. ' + friendlyError(e));
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
      setState(() => message = 'Could not save sale: ' + friendlyError(e));
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
      DropdownButtonFormField<String>(
        value: variants.any((v) => v['id'] == selectedVariantId) ? selectedVariantId : null,
        items: variants.map((v) => DropdownMenuItem<String>(
          value: v['id'] as String,
          child: Text('${v['sku'] ?? 'NO-ID'} • ${v['variant_name']}'),
        )).toList(),
        onChanged: (v) => setState(() => selectedVariantId = v),
        decoration: InputDecoration(
          labelText: product == 'Maize' ? 'Maize product ID' : (product == 'Beans' ? 'Bean variety and ID' : 'Fertilizer type and ID'),
        ),
      ),
      if (product != 'Maize')
        TextButton.icon(
          onPressed: loadingVariants ? null : addVariant,
          icon: const Icon(Icons.add),
          label: Text(product == 'Beans' ? 'Add bean variety' : 'Add fertilizer type'),
        ),
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
  List<dynamic> products=[];
  List<dynamic> pending=[];
  final Map<String,TextEditingController> acceptedControllers={};
  String message='';
  bool loading=false;
  bool reviewing=false;

  Future<void> load()async{
    if(mounted)setState(()=>loading=true);
    try{
      final db=Supabase.instance.client;
      final results=await Future.wait([
        db.rpc('get_stock_balances'),
        db.rpc('get_pending_purchase_quality'),
      ]);
      if(!mounted)return;
      final pendingRows=List<dynamic>.from(results[1] as List);
      final validIds=<String>{};
      for(final purchase in pendingRows){
        if(purchase is! Map)continue;
        final items=List<dynamic>.from(purchase['items']??const []);
        for(final item in items){
          if(item is! Map)continue;
          final id=item['purchase_item_id']?.toString();
          if(id==null)continue;
          validIds.add(id);
          acceptedControllers.putIfAbsent(id,()=>TextEditingController());
        }
      }
      for(final id in acceptedControllers.keys.toList()){
        if(!validIds.contains(id)){
          acceptedControllers.remove(id)?.dispose();
        }
      }
      setState((){
        products=List<dynamic>.from(results[0] as List);
        pending=pendingRows;
        message='';
      });
    }catch(e){
      if(mounted)setState(()=>message='Could not load stock or pending approvals. Sign in with an active Director or Branch Manager account. Details: ${friendlyError(e)}');
    }finally{
      if(mounted)setState(()=>loading=false);
    }
  }

  Future<void> approvePurchase(Map purchase)async{
    if(reviewing)return;
    final items=List<dynamic>.from(purchase['items']??const []);
    final accepted=<Map<String,dynamic>>[];
    for(final item in items){
      final id=item['purchase_item_id']?.toString();
      final raw=id==null?null:acceptedControllers[id]?.text.trim();
      final qty=raw==null?null:double.tryParse(raw);
      final received=(item['quantity'] as num?)?.toDouble();
      if(qty==null||qty<0||received==null||qty>received){
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Enter a valid accepted quantity for every item. Use 0 for a fully rejected item.')));
        return;
      }
      accepted.add({'purchase_item_id':id,'accepted_quantity':qty});
    }
    final confirm=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Confirm stock approval'),
      content:const Text('Only the quantities you entered will be added to available stock. Remaining quantities will be rejected. Continue?'),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Approve stock')),
      ],
    ));
    if(confirm!=true)return;
    setState(()=>reviewing=true);
    try{
      await Supabase.instance.client.rpc('approve_purchase_quality',params:{
        'p_purchase_id':purchase['purchase_id'],
        'p_accepted':accepted,
      });
      if(!mounted)return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Stock review completed. Approved quantities are now in stock.')));
      for(final item in items){
        final id=item['purchase_item_id']?.toString();
        if(id!=null)acceptedControllers[id]?.clear();
      }
      await load();
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Stock approval failed: ${friendlyError(e)}')));
    }finally{
      if(mounted)setState(()=>reviewing=false);
    }
  }

  @override void initState(){super.initState();load();}
  @override void dispose(){for(final c in acceptedControllers.values){c.dispose();}super.dispose();}

  @override Widget build(BuildContext context)=>RefreshIndicator(
    onRefresh:load,
    child:ListView(padding:const EdgeInsets.all(18),children:[
      const Text('Stock balances',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold)),
      Align(alignment:Alignment.centerLeft,child:OutlinedButton.icon(onPressed:loading?null:load,icon:const Icon(Icons.refresh),label:const Text('Refresh'))),
      if(message.isNotEmpty)Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Text(message,style:const TextStyle(color:Colors.red))),
      if(loading)const LinearProgressIndicator(),
      const SizedBox(height:12),
      const Text('Stock awaiting approval',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
      const Text('Review received quantities below. Enter the quantity accepted for each item, then approve. Enter 0 if the whole item is rejected.'),
      if(pending.isEmpty&&!loading)const Card(child:Padding(padding:EdgeInsets.all(14),child:Text('No stock is waiting for approval.'))),
      ...pending.whereType<Map>().map((purchase){
        final items=List<dynamic>.from(purchase['items']??const []);
        final total=items.fold<double>(0,(sum,item)=>sum+((item['quantity'] as num?)?.toDouble()??0));
        return Card(margin:const EdgeInsets.symmetric(vertical:7),child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('Purchase ${purchase['purchase_number']??'—'}',style:const TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
          Text('Received quantity: ${total.toStringAsFixed(2)}'),
          const Divider(),
          ...items.whereType<Map>().map((item){
            final id=item['purchase_item_id']?.toString()??'';
            final qty=(item['quantity'] as num?)?.toDouble()??0;
            return Padding(padding:const EdgeInsets.symmetric(vertical:6),child:Row(children:[
              Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text('Received: ${qty.toStringAsFixed(2)} ${item['unit']??''}'),
                Text('Item ID: ${id.length>8?id.substring(0,8):id}',style:const TextStyle(fontSize:11,color:Colors.black54)),
              ])),
              SizedBox(width:118,child:TextField(
                controller:acceptedControllers[id],
                keyboardType:const TextInputType.numberWithOptions(decimal:true),
                decoration:const InputDecoration(labelText:'Accepted qty',border:OutlineInputBorder(),isDense:true),
              )),
            ]));
          }),
          const SizedBox(height:8),
          SizedBox(width:double.infinity,child:FilledButton.icon(
            onPressed:reviewing?null:()=>approvePurchase(purchase),
            icon:const Icon(Icons.verified),
            label:Text(reviewing?'Please wait…':'Approve stock'),
          )),
        ])));
      }),
      const Divider(height:28),
      const Text('Available stock',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
      if(products.isEmpty&&!loading)const Card(child:Padding(padding:EdgeInsets.all(14),child:Text('No approved stock balances yet.'))),
      ...products.map((p)=>Card(child:ListTile(
        leading:const Icon(Icons.inventory_2,color:brandGreen),
        title:Text('${p['product_name']??p['name']??'Product'}'),
        subtitle:Text('Branch: ${p['branch_name']??'Ntulele'}'),
        trailing:Text('${p['quantity_available']??''} ${p['unit']??''}'),
      ))),
    ]),
  );
}
class CustomersPage extends StatefulWidget { const CustomersPage({super.key}); @override State<CustomersPage> createState()=>_CustomersPageState(); }
class _CustomersPageState extends State<CustomersPage> {
  List<Map<String,dynamic>> rows=[];
  String message='';
  bool busy=false;
  bool showDeleted=false;
  final search=TextEditingController();

  @override void initState(){ super.initState(); load(); }
  @override void dispose(){ search.dispose(); super.dispose(); }

  Future<void> load() async {
    setState(() { busy=true; message=''; });
    try {
      final r=await Supabase.instance.client.from('customers')
        .select('id,profile_id,customer_type,full_name,phone,email,default_branch_id,active,marketplace_can_buy,marketplace_can_sell,approved_at,approved_by,created_at,deleted_at,permanently_deleted_at')
        .order('full_name');
      if(!mounted)return;
      setState(()=>rows=List<Map<String,dynamic>>.from(r));
    } catch(e) {
      if(!mounted)return;
      setState(()=>message='Could not load customers. Customer access is limited to authorized director accounts. Details: ${friendlyError(e)}');
    }
    if(mounted)setState(()=>busy=false);
  }

  Future<void> editCustomer([Map<String,dynamic>? row]) async {
    final name=TextEditingController(text:row?['full_name']?.toString()??'');
    final phone=TextEditingController(text:row?['phone']?.toString()??'');
    final email=TextEditingController(text:row?['email']?.toString()??'');
    bool canBuy=row==null?true:row['marketplace_can_buy']==true;
    bool canSell=row==null?false:row['marketplace_can_sell']==true;
    String? error;
    final result=await showDialog<bool>(context:context,builder:(dialogContext)=>StatefulBuilder(builder:(context,refresh)=>AlertDialog(
      title:Text(row==null?'Add customer':'Edit customer'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:name,decoration:const InputDecoration(labelText:'Customer name')),
        TextField(controller:phone,keyboardType:TextInputType.phone,decoration:const InputDecoration(labelText:'Phone number')),
        TextField(controller:email,keyboardType:TextInputType.emailAddress,decoration:const InputDecoration(labelText:'Email (optional)')),
        const Align(alignment:Alignment.centerLeft,child:Text('Marketplace permissions',style:TextStyle(fontWeight:FontWeight.bold))),
        CheckboxListTile(contentPadding:EdgeInsets.zero,title:const Text('Can buy'),value:canBuy,onChanged:(v)=>refresh(()=>canBuy=v??false)),
        CheckboxListTile(contentPadding:EdgeInsets.zero,title:const Text('Can sell'),value:canSell,onChanged:(v)=>refresh(()=>canSell=v??false)),
        if(error!=null)Text(error!,style:const TextStyle(color:Colors.red)),
      ])),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('Cancel')),
        FilledButton(onPressed:()async{
          if(name.text.trim().isEmpty||phone.text.trim().isEmpty){refresh(()=>error='Name and phone number are required.');return;}
          if(!canBuy&&!canSell){refresh(()=>error='Enable buying, selling, or both.');return;}
          Navigator.pop(dialogContext,true);
        },child:const Text('Save')),
      ],
    )));
    if(result==true){
      try {
        final db=Supabase.instance.client;
        final values=<String,dynamic>{'customer_type':canBuy&&canSell?'both':canSell?'seller':'buyer','marketplace_can_buy':canBuy,'marketplace_can_sell':canSell,'full_name':name.text.trim(),'phone':phone.text.trim(),
          'email':email.text.trim().isEmpty?null:email.text.trim()};
        if(row==null){
          final branch=await db.from('branches').select('id').eq('code','NTULELE').maybeSingle();
          if(branch!=null)values['default_branch_id']=branch['id'];
          await db.from('customers').insert(values);
        } else {
          await db.from('customers').update(values).eq('id',row['id']);
        }
        await load();
      } catch(e) { if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Customer could not be saved: ${friendlyError(e)}'))); }
    }
    name.dispose();phone.dispose();email.dispose();
  }

  Future<void> setCustomerPin(Map<String,dynamic> customer) async {
    final pin=TextEditingController();
    final confirm=TextEditingController();
    String? error;
    final accepted=await showDialog<bool>(context:context,builder:(dialogContext)=>StatefulBuilder(
      builder:(context,refresh)=>AlertDialog(
        title:Text('Set PIN for '+(customer['full_name']?.toString()??'customer')),
        content:Column(mainAxisSize:MainAxisSize.min,children:[
          const Text('Create a four-digit customer sign-in PIN. Share it privately with the customer.'),
          const SizedBox(height:12),
          TextField(controller:pin,keyboardType:TextInputType.number,obscureText:true,maxLength:4,
            decoration:const InputDecoration(labelText:'New 4-digit PIN')),
          TextField(controller:confirm,keyboardType:TextInputType.number,obscureText:true,maxLength:4,
            decoration:const InputDecoration(labelText:'Confirm PIN')),
          if(error!=null)Text(error!,style:const TextStyle(color:Colors.red)),
        ]),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('Cancel')),
          FilledButton(onPressed:(){
            if(!RegExp(r'^[0-9]{4}$').hasMatch(pin.text)){refresh(()=>error='PIN must contain exactly four digits.');return;}
            if(pin.text!=confirm.text){refresh(()=>error='The PIN entries do not match.');return;}
            Navigator.pop(dialogContext,true);
          },child:const Text('Save PIN')),
        ],
      )));
    if(accepted==true){
      try{
        final response=await Supabase.instance.client.functions.invoke(
          'tajir-director-set-customer-pin',
          body:{'customer_id':customer['id'],'pin':pin.text},
        );
        final data=response.data;
        if(response.status!=200||data is! Map||data['success']!=true){
          throw FormatException(data is Map?(friendlyError(data['error'] ?? 'Something went wrong.')??'Could not set PIN.'):'Could not set PIN.');
        }
        if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Customer PIN updated successfully.')));
      }catch(e){
        if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Could not set customer PIN: ${friendlyError(e)}')));
      }
    }
    pin.dispose();confirm.dispose();
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
          Text('Customer type: ${customer['customer_type']??'—'}'),
          Text('Account status: ${customer['active']==true?'Active':'Inactive'}'),
          Text('Customer record ID: ${customer['id']??'—'}'),
          Text('Login profile ID: ${customer['profile_id']??'Not linked'}'),
          Text('Default branch ID: ${customer['default_branch_id']??'Not assigned'}'),
          Text('Registered: ${customer['created_at']??'—'}'),
          Text('Approved at: ${customer['approved_at']??'Not approved'}'),
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
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Customer financial history is not available for this account: ${friendlyError(e)}')));
    }
  }

  Future<void> deleteCustomerAccount(Map<String,dynamic> customer) async {
    final name=customer['full_name']?.toString()??'this customer';
    final confirmed=await showDialog<bool>(context:context,builder:(dialogContext)=>AlertDialog(
      title:const Text('Delete customer account?'),
      content:Text('Disable the login account for $name? The customer record, sales, payments and financial history will be retained. The customer will no longer be able to sign in.'),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('Cancel')),
        FilledButton(
          style:FilledButton.styleFrom(backgroundColor:Colors.red),
          onPressed:()=>Navigator.pop(dialogContext,true),
          child:const Text('Delete account'),
        ),
      ],
    ));
    if(confirmed!=true)return;
    try{
      final response=await Supabase.instance.client.functions.invoke(
        'tajir-director-delete-customer-account',
        body:{'customer_id':customer['id']},
      );
      final data=response.data;
      if(response.status!=200||data is! Map||data['success']!=true){
        throw FormatException(data is Map?(friendlyError(data['error'] ?? 'Something went wrong.')??'Could not delete customer account.'):'Could not delete customer account.');
      }
      if(!mounted)return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Customer account moved to Deleted Accounts. Financial history retained.')));
      setState(()=>showDeleted=true);
      await load();
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Could not delete customer account: ${friendlyError(e)}')));
    }
  }

  Future<void> restoreCustomerAccount(Map<String,dynamic> customer) async {
    final name=customer['full_name']?.toString()??'this customer';
    final confirmed=await showDialog<bool>(context:context,builder:(dialogContext)=>AlertDialog(
      title:const Text('Restore customer account?'),
      content:Text('Restore $name to the active customer list? This re-enables the linked login and keeps all previous sales, orders, payments and audit history.'),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('Cancel')),
        FilledButton(onPressed:()=>Navigator.pop(dialogContext,true),child:const Text('Restore account')),
      ],
    ));
    if(confirmed!=true)return;
    try{
      final response=await Supabase.instance.client.functions.invoke(
        'tajir-director-restore-customer-account',
        body:{'customer_id':customer['id']},
      );
      final data=response.data;
      if(response.status!=200||data is! Map||data['success']!=true){
        throw FormatException(data is Map?(friendlyError(data['error'] ?? 'Something went wrong.')??'Could not restore customer account.'):'Could not restore customer account.');
      }
      if(!mounted)return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Customer account restored. Login access is re-enabled.')));
      setState(()=>showDeleted=false);
      await load();
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Could not restore customer account: ${friendlyError(e)}')));
    }
  }

  Future<void> permanentlyDeleteCustomerAccount(Map<String,dynamic> customer) async {
    final name=customer['full_name']?.toString()??'this customer';
    final confirmed=await showDialog<bool>(context:context,builder:(dialogContext)=>AlertDialog(
      title:const Text('Permanently delete customer?'),
      content:Text('This action cannot be undone. It will permanently remove $name\'s login and personal contact details. The customer history record will remain as an anonymized reference so sales, orders, payments and audit history are preserved.'),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('Cancel')),
        FilledButton(
          style:FilledButton.styleFrom(backgroundColor:Colors.red),
          onPressed:()=>Navigator.pop(dialogContext,true),
          child:const Text('Permanently delete'),
        ),
      ],
    ));
    if(confirmed!=true)return;
    try{
      final session=Supabase.instance.client.auth.currentSession;
      final accessToken=session?.accessToken;
      if(accessToken==null||accessToken.isEmpty){
        throw Exception('Your Director session is missing or expired. Sign out and sign in again, then retry.');
      }
      final response=await Supabase.instance.client.functions.invoke(
        'tajir-director-permanently-delete-customer',
        headers:{'Authorization':'Bearer $accessToken'},
        body:{'customer_id':customer['id'],'confirm_permanent_delete':true},
      );
      final data=response.data;
      if(response.status!=200||data is! Map||data['success']!=true){
        throw FormatException(data is Map?(friendlyError(data['error'] ?? 'Something went wrong.')??'Could not permanently delete customer.'):'Could not permanently delete customer.');
      }
      if(!mounted)return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Personal details permanently removed. Financial and transaction history retained.')));
      await load();
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Could not permanently delete customer: ${friendlyError(e)}')));
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
    } catch(e){ if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Could not update customer: ${friendlyError(e)}'))); }
  }

  @override Widget build(BuildContext context) {
    final query=search.text.trim().toLowerCase();
    // Permanently deleted customers are removed from this list; anonymized transaction history remains in the database.
    final deletedCount=rows.where((r)=>r['deleted_at']!=null&&r['permanently_deleted_at']==null).length;
    final filtered=rows.where((r)=>(showDeleted?(r['deleted_at']!=null&&r['permanently_deleted_at']==null):r['deleted_at']==null)&&((r['full_name']??'').toString().toLowerCase().contains(query)||(r['phone']??'').toString().toLowerCase().contains(query))).toList();
    return ListView(padding:const EdgeInsets.all(18),children:[
      Row(children:[const Expanded(child:Text('Customers',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold))),
        IconButton(onPressed:busy?null:load,icon:const Icon(Icons.refresh),tooltip:'Refresh'),
        FilledButton.icon(onPressed:()=>editCustomer(),icon:const Icon(Icons.person_add),label:const Text('Add'))]),
      Row(children:[Expanded(child:ChoiceChip(label:Text('Active customers (${rows.where((r)=>r['deleted_at']==null).length})'),selected:!showDeleted,onSelected:(_)=>setState(()=>showDeleted=false))),const SizedBox(width:8),Expanded(child:ChoiceChip(label:Text('Deleted accounts ($deletedCount)'),selected:showDeleted,onSelected:(_)=>setState(()=>showDeleted=true)))]),
      const SizedBox(height:8),
      TextField(controller:search,onChanged:(_)=>setState((){}),decoration:InputDecoration(prefixIcon:const Icon(Icons.search),labelText:showDeleted?'Search deleted accounts':'Search by name or phone',border:const OutlineInputBorder())),
      const SizedBox(height:10),
      if(message.isNotEmpty)Padding(padding:const EdgeInsets.all(12),child:Text(message,style:const TextStyle(color:Colors.red))),
      if(busy)const Center(child:Padding(padding:EdgeInsets.all(20),child:CircularProgressIndicator())),
      if(!busy&&message.isEmpty&&filtered.isEmpty)Padding(padding:const EdgeInsets.all(20),child:Text(showDeleted?'No deleted accounts.':'No customers found. Add your first customer.')),
      ...filtered.map((r)=>Card(child:ListTile(
        leading:CircleAvatar(child:Icon(r['customer_type']=='seller'?Icons.store:Icons.person)),
        title:Text(r['full_name']?.toString()??''),
        subtitle:Text('${r['phone']??''} • ${r['customer_type']??''}${r['permanently_deleted_at']!=null?' • Permanently deleted (anonymized)':r['deleted_at']!=null?' • Archived':r['active']==false?' • Inactive':''}'),
        onTap:()=>showCustomer(r),
        trailing:PopupMenuButton<String>(onSelected:(v){
          if(v=='edit')editCustomer(r);
          if(v=='deactivate')setActive(r,false);
          if(v=='activate')setActive(r,true);
          if(v=='delete')deleteCustomerAccount(r);
          if(v=='restore')restoreCustomerAccount(r);
          if(v=='permanent')permanentlyDeleteCustomerAccount(r);
        },
          itemBuilder:(context)=>[
            if(!showDeleted)const PopupMenuItem(value:'edit',child:Text('Edit details')),
            if(!showDeleted&&r['active']==true)const PopupMenuItem(value:'deactivate',child:Text('Deactivate')),
            if(!showDeleted&&r['active']==false)const PopupMenuItem(value:'activate',child:Text('Approve / activate account')),
            if(!showDeleted)const PopupMenuItem(value:'delete',child:Text('Move to Deleted Accounts',style:TextStyle(color:Colors.red))),
            if(showDeleted&&r['permanently_deleted_at']==null)const PopupMenuItem(value:'restore',child:Text('Restore account')),
            if(showDeleted&&r['permanently_deleted_at']==null)const PopupMenuItem(value:'permanent',child:Text('Permanently delete',style:TextStyle(color:Colors.red))),
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
  late final TabController tabs = TabController(length: 5, vsync: this);
  final db = Supabase.instance.client;
  List<Map<String,dynamic>> branches = [], tractors = [], jobs = [], customers = [], operators = [], payments = [], expenses = [], maintenanceRecords = [];
  String? branchId, selectedTractor, selectedJob, selectedCustomerId, selectedOperatorId;
  bool loading = true, saving = false;
  String message = '', financeMessage = '';
  String ownership = 'company', service = 'ploughing', paymentMethod = 'cash', payer = 'Edu';
  String expenseType = 'fuel', maintenanceType = 'routine_service', reportPeriod = 'daily', tractorStatus = 'available';
  DateTime bookedFor = DateTime.now().add(const Duration(days: 1));
  DateTime? nextServiceDate;
  final code=TextEditingController(), reg=TextEditingController(), model=TextEditingController(), owner=TextEditingController();
  final assetHours=TextEditingController(), assetNotes=TextEditingController();
  final farmer=TextEditingController(), phone=TextEditingController(), location=TextEditingController(), acres=TextEditingController(), rate=TextEditingController(), notes=TextEditingController();
  final pay=TextEditingController(), reference=TextEditingController(), expense=TextEditingController(), expenseNote=TextEditingController(), estimatedHours=TextEditingController(text:'1');
  final maintenance=TextEditingController(), maintenanceCost=TextEditingController(), maintenanceHours=TextEditingController(), finishHours=TextEditingController();

  @override void initState(){super.initState();load();}
  @override void dispose(){
    tabs.dispose();
    for(final c in [code,reg,model,owner,assetHours,assetNotes,farmer,phone,location,acres,rate,notes,pay,reference,expense,expenseNote,estimatedHours,maintenance,maintenanceCost,maintenanceHours,finishHours]){c.dispose();}
    super.dispose();
  }

  String dateText(DateTime d)=>d.year.toString()+'-'+d.month.toString().padLeft(2,'0')+'-'+d.day.toString().padLeft(2,'0');
  String dateTimeText(DateTime d)=>dateText(d)+' '+d.hour.toString().padLeft(2,'0')+':'+d.minute.toString().padLeft(2,'0');
  double numberOf(Map<String,dynamic> row,String key)=>double.tryParse((row[key]??0).toString())??0;
  String money(double value)=>'KES '+value.toStringAsFixed(2);
  String operatorName(dynamic id){final found=operators.where((o)=>o['id'].toString()==(id??'').toString()).toList();return found.isEmpty?'Not assigned':found.first['display_name'].toString();}
  String labelCase(String value)=>value.replaceAll('_',' ').split(' ').map((s)=>s.isEmpty?s:s[0].toUpperCase()+s.substring(1)).join(' ');

  Future<void> load() async {
    if(mounted)setState((){loading=true;message='';});
    try{
      final b=await db.from('branches').select('id,code,name').eq('is_active',true).order('name');
      branches=List<Map<String,dynamic>>.from(b);
      if(branches.isEmpty)throw Exception('No branch is available to this account. Check its branch assignment.');
      if(branchId==null||!branches.any((x)=>x['id'].toString()==branchId)){branchId=branches.first['id'].toString();}
      await loadBranchData();
    }catch(e){if(mounted)setState((){loading=false;message='Could not load tractor services: '+friendlyError(e);});}
  }

  Future<void> loadBranchData() async {
    if(branchId==null)return;
    if(mounted)setState(()=>loading=true);
    try{
      final a=await db.from('tractor_assets').select().eq('branch_id',branchId!).order('created_at',ascending:false);
      final j=await db.from('tractor_service_jobs').select().eq('branch_id',branchId!).order('created_at',ascending:false);
      tractors=List<Map<String,dynamic>>.from(a);
      jobs=List<Map<String,dynamic>>.from(j);
      if(selectedTractor==null||!tractors.any((x)=>x['id'].toString()==selectedTractor)){selectedTractor=tractors.isEmpty?null:tractors.first['id'].toString();}
      if(selectedJob==null||!jobs.any((x)=>x['id'].toString()==selectedJob)){selectedJob=jobs.isEmpty?null:jobs.first['id'].toString();}
      if(selectedTractor!=null){
        final selected=tractors.firstWhere((x)=>x['id'].toString()==selectedTractor);
        assetHours.text=(selected['engine_hours']??0).toString();
      }
      financeMessage='';
      try{
        final p=await db.from('tractor_job_payments').select().eq('branch_id',branchId!).order('created_at',ascending:false);
        payments=List<Map<String,dynamic>>.from(p);
      }catch(e){payments=[];financeMessage='Payment history is restricted for this account.';}
      try{
        final x=await db.from('tractor_job_expenses').select().eq('branch_id',branchId!).order('created_at',ascending:false);
        expenses=List<Map<String,dynamic>>.from(x);
      }catch(e){expenses=[];financeMessage='Financial history is restricted for this account.';}
      try{
        final m=await db.from('tractor_maintenance_records').select().eq('branch_id',branchId!).order('created_at',ascending:false);
        maintenanceRecords=List<Map<String,dynamic>>.from(m);
      }catch(e){maintenanceRecords=[];}
      try{
        final c=await db.from('customers').select('id,full_name,phone').eq('active',true).order('full_name');
        customers=List<Map<String,dynamic>>.from(c);
      }catch(e){customers=[];}
      try{
        final assignments=await db.from('user_branch_assignments').select('user_id,ended_at').eq('branch_id',branchId!);
        final assignedIds=List<Map<String,dynamic>>.from(assignments).where((x)=>x['ended_at']==null).map((x)=>x['user_id'].toString()).toSet();
        final roles=await db.from('user_role_assignments').select('user_id,role_id').eq('is_active',true);
        final workerIds=List<Map<String,dynamic>>.from(roles).where((x)=>x['role_id'].toString()=='4'&&assignedIds.contains(x['user_id'].toString())).map((x)=>x['user_id'].toString()).toSet().toList();
        if(workerIds.isNotEmpty){
          final staff=await db.from('profiles').select('id,display_name,phone').inFilter('id',workerIds).order('display_name');
          operators=List<Map<String,dynamic>>.from(staff);
        }else{operators=[];}
      }catch(e){operators=[];}
      if(selectedOperatorId!=null&&!operators.any((x)=>x['id'].toString()==selectedOperatorId)){selectedOperatorId=null;}
      if(selectedCustomerId!=null&&!customers.any((x)=>x['id'].toString()==selectedCustomerId)){selectedCustomerId=null;}
      if(mounted)setState(()=>loading=false);
    }catch(e){if(mounted)setState((){loading=false;message='Could not load this branch tractor records: '+friendlyError(e);});}
  }

  Future<void> changeBranch(String? value) async {
    if(value==null||value==branchId)return;
    setState((){branchId=value;selectedTractor=null;selectedJob=null;selectedCustomerId=null;selectedOperatorId=null;message='';});
    await loadBranchData();
  }

  Future<void> registerTractor() async {
    final hours=double.tryParse(assetHours.text.trim())??0;
    if(branchId==null||code.text.trim().isEmpty||model.text.trim().isEmpty||hours<0){setState(()=>message='Enter a tractor code, make/model and a valid engine-hour reading.');return;}
    setState(()=>saving=true);
    try{
      await db.from('tractor_assets').insert({
        'branch_id':branchId,'tractor_code':code.text.trim(),'registration_number':reg.text.trim().isEmpty?null:reg.text.trim(),
        'make_model':model.text.trim(),'ownership_type':ownership,'owner_name':owner.text.trim().isEmpty?null:owner.text.trim(),
        'engine_hours':hours,'notes':assetNotes.text.trim().isEmpty?null:assetNotes.text.trim(),'created_by':db.auth.currentUser!.id
      });
      code.clear();reg.clear();model.clear();owner.clear();assetHours.text='0';assetNotes.clear();
      setState(()=>message='Tractor registered successfully.');await loadBranchData();
    }catch(e){setState(()=>message='Could not register tractor: '+friendlyError(e));}
    if(mounted)setState(()=>saving=false);
  }

  Future<void> saveTractorDetails() async {
    if(selectedTractor==null){setState(()=>message='Select a tractor first.');return;}
    final hours=double.tryParse(assetHours.text.trim());
    if(hours==null||hours<0){setState(()=>message='Enter a valid engine-hour reading.');return;}
    setState(()=>saving=true);
    try{
      await db.from('tractor_assets').update({'engine_hours':hours,'notes':assetNotes.text.trim().isEmpty?null:assetNotes.text.trim(),'status':tractorStatus}).eq('id',selectedTractor!);
      setState(()=>message='Tractor details updated.');await loadBranchData();
    }catch(e){setState(()=>message='Could not update tractor: '+friendlyError(e));}
    if(mounted)setState(()=>saving=false);
  }

  Future<void> chooseBookingDate() async {
    final picked=await showDatePicker(context:context,initialDate:bookedFor,firstDate:DateTime.now().subtract(const Duration(days:1)),lastDate:DateTime(2100));
    if(picked==null||!mounted)return;
    setState(()=>bookedFor=DateTime(picked.year,picked.month,picked.day,bookedFor.hour,bookedFor.minute));
  }
  Future<void> chooseBookingTime() async {
    final picked=await showTimePicker(context:context,initialTime:TimeOfDay.fromDateTime(bookedFor));
    if(picked==null||!mounted)return;
    setState(()=>bookedFor=DateTime(bookedFor.year,bookedFor.month,bookedFor.day,picked.hour,picked.minute));
  }
  Future<void> chooseNextServiceDate() async {
    final picked=await showDatePicker(context:context,initialDate:nextServiceDate??DateTime.now().add(const Duration(days:30)),firstDate:DateTime.now(),lastDate:DateTime(2100));
    if(picked!=null&&mounted)setState(()=>nextServiceDate=picked);
  }

  Future<void> bookJob() async {
    final area=acres.text.trim().isEmpty?null:double.tryParse(acres.text.trim());
    final unitRate=double.tryParse(rate.text.trim());
    final duration=double.tryParse(estimatedHours.text.trim());
    final selectedCustomer=customers.where((x)=>x['id'].toString()==selectedCustomerId).toList();
    final customerName=selectedCustomer.isNotEmpty?selectedCustomer.first['full_name'].toString():farmer.text.trim();
    final customerPhone=selectedCustomer.isNotEmpty?(selectedCustomer.first['phone']??'').toString():phone.text.trim();
    if(branchId==null||selectedTractor==null||customerName.isEmpty||location.text.trim().isEmpty||unitRate==null||unitRate<0||duration==null||duration<=0||(acres.text.trim().isNotEmpty&&(area==null||area<=0))){
      setState(()=>message='Choose a tractor and enter farmer, farm location, valid area (if applicable), estimated duration and rate.');return;
    }
    final tractor=tractors.where((x)=>x['id'].toString()==selectedTractor).toList();
    if(tractor.isEmpty||['maintenance','inactive'].contains(tractor.first['status'])){setState(()=>message='This tractor is not available for booking.');return;}
    setState(()=>saving=true);
    try{
      await db.from('tractor_service_jobs').insert({
        'job_number':'TRJ-'+DateTime.now().millisecondsSinceEpoch.toString(),'branch_id':branchId,'tractor_id':selectedTractor,
        'customer_id':selectedCustomerId,'farmer_name':customerName,'farmer_phone':customerPhone.isEmpty?null:customerPhone,
        'service_type':service,'service_location':location.text.trim(),'area_acres':area,'booked_for':bookedFor.toUtc().toIso8601String(),'estimated_hours':duration,
        'operator_id':selectedOperatorId,'rate':unitRate,'total_charge':(area??1)*unitRate,'status':'booked',
        'notes':notes.text.trim().isEmpty?null:notes.text.trim(),'recorded_by':db.auth.currentUser!.id
      });
      farmer.clear();phone.clear();location.clear();acres.clear();rate.clear();notes.clear();estimatedHours.text='1';selectedCustomerId=null;selectedOperatorId=null;
      setState(()=>message='Booking saved. The job has been added to the schedule.');await loadBranchData();
    }catch(e){setState(()=>message='Could not save booking: '+friendlyError(e));}
    if(mounted)setState(()=>saving=false);
  }

  Future<void> refreshTractorStatus(String tractorId) async {
    try{
      final asset=await db.from('tractor_assets').select('status').eq('id',tractorId).single();
      if(asset['status']=='maintenance'||asset['status']=='inactive')return;
      final active=await db.from('tractor_service_jobs').select('status').eq('tractor_id',tractorId).inFilter('status',['booked','confirmed','in_progress']);
      final rows=List<Map<String,dynamic>>.from(active);
      final next=rows.any((x)=>x['status']=='in_progress')?'working':rows.isNotEmpty?'booked':'available';
      await db.from('tractor_assets').update({'status':next}).eq('id',tractorId);
    }catch(_){}
  }

  Future<void> updateJobStatus(String nextStatus) async {
    if(selectedJob==null){setState(()=>message='Select a service job first.');return;}
    final selected=jobs.where((x)=>x['id'].toString()==selectedJob).toList();
    if(selected.isEmpty)return;
    final job=selected.first;
    final update=<String,dynamic>{'status':nextStatus};
    if(nextStatus=='in_progress')update['started_at']=DateTime.now().toUtc().toIso8601String();
    if(nextStatus=='completed'){
      final hours=double.tryParse(finishHours.text.trim());
      if(hours==null||hours<=0){setState(()=>message='Enter the actual hours worked before completing the job.');return;}
      update['hours_worked']=hours;update['completed_at']=DateTime.now().toUtc().toIso8601String();
    }
    setState(()=>saving=true);
    try{
      await db.from('tractor_service_jobs').update(update).eq('id',selectedJob!);
      if(nextStatus=='completed'){
        // A database trigger updates fleet engine hours atomically when the job is completed.
        finishHours.clear();
      }
      await refreshTractorStatus(job['tractor_id'].toString());
      setState(()=>message='Job status updated to '+labelCase(nextStatus)+'.');await loadBranchData();
    }catch(e){setState(()=>message='Could not update job: '+friendlyError(e));}
    if(mounted)setState(()=>saving=false);
  }

  Future<void> recordPayment() async {
    final amount=double.tryParse(pay.text.trim());
    if(selectedJob==null||amount==null||amount<=0){setState(()=>message='Select a job and enter a valid payment amount.');return;}
    setState(()=>saving=true);
    try{
      final result=await db.rpc('record_tractor_job_payment',params:{'p_job_id':selectedJob,'p_amount':amount,'p_method':paymentMethod,'p_reference':reference.text.trim().isEmpty?null:reference.text.trim()});
      pay.clear();reference.clear();
      setState(()=>message='Payment recorded: '+result['payment_number'].toString()+' • '+result['status'].toString()+'.');
      await loadBranchData();
    }catch(e){setState(()=>message='Could not record payment: '+friendlyError(e));}
    if(mounted)setState(()=>saving=false);
  }

  Future<void> verifyPayment(Map<String,dynamic> payment) async {
    final referenceController=TextEditingController(text:(payment['provider_reference']??'').toString());
    final confirmed=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Verify payment'),
      content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('Payment '+payment['payment_number'].toString()+' • '+money(numberOf(payment,'amount'))),
        Text('Method: '+labelCase(payment['method'].toString())),
        const SizedBox(height:12),
        const Text('Only verify after checking the actual cash, M-Pesa statement or bank transaction.'),
        const SizedBox(height:8),
        TextField(controller:referenceController,decoration:const InputDecoration(labelText:'Transaction reference',border:OutlineInputBorder()))
      ]),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Confirm verification'))
      ]
    ));
    if(confirmed!=true){referenceController.dispose();return;}
    setState(()=>saving=true);
    try{
      final result=await db.rpc('verify_tractor_job_payment',params:{
        'p_payment_id':payment['id'].toString(),
        'p_transaction_reference':referenceController.text.trim()
      });
      setState(()=>message='Payment '+result['payment_number'].toString()+' verified.');
      await loadBranchData();
    }catch(e){setState(()=>message='Could not verify payment: '+friendlyError(e));}
    referenceController.dispose();
    if(mounted)setState(()=>saving=false);
  }

  Future<void> recordExpense() async {
    final amount=double.tryParse(expense.text.trim());
    if(selectedJob==null||amount==null||amount<=0){setState(()=>message='Select a job and enter a valid expense amount.');return;}
    setState(()=>saving=true);
    try{
      await db.from('tractor_job_expenses').insert({
        'job_id':selectedJob,'branch_id':branchId,'expense_type':expenseType,'description':expenseNote.text.trim().isEmpty?null:expenseNote.text.trim(),
        'amount':amount,'paid_by_owner':payer,'recorded_by':db.auth.currentUser!.id
      });
      expense.clear();expenseNote.clear();setState(()=>message='Expense saved to this job.');await loadBranchData();
    }catch(e){setState(()=>message='Could not save expense: '+friendlyError(e));}
    if(mounted)setState(()=>saving=false);
  }

  Future<void> saveMaintenance() async {
    final cost=double.tryParse(maintenanceCost.text.trim())??0;
    final hours=maintenanceHours.text.trim().isEmpty?null:double.tryParse(maintenanceHours.text.trim());
    if(selectedTractor==null||maintenance.text.trim().isEmpty||cost<0||(maintenanceHours.text.trim().isNotEmpty&&(hours==null||hours<0))){
      setState(()=>message='Select a tractor, describe the work and enter valid cost/hour readings.');return;
    }
    setState(()=>saving=true);
    try{
      await db.from('tractor_maintenance_records').insert({
        'tractor_id':selectedTractor,'branch_id':branchId,'maintenance_type':maintenanceType,
        'description':maintenance.text.trim(),'cost':cost,'engine_hours':hours,
        'next_service_date':nextServiceDate==null?null:dateText(nextServiceDate!),
        'recorded_by':db.auth.currentUser!.id
      });
      await db.from('tractor_assets').update({'status':'maintenance',if(hours!=null)'engine_hours':hours}).eq('id',selectedTractor!);
      maintenance.clear();maintenanceCost.clear();maintenanceHours.clear();nextServiceDate=null;
      setState(()=>message='Maintenance record saved. Tractor status set to maintenance until it is released.');await loadBranchData();
    }catch(e){setState(()=>message='Could not save maintenance: '+friendlyError(e));}
    if(mounted)setState(()=>saving=false);
  }

  Future<void> releaseTractor() async {
    if(selectedTractor==null){setState(()=>message='Select a tractor first.');return;}
    setState(()=>saving=true);
    try{
      await db.from('tractor_assets').update({'status':'available'}).eq('id',selectedTractor!).eq('status','maintenance');
      await refreshTractorStatus(selectedTractor!);
      setState(()=>message='Tractor released from maintenance.');await loadBranchData();
    }catch(e){setState(()=>message='Could not release tractor: '+friendlyError(e));}
    if(mounted)setState(()=>saving=false);
  }

  DateTime reportStart(){
    final now=DateTime.now();
    if(reportPeriod=='daily')return DateTime(now.year,now.month,now.day);
    if(reportPeriod=='weekly')return DateTime(now.year,now.month,now.day-(now.weekday-1));
    if(reportPeriod=='monthly')return DateTime(now.year,now.month,1);
    return DateTime(2000,1,1);
  }
  List<Map<String,dynamic>> inPeriod(List<Map<String,dynamic>> rows){
    final start=reportStart();
    return rows.where((x){final d=DateTime.tryParse((x['created_at']??'').toString());return d!=null&&!d.isBefore(start);}).toList();
  }
  void showReceipt(Map<String,dynamic> p) {
    final job=jobs.where((x)=>x['id'].toString()==p['job_id'].toString()).toList();
    showDialog(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('TAJIR tractor service receipt'),
      content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('Receipt: '+p['payment_number'].toString()),Text('Date: '+(p['created_at']??'').toString()),
        Text('Customer: '+(job.isEmpty?'Service customer':job.first['farmer_name'].toString())),
        Text('Job: '+(job.isEmpty?'—':job.first['job_number'].toString())),
        Text('Amount: '+money(numberOf(p,'amount'))),Text('Method: '+labelCase(p['method'].toString())),
        Text('Status: '+labelCase(p['status'].toString()))
      ]),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Close'))]
    ));
  }

  Widget field(TextEditingController c,String label,{bool number=false,int lines=1})=>Padding(
    padding:const EdgeInsets.only(bottom:10),
    child:TextField(controller:c,maxLines:lines,keyboardType:number?const TextInputType.numberWithOptions(decimal:true):TextInputType.text,
      decoration:InputDecoration(labelText:label,border:const OutlineInputBorder()))
  );
  Widget dropdown(String label,String? value,List<String> values,ValueChanged<String?> change)=>Padding(
    padding:const EdgeInsets.only(bottom:10),
    child:DropdownButtonFormField<String>(value:value,decoration:InputDecoration(labelText:label,border:const OutlineInputBorder()),
      items:values.map((v)=>DropdownMenuItem(value:v,child:Text(labelCase(v)))).toList(),onChanged:change)
  );
  Widget button(String label,VoidCallback fn)=>SizedBox(width:double.infinity,child:FilledButton(onPressed:saving?null:fn,child:Text(saving?'Saving…':label)));
  Widget branchPicker()=>Padding(padding:const EdgeInsets.fromLTRB(14,8,14,4),child:DropdownButtonFormField<String>(
    value:branchId,decoration:const InputDecoration(labelText:'Branch',border:OutlineInputBorder(),isDense:true),
    items:branches.map((b)=>DropdownMenuItem(value:b['id'].toString(),child:Text(b['name'].toString()+' ('+b['code'].toString()+')'))).toList(),
    onChanged:branches.length>1?changeBranch:null
  ));
  Widget tractorPicker()=>Padding(padding:const EdgeInsets.only(bottom:10),child:DropdownButtonFormField<String>(
    value:selectedTractor,decoration:const InputDecoration(labelText:'Tractor',border:OutlineInputBorder()),
    items:tractors.map((t)=>DropdownMenuItem(value:t['id'].toString(),child:Text(t['tractor_code'].toString()+' • '+t['make_model'].toString()))).toList(),
    onChanged:(v)=>setState((){
      selectedTractor=v;
      final found=tractors.where((x)=>x['id'].toString()==v).toList();
      if(found.isNotEmpty){assetHours.text=(found.first['engine_hours']??0).toString();tractorStatus=(found.first['status']??'available').toString();assetNotes.text=(found.first['notes']??'').toString();}
    })
  ));
  Widget jobPicker()=>Padding(padding:const EdgeInsets.only(bottom:10),child:DropdownButtonFormField<String>(
    value:selectedJob,decoration:const InputDecoration(labelText:'Service job',border:OutlineInputBorder()),
    items:jobs.map((j)=>DropdownMenuItem(value:j['id'].toString(),child:Text(j['job_number'].toString()+' • '+j['farmer_name'].toString()))).toList(),
    onChanged:(v)=>setState(()=>selectedJob=v)
  ));

  Widget fleetTab()=>ListView(padding:const EdgeInsets.all(14),children:[
    const Text('Register tractor',style:TextStyle(fontSize:19,fontWeight:FontWeight.bold)),
    field(code,'Tractor code / fleet number'),field(reg,'Registration number'),field(model,'Make and model'),
    dropdown('Ownership type',ownership,['company','leased','third_party'],(v)=>setState(()=>ownership=v??'company')),
    field(owner,'Owner name (if leased or third-party)'),field(assetHours,'Current engine hours',number:true),field(assetNotes,'Tractor notes',lines:2),
    button('Register tractor',registerTractor),
    const Divider(height:30),Text('Fleet records ('+tractors.length.toString()+')',style:const TextStyle(fontWeight:FontWeight.bold)),
    if(tractors.isEmpty)const Padding(padding:EdgeInsets.all(12),child:Text('No tractors registered for this branch yet.')),
    ...tractors.map((t)=>Card(child:ListTile(
      leading:const Icon(Icons.agriculture,color:brandGreen),
      title:Text(t['tractor_code'].toString()+' • '+t['make_model'].toString()),
      subtitle:Text((t['registration_number']??'No registration').toString()+' • '+labelCase(t['ownership_type'].toString())+' • '+numberOf(t,'engine_hours').toStringAsFixed(1)+' engine hours'),
      trailing:Text(labelCase((t['status']??'available').toString())),
      onTap:()=>setState((){
        selectedTractor=t['id'].toString();assetHours.text=(t['engine_hours']??0).toString();
        assetNotes.text=(t['notes']??'').toString();tractorStatus=(t['status']??'available').toString();
      })
    ))),
    const Divider(height:30),const Text('Update selected tractor',style:TextStyle(fontWeight:FontWeight.bold)),
    tractorPicker(),field(assetHours,'Engine-hour reading',number:true),field(assetNotes,'Notes',lines:2),
    dropdown('Fleet status',tractorStatus,['available','booked','working','maintenance','inactive'],(v)=>setState(()=>tractorStatus=v??'available')),
    button('Save tractor details',saveTractorDetails),
    const Divider(height:30),const Text('Maintenance and repairs',style:TextStyle(fontWeight:FontWeight.bold)),
    tractorPicker(),dropdown('Maintenance type',maintenanceType,['routine_service','repair','oil_change','tyre','other'],(v)=>setState(()=>maintenanceType=v??'routine_service')),
    field(maintenance,'Work done / repair details',lines:2),field(maintenanceCost,'Maintenance cost (KES)',number:true),
    field(maintenanceHours,'Engine hours at service (optional)',number:true),
    TextButton.icon(onPressed:chooseNextServiceDate,icon:const Icon(Icons.calendar_month),label:Text(nextServiceDate==null?'Set next service date':'Next service: '+dateText(nextServiceDate!))),
    button('Save maintenance record',saveMaintenance),
    OutlinedButton.icon(onPressed:saving?null:releaseTractor,icon:const Icon(Icons.check_circle_outline),label:const Text('Release selected tractor from maintenance'))
  ]);

  Widget bookingTab()=>ListView(padding:const EdgeInsets.all(14),children:[
    const Text('Book tractor service',style:TextStyle(fontSize:19,fontWeight:FontWeight.bold)),
    tractorPicker(),
    if(customers.isNotEmpty)Padding(padding:const EdgeInsets.only(bottom:10),child:DropdownButtonFormField<String>(
      value:selectedCustomerId,decoration:const InputDecoration(labelText:'Link an existing customer (optional)',border:OutlineInputBorder()),
      items:customers.map((c)=>DropdownMenuItem(value:c['id'].toString(),child:Text(c['full_name'].toString()+' • '+c['phone'].toString()))).toList(),
      onChanged:(v)=>setState((){
        selectedCustomerId=v;
        final found=customers.where((x)=>x['id'].toString()==v).toList();
        if(found.isNotEmpty){farmer.text=found.first['full_name'].toString();phone.text=(found.first['phone']??'').toString();}
      })
    )),
    field(farmer,'Farmer / customer name'),field(phone,'Customer phone number'),
    dropdown('Service type',service,['ploughing','planting','harrowing','transport','other'],(v)=>setState(()=>service=v??'ploughing')),
    field(location,'Farm location / village'),field(acres,'Area in acres (leave blank for flat-rate job)',number:true),
    field(estimatedHours,'Estimated job duration (hours)',number:true),field(rate,'Rate per acre or flat rate (KES)',number:true),
    if(operators.isNotEmpty)Padding(padding:const EdgeInsets.only(bottom:10),child:DropdownButtonFormField<String>(
      value:selectedOperatorId,decoration:const InputDecoration(labelText:'Assign operator / driver',border:OutlineInputBorder()),
      items:operators.map((o)=>DropdownMenuItem(value:o['id'].toString(),child:Text(o['display_name'].toString()+' • '+(o['phone']??'').toString()))).toList(),
      onChanged:(v)=>setState(()=>selectedOperatorId=v)
    )),
    Row(children:[
      Expanded(child:TextButton.icon(onPressed:chooseBookingDate,icon:const Icon(Icons.calendar_month),label:Text(dateText(bookedFor)))),
      Expanded(child:TextButton.icon(onPressed:chooseBookingTime,icon:const Icon(Icons.access_time),label:Text(bookedFor.hour.toString().padLeft(2,'0')+':'+bookedFor.minute.toString().padLeft(2,'0'))))
    ]),
    field(notes,'Booking notes / instructions',lines:2),
    if(double.tryParse(rate.text.trim())!=null)Padding(padding:const EdgeInsets.only(bottom:12),child:Text(
      'Quotation total: '+money((double.tryParse(rate.text.trim())??0)*(double.tryParse(acres.text.trim())??1)),
      style:const TextStyle(fontWeight:FontWeight.bold,fontSize:16)
    )),
    button('Save booking and quotation',bookJob),
    const Divider(height:30),Text('Bookings ('+jobs.length.toString()+')',style:const TextStyle(fontWeight:FontWeight.bold)),
    ...jobs.map((j)=>Card(child:ListTile(
      leading:const Icon(Icons.event_available,color:brandGreen),
      title:Text(j['job_number'].toString()+' • '+j['farmer_name'].toString()),
      subtitle:Text(labelCase(j['service_type'].toString())+' • '+j['service_location'].toString()+' • '+dateTimeText((DateTime.tryParse((j['booked_for']??j['created_at']).toString())??DateTime.now()).toLocal())+' • '+numberOf(j,'estimated_hours').toStringAsFixed(1)+' hrs'),
      trailing:Text(money(numberOf(j,'total_charge'))+'\n'+labelCase(j['status'].toString()),textAlign:TextAlign.end),
      onTap:()=>setState(()=>selectedJob=j['id'].toString())
    )))
  ]);

  Widget jobControlTab()=>ListView(padding:const EdgeInsets.all(14),children:[
    const Text('Job scheduling and progress',style:TextStyle(fontSize:19,fontWeight:FontWeight.bold)),
    jobPicker(),
    if(selectedJob!=null)...[
      ...jobs.where((j)=>j['id'].toString()==selectedJob).map((j)=>Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(j['job_number'].toString(),style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
        Text('Customer: '+j['farmer_name'].toString()+' • '+(j['farmer_phone']??'').toString()),
        Text('Service: '+labelCase(j['service_type'].toString())+' at '+j['service_location'].toString()),
        Text('Area: '+(j['area_acres']??'Flat rate').toString()+' acres • Estimated duration: '+numberOf(j,'estimated_hours').toStringAsFixed(1)+' hours • Rate: '+money(numberOf(j,'rate'))),
        Text('Quotation: '+money(numberOf(j,'total_charge'))+' • Status: '+labelCase(j['status'].toString())),
        Text('Operator: '+operatorName(j['operator_id'])), 
        Text('Hours worked: '+numberOf(j,'hours_worked').toStringAsFixed(1)),
      ])))),
      const SizedBox(height:8),
      Wrap(spacing:8,runSpacing:8,children:[
        if(['booked'].contains(jobs.firstWhere((x)=>x['id'].toString()==selectedJob)['status']))OutlinedButton(onPressed:saving?null:()=>updateJobStatus('confirmed'),child:const Text('Confirm job')),
        if(['booked','confirmed'].contains(jobs.firstWhere((x)=>x['id'].toString()==selectedJob)['status']))FilledButton.tonal(onPressed:saving?null:()=>updateJobStatus('in_progress'),child:const Text('Start job')),
        if(jobs.firstWhere((x)=>x['id'].toString()==selectedJob)['status']=='in_progress')SizedBox(width:180,child:field(finishHours,'Actual hours worked',number:true)),
        if(jobs.firstWhere((x)=>x['id'].toString()==selectedJob)['status']=='in_progress')FilledButton(onPressed:saving?null:()=>updateJobStatus('completed'),child:const Text('Complete job')),
        if(!['completed','cancelled'].contains(jobs.firstWhere((x)=>x['id'].toString()==selectedJob)['status']))TextButton(onPressed:saving?null:()=>updateJobStatus('cancelled'),child:const Text('Cancel job'))
      ])
    ],
    const Divider(height:30),const Text('All service jobs',style:TextStyle(fontWeight:FontWeight.bold)),
    ...jobs.map((j)=>Card(child:ListTile(
      title:Text(j['job_number'].toString()+' • '+j['farmer_name'].toString()),
      subtitle:Text(labelCase(j['service_type'].toString())+' • '+labelCase(j['status'].toString())),
      trailing:Text(money(numberOf(j,'total_charge'))),
      onTap:()=>setState(()=>selectedJob=j['id'].toString())
    )))
  ]);

  Widget financeTab()=>ListView(padding:const EdgeInsets.all(14),children:[
    const Text('Payments, balances and costs',style:TextStyle(fontSize:19,fontWeight:FontWeight.bold)),
    if(financeMessage.isNotEmpty)Padding(padding:const EdgeInsets.only(bottom:8),child:Text(financeMessage,style:const TextStyle(color:Colors.deepOrange))),
    jobPicker(),
    if(selectedJob!=null)...jobs.where((j)=>j['id'].toString()==selectedJob).map((j){
      final paid=payments.where((p)=>p['job_id'].toString()==selectedJob&&p['status']=='verified').fold<double>(0,(s,p)=>s+numberOf(p,'amount'));
      final due=numberOf(j,'total_charge')-paid;
      return Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('Job value: '+money(numberOf(j,'total_charge'))),
        Text('Verified payments: '+money(paid)),
        Text('Outstanding balance: '+money(due<0?0:due),style:const TextStyle(fontWeight:FontWeight.bold))
      ])));
    }),
    field(pay,'Payment amount (KES)',number:true),
    dropdown('Payment method',paymentMethod,['cash','mpesa','bank_transfer','other'],(v)=>setState(()=>paymentMethod=v??'cash')),
    field(reference,'M-Pesa / bank reference'),button('Record payment',recordPayment),
    const Divider(height:30),const Text('Payment receipts',style:TextStyle(fontWeight:FontWeight.bold)),
    if(payments.isEmpty)const Text('No payment records visible for this branch or role.'),
    ...payments.map((p)=>Card(child:ListTile(
      leading:const Icon(Icons.receipt_long,color:brandGreen),title:Text(p['payment_number'].toString()+' • '+money(numberOf(p,'amount'))),
      subtitle:Text(labelCase(p['method'].toString())+' • '+labelCase(p['status'].toString())),
      trailing:Row(mainAxisSize:MainAxisSize.min,children:[
        if(p['status']=='pending')IconButton(tooltip:'Verify payment',onPressed:saving?null:()=>verifyPayment(p),icon:const Icon(Icons.verified,color:brandGreen)),
        IconButton(tooltip:'View receipt',onPressed:()=>showReceipt(p),icon:const Icon(Icons.visibility))
      ]),onTap:()=>showReceipt(p)
    ))),
    const Divider(height:30),const Text('Operating expenses',style:TextStyle(fontWeight:FontWeight.bold)),
    dropdown('Expense type',expenseType,['fuel','labour','transport','repair','other'],(v)=>setState(()=>expenseType=v??'fuel')),
    field(expenseNote,'Expense description'),field(expense,'Expense amount (KES)',number:true),
    dropdown('Paid by',payer,['Edu','Mercy'],(v)=>setState(()=>payer=v??'Edu')),button('Save job expense',recordExpense),
    ...expenses.take(20).map((x)=>Card(child:ListTile(
      leading:const Icon(Icons.money_off),title:Text(labelCase(x['expense_type'].toString())+' • '+money(numberOf(x,'amount'))),
      subtitle:Text((x['description']??'No description').toString()+' • Paid by '+(x['paid_by_owner']??'—').toString())
    ))),
    const Divider(height:30),const Text('Maintenance and repair history',style:TextStyle(fontWeight:FontWeight.bold)),
    ...maintenanceRecords.take(20).map((m)=>Card(child:ListTile(
      leading:const Icon(Icons.build_circle_outlined),title:Text(labelCase(m['maintenance_type'].toString())+' • '+money(numberOf(m,'cost'))),
      subtitle:Text((m['description']??'').toString()+' • '+(m['maintenance_date']??'').toString()+' • '+(m['next_service_date']??'No next service date').toString())
    )))
  ]);

  Widget reportCard(String title,double value,{bool highlight=false})=>Card(child:Padding(
    padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(title,style:const TextStyle(color:Colors.black54)),const SizedBox(height:5),
      Text(money(value),style:TextStyle(fontSize:20,fontWeight:FontWeight.bold,color:highlight?(value>=0?brandGreen:Colors.red):null))
    ])
  ));

  Widget reportsTab(){
    final p=inPeriod(payments);
    final x=inPeriod(expenses);
    final m=inPeriod(maintenanceRecords);
    final j=inPeriod(jobs);
    final received=p.where((r)=>r['status']=='verified').fold<double>(0,(s,r)=>s+numberOf(r,'amount'));
    final pending=p.where((r)=>r['status']=='pending').fold<double>(0,(s,r)=>s+numberOf(r,'amount'));
    final costs=x.fold<double>(0,(s,r)=>s+numberOf(r,'amount'))+m.fold<double>(0,(s,r)=>s+numberOf(r,'cost'));
    final invoiced=j.fold<double>(0,(s,r)=>s+numberOf(r,'total_charge'));
    final profit=received-costs;
    return ListView(padding:const EdgeInsets.all(14),children:[
      const Text('Tractor service reports',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
      dropdown('Reporting period',reportPeriod,['daily','weekly','monthly','overall'],(v)=>setState(()=>reportPeriod=v??'daily')),
      Text('From '+dateText(reportStart())+' • '+j.length.toString()+' jobs'),
      reportCard('Invoiced service charges',invoiced),
      reportCard('Payments received and verified',received),
      reportCard('Pending payments',pending),
      reportCard('Operating and maintenance expenses',costs),
      reportCard(profit>=0?'Net operating profit':'Net operating loss',profit,highlight:true),
      reportCard('Outstanding customer balances',invoiced-received),
      const Divider(height:24),const Text('Job status summary',style:TextStyle(fontWeight:FontWeight.bold)),
      ...['booked','confirmed','in_progress','completed','cancelled'].map((status){
        final count=j.where((r)=>r['status']==status).length;
        return ListTile(dense:true,title:Text(labelCase(status)),trailing:Text(count.toString(),style:const TextStyle(fontWeight:FontWeight.bold)));
      }),
      const Text('Profit is calculated from verified receipts less recorded expenses for the selected period. Pending M-Pesa/bank payments are not counted as received income.',style:TextStyle(fontSize:12,color:Colors.black54))
    ]);
  }

  @override Widget build(BuildContext context)=>Column(children:[
    const Padding(padding:EdgeInsets.fromLTRB(16,10,16,0),child:Align(alignment:Alignment.centerLeft,child:Text('Tractor Services',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold)))),
    if(branches.isNotEmpty)branchPicker(),
    if(message.isNotEmpty)Padding(padding:const EdgeInsets.all(8),child:Text(message,style:TextStyle(color:message.startsWith('Could not')?Colors.red:brandGreen))),
    if(loading)const Expanded(child:Center(child:CircularProgressIndicator()))
    else Expanded(child:Column(children:[
      TabBar(controller:tabs,isScrollable:true,labelColor:brandGreen,tabs:const[
        Tab(icon:Icon(Icons.agriculture),text:'Fleet'),Tab(icon:Icon(Icons.event),text:'Bookings'),
        Tab(icon:Icon(Icons.assignment_turned_in),text:'Job control'),Tab(icon:Icon(Icons.payments),text:'Payments & costs'),
        Tab(icon:Icon(Icons.analytics),text:'Reports')
      ]),
      Expanded(child:TabBarView(controller:tabs,children:[fleetTab(),bookingTab(),jobControlTab(),financeTab(),reportsTab()]))
    ])),
    Align(alignment:Alignment.centerRight,child:TextButton.icon(onPressed:loading?null:load,icon:const Icon(Icons.refresh),label:const Text('Refresh')))
  ]);
}



class FinancialRecordsPage extends StatefulWidget {
  const FinancialRecordsPage({super.key});
  @override State<FinancialRecordsPage> createState() => _FinancialRecordsPageState();
}
class _FinancialRecordsPageState extends State<FinancialRecordsPage> {
  bool loading = false;
  String error = '';
  String period = 'This month';
  double revenue = 0, costOfGoods = 0, purchaseCostsTotal = 0, purchaseTotal = 0, customerReceipts = 0, supplierPayments = 0;
  List<Map<String,dynamic>> salesRows = [], purchaseCostRows = [], purchaseRows = [], customerPaymentRows = [], supplierPaymentRows = [];
  double numVal(dynamic v) => v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0;
  DateTime? get startDate {
    final now = DateTime.now();
    if (period == 'Today') return DateTime(now.year,now.month,now.day);
    if (period == 'This week') return DateTime(now.year,now.month,now.day).subtract(Duration(days:now.weekday-1));
    if (period == 'This month') return DateTime(now.year,now.month,1);
    if (period == 'This year') return DateTime(now.year,1,1);
    return null;
  }
  bool within(dynamic raw) {
    if (startDate == null || raw == null) return true;
    final date = DateTime.tryParse(raw.toString());
    return date != null && !date.isBefore(startDate!);
  }
  @override void initState() { super.initState(); load(); }
  Future<void> load() async {
    setState(() { loading = true; error = ''; });
    try {
      final db = Supabase.instance.client;
      final roles = await db.from('user_role_assignments').select('app_roles(code)').eq('user_id', db.auth.currentUser!.id).eq('is_active', true);
      final isDirector = roles.any((r) => r['app_roles'] is Map && (r['app_roles'] as Map)['code'] == 'director');
      if (!isDirector) throw Exception('This financial report is available to Director accounts only.');
      final data = await Future.wait([
        db.from('sales').select('id,sale_number,sale_date,total_amount,sale_items(line_cost)').order('sale_date',ascending:false),
        db.from('purchase_costs').select('id,purchase_id,purchase_item_id,cost_type,amount,description,incurred_at').order('incurred_at',ascending:false),
        db.from('purchases').select('id,purchase_number,purchase_date,status,purchase_items(quantity,quantity_accepted,buying_price_per_unit)').order('purchase_date',ascending:false),
        db.from('customer_payments').select('payment_number,amount,status,method,received_at').order('received_at',ascending:false),
        db.from('supplier_payments').select('amount,status,method,payment_date,transaction_reference').order('payment_date',ascending:false),
      ]);
      final sr = List<Map<String,dynamic>>.from(data[0]).where((r)=>within(r['sale_date'])).toList();
      final pcr = List<Map<String,dynamic>>.from(data[1]).where((r)=>within(r['incurred_at'])).toList();
      final pr = List<Map<String,dynamic>>.from(data[2]).where((r)=>within(r['purchase_date']) && r['status']=='accepted').toList();
      final cr = List<Map<String,dynamic>>.from(data[3]).where((r)=>within(r['received_at']) && r['status']=='verified').toList();
      final spr = List<Map<String,dynamic>>.from(data[4]).where((r)=>within(r['payment_date']) && r['status']=='verified').toList();
      double rev=0,cogs=0,buy=0;
      for(final row in sr) {
        rev += numVal(row['total_amount']);
        for(final item in List<dynamic>.from(row['sale_items'] ?? const [])) { if(item is Map) cogs += numVal(item['line_cost']); }
      }
      for(final row in pr) {
        for(final item in List<dynamic>.from(row['purchase_items'] ?? const [])) {
          if(item is Map) buy += numVal(item['quantity_accepted'] ?? item['quantity']) * numVal(item['buying_price_per_unit']);
        }
      }
      if(!mounted)return;
      setState(() {
        salesRows=sr; purchaseCostRows=pcr; purchaseRows=pr; customerPaymentRows=cr; supplierPaymentRows=spr;
        revenue=rev; costOfGoods=cogs; purchaseCostsTotal=pcr.fold(0.0,(v,r)=>v+numVal(r['amount']));
        purchaseTotal=buy; customerReceipts=cr.fold(0.0,(v,r)=>v+numVal(r['amount']));
        supplierPayments=spr.fold(0.0,(v,r)=>v+numVal(r['amount']));
      });
    } catch(e) { if(mounted)setState(()=>error=friendlyError(e)); }
    finally { if(mounted)setState(()=>loading=false); }
  }
  String cash(double v) => 'KSh ' + v.toStringAsFixed(2);
  Widget metric(String title,double value,{bool highlight=false}) => Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text(title,style:const TextStyle(fontSize:13,color:Colors.black54)),const SizedBox(height:5),
    Text(cash(value),style:TextStyle(fontSize:19,fontWeight:FontWeight.bold,color:highlight?Colors.green: null)),
  ])));
  Widget section(String title,List<Map<String,dynamic>> rows,String dateField,String amountField,String nameField) => Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    const Divider(height:24),Text(title,style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
    if(rows.isEmpty) const Padding(padding:EdgeInsets.symmetric(vertical:8),child:Text('No records for this period.')),
    ...rows.take(40).map((r)=>ListTile(dense:true,title:Text((r[nameField]??title).toString()),subtitle:Text((r[dateField]??'').toString()),trailing:Text(cash(numVal(r[amountField]))))),
  ]);
  @override Widget build(BuildContext context) {
    final gross = revenue-costOfGoods;
    final net = gross;
    return RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.all(16),children:[
      const Text('Financial Records & Profit',style:TextStyle(fontSize:23,fontWeight:FontWeight.bold)),
      const Text('Director reports • amounts in Kenya shillings'),
      const SizedBox(height:12),
      DropdownButtonFormField<String>(value:period,decoration:const InputDecoration(labelText:'Reporting period',border:OutlineInputBorder()),
        items:const ['Today','This week','This month','This year','All time'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),
        onChanged:(v){if(v!=null){setState(()=>period=v);load();}}),
      if(loading) const LinearProgressIndicator(),
      if(error.isNotEmpty) Padding(padding:const EdgeInsets.all(10),child:Text('Unable to load records: '+error,style:const TextStyle(color:Colors.red))),
      const SizedBox(height:8),
      GridView.count(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),crossAxisCount:MediaQuery.of(context).size.width>600?2:1,childAspectRatio:3.8,children:[
        metric('Sales revenue',revenue),metric('Cost of goods sold',costOfGoods),
        metric('Trading profit (including landed stock cost)',gross,highlight:true),metric('Purchase-related expenses',purchaseCostsTotal),
        metric('Net trading result before other overheads',net,highlight:true),metric('Accepted purchases / stock cost',purchaseTotal),
        metric('Verified customer receipts',customerReceipts),metric('Verified supplier payments',supplierPayments),
      ]),
      section('Sales records',salesRows,'sale_date','total_amount','sale_number'),
      section('Expenses attached to purchases',purchaseCostRows,'incurred_at','amount','cost_type'),
      section('Accepted purchases',purchaseRows,'purchase_date','id','purchase_number'),
      section('Verified customer payments',customerPaymentRows,'received_at','amount','payment_number'),
      section('Verified supplier payments',supplierPaymentRows,'payment_date','amount','transaction_reference'),
      const Padding(padding:EdgeInsets.only(top:14),child:Text('Profit method: trading profit = recorded sales revenue less the cost of goods sold. Purchase-related costs such as transport, loading, labour and drying are attached to each purchase and included in landed stock cost, so they are not deducted a second time. This is trading profit before any separate business overheads. Figures depend on complete and correctly approved records.',style:TextStyle(fontSize:12,color:Colors.black54))),
      Align(alignment:Alignment.centerRight,child:TextButton.icon(onPressed:loading?null:load,icon:const Icon(Icons.refresh),label:const Text('Refresh'))),
    ]));
  }
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
