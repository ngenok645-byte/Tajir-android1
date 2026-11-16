import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const brandGreen = Color(0xFF176B3A);
const brandGold = Color(0xFFD6A52D);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const anon = String.fromEnvironment('SUPABASE_ANON_KEY');
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

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (Supabase.instance.client.auth.currentSession == null) {
          return const LoginPage();
        }
        return const HomeShell();
      },
    );
  }
}


class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override State<LoginPage> createState() => _LoginPageState();
}
class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController(), password = TextEditingController();
  bool busy = false;
  String? error;
  Future<void> submit() async {
    setState(() { busy = true; error = null; });
    try {
      final auth = Supabase.instance.client.auth;
      await auth.signInWithPassword(email: email.text.trim(), password: password.text);
    } on AuthException catch (e) { setState(() => error = e.message); }
      catch (e) { setState(() => error = 'Could not sign in: $e'); }
    if (mounted) setState(() => busy = false);
  }
  @override Widget build(BuildContext context) => Scaffold(
    body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420),
      child: Card(margin: const EdgeInsets.all(24), child: Padding(padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const BrandMark(), const SizedBox(height: 24),
          const Text('Sign in to TAJIR', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 18),
          TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder())),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: Colors.red))),
          const SizedBox(height: 16),
          FilledButton(onPressed: busy ? null : submit, child: Text(busy ? 'Please wait…' : 'Sign in')),
          const Text('Accounts are created and activated by the TAJIR administrator.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.black54)),
        ]),
      )),
    )),
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
  final pages = const [DashboardPage(), PurchasePage(), SalePage(), StockPage(), CustomersPage(), BranchesPage()];
  final labels = const ['Dashboard','Purchases','Sales','Stock','Customers','Branches'];
  final icons = const [Icons.dashboard, Icons.add_shopping_cart, Icons.point_of_sale, Icons.inventory_2, Icons.people, Icons.store];
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


class BranchesPage extends StatefulWidget {
  const BranchesPage({super.key});
  @override State<BranchesPage> createState() => _BranchesPageState();
}

class _BranchesPageState extends State<BranchesPage> {
  List<Map<String,dynamic>> rows = [];
  bool isDirector = false, busy = false;
  String message = '';

  @override void initState() { super.initState(); load(); }

  Future<void> load() async {
    setState(() { busy = true; message = ''; });
    try {
      final db = Supabase.instance.client;
      final contexts = List<Map<String,dynamic>>.from(await db.rpc('get_my_tajir_context'));
      if (contexts.isEmpty) throw Exception('Your TAJIR profile is not active.');
      final roleCodes = List<String>.from(contexts.first['role_codes'] ?? const []);
      final data = await db.from('branches')
        .select('id,code,name,address,phone,is_active')
        .order('name');
      if (!mounted) return;
      setState(() {
        isDirector = roleCodes.contains('director');
        rows = List<Map<String,dynamic>>.from(data);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => message = 'Could not load branches: $e');
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> editBranch([Map<String,dynamic>? row]) async {
    if (!isDirector) return;
    final code = TextEditingController(text: row?['code']?.toString() ?? '');
    final name = TextEditingController(text: row?['name']?.toString() ?? '');
    final address = TextEditingController(text: row?['address']?.toString() ?? '');
    final phone = TextEditingController(text: row?['phone']?.toString() ?? '');
    String? validation;
    final ok = await showDialog<bool>(context: context, builder: (dialogContext) =>
      StatefulBuilder(builder: (context, refresh) => AlertDialog(
        title: Text(row == null ? 'Add branch' : 'Edit branch'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: code, textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Branch code')),
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Branch name')),
          TextField(controller: address, decoration: const InputDecoration(labelText: 'Location / address')),
          TextField(controller: phone, keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone number')),
          if (validation != null) Text(validation!, style: const TextStyle(color: Colors.red)),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            if (code.text.trim().isEmpty || name.text.trim().isEmpty) {
              refresh(() => validation = 'Branch code and name are required.');
              return;
            }
            Navigator.pop(dialogContext, true);
          }, child: const Text('Save')),
        ],
      )));
    if (ok == true) {
      try {
        final values = <String,dynamic>{
          'code': code.text.trim().toUpperCase(),
          'name': name.text.trim(),
          'address': address.text.trim().isEmpty ? null : address.text.trim(),
          'phone': phone.text.trim().isEmpty ? null : phone.text.trim(),
        };
        final db = Supabase.instance.client;
        if (row == null) {
          await db.from('branches').insert(values);
        } else {
          await db.from('branches').update(values).eq('id', row['id']);
        }
        await load();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Branch could not be saved: $e')));
      }
    }
    code.dispose(); name.dispose(); address.dispose(); phone.dispose();
  }

  Future<void> deactivateBranch(Map<String,dynamic> row) async {
    if (!isDirector || row['is_active'] != true) return;
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Deactivate branch?'),
      content: Text('The branch "${row['name']}" will be hidden from new operations. Existing records will be preserved.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Deactivate')),
      ],
    ));
    if (confirmed == true) {
      try {
        await Supabase.instance.client.from('branches')
          .update({'is_active': false}).eq('id', row['id']);
        await load();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Branch could not be deactivated: $e')));
      }
    }
  }

  @override Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: load,
    child: ListView(padding: const EdgeInsets.all(18), children: [
      Row(children: [
        const Expanded(child: Text('Branches', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold))),
        if (isDirector) FilledButton.icon(onPressed: () => editBranch(), icon: const Icon(Icons.add), label: const Text('Add')),
      ]),
      const SizedBox(height: 8),
      const Text('Branch access is restricted by the signed-in user’s branch assignment. Deactivated branches and their historical records are retained.'),
      if (busy) const LinearProgressIndicator(),
      if (message.isNotEmpty) Text(message, style: const TextStyle(color: Colors.red)),
      if (!busy && rows.isEmpty && message.isEmpty)
        const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('No branches are available to this account.'))),
      ...rows.map((row) => Card(child: ListTile(
        leading: Icon(Icons.store, color: row['is_active'] == true ? brandGreen : Colors.grey),
        title: Text('${row['name']} (${row['code']})'),
        subtitle: Text('${row['address'] ?? 'No address'} • ${row['phone'] ?? 'No phone'} • ${row['is_active'] == true ? 'Active' : 'Inactive'}'),
        trailing: isDirector ? PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'edit') editBranch(row);
            if (value == 'deactivate') deactivateBranch(row);
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'edit', child: Text('Edit')),
            if (row['is_active'] == true)
              const PopupMenuItem(value: 'deactivate', child: Text('Deactivate')),
          ],
        ) : null,
      ))),
    ]),
  );
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
      final contextRows = await db.rpc('get_my_tajir_context');
      final contextList = List<Map<String,dynamic>>.from(contextRows);
      if (contextList.isEmpty) throw Exception('Your TAJIR profile is not active yet.');
      final profile = contextList.first;
      final roleNames = List<String>.from(profile['role_names'] ?? const []);
      final branchName = profile['branch_name']?.toString();
      final s = await db.rpc('get_stock_balances');
      if (!mounted) return;
      setState(() {
        role = '${profile['display_name']} • ${roleNames.isEmpty ? 'No role assigned' : roleNames.join(', ')}${branchName == null ? '' : ' • $branchName'}';
        stock = List<Map<String,dynamic>>.from(s);
        error = null;
      });
    } catch(e) { setState(() => error = e.toString()); }
  }
  @override Widget build(BuildContext context) => RefreshIndicator(onRefresh: load, child: ListView(padding: const EdgeInsets.all(18), children: [
    const Text('Business overview', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
    Text(role, style: const TextStyle(color: Colors.black54)),
    const SizedBox(height: 18),
    const Wrap(spacing: 12, runSpacing: 12, children: [
      MetricCard(title: 'Location', value: 'Ntulele', icon: Icons.location_on),
      MetricCard(title: 'Products', value: 'Maize & Fertilizer', icon: Icons.grain),
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

class PurchasePage extends StatefulWidget { const PurchasePage({super.key}); @override State<PurchasePage> createState()=>_PurchasePageState(); }
class _PurchasePageState extends State<PurchasePage> {
  final qty=TextEditingController(), cost=TextEditingController(), supplier=TextEditingController(), notes=TextEditingController();
  String product='Maize', payer='Mercy'; bool busy=false; String message=''; List<Map<String,dynamic>> pending=[];
  @override void initState(){super.initState();loadPending();}
  Future<void> loadPending() async { try { final r=await Supabase.instance.client.rpc('get_pending_purchase_quality'); if(!mounted)return; setState(()=>pending=List<Map<String,dynamic>>.from(r)); } catch(_) {} }
  Future<void> reviewQuality(Map<String,dynamic> purchase) async {
    final items=List<Map<String,dynamic>>.from(purchase['items']??const []);
    final controllers=items.map((x)=>TextEditingController(text:(x['quantity']??0).toString())).toList();
    final accepted=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:Text('Quality check • ${purchase['purchase_number']}'),
      content:SizedBox(width:420,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        const Text('Enter the accepted quantity for each received item. Rejected quantity is calculated automatically.'),
        ...List.generate(items.length,(i)=>TextField(controller:controllers[i],keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:'Accepted of ${items[i]['quantity']} ${items[i]['unit']}'))),
      ]))),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Approve'))],
    ));
    if(accepted==true){
      try {
        final payload=<Map<String,dynamic>>[];
        for(var i=0;i<items.length;i++){ final n=double.tryParse(controllers[i].text); final max=(items[i]['quantity'] as num).toDouble(); if(n==null||n<0||n>max)throw Exception('Accepted quantity must be between 0 and $max'); payload.add({'purchase_item_id':items[i]['purchase_item_id'],'accepted_quantity':n}); }
        await Supabase.instance.client.rpc('approve_purchase_quality',params:{'p_purchase_id':purchase['purchase_id'],'p_accepted':payload});
        if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Quality decision saved. Approved quantities are now reflected in stock.')));
        await loadPending();
      } catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Quality approval failed: $e')));}
    }
    for(final c in controllers){c.dispose();}
  }
  Future<void> save() async {
    final q=double.tryParse(qty.text), c=double.tryParse(cost.text);
    if(q==null || c==null || q<=0 || c<0) { setState(()=>message='Enter a valid quantity and buying price.'); return; }
    setState(()=>busy=true);
    try {
      final db=Supabase.instance.client;
      final ctx=List<Map<String,dynamic>>.from(await db.rpc('get_my_tajir_context'));
      if(ctx.isEmpty) throw Exception('Active TAJIR profile not found.');
      var branchId=ctx.first['branch_id']?.toString();
      if(branchId==null){ final bs=await db.from('branches').select('id').eq('is_active',true).order('name').limit(1); if(bs.isEmpty) throw Exception('No active branch available.'); branchId=bs.first['id'].toString(); }
      final matches=await db.from('product_variants').select('id,base_unit,products!inner(name)').eq('products.name',product).eq('is_active',true).limit(1);
      if(matches.isEmpty) throw Exception('No active variant configured for '+product);
      final prod=matches.first;
      await db.rpc('record_purchase', params: {'p_payload': {
        'branch_id':branchId, 'purchase_date':DateTime.now().toIso8601String().substring(0,10),
        'payer':payer, 'notes':notes.text, 'items':[{'product_variant_id':prod['id'],'quantity':q,'unit_cost':c}]
      }});
      setState(()=>message='Purchase saved. Stock is quarantined pending quality approval.'); qty.clear(); cost.clear(); supplier.clear(); notes.clear(); await loadPending();
    } catch(e) { setState(()=>message='Could not save purchase: $e'); }
    if(mounted) setState(()=>busy=false);
  }
  @override Widget build(BuildContext context)=>FormPage(title:'Record purchase', children:[
    DropdownButtonFormField(value:product, items:['Maize','Fertilizer'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(), onChanged:(v)=>setState(()=>product=v!), decoration:const InputDecoration(labelText:'Product')),
    field(qty,'Quantity (bags)',number:true), field(cost,'Buying price per unit (KES)',number:true),
    field(supplier,'Supplier name'), DropdownButtonFormField(value:payer, items:['Mercy','Edu'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(), onChanged:(v)=>setState(()=>payer=v!), decoration:const InputDecoration(labelText:'Paid by')),
    field(notes,'Notes / extra details'), actionButton('Save purchase',busy,save), if(message.isNotEmpty) Text(message),
    const Divider(), const Align(alignment:Alignment.centerLeft,child:Text('Pending stock quality checks',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold))),
    if(pending.isEmpty) const Align(alignment:Alignment.centerLeft,child:Text('No purchases awaiting quality approval.')),
    ...pending.map((p)=>Card(child:ListTile(title:Text(p['purchase_number'].toString()),subtitle:Text('${(p['items'] as List).length} item(s) awaiting inspection'),trailing:TextButton(onPressed:()=>reviewQuality(p),child:const Text('Review'))))),
    const Text('Note: workers may submit buying prices for recording, but the backend must not expose finance reports or purchase-cost tables to worker accounts.',style:TextStyle(fontSize:12,color:Colors.black54)),
  ]);
}

class SalePage extends StatefulWidget { const SalePage({super.key}); @override State<SalePage> createState()=>_SalePageState(); }
class _SalePageState extends State<SalePage> {
  final qty=TextEditingController(), price=TextEditingController(), address=TextEditingController(), fee=TextEditingController(), customer=TextEditingController(), paid=TextEditingController(), reference=TextEditingController();
  String product='Maize', mode='collection', method='cash'; bool busy=false; String message='';
  Future<void> save() async {
    final q=double.tryParse(qty.text), p=double.tryParse(price.text), amount=double.tryParse(paid.text)??0, deliveryFee=double.tryParse(fee.text)??0;
    if(q==null||p==null||q<=0||p<0||(mode=='delivery'&&address.text.trim().isEmpty)){setState(()=>message='Check quantity, selling price and delivery address.');return;}
    setState(()=>busy=true);
    try {
      final db=Supabase.instance.client;
      final ctx=List<Map<String,dynamic>>.from(await db.rpc('get_my_tajir_context'));
      if(ctx.isEmpty) throw Exception('Active TAJIR profile not found.');
      var branchId=ctx.first['branch_id']?.toString();
      if(branchId==null){ final bs=await db.from('branches').select('id').eq('is_active',true).order('name').limit(1); if(bs.isEmpty) throw Exception('No active branch available.'); branchId=bs.first['id'].toString(); }
      final matches=await db.from('product_variants').select('id,base_unit,products!inner(name)').eq('products.name',product).eq('is_active',true).limit(1);
      if(matches.isEmpty) throw Exception('No active variant configured for '+product);
      final prod=matches.first;
      String? customerId;
      if(customer.text.trim().isNotEmpty){
        final matches=await db.from('customers').select('id').ilike('full_name',customer.text.trim()).limit(1);
        if(matches.isNotEmpty) customerId=matches.first['id'] as String;
      }
      final payload=<String,dynamic>{
        'branch_id':branchId,'customer_id':customerId,'customer_name':customer.text.trim(),'sale_date':DateTime.now().toIso8601String().substring(0,10),
        'fulfilment_mode':mode,'delivery_address':address.text,'delivery_fee':deliveryFee,
        'items':[{'product_variant_id':prod['id'],'quantity':q,'unit_price':p}],
      };
      if(amount>0) payload['payment']={'amount':amount,'method':method,'reference':reference.text};
      final result=await db.rpc('record_sale',params:{'p_payload':payload});
      setState(()=>message='Sale saved. Reference: ${result['sale_id']}. Balance: KES ${result['balance']}');
      qty.clear();price.clear();paid.clear();reference.clear();
    } catch(e){setState(()=>message='Could not save sale: $e');}
    if(mounted)setState(()=>busy=false);
  }
  @override Widget build(BuildContext context)=>FormPage(title:'Record sale / customer order',children:[
    DropdownButtonFormField(value:product,items:['Maize','Fertilizer'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(v)=>setState(()=>product=v!),decoration:const InputDecoration(labelText:'Product')),
    field(qty,'Quantity (bags)',number:true),field(price,'Selling price per bag (KES)',number:true),field(customer,'Customer name (optional)'),
    DropdownButtonFormField(value:mode,items:const [DropdownMenuItem(value:'collection',child:Text('Collect at your assigned branch')),DropdownMenuItem(value:'delivery',child:Text('Deliver to customer'))],onChanged:(v)=>setState(()=>mode=v!),decoration:const InputDecoration(labelText:'Fulfilment')),
    if(mode=='delivery') field(address,'Delivery address'),
    if(mode=='delivery') field(fee,'Delivery fee (KES)',number:true),
    const Divider(), const Text('Payment (optional)',style:TextStyle(fontWeight:FontWeight.bold)),
    field(paid,'Amount received (KES)',number:true),
    DropdownButtonFormField(value:method,items:const [DropdownMenuItem(value:'mpesa',child:Text('M-Pesa')),DropdownMenuItem(value:'cash',child:Text('Cash')),DropdownMenuItem(value:'bank_transfer',child:Text('Bank transfer')),DropdownMenuItem(value:'other',child:Text('Other'))],onChanged:(v)=>setState(()=>method=v!),decoration:const InputDecoration(labelText:'Payment method')),
    field(reference,'Payment reference'), actionButton('Save sale',busy,save),if(message.isNotEmpty)Text(message),
    const Text('M-Pesa is recorded as unverified until a Daraja callback integration confirms it. Do not treat a screenshot or typed code as verified payment.',style:TextStyle(fontSize:12,color:Colors.black54)),
  ]);
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
          final ctx=List<Map<String,dynamic>>.from(await db.rpc('get_my_tajir_context'));
          final assigned=ctx.isEmpty?null:ctx.first['branch_id'];
          if(assigned!=null)values['default_branch_id']=assigned;
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
    try { await Supabase.instance.client.from('customers').update({'active':active}).eq('id',row['id']); await load(); }
    catch(e){ if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Could not update customer: $e'))); }
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
            if(r['active']==false)const PopupMenuItem(value:'activate',child:Text('Reactivate')),
          ]),
      ))),
      const Padding(padding:EdgeInsets.only(top:8),child:Text('Customer balances count verified payments only. Pending, rejected and reversed payments are not treated as money received.',style:TextStyle(fontSize:12,color:Colors.black54))),
    ]);
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
