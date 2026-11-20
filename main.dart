import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

const double maizeBagWeightKg = 90.0;

// Bag weight is product-variant data. The agreed 90 kg rule is the maize
// fallback only; never apply it to beans or fertilizer by assumption.
double? bagWeightKgForProduct(String product, Map<String, dynamic>? variant) {
  final raw = variant?['bag_weight_kg'];
  final configured = raw is num ? raw.toDouble() : double.tryParse(raw?.toString() ?? '');
  if (configured != null && configured > 0) return configured;
  return product.toLowerCase() == 'maize' ? maizeBagWeightKg : null;
}

String storedUnitSummary({
  required String quantityText,
  required String priceText,
  required String unit,
  required double? bagWeightKg,
}) {
  final quantity = double.tryParse(quantityText.trim());
  final price = double.tryParse(priceText.trim());
  if (quantity == null || price == null) return '';
  if (unit == 'KG' && (bagWeightKg == null || bagWeightKg <= 0)) {
    return 'Kilogram conversion is not configured for this product.';
  }
  final bags = unit == 'KG' ? quantity / bagWeightKg! : quantity;
  final pricePerBag = unit == 'KG' ? price * bagWeightKg! : price;
  final kgText = bagWeightKg == null ? '' : ' • ${(bags * bagWeightKg).toStringAsFixed(2)} KG';
  return 'Stored as: ${bags.toStringAsFixed(3)} bags$kgText • ${pricePerBag.toStringAsFixed(2)} KES per bag';
}

String stockQuantityLabel(String product, double quantity) {
  final weight = bagWeightKgForProduct(product, null);
  final bags = '${quantity.toStringAsFixed(2)} bags';
  return weight == null ? bags : '$bags\n${(quantity * weight).toStringAsFixed(1)} KG';
}

IconData productIconFor(String value) {
  final name = value.toLowerCase();
  if (name.contains('maize') || name.contains('corn')) return Icons.grain;
  if (name.contains('bean')) return Icons.spa_outlined;
  if (name.contains('fertilizer') || name.contains('fertiliser') || name.contains('dap') || name.contains('can')) return Icons.science_outlined;
  if (name.contains('seed')) return Icons.eco_outlined;
  if (name.contains('chemical') || name.contains('pesticide')) return Icons.biotech_outlined;
  return Icons.inventory_2_outlined;
}

const brandGreen = Color(0xFF176B3A);
const brandGold = Color(0xFFD6A52D);
const tajirUpdateChannel = MethodChannel('tajir/update');
const tajirVersion = String.fromEnvironment('TAJIR_VERSION', defaultValue: '0');

Future<Map<String, dynamic>?> checkTajirUpdate() async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
  try {
    final request = await client.getUrl(Uri.parse('https://api.github.com/repos/ngenok645-byte/Tajir-android1/releases/latest'));
    request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    request.headers.set(HttpHeaders.userAgentHeader, 'TAJIR-Android');
    final response = await request.close();
    if (response.statusCode != 200) return null;
    final payload = jsonDecode(await response.transform(utf8.decoder).join());
    if (payload is! Map) return null;
    final tag = (payload['tag_name'] ?? '').toString().replaceFirst(RegExp(r'^[vV]'), '');
    final remote = int.tryParse(tag) ?? 0;
    final local = int.tryParse(tajirVersion) ?? 0;
    if (remote <= local) return null;
    final assets = payload['assets'];
    if (assets is! List) return null;
    for (final asset in assets) {
      if (asset is Map && (asset['name'] ?? '').toString().toLowerCase().endsWith('.apk')) {
        final url = (asset['browser_download_url'] ?? '').toString();
        if (url.startsWith('https://')) return {'version': tag, 'url': url};
      }
    }
    return null;
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

Future<void> openTajirUpdate(String url) async {
  await tajirUpdateChannel.invokeMethod<void>('openUrl', {'url': url});
}

Future<void> promptForTajirUpdate(BuildContext context, {bool showCurrent = false}) async {
  final found = await checkTajirUpdate();
  if (!context.mounted) return;
  if (found == null) {
    if (showCurrent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('TAJIR is up to date.')),
      );
    }
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('TAJIR update available'),
      content: Text('A newer version (${found['version']}) is ready. Update to get the latest improvements and fixes.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Later')),
        FilledButton.icon(
          onPressed: () async {
            Navigator.pop(dialogContext);
            try {
              await openTajirUpdate(found['url'].toString());
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Could not open the update link. Please try again.')),
                );
              }
            }
          },
          icon: const Icon(Icons.download),
          label: const Text('Download update'),
        ),
      ],
    ),
  );
}

Future<void> callTajirPhone(String phone) async {
  final digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
  if (digits.replaceAll(RegExp(r'[^0-9]'), '').length < 9) {
    throw const FormatException('This contact does not have a valid phone number.');
  }
  await tajirUpdateChannel.invokeMethod<void>('callPhone', {'phone': digits});
}

Future<void> showTajirNationalId(BuildContext context, String profileId) async {
  try {
    final value = await Supabase.instance.client.rpc(
      'get_tajir_national_id',
      params: {'p_profile_id': profileId},
    );
    if (!context.mounted) return;
    final id = value?.toString() ?? '';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('National ID (private)'),
        content: SelectableText(id.isEmpty ? 'No National ID has been registered.' : id),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close'))],
      ),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    }
  }
}

Future<void> addMyTajirNationalId(BuildContext context) async {
  final controller = TextEditingController();
  try {
    final entered = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Register your National ID'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Your full National ID is encrypted. Only you and an authorised TAJIR Director can view it.'),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            maxLength: 8,
            decoration: const InputDecoration(labelText: '7 or 8 digit National ID', border: OutlineInputBorder(), counterText: ''),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Save securely')),
        ],
      ),
    );
    if (entered == null || !context.mounted) return;
    if (entered.length < 7 || entered.length > 8 || int.tryParse(entered) == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid 7 or 8 digit National ID.')));
      return;
    }
    await Supabase.instance.client.rpc('register_my_national_id', params: {'p_national_id': entered});
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('National ID saved securely.')));
    await showTajirNationalId(context, Supabase.instance.client.auth.currentUser!.id);
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(friendlyError(e))),
    );
  } finally {
    controller.dispose();
  }
}

class TajirCallButton extends StatelessWidget {
  final String profileId;
  final String label;
  const TajirCallButton({super.key, required this.profileId, this.label = 'Call'});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: profileId.trim().isEmpty ? null : () async {
        try {
          // Always resolve the number from the selected user's registered profile.
          // Never dial a stale customer/provider contact field.
          final row = await Supabase.instance.client
              .from('profiles')
              .select('phone')
              .eq('id', profileId)
              .maybeSingle();
          final registeredPhone = row?['phone']?.toString().trim() ?? '';
          if (registeredPhone.isEmpty) {
            throw const FormatException('This account has no registered phone number.');
          }
          await callTajirPhone(registeredPhone);
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(friendlyError(e))),
            );
          }
        }
      },
      icon: const Icon(Icons.call),
      label: Text(label),
    );
  }
}


class TajirDirectorContacts extends StatelessWidget {
  const TajirDirectorContacts({super.key});
  Future<void> _call(BuildContext context, String phone) async {
    try { await callTajirPhone(phone); }
    catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e)))); }
  }
  @override Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [Icon(Icons.support_agent, color: brandGreen), SizedBox(width: 8), Expanded(child: Text('TAJIR Director contacts', style: TextStyle(fontWeight: FontWeight.bold)))]),
        ListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Director'), subtitle: const Text('0700020140'),
          trailing: IconButton(tooltip: 'Call Director', onPressed: () => _call(context, '0700020140'), icon: const Icon(Icons.call, color: brandGreen))),
        ListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Mercy • Director'), subtitle: const Text('0713971207'),
          trailing: IconButton(tooltip: 'Call Mercy', onPressed: () => _call(context, '0713971207'), icon: const Icon(Icons.call, color: brandGreen))),
      ])),
  );
}

 
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

class _TajirAppState extends State<TajirApp> with WidgetsBindingObserver {
  static const _inactivityLimit = Duration(minutes: 10);
  Timer? _inactivityTimer;
  StreamSubscription<AuthState>? _authSubscription;
  DateTime? _backgroundedAt;
  bool _signOutInProgress = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      _resetInactivityTimer();
    });
    _resetInactivityTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _inactivityTimer?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }

  // A short app switch (for example, answering a call) must not log a user out.
  // A long background period or ten minutes without interaction expires the session.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _backgroundedAt = DateTime.now();
      _inactivityTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      final backgroundedAt = _backgroundedAt;
      _backgroundedAt = null;
      if (backgroundedAt != null &&
          DateTime.now().difference(backgroundedAt) >= _inactivityLimit) {
        _signOutForInactivity();
      } else {
        _resetInactivityTimer();
      }
    }
  }

  void _recordActivity() {
    if (Supabase.instance.client.auth.currentSession != null) {
      _resetInactivityTimer();
    }
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    if (!mounted || Supabase.instance.client.auth.currentSession == null) return;
    _inactivityTimer = Timer(_inactivityLimit, _signOutForInactivity);
  }

  Future<void> _signOutForInactivity() async {
    if (_signOutInProgress) return;
    final auth = Supabase.instance.client.auth;
    if (auth.currentSession == null) return;
    _signOutInProgress = true;
    _inactivityTimer?.cancel();
    try {
      await auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      // Keep the app responsive during a temporary network outage. Supabase
      // will still enforce server-side token expiry and refresh rules.
    } finally {
      _signOutInProgress = false;
      _resetInactivityTimer();
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'TAJIR', debugShowCheckedModeBanner: false, theme: appTheme,
    builder: (context, child) => Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _recordActivity(),
      child: child ?? const SizedBox.shrink(),
    ),
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
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        leading: CircleAvatar(backgroundColor: brandGreen.withOpacity(.10),
          child: Icon(icon, color: brandGreen)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Text(subtitle)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onPressed,
      ),
    );
  }

  void _openLogin(BuildContext context, String role, {String? roleCode}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LoginPage(accountType: role, roleCode: roleCode)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const BrandMark(),
          const SizedBox(height: 14),
          const Text('Welcome to TAJIR',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('Choose the account type you use. TAJIR will verify your registered role before opening your dashboard.',
            textAlign: TextAlign.center),
          const SizedBox(height: 20),
          const Text('TEAM & SERVICE PROVIDERS',
            style: TextStyle(fontWeight: FontWeight.bold, color: brandGreen)),
          const SizedBox(height: 6),
          _choice(context, icon: Icons.admin_panel_settings_outlined,
            title: 'Director / Branch Manager / Accountant / Worker',
            subtitle: 'Sign in to your authorised TAJIR team account.',
            button: 'Sign in', onPressed: () => _openLogin(context, 'Team account')),
          _choice(context, icon: Icons.agriculture,
            title: 'Tractor owner',
            subtitle: 'Manage tractors, bookings, repair requests and owner services.',
            button: 'Sign in / register', onPressed: () => _openLogin(context, 'Tractor owner', roleCode: 'tractor_owner')),
          _choice(context, icon: Icons.local_shipping_outlined,
            title: 'Tractor driver',
            subtitle: 'View assigned jobs and update job progress.',
            button: 'Sign in', onPressed: () => _openLogin(context, 'Tractor driver', roleCode: 'driver')),
          _choice(context, icon: Icons.build_circle_outlined,
            title: 'Mechanic',
            subtitle: 'Manage repair assignments and parts requests.',
            button: 'Sign in / register', onPressed: () => _openLogin(context, 'Mechanic', roleCode: 'mechanic')),
          _choice(context, icon: Icons.handyman_outlined,
            title: 'Auto-spares provider',
            subtitle: 'Manage shop inventory and incoming parts requests.',
            button: 'Sign in / register', onPressed: () => _openLogin(context, 'Auto-spares provider', roleCode: 'auto_spares_owner')),
          const SizedBox(height: 14),
          const Divider(),
          const Text('CUSTOMERS & TRADERS',
            style: TextStyle(fontWeight: FontWeight.bold, color: brandGreen)),
          const SizedBox(height: 6),
          _choice(context, icon: Icons.storefront_outlined,
            title: 'Farmer / Buyer / Seller / Customer',
            subtitle: 'Create a customer account or sign in to trade and access farm services.',
            button: 'Continue', onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CustomerAuthPage()))),
          const SizedBox(height: 8),
          const Text('New customer? Choose the customer option to register. Team and service-provider accounts must be created or authorised by a Director. Choosing a role here does not grant permissions; TAJIR checks the role assigned to your account.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.black54)),
        ]),
      ),
    ))),
  );
}

class LoginPage extends StatefulWidget {
  final String accountType;
  final String? roleCode;
  const LoginPage({super.key, this.accountType = 'TAJIR team / service account', this.roleCode});
  @override State<LoginPage> createState() => _LoginPageState();
}

String staffAuthPassword(String pin) => 'TAJIR-PIN-$pin-Account#2026';
String tajirLoginEmail(String phone) => 'u${phone.replaceAll(RegExp(r'[^0-9]'), '')}@login.tajir.app';

class _LoginPageState extends State<LoginPage> {
  final phone = TextEditingController();
  final pin = TextEditingController();
  final confirmPin = TextEditingController();
  final phoneCode = TextEditingController();
  String? phoneVerificationId;
  bool phoneCodeSent = false, phoneVerified = false;
  bool busy = false, setupDirector = false;
  String? error;

  @override
  void dispose() {
    phone.dispose();
    pin.dispose();
    confirmPin.dispose();
    phoneCode.dispose();
    super.dispose();
  }

  Future<void> requestDirectorPhoneCode() async {
    if (busy) return;
    setState(() { busy = true; error = null; });
    try {
      final id = await requestTajirPhoneVerification(Supabase.instance.client, phone.text.trim(), 'director_setup');
      if (mounted) setState(() { phoneVerificationId = id; phoneCodeSent = true; phoneVerified = false; phoneCode.clear(); });
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e).replaceFirst('FormatException: ', ''));
    } finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> verifyDirectorPhoneCode() async {
    if (busy) return;
    if (phoneVerificationId == null) { setState(() => error = 'Request a verification code first.'); return; }
    setState(() { busy = true; error = null; });
    try {
      await verifyTajirPhoneVerification(Supabase.instance.client, phone.text.trim(), 'director_setup', phoneVerificationId!, phoneCode.text.trim());
      if (mounted) setState(() { phoneVerified = true; error = null; });
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e).replaceFirst('FormatException: ', ''));
    } finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> showForgotPinHelp() async {
    final recoveryPhone = TextEditingController(text: phone.text.trim());
    final code = TextEditingController();
    final newPin = TextEditingController();
    final confirm = TextEditingController();
    bool codeSent = false;
    bool working = false;
    String? recoveryError;
    String? recoveryMessage;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Reset staff PIN'),
          content: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('A six-digit verification code will be sent to the registered staff phone number.'),
              const SizedBox(height: 12),
              TextField(controller: recoveryPhone, keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Registered staff phone', hintText: '07XXXXXXXX', border: OutlineInputBorder())),
              if (codeSent) ...[
                const SizedBox(height: 12),
                TextField(controller: code, keyboardType: TextInputType.number, maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Six-digit SMS code', border: OutlineInputBorder(), counterText: '')),
                const SizedBox(height: 10),
                TextField(controller: newPin, keyboardType: TextInputType.number, obscureText: true, maxLength: 4,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'New four-digit PIN', border: OutlineInputBorder(), counterText: '')),
                const SizedBox(height: 10),
                TextField(controller: confirm, keyboardType: TextInputType.number, obscureText: true, maxLength: 4,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Confirm new PIN', border: OutlineInputBorder(), counterText: '')),
              ],
              if (recoveryMessage != null) Padding(padding: const EdgeInsets.only(top: 10),
                child: Text(recoveryMessage!, style: const TextStyle(color: brandGreen))),
              if (recoveryError != null) Padding(padding: const EdgeInsets.only(top: 10),
                child: Text(recoveryError!, style: const TextStyle(color: Colors.red))),
            ],
          )),
          actions: [
            TextButton(onPressed: working ? null : () => Navigator.pop(dialogContext), child: const Text('Close')),
            if (!codeSent)
              FilledButton(
                onPressed: working ? null : () async {
                  setDialogState(() { working = true; recoveryError = null; recoveryMessage = null; });
                  try {
                    final result = await Supabase.instance.client.functions.invoke(
                      'tajir-staff-pin-recovery',
                      body: {'action': 'request', 'phone': recoveryPhone.text.trim()},
                    );
                    final data = result.data;
                    if (result.status != 200 || data is! Map || data['success'] != true) {
                      throw FormatException(data is Map ? (data['error']?.toString() ?? 'Could not request a code.') : 'Could not request a code.');
                    }
                    setDialogState(() {
                      codeSent = true;
                      recoveryMessage = 'If this is an active staff account, a code will arrive by SMS. It expires in five minutes.';
                    });
                  } catch (e) {
                    setDialogState(() => recoveryError = friendlyError(e));
                  }
                  setDialogState(() => working = false);
                },
                child: Text(working ? 'Sending…' : 'Send verification code'),
              )
            else
              FilledButton(
                onPressed: working ? null : () async {
                  if (code.text.trim().length != 6 || int.tryParse(code.text.trim()) == null ||
                      newPin.text.trim().length != 4 || int.tryParse(newPin.text.trim()) == null ||
                      newPin.text.trim() != confirm.text.trim()) {
                    setDialogState(() => recoveryError = 'Enter the six-digit code and matching four-digit PINs.');
                    return;
                  }
                  setDialogState(() { working = true; recoveryError = null; recoveryMessage = null; });
                  try {
                    final result = await Supabase.instance.client.functions.invoke(
                      'tajir-staff-pin-recovery',
                      body: {
                        'action': 'verify',
                        'phone': recoveryPhone.text.trim(),
                        'code': code.text.trim(),
                        'new_pin': newPin.text.trim(),
                      },
                    );
                    final data = result.data;
                    if (result.status != 200 || data is! Map || data['success'] != true) {
                      throw FormatException(data is Map ? (data['error']?.toString() ?? 'PIN reset failed.') : 'PIN reset failed.');
                    }
                    if (mounted) setState(() => error = 'Your staff PIN has been reset. Sign in using your new PIN.');
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  } catch (e) {
                    setDialogState(() => recoveryError = friendlyError(e));
                  }
                  if (dialogContext.mounted) setDialogState(() => working = false);
                },
                child: Text(working ? 'Verifying…' : 'Verify code and reset PIN'),
              ),
          ],
        ),
      ),
    );
    recoveryPhone.dispose();
    code.dispose();
    newPin.dispose();
    confirm.dispose();
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
          if (!phoneVerified || phoneVerificationId == null) throw const FormatException('Verify that you control the registered Director phone number first.');
          if (pin.text != confirmPin.text) {
            throw const FormatException('The PIN entries do not match.');
          }
          final response = await db.functions.invoke(
            'tajir-director-setup',
            body: {'phone': phone.text.trim(), 'pin': pin.text, 'verification_id': phoneVerificationId},
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
            Text(setupDirector ? 'Set up Director access' : '${widget.accountType} sign in',
              style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 18),
            TextField(controller: phone, enabled: !busy, keyboardType: TextInputType.phone,
                onChanged: (_) => setState(() { phoneVerificationId = null; phoneCodeSent = false; phoneVerified = false; phoneCode.clear(); }),
                decoration: const InputDecoration(labelText: 'Phone number', hintText: '07XXXXXXXX', border: OutlineInputBorder())),
              if (setupDirector) ...[
                const SizedBox(height: 10),
                SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: busy ? null : requestDirectorPhoneCode, icon: const Icon(Icons.sms_outlined), label: Text(phoneCodeSent ? 'Resend verification code' : 'Verify Director phone by SMS'))),
                if (phoneCodeSent) ...[
                  TextField(controller: phoneCode, keyboardType: TextInputType.number, maxLength: 6, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(labelText: 'Six-digit SMS code', border: OutlineInputBorder(), counterText: '')),
                  SizedBox(width: double.infinity, child: OutlinedButton(onPressed: busy || phoneVerified ? null : verifyDirectorPhoneCode, child: Text(phoneVerified ? 'Phone number verified' : 'Confirm SMS code'))),
                ],
              ],
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
                : 'Enter the phone number and PIN registered to your account. TAJIR checks your assigned role and opens the correct dashboard automatically.',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.black54)),
            if (widget.roleCode == 'driver')
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Driver accounts are created and linked to a tractor by the tractor owner or Director. Use the phone number and PIN they registered for you.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.black54)),
              ),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 12),
              child: Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red))),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: FilledButton(
              onPressed: busy ? null : submit,
              child: Text(busy ? 'Please wait…' : setupDirector ? 'Set up and sign in' : 'Sign in'),
            )),
            TextButton(onPressed: busy ? null : showForgotPinHelp,
              child: const Text('Forgot PIN?')),
            TextButton(onPressed: busy ? null : () => setState(() { setupDirector = !setupDirector; error = null; phoneVerificationId = null; phoneCodeSent = false; phoneVerified = false; phoneCode.clear(); }),
              child: Text(setupDirector ? 'I already set up my PIN — sign in' : 'First time? Set up director PIN')),
            if (widget.roleCode == 'tractor_owner' || widget.roleCode == 'mechanic' || widget.roleCode == 'auto_spares_owner')
              TextButton.icon(
                onPressed: busy ? null : () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ProviderRegistrationPage(roleCode: widget.roleCode!))),
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('New here? Apply for this provider account'),
              ),
            TextButton(onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CustomerAuthPage())),
              child: const Text('Client sign in / register')),
          ]),
        )),
      ),
    )),
  );
}

String normalizeKenyanPhone(String input) {
  var digits = input.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length == 10 && digits.startsWith('0')) digits = '254' + digits.substring(1);
  if (digits.length == 9 && (digits.startsWith('7') || digits.startsWith('1'))) digits = '254' + digits;
  if (digits.length == 12 && digits.startsWith('254') && RegExp(r'^254[17]\d{8}$').hasMatch(digits)) return '+' + digits;
  throw const FormatException('Enter a valid Kenyan mobile number, e.g. 0712345678.');
}

Future<String> requestTajirPhoneVerification(SupabaseClient db, String phone, String purpose) async {
  final normalized = normalizeKenyanPhone(phone);
  final response = await db.functions.invoke('tajir-phone-verification', body: {'action': 'request', 'phone': normalized, 'purpose': purpose});
  final data = response.data;
  if (response.status != 200 || data is! Map || data['success'] != true || data['challenge_id'] == null) {
    throw FormatException(data is Map ? (data['error']?.toString() ?? 'Could not send a verification code.') : 'Could not send a verification code.');
  }
  return data['challenge_id'].toString();
}

Future<void> verifyTajirPhoneVerification(SupabaseClient db, String phone, String purpose, String challengeId, String code) async {
  if (!RegExp(r'^\d{6}$').hasMatch(code)) throw const FormatException('Enter the six-digit SMS code.');
  final response = await db.functions.invoke('tajir-phone-verification', body: {'action': 'verify', 'phone': normalizeKenyanPhone(phone), 'purpose': purpose, 'challenge_id': challengeId, 'code': code});
  final data = response.data;
  if (response.status != 200 || data is! Map || data['verified'] != true) {
    throw FormatException(data is Map ? (data['error']?.toString() ?? 'Phone verification failed.') : 'Phone verification failed.');
  }
}

class ProviderRegistrationPage extends StatefulWidget {
  final String roleCode;
  const ProviderRegistrationPage({super.key, required this.roleCode});
  @override
  State<ProviderRegistrationPage> createState() => _ProviderRegistrationPageState();
}

class _ProviderRegistrationPageState extends State<ProviderRegistrationPage> {
  final fullName = TextEditingController();
  final phone = TextEditingController();
  final businessName = TextEditingController();
  final location = TextEditingController();
  final services = TextEditingController();
  final pin = TextEditingController();
  final confirmPin = TextEditingController();
  final phoneCode = TextEditingController();
  String? phoneVerificationId;
  bool phoneCodeSent = false, phoneVerified = false;
  bool busy = false;
  String? error;

  String get roleName {
    switch (widget.roleCode) {
      case 'tractor_owner': return 'Tractor owner';
      case 'mechanic': return 'Mechanic';
      case 'auto_spares_owner': return 'Auto-spares provider';
      default: return 'Service provider';
    }
  }

  @override
  void dispose() {
    fullName.dispose();
    phone.dispose();
    businessName.dispose();
    location.dispose();
    services.dispose();
    pin.dispose();
    confirmPin.dispose();
    phoneCode.dispose();
    super.dispose();
  }

  Future<void> requestProviderPhoneCode() async {
    if (busy) return;
    setState(() { busy = true; error = null; });
    try {
      final id = await requestTajirPhoneVerification(Supabase.instance.client, phone.text.trim(), 'provider_registration');
      if (mounted) setState(() { phoneVerificationId = id; phoneCodeSent = true; phoneVerified = false; phoneCode.clear(); });
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e).replaceFirst('FormatException: ', ''));
    } finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> verifyProviderPhoneCode() async {
    if (busy) return;
    if (phoneVerificationId == null) { setState(() => error = 'Request a verification code first.'); return; }
    setState(() { busy = true; error = null; });
    try {
      await verifyTajirPhoneVerification(Supabase.instance.client, phone.text.trim(), 'provider_registration', phoneVerificationId!, phoneCode.text.trim());
      if (mounted) setState(() { phoneVerified = true; error = null; });
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e).replaceFirst('FormatException: ', ''));
    } finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> submit() async {
    if (busy) return;
    setState(() { busy = true; error = null; });
    try {
      final normalized = normalizeKenyanPhone(phone.text);
      if (!phoneVerified || phoneVerificationId == null) throw const FormatException('Verify that you control this phone number before applying.');
      if (fullName.text.trim().length < 2) {
        throw const FormatException('Enter your full name.');
      }
      if (!RegExp(r'^[0-9]{4}$').hasMatch(pin.text)) {
        throw const FormatException('Choose a four-digit PIN.');
      }
      if (pin.text != confirmPin.text) {
        throw const FormatException('The PIN entries do not match.');
      }
      if (widget.roleCode != 'tractor_owner' && businessName.text.trim().length < 2) {
        throw const FormatException('Enter your business or shop name.');
      }
      if (widget.roleCode != 'tractor_owner' && location.text.trim().length < 2) {
        throw const FormatException('Enter your operating location.');
      }
      if (widget.roleCode == 'mechanic' && services.text.trim().length < 2) {
        throw const FormatException('List at least one repair service.');
      }

      final response = await Supabase.instance.client.functions.invoke(
        'tajir-provider-register',
        body: {
          'role': widget.roleCode,
          'full_name': fullName.text.trim(),
          'phone': normalized,
          'pin': pin.text,
          'verification_id': phoneVerificationId,
          'business_name': businessName.text.trim(),
          'location': location.text.trim(),
          'services': services.text.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty).toList(),
        },
      );
      final data = response.data;
      if (response.status != 200 || data is! Map || data['success'] != true) {
        throw FormatException(data is Map
          ? (data['error']?.toString() ?? 'Registration could not be completed.')
          : 'Registration could not be completed.');
      }

      await Supabase.instance.client.auth.signInWithPassword(
        email: tajirLoginEmail(normalized),
        password: staffAuthPassword(pin.text),
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AccountRouter()),
        (route) => false,
      );
    } on AuthException catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e).replaceFirst('FormatException: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Register as ' + roleName)),
    body: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460),
        child: Card(child: Padding(padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const BrandMark(),
            const SizedBox(height: 14),
            Text('Apply for a ' + roleName + ' account',
              style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text('Your application will be reviewed by a TAJIR Director. Provider tools and job access stay locked until approval.',
              textAlign: TextAlign.center),
            const SizedBox(height: 16),
            TextField(controller: fullName, textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Full name', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: phone, enabled: !busy, keyboardType: TextInputType.phone,
              onChanged: (_) => setState(() { phoneVerificationId = null; phoneCodeSent = false; phoneVerified = false; phoneCode.clear(); }),
              decoration: const InputDecoration(labelText: 'Your phone number', hintText: '07XXXXXXXX', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            OutlinedButton.icon(onPressed: busy ? null : requestProviderPhoneCode, icon: const Icon(Icons.sms_outlined), label: Text(phoneCodeSent ? 'Resend verification code' : 'Verify phone by SMS')),
            if (phoneCodeSent) ...[
              TextField(controller: phoneCode, keyboardType: TextInputType.number, maxLength: 6, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(labelText: 'Six-digit SMS code', border: OutlineInputBorder(), counterText: '')),
              OutlinedButton(onPressed: busy || phoneVerified ? null : verifyProviderPhoneCode, child: Text(phoneVerified ? 'Phone number verified' : 'Confirm SMS code')),
            ],
            if (widget.roleCode != 'tractor_owner') ...[
              const SizedBox(height: 12),
              TextField(controller: businessName, textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: widget.roleCode == 'mechanic' ? 'Workshop / business name' : 'Shop name',
                  border: const OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: location,
                decoration: const InputDecoration(labelText: 'Town / operating location', border: OutlineInputBorder())),
            ] else ...[
              const SizedBox(height: 12),
              TextField(controller: businessName, textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Company name (optional)', border: OutlineInputBorder())),
            ],
            if (widget.roleCode == 'mechanic') ...[
              const SizedBox(height: 12),
              TextField(controller: services, maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Services offered',
                  hintText: 'Engine repair, hydraulics, servicing',
                  helperText: 'Separate services with commas.',
                  border: OutlineInputBorder())),
            ],
            const SizedBox(height: 12),
            TextField(controller: pin, keyboardType: TextInputType.number, obscureText: true,
              maxLength: 4, decoration: const InputDecoration(labelText: 'Create four-digit PIN', border: OutlineInputBorder(), counterText: '')),
            const SizedBox(height: 12),
            TextField(controller: confirmPin, keyboardType: TextInputType.number, obscureText: true,
              maxLength: 4, decoration: const InputDecoration(labelText: 'Confirm four-digit PIN', border: OutlineInputBorder(), counterText: '')),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 12),
              child: Text(error!, style: const TextStyle(color: Colors.red))),
            const SizedBox(height: 16),
            FilledButton(onPressed: busy ? null : submit,
              child: Text(busy ? 'Submitting application…' : 'Submit application')),
          ]),
        )),
      ),
    )),
  );
}

class ProviderPendingPage extends StatelessWidget {
  final String roleName;
  final String status;
  const ProviderPendingPage({super.key, required this.roleName, required this.status});

  @override
  Widget build(BuildContext context) {
    final rejected = status == 'rejected';
    return Scaffold(
      appBar: AppBar(title: const Text('Provider application')),
      body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(20),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(rejected ? Icons.info_outline : Icons.hourglass_top,
              size: 58, color: brandGold),
            const SizedBox(height: 16),
            Text(rejected ? 'Application needs attention' : 'Application under review',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
            const SizedBox(height: 10),
            Text('Your ' + roleName + ' application status is: ' + status.replaceAll('_', ' ') + '.',
              textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text('TAJIR will enable your provider dashboard after a Director reviews and approves your application. Your account details and saved records are kept safe.',
              textAlign: TextAlign.center),
            const SizedBox(height: 16),
            const TajirDirectorContacts(),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () => Supabase.instance.client.auth.signOut(scope: SignOutScope.local),
              child: const Text('Sign out')),
          ]),
        ),
      )),
    );
  }
}

class CustomerAuthPage extends StatefulWidget {
  const CustomerAuthPage({super.key});
  @override State<CustomerAuthPage> createState() => _CustomerAuthPageState();
}
class _CustomerAuthPageState extends State<CustomerAuthPage> {
  final name = TextEditingController();
  final phone = TextEditingController();
  final nationalId = TextEditingController();
  final pin = TextEditingController();
  final confirmPin = TextEditingController();
  final phoneCode = TextEditingController();
  String? phoneVerificationId;
  bool phoneCodeSent = false, phoneVerified = false;
  bool createAccount = true, busy = false;
  String customerType = 'buyer';
  String? message;
  @override void dispose() {
    name.dispose(); phone.dispose(); nationalId.dispose(); pin.dispose(); confirmPin.dispose(); phoneCode.dispose(); super.dispose();
  }

  Future<void> requestCustomerPhoneCode() async {
    if (busy) return;
    setState(() { busy = true; message = null; });
    try {
      final id = await requestTajirPhoneVerification(Supabase.instance.client, phone.text.trim(), 'customer_registration');
      if (mounted) setState(() { phoneVerificationId = id; phoneCodeSent = true; phoneVerified = false; phoneCode.clear(); message = 'A six-digit code has been sent to your phone.'; });
    } catch (e) {
      if (mounted) setState(() => message = friendlyError(e).replaceFirst('FormatException: ', ''));
    } finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> verifyCustomerPhoneCode() async {
    if (busy) return;
    if (phoneVerificationId == null) { setState(() => message = 'Request a verification code first.'); return; }
    setState(() { busy = true; message = null; });
    try {
      await verifyTajirPhoneVerification(Supabase.instance.client, phone.text.trim(), 'customer_registration', phoneVerificationId!, phoneCode.text.trim());
      if (mounted) setState(() { phoneVerified = true; message = 'Phone number verified.'; });
    } catch (e) {
      if (mounted) setState(() => message = friendlyError(e).replaceFirst('FormatException: ', ''));
    } finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> showForgotPinHelp() async {
    final recoveryPhone = TextEditingController(text: phone.text.trim());
    final code = TextEditingController();
    final newPin = TextEditingController();
    final confirm = TextEditingController();
    bool codeSent = false;
    bool working = false;
    String? recoveryError;
    String? recoveryMessage;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Reset your customer PIN'),
          content: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('We will send a six-digit verification code to your registered phone number.'),
              const SizedBox(height: 12),
              TextField(controller: recoveryPhone, keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Registered phone number', hintText: '07XXXXXXXX', border: OutlineInputBorder())),
              if (codeSent) ...[
                const SizedBox(height: 12),
                TextField(controller: code, keyboardType: TextInputType.number, maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Six-digit SMS code', border: OutlineInputBorder(), counterText: '')),
                const SizedBox(height: 10),
                TextField(controller: newPin, keyboardType: TextInputType.number, obscureText: true, maxLength: 4,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'New four-digit PIN', border: OutlineInputBorder(), counterText: '')),
                const SizedBox(height: 10),
                TextField(controller: confirm, keyboardType: TextInputType.number, obscureText: true, maxLength: 4,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Confirm new PIN', border: OutlineInputBorder(), counterText: '')),
              ],
              if (recoveryMessage != null) Padding(padding: const EdgeInsets.only(top: 10),
                child: Text(recoveryMessage!, style: const TextStyle(color: brandGreen))),
              if (recoveryError != null) Padding(padding: const EdgeInsets.only(top: 10),
                child: Text(recoveryError!, style: const TextStyle(color: Colors.red))),
            ],
          )),
          actions: [
            TextButton(onPressed: working ? null : () => Navigator.pop(dialogContext), child: const Text('Close')),
            if (!codeSent)
              FilledButton(
                onPressed: working ? null : () async {
                  setDialogState(() { working = true; recoveryError = null; recoveryMessage = null; });
                  try {
                    final result = await Supabase.instance.client.functions.invoke(
                      'tajir-customer-pin-recovery',
                      body: {'action': 'request', 'phone': recoveryPhone.text.trim()},
                    );
                    final data = result.data;
                    if (result.status != 200 || data is! Map || data['success'] != true) {
                      throw FormatException(data is Map ? (data['error']?.toString() ?? 'Could not request a code.') : 'Could not request a code.');
                    }
                    setDialogState(() {
                      codeSent = true;
                      recoveryMessage = 'If this is a registered active customer number, a code will arrive by SMS. The code expires in five minutes.';
                    });
                  } catch (e) {
                    setDialogState(() => recoveryError = friendlyError(e));
                  }
                  setDialogState(() => working = false);
                },
                child: Text(working ? 'Sending…' : 'Send verification code'),
              )
            else
              FilledButton(
                onPressed: working ? null : () async {
                  if (code.text.trim().length != 6 || int.tryParse(code.text.trim()) == null ||
                      newPin.text.trim().length != 4 || int.tryParse(newPin.text.trim()) == null ||
                      newPin.text.trim() != confirm.text.trim()) {
                    setDialogState(() => recoveryError = 'Enter the six-digit code and matching four-digit PINs.');
                    return;
                  }
                  setDialogState(() { working = true; recoveryError = null; recoveryMessage = null; });
                  try {
                    final result = await Supabase.instance.client.functions.invoke(
                      'tajir-customer-pin-recovery',
                      body: {
                        'action': 'verify',
                        'phone': recoveryPhone.text.trim(),
                        'code': code.text.trim(),
                        'new_pin': newPin.text.trim(),
                      },
                    );
                    final data = result.data;
                    if (result.status != 200 || data is! Map || data['success'] != true) {
                      throw FormatException(data is Map ? (data['error']?.toString() ?? 'PIN reset failed.') : 'PIN reset failed.');
                    }
                    if (mounted) setState(() => message = 'Your PIN has been reset. Sign in using your new PIN.');
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  } catch (e) {
                    setDialogState(() => recoveryError = friendlyError(e));
                  }
                  if (dialogContext.mounted) setDialogState(() => working = false);
                },
                child: Text(working ? 'Verifying…' : 'Verify code and reset PIN'),
              ),
          ],
        ),
      ),
    );
    recoveryPhone.dispose();
    code.dispose();
    newPin.dispose();
    confirm.dispose();
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
      if (createAccount && (!phoneVerified || phoneVerificationId == null)) throw const FormatException('Verify that you control this phone number before creating an account.');
      if (createAccount && (nationalId.text.trim().length < 7 ||
          nationalId.text.trim().length > 8 ||
          int.tryParse(nationalId.text.trim()) == null)) {
        throw const FormatException('Enter a valid Kenyan National ID number (7 or 8 digits).');
      }
      if (pin.text.length != 4 || int.tryParse(pin.text) == null) {
        throw const FormatException('Enter your four-digit PIN.');
      }
      if (createAccount) {
        if (name.text.trim().length < 2) throw const FormatException('Enter your full name.');
        if (pin.text != confirmPin.text) throw const FormatException('The PIN entries do not match.');
        final response = await db.functions.invoke(
          'tajir-customer-register',
          body: {'full_name': name.text.trim(), 'phone': normalized, 'pin': pin.text, 'customer_type': customerType, 'verification_id': phoneVerificationId},
        );
        final resultData = response.data;
        if (response.status != 200 || resultData is! Map || resultData['success'] != true) {
          final data = resultData;
          throw FormatException(data is Map ? (friendlyError(data['error'] ?? 'Something went wrong.') ?? 'Customer registration failed.') : 'Customer registration failed.');
        }
        await signInCustomerWithPin(db, normalized, pin.text);
        await db.rpc('register_my_national_id', params: {
          'p_national_id': nationalId.text.trim(),
        });
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
            const Text('Your National ID is used to help prevent duplicate accounts. TAJIR stores a protected verification code, not the full ID number. Entering an ID does not mean it has been checked against government records.', textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, fontSize: 12)),
            const SizedBox(height: 16),
            if (createAccount) TextField(controller: name, textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Full name', border: OutlineInputBorder())),
            if (createAccount) const SizedBox(height: 12),
            TextField(controller: phone, enabled: !busy, keyboardType: TextInputType.phone,
              onChanged: (_) => setState(() { phoneVerificationId = null; phoneCodeSent = false; phoneVerified = false; phoneCode.clear(); }),
              decoration: const InputDecoration(labelText: 'Phone number', hintText: '07XXXXXXXX', border: OutlineInputBorder())),
            if (createAccount) ...[
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: busy ? null : requestCustomerPhoneCode, icon: const Icon(Icons.sms_outlined), label: Text(phoneCodeSent ? 'Resend verification code' : 'Verify phone by SMS'))),
              if (phoneCodeSent) ...[
                TextField(controller: phoneCode, keyboardType: TextInputType.number, maxLength: 6, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(labelText: 'Six-digit SMS code', border: OutlineInputBorder(), counterText: '')),
                SizedBox(width: double.infinity, child: OutlinedButton(onPressed: busy || phoneVerified ? null : verifyCustomerPhoneCode, child: Text(phoneVerified ? 'Phone number verified' : 'Confirm SMS code'))),
              ],
              const SizedBox(height: 12),
            ],
            if (createAccount) DropdownButtonFormField<String>(
              value: customerType,
              decoration: const InputDecoration(
                labelText: 'How will you use TAJIR?',
                helperText: 'You can request additional marketplace access later.',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'buyer', child: Text('Buyer — purchase farm products')),
                DropdownMenuItem(value: 'seller', child: Text('Seller — list products for sale')),
              ],
              onChanged: busy ? null : (value) {
                if (value != null) setState(() => customerType = value);
              },
            ),
            if (createAccount) const SizedBox(height: 12),
            if (createAccount) TextField(
              controller: nationalId,
              keyboardType: TextInputType.number,
              maxLength: 8,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'National ID number',
                hintText: 'Enter 7 or 8 digits',
                helperText: 'Kept private. Only the last four digits are retained for account support.',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextField(controller: pin, keyboardType: TextInputType.number, obscureText: true, maxLength: 4,
              decoration: InputDecoration(labelText: createAccount ? 'Four-digit PIN' : 'PIN', border: const OutlineInputBorder(), counterText: '')),
            if (createAccount) const SizedBox(height: 12),
            if (createAccount) TextField(controller: confirmPin, keyboardType: TextInputType.number, obscureText: true, maxLength: 4,
              decoration: const InputDecoration(labelText: 'Confirm four-digit PIN', border: OutlineInputBorder(), counterText: '')),
            if (message != null) Padding(padding: const EdgeInsets.only(top: 12),
              child: Text(message!, style: TextStyle(color: (message == 'Phone number verified.' || message == 'A six-digit code has been sent to your phone.') ? brandGreen : Colors.red))),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: FilledButton(onPressed: busy ? null : submit,
              child: Text(busy ? 'Please wait…' : createAccount ? 'Create account' : 'Sign in'))),
            if (!createAccount)
              TextButton(onPressed: busy ? null : showForgotPinHelp,
                child: const Text('Forgot PIN?')),
            TextButton(onPressed: busy ? null : () => setState(() { createAccount = !createAccount; message = null; phoneVerificationId = null; phoneCodeSent = false; phoneVerified = false; phoneCode.clear(); }),
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

 @override void initState(){super.initState();load(); WidgetsBinding.instance.addPostFrameCallback((_) => checkCustomerUpdates());}

 Future<void> checkCustomerUpdates() async {
  final found = await checkTajirUpdate();
  if (!mounted || found == null) return;
  showDialog<void>(context:context,builder:(ctx)=>AlertDialog(
   title:const Text('TAJIR update available'),
   content:Text('A newer version (${found['version']}) is ready. Update to get the latest improvements and fixes.'),
   actions:[
    TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Later')),
    FilledButton.icon(onPressed:()async{Navigator.pop(ctx);try{await openTajirUpdate(found['url'].toString());}catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Could not open the update link. Please try again.')));}},icon:const Icon(Icons.download),label:const Text('Download update')),
   ],
  ));
 }

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
    TextButton(onPressed:()=>Supabase.instance.client.auth.signOut(scope: SignOutScope.local),child:const Text('Sign out'))
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
     IconButton(tooltip:'Check for updates',onPressed:checkCustomerUpdates,icon:const Icon(Icons.system_update)),
     IconButton(tooltip:'Account security',onPressed:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>const AccountSecurityPage())),icon:const Icon(Icons.lock_reset)),
     IconButton(tooltip:'Refresh',onPressed:onSection?()=>setState((){}):load,icon:const Icon(Icons.refresh)),
     IconButton(tooltip:'Sign out',onPressed:()=>Supabase.instance.client.auth.signOut(scope: SignOutScope.local),icon:const Icon(Icons.logout))
    ],
   ),
   body:Column(children:[
    const TajirDirectorContacts(),
    Expanded(child:onSection
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
      homeTile(title:'PURCHASE REQUESTS',subtitle:'View and follow up your product requests',imageUrl:TajirPictures.orders,icon:Icons.receipt_long_outlined,section:2),
      const SizedBox(height:12),
      OutlinedButton.icon(
        onPressed: () => showTajirNationalId(context, Supabase.instance.client.auth.currentUser!.id),
        icon: const Icon(Icons.verified_user_outlined),
        label: const Text('View my National ID'),
      ),
      OutlinedButton.icon(
        onPressed: () => addMyTajirNationalId(context),
        icon: const Icon(Icons.add_moderator_outlined),
        label: const Text('Add or retry National ID registration'),
      )
    ]))
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

  Future<Widget> _resolveAccount() async {
    final db = Supabase.instance.client;
    final user = db.auth.currentUser;
    if (user == null) return const AuthChoicePage();

    // Resolve customer status and staff roles independently. A failed permission
    // lookup must never silently grant access to the general staff dashboard.
    final status = await db.rpc('get_my_account_status');
    final rows = List<Map<String,dynamic>>.from(status ?? const []);
    if (rows.isNotEmpty && rows.first['is_customer'] == true) {
      return const CustomerPortalPage();
    }

    // Provider applications remain behind an approval gate. Do not route an
    // unapproved provider into an operational workspace, even if a role row exists.
    final ownerApplication = await db.from('tractor_owner_profiles')
      .select('status').eq('profile_id', user.id).maybeSingle();
    if (ownerApplication != null && ownerApplication['status'] != 'approved') {
      return ProviderPendingPage(roleName: 'Tractor owner', status: ownerApplication['status'].toString());
    }
    final mechanicApplication = await db.from('mechanic_profiles')
      .select('status').eq('profile_id', user.id).maybeSingle();
    if (mechanicApplication != null && mechanicApplication['status'] != 'approved') {
      return ProviderPendingPage(roleName: 'Mechanic', status: mechanicApplication['status'].toString());
    }
    final sparesApplication = await db.from('auto_spares_profiles')
      .select('status').eq('profile_id', user.id).maybeSingle();
    if (sparesApplication != null && sparesApplication['status'] != 'approved') {
      return ProviderPendingPage(roleName: 'Auto-spares provider', status: sparesApplication['status'].toString());
    }

    final assigned = await db.from('user_role_assignments')
        .select('app_roles(code,name)')
        .eq('user_id', user.id)
        .eq('is_active', true);
    final roleCodes = <String>{};
    for (final item in assigned) {
      final role = item['app_roles'];
      if (role is Map && role['code'] != null) {
        roleCodes.add(role['code'].toString());
      }
    }

    const staffRoles = {'director','branch_manager','accountant','worker'};
    const serviceRoles = {
      'tractor_owner': 'Tractor Owner',
      'driver': 'Driver',
      'mechanic': 'Mechanic',
      'auto_spares_owner': 'Auto-spares Owner',
    };
    for (final entry in serviceRoles.entries) {
      if (roleCodes.contains(entry.key)) {
        return RoleWorkspacePage(roleCode: entry.key, roleName: entry.value);
      }
    }
    if (roleCodes.contains('worker')) return const WorkerWorkspacePage();
    if (roleCodes.any(staffRoles.contains)) return const HomeShell();
    return const AccountAccessIssuePage();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Widget>(
    future: _resolveAccount(),
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (snapshot.hasError) return const AccountAccessIssuePage();
      return snapshot.data ?? const AccountAccessIssuePage();
    },
  );
}

class RoleWorkspacePage extends StatefulWidget {
  final String roleCode;
  final String roleName;
  const RoleWorkspacePage({super.key, required this.roleCode, required this.roleName});
  @override State<RoleWorkspacePage> createState() => _RoleWorkspacePageState();
}

class _RoleWorkspacePageState extends State<RoleWorkspacePage> {
  final db = Supabase.instance.client;
  bool loading = true, busy = false;
  String error = '';
  Map<String,dynamic>? profile;
  List<Map<String,dynamic>> primary = [], secondary = [], requests = [];

  @override void initState() { super.initState(); load(); WidgetsBinding.instance.addPostFrameCallback((_) => promptForTajirUpdate(context)); }

  String get uid => db.auth.currentUser!.id;
  String money(dynamic value) => 'KES ${(double.tryParse((value ?? 0).toString()) ?? 0).toStringAsFixed(2)}';

  Future<void> load() async {
    if (mounted) setState(() { loading = true; error = ''; });
    try {
      profile = null; primary = []; secondary = []; requests = [];
      switch (widget.roleCode) {
        case 'tractor_owner':
          profile = await db.from('tractor_owner_profiles')
            .select('id,full_name,company_name,phone,status,operating_mode')
            .eq('profile_id', uid).maybeSingle();
          if (profile != null) {
            final ownerId = profile!['id'].toString();
            final assets = await db.from('tractor_owner_assets')
              .select('id,tractor_id,verification_status,verified_at,created_at')
              .eq('owner_id', ownerId).order('created_at', ascending: false);
            primary = List<Map<String,dynamic>>.from(assets);
          }
          final jobs = await db.from('tractor_repair_jobs').select()
            .eq('owner_user_id', uid).order('requested_at', ascending: false);
          secondary = List<Map<String,dynamic>>.from(jobs);
          break;
        case 'driver':
          final jobs = await db.from('tractor_service_jobs')
            .select('id,job_number,service_type,service_location,booked_for,status,total_charge,tractor_id,operator_id')
            .eq('operator_id', uid).order('booked_for', ascending: false);
          primary = List<Map<String,dynamic>>.from(jobs);
          break;
        case 'mechanic':
          profile = await db.from('mechanic_profiles')
            .select('id,business_name,phone,location,services,status')
            .eq('profile_id', uid).maybeSingle();
          if (profile != null) {
            final mechanicId = profile!['id'].toString();
            final jobs = await db.from('tractor_repair_jobs').select()
              .eq('mechanic_id', mechanicId).order('requested_at', ascending: false);
            primary = List<Map<String,dynamic>>.from(jobs);
            final parts = await db.from('repair_part_requests').select()
              .eq('mechanic_id', mechanicId).order('requested_at', ascending: false);
            requests = List<Map<String,dynamic>>.from(parts);
          }
          break;
        case 'auto_spares_owner':
          profile = await db.from('auto_spares_profiles')
            .select('id,shop_name,phone,location,status')
            .eq('profile_id', uid).maybeSingle();
          if (profile != null) {
            final shopId = profile!['id'].toString();
            final stock = await db.from('auto_spares_inventory').select()
              .eq('shop_id', shopId).order('created_at', ascending: false);
            primary = List<Map<String,dynamic>>.from(stock);
            final parts = await db.from('repair_part_requests').select()
              .eq('shop_id', shopId).order('requested_at', ascending: false);
            requests = List<Map<String,dynamic>>.from(parts);
          }
          break;
      }
    } catch (e) {
      error = 'Could not load your workspace: ${friendlyError(e)}';
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> updatePartRequest(Map<String,dynamic> row, String nextStatus) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await db.from('repair_part_requests').update({'status': nextStatus}).eq('id', row['id']);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Parts request updated to ${nextStatus.replaceAll('_',' ')}.')));
      await load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget sectionTitle(String title, int count) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 8),
    child: Row(children: [
      Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
      Chip(label: Text('$count')),
    ]),
  );

  Widget recordCard(String title, String subtitle, {String? trailing, Widget? actions}) =>
    Card(child: Padding(padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(children: [
        ListTile(title: Text(title), subtitle: Text(subtitle), trailing: trailing == null ? null : Text(trailing)),
        if (actions != null) Padding(padding: const EdgeInsets.fromLTRB(12,0,12,10),
          child: Align(alignment: Alignment.centerRight, child: actions)),
      ])));

  Future<void> updateDriverJob(Map<String,dynamic> row, String nextStatus) async {
    double? hoursWorked;
    if (nextStatus == 'completed') {
      final hours = TextEditingController();
      try {
        final entered = await showDialog<String>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Complete tractor job'),
            content: TextField(
              controller: hours,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Actual hours worked'),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, hours.text.trim()), child: const Text('Confirm completion')),
            ],
          ),
        );
        if (entered == null) return;
        hoursWorked = double.tryParse(entered);
        if (hoursWorked == null || hoursWorked! <= 0 || hoursWorked! > 720) {
          throw const FormatException('Enter actual hours greater than zero and no more than 720.');
        }
      } finally {
        hours.dispose();
      }
    }
    if (busy) return;
    setState(() => busy = true);
    try {
      await db.rpc('update_my_assigned_tractor_job', params: {
        'p_job_id': row['id'],
        'p_status': nextStatus,
        'p_hours_worked': hoursWorked,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tractor job marked ' + nextStatus.replaceAll('_',' ') + '.')),
      );
      await load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> addSparePart() async {
    if (profile == null || profile!['status'] != 'approved') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Your spare-parts shop must be approved before adding stock.')));
      return;
    }
    final name = TextEditingController();
    final reference = TextEditingController();
    final description = TextEditingController();
    final quantity = TextEditingController();
    final unit = TextEditingController(text: 'pieces');
    final price = TextEditingController();
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Add spare part to inventory'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Part name')),
            TextField(controller: reference, decoration: const InputDecoration(labelText: 'Part reference / SKU')),
            TextField(controller: description, decoration: const InputDecoration(labelText: 'Description')),
            TextField(controller: quantity, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Quantity')),
            TextField(controller: unit, decoration: const InputDecoration(labelText: 'Unit (pieces, litres, etc.)')),
            TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Selling price (KES)')),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save stock')),
          ],
        ),
      );
      if (confirmed != true) return;
      final qty = double.tryParse(quantity.text.trim());
      final amount = double.tryParse(price.text.trim());
      if (name.text.trim().length < 2 || qty == null || qty < 0 || amount == null || amount < 0 || unit.text.trim().isEmpty) {
        throw const FormatException('Enter a part name, valid quantity, unit and non-negative selling price.');
      }
      setState(() => busy = true);
      await db.from('auto_spares_inventory').insert({
        'shop_id': profile!['id'],
        'part_name': name.text.trim(),
        'part_reference': reference.text.trim().isEmpty ? null : reference.text.trim(),
        'description': description.text.trim().isEmpty ? null : description.text.trim(),
        'quantity': qty,
        'unit': unit.text.trim(),
        'price_kes': amount,
        'status': qty > 0 ? 'active' : 'out_of_stock',
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Spare part added to inventory.')));
      await load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      name.dispose(); reference.dispose(); description.dispose(); quantity.dispose(); unit.dispose(); price.dispose();
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> updateMechanicJobStatus(Map<String,dynamic> row, String nextStatus) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await db.rpc('update_my_mechanic_job_status', params: {
        'p_job_id': row['id'],
        'p_status': nextStatus,
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Repair job status updated to ' + nextStatus.replaceAll('_',' ') + '.')),
      );
      await load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget partRequestCard(Map<String,dynamic> row) {
    final status = (row['status'] ?? 'requested').toString();
    final buttons = <Widget>[];
    if (widget.roleCode == 'auto_spares_owner' && status == 'requested') {
      buttons.add(TextButton(onPressed: busy ? null : () => updatePartRequest(row,'accepted'), child: const Text('Accept')));
      buttons.add(TextButton(onPressed: busy ? null : () => updatePartRequest(row,'declined'), child: const Text('Decline')));
    }
    if (widget.roleCode == 'auto_spares_owner' && status == 'accepted') {
      buttons.add(FilledButton(onPressed: busy ? null : () => updatePartRequest(row,'supplied'), child: const Text('Mark supplied')));
    }
    if (widget.roleCode == 'mechanic' && status == 'requested') {
      buttons.add(TextButton(onPressed: busy ? null : () => updatePartRequest(row,'cancelled'), child: const Text('Cancel request')));
    }
    if (widget.roleCode == 'mechanic' && status == 'supplied') {
      buttons.add(FilledButton(onPressed: busy ? null : () => updatePartRequest(row,'installed'), child: const Text('Mark installed')));
    }
    return recordCard(
      'Parts request • ${row['quantity'] ?? ''} units',
      'Status: $status • Unit price: ${money(row['agreed_unit_price_kes'])}',
      trailing: row['requested_at']?.toString().split('T').first,
      actions: buttons.isEmpty ? null : Wrap(spacing: 8, children: buttons),
    );
  }

  List<Widget> workspaceContent() {
    final out = <Widget>[];
    if (profile != null) {
      final name = profile!['company_name'] ?? profile!['business_name'] ?? profile!['shop_name'] ?? profile!['full_name'] ?? widget.roleName;
      out.add(Card(child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.verified_user_outlined)),
        title: Text(name.toString()),
        subtitle: Text('${profile!['status'] ?? 'Profile'} • ${profile!['phone'] ?? ''}'),
      )));
    }
    switch (widget.roleCode) {
      case 'tractor_owner':
        out.add(sectionTitle('Registered tractor assets', primary.length));
        out.add(Align(alignment: Alignment.centerLeft, child: FilledButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Repair and spare-parts marketplace')),
            body: const SafeArea(child: RepairMarketplacePage()),
          ))),
          icon: const Icon(Icons.build_circle_outlined),
          label: const Text('Find a mechanic or spare parts'),
        )));
        if (primary.isEmpty) out.add(const Text('No tractor ownership records are linked to this account yet.'));
        for (final r in primary) {
          out.add(recordCard('Tractor asset • ${r['tractor_id']}', 'Verification: ${r['verification_status'] ?? 'pending'}'));
        }
        out.add(sectionTitle('Repair requests and history', secondary.length));
        if (secondary.isEmpty) out.add(const Text('No repair jobs have been submitted.'));
        for (final r in secondary) {
          out.add(recordCard('${r['job_number'] ?? 'Repair job'}', '${r['issue_description'] ?? ''} • ${r['status'] ?? ''}', trailing: money(r['final_cost_kes'] ?? r['estimated_cost_kes'])));
        }
        break;
      case 'driver':
        out.add(sectionTitle('My assigned tractor jobs', primary.length));
        if (primary.isEmpty) out.add(const Text('No jobs are currently assigned to you.'));
        for (final r in primary) {
          final jobStatus = (r['status'] ?? '').toString();
          final jobActions = <Widget>[];
          if (jobStatus == 'confirmed') {
            jobActions.add(FilledButton(onPressed: busy ? null : () => updateDriverJob(r, 'in_progress'), child: const Text('Start job')));
          } else if (jobStatus == 'in_progress') {
            jobActions.add(FilledButton(onPressed: busy ? null : () => updateDriverJob(r, 'completed'), child: const Text('Complete job')));
          }
          out.add(recordCard('${r['job_number'] ?? 'Job'} • ${r['service_type'] ?? ''}',
            '${r['service_location'] ?? ''} • ${r['booked_for'] ?? ''} • ' + jobStatus,
            trailing: money(r['total_charge']),
            actions: jobActions.isEmpty ? null : Wrap(spacing: 8, children: jobActions)));
        }
        break;
      case 'mechanic':
        out.add(sectionTitle('Assigned repair jobs', primary.length));
        if (primary.isEmpty) out.add(const Text('No repair jobs are currently assigned to you.'));
        for (final r in primary) {
          final jobStatus = (r['status'] ?? '').toString();
          final jobActions = <Widget>[];
          if (jobStatus == 'requested') {
            jobActions.add(FilledButton(onPressed: busy ? null : () => updateMechanicJobStatus(r, 'accepted'), child: const Text('Accept job')));
          } else if (jobStatus == 'accepted') {
            jobActions.add(FilledButton(onPressed: busy ? null : () => updateMechanicJobStatus(r, 'in_progress'), child: const Text('Start work')));
          } else if (jobStatus == 'in_progress') {
            jobActions.add(OutlinedButton(onPressed: busy ? null : () => updateMechanicJobStatus(r, 'waiting_parts'), child: const Text('Waiting for parts')));
            jobActions.add(FilledButton(onPressed: busy ? null : () => updateMechanicJobStatus(r, 'completed'), child: const Text('Complete job')));
          } else if (jobStatus == 'waiting_parts') {
            jobActions.add(FilledButton(onPressed: busy ? null : () => updateMechanicJobStatus(r, 'in_progress'), child: const Text('Resume work')));
          }
          out.add(recordCard('${r['job_number'] ?? 'Repair job'}',
            '${r['issue_description'] ?? ''} • ${r['location'] ?? ''} • ' + jobStatus,
            trailing: money(r['estimated_cost_kes'] ?? r['final_cost_kes']),
            actions: jobActions.isEmpty ? null : Wrap(spacing: 8, children: jobActions)));
        }
        out.add(sectionTitle('Parts requests', requests.length));
        if (requests.isEmpty) out.add(const Text('No parts requests yet.'));
        out.addAll(requests.map(partRequestCard));
        break;
      case 'auto_spares_owner':
        out.add(sectionTitle('Spare-parts inventory', primary.length));
        out.add(Align(alignment: Alignment.centerLeft, child: FilledButton.icon(
          onPressed: busy || profile == null || profile!['status'] != 'approved' ? null : addSparePart,
          icon: const Icon(Icons.add_box_outlined),
          label: const Text('Add spare part'),
        )));
        if (primary.isEmpty) out.add(const Text('No spare parts have been added to your shop yet.'));
        for (final r in primary) {
          out.add(recordCard('${r['part_name'] ?? 'Spare part'}',
            'Ref: ${r['part_reference'] ?? '-'} • Stock: ${r['quantity'] ?? 0} ${r['unit'] ?? ''} • ${r['status'] ?? ''}',
            trailing: money(r['price_kes'])));
        }
        out.add(sectionTitle('Incoming parts requests', requests.length));
        if (requests.isEmpty) out.add(const Text('No incoming repair-parts requests.'));
        out.addAll(requests.map(partRequestCard));
        break;
    }
    return out;
  }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.roleName), actions: [
      IconButton(tooltip: 'Check for updates', onPressed: () => promptForTajirUpdate(context, showCurrent: true), icon: const Icon(Icons.system_update)),
      IconButton(tooltip: 'Account security', onPressed: () => Navigator.push(context,
        MaterialPageRoute(builder: (_) => const AccountSecurityPage())), icon: const Icon(Icons.shield_outlined)),
      IconButton(tooltip: 'Refresh', onPressed: loading ? null : load, icon: const Icon(Icons.refresh)),
      IconButton(tooltip: 'Sign out', onPressed: () => db.auth.signOut(scope: SignOutScope.local), icon: const Icon(Icons.logout)),
    ]),
    body: RefreshIndicator(onRefresh: load, child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(18),
      children: [
        const TajirDirectorContacts(),
       Text('${widget.roleName} workspace', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const Text('Your records are limited by your signed-in account permissions.'),
        if (loading) const LinearProgressIndicator(),
        if (error.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(error, style: const TextStyle(color: Colors.red))),
        if (!loading && error.isEmpty) ...workspaceContent(),
        if (!loading && error.isNotEmpty) OutlinedButton.icon(onPressed: load, icon: const Icon(Icons.refresh), label: const Text('Try again')),
      ],
    )),
  );
}

class WorkerWorkspacePage extends StatefulWidget {
  const WorkerWorkspacePage({super.key});
  @override State<WorkerWorkspacePage> createState() => _WorkerWorkspacePageState();
}

class _WorkerWorkspacePageState extends State<WorkerWorkspacePage> {
  final db = Supabase.instance.client;
  bool loading = true, busy = false;
  String error = '';
  String? branchId;
  List<Map<String,dynamic>> branches = [], tasks = [], attendance = [];

  String get uid => db.auth.currentUser!.id;
  Map<String,dynamic>? get activeShift {
    for (final row in attendance) {
      if (row['check_out_at'] == null) return row;
    }
    return null;
  }

  @override void initState() { super.initState(); load(); WidgetsBinding.instance.addPostFrameCallback((_) => promptForTajirUpdate(context)); }

  Future<void> load() async {
    if (mounted) setState(() { loading = true; error = ''; });
    try {
      final assigned = await db.from('user_branch_assignments')
        .select('branch_id,branches(name)')
        .eq('user_id', uid)
        .isFilter('ended_at', null);
      branches = List<Map<String,dynamic>>.from(assigned);
      if (branchId == null || !branches.any((b) => b['branch_id'].toString() == branchId)) {
        branchId = branches.isEmpty ? null : branches.first['branch_id'].toString();
      }
      final taskRows = await db.from('staff_tasks')
        .select('id,task_number,title,description,due_at,status,branch_id')
        .eq('assigned_to', uid)
        .order('created_at', ascending: false);
      tasks = List<Map<String,dynamic>>.from(taskRows);
      final attendanceRows = await db.from('staff_attendance')
        .select('id,branch_id,check_in_at,check_out_at')
        .eq('user_id', uid)
        .order('check_in_at', ascending: false)
        .limit(20);
      attendance = List<Map<String,dynamic>>.from(attendanceRows);
    } catch (e) {
      error = 'Could not load your worker records: ' + friendlyError(e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String branchName(Map<String,dynamic> row) {
    final nested = row['branches'];
    if (nested is Map && nested['name'] != null) return nested['name'].toString();
    return 'Assigned branch';
  }

  Future<void> recordAttendance(bool checkIn) async {
    if (busy) return;
    if (checkIn && branchId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ask the Director to assign you to an active branch before checking in.')));
      return;
    }
    setState(() => busy = true);
    try {
      if (checkIn) {
        await db.rpc('staff_check_in', params: {'p_branch_id': branchId});
      } else {
        await db.rpc('staff_check_out');
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(checkIn ? 'Attendance check-in recorded.' : 'Attendance check-out recorded.')));
      await load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> updateTask(Map<String,dynamic> task, String status) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await db.from('staff_tasks').update({'status': status})
        .eq('id', task['id']).eq('assigned_to', uid);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Task updated to ' + status.replaceAll('_',' ') + '.')));
      await load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Worker dashboard'), actions: [
      IconButton(tooltip: 'Check for updates', onPressed: () => promptForTajirUpdate(context, showCurrent: true), icon: const Icon(Icons.system_update)),
      IconButton(tooltip: 'Account security', onPressed: () => Navigator.push(context,
        MaterialPageRoute(builder: (_) => const AccountSecurityPage())), icon: const Icon(Icons.shield_outlined)),
      IconButton(tooltip: 'Refresh', onPressed: loading ? null : load, icon: const Icon(Icons.refresh)),
      IconButton(tooltip: 'Sign out', onPressed: () => db.auth.signOut(scope: SignOutScope.local), icon: const Icon(Icons.logout)),
    ]),
    body: RefreshIndicator(onRefresh: load, child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(18),
      children: [
        const TajirDirectorContacts(),
        const Text('My work and attendance', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const Text('Only tasks and attendance linked to your signed-in account are shown.'),
        if (loading) const LinearProgressIndicator(),
        if (error.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(error, style: const TextStyle(color: Colors.red))),
        if (!loading && error.isEmpty) ...[
          const SizedBox(height: 12),
          const Text('Attendance', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          if (activeShift == null && branches.isNotEmpty) DropdownButtonFormField<String>(
            value: branchId,
            decoration: const InputDecoration(labelText: 'Assigned branch'),
            items: branches.map((b) => DropdownMenuItem<String>(
              value: b['branch_id'].toString(), child: Text(branchName(b)))).toList(),
            onChanged: busy ? null : (value) => setState(() => branchId = value),
          ),
          if (branches.isEmpty) const Text('No active branch assignment was found. Contact the Director before recording attendance.'),
          if (activeShift == null)
            FilledButton.icon(onPressed: busy || branchId == null ? null : () => recordAttendance(true),
              icon: const Icon(Icons.login), label: const Text('Check in')),
          if (activeShift != null) Card(child: ListTile(
            leading: const Icon(Icons.timer, color: brandGreen),
            title: const Text('You are checked in'),
            subtitle: Text('Since ' + (activeShift!['check_in_at'] ?? '').toString()),
            trailing: FilledButton(onPressed: busy ? null : () => recordAttendance(false), child: const Text('Check out')),
          )),
          const SizedBox(height: 16),
          Row(children: [
            const Expanded(child: Text('Assigned tasks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            Chip(label: Text(tasks.length.toString())),
          ]),
          if (tasks.isEmpty) const Text('No tasks have been assigned to you yet.'),
          ...tasks.map((task) {
            final status = (task['status'] ?? 'pending').toString();
            Widget? action;
            if (status == 'pending') {
              action = FilledButton.tonal(onPressed: busy ? null : () => updateTask(task, 'in_progress'), child: const Text('Start task'));
            } else if (status == 'in_progress') {
              action = FilledButton(onPressed: busy ? null : () => updateTask(task, 'submitted'), child: const Text('Submit task'));
            }
            return Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text((task['task_number'] ?? 'Task').toString() + ' • ' + (task['title'] ?? '').toString(),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
                if ((task['description'] ?? '').toString().isNotEmpty) Text(task['description'].toString()),
                Text('Status: ' + status + ' • Due: ' + (task['due_at'] ?? 'Not specified').toString()),
                if (action != null) Align(alignment: Alignment.centerRight, child: action),
              ],
            )));
          }),
          const SizedBox(height: 16),
          const Text('Recent attendance history', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          if (attendance.isEmpty) const Text('No attendance records yet.'),
          ...attendance.map((row) => Card(child: ListTile(
            leading: const Icon(Icons.event_available_outlined),
            title: Text(branches.where((b) => b['branch_id'].toString() == row['branch_id'].toString()).isEmpty
              ? 'Branch attendance' : branchName(branches.firstWhere((b) => b['branch_id'].toString() == row['branch_id'].toString()))),
            subtitle: Text('In: ' + (row['check_in_at'] ?? '').toString() + '\nOut: ' + (row['check_out_at'] ?? 'Still checked in').toString()),
          ))),
        ],
        if (!loading && error.isNotEmpty) OutlinedButton.icon(onPressed: load, icon: const Icon(Icons.refresh), label: const Text('Try again')),
      ],
    )),
  );
}

class AccountAccessIssuePage extends StatelessWidget {
  const AccountAccessIssuePage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('TAJIR account access')),
    body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.lock_outline, size: 56, color: brandGreen),
        const SizedBox(height: 14),
        const Text('We could not verify your account role', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        const Text('For your security, TAJIR has not opened the staff dashboard. Check your connection or ask the Director to verify your active account role.', textAlign: TextAlign.center),
        const SizedBox(height: 16),
        FilledButton(onPressed: () => Supabase.instance.client.auth.signOut(scope: SignOutScope.local), child: const Text('Return to sign in')),
      ],
    ))),
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


class DirectorPricingPage extends StatefulWidget {
  const DirectorPricingPage({super.key});
  @override State<DirectorPricingPage> createState() => _DirectorPricingPageState();
}
class _DirectorPricingPageState extends State<DirectorPricingPage> with SingleTickerProviderStateMixin {
  late final TabController tabs = TabController(length: 2, vsync: this);
  final db = Supabase.instance.client;
  final branchPrice = TextEditingController();
  final listingBuyingPrice = TextEditingController();
  final listingSellingPrice = TextEditingController();
  List<Map<String, dynamic>> branches = [], variants = [], listings = [];
  Map<String, dynamic> branchPrices = {}, buyingPrices = {}, sellingPrices = {};
  String? selectedBranchId, selectedVariantId, selectedListingId;
  bool busy = true, saving = false;
  String? error;
  @override void initState() { super.initState(); load(); }
  @override void dispose() { tabs.dispose(); branchPrice.dispose(); listingBuyingPrice.dispose(); listingSellingPrice.dispose(); super.dispose(); }
  String _branchKey(String b, String v) => '$b|$v';
  String _priceText(dynamic v) => v == null ? '' : (v as num).toStringAsFixed(2);

  Future<void> load() async {
    if (mounted) setState(() { busy = true; error = null; });
    try {
      final r = await Future.wait([
        db.from('branches').select('id,name').eq('is_active', true).order('name'),
        db.from('product_variants').select('id,variant_name,bag_weight_kg,base_unit,products(name)').eq('is_active', true).order('variant_name'),
        db.from('marketplace_listings').select('id,product_name,quantity,unit,location,status').order('created_at', ascending: false),
        db.from('branch_product_selling_prices').select('branch_id,product_variant_id,selling_price_per_kg'),
        db.from('marketplace_listing_buying_prices').select('listing_id,buying_price_kes'),
        db.from('marketplace_listing_selling_prices').select('listing_id,selling_price_kes'),
      ]);
      final b = List<Map<String, dynamic>>.from(r[0]);
      final v = List<Map<String, dynamic>>.from(r[1]);
      final l = List<Map<String, dynamic>>.from(r[2]);
      final bp = <String, dynamic>{};
      for (final x in List<Map<String, dynamic>>.from(r[3])) { bp[_branchKey(x['branch_id'].toString(), x['product_variant_id'].toString())] = x['selling_price_per_kg']; }
      final buy = <String, dynamic>{};
      for (final x in List<Map<String, dynamic>>.from(r[4])) { buy[x['listing_id'].toString()] = x['buying_price_kes']; }
      final sell = <String, dynamic>{};
      for (final x in List<Map<String, dynamic>>.from(r[5])) { sell[x['listing_id'].toString()] = x['selling_price_kes']; }
      if (!mounted) return;
      setState(() {
        branches=b; variants=v; listings=l; branchPrices=bp; buyingPrices=buy; sellingPrices=sell;
        if (!branches.any((x)=>x['id'].toString()==selectedBranchId)) selectedBranchId=branches.isEmpty?null:branches.first['id'].toString();
        if (!variants.any((x)=>x['id'].toString()==selectedVariantId)) selectedVariantId=variants.isEmpty?null:variants.first['id'].toString();
        if (!listings.any((x)=>x['id'].toString()==selectedListingId)) selectedListingId=listings.isEmpty?null:listings.first['id'].toString();
        _syncBranchPrice(); _syncListingPrices();
      });
    } catch(e) { if(mounted)setState(()=>error=friendlyError(e)); }
    finally { if(mounted)setState(()=>busy=false); }
  }
  void _syncBranchPrice() {
    if(selectedBranchId==null||selectedVariantId==null){branchPrice.clear();return;}
    branchPrice.text=_priceText(branchPrices[_branchKey(selectedBranchId!,selectedVariantId!)]);
  }
  void _syncListingPrices() {
    if(selectedListingId==null){listingBuyingPrice.clear();listingSellingPrice.clear();return;}
    listingBuyingPrice.text=_priceText(buyingPrices[selectedListingId!]);
    listingSellingPrice.text=_priceText(sellingPrices[selectedListingId!]);
  }
  Map<String,dynamic>? _selectedVariant(){for(final x in variants){if(x['id'].toString()==selectedVariantId)return x;}return null;}
  Map<String,dynamic>? _selectedListing(){for(final x in listings){if(x['id'].toString()==selectedListingId)return x;}return null;}

  Future<void> saveBranchPrice() async {
    if(saving)return;
    final value=double.tryParse(branchPrice.text.trim());
    if(selectedBranchId==null||selectedVariantId==null||value==null||value<=0){setState(()=>error='Select a branch and product variant, then enter a price greater than zero.');return;}
    setState(() { saving = true; error = null; });
    try{
      await db.from('branch_product_selling_prices').upsert({'branch_id':selectedBranchId,'product_variant_id':selectedVariantId,'selling_price_per_kg':value,'updated_by':db.auth.currentUser!.id},onConflict:'branch_id,product_variant_id');
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Branch selling price saved.')));
      await load();
    }catch(e){if(mounted)setState(()=>error=friendlyError(e));}
    finally{if(mounted)setState(()=>saving=false);}
  }
  Future<void> saveListingPrices() async {
    if(saving)return;
    final buying=double.tryParse(listingBuyingPrice.text.trim()), selling=double.tryParse(listingSellingPrice.text.trim());
    if(selectedListingId==null||buying==null||selling==null||buying<=0||selling<=0){setState(()=>error='Select a listing and enter both prices greater than zero.');return;}
    setState(() { saving = true; error = null; });
    try{
      await db.rpc('director_set_marketplace_listing_prices',params:{'p_listing_id':selectedListingId,'p_buying_price_kes':buying,'p_selling_price_kes':selling});
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Marketplace buying and selling prices saved.')));
      await load();
    }catch(e){if(mounted)setState(()=>error=friendlyError(e));}
    finally{if(mounted)setState(()=>saving=false);}
  }

  Widget _branchTab(){
    final selected=_selectedVariant();
    final product=(selected?['products'] as Map?)?.cast<String,dynamic>()??{};
    final weight=selected?['bag_weight_kg'] as num?;
    final entered=double.tryParse(branchPrice.text.trim());
    return RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.all(16),children:[
      const Text('Branch customer prices',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
      const Text('Set the public selling price in KES per kilogram. The app calculates the equivalent bag price using that variant’s configured bag weight.'),
      const SizedBox(height:14),
      DropdownButtonFormField<String>(value:selectedBranchId,decoration:const InputDecoration(labelText:'Branch',border:OutlineInputBorder()),items:branches.map((b)=>DropdownMenuItem(value:b['id'].toString(),child:Text(b['name'].toString()))).toList(),onChanged:saving?null:(v)=>setState(() { selectedBranchId = v; _syncBranchPrice(); })),
      const SizedBox(height:12),
      DropdownButtonFormField<String>(value:selectedVariantId,decoration:const InputDecoration(labelText:'Product variant',border:OutlineInputBorder()),items:variants.map((v){final p=(v['products'] as Map?)?.cast<String,dynamic>()??{};final label='${p['name']??'Product'} • ${v['variant_name']}';return DropdownMenuItem(value:v['id'].toString(),child:Text(label));}).toList(),onChanged:saving?null:(v)=>setState(() { selectedVariantId = v; _syncBranchPrice(); })),
      if(product.isNotEmpty)Padding(padding:const EdgeInsets.only(top:8),child:Text('Product: ${product['name']}')),
      if(weight!=null&&weight>0)Padding(padding:const EdgeInsets.symmetric(vertical:10),child:Text('Configured bag weight: ${weight.toStringAsFixed(2)} kg')),
      const SizedBox(height:8),
      TextField(controller:branchPrice,onChanged:(_)=>setState((){}),keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Selling price per KG (KES)',border:OutlineInputBorder())),
      if(weight!=null&&weight>0&&entered!=null)Padding(padding:const EdgeInsets.only(top:8),child:Text('Equivalent price per bag: KES ${(entered*weight).toStringAsFixed(2)}')),
      const SizedBox(height:14),
      FilledButton.icon(onPressed:saving||branches.isEmpty||variants.isEmpty?null:saveBranchPrice,icon:const Icon(Icons.save),label:Text(saving?'Saving…':'Save branch price')),
      if(branches.isEmpty||variants.isEmpty)const Padding(padding:EdgeInsets.only(top:12),child:Text('Add an active branch and product variant before setting a price.')),
    ]));
  }
  Widget _marketplaceTab(){
    final selected=_selectedListing();
    return RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.all(16),children:[
      const Text('Marketplace listing prices',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
      const Text('The buying price is private to the seller and Director. The selling price is shown to Buyers. Both are set by the Director.'),
      const SizedBox(height:14),
      DropdownButtonFormField<String>(value:selectedListingId,decoration:const InputDecoration(labelText:'Seller listing',border:OutlineInputBorder()),items:listings.map((l)=>DropdownMenuItem(value:l['id'].toString(),child:Text('${l['product_name']} • ${l['quantity']} ${l['unit']}'))).toList(),onChanged:saving?null:(v)=>setState(() { selectedListingId = v; _syncListingPrices(); })),
      if(selected!=null)Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Text('Location: ${selected['location']} • Status: ${selected['status']}')),
      const SizedBox(height:8),
      TextField(controller:listingBuyingPrice,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Buying price per listing unit (KES)',border:OutlineInputBorder())),
      const SizedBox(height:10),
      TextField(controller:listingSellingPrice,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Selling price per listing unit (KES)',border:OutlineInputBorder())),
      const SizedBox(height:14),
      FilledButton.icon(onPressed:saving||listings.isEmpty?null:saveListingPrices,icon:const Icon(Icons.price_change),label:Text(saving?'Saving…':'Save both marketplace prices')),
      if(listings.isEmpty)const Padding(padding:EdgeInsets.only(top:12),child:Text('No seller listings have been submitted yet.')),
    ]));
  }
  @override Widget build(BuildContext context)=>Column(children:[
    Material(color:Colors.white,child:TabBar(controller:tabs,labelColor:brandGreen,tabs:const[Tab(icon:Icon(Icons.storefront),text:'Branch prices'),Tab(icon:Icon(Icons.price_change),text:'Marketplace')])),
    if(busy)const LinearProgressIndicator(),
    if(error!=null)Padding(padding:const EdgeInsets.all(8),child:Text(error!,style:const TextStyle(color:Colors.red))),
    Expanded(child:TabBarView(controller:tabs,children:[_branchTab(),_marketplaceTab()])),
  ]);
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override State<HomeShell> createState() => _HomeShellState();
}
class _HomeShellState extends State<HomeShell> {
  bool checkingUpdate = false;
  Map<String, dynamic>? availableUpdate;

  Future<void> checkUpdates({bool showCurrent = false}) async {
    if (checkingUpdate) return;
    if (mounted) setState(() => checkingUpdate = true);
    final found = await checkTajirUpdate();
    if (!mounted) return;
    setState(() { availableUpdate = found; checkingUpdate = false; });
    if (found != null) {
      showDialog<void>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('TAJIR update available'),
        content: Text('A newer version (${found['version']}) is ready. Update to get the latest improvements and fixes.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Later')),
          FilledButton.icon(onPressed: () async {
            Navigator.pop(ctx);
            try { await openTajirUpdate(found['url'].toString()); }
            catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the update link. Please try again.'))); }
          }, icon: const Icon(Icons.download), label: const Text('Download update')),
        ],
      ));
    } else if (showCurrent) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('TAJIR is up to date.')));
    }
  }

  int index = 0;
  bool director = false;
  List<Widget> get pages => [DashboardPage(onOpenTractor: () => selectPage(5), onOpenItems: () => selectPage(3), onOpenFinancial: () => selectPage(6), onOpenStaff: () => selectPage(7)), const PurchasePage(), const SalePage(), const StockPage(), const CustomersPage(), const TractorServicesPage(), if (director) const FinancialRecordsPage(), if (director) const StaffAccountsPage()];
  List<String> get labels => ['Dashboard','Purchases','Sales','Stock','Customers','Tractor Services', if (director) 'Financial Records', if (director) 'Staff & Accounts'];
  List<IconData> get icons => [Icons.dashboard,Icons.add_shopping_cart,Icons.point_of_sale,Icons.inventory_2,Icons.people,Icons.agriculture, if (director) Icons.account_balance, if (director) Icons.manage_accounts];
  @override void initState() { super.initState(); loadAccess(); WidgetsBinding.instance.addPostFrameCallback((_) => checkUpdates()); }
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
      if (director) ListTile(leading: const Icon(Icons.manage_accounts), title: const Text('Staff & Accounts'), selected: index == 7, onTap: () { Navigator.pop(sheetContext); selectPage(7); }),
      const SizedBox(height: 8),
    ])));
  }
  @override Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 800;
    return Scaffold(
      appBar: AppBar(title: const Text('TAJIR'), actions: [IconButton(tooltip: checkingUpdate ? 'Checking for updates' : 'Check for updates', onPressed: checkingUpdate ? null : () => checkUpdates(showCurrent: true), icon: Icon(checkingUpdate ? Icons.hourglass_top : Icons.system_update)), IconButton(tooltip: 'Account security', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AccountSecurityPage())), icon: const Icon(Icons.lock_reset)), IconButton(tooltip: 'Sign out', onPressed: () => Supabase.instance.client.auth.signOut(scope: SignOutScope.local), icon: const Icon(Icons.logout))]),
      body: Column(children: [
        const TajirDirectorContacts(),
        Expanded(child: Row(children: [
          if (wide) NavigationRail(selectedIndex: index, onDestinationSelected: selectPage, labelType: NavigationRailLabelType.all, destinations: List.generate(labels.length, (i) => NavigationRailDestination(icon: Icon(icons[i]), label: Text(labels[i])))),
          Expanded(child: IndexedStack(index: index, children: pages)),
        ])),
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
  final VoidCallback? onOpenFinancial;
  final VoidCallback? onOpenStaff;
  const DashboardPage({super.key, this.onOpenTractor, this.onOpenItems, this.onOpenFinancial, this.onOpenStaff});
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
    if(director) ...[
      const SizedBox(height: 18),
      Card(child: ListTile(
        leading: const CircleAvatar(backgroundColor: Color(0xFFEAF4EC), child: Icon(Icons.analytics_outlined, color: brandGreen)),
        title: const Text('Director business overview', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('Open company-wide sales, purchases, payments, costs and profit reports'),
        trailing: const Icon(Icons.chevron_right),
        onTap: widget.onOpenFinancial,
      )),
    ],
    if(director) ...[
      const SizedBox(height: 8),
      Card(child: ListTile(
        leading: const CircleAvatar(backgroundColor: Color(0xFFEAF4EC), child: Icon(Icons.manage_accounts, color: brandGreen)),
        title: const Text('Staff & Accounts', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('Read-only directory of registered staff and assigned roles'),
        trailing: const Icon(Icons.chevron_right),
        onTap: widget.onOpenStaff,
      )),
    ],
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

class StaffAccountsPage extends StatefulWidget {
  const StaffAccountsPage({super.key});
  @override State<StaffAccountsPage> createState() => _StaffAccountsPageState();
}

class _StaffAccountsPageState extends State<StaffAccountsPage> {
  bool loading = true;
  String error = '';
  List<Map<String, dynamic>> accounts = [];

  @override void initState() { super.initState(); load(); }

  Future<void> load() async {
    if (mounted) setState(() { loading = true; error = ''; });
    try {
      final db = Supabase.instance.client;
      final roles = await db.from('user_role_assignments')
        .select('user_id,is_active,app_roles(name,code)')
        .eq('is_active', true);
      final profiles = await db.from('profiles').select('id,display_name').order('display_name');
      final names = <String, String>{
        for (final p in List<Map<String, dynamic>>.from(profiles))
          p['id'].toString(): (p['display_name'] ?? 'Unnamed account').toString()
      };
      final grouped = <String, List<String>>{};
      for (final row in List<Map<String, dynamic>>.from(roles)) {
        final id = row['user_id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final role = row['app_roles'];
        final label = role is Map ? (role['name'] ?? role['code'] ?? 'Assigned role').toString() : 'Assigned role';
        grouped.putIfAbsent(id, () => <String>[]).add(label);
      }
      final result = grouped.entries.map((entry) => <String, dynamic>{
        'user_id': entry.key,
        'name': names[entry.key] ?? 'Profile name unavailable',
        'roles': entry.value.toSet().toList()..sort(),
      }).toList()..sort((a,b) => a['name'].toString().compareTo(b['name'].toString()));
      if (mounted) setState(() => accounts = result);
    } catch (e) {
      if (mounted) setState(() => error = 'Could not load the staff directory: ${friendlyError(e)}');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: load,
    child: ListView(padding: const EdgeInsets.all(18), children: [
      const Text('Staff & Accounts', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      const Text('Director read-only view • PINs and passwords are never displayed'),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: Text('${accounts.length} accounts with active role assignments')),
        IconButton(tooltip: 'Refresh', onPressed: loading ? null : load, icon: const Icon(Icons.refresh)),
      ]),
      Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AttendanceRecordsPage())),
        icon: const Icon(Icons.event_note),
        label: const Text('View worker attendance'),
      )),
      if (loading) const LinearProgressIndicator(),
      if (error.isNotEmpty) Text(error, style: const TextStyle(color: Colors.red)),
      if (!loading && accounts.isEmpty && error.isEmpty) const Text('No active staff role assignments were found.'),
      ...accounts.map((account) => Card(child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person_outline)),
        title: Text(account['name'].toString()),
        subtitle: Text((account['roles'] as List<String>).join(' • ')),
        trailing: const Icon(Icons.visibility_outlined),
      ))),
      const Padding(padding: EdgeInsets.only(top: 12), child: Text(
        'This directory is read-only. It does not expose PINs, passwords, authentication tokens, or private login credentials.',
        style: TextStyle(fontSize: 12, color: Colors.black54),
      )),
    ]),
  );
}

class AttendanceRecordsPage extends StatefulWidget {
  const AttendanceRecordsPage({super.key});
  @override State<AttendanceRecordsPage> createState() => _AttendanceRecordsPageState();
}

class _AttendanceRecordsPageState extends State<AttendanceRecordsPage> {
  bool loading = true;
  String error = '';
  List<Map<String,dynamic>> rows = [];
  Map<String,String> names = {}, branches = {};

  @override void initState() { super.initState(); load(); }

  Future<void> load() async {
    if (mounted) setState(() { loading = true; error = ''; });
    try {
      final db = Supabase.instance.client;
      final result = await db.from('staff_attendance')
        .select('id,user_id,branch_id,check_in_at,check_out_at')
        .order('check_in_at', ascending: false).limit(200);
      rows = List<Map<String,dynamic>>.from(result);
      final userIds = rows.map((r) => r['user_id'].toString()).toSet().toList();
      final branchIds = rows.map((r) => r['branch_id'].toString()).toSet().toList();
      names = {};
      branches = {};
      if (userIds.isNotEmpty) {
        final profiles = await db.from('profiles').select('id,display_name').inFilter('id', userIds);
        for (final p in List<Map<String,dynamic>>.from(profiles)) {
          names[p['id'].toString()] = (p['display_name'] ?? 'Unnamed worker').toString();
        }
      }
      if (branchIds.isNotEmpty) {
        final locations = await db.from('branches').select('id,name').inFilter('id', branchIds);
        for (final b in List<Map<String,dynamic>>.from(locations)) {
          branches[b['id'].toString()] = (b['name'] ?? 'Branch').toString();
        }
      }
    } catch (e) {
      error = 'Could not load attendance records: ' + friendlyError(e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Worker attendance')),
    body: RefreshIndicator(onRefresh: load, child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(18),
      children: [
        const Text('Attendance records', style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
        const Text('Director-only view • Server-recorded check-in and check-out times'),
        if (loading) const LinearProgressIndicator(),
        if (error.isNotEmpty) Text(error, style: const TextStyle(color: Colors.red)),
        if (!loading && rows.isEmpty && error.isEmpty) const Text('No worker attendance has been recorded yet.'),
        ...rows.map((r) {
          final user = r['user_id'].toString();
          final branch = r['branch_id'].toString();
          final checkedOut = r['check_out_at'] != null;
          return Card(child: ListTile(
            leading: CircleAvatar(child: Icon(checkedOut ? Icons.event_available : Icons.timer)),
            title: Text(names[user] ?? 'Worker account'),
            subtitle: Text((branches[branch] ?? 'Branch') +
              '\nIn: ' + (r['check_in_at'] ?? '').toString() +
              '\nOut: ' + (r['check_out_at'] ?? 'Still checked in').toString()),
            isThreeLine: true,
            trailing: Text(checkedOut ? 'Closed' : 'Active'),
          ));
        }),
      ],
    )),
  );
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
  String quantityUnit = 'BAGS';
  String payer = 'Mercy';
  String? productId;
  String? selectedVariantId;
  List<Map<String, dynamic>> variants = [];
  bool busy = false;
  bool loadingVariants = false;
  String message = '';

  double? get selectedBagWeightKg {
    for (final variant in variants) {
      if (variant['id'] == selectedVariantId) return bagWeightKgForProduct(product, variant);
    }
    return bagWeightKgForProduct(product, null);
  }

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
          .select('id,variant_name,base_unit,sku,bag_weight_kg')
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
          .select('id,variant_name,base_unit,sku,bag_weight_kg')
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
    final enteredQuantity = double.tryParse(qty.text);
    final enteredCost = double.tryParse(cost.text);
    final bagWeightKg = selectedBagWeightKg;
    final q = enteredQuantity == null ? null : (quantityUnit == 'KG' ? (bagWeightKg == null ? null : enteredQuantity / bagWeightKg) : enteredQuantity);
    final c = enteredCost == null ? null : (quantityUnit == 'KG' ? (bagWeightKg == null ? null : enteredCost * bagWeightKg) : enteredCost);
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
    if (q == null || c == null || q <= 0 || c < 0 || selectedVariantId == null || (quantityUnit == 'KG' && bagWeightKg == null) || transport == null || loading == null || labour == null || drying == null || [transport,loading,labour,drying].any((v)=>v<0) || invalidCustomExpense) {
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
            .map((x) => DropdownMenuItem(value: x, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(productIconFor(x), size: 20, color: brandGreen), const SizedBox(width: 10), Text(x)])))
            .toList(),
        onChanged: (v) {
          if (v == null) return;
          setState(() { product = v; quantityUnit = 'BAGS'; });
          loadProductVariants();
        },
        decoration: const InputDecoration(labelText: 'Product'),
      ),
      if (loadingVariants) const LinearProgressIndicator(),
      DropdownButtonFormField<String>(
        value: variants.any((v) => v['id'] == selectedVariantId) ? selectedVariantId : null,
        items: variants.map((v) => DropdownMenuItem<String>(
          value: v['id'] as String,
          child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(productIconFor(product), size: 20, color: brandGreen), const SizedBox(width: 10), Flexible(child: Text('${v['sku'] ?? 'NO-ID'} • ${v['variant_name']}'))]),
        )).toList(),
        onChanged: (v) => setState(() {
          selectedVariantId = v;
          if (selectedBagWeightKg == null) quantityUnit = 'BAGS';
        }),
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
      DropdownButtonFormField<String>(
        value: quantityUnit,
        items: [
          const DropdownMenuItem(value: 'BAGS', child: Text('Bags')),
          if (selectedBagWeightKg != null)
            DropdownMenuItem(value: 'KG', child: Text('Kilograms (1 bag = ' + selectedBagWeightKg!.toStringAsFixed(0) + ' KG)')),
        ],
        onChanged: (v) => setState(() => quantityUnit = v ?? 'BAGS'),
        decoration: const InputDecoration(labelText: 'Quantity and price unit'),
      ),
      field(qty, 'Quantity (${quantityUnit == 'KG' ? 'KG' : 'bags'})', number: true, onChanged: () => setState(() {})),
      field(cost, 'Buying price per ${quantityUnit == 'KG' ? 'KG' : 'bag'} (KES)', number: true, onChanged: () => setState(() {})),
      if (qty.text.trim().isNotEmpty && cost.text.trim().isNotEmpty) Text(storedUnitSummary(quantityText: qty.text, priceText: cost.text, unit: quantityUnit, bagWeightKg: selectedBagWeightKg)),
      liveKgPriceSummary(quantityText: qty.text, unitPriceText: cost.text, quantityUnit: quantityUnit, bagWeightKg: selectedBagWeightKg),
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
  String quantityUnit = 'BAGS';
  String mode = 'collection';
  String method = 'cash';
  String? productId;
  String? selectedVariantId;
  List<Map<String, dynamic>> variants = [];
  bool busy = false;
  bool loadingVariants = false;
  String message = '';

  double? get selectedBagWeightKg {
    for (final variant in variants) {
      if (variant['id'] == selectedVariantId) return bagWeightKgForProduct(product, variant);
    }
    return bagWeightKgForProduct(product, null);
  }

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
          .select('id,variant_name,base_unit,sku,bag_weight_kg')
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
          .select('id,variant_name,base_unit,sku,bag_weight_kg')
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
    final enteredQuantity = double.tryParse(qty.text);
    final enteredPrice = double.tryParse(price.text);
    final bagWeightKg = selectedBagWeightKg;
    final q = enteredQuantity == null ? null : (quantityUnit == 'KG' ? (bagWeightKg == null ? null : enteredQuantity / bagWeightKg) : enteredQuantity);
    final p = enteredPrice == null ? null : (quantityUnit == 'KG' ? (bagWeightKg == null ? null : enteredPrice * bagWeightKg) : enteredPrice);
    final amount = double.tryParse(paid.text) ?? 0;
    final deliveryFee = double.tryParse(fee.text) ?? 0;
    if (q == null || p == null || q <= 0 || p < 0 || selectedVariantId == null || (quantityUnit == 'KG' && bagWeightKg == null) ||
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
            .map((x) => DropdownMenuItem(value: x, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(productIconFor(x), size: 20, color: brandGreen), const SizedBox(width: 10), Text(x)])))
            .toList(),
        onChanged: (v) {
          if (v == null) return;
          setState(() { product = v; quantityUnit = 'BAGS'; });
          loadProductVariants();
        },
        decoration: const InputDecoration(labelText: 'Product'),
      ),
      if (loadingVariants) const LinearProgressIndicator(),
      DropdownButtonFormField<String>(
        value: variants.any((v) => v['id'] == selectedVariantId) ? selectedVariantId : null,
        items: variants.map((v) => DropdownMenuItem<String>(
          value: v['id'] as String,
          child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(productIconFor(product), size: 20, color: brandGreen), const SizedBox(width: 10), Flexible(child: Text('${v['sku'] ?? 'NO-ID'} • ${v['variant_name']}'))]),
        )).toList(),
        onChanged: (v) => setState(() {
          selectedVariantId = v;
          if (selectedBagWeightKg == null) quantityUnit = 'BAGS';
        }),
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
      DropdownButtonFormField<String>(
        value: quantityUnit,
        items: [
          const DropdownMenuItem(value: 'BAGS', child: Text('Bags')),
          if (selectedBagWeightKg != null)
            DropdownMenuItem(value: 'KG', child: Text('Kilograms (1 bag = ' + selectedBagWeightKg!.toStringAsFixed(0) + ' KG)')),
        ],
        onChanged: (v) => setState(() => quantityUnit = v ?? 'BAGS'),
        decoration: const InputDecoration(labelText: 'Quantity and price unit'),
      ),
      field(qty, 'Quantity (${quantityUnit == 'KG' ? 'KG' : 'bags'})', number: true, onChanged: () => setState(() {})),
      field(price, 'Selling price per ${quantityUnit == 'KG' ? 'KG' : 'bag'} (KES)', number: true, onChanged: () => setState(() {})),
      if (qty.text.trim().isNotEmpty && price.text.trim().isNotEmpty) Text(storedUnitSummary(quantityText: qty.text, priceText: price.text, unit: quantityUnit, bagWeightKg: selectedBagWeightKg)),
      liveKgPriceSummary(quantityText: qty.text, unitPriceText: price.text, quantityUnit: quantityUnit, bagWeightKg: selectedBagWeightKg),
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
        leading:CircleAvatar(backgroundColor:brandGreen.withOpacity(.10),child:Icon(productIconFor((p['product_name']??p['name']??'').toString()),color:brandGreen)),
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
          const SizedBox(height: 8),
          if ((customer['profile_id']?.toString() ?? '').isNotEmpty) ...[
            TajirCallButton(profileId: customer['profile_id'].toString(), label: 'Call customer'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => showTajirNationalId(context, customer['profile_id'].toString()),
              icon: const Icon(Icons.verified_user_outlined),
              label: const Text('View National ID (Director only)'),
            ),
          ],
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

Widget liveKgPriceSummary({required String quantityText, required String unitPriceText, required String quantityUnit, required double? bagWeightKg}) {
  final enteredQuantity = double.tryParse(quantityText.trim());
  final enteredPrice = double.tryParse(unitPriceText.trim());
  if (bagWeightKg == null || bagWeightKg <= 0 || enteredQuantity == null || enteredPrice == null || enteredQuantity <= 0 || enteredPrice < 0) return const SizedBox.shrink();
  final quantityKg = quantityUnit == 'KG' ? enteredQuantity : enteredQuantity * bagWeightKg;
  final pricePerKg = quantityUnit == 'KG' ? enteredPrice : enteredPrice / bagWeightKg;
  final total = quantityKg * pricePerKg;
  return Card(color: brandGreen.withOpacity(.07), child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('LIVE KG PRICE CALCULATION', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
    const SizedBox(height: 5),
    Text('${quantityKg.toStringAsFixed(2)} KG  •  ${(quantityKg / bagWeightKg).toStringAsFixed(3)} bags'),
    Text('Price: KES ${pricePerKg.toStringAsFixed(2)} per KG'),
    Text('Total: KES ${total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
  ])));
}

Widget field(TextEditingController c,String label,{bool number=false,VoidCallback? onChanged})=>TextField(controller:c,onChanged:onChanged==null?null:(_)=>onChanged(),keyboardType:number?const TextInputType.numberWithOptions(decimal:true):TextInputType.text,decoration:InputDecoration(labelText:label,border:const OutlineInputBorder()));
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
  String entryUnit = 'BAGS';
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
    final enteredQ = double.tryParse(quantity.text.trim());
    final enteredP = double.tryParse(price.text.trim());
    final bagWeightKg = bagWeightKgForProduct(product, null);
    final q = enteredQ == null ? null : (entryUnit == 'KG' ? (bagWeightKg == null ? null : enteredQ / bagWeightKg) : enteredQ);
    final p = enteredP == null ? null : (entryUnit == 'KG' ? (bagWeightKg == null ? null : enteredP * bagWeightKg) : enteredP);
    if (q == null || q <= 0 || p == null || p < 0 || (entryUnit == 'KG' && bagWeightKg == null)) {
      setState(() => message = 'Enter a valid quantity and price.');
      return;
    }
    final item = <String, String>{
      'date': '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}',
      'product': product,
      'variety': product == 'Beans' ? beanVariety : product == 'Fertilizer' ? fertilizerType : '—',
      'quantity': q.toString(),
      'price': p.toStringAsFixed(2),
      'entered_unit': entryUnit,
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
            onChanged: (v) => setState(() { product = v ?? 'Maize'; entryUnit = 'BAGS'; message = ''; }),
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
          DropdownButtonFormField<String>(
            value: entryUnit,
            decoration: const InputDecoration(labelText: 'Quantity and price unit', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem(value: 'BAGS', child: Text('Bags')),
              if (bagWeightKgForProduct(product, null) != null)
                DropdownMenuItem(value: 'KG', child: Text('Kilograms (1 bag = ' + bagWeightKgForProduct(product, null)!.toStringAsFixed(0) + ' KG)')),
            ],
            onChanged: (v) => setState(() => entryUnit = v ?? 'BAGS'),
          ),
          const SizedBox(height: 12),
          TextField(controller: quantity, keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Quantity (${entryUnit == 'KG' ? 'KG' : 'bags'})', border: const OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: isSale ? 'Selling price per ${entryUnit == 'KG' ? 'KG' : 'bag'} (KES)' : 'Buying price per ${entryUnit == 'KG' ? 'KG' : 'bag'} (KES)',
                  border: const OutlineInputBorder())),
          if (quantity.text.trim().isNotEmpty && price.text.trim().isNotEmpty) Text(storedUnitSummary(quantityText: quantity.text, priceText: price.text, unit: entryUnit, bagWeightKg: bagWeightKgForProduct(product, null))),
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
          subtitle: Text('${r['date']}  |  ${stockQuantityLabel(r['product'] as String, double.tryParse(r['quantity'] ?? '0') ?? 0)}'),
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
          const Text('Net stock (bags)'), Text('${total.toStringAsFixed(2)} bags', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
          trailing: Text(stockQuantityLabel(row['product'] as String, quantity), textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.bold)),
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
          trailing: Text(stockQuantityLabel(e['product'] as String, double.tryParse(e['quantity'] ?? '0') ?? 0), textAlign: TextAlign.end),
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
