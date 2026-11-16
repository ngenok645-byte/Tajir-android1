from pathlib import Path

source = Path("TAJIR_flutter_app/lib/main.dart")
text = source.read_text(encoding="utf-8")

dashboard = text.index("class _DashboardPageState")
start = text.index("  Future<void> load() async {", dashboard)
end_marker = "\n  }\n  @override Widget build"
end = text.index(end_marker, start) + len("\n  }")

replacement = """  Future<void> load() async {
    try {
      final db = Supabase.instance.client;
      final contextResult = await db.rpc('get_my_tajir_context');
      final contextRows = List<Map<String, dynamic>>.from(contextResult);
      if (contextRows.isEmpty) {
        throw StateError('Your TAJIR profile is not available or your account is not active.');
      }
      final profile = contextRows.first;
      final roleNames = List<String>.from(profile['role_names'] ?? const []);
      final branchName = (profile['branch_name'] ?? 'No branch assigned').toString();
      final stockResult = await db.rpc('get_stock_balances');
      if (!mounted) return;
      setState(() {
        final name = (profile['display_name'] ?? 'TAJIR user').toString();
        final roles = roleNames.isEmpty ? 'No role assigned' : roleNames.join(', ');
        role = '$name • $roles • $branchName';
        stock = List<Map<String, dynamic>>.from(stockResult);
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => error = e.toString());
    }
  }"""

text = text[:start] + replacement + text[end:]
source.write_text(text, encoding="utf-8")
print("Updated dashboard to use the live TAJIR profile/role/branch RPC.")
