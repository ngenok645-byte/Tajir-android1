import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

const double kgPerBag = 90.0;

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
      final assetName = asset is Map ? (asset['name'] ?? '').toString().toLowerCase() : '';
      if (asset is Map && assetName.endsWith('.apk') && assetName.contains('signed')) {
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


class TajirDirectorContacts extends StatefulWidget {
  const TajirDirectorContacts({super.key});
  @override State<TajirDirectorContacts> createState() => _TajirDirectorContactsState();
}

class _TajirDirectorContactsState extends State<TajirDirectorContacts> {
  List<Map<String, dynamic>> directors = [];
  bool loading = true;
  String? error;

  @override void initState() {
    super.initState();
    loadDirectors();
  }

  Future<void> loadDirectors() async {
    try {
      // This narrowly scoped RPC returns only active Director contact details.
      // It is required because customer/staff RLS intentionally hides other profiles.
      final result = await Supabase.instance.client.rpc('tajir_director_contacts');
      if (mounted) setState(() {
        directors = List<Map<String, dynamic>>.from(result);
        loading = false;
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() {
        loading = false;
        error = friendlyError(e);
      });
    }
  }

  Future<void> callDirector(String phone) async {
    try {
      await callTajirPhone(phone);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e))),
      );
    }
  }

  @override Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.support_agent, color: brandGreen),
          SizedBox(width: 8),
          Expanded(child: Text('TAJIR Director contacts', style: TextStyle(fontWeight: FontWeight.bold))),
        ]),
        if (loading) const LinearProgressIndicator(),
        if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
        if (!loading && error == null && directors.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No active Director contacts are available.')),
        ...directors.map((director) {
          final name = (director['display_name'] ?? 'TAJIR Director').toString();
          final phone = (director['phone'] ?? '').toString();
          return ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(name),
            subtitle: const Text('Registered Director contact'),
            trailing: IconButton(
              tooltip: 'Call $name',
              onPressed: phone.trim().isEmpty ? null : () => callDirector(phone),
              icon: const Icon(Icons.call, color: brandGreen),
            ),
          );
        }),
      ]),
    ),
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
      child: Text('TAJIR setup required\n\nBuild with SUPABASE_URL and SUPABASE_ANON_KEY. See README.md.',
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
  bool _backgroundLogoutStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Sign out when TAJIR is sent to the background so reopening requires login.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _logoutWhenAppIsLeft();
    }
  }

  Future<void> _logoutWhenAppIsLeft() async {
    if (_backgroundLogoutStarted) return;
    _backgroundLogoutStarted = true;
    try {
      if (Supabase.instance.client.auth.currentSession != null) {
        await Supabase.instance.client.auth.signOut();
      }
    } catch (_) {
      // Do not block app closing if the network is unavailable.
    } finally {
      _backgroundLogoutStarted = false;
    }
  }

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
          const Text('Sign in or create your account.',
            textAlign: TextAlign.center),
          const SizedBox(height: 18),
          _choice(context, icon: Icons.admin_panel_settings_outlined,
            title: 'STAFF',
            subtitle: 'Director and authorised staff accounts.',
            button: 'Staff sign in',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LoginPage()))),
          const SizedBox(height: 10),
          _choice(context, icon: Icons.agriculture,
            title: 'CLIENTS & FARM SERVICES',
            subtitle: 'Buyers, sellers, farmers, tractor owners, drivers and other service users.',
            button: 'Client sign in / register',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CustomerAuthPage()))),
          const SizedBox(height: 8),
          const Text('New to TAJIR? Choose Client to create an account. Staff accounts are created by the Director.',
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
                decoration: const InputDecoration(labelText: 'Phone number', hintText: '07XXXXXXXX', border: OutlineInputBorder())),
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
                : 'Enter the phone number and PIN you used when your staff account was set up.',
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
  final nationalId = TextEditingController();
  final pin = TextEditingController();
  final confirmPin = TextEditingController();
  bool createAccount = true, busy = false;
  String? message;
  @override void dispose() {
    name.dispose(); phone.dispose(); nationalId.dispose(); pin.dispose(); confirmPin.dispose(); super.dispose();
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
          body: {'full_name': name.text.trim(), 'phone': normalized, 'pin': pin.text},
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
            TextField(controller: phone, keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone number', hintText: '07XXXXXXXX', border: OutlineInputBorder())),
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
  'Tractor & Machinery Services','My Bookings','My Branch','Buy from Farmers'
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
   case 6:
    return CustomerMarketPage(customer:c!,mode:'marketplace_buy');
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
     IconButton(tooltip:'Check for updates',onPressed:checkCustomerUpdates,icon:const Icon(Icons.system_update)),
     IconButton(tooltip:'Account security',onPressed:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>const AccountSecurityPage())),icon:const Icon(Icons.lock_reset)),
     IconButton(tooltip:'Refresh',onPressed:onSection?()=>setState((){}):load,icon:const Icon(Icons.refresh)),
     IconButton(tooltip:'Sign out',onPressed:()=>Supabase.instance.client.auth.signOut(),icon:const Icon(Icons.logout))
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
       Expanded(child:homeTile(title:'SELL PRODUCTS',subtitle:sell?'Choose a catalogue product and view the Director-approved TAJIR buying price':'Access locked',imageUrl:TajirPictures.sell,icon:Icons.storefront_outlined,section:1,locked:!sell))
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
      const SizedBox(height:10),
      homeTile(title:'BUY FROM FARMERS',subtitle:'Browse farmer offers at Director-approved TAJIR selling prices',imageUrl:TajirPictures.buy,icon:Icons.storefront_outlined,section:6,large:true),
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
    ...mechanics.map((m)=>Card(child:ListTile(isThreeLine:true,leading:const CircleAvatar(child:Icon(Icons.handyman)),title:Text(m['business_name'].toString()),subtitle:Text('${m['location']} • ${m['phone']}\n${(m['services'] as List).join(', ')}'),trailing:FilledButton(onPressed:()=>requestRepair(m),child:const Text('Choose')))))
   ])),
   RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.all(12),children:[
    const Text('Available spare parts',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
    const Text('Parts listed by approved auto-spares shops.'),
    if(!busy&&parts.isEmpty)const Padding(padding:EdgeInsets.all(20),child:Text('No spare parts are listed yet.')),
    ...parts.map((p){final shop=(p['auto_spares_profiles'] as Map?)?.cast<String,dynamic>()??{};return Card(child:ListTile(leading:const CircleAvatar(child:Icon(Icons.settings)),title:Text(p['part_name'].toString()),subtitle:Text('${shop['shop_name']??'Auto spares'} • ${shop['location']??''}\nRef: ${p['part_reference']??'Not supplied'} • Stock: ${p['quantity']} ${p['unit']}'),trailing:Text('KES ${p['price_kes']}',style:const TextStyle(fontWeight:FontWeight.bold))));})
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
    // One row per branch/product variant so the customer sees the price for the selected branch.
    r=await db.rpc('customer_list_tajir_products');
   }else if(widget.mode=='sell'){
    r=await db.from('marketplace_listings').select('id,seller_customer_id,product_name,description,quantity,unit,price_per_unit,location,status,total_value_kes,quantity_kg,branch_id,branches(name),marketplace_listing_buying_prices(buying_price_kes)').eq('seller_customer_id',widget.customer['id']).order('created_at',ascending:false);
   }else if(widget.mode=='marketplace_buy'){
    r=await db.from('marketplace_listings').select('id,seller_customer_id,product_name,description,quantity,unit,location,status,total_value_kes,branch_id,branches(name),marketplace_listing_selling_prices(selling_price_kes)').eq('status','active').neq('seller_customer_id',widget.customer['id']).order('created_at',ascending:false);
   }else{
    final marketplaceRows=await db.from('marketplace_purchase_requests').select('id,buyer_customer_id,listing_id,quantity,unit_price_kes,line_total_kes,message,status,created_at,listing:marketplace_listings!marketplace_purchase_requests_listing_id_fkey(product_name,unit,seller_customer_id)').order('created_at',ascending:false);
    final tajirRows=await db.from('customer_product_requests').select('id,quantity_requested,quantity_unit,quantity_kg,unit_price_per_kg,line_total_kes,note,status,created_at,products(name),product_variants(variant_name),branches(name)').order('created_at',ascending:false);
    final customRows=await db.from('customer_custom_product_requests').select('id,product_name,description,quantity,quantity_unit,proposed_unit_price_kes,agreed_unit_price_kes,director_response,request_direction,customer_confirmed_at,status,created_at').order('created_at',ascending:false);
    r=[
     ...List<Map<String,dynamic>>.from(marketplaceRows),
     ...List<Map<String,dynamic>>.from(tajirRows).map((x)=>{...x,'_is_tajir_request':true}),
     ...List<Map<String,dynamic>>.from(customRows).map((x)=>{...x,'_is_custom_request':true}),
    ]..sort((a,b)=>DateTime.parse(b['created_at'].toString()).compareTo(DateTime.parse(a['created_at'].toString())));
   }
   if(mounted)setState(()=>{rows=List<Map<String,dynamic>>.from(r),error=null});
  }catch(e){if(mounted)setState(()=>error=friendlyError(e));}
  if(mounted)setState(()=>busy=false);
 }

 Future<void> requestTajirProduct(Map<String,dynamic> item)async{
  final quantity=TextEditingController(text:'1');
  final note=TextEditingController();
  String unit='BAG';
  final price=(item['official_buy_price_per_kg'] as num?)?.toDouble();
  final branch=(item['branch_id']??'').toString();
  final variant=(item['variant_name']??'').toString();
  final product=(item['product_name']??'Product').toString();
  final title=variant.isNotEmpty&&variant.toLowerCase()!=product.toLowerCase()?product+' • '+variant:product;
  if(price==null||price<=0){
   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('TAJIR has not published an official price for this product at this branch yet.')));
   return;
  }
  final ok=await showDialog<bool>(context:context,builder:(x)=>StatefulBuilder(builder:(dialogContext,setDialogState)=>AlertDialog(
   title:Text('Request $title'),
   content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text('Branch: '+(item['branch_name']??'TAJIR branch').toString(),style:const TextStyle(fontWeight:FontWeight.w600)),
    Text('Official TAJIR price: KES '+price.toStringAsFixed(2)+' per KG'),
    const SizedBox(height:12),
    DropdownButtonFormField<String>(
     value:unit,
     decoration:const InputDecoration(labelText:'Quantity unit'),
     items:const [DropdownMenuItem(value:'KG',child:Text('Kilograms (KG)')),DropdownMenuItem(value:'BAG',child:Text('Bags (1 bag = 90 KG)'))],
     onChanged:(v)=>setDialogState(()=>unit=v??'BAG'),
    ),
    TextField(controller:quantity,keyboardType:const TextInputType.numberWithOptions(decimal:true),onChanged:(_)=>setDialogState((){}),decoration:InputDecoration(labelText:unit=='KG'?'Quantity in KG':'Quantity in bags')),
    const SizedBox(height:8),
    Builder(builder:(_){
     final q=double.tryParse(quantity.text.trim())??0;
     final kg=unit=='BAG'?q*kgPerBag:q;
     return Text('Equivalent: '+kg.toStringAsFixed(2)+' KG\nEstimated total: KES '+(kg*price).toStringAsFixed(2),style:const TextStyle(fontWeight:FontWeight.w600));
    }),
    const SizedBox(height:8),
    TextField(controller:note,maxLines:2,decoration:const InputDecoration(labelText:'Note (optional)')),
    const SizedBox(height:6),
    const Text('The Director controls the official price. TAJIR verifies the price and total again when your request is saved.',style:TextStyle(fontSize:12,color:Colors.black54)),
   ])),
   actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(dialogContext,true),child:const Text('Send request'))],
  )));
  if(ok==true){
   try{
    final amount=double.tryParse(quantity.text.trim());
    if(amount==null||amount<=0)throw const FormatException('Enter a quantity greater than zero.');
    await Supabase.instance.client.from('customer_product_requests').insert({
     'customer_id':widget.customer['id'],
     'branch_id':branch,
     'product_id':item['product_id'],
     'product_variant_id':item['product_variant_id'],
     'quantity_requested':amount,
     'quantity_unit':unit,
     'note':note.text.trim().isEmpty?null:note.text.trim(),
    });
    if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Your request was sent. TAJIR has applied the official branch price and calculated the total.')));
    await load();
   }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(friendlyError(e))));}
  }
  quantity.dispose();note.dispose();
 }

 Future<void> createCustomProductRequest(String direction)async{
  final product=TextEditingController(),description=TextEditingController(),quantity=TextEditingController(text:'1'),proposedPrice=TextEditingController();
  String unit='BAG';
  final ok=await showDialog<bool>(context:context,builder:(x)=>StatefulBuilder(builder:(dialogContext,setDialogState)=>AlertDialog(
   title:Text(direction=='SELL_TO_TAJIR'?'Offer an unlisted product to TAJIR':'Request a product not in TAJIR catalogue'),
   content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
    TextField(controller:product,decoration:const InputDecoration(labelText:'Product name')),
    TextField(controller:description,maxLines:2,decoration:const InputDecoration(labelText:'Description / specification (optional)')),
    DropdownButtonFormField<String>(value:unit,decoration:const InputDecoration(labelText:'Quantity unit'),items:const [DropdownMenuItem(value:'KG',child:Text('Kilograms (KG)')),DropdownMenuItem(value:'BAG',child:Text('Bags (1 bag = 90 KG)'))],onChanged:(v)=>setDialogState(()=>unit=v??'BAG')),
    TextField(controller:quantity,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:unit=='KG'?'Required quantity (KG)':'Required quantity (bags)')),
    TextField(controller:proposedPrice,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:unit=='KG'?'Your proposed price per KG (KES)':'Your proposed price per bag (KES)')),
    const SizedBox(height:8),
    Container(width:double.infinity,padding:const EdgeInsets.all(10),decoration:BoxDecoration(color:Colors.amber.shade50,borderRadius:BorderRadius.circular(10)),child:Text(direction=='SELL_TO_TAJIR'?'CLIENT-SUBMITTED OFFER • NOT AN OFFICIAL TAJIR BUYING PRICE. The Director must review and approve or negotiate the proposed amount before it becomes an official offer.':'CLIENT-SUBMITTED REQUEST • NOT AN OFFICIAL TAJIR SELLING PRICE. The Director must review and approve or negotiate the proposed amount before it becomes an official offer.',style:const TextStyle(fontSize:12,fontWeight:FontWeight.w600))),
   ])),
   actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(dialogContext,true),child:const Text('Submit request'))],
  )));
  if(ok==true){
   try{
    final name=product.text.trim(),q=double.tryParse(quantity.text.trim()),price=double.tryParse(proposedPrice.text.trim());
    if(name.length<2)throw const FormatException('Enter the product name.');
    if(q==null||q<=0)throw const FormatException('Enter a quantity greater than zero.');
    if(price==null||price<=0)throw const FormatException('Enter a proposed price greater than zero.');
    await Supabase.instance.client.from('customer_custom_product_requests').insert({
     'customer_id':widget.customer['id'],
     'product_name':name,
     'description':description.text.trim().isEmpty?null:description.text.trim(),
     'quantity':q,
     'quantity_unit':unit,
     'proposed_unit_price_kes':price,
     'request_direction':direction,
    });
    if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(direction=='SELL_TO_TAJIR'?'Your product offer was submitted for Director review. It is not an official TAJIR buying price.':'Your custom product request was submitted for Director review. It is not an official TAJIR selling price.')));
    await load();
   }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(friendlyError(e))));}
  }
  product.dispose();description.dispose();quantity.dispose();proposedPrice.dispose();
 }
 Future<void> confirmCustomRequest(Map<String,dynamic> row)async{
  try{
   await Supabase.instance.client.rpc('customer_confirm_custom_product_request',params:{'p_request_id':row['id']});
   if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('You confirmed the Director-approved offer. TAJIR can now proceed with the request.')));
   await load();
  }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(friendlyError(e))));}
 }
 Future<void> createListing()async{
  final quantity=TextEditingController(text:'1');
  final location=TextEditingController();
  final description=TextEditingController();
  try{
   final result=await Supabase.instance.client.rpc('customer_list_tajir_sell_products');
   final options=List<Map<String,dynamic>>.from(result);
   if(options.isEmpty){
    if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('TAJIR has not set a buying price for any sellable product yet. Please contact the Director.')));
    return;
   }
   String optionKey(Map<String,dynamic> item)=>item['branch_id'].toString()+'|'+item['product_variant_id'].toString();
   String selectedKey=optionKey(options.first);
   String unit='BAG';
   final ok=await showDialog<bool>(context:context,builder:(dialogContext)=>StatefulBuilder(builder:(dialogContext,setDialogState){
    final selected=options.firstWhere((o)=>optionKey(o)==selectedKey);
    final price=(selected['official_tajir_buy_price_per_kg'] as num).toDouble();
    final q=double.tryParse(quantity.text.trim())??0;
    final kg=unit=='BAG'?q*kgPerBag:q;
    return AlertDialog(
     title:const Text('Offer produce to TAJIR'),
     content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
      DropdownButtonFormField<String>(
       value:selectedKey,
       isExpanded:true,
       decoration:const InputDecoration(labelText:'TAJIR catalogue product and branch'),
       items:options.map((o)=>DropdownMenuItem<String>(value:optionKey(o),child:Text((o['product_name']??'Product').toString()+' • '+(o['variant_name']??'Standard').toString()+' — '+(o['branch_name']??'Branch').toString(),overflow:TextOverflow.ellipsis))).toList(),
       onChanged:(v)=>setDialogState(()=>selectedKey=v??selectedKey),
      ),
      const SizedBox(height:10),
      Text('Director-approved TAJIR BUY price: KES '+price.toStringAsFixed(2)+' per KG',style:const TextStyle(fontWeight:FontWeight.w600)),
      DropdownButtonFormField<String>(
       value:unit,
       decoration:const InputDecoration(labelText:'Quantity unit'),
       items:const [DropdownMenuItem(value:'KG',child:Text('Kilograms (KG)')),DropdownMenuItem(value:'BAG',child:Text('Bags (1 bag = 90 KG)'))],
       onChanged:(v)=>setDialogState(()=>unit=v??'BAG'),
      ),
      TextField(controller:quantity,keyboardType:const TextInputType.numberWithOptions(decimal:true),onChanged:(_)=>setDialogState((){}),decoration:InputDecoration(labelText:unit=='BAG'?'Quantity in bags':'Quantity in KG')),
      const SizedBox(height:8),
      Text('Equivalent: '+kg.toStringAsFixed(2)+' KG\nEstimated amount TAJIR pays: KES '+(kg*price).toStringAsFixed(2),style:const TextStyle(fontWeight:FontWeight.w600)),
      TextField(controller:location,decoration:const InputDecoration(labelText:'Produce location / collection point')),
      TextField(controller:description,maxLines:2,decoration:const InputDecoration(labelText:'Quality, variety or other details (optional)')),
      const SizedBox(height:6),
      const Text('The Director controls this price. The database checks it again when your offer is saved. You cannot enter or change the official amount.',style:TextStyle(fontSize:12,color:Colors.black54)),
     ])),
     actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(dialogContext,true),child:const Text('Submit offer'))],
    );
   }));
   if(ok==true){
    final selected=options.firstWhere((o)=>optionKey(o)==selectedKey);
    final amount=double.tryParse(quantity.text.trim());
    if(amount==null||amount<=0)throw const FormatException('Enter a quantity greater than zero.');
    if(location.text.trim().length<3)throw const FormatException('Enter the produce location or collection point.');
    final price=(selected['official_tajir_buy_price_per_kg'] as num).toDouble();
    final productName=(selected['product_name']??'Product').toString();
    final variant=(selected['variant_name']??'').toString();
    await Supabase.instance.client.from('marketplace_listings').insert({
     'seller_customer_id':widget.customer['id'],
     'product_name':variant.isNotEmpty&&variant.toLowerCase()!=productName.toLowerCase()?productName+' • '+variant:productName,
     'description':description.text.trim().isEmpty?null:description.text.trim(),
     'quantity':amount,
     'unit':unit,
     'price_per_unit':unit=='BAG'?price*kgPerBag:price,
     'location':location.text.trim(),
     'status':'active',
     'product_variant_id':selected['product_variant_id'],
     'branch_id':selected['branch_id'],
    });
    if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Your produce offer was submitted using the official TAJIR buying price.')));
    await load();
   }
  }catch(e){
   if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(friendlyError(e))));
  }finally{
   quantity.dispose();location.dispose();description.dispose();
  }
 }
 Future<void> requestBuy(Map<String,dynamic> item)async{
  final priceRow=(item['marketplace_listing_selling_prices'] as Map?)?.cast<String,dynamic>()??{};
  final price=(priceRow['selling_price_kes'] as num?)?.toDouble();
  if(price==null||price<=0){
   if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('The Director has not set the official selling price for this listing yet.')));
   return;
  }
  final quantity=TextEditingController(text:'1');
  final available=(item['quantity'] as num).toDouble();
  final unit=(item['unit']??'BAG').toString();
  final product=(item['product_name']??'Produce').toString();
  final ok=await showDialog<bool>(context:context,builder:(dialogContext)=>StatefulBuilder(builder:(dialogContext,setDialogState){
   final q=double.tryParse(quantity.text.trim())??0;
   return AlertDialog(
    title:Text('Request $product'),
    content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
     Text('Official TAJIR SELL price: KES '+price.toStringAsFixed(2)+' per '+unit,style:const TextStyle(fontWeight:FontWeight.w600)),
     Text('Available: '+available.toStringAsFixed(2)+' '+unit),
     TextField(controller:quantity,keyboardType:const TextInputType.numberWithOptions(decimal:true),onChanged:(_)=>setDialogState((){}),decoration:InputDecoration(labelText:'Quantity in '+unit)),
     const SizedBox(height:8),
     Text('Estimated total: KES '+(q*price).toStringAsFixed(2),style:const TextStyle(fontWeight:FontWeight.w600)),
     const SizedBox(height:4),
     const Text('The Director-approved price and total are checked and saved by TAJIR when you submit.',style:TextStyle(fontSize:12,color:Colors.black54)),
    ]),
    actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(dialogContext,true),child:const Text('Send request'))],
   );
  }));
  if(ok==true){
   try{
    final amount=double.tryParse(quantity.text.trim());
    if(amount==null||amount<=0)throw const FormatException('Enter a quantity greater than zero.');
    if(amount>available)throw const FormatException('Quantity exceeds the available listing quantity.');
    await Supabase.instance.client.from('marketplace_purchase_requests').insert({
     'listing_id':item['id'],
     'buyer_customer_id':widget.customer['id'],
     'quantity':amount,
    });
    if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Purchase request sent. TAJIR saved the official unit price and total.')));
    await load();
   }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(friendlyError(e))));}
  }
  quantity.dispose();
 }
 Future<void> change(Map<String,dynamic> r,String value,bool listing)async{try{await Supabase.instance.client.from(listing?'marketplace_listings':'marketplace_purchase_requests').update({'status':value}).eq('id',r['id']);await load();}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(friendlyError(e))));}}
 @override Widget build(BuildContext context)=>RefreshIndicator(
  onRefresh:load,
  child:ListView(padding:const EdgeInsets.all(16),children:[
   Row(children:[
    Expanded(child:Text(widget.mode=='buy'?'TAJIR products available':widget.mode=='sell'?'Your produce offers':widget.mode=='marketplace_buy'?'Farmer marketplace':'Purchase requests',style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold))),
    if(widget.mode=='sell')FilledButton(onPressed:createListing,child:const Text('Offer produce')),
   ]),
   if(widget.mode=='buy')Align(alignment:Alignment.centerRight,child:OutlinedButton.icon(onPressed:()=>createCustomProductRequest('BUY_FROM_TAJIR'),icon:const Icon(Icons.add_circle_outline),label:const Text('Request unlisted product'))),
   if(widget.mode=='sell')Align(alignment:Alignment.centerRight,child:OutlinedButton.icon(onPressed:()=>createCustomProductRequest('SELL_TO_TAJIR'),icon:const Icon(Icons.add_circle_outline),label:const Text('Offer unlisted product to TAJIR'))),
   if(busy)const LinearProgressIndicator(),
   if(error!=null)Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Text(error!,style:const TextStyle(color:Colors.red))),
   if(!busy&&rows.isEmpty)Padding(padding:const EdgeInsets.symmetric(vertical:20),child:Text(widget.mode=='buy'?'No TAJIR stock is currently available. Please check again or contact your branch.':widget.mode=='marketplace_buy'?'No farmer offers are available at the moment.':'No marketplace records yet.')),
   ...rows.map((r){
    if(widget.mode=='buy'){
     final variant=(r['variant_name']??'').toString();
     final product=(r['product_name']??'Product').toString();
     final title=variant.isNotEmpty&&variant.toLowerCase()!=product.toLowerCase()?product+' • '+variant:product;
     final price=(r['official_buy_price_per_kg'] as num?)?.toDouble();
     final branch=(r['branch_name']??'TAJIR branch').toString();
     return Card(child:ListTile(
      leading:const CircleAvatar(child:Icon(Icons.inventory_2_outlined)),
      title:Text(title),
      subtitle:Text(branch+'\n'+(price==null?'Official price not set':'Official TAJIR price: KES '+price.toStringAsFixed(2)+' / KG')),
      isThreeLine:true,
      trailing:FilledButton.tonal(onPressed:price==null?null:()=>requestTajirProduct(r),child:const Text('Select'))
     ));
    }
    if(widget.mode=='marketplace_buy'){
     final priceRow=(r['marketplace_listing_selling_prices'] as Map?)?.cast<String,dynamic>()??{};
     final price=(priceRow['selling_price_kes'] as num?)?.toDouble();
     final quantity=(r['quantity'] as num?)?.toDouble()??0;
     final unit=(r['unit']??'BAG').toString();
     final branch=(r['branches'] as Map?)?.cast<String,dynamic>()??{};
     return Card(child:ListTile(
      leading:const CircleAvatar(child:Icon(Icons.storefront_outlined)),
      title:Text((r['product_name']??'Produce').toString()),
      subtitle:Text('Available: '+quantity.toStringAsFixed(2)+' '+unit+' • '+(branch['name']??'TAJIR branch').toString()+' • '+(r['location']??'').toString()+'\n'+(price==null?'Official TAJIR SELL price pending Director approval':'Official TAJIR SELL price: KES '+price.toStringAsFixed(2)+' / '+unit+' • Total for available quantity: KES '+(quantity*price).toStringAsFixed(2))),
      isThreeLine:true,
      trailing:FilledButton.tonal(onPressed:price==null?null:()=>requestBuy(r),child:const Text('Select')),
     ));
    }
    if(widget.mode=='requests'){
     if(r['_is_custom_request']==true){
      final unit=(r['quantity_unit']??'KG').toString();
      final response=(r['director_response']??'').toString();
      final agreed=r['agreed_unit_price_kes'];
      return Card(child:ListTile(
       leading:const Icon(Icons.assignment_late_outlined,color:Colors.deepOrange),
       title:Text((r['product_name']??'Custom product').toString()),
       subtitle:Text('CLIENT-SUBMITTED • NOT OFFICIAL TAJIR PRICE\n'+((r['request_direction']??'BUY_FROM_TAJIR')=='SELL_TO_TAJIR'?'Offer to sell to TAJIR':'Request to buy from TAJIR')+'\nQuantity: '+r['quantity'].toString()+' '+unit+' • Proposed: KES '+r['proposed_unit_price_kes'].toString()+'/'+unit+(agreed==null?'':' • Director agreed: KES '+agreed.toString()+'/'+unit)+'\nStatus: '+r['status'].toString()+(response.isEmpty?'':'\nDirector: '+response)),
       isThreeLine:true,
       trailing:r['customer_confirmed_at']!=null
        ? const Icon(Icons.verified,color:brandGreen)
        : r['status']=='approved'
         ? FilledButton.tonal(onPressed:()=>confirmCustomRequest(r),child:const Text('Confirm offer'))
         : const Icon(Icons.hourglass_top),
      ));
     }
     if(r['_is_tajir_request']==true){
      final p=(r['products'] as Map?)?.cast<String,dynamic>()??{};
      final v=(r['product_variants'] as Map?)?.cast<String,dynamic>()??{};
      final name=(p['name']??'TAJIR product').toString();
      final variant=(v['variant_name']??'').toString();
      return Card(child:ListTile(
       leading:const Icon(Icons.inventory_2_outlined),
       title:Text(variant.isEmpty?name:'$name • $variant'),
       subtitle:Text('Quantity: '+r['quantity_requested'].toString()+' '+(r['quantity_unit']??'BAG').toString()+' • '+(r['branches'] is Map?(r['branches'] as Map)['name']??'TAJIR branch':'TAJIR branch').toString()+'\nOfficial total: KES '+(r['line_total_kes']??'Pending').toString()+' • '+r['status'].toString()),
       trailing:const Icon(Icons.hourglass_top),
      ));
     }
     final l=(r['listing'] as Map?)?.cast<String,dynamic>()??{};
     final seller=l['seller_customer_id']==widget.customer['id'];
     return Card(child:ListTile(
      title:Text((l['product_name']??'Purchase request').toString()),
      subtitle:Text('Quantity: '+r['quantity'].toString()+' '+(l['unit']??'').toString()+' • Official price: KES '+(r['unit_price_kes']??'Pending').toString()+' / '+(l['unit']??'unit').toString()+' • Total: KES '+(r['line_total_kes']??'Pending').toString()+' • '+r['status'].toString()),
      trailing:seller&&r['status']=='pending'?PopupMenuButton<String>(onSelected:(v)=>change(r,v,false),itemBuilder:(_)=>const [PopupMenuItem(value:'accepted',child:Text('Accept')),PopupMenuItem(value:'declined',child:Text('Decline'))]):seller&&r['status']=='accepted'?TextButton(onPressed:()=>change(r,'completed',false),child:const Text('Complete')):null
     ));
    }
    final branch=(r['branches'] as Map?)?.cast<String,dynamic>()??{};
    final buyingRow=(r['marketplace_listing_buying_prices'] as Map?)?.cast<String,dynamic>()??{};
    final officialBuy=buyingRow['buying_price_kes']??r['price_per_unit'];
    final buyValue=double.tryParse(officialBuy.toString())??0;
    final listingQuantity=(r['quantity'] as num?)?.toDouble()??0;
    return Card(child:ListTile(
     leading:const Icon(Icons.local_florist_outlined,color:brandGreen),
     title:Text(r['product_name'].toString()),
     subtitle:Text('Quantity: '+r['quantity'].toString()+' '+r['unit'].toString()+' • TAJIR BUY price: KES '+officialBuy.toString()+' / '+r['unit'].toString()+' • Total: KES '+(buyValue*listingQuantity).toStringAsFixed(2)+' • '+(branch['name']??'TAJIR branch').toString()+' • '+r['location'].toString()),
     isThreeLine:true,
     trailing:(r['status']=='sold'||listingQuantity<=0)?null:PopupMenuButton<String>(onSelected:(v)=>change(r,v,true),itemBuilder:(_)=>const [PopupMenuItem(value:'active',child:Text('Active')),PopupMenuItem(value:'paused',child:Text('Pause')),PopupMenuItem(value:'sold',child:Text('Sold'))])
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
      IconButton(tooltip: 'Sign out', onPressed: () => db.auth.signOut(), icon: const Icon(Icons.logout)),
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
      IconButton(tooltip: 'Sign out', onPressed: () => db.auth.signOut(), icon: const Icon(Icons.logout)),
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
        FilledButton(onPressed: () => Supabase.instance.client.auth.signOut(), child: const Text('Return to sign in')),
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
  bool accountant = false;
  bool branchManager = false;
  bool accessLoaded = false;
  String? accessError;
  List<Widget> get pages {
    if (accountant && !director && !branchManager) {
      return [
        DashboardPage(onOpenItems: () => selectPage(1), onOpenFinancial: () => selectPage(2)),
        const StockPage(),
        const FinancialRecordsPage(),
      ];
    }
    return [
      DashboardPage(onOpenTractor: () => selectPage(5), onOpenItems: () => selectPage(3), onOpenFinancial: () => selectPage(6), onOpenStaff: () => selectPage(7), onOpenPrices: () => selectPage(8), onOpenCustomRequests: () => selectPage(9), onOpenMarketplacePrices: () => selectPage(10)),
      const PurchasePage(), const SalePage(), const StockPage(), const CustomersPage(), const TractorServicesPage(),
      if (director || accountant) const FinancialRecordsPage(),
      if (director) const StaffAccountsPage(),
      if (director) const DirectorPriceManagementPage(),
      if (director) const DirectorCustomProductRequestsPage(),
      if (director) const DirectorMarketplacePricesPage(),
    ];
  }
  List<String> get labels => accountant && !director && !branchManager
    ? ['Dashboard','Stock','Financial Records']
    : ['Dashboard','Purchases','Sales','Stock','Customers','Tractor Services', if (director || accountant) 'Financial Records', if (director) 'Staff & Accounts', if (director) 'Catalogue Prices', if (director) 'Custom Requests', if (director) 'Marketplace Prices'];
  List<IconData> get icons => accountant && !director && !branchManager
    ? [Icons.dashboard,Icons.inventory_2,Icons.account_balance]
    : [Icons.dashboard,Icons.add_shopping_cart,Icons.point_of_sale,Icons.inventory_2,Icons.people,Icons.agriculture, if (director || accountant) Icons.account_balance, if (director) Icons.manage_accounts, if (director) Icons.price_change_outlined, if (director) Icons.fact_check_outlined, if (director) Icons.storefront_outlined];
  @override void initState() { super.initState(); loadAccess(); WidgetsBinding.instance.addPostFrameCallback((_) => checkUpdates()); }
  Future<void> loadAccess() async {
    try {
      final rows = await Supabase.instance.client.from('user_role_assignments').select('app_roles(code)').eq('user_id', Supabase.instance.client.auth.currentUser!.id).eq('is_active', true);
      final allowed = rows.any((r) => r['app_roles'] is Map && (r['app_roles'] as Map)['code'] == 'director');
      final finance = rows.any((r) => r['app_roles'] is Map && (r['app_roles'] as Map)['code'] == 'accountant');
      final manager = rows.any((r) => r['app_roles'] is Map && (r['app_roles'] as Map)['code'] == 'branch_manager');
      if (mounted) setState(() { director = allowed; accountant = finance; branchManager = manager; accessLoaded = true; index = 0; });
    } catch (_) { if (mounted) setState(() { director = false; accountant = false; branchManager = false; accessError = 'Could not verify your role permissions. Please sign in again.'; accessLoaded = true; index = 0; }); }
  }
  void selectPage(int value) { if (value >= 0 && value < pages.length) setState(() => index = value); }
  void openMoreMenu() {
    showModalBottomSheet<void>(context: context, builder: (sheetContext) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(leading: const Icon(Icons.people), title: const Text('Customers'), selected: index == 4, onTap: () { Navigator.pop(sheetContext); selectPage(4); }),
      ListTile(leading: const Icon(Icons.agriculture), title: const Text('Tractor Services'), selected: index == 5, onTap: () { Navigator.pop(sheetContext); selectPage(5); }),
      if (director || accountant) ListTile(leading: const Icon(Icons.account_balance), title: const Text('Financial Records'), selected: index == 6, onTap: () { Navigator.pop(sheetContext); selectPage(6); }),
      if (director) ListTile(leading: const Icon(Icons.manage_accounts), title: const Text('Staff & Accounts'), selected: index == 7, onTap: () { Navigator.pop(sheetContext); selectPage(7); }),
      if (director) ListTile(leading: const Icon(Icons.price_change_outlined), title: const Text('Catalogue Prices'), selected: index == 8, onTap: () { Navigator.pop(sheetContext); selectPage(8); }),
      if (director) ListTile(leading: const Icon(Icons.fact_check_outlined), title: const Text('Custom Requests'), selected: index == 9, onTap: () { Navigator.pop(sheetContext); selectPage(9); }),
      if (director) ListTile(leading: const Icon(Icons.storefront_outlined), title: const Text('Marketplace Prices'), selected: index == 10, onTap: () { Navigator.pop(sheetContext); selectPage(10); }),
      const SizedBox(height: 8),
    ])));
  }
  @override Widget build(BuildContext context) {
    if (!accessLoaded) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (accessError != null) return const AccountAccessIssuePage();
    final wide = MediaQuery.of(context).size.width >= 800;
    return Scaffold(
      appBar: AppBar(title: const Text('TAJIR'), actions: [IconButton(tooltip: checkingUpdate ? 'Checking for updates' : 'Check for updates', onPressed: checkingUpdate ? null : () => checkUpdates(showCurrent: true), icon: Icon(checkingUpdate ? Icons.hourglass_top : Icons.system_update)), IconButton(tooltip: 'Account security', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AccountSecurityPage())), icon: const Icon(Icons.lock_reset)), IconButton(tooltip: 'Sign out', onPressed: () => Supabase.instance.client.auth.signOut(), icon: const Icon(Icons.logout))]),
      body: Column(children: [
        const TajirDirectorContacts(),
        Expanded(child: Row(children: [
          if (wide) NavigationRail(selectedIndex: index, onDestinationSelected: selectPage, labelType: NavigationRailLabelType.all, destinations: List.generate(labels.length, (i) => NavigationRailDestination(icon: Icon(icons[i]), label: Text(labels[i])))),
          Expanded(child: IndexedStack(index: index, children: pages)),
        ])),
      ]),
      bottomNavigationBar: wide ? null : NavigationBar(
        selectedIndex: accountant && !director && !branchManager ? index : (index < 4 ? index : 4),
        onDestinationSelected: accountant && !director && !branchManager ? selectPage : (v) { if (v == 4) { openMoreMenu(); } else { selectPage(v); } },
        destinations: accountant && !director && !branchManager ? const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.inventory_2), label: 'Stock'),
          NavigationDestination(icon: Icon(Icons.account_balance), label: 'Financials'),
        ] : const [
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
  final VoidCallback? onOpenPrices;
  final VoidCallback? onOpenCustomRequests;
  final VoidCallback? onOpenMarketplacePrices;
  const DashboardPage({super.key, this.onOpenTractor, this.onOpenItems, this.onOpenFinancial, this.onOpenStaff, this.onOpenPrices, this.onOpenCustomRequests, this.onOpenMarketplacePrices});
  @override State<DashboardPage> createState() => _DashboardPageState();
}
class _DashboardPageState extends State<DashboardPage> {
  String role = 'Loading role…'; List<Map<String,dynamic>> stock = [], branches = [], pendingRequests = []; String? error, selectedBranch; bool director = false, accountant = false, branchManager = false;
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
      accountant = assigned.any((r) => r['app_roles'] is Map && (r['app_roles'] as Map)['code']=='accountant');
      branchManager = assigned.any((r) => r['app_roles'] is Map && (r['app_roles'] as Map)['code']=='branch_manager');
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
    if(!accountant || branchManager) TajirImageTile(
      title:'TRACTOR & MACHINERY SERVICES',
      subtitle:'Manage machines, providers, bookings, operators and payments',
      imageUrl:TajirPictures.tractor,
      icon:Icons.agriculture,
      large:true,
      onTap:widget.onOpenTractor ?? _noDashboardAction,
    ),
    if(director || accountant) ...[
      const SizedBox(height: 18),
      Card(child: ListTile(
        leading: const CircleAvatar(backgroundColor: Color(0xFFEAF4EC), child: Icon(Icons.analytics_outlined, color: brandGreen)),
        title: Text(director ? 'Director business overview' : 'Accountant financial overview', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('Open authorised sales, purchases, payments, costs and profit reports'),
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
    if(director) ...[
      const SizedBox(height: 8),
      Card(child: ListTile(
        leading: const CircleAvatar(backgroundColor: Color(0xFFEAF4EC), child: Icon(Icons.price_change_outlined, color: brandGreen)),
        title: const Text('Director Catalogue Prices', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('Set separate TAJIR selling prices and TAJIR buying prices per KG for each branch'),
        trailing: const Icon(Icons.chevron_right),
        onTap: widget.onOpenPrices,
      )),
    ],
    if(director) ...[
      const SizedBox(height: 8),
      Card(child: ListTile(
        leading: const CircleAvatar(backgroundColor: Color(0xFFFFF3E0), child: Icon(Icons.fact_check_outlined, color: Colors.deepOrange)),
        title: const Text('Customer Custom Requests', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('Review unlisted product requests and offers, set the agreed price, or decline'),
        trailing: const Icon(Icons.chevron_right),
        onTap: widget.onOpenCustomRequests,
      )),
    ],
    if(director) ...[
      const SizedBox(height: 8),
      Card(child: ListTile(
        leading: const CircleAvatar(backgroundColor: Color(0xFFEAF4EC), child: Icon(Icons.storefront_outlined, color: brandGreen)),
        title: const Text('Marketplace Listing Prices', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('Set separate TAJIR BUY and TAJIR SELL prices for farmer-listed produce'),
        trailing: const Icon(Icons.chevron_right),
        onTap: widget.onOpenMarketplacePrices,
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
    if(!accountant || branchManager) OutlinedButton.icon(onPressed:()=>showDialog<void>(context:context,builder:(_)=>const Dialog(child:SizedBox(width:520,height:560,child:BranchRequestPanel()))),icon:const Icon(Icons.add_location_alt),label:const Text('Request a new branch')),
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
    final enteredQuantity = double.tryParse(qty.text);
    final enteredCost = double.tryParse(cost.text);
    final q = enteredQuantity == null ? null : (quantityUnit == 'KG' ? enteredQuantity / kgPerBag : enteredQuantity);
    final c = enteredCost == null ? null : (quantityUnit == 'KG' ? enteredCost * kgPerBag : enteredCost);
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
            .map((x) => DropdownMenuItem(value: x, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(productIconFor(x), size: 20, color: brandGreen), const SizedBox(width: 10), Text(x)])))
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
          child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(productIconFor(product), size: 20, color: brandGreen), const SizedBox(width: 10), Flexible(child: Text('${v['sku'] ?? 'NO-ID'} • ${v['variant_name']}'))]),
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
      DropdownButtonFormField<String>(
        value: quantityUnit,
        items: const [DropdownMenuItem(value: 'BAGS', child: Text('Bags (1 bag = 90 KG)')), DropdownMenuItem(value: 'KG', child: Text('Kilograms (KG)'))],
        onChanged: (v) => setState(() => quantityUnit = v ?? 'BAGS'),
        decoration: const InputDecoration(labelText: 'Quantity and price unit'),
      ),
      field(qty, 'Quantity (${quantityUnit == 'KG' ? 'KG' : 'bags'})', number: true, onChanged: () => setState(() {})),
      field(cost, 'Buying price per ${quantityUnit == 'KG' ? 'KG' : 'bag'} (KES)', number: true, onChanged: () => setState(() {})),
      if (qty.text.trim().isNotEmpty && cost.text.trim().isNotEmpty) Text('Stored as: ${(double.tryParse(qty.text.trim()) == null ? 0 : (quantityUnit == 'KG' ? double.parse(qty.text.trim()) / kgPerBag : double.parse(qty.text.trim()))).toStringAsFixed(3)} bags • ${(double.tryParse(cost.text.trim()) == null ? 0 : (quantityUnit == 'KG' ? double.parse(cost.text.trim()) * kgPerBag : double.parse(cost.text.trim()))).toStringAsFixed(2)} KES per bag'),
      liveKgPriceSummary(quantityText: qty.text, unitPriceText: cost.text, quantityUnit: quantityUnit),
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

class _SaleSplitPaymentEntry {
  String method;
  final amount = TextEditingController();
  final reference = TextEditingController();
  _SaleSplitPaymentEntry({this.method = 'cash'});
  void dispose() { amount.dispose(); reference.dispose(); }
}

class SalePage extends StatefulWidget {
  const SalePage({super.key});
  @override State<SalePage> createState() => _SalePageState();
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
  String paymentMode = 'cash';
  String? productId;
  String? selectedVariantId;
  String? branchId;
  double? officialPricePerKg;
  List<Map<String, dynamic>> variants = [];
  final List<_SaleSplitPaymentEntry> splitPayments = [
    _SaleSplitPaymentEntry(method: 'cash'),
    _SaleSplitPaymentEntry(method: 'mpesa'),
  ];
  bool busy = false;
  bool loadingVariants = false;
  bool loadingOfficialPrice = false;
  String message = '';

  @override void initState() {
    super.initState();
    loadProductVariants();
  }

  @override void dispose() {
    qty.dispose(); price.dispose(); address.dispose(); fee.dispose();
    customer.dispose(); customerPhone.dispose(); paid.dispose(); reference.dispose();
    for (final entry in splitPayments) { entry.dispose(); }
    super.dispose();
  }

  void updateDisplayedOfficialPrice() {
    final value = officialPricePerKg;
    if (value == null || value <= 0) { price.clear(); return; }
    final displayed = quantityUnit == 'KG' ? value : value * kgPerBag;
    price.text = displayed.toStringAsFixed(2);
  }

  Future<void> loadDirectorSellingPrice() async {
    final variantId = selectedVariantId;
    if (variantId == null) return;
    if (mounted) setState(() { loadingOfficialPrice = true; officialPricePerKg = null; price.clear(); });
    try {
      final db = Supabase.instance.client;
      final branch = await db.from('branches').select('id').eq('code', 'NTULELE').single();
      branchId = branch['id'] as String;
      final row = await db.rpc('staff_get_branch_sale_price', params: {
        'p_branch_id': branchId,
        'p_product_variant_id': variantId,
      });
      final value = (row as num?)?.toDouble();
      if (!mounted) return;
      setState(() {
        officialPricePerKg = value;
        updateDisplayedOfficialPrice();
        message = value == null || value <= 0
          ? 'The Director has not set a selling price for this product at Ntulele. Sale entry is blocked until the price is approved.'
          : '';
      });
    } catch (e) {
      if (mounted) setState(() { officialPricePerKg = null; price.clear(); message = 'Could not load the Director-approved price: ' + friendlyError(e); });
    } finally {
      if (mounted) setState(() { loadingOfficialPrice = false; });
    }
  }

  Future<void> loadProductVariants() async {
    setState(() {
      loadingVariants = true;
      variants = [];
      selectedVariantId = null;
      productId = null;
      officialPricePerKg = null;
      price.clear();
      message = '';
    });
    try {
      final db = Supabase.instance.client;
      final category = await db.from('product_categories').select('id').eq('code', product.toLowerCase()).single();
      final products = await db.from('products').select('id,name').eq('category_id', category['id']).eq('is_active', true);
      final productRows = List<Map<String, dynamic>>.from(products);
      if (productRows.isEmpty) throw Exception('No active product is configured for ' + product + '.');
      final row = productRows.firstWhere((item) => item['name'] == product, orElse: () => productRows.first);
      final loaded = await db.from('product_variants').select('id,variant_name,base_unit,sku')
        .eq('product_id', row['id']).eq('is_active', true).order('variant_name');
      final loadedRows = List<Map<String, dynamic>>.from(loaded);
      if (!mounted) return;
      setState(() {
        productId = row['id'] as String;
        variants = loadedRows;
        selectedVariantId = loadedRows.isNotEmpty ? loadedRows.first['id'] as String : null;
        if (loadedRows.isEmpty) message = 'No active stock option is configured for ' + product + '.';
      });
      if (loadedRows.isNotEmpty) await loadDirectorSellingPrice();
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
        content: TextField(controller: controller, autofocus: true, textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: product == 'Beans' ? 'Variety name' : 'Fertilizer type')),
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
      final inserted = await Supabase.instance.client.from('product_variants').insert({
        'product_id': productId,
        'variant_name': cleanName,
        'grade_or_formulation': product == 'Fertilizer' ? cleanName : null,
        'base_unit': 'bag',
        'is_active': true,
      }).select('id,variant_name,base_unit,sku').single();
      if (!mounted) return;
      setState(() {
        variants.add(Map<String, dynamic>.from(inserted));
        variants.sort((a, b) => (a['variant_name'] as String).compareTo(b['variant_name'] as String));
        selectedVariantId = inserted['id'] as String;
        message = 'Added ' + cleanName + '.';
      });
      await loadDirectorSellingPrice();
    } catch (e) {
      if (mounted) setState(() => message = 'Could not add this option. Only an authorised director can add product varieties/types. ' + friendlyError(e));
    }
  }

  void addSplitPayment() => setState(() => splitPayments.add(_SaleSplitPaymentEntry(method: 'other')));
  void removeSplitPayment(int index) {
    if (splitPayments.length <= 2) return;
    final removed = splitPayments.removeAt(index);
    removed.dispose();
    setState(() {});
  }

  Future<void> save() async {
    final enteredQuantity = double.tryParse(qty.text.trim());
    final enteredPrice = double.tryParse(price.text.trim());
    final selectedRows = variants.where((v) => v['id'] == selectedVariantId).toList();
    final selected = selectedRows.isNotEmpty ? selectedRows.first : <String, dynamic>{};
    final stockUnit = (selected['base_unit'] ?? 'bag').toString().toLowerCase();
    double? q;
    double? p;
    if (enteredQuantity != null && enteredPrice != null) {
      if (stockUnit == 'bag') {
        q = quantityUnit == 'KG' ? enteredQuantity / kgPerBag : enteredQuantity;
        p = quantityUnit == 'KG' ? enteredPrice * kgPerBag : enteredPrice;
      } else if (stockUnit == 'kg') {
        q = quantityUnit == 'BAGS' ? enteredQuantity * kgPerBag : enteredQuantity;
        p = quantityUnit == 'BAGS' ? enteredPrice / kgPerBag : enteredPrice;
      }
    }
    final deliveryFee = double.tryParse(fee.text) ?? 0;
    if (q == null || p == null || q <= 0 || p <= 0 || selectedVariantId == null ||
        officialPricePerKg == null || officialPricePerKg! <= 0 ||
        customer.text.trim().isEmpty ||
        (mode == 'delivery' && address.text.trim().isEmpty)) {
      setState(() => message = 'Choose a product with a Director-approved price, then check the customer, quantity and delivery details.');
      return;
    }
    final saleTotal = q * p + deliveryFee;
    Map<String, dynamic>? payment;
    List<Map<String, dynamic>>? payments;
    if (paymentMode == 'split') {
      final rows = <Map<String, dynamic>>[];
      final methods = <String>{};
      var splitTotal = 0.0;
      for (final entry in splitPayments) {
        final amount = double.tryParse(entry.amount.text.trim());
        if (amount == null || amount <= 0) {
          setState(() => message = 'Enter a positive amount for every split payment row.');
          return;
        }
        final ref = entry.reference.text.trim();
        if ((entry.method == 'mpesa' || entry.method == 'bank_transfer') && ref.isEmpty) {
          setState(() => message = 'Add a reference for every M-Pesa or bank transfer split payment.');
          return;
        }
        methods.add(entry.method);
        splitTotal += amount;
        rows.add({'amount': amount, 'method': entry.method, 'reference': ref});
      }
      if (rows.length < 2 || methods.length < 2) {
        setState(() => message = 'Split payment must contain at least two different payment methods.');
        return;
      }
      if (splitTotal > saleTotal) {
        setState(() => message = 'Split payments cannot exceed the sale total of KES ' + saleTotal.toStringAsFixed(2) + '.');
        return;
      }
      payments = rows;
    } else if (paymentMode != 'credit') {
      final amount = double.tryParse(paid.text.trim()) ?? 0;
      if (amount <= 0 || amount > saleTotal) {
        setState(() => message = 'Enter a payment amount greater than zero and not exceeding KES ' + saleTotal.toStringAsFixed(2) + '.');
        return;
      }
      final ref = reference.text.trim();
      if ((paymentMode == 'mpesa' || paymentMode == 'bank_transfer') && ref.isEmpty) {
        setState(() => message = 'Enter the M-Pesa or bank transfer reference.');
        return;
      }
      payment = {'amount': amount, 'method': paymentMode, 'reference': ref};
    }

    setState(() { busy = true; message = ''; });
    try {
      final db = Supabase.instance.client;
      final branch = branchId == null
        ? await db.from('branches').select('id').eq('code', 'NTULELE').single()
        : {'id': branchId};
      String? customerId;
      final matches = await db.from('customers').select('id').ilike('full_name', customer.text.trim()).limit(1);
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
        'payment_mode': paymentMode,
        'items': [{'product_variant_id': selectedVariantId, 'quantity': q, 'unit_price': p}],
      };
      if (payment != null) payload['payment'] = payment;
      if (payments != null) payload['payments'] = payments;
      final result = await db.rpc('record_sale', params: {'p_payload': payload});
      if (!mounted) return;
      setState(() => message = 'Sale saved. Reference: ' + result['sale_id'].toString() +
        '. Payment: ' + paymentMode.replaceAll('_', ' ') +
        '. Verified balance due: KES ' + (result['balance'] ?? 0).toString());
      qty.clear();
      paid.clear();
      reference.clear();
      for (final entry in splitPayments) { entry.dispose(); }
      splitPayments
        ..clear()
        ..add(_SaleSplitPaymentEntry(method: 'cash'))
        ..add(_SaleSplitPaymentEntry(method: 'mpesa'));
    } catch (e) {
      if (mounted) setState(() => message = 'Could not save sale: ' + friendlyError(e));
    }
    if (mounted) setState(() => busy = false);
  }

  @override Widget build(BuildContext context) {
    final splitTotal = splitPayments.fold<double>(0, (sum, entry) => sum + (double.tryParse(entry.amount.text.trim()) ?? 0));
    return FormPage(
      title: 'Record sale / customer order',
      children: [
        DropdownButtonFormField<String>(
          value: product,
          items: const ['Maize', 'Beans', 'Fertilizer'].map((x) => DropdownMenuItem(value: x,
            child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(productIconFor(x), size: 20, color: brandGreen), const SizedBox(width: 10), Text(x)]))).toList(),
          onChanged: (v) { if (v == null) return; setState(() => product = v); loadProductVariants(); },
          decoration: const InputDecoration(labelText: 'Product'),
        ),
        if (loadingVariants) const LinearProgressIndicator(),
        DropdownButtonFormField<String>(
          value: variants.any((v) => v['id'] == selectedVariantId) ? selectedVariantId : null,
          items: variants.map((v) => DropdownMenuItem<String>(value: v['id'] as String,
            child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(productIconFor(product), size: 20, color: brandGreen), const SizedBox(width: 10), Flexible(child: Text('${v['sku'] ?? 'NO-ID'} • ${v['variant_name']}'))]))).toList(),
          onChanged: (v) { setState(() => selectedVariantId = v); loadDirectorSellingPrice(); },
          decoration: InputDecoration(labelText: product == 'Maize' ? 'Maize product ID' : (product == 'Beans' ? 'Bean variety and ID' : 'Fertilizer type and ID')),
        ),
        if (product != 'Maize')
          TextButton.icon(onPressed: loadingVariants ? null : addVariant, icon: const Icon(Icons.add),
            label: Text(product == 'Beans' ? 'Add bean variety' : 'Add fertilizer type')),
        DropdownButtonFormField<String>(
          value: quantityUnit,
          items: const [
            DropdownMenuItem(value: 'BAGS', child: Text('Bags (1 bag = 90 KG)')),
            DropdownMenuItem(value: 'KG', child: Text('Kilograms (KG)')),
          ],
          onChanged: (v) => setState(() { quantityUnit = v ?? 'BAGS'; updateDisplayedOfficialPrice(); }),
          decoration: const InputDecoration(labelText: 'Quantity and price unit'),
        ),
        field(qty, 'Quantity (${quantityUnit == 'KG' ? 'KG' : 'bags'})', number: true, onChanged: () => setState(() {})),
        TextField(
          controller: price,
          readOnly: true,
          decoration: InputDecoration(
            labelText: 'Director-approved selling price per ${quantityUnit == 'KG' ? 'KG' : 'bag'} (KES)',
            border: const OutlineInputBorder(),
            suffixIcon: loadingOfficialPrice ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : const Icon(Icons.lock_outline),
          ),
        ),
        if (officialPricePerKg == null && !loadingOfficialPrice)
          const Text('A Director must approve the selling price before this sale can be recorded.', style: TextStyle(color: Colors.red, fontSize: 12)),
        if (qty.text.trim().isNotEmpty && price.text.trim().isNotEmpty)
          Text('Director price • Stored unit price: KES ' + (double.tryParse(price.text.trim()) ?? 0).toStringAsFixed(2)),
        liveKgPriceSummary(quantityText: qty.text, unitPriceText: price.text, quantityUnit: quantityUnit),
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
        const Text('Payment option', style: TextStyle(fontWeight: FontWeight.bold)),
        DropdownButtonFormField<String>(
          value: paymentMode,
          items: const [
            DropdownMenuItem(value: 'cash', child: Text('Cash')),
            DropdownMenuItem(value: 'mpesa', child: Text('M-Pesa')),
            DropdownMenuItem(value: 'bank_transfer', child: Text('Bank transfer')),
            DropdownMenuItem(value: 'credit', child: Text('Credit • Pay later')),
            DropdownMenuItem(value: 'split', child: Text('Split payment • Two or more methods')),
            DropdownMenuItem(value: 'other', child: Text('Other / manual payment')),
          ],
          onChanged: (v) => setState(() => paymentMode = v ?? 'cash'),
          decoration: const InputDecoration(labelText: 'Choose how the customer is paying'),
        ),
        if (paymentMode == 'credit')
          const Card(child: Padding(padding: EdgeInsets.all(12), child: Text('Credit sale: no payment is collected now. The full amount remains outstanding in the customer account.'))),
        if (paymentMode == 'split') ...[
          const Text('Enter at least two different payment methods. Cash is verified immediately; M-Pesa, bank and other/manual entries remain pending verification.'),
          ...splitPayments.asMap().entries.map((entry) {
            final index = entry.key;
            final row = entry.value;
            return Card(child: Padding(padding: const EdgeInsets.all(10), child: Column(children: [
              Row(children: [
                Expanded(child: DropdownButtonFormField<String>(
                  value: row.method,
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('Cash')),
                    DropdownMenuItem(value: 'mpesa', child: Text('M-Pesa')),
                    DropdownMenuItem(value: 'bank_transfer', child: Text('Bank transfer')),
                    DropdownMenuItem(value: 'other', child: Text('Other / manual')),
                  ],
                  onChanged: (v) => setState(() => row.method = v ?? 'cash'),
                  decoration: InputDecoration(labelText: 'Payment method ${index + 1}'),
                )),
                IconButton(onPressed: splitPayments.length <= 2 ? null : () => removeSplitPayment(index),
                  icon: const Icon(Icons.delete_outline, color: Colors.red), tooltip: 'Remove payment method'),
              ]),
              TextField(controller: row.amount, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Amount (KES)', border: OutlineInputBorder())),
              if (row.method != 'cash') TextField(controller: row.reference,
                decoration: const InputDecoration(labelText: 'Reference / manual receipt note', border: OutlineInputBorder())),
            ])));
          }),
          Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: addSplitPayment,
            icon: const Icon(Icons.add), label: const Text('Add another payment method'))),
          Text('Split payment total: KES ' + splitTotal.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
        if (paymentMode != 'credit' && paymentMode != 'split') ...[
          field(paid, 'Amount received (KES)', number: true),
          if (paymentMode != 'cash') field(reference, paymentMode == 'other' ? 'Receipt / manual payment note' : 'Payment reference'),
        ],
        actionButton('Save sale', busy || loadingVariants || loadingOfficialPrice, save),
        if (message.isNotEmpty) Text(message),
        const Text('Maize has no variety. Beans and fertilizer use their own saved variety/type options.',
          style: TextStyle(fontSize: 12, color: Colors.black54)),
      ],
    );
  }
}

class DirectorPriceManagementPage extends StatefulWidget {
  const DirectorPriceManagementPage({super.key});
  @override State<DirectorPriceManagementPage> createState() => _DirectorPriceManagementPageState();
}

class _DirectorPriceManagementPageState extends State<DirectorPriceManagementPage> {
  final db = Supabase.instance.client;
  List<Map<String, dynamic>> branches = [];
  List<Map<String, dynamic>> variants = [];
  final Map<String, TextEditingController> customerBuy = {};
  final Map<String, TextEditingController> tajirBuy = {};
  String? branchId;
  String message = '';
  bool loading = true;
  String? savingVariant;

  @override void initState() {
    super.initState();
    load();
  }

  @override void dispose() {
    for (final c in customerBuy.values) { c.dispose(); }
    for (final c in tajirBuy.values) { c.dispose(); }
    super.dispose();
  }

  Future<void> load() async {
    if (mounted) setState(() { loading = true; message = ''; });
    try {
      final results = await Future.wait([
        db.from('branches').select('id,code,name').eq('is_active', true).order('name'),
        db.from('product_variants').select('id,variant_name,base_unit,sku,products(name)').eq('is_active', true).order('variant_name'),
      ]);
      branches = List<Map<String, dynamic>>.from(results[0]);
      variants = List<Map<String, dynamic>>.from(results[1]);
      if (branchId == null || !branches.any((b) => b['id'].toString() == branchId)) {
        branchId = branches.isEmpty ? null : branches.first['id'].toString();
      }
      await loadBranchPrices();
    } catch (e) {
      if (mounted) setState(() { message = 'Could not load catalogue prices: ' + friendlyError(e); loading = false; });
    }
  }

  Future<void> loadBranchPrices() async {
    if (branchId == null) {
      if (mounted) setState(() { loading = false; });
      return;
    }
    try {
      final rows = await db.from('branch_product_selling_prices')
        .select('product_variant_id,selling_price_per_kg,buying_price_per_kg')
        .eq('branch_id', branchId!);
      final prices = <String, Map<String, dynamic>>{
        for (final row in List<Map<String, dynamic>>.from(rows))
          row['product_variant_id'].toString(): row,
      };
      for (final c in customerBuy.values) { c.dispose(); }
      for (final c in tajirBuy.values) { c.dispose(); }
      customerBuy.clear();
      tajirBuy.clear();
      for (final variant in variants) {
        final id = variant['id'].toString();
        final row = prices[id] ?? const <String, dynamic>{};
        customerBuy[id] = TextEditingController(text: row['selling_price_per_kg']?.toString() ?? '');
        tajirBuy[id] = TextEditingController(text: row['buying_price_per_kg']?.toString() ?? '');
      }
      if (mounted) setState(() { loading = false; message = ''; });
    } catch (e) {
      if (mounted) setState(() { loading = false; message = 'Could not load prices for this branch: ' + friendlyError(e); });
    }
  }

  Future<void> savePrice(Map<String, dynamic> variant) async {
    final id = variant['id'].toString();
    final customerPrice = double.tryParse(customerBuy[id]?.text.trim() ?? '');
    final tajirPriceText = tajirBuy[id]?.text.trim() ?? '';
    final tajirPrice = tajirPriceText.isEmpty ? null : double.tryParse(tajirPriceText);
    if (branchId == null || customerPrice == null || customerPrice <= 0 ||
        (tajirPriceText.isNotEmpty && (tajirPrice == null || tajirPrice <= 0))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a positive TAJIR selling price per KG. The TAJIR buying price may be left blank until needed.')));
      return;
    }
    setState(() { savingVariant = id; message = ''; });
    try {
      await db.from('branch_product_selling_prices').upsert({
        'branch_id': branchId,
        'product_variant_id': id,
        'selling_price_per_kg': customerPrice,
        'buying_price_per_kg': tajirPrice,
        'updated_by': db.auth.currentUser!.id,
      }, onConflict: 'branch_id,product_variant_id');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Official branch prices saved. Customer BUY and TAJIR BUY prices remain separate.')));
        setState(() { savingVariant = null; });
      }
    } catch (e) {
      if (mounted) {
        setState(() { savingVariant = null; message = 'Price save failed: ' + friendlyError(e); });
      }
    }
  }

  @override Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: load,
    child: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Director catalogue prices', style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
      const SizedBox(height: 5),
      const Text('Only an authorised Director can change these official prices. All prices are stored per KG; 1 bag = 90 KG.'),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        value: branchId,
        decoration: const InputDecoration(labelText: 'Branch', border: OutlineInputBorder()),
        items: branches.map((b) => DropdownMenuItem<String>(value: b['id'].toString(), child: Text('${b['name']} (${b['code']})'))).toList(),
        onChanged: loading ? null : (v) async {
          setState(() { branchId = v; loading = true; });
          await loadBranchPrices();
        },
      ),
      const SizedBox(height: 12),
      const Card(child: Padding(padding: EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Customer BUY price', style: TextStyle(fontWeight: FontWeight.bold)),
        Text('TAJIR sells to the customer. This is the official price shown in the customer catalogue.'),
        SizedBox(height: 8),
        Text('TAJIR BUY price', style: TextStyle(fontWeight: FontWeight.bold)),
        Text('TAJIR buys produce from the customer. This is a separate price and is never substituted for the customer BUY price.'),
      ]))),
      if (loading) const LinearProgressIndicator(),
      if (message.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(message, style: const TextStyle(color: Colors.red))),
      if (!loading && branches.isEmpty) const Text('No active branches are configured.'),
      if (!loading && variants.isEmpty) const Text('No active product variants are configured.'),
      ...variants.map((variant) {
        final id = variant['id'].toString();
        final product = (variant['products'] as Map?)?.cast<String, dynamic>() ?? {};
        final name = (product['name'] ?? 'Product').toString() + ' • ' + (variant['variant_name'] ?? 'Standard').toString();
        final customer = double.tryParse(customerBuy[id]?.text.trim() ?? '');
        final supplier = double.tryParse(tajirBuy[id]?.text.trim() ?? '');
        return Card(margin: const EdgeInsets.symmetric(vertical: 7), child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(productIconFor(name), color: brandGreen),
              const SizedBox(width: 8),
              Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold))),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: customerBuy[id],
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Customer BUY price • KES per KG', border: OutlineInputBorder()),
            ),
            if (customer != null && customer > 0) Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Customer pays KES ${(customer * kgPerBag).toStringAsFixed(2)} per 90 KG bag'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: tajirBuy[id],
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'TAJIR BUY price • KES per KG (optional)', border: OutlineInputBorder()),
            ),
            if (supplier != null && supplier > 0) Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('TAJIR pays KES ${(supplier * kgPerBag).toStringAsFixed(2)} per 90 KG bag'),
            ),
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerRight, child: FilledButton.icon(
              onPressed: savingVariant == id || loading ? null : () => savePrice(variant),
              icon: Icon(savingVariant == id ? Icons.hourglass_top : Icons.save),
              label: Text(savingVariant == id ? 'Saving…' : 'Save official prices'),
            )),
          ]),
        ));
      }),
    ]),
  );
}

class DirectorCustomProductRequestsPage extends StatefulWidget {
  const DirectorCustomProductRequestsPage({super.key});
  @override State<DirectorCustomProductRequestsPage> createState() => _DirectorCustomProductRequestsPageState();
}

class _DirectorCustomProductRequestsPageState extends State<DirectorCustomProductRequestsPage> {
  final db = Supabase.instance.client;
  List<Map<String, dynamic>> rows = [];
  bool loading = true;
  String? busyId;
  String message = '';

  @override void initState() { super.initState(); load(); }

  Future<void> load() async {
    if (mounted) setState(() { loading = true; message = ''; });
    try {
      final result = await db.from('customer_custom_product_requests')
        .select('id,product_name,description,quantity,quantity_unit,proposed_unit_price_kes,agreed_unit_price_kes,request_direction,status,director_response,customer_confirmed_at,created_at,customers(full_name,phone)')
        .order('created_at', ascending: false);
      if (mounted) setState(() {
        rows = List<Map<String, dynamic>>.from(result);
        loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { loading = false; message = 'Could not load customer requests: ' + friendlyError(e); });
    }
  }

  Future<void> review(Map<String, dynamic> row) async {
    final price = TextEditingController(text: row['agreed_unit_price_kes']?.toString() ?? '');
    final response = TextEditingController(text: (row['director_response'] ?? '').toString());
    String status = (row['status'] == 'pending' ? 'under_review' : row['status']).toString();
    final result = await showDialog<bool>(context: context, builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('Review customer-submitted request'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text((row['product_name'] ?? 'Product').toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('Proposed by customer: KES ${row['proposed_unit_price_kes']} per ${row['quantity_unit']}'),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: status,
            decoration: const InputDecoration(labelText: 'Decision'),
            items: const [
              DropdownMenuItem(value: 'under_review', child: Text('Under review')),
              DropdownMenuItem(value: 'approved', child: Text('Approve')),
              DropdownMenuItem(value: 'negotiation', child: Text('Negotiate')),
              DropdownMenuItem(value: 'rejected', child: Text('Reject')),
            ],
            onChanged: (v) => setDialogState(() => status = v ?? 'under_review'),
          ),
          TextField(
            controller: price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: row['request_direction'] == 'SELL_TO_TAJIR' ? 'Agreed TAJIR buying price (KES)' : 'Agreed official price (KES) per ${row['quantity_unit']}'),
          ),
          TextField(controller: response, maxLines: 3, decoration: const InputDecoration(labelText: 'Director response / conditions')),
          const SizedBox(height: 6),
          const Text('For BUY_FROM_TAJIR, this is TAJIR’s selling price. For SELL_TO_TAJIR, this is the price TAJIR agrees to pay the customer.', style: TextStyle(fontSize: 12, color: Colors.black54)),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save decision')),
        ],
      ),
    ));
    if (result == true) {
      final agreed = double.tryParse(price.text.trim());
      if ((status == 'approved' || status == 'negotiation') && (agreed == null || agreed <= 0)) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a positive agreed price before approving or negotiating.')));
      } else {
        setState(() { busyId = row['id'].toString(); });
        try {
          await db.from('customer_custom_product_requests').update({
            'status': status,
            'agreed_unit_price_kes': (status == 'approved' || status == 'negotiation') ? agreed : null,
            'director_response': response.text.trim().isEmpty ? null : response.text.trim(),
          }).eq('id', row['id']);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Director decision saved and recorded.')));
          await load();
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
        } finally {
          if (mounted) setState(() { busyId = null; });
        }
      }
    }
    price.dispose();
    response.dispose();
  }

  @override Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: load,
    child: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Customer custom product requests', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      const Text('These are customer-submitted requests/offers, not official TAJIR catalogue prices. Review the proposed price and enter the agreed TAJIR price separately.'),
      if (loading) const LinearProgressIndicator(),
      if (message.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(message, style: const TextStyle(color: Colors.red))),
      if (!loading && rows.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 18), child: Text('No customer custom requests have been submitted.')),
      ...rows.map((row) {
        final customer = (row['customers'] as Map?)?.cast<String, dynamic>() ?? {};
        final direction = (row['request_direction'] ?? 'BUY_FROM_TAJIR').toString();
        final status = (row['status'] ?? 'pending').toString();
        final confirmed = row['customer_confirmed_at'] != null;
        final canReview = !confirmed && status != 'rejected' && status != 'approved';
        final title = direction == 'SELL_TO_TAJIR' ? 'Customer offers to sell to TAJIR' : 'Customer requests to buy from TAJIR';
        return Card(margin: const EdgeInsets.symmetric(vertical: 7), child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.assignment_outlined, color: Colors.deepOrange),
              const SizedBox(width: 8),
              Expanded(child: Text((row['product_name'] ?? 'Product').toString(), style: const TextStyle(fontWeight: FontWeight.bold))),
              Chip(label: Text(status.replaceAll('_', ' '))),
            ]),
            Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            Text('Customer: ${customer['full_name'] ?? 'Customer'} • ${customer['phone'] ?? 'No phone'}'),
            Text('Quantity: ${row['quantity']} ${row['quantity_unit']} • Proposed: KES ${row['proposed_unit_price_kes']} / ${row['quantity_unit']}'),
            if (row['agreed_unit_price_kes'] != null) Text('Agreed official price: KES ${row['agreed_unit_price_kes']} / ${row['quantity_unit']}', style: const TextStyle(fontWeight: FontWeight.bold)),
            if ((row['description'] ?? '').toString().isNotEmpty) Text('Details: ${row['description']}'),
            if ((row['director_response'] ?? '').toString().isNotEmpty) Text('Director response: ${row['director_response']}'),
            if (confirmed) const Text('Customer confirmed the approved offer.', style: TextStyle(color: brandGreen, fontWeight: FontWeight.bold)),
            if (canReview) Align(alignment: Alignment.centerRight, child: FilledButton.icon(
              onPressed: busyId == row['id'].toString() ? null : () => review(row),
              icon: Icon(busyId == row['id'].toString() ? Icons.hourglass_top : Icons.rate_review_outlined),
              label: const Text('Review request'),
            )),
          ]),
        ));
      }),
    ]),
  );
}

class DirectorMarketplacePricesPage extends StatefulWidget {
  const DirectorMarketplacePricesPage({super.key});
  @override State<DirectorMarketplacePricesPage> createState() => _DirectorMarketplacePricesPageState();
}

class _DirectorMarketplacePricesPageState extends State<DirectorMarketplacePricesPage> {
  final db = Supabase.instance.client;
  List<Map<String, dynamic>> listings = [];
  final Map<String, TextEditingController> buying = {};
  final Map<String, TextEditingController> selling = {};
  bool loading = true;
  String? savingId;
  String message = '';

  @override void initState() { super.initState(); load(); }

  @override void dispose() {
    for (final c in buying.values) { c.dispose(); }
    for (final c in selling.values) { c.dispose(); }
    super.dispose();
  }

  Future<void> load() async {
    if (mounted) setState(() { loading = true; message = ''; });
    try {
      final result = await db.from('marketplace_listings')
        .select('id,product_name,quantity,unit,price_per_unit,total_value_kes,location,marketplace_listing_buying_prices(buying_price_kes),marketplace_listing_selling_prices(selling_price_kes),customers(full_name),branches(name)')
        .eq('status', 'active')
        .order('created_at', ascending: false);
      listings = List<Map<String, dynamic>>.from(result);
      for (final c in buying.values) { c.dispose(); }
      for (final c in selling.values) { c.dispose(); }
      buying.clear();
      selling.clear();
      for (final row in listings) {
        final id = row['id'].toString();
        final buyRow = (row['marketplace_listing_buying_prices'] as Map?)?.cast<String, dynamic>() ?? {};
        final sellRow = (row['marketplace_listing_selling_prices'] as Map?)?.cast<String, dynamic>() ?? {};
        buying[id] = TextEditingController(text: (buyRow['buying_price_kes'] ?? row['price_per_unit'] ?? '').toString());
        selling[id] = TextEditingController(text: (sellRow['selling_price_kes'] ?? '').toString());
      }
      if (mounted) setState(() { loading = false; });
    } catch (e) {
      if (mounted) setState(() { loading = false; message = 'Could not load marketplace prices: ' + friendlyError(e); });
    }
  }

  Future<void> save(Map<String, dynamic> listing) async {
    final id = listing['id'].toString();
    final buy = double.tryParse(buying[id]?.text.trim() ?? '');
    final sell = double.tryParse(selling[id]?.text.trim() ?? '');
    if (buy == null || buy <= 0 || sell == null || sell <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter both positive Director-approved prices before publishing this listing to buyers.')));
      return;
    }
    setState(() { savingId = id; message = ''; });
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      await db.from('marketplace_listing_buying_prices').upsert({
        'listing_id': id,
        'buying_price_kes': buy,
        'updated_by': db.auth.currentUser!.id,
        'updated_at': now,
      }, onConflict: 'listing_id');
      await db.from('marketplace_listing_selling_prices').upsert({
        'listing_id': id,
        'selling_price_kes': sell,
        'updated_by': db.auth.currentUser!.id,
        'updated_at': now,
      }, onConflict: 'listing_id');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marketplace BUY and SELL prices saved separately.')));
        setState(() { savingId = null; });
      }
    } catch (e) {
      if (mounted) setState(() { savingId = null; message = 'Could not save marketplace prices: ' + friendlyError(e); });
    }
  }

  @override Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: load,
    child: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Marketplace listing prices', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      const Text('Set two separate prices for each farmer offer. TAJIR BUY is what the seller receives; TAJIR SELL is what the customer pays. Both are per listing unit.'),
      if (loading) const LinearProgressIndicator(),
      if (message.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(message, style: const TextStyle(color: Colors.red))),
      if (!loading && listings.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 18), child: Text('No active farmer offers are waiting for Director pricing.')),
      ...listings.map((row) {
        final id = row['id'].toString();
        final seller = (row['customers'] as Map?)?.cast<String, dynamic>() ?? {};
        final branch = (row['branches'] as Map?)?.cast<String, dynamic>() ?? {};
        final unit = (row['unit'] ?? 'BAG').toString();
        final buy = double.tryParse(buying[id]?.text.trim() ?? '');
        final sell = double.tryParse(selling[id]?.text.trim() ?? '');
        final quantity = (row['quantity'] as num?)?.toDouble() ?? 0;
        return Card(margin: const EdgeInsets.symmetric(vertical: 7), child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((row['product_name'] ?? 'Produce').toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Seller: ${seller['full_name'] ?? 'Customer'} • Branch: ${branch['name'] ?? 'TAJIR branch'}'),
            Text('Available: ${row['quantity']} ${unit} • ${row['location']}'),
            const SizedBox(height: 10),
            TextField(controller: buying[id], keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: 'TAJIR BUY price • KES per ${unit}', border: const OutlineInputBorder())),
            if (buy != null && buy > 0) Text('Seller receives KES ${(buy * quantity).toStringAsFixed(2)} for all available quantity'),
            const SizedBox(height: 10),
            TextField(controller: selling[id], keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: 'TAJIR SELL price • KES per ${unit}', border: const OutlineInputBorder())),
            if (sell != null && sell > 0) Text('Customer pays KES ${(sell * quantity).toStringAsFixed(2)} for all available quantity'),
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerRight, child: FilledButton.icon(
              onPressed: savingId == id || loading ? null : () => save(row),
              icon: Icon(savingId == id ? Icons.hourglass_top : Icons.save),
              label: Text(savingId == id ? 'Saving…' : 'Save both prices'),
            )),
          ]),
        ));
      }),
    ]),
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

  Future<void> recordCustomerPayment(
    Map<String,dynamic> customer,
    List<Map<String,dynamic>> sales,
    List<Map<String,dynamic>> payments,
  ) async {
    final paidBySale = <String,double>{};
    for (final payment in payments) {
      final saleId = payment['sale_id']?.toString();
      if (saleId == null || !['pending','verified'].contains(payment['status'])) continue;
      paidBySale[saleId] = (paidBySale[saleId] ?? 0) + ((payment['amount'] as num?)?.toDouble() ?? 0);
    }
    double dueFor(Map<String,dynamic> sale) {
      final total = (sale['total_amount'] as num?)?.toDouble() ?? 0;
      return (total - (paidBySale[sale['id'].toString()] ?? 0)).clamp(0, double.infinity).toDouble();
    }
    final openSales = sales.where((sale) => dueFor(sale) > 0.009).toList();
    if (openSales.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('This customer has no unallocated sale balance to pay.')));
      return;
    }

    String selectedSaleId = openSales.first['id'].toString();
    String method = 'cash';
    final amountController = TextEditingController();
    final referenceController = TextEditingController();
    final accepted = await showDialog<bool>(context:context,builder:(dialogContext)=>StatefulBuilder(builder:(dialogContext,setDialogState)=>AlertDialog(
      title:Text('Record customer payment'),
      content:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(customer['full_name']?.toString() ?? 'Customer',style:const TextStyle(fontWeight:FontWeight.bold)),
        const SizedBox(height:8),
        DropdownButtonFormField<String>(
          value:selectedSaleId,
          isExpanded:true,
          items:openSales.map((sale)=>DropdownMenuItem<String>(
            value:sale['id'].toString(),
            child:Text((sale['sale_number']??'Sale').toString()+' • Due KES '+dueFor(sale).toStringAsFixed(2),overflow:TextOverflow.ellipsis),
          )).toList(),
          onChanged:(value)=>setDialogState(()=>selectedSaleId=value??selectedSaleId),
          decoration:const InputDecoration(labelText:'Sale / outstanding balance'),
        ),
        TextField(controller:amountController,keyboardType:const TextInputType.numberWithOptions(decimal:true),
          decoration:const InputDecoration(labelText:'Payment amount (KES)')),
        DropdownButtonFormField<String>(
          value:method,
          items:const [
            DropdownMenuItem(value:'cash',child:Text('Cash')),
            DropdownMenuItem(value:'mpesa',child:Text('M-Pesa')),
            DropdownMenuItem(value:'bank_transfer',child:Text('Bank transfer')),
            DropdownMenuItem(value:'other',child:Text('Other / manual payment')),
          ],
          onChanged:(value)=>setDialogState(()=>method=value??'cash'),
          decoration:const InputDecoration(labelText:'Payment method'),
        ),
        if(method!='cash') TextField(controller:referenceController,
          decoration:InputDecoration(labelText:method=='other'?'Receipt / manual note':'Payment reference')),
        const SizedBox(height:6),
        const Text('M-Pesa and bank transfers remain pending until verified. Cash is recorded as received.',style:TextStyle(fontSize:12,color:Colors.black54)),
      ]),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('Cancel')),
        FilledButton(onPressed:()=>Navigator.pop(dialogContext,true),child:const Text('Record payment')),
      ],
    )));
    if(accepted==true){
      try{
        final amount=double.tryParse(amountController.text.trim());
        if(amount==null||amount<=0)throw const FormatException('Enter a payment amount greater than zero.');
        final selected=openSales.firstWhere((sale)=>sale['id'].toString()==selectedSaleId);
        if(amount>dueFor(selected)+0.009)throw const FormatException('Payment exceeds the remaining sale balance.');
        final result=await Supabase.instance.client.rpc('record_customer_sale_payment',params:{
          'p_sale_id':selectedSaleId,
          'p_amount':amount,
          'p_method':method,
          'p_reference':referenceController.text.trim(),
        });
        if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(
          'Payment recorded: '+result['payment_number'].toString()+
          '. Remaining unallocated balance: KES '+(result['unallocated_balance']??0).toString(),
        )));
        if(mounted)await showCustomer(customer);
      }catch(e){
        if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Could not record payment: '+friendlyError(e))));
      }
    }
    amountController.dispose();
    referenceController.dispose();
  }

  Future<void> showCustomer(Map<String,dynamic> customer) async {
    final db=Supabase.instance.client;
    try {
      final id=customer['id'];
      final results=await Future.wait([
        db.from('sales').select('id,sale_number,sale_date,total_amount,payment_mode').eq('customer_id',id).order('sale_date',ascending:false),
        db.from('customer_payments').select('id,payment_number,sale_id,amount,method,status,received_at,created_at').eq('customer_id',id).order('created_at',ascending:false),
      ]);
      final sales=List<Map<String,dynamic>>.from(results[0]);
      final payments=List<Map<String,dynamic>>.from(results[1]);
      final totalSales=sales.fold<double>(0,(s,r)=>s+((r['total_amount'] as num?)?.toDouble()??0));
      final verified=payments.where((p)=>p['status']=='verified').fold<double>(0,(s,r)=>s+((r['amount'] as num?)?.toDouble()??0));
      final pending=payments.where((p)=>p['status']=='pending').fold<double>(0,(s,r)=>s+((r['amount'] as num?)?.toDouble()??0));
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
          Text('Pending verification: KES ${pending.toStringAsFixed(2)}'),
          Text('Outstanding balance: KES ${balance.toStringAsFixed(2)}',style:TextStyle(fontWeight:FontWeight.bold,color:balance>0?Colors.red:brandGreen)),
          const Divider(),
          const Text('Purchase history',style:TextStyle(fontWeight:FontWeight.bold)),
          if(sales.isEmpty)const Text('No sales recorded for this customer.'),
          ...sales.map((s)=>ListTile(contentPadding:EdgeInsets.zero,title:Text('${s['sale_number']}'),subtitle:Text('${s['sale_date']} • Payment: ${s['payment_mode']??'credit'}'),trailing:Text('KES ${((s['total_amount'] as num?)?.toDouble()??0).toStringAsFixed(2)}'))),
          const Divider(),
          const Text('Payments',style:TextStyle(fontWeight:FontWeight.bold)),
          if(payments.isEmpty)const Text('No payments recorded.'),
          ...payments.map((p)=>ListTile(contentPadding:EdgeInsets.zero,title:Text('KES ${((p['amount'] as num?)?.toDouble()??0).toStringAsFixed(2)} • ${p['method']}'),subtitle:Text('${p['status']} • ${p['payment_number']}'))),
        ]))),
        actions:[
          if(balance>0.009) OutlinedButton.icon(onPressed:(){Navigator.pop(context);recordCustomerPayment(customer,sales,payments);},icon:const Icon(Icons.payments_outlined),label:const Text('Record payment')),
          TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Close')),
        ],
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
  double revenue = 0, costOfGoods = 0, purchaseCostsTotal = 0, purchaseTotal = 0, customerReceipts = 0, pendingCustomerReceipts = 0, supplierPayments = 0;
  List<Map<String,dynamic>> salesRows = [], purchaseCostRows = [], purchaseRows = [], customerPaymentRows = [], pendingCustomerPaymentRows = [], supplierPaymentRows = [];
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
      final hasFinanceAccess = roles.any((r) => r['app_roles'] is Map && ['director','accountant'].contains((r['app_roles'] as Map)['code']));
      if (!hasFinanceAccess) throw Exception('This financial report is available to Director and Accountant accounts only.');
      final data = await Future.wait([
        db.from('sales').select('id,sale_number,sale_date,total_amount,payment_mode,sale_items(line_cost)').order('sale_date',ascending:false),
        db.from('purchase_costs').select('id,purchase_id,purchase_item_id,cost_type,amount,description,incurred_at').order('incurred_at',ascending:false),
        db.from('purchases').select('id,purchase_number,purchase_date,status,purchase_items(quantity,quantity_accepted,buying_price_per_unit)').order('purchase_date',ascending:false),
        db.from('customer_payments').select('payment_number,sale_id,amount,status,method,received_at').order('received_at',ascending:false),
        db.from('supplier_payments').select('amount,status,method,payment_date,transaction_reference').order('payment_date',ascending:false),
      ]);
      final sr = List<Map<String,dynamic>>.from(data[0]).where((r)=>within(r['sale_date'])).toList();
      final pcr = List<Map<String,dynamic>>.from(data[1]).where((r)=>within(r['incurred_at'])).toList();
      final pr = List<Map<String,dynamic>>.from(data[2]).where((r)=>within(r['purchase_date']) && r['status']=='accepted').toList();
      final allCustomerRows = List<Map<String,dynamic>>.from(data[3]).where((r)=>within(r['received_at'])).toList();
      final cr = allCustomerRows.where((r)=>r['status']=='verified').toList();
      final pendingCr = allCustomerRows.where((r)=>r['status']=='pending').toList();
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
        salesRows=sr; purchaseCostRows=pcr; purchaseRows=pr; customerPaymentRows=cr; pendingCustomerPaymentRows=pendingCr; supplierPaymentRows=spr;
        revenue=rev; costOfGoods=cogs; purchaseCostsTotal=pcr.fold(0.0,(v,r)=>v+numVal(r['amount']));
        purchaseTotal=buy; customerReceipts=cr.fold(0.0,(v,r)=>v+numVal(r['amount']));
        pendingCustomerReceipts=pendingCr.fold(0.0,(v,r)=>v+numVal(r['amount']));
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
  Widget section(String title,List<Map<String,dynamic>> rows,String dateField,String amountField,String nameField,{String? extraField}) => Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    const Divider(height:24),Text(title,style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
    if(rows.isEmpty) const Padding(padding:EdgeInsets.symmetric(vertical:8),child:Text('No records for this period.')),
    ...rows.take(40).map((r)=>ListTile(dense:true,title:Text((r[nameField]??title).toString()),subtitle:Text((r[dateField]??'').toString()+(extraField==null?'':' • '+(r[extraField]??'').toString())),trailing:Text(cash(numVal(r[amountField]))))),
  ]);
  @override Widget build(BuildContext context) {
    final gross = revenue-costOfGoods;
    final net = gross;
    return RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.all(16),children:[
      const Text('Financial Records & Profit',style:TextStyle(fontSize:23,fontWeight:FontWeight.bold)),
      const Text('Director & Accountant reports • amounts in Kenya shillings'),
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
        metric('Verified customer receipts',customerReceipts),metric('Pending customer payments',pendingCustomerReceipts),metric('Verified supplier payments',supplierPayments),
      ]),
      section('Sales records',salesRows,'sale_date','total_amount','sale_number',extraField:'payment_mode'),
      section('Expenses attached to purchases',purchaseCostRows,'incurred_at','amount','cost_type'),
      section('Accepted purchases',purchaseRows,'purchase_date','id','purchase_number'),
      section('Verified customer payments',customerPaymentRows,'received_at','amount','payment_number'),
      section('Pending customer payments',pendingCustomerPaymentRows,'received_at','amount','payment_number'),
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

Widget liveKgPriceSummary({required String quantityText, required String unitPriceText, required String quantityUnit}) {
  final enteredQuantity = double.tryParse(quantityText.trim());
  final enteredPrice = double.tryParse(unitPriceText.trim());
  if (enteredQuantity == null || enteredPrice == null || enteredQuantity <= 0 || enteredPrice < 0) return const SizedBox.shrink();
  final quantityKg = quantityUnit == 'KG' ? enteredQuantity : enteredQuantity * kgPerBag;
  final pricePerKg = quantityUnit == 'KG' ? enteredPrice : enteredPrice / kgPerBag;
  final total = quantityKg * pricePerKg;
  return Card(color: brandGreen.withOpacity(.07), child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('LIVE KG PRICE CALCULATION', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
    const SizedBox(height: 5),
    Text('${quantityKg.toStringAsFixed(2)} KG  •  ${(quantityKg / kgPerBag).toStringAsFixed(3)} bags'),
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
    final q = enteredQ == null ? null : (entryUnit == 'KG' ? enteredQ / kgPerBag : enteredQ);
    final p = enteredP == null ? null : (entryUnit == 'KG' ? enteredP * kgPerBag : enteredP);
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
          DropdownButtonFormField<String>(
            value: entryUnit,
            decoration: const InputDecoration(labelText: 'Quantity and price unit', border: OutlineInputBorder()),
            items: const [DropdownMenuItem(value: 'BAGS', child: Text('Bags (1 bag = 90 KG)')), DropdownMenuItem(value: 'KG', child: Text('Kilograms (KG)'))],
            onChanged: (v) => setState(() => entryUnit = v ?? 'BAGS'),
          ),
          const SizedBox(height: 12),
          TextField(controller: quantity, keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Quantity (${entryUnit == 'KG' ? 'KG' : 'bags'})', border: const OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: isSale ? 'Selling price per ${entryUnit == 'KG' ? 'KG' : 'bag'} (KES)' : 'Buying price per ${entryUnit == 'KG' ? 'KG' : 'bag'} (KES)',
                  border: const OutlineInputBorder())),
          if (quantity.text.trim().isNotEmpty && price.text.trim().isNotEmpty) Text('Equivalent: ${(double.tryParse(quantity.text.trim()) == null ? 0 : (entryUnit == 'KG' ? double.parse(quantity.text.trim()) / kgPerBag : double.parse(quantity.text.trim()))).toStringAsFixed(3)} bags • ${(double.tryParse(price.text.trim()) == null ? 0 : (entryUnit == 'KG' ? double.parse(price.text.trim()) * kgPerBag : double.parse(price.text.trim()))).toStringAsFixed(2)} KES per bag'),
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
          subtitle: Text('${r['date']}  |  ${r['quantity']} bags (${((double.tryParse(r['quantity'] ?? '0') ?? 0) * kgPerBag).toStringAsFixed(1)} KG)'),
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
          const Text('Net stock (bags / KG)'), Text('${total.toStringAsFixed(2)} bags\n${(total * kgPerBag).toStringAsFixed(1)} KG', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
          trailing: Text('${quantity.toStringAsFixed(2)} bags\n${(quantity * kgPerBag).toStringAsFixed(1)} KG', textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.bold)),
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
          trailing: Text('${e['quantity']} bags\n${((double.tryParse(e['quantity'] ?? '0') ?? 0) * kgPerBag).toStringAsFixed(1)} KG', textAlign: TextAlign.end),
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
