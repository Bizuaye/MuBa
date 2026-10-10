// ============================================================
// VETSTOCK - Veterinary Drugs Wholesale Manager
// Single-file app: inventory, expiry, profit, customer credit
// ============================================================
import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:intl/intl.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DB.instance.database;
  runApp(const VetStockApp());
}

// ============================================================
// DATABASE
// ============================================================
class DB {
  static final DB instance = DB._();
  DB._();
  static Database? _db;

  Future<Database> get database async {
    _db ??= await _init();
    return _db!;
  }

  Future<Database> _init() async {
    final p = join(await getDatabasesPath(), 'vetstock.db');
    return openDatabase(p, version: 1, onCreate: (db, v) async {
      await db.execute('''CREATE TABLE drugs(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT, category TEXT, batch TEXT, supplier TEXT,
        qty INTEGER, cost REAL, sell REAL, expiry TEXT, notes TEXT)''');
      await db.execute('''CREATE TABLE customers(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT, phone TEXT, address TEXT, limitAmt REAL DEFAULT 0)''');
      await db.execute('''CREATE TABLE txns(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customerId INTEGER, drugId INTEGER,
        description TEXT, amount REAL, date TEXT, type TEXT)''');
    });
  }

  Future<List<Map<String, dynamic>>> getDrugs() async {
    final db = await database;
    return db.query('drugs', orderBy: 'expiry ASC');
  }

  Future<int> insertDrug(Map<String, dynamic> d) async {
    final db = await database;
    d.remove('id');
    return db.insert('drugs', d);
  }

  Future<int> updateDrug(Map<String, dynamic> d) async {
    final db = await database;
    return db.update('drugs', d, where: 'id=?', whereArgs: [d['id']]);
  }

  Future<void> deleteDrug(int id) async {
    final db = await database;
    await db.delete('drugs', where: 'id=?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getCustomers() async {
    final db = await database;
    return db.query('customers', orderBy: 'name ASC');
  }

  Future<int> insertCustomer(Map<String, dynamic> c) async {
    final db = await database;
    c.remove('id');
    return db.insert('customers', c);
  }

  Future<int> updateCustomer(Map<String, dynamic> c) async {
    final db = await database;
    return db.update('customers', c, where: 'id=?', whereArgs: [c['id']]);
  }

  Future<void> deleteCustomer(int id) async {
    final db = await database;
    await db.delete('txns', where: 'customerId=?', whereArgs: [id]);
    await db.delete('customers', where: 'id=?', whereArgs: [id]);
  }

  Future<int> insertTxn(Map<String, dynamic> t) async {
    final db = await database;
    t.remove('id');
    return db.insert('txns', t);
  }

  Future<List<Map<String, dynamic>>> getTxns(int customerId) async {
    final db = await database;
    return db.query('txns',
        where: 'customerId=?', whereArgs: [customerId], orderBy: 'date DESC');
  }

  Future<double> getBalance(int customerId) async {
    final db = await database;
    final r = await db.rawQuery(
        'SELECT COALESCE(SUM(amount),0) AS t FROM txns WHERE customerId=?',
        [customerId]);
    return (r.first['t'] as num).toDouble();
  }

  Future<Map<int, double>> getAllBalances() async {
    final db = await database;
    final r = await db
        .rawQuery('SELECT customerId, SUM(amount) AS t FROM txns GROUP BY customerId');
    return {
      for (final x in r) (x['customerId'] as int): (x['t'] as num).toDouble()
    };
  }
}

// ============================================================
// APP ROOT
// ============================================================
class VetStockApp extends StatelessWidget {
  const VetStockApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VetStock',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

// ============================================================
// HOME PAGE (2 tabs)
// ============================================================
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<Map<String, dynamic>> _drugs = [];
  List<Map<String, dynamic>> _filtered = [];
  List<Map<String, dynamic>> _customers = [];
  Map<int, double> _balances = {};
  final _search = TextEditingController();
  int _filter = 0;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() => setState(() {}));
    _load();
  }

  Future<void> _load() async {
    final d = await DB.instance.getDrugs();
    final c = await DB.instance.getCustomers();
    final b = await DB.instance.getAllBalances();
    setState(() {
      _drugs = d;
      _customers = c;
      _balances = b;
      _apply();
    });
  }

  void _apply() {
    final q = _search.text.toLowerCase();
    List<Map<String, dynamic>> base = _drugs;
    if (_filter == 1) {
      base = base.where((d) => _isExpired(d)).toList();
    } else if (_filter == 2) {
      base = base.where((d) => _isSoon(d)).toList();
    } else if (_filter == 3) {
      base = base.where((d) => (d['qty'] as int) <= 10).toList();
    }
    if (q.isNotEmpty) {
      base = base.where((d) =>
          (d['name'] ?? '').toString().toLowerCase().contains(q) ||
          (d['category'] ?? '').toString().toLowerCase().contains(q) ||
          (d['supplier'] ?? '').toString().toLowerCase().contains(q) ||
          (d['batch'] ?? '').toString().toLowerCase().contains(q)).toList();
    }
    _filtered = base;
  }

  bool _isExpired(Map d) =>
      DateTime.parse(d['expiry']).isBefore(DateTime.now());
  bool _isSoon(Map d) {
    final days = DateTime.parse(d['expiry']).difference(DateTime.now()).inDays;
    return days >= 0 && days <= 30;
  }

  int _daysLeft(Map d) =>
      DateTime.parse(d['expiry']).difference(DateTime.now()).inDays;

  Color _statusColor(Map d) => _isExpired(d)
      ? Colors.red
      : (_isSoon(d) ? Colors.orange : Colors.green);

  String _statusText(Map d) {
    if (_isExpired(d)) return 'EXPIRED ${-_daysLeft(d)}d ago';
    if (_isSoon(d)) return 'Expires in ${_daysLeft(d)}d';
    return 'OK';
  }

  double _profit(Map d) => (d['sell'] as num).toDouble() - (d['cost'] as num).toDouble();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VetStock'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.medical_services), text: 'Inventory'),
            Tab(icon: Icon(Icons.people), text: 'Customers'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [_inventoryTab(), _customersTab()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text(_tab.index == 0 ? 'Add Drug' : 'Add Customer'),
        onPressed: () async {
          if (_tab.index == 0) {
            await Navigator.push(context,
                MaterialPageRoute(builder: (_) => const DrugFormPage()));
          } else {
            await Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CustomerFormPage()));
          }
          _load();
        },
      ),
    );
  }

  // -------- INVENTORY TAB --------
  Widget _inventoryTab() {
    double totalCost = 0, totalSell = 0;
    for (final d in _drugs) {
      totalCost += (d['cost'] as num).toDouble() * (d['qty'] as int);
      totalSell += (d['sell'] as num).toDouble() * (d['qty'] as int);
    }
    final profit = totalSell - totalCost;
    final expired = _drugs.where(_isExpired).length;
    final soon = _drugs.where(_isSoon).length;

    return Column(children: [
      Container(
        color: Colors.teal.shade50,
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          _kpi('Cost', '\$${totalCost.toStringAsFixed(0)}', Colors.blueGrey),
          _kpi('Value', '\$${totalSell.toStringAsFixed(0)}', Colors.blue),
          _kpi('Profit', '\$${profit.toStringAsFixed(0)}', Colors.green),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.all(6),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _chip('All (${_drugs.length})', 0, Colors.teal),
            _chip('Expired ($expired)', 1, Colors.red),
            _chip('Soon ($soon)', 2, Colors.orange),
            _chip('Low Stock', 3, Colors.purple),
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: TextField(
          controller: _search,
          onChanged: (_) => setState(_apply),
          decoration: InputDecoration(
            hintText: 'Search name, batch, supplier...',
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            isDense: true,
          ),
        ),
      ),
      const SizedBox(height: 6),
      Expanded(
        child: _filtered.isEmpty
            ? const Center(child: Text('No drugs. Tap + to add.'))
            : ListView.builder(
                itemCount: _filtered.length,
                itemBuilder: (_, i) {
                  final d = _filtered[i];
                  final df = DateFormat('yyyy-MM-dd');
                  final exp = DateTime.parse(d['expiry']);
                  final p = _profit(d);
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _statusColor(d).withOpacity(0.15),
                        child: Icon(Icons.medical_services, color: _statusColor(d)),
                      ),
                      title: Text(d['name'] ?? '',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${d['category']} • Batch: ${d['batch']}'),
                            Text(
                                'Qty: ${d['qty']} • Cost: \$${(d['cost'] as num).toStringAsFixed(2)} • Sell: \$${(d['sell'] as num).toStringAsFixed(2)}'),
                            Text(
                              'Profit/unit: \$${p.toStringAsFixed(2)}${p < 0 ? " ⚠ LOSS" : ""}',
                              style: TextStyle(
                                color: p < 0 ? Colors.red : Colors.green,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text('Exp: ${df.format(exp)} • ${_statusText(d)}',
                                style: TextStyle(
                                    color: _statusColor(d), fontSize: 12)),
                          ]),
                      isThreeLine: true,
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'edit') {
                            await Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => DrugFormPage(drug: d)));
                            _load();
                          } else if (v == 'delete') {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text('Delete drug?'),
                                content: Text('Remove "${d['name']}"?'),
                                actions: [
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('Cancel')),
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('Delete')),
                                ],
                              ),
                            );
                            if (ok == true) {
                              await DB.instance.deleteDrug(d['id']);
                              _load();
                            }
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    ]);
  }

  Widget _kpi(String label, String value, Color color) => Expanded(
        child: Column(children: [
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16, color: color)),
          Text(label, style: TextStyle(fontSize: 12, color: color)),
        ]),
      );

  Widget _chip(String label, int index, Color color) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ChoiceChip(
          label: Text(label, style: const TextStyle(fontSize: 12)),
          selected: _filter == index,
          selectedColor: color.withOpacity(0.2),
          onSelected: (_) => setState(() {
            _filter = index;
            _apply();
          }),
        ),
      );

  // -------- CUSTOMERS TAB --------
  Widget _customersTab() {
    double totalDebt = 0;
    int debtors = 0;
    for (final b in _balances.values) {
      if (b > 0) {
        totalDebt += b;
        debtors++;
      }
    }

    return Column(children: [
      Container(
        color: Colors.red.shade50,
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          const Icon(Icons.account_balance_wallet, color: Colors.red, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Owed to You: \$${totalDebt.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                          fontSize: 16)),
                  Text('$debtors customer(s) with balance'),
                ]),
          ),
        ]),
      ),
      Expanded(
        child: _customers.isEmpty
            ? const Center(child: Text('No customers. Tap + to add.'))
            : ListView.builder(
                itemCount: _customers.length,
                itemBuilder: (_, i) {
                  final c = _customers[i];
                  final bal = _balances[c['id']] ?? 0;
                  final limit = (c['limitAmt'] as num?)?.toDouble() ?? 0;
                  final over = limit > 0 && bal > limit;
                  return Card(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            bal > 0 ? Colors.red.shade100 : Colors.green.shade100,
                        child: Icon(Icons.person,
                            color: bal > 0 ? Colors.red : Colors.green),
                      ),
                      title: Text(c['name'] ?? '',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c['phone'] ?? ''),
                            Text('Balance: \$${bal.toStringAsFixed(2)}',
                                style: TextStyle(
                                  color: bal > 0 ? Colors.red : Colors.green,
                                  fontWeight: FontWeight.w600,
                                )),
                            if (limit > 0)
                              Text(
                                  'Limit: \$${limit.toStringAsFixed(2)}${over ? " ⚠ OVER" : ""}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: over ? Colors.red : Colors.grey)),
                          ]),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => CustomerFormPage(customer: c)));
                        _load();
                      },
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}

// ============================================================
// DRUG FORM (Add / Edit)
// ============================================================
class DrugFormPage extends StatefulWidget {
  final Map<String, dynamic>? drug;
  const DrugFormPage({super.key, this.drug});
  @override
  State<DrugFormPage> createState() => _DrugFormPageState();
}

class _DrugFormPageState extends State<DrugFormPage> {
  final _name = TextEditingController();
  final _cat = TextEditingController();
  final _batch = TextEditingController();
  final _sup = TextEditingController();
  final _qty = TextEditingController();
  final _cost = TextEditingController();
  final _sell = TextEditingController();
  final _notes = TextEditingController();
  DateTime _expiry = DateTime.now().add(const Duration(days: 365));

  @override
  void initState() {
    super.initState();
    final d = widget.drug;
    if (d != null) {
      _name.text = d['name'] ?? '';
      _cat.text = d['category'] ?? '';
      _batch.text = d['batch'] ?? '';
      _sup.text = d['supplier'] ?? '';
      _qty.text = d['qty'].toString();
      _cost.text = d['cost'].toString();
      _sell.text = d['sell'].toString();
      _notes.text = d['notes'] ?? '';
      _expiry = DateTime.parse(d['expiry']);
    }
    _cost.addListener(() => setState(() {}));
    _sell.addListener(() => setState(() {}));
    _qty.addListener(() => setState(() {}));
  }

  Future<void> _pickDate() async {
    final p = await showDatePicker(
      context: context,
      initialDate: _expiry,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (p != null) setState(() => _expiry = p);
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty ||
        _qty.text.isEmpty ||
        _cost.text.isEmpty ||
        _sell.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fill all required fields')));
      return;
    }
    final map = {
      if (widget.drug != null) 'id': widget.drug!['id'],
      'name': _name.text.trim(),
      'category': _cat.text.trim(),
      'batch': _batch.text.trim(),
      'supplier': _sup.text.trim(),
      'qty': int.tryParse(_qty.text) ?? 0,
      'cost': double.tryParse(_cost.text) ?? 0,
      'sell': double.tryParse(_sell.text) ?? 0,
      'expiry': DateFormat('yyyy-MM-dd').format(_expiry),
      'notes': _notes.text.trim(),
    };
    if (widget.drug == null) {
      await DB.instance.insertDrug(map);
    } else {
      await DB.instance.updateDrug(map);
    }
    if (mounted) Navigator.pop(context);
  }

  Widget _field(TextEditingController c, String label,
      {bool num = false, bool dec = false, int maxLines = 1}) {
    return TextField(
      controller: c,
      maxLines: maxLines,
      keyboardType: num
          ? (dec
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.number)
          : TextInputType.text,
      decoration:
          InputDecoration(labelText: label, border: const OutlineInputBorder()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cost = double.tryParse(_cost.text) ?? 0;
    final sell = double.tryParse(_sell.text) ?? 0;
    final qty = int.tryParse(_qty.text) ?? 0;
    final profit = sell - cost;
    final loss = profit < 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.drug == null ? 'Add Drug' : 'Edit Drug'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _field(_name, 'Drug Name *'),
          const SizedBox(height: 12),
          _field(_cat, 'Category (Antibiotic, Vaccine...)'),
          const SizedBox(height: 12),
          _field(_batch, 'Batch Number'),
          const SizedBox(height: 12),
          _field(_sup, 'Supplier'),
          const SizedBox(height: 12),
          _field(_qty, 'Quantity *', num: true),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _field(_cost, 'Cost Price *', num: true, dec: true)),
            const SizedBox(width: 10),
            Expanded(child: _field(_sell, 'Selling Price *', num: true, dec: true)),
          ]),
          const SizedBox(height: 12),
          Card(
            color: loss ? Colors.red.shade50 : Colors.green.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(loss ? Icons.trending_down : Icons.trending_up,
                          color: loss ? Colors.red : Colors.green),
                      const SizedBox(width: 6),
                      Text('Profit/unit: \$${profit.toStringAsFixed(2)}',
                          style: TextStyle(
                              color: loss ? Colors.red : Colors.green,
                              fontWeight: FontWeight.bold)),
                    ]),
                    Text('Total if all sold: \$${(profit * qty).toStringAsFixed(2)}'),
                  ]),
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Expiry Date',
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.calendar_today),
              ),
              child: Text(DateFormat('yyyy-MM-dd').format(_expiry)),
            ),
          ),
          const SizedBox(height: 12),
          _field(_notes, 'Notes (optional)', maxLines: 3),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: Text(widget.drug == null ? 'Save' : 'Update'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// CUSTOMER FORM (Add / Edit + Sale + Payment)
// ============================================================
class CustomerFormPage extends StatefulWidget {
  final Map<String, dynamic>? customer;
  const CustomerFormPage({super.key, this.customer});
  @override
  State<CustomerFormPage> createState() => _CustomerFormPageState();
}

class _CustomerFormPageState extends State<CustomerFormPage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _addr = TextEditingController();
  final _limit = TextEditingController(text: '0');

  Map<String, dynamic>? _c;
  List<Map<String, dynamic>> _txns = [];
  double _balance = 0;

  @override
  void initState() {
    super.initState();
    _c = widget.customer;
    if (_c != null) {
      _name.text = _c!['name'] ?? '';
      _phone.text = _c!['phone'] ?? '';
      _addr.text = _c!['address'] ?? '';
      _limit.text = (_c!['limitAmt'] ?? 0).toString();
      _loadTxns();
    }
  }

  Future<void> _loadTxns() async {
    if (_c == null) return;
    final t = await DB.instance.getTxns(_c!['id']);
    final b = await DB.instance.getBalance(_c!['id']);
    setState(() {
      _txns = t;
      _balance = b;
    });
  }

  Future<void> _saveCustomer() async {
    if (_name.text.trim().isEmpty || _phone.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Name and phone required')));
      return;
    }
    final map = {
      if (_c != null) 'id': _c!['id'],
      'name': _name.text.trim(),
      'phone': _phone.text.trim(),
      'address': _addr.text.trim(),
      'limitAmt': double.tryParse(_limit.text) ?? 0,
    };
    if (_c == null) {
      final id = await DB.instance.insertCustomer(map);
      _c = {...map, 'id': id};
    } else {
      await DB.instance.updateCustomer(map);
    }
    await _loadTxns();
    if (mounted) setState(() {});
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete customer?'),
        content: const Text('All history will be deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      await DB.instance.deleteCustomer(_c!['id']);
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _recordSale() async {
    final drugs = await DB.instance.getDrugs();
    if (drugs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add drugs first')));
      return;
    }
    Map<String, dynamic>? selected = drugs.first;
    final qtyCtrl = TextEditingController(text: '1');
    final priceCtrl =
        TextEditingController(text: (drugs.first['sell'] as num).toString());
    bool paidFull = false;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Sale on Credit'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<Map<String, dynamic>>(
                value: selected,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Drug'),
                items: drugs
                    .map((d) => DropdownMenuItem(
                          value: d,
                          child: Text('${d['name']} (${d['qty']} left)',
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) {
                  setS(() {
                    selected = v;
                    priceCtrl.text = (v!['sell'] as num).toString();
                  });
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: qtyCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantity'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: priceCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Unit Price'),
              ),
              CheckboxListTile(
                value: paidFull,
                onChanged: (v) => setS(() => paidFull = v!),
                title: const Text('Paid in full (no debt)'),
                contentPadding: EdgeInsets.zero,
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save')),
          ],
        ),
      ),
    );

    if (ok != true || selected == null) return;
    final qty = int.tryParse(qtyCtrl.text) ?? 0;
    final price = double.tryParse(priceCtrl.text) ?? 0;
    if (qty <= 0) return;
    if (qty > (selected!['qty'] as int)) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Only ${selected!['qty']} in stock')));
      return;
    }

    final updated = Map<String, dynamic>.from(selected!);
    updated['qty'] = (selected!['qty'] as int) - qty;
    await DB.instance.updateDrug(updated);

    await DB.instance.insertTxn({
      'customerId': _c!['id'],
      'drugId': selected!['id'],
      'description':
          'Sold $qty x ${selected!['name']}${paidFull ? " (PAID)" : ""}',
      'amount': paidFull ? 0.0 : qty * price,
      'date': DateTime.now().toIso8601String(),
      'type': 'sale',
    });
    _loadTxns();
  }

  Future<void> _recordPayment() async {
    final amt = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Record Payment'),
        content: TextField(
          controller: amt,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
              labelText: 'Amount',
              helperText: 'Balance: \$${_balance.toStringAsFixed(2)}'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    final a = double.tryParse(amt.text) ?? 0;
    if (a <= 0) return;
    await DB.instance.insertTxn({
      'customerId': _c!['id'],
      'description': 'Payment received',
      'amount': -a,
      'date': DateTime.now().toIso8601String(),
      'type': 'payment',
    });
    _loadTxns();
  }

  @override
  Widget build(BuildContext context) {
    final isNew = _c == null;
    final df = DateFormat('yyyy-MM-dd HH:mm');
    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'New Customer' : _c!['name']),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          if (!isNew)
            IconButton(icon: const Icon(Icons.delete), onPressed: _delete),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
              controller: _name,
              decoration: const InputDecoration(
                  labelText: 'Customer Name *',
                  border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                  labelText: 'Phone *', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(
              controller: _addr,
              decoration: const InputDecoration(
                  labelText: 'Address', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(
              controller: _limit,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Credit Limit (0 = no limit)',
                  border: OutlineInputBorder())),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _saveCustomer,
            icon: const Icon(Icons.save),
            label: Text(isNew ? 'Create Customer' : 'Update Info'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          if (!isNew) ...[
            const Divider(height: 40),
            Card(
              color: _balance > 0 ? Colors.red.shade50 : Colors.green.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  Text(_balance > 0 ? 'OWES YOU' : 'BALANCE',
                      style:
                          const TextStyle(fontSize: 12, color: Colors.grey)),
                  Text('\$${_balance.abs().toStringAsFixed(2)}',
                      style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color:
                              _balance > 0 ? Colors.red : Colors.green)),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                  child: ElevatedButton.icon(
                onPressed: _recordSale,
                icon: const Icon(Icons.shopping_cart),
                label: const Text('Sale'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white),
              )),
              const SizedBox(width: 8),
              Expanded(
                  child: ElevatedButton.icon(
                onPressed: _balance > 0 ? _recordPayment : null,
                icon: const Icon(Icons.payments),
                label: const Text('Payment'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white),
              )),
            ]),
            const Divider(height: 40),
            const Text('History',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            if (_txns.isEmpty)
              const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: Text('No transactions yet'))),
            ..._txns.map((t) => Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: (t['amount'] as num) > 0
                          ? Colors.red.shade100
                          : Colors.green.shade100,
                      child: Icon(
                          (t['amount'] as num) > 0
                              ? Icons.arrow_upward
                              : Icons.arrow_downward,
                          color: (t['amount'] as num) > 0
                              ? Colors.red
                              : Colors.green,
                          size: 18),
                    ),
                    title: Text(t['description'] ?? ''),
                    subtitle: Text(df.format(DateTime.parse(t['date']))),
                    trailing: Text(
                      '${(t['amount'] as num) > 0 ? "+" : ""}\$${(t['amount'] as num).abs().toStringAsFixed(2)}',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: (t['amount'] as num) > 0
                              ? Colors.red
                              : Colors.green),
                    ),
                  ),
                )),
          ],
        ],
      ),
    );
  }
}
