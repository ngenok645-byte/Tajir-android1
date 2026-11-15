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

  static const previewMode =
      bool.fromEnvironment('TAJIR_PREVIEW');

  @override
  Widget build(BuildContext context) {
    if (previewMode) {
      return const PreviewHome();
    }

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
  bool busy = false, signup = false;
  String? error;
  Future<void> submit() async {
    setState(() { busy = true; error = null; });
    try {
      final auth = Supabase.instance.client.auth;
      if (signup) {
        await auth.signUp(email: email.text.trim(), password: password.text);
        if (mounted) setState(() => error = 'Account request submitted. An administrator must assign your TAJIR role.');
      } else {
        await auth.signInWithPassword(email: email.text.trim(), password: password.text);
      }
    } on AuthException catch (e) { setState(() => error = e.message); }
      catch (e) { setState(() => error = 'Could not sign in: $e'); }
    if (mounted) setState(() => busy = false);
  }
  @override Widget build(BuildContext context) => Scaffold(
    body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420),
      child: Card(margin: const EdgeInsets.all(24), child: Padding(padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const BrandMark(), const SizedBox(height: 24),
          Text(signup ? 'Create account' : 'Sign in to TAJIR', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 18),
          TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder())),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: Colors.red))),
          const SizedBox(height: 16),
          FilledButton(onPressed: busy ? null : submit, child: Text(busy ? 'Please wait…' : signup ? 'Request account' : 'Sign in')),
          TextButton(onPressed: () => setState(() { signup = !signup; error = null; }), child: Text(signup ? 'Back to sign in' : 'Create an account')),
          const Text('Only an authorized administrator can grant staff roles.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.black54)),
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
  final pages = const [DashboardPage(), PurchasePage(), SalePage(), StockPage(), CustomersPage()];
  final labels = const ['Dashboard','Purchases','Sales','Stock','Customers'];
  final icons = const [Icons.dashboard, Icons.add_shopping_cart, Icons.point_of_sale, Icons.inventory_2, Icons.people];
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
  String product='Maize', payer='Mercy'; bool busy=false; String message='';
  Future<void> save() async {
    final q=double.tryParse(qty.text), c=double.tryParse(cost.text);
    if(q==null || c==null || q<=0 || c<0) { setState(()=>message='Enter a valid quantity and buying price.'); return; }
    setState(()=>busy=true);
    try {
      final db=Supabase.instance.client;
      final branch=await db.from('branches').select('id').eq('name','TAJIR Ntulele').single();
      final prod=await db.from('products').select('id,unit').eq('category',product.toLowerCase()).single();
      await db.rpc('record_purchase', params: {'p_payload': {
        'branch_id':branch['id'], 'purchase_date':DateTime.now().toIso8601String().substring(0,10),
        'payer':payer, 'notes':notes.text, 'items':[{'product_id':prod['id'],'quantity':q,'unit_cost':c,'unit':prod['unit'],'details':{'supplier':supplier.text}}]
      }});
      setState(()=>message='Purchase saved and stock updated.'); qty.clear(); cost.clear(); supplier.clear(); notes.clear();
    } catch(e) { setState(()=>message='Could not save purchase: $e'); }
    if(mounted) setState(()=>busy=false);
  }
  @override Widget build(BuildContext context)=>FormPage(title:'Record purchase', children:[
    DropdownButtonFormField(value:product, items:['Maize','Fertilizer'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(), onChanged:(v)=>setState(()=>product=v!), decoration:const InputDecoration(labelText:'Product')),
    field(qty,'Quantity (bags)',number:true), field(cost,'Buying price per unit (KES)',number:true),
    field(supplier,'Supplier name'), DropdownButtonFormField(value:payer, items:['Mercy','Edu','Company','Other'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(), onChanged:(v)=>setState(()=>payer=v!), decoration:const InputDecoration(labelText:'Paid by')),
    field(notes,'Notes / extra details'), actionButton('Save purchase',busy,save), if(message.isNotEmpty) Text(message),
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
      final branch=await db.from('branches').select('id').eq('name','TAJIR Ntulele').single();
      final prod=await db.from('products').select('id').eq('category',product.toLowerCase()).single();
      String? customerId;
      if(customer.text.trim().isNotEmpty){
        final matches=await db.from('customers').select('id').ilike('name',customer.text.trim()).limit(1);
        if(matches.isNotEmpty) customerId=matches.first['id'] as String;
      }
      final payload=<String,dynamic>{
        'branch_id':branch['id'],'customer_id':customerId,'sale_date':DateTime.now().toIso8601String().substring(0,10),
        'fulfilment_mode':mode,'delivery_address':address.text,'delivery_fee':deliveryFee,
        'items':[{'product_id':prod['id'],'quantity':q,'unit_price':p}],
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
    DropdownButtonFormField(value:mode,items:const [DropdownMenuItem(value:'collection',child:Text('Collect at Ntulele')),DropdownMenuItem(value:'delivery',child:Text('Deliver to customer'))],onChanged:(v)=>setState(()=>mode=v!),decoration:const InputDecoration(labelText:'Fulfilment')),
    if(mode=='delivery') field(address,'Delivery address'),
    if(mode=='delivery') field(fee,'Delivery fee (KES)',number:true),
    const Divider(), const Text('Payment (optional)',style:TextStyle(fontWeight:FontWeight.bold)),
    field(paid,'Amount received (KES)',number:true),
    DropdownButtonFormField(value:method,items:const [DropdownMenuItem(value:'mpesa',child:Text('M-Pesa')),DropdownMenuItem(value:'cash',child:Text('Cash')),DropdownMenuItem(value:'bank',child:Text('Bank')),DropdownMenuItem(value:'credit',child:Text('Credit'))],onChanged:(v)=>setState(()=>method=v!),decoration:const InputDecoration(labelText:'Payment method')),
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
class CustomersPage extends StatefulWidget {const CustomersPage({super.key});@override State<CustomersPage> createState()=>_CustomersPageState();}
class _CustomersPageState extends State<CustomersPage>{
  List<dynamic> rows=[];String message='';
  Future<void> load()async{try{final r=await Supabase.instance.client.from('customers').select('name,phone,default_address').order('name');setState(()=>rows=List<dynamic>.from(r));}catch(e){setState(()=>message='Customer list unavailable: $e');}}
  @override void initState(){super.initState();load();}
  @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.all(18),children:[
    const Text('Customers',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold)),
    Align(alignment:Alignment.centerLeft,child:OutlinedButton.icon(onPressed:load,icon:const Icon(Icons.refresh),label:const Text('Refresh'))),
    if(message.isNotEmpty)Text(message),
    ...rows.map((r)=>Card(child:ListTile(leading:const CircleAvatar(child:Icon(Icons.person)),title:Text(r['name']??''),subtitle:Text('${r['phone']??''}  ${r['default_address']??''}')))),
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
      'date': '\${selectedDate.year}-\${selectedDate.month.toString().padLeft(2, '0')}-\${selectedDate.day.toString().padLeft(2, '0')}',
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
            label: Text('Date: \${selectedDate.year}-\${selectedDate.month.toString().padLeft(2, '0')}-\${selectedDate.day.toString().padLeft(2, '0')}'),
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
        Text(isSale ? 'Preview sales (\${records.length})' : 'Preview purchases (\${records.length})',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        if (records.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('No entries added yet.')),
        ...records.map((r) => Card(child: ListTile(
          title: Text('\${r['product']} • \${r['variety']}'),
          subtitle: Text('\${r['date']}  |  \${r['quantity']} bags'),
          trailing: Text('KES \${r['price']}'),
        ))),
      ],
    );
  }

  Widget homePage() => const ListView(padding: EdgeInsets.all(20), children: [
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
      const Center(child: Text('Stock preview — live stock is not connected in preview mode.')),
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
