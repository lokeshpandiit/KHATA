import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/storage_backup_service.dart';
import '../services/farm_reminder_service.dart';
import '../widgets/khet_map_widget.dart';
import '../widgets/plot_selector.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {

  double _amount(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString().replaceAll(',', '').replaceAll('₹', '').trim()) ?? 0;
  }

  DateTime? _date(Map<String, dynamic> row) {
    for (final key in ['date', 'createdAt', 'updatedAt']) {
      final value = row[key];
      if (value is String) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  double _balance(Map<String, dynamic> row) {
    final explicit = row['balance'];
    if (explicit is num) return explicit.toDouble();
    final total = _amount(row['totalAmount'] ?? row['price']);
    final paid = _amount(row['paidAmount']);
    return (total - paid).clamp(0, double.infinity).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final storage = StorageBackupService.instance;
    return ValueListenableBuilder<int>(
      valueListenable: storage.revision,
      builder: (context, _, __) => _buildDashboard(context, storage),
    );
  }

  String? _selectedMonth;
  String _monthKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

  Widget _buildDashboard(BuildContext context, StorageBackupService storage) {
    final hisabs = storage.records('hisabs');
    final khet = storage.records('khet');
    final now = DateTime.now();
    final monthKeys = <String>{_monthKey(now), ...hisabs.map(_date).whereType<DateTime>().map(_monthKey), ...khet.map(_date).whereType<DateTime>().map(_monthKey)}.toList()..sort((a,b)=>b.compareTo(a));
    if (_selectedMonth == null) _selectedMonth = _monthKey(now);
    if (!monthKeys.contains(_selectedMonth)) _selectedMonth = monthKeys.first;
    final selectedParts = _selectedMonth!.split('-');
    final selectedDate = DateTime(int.parse(selectedParts[0]), int.parse(selectedParts[1]));
    bool thisMonth(Map<String, dynamic> row) {
      final date = _date(row);
      return date != null && _monthKey(date) == _selectedMonth;
    }
    final monthHisabAmount = hisabs.where(thisMonth).fold<double>(
      0, (sum, row) => sum + _amount(row['amount']),
    );
    final monthKhetAmount = khet.where(thisMonth)
        .where((row) => row['type'] != 'PANI' && row['type'] != 'TRACTOR')
        .fold<double>(0, (sum, row) => sum + _amount(row['price']));
    final monthPani = khet.where(thisMonth)
        .where((row) => row['type'] == 'PANI' && row['ledgerMode'] != 'PERSON')
        .fold<int>(0, (sum, row) => sum + ((row['minutes'] as num?)?.toInt() ?? 0));
    final pending = khet.where((row) => row['type'] == 'TRACTOR' && _balance(row) > 0 && thisMonth(row)).toList()
      ..sort((a, b) => (DateTime.tryParse(a['dueDate'] as String? ?? '') ?? DateTime(9999))
          .compareTo(DateTime.tryParse(b['dueDate'] as String? ?? '') ?? DateTime(9999)));
    final pendingTotal = pending.fold<double>(0, (sum, row) => sum + _balance(row));
    final money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Namaste, ${storage.senderName} 👋', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(DateFormat('EEEE, dd MMMM yyyy').format(now), style: const TextStyle(color: Colors.black54)),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _selectedMonth,
                items: monthKeys.map((key) {
                  final parts = key.split('-');
                  final date = DateTime(int.parse(parts[0]), int.parse(parts[1]));
                  return DropdownMenuItem(value: key, child: Text(DateFormat('MMMM yyyy').format(date)));
                }).toList(),
                onChanged: (value) => setState(() => _selectedMonth = value),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        const KhetMapWidget(),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => _PendingPaymentsScreen(rows: pending, waterRows: khet.where((r) => r['type'] == 'PANI' && r['waterPaymentPending'] == true && thisMonth(r)).toList(), money: money, storage: storage, monthTitle: DateFormat('MMMM yyyy').format(selectedDate)),
            )),
            child: _MetricCard(title: 'Pending payments', value: money.format(pendingTotal), icon: Icons.pending_actions, tint: const Color(0xFFE5F2EC)),
          )),
          const SizedBox(width: 10),
          Expanded(child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => _MonthPersonLedgerScreen(rows: hisabs.where(thisMonth).toList(), monthTitle: DateFormat('MMMM yyyy').format(selectedDate)),
            )),
            child: _MetricCard(title: '${DateFormat('MMMM yyyy').format(selectedDate)} Hisab', value: money.format(monthHisabAmount), icon: Icons.receipt_long, tint: const Color(0xFFEAF0FA)),
          )),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: InkWell(onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => _KhetExpensesScreen(rows: khet, money: money, initialMonth: _selectedMonth))), child: _MetricCard(title: 'Khet expenses', value: money.format(monthKhetAmount), icon: Icons.agriculture, tint: const Color(0xFFF8EEDC)))),
          const SizedBox(width: 10),
          Expanded(child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => _MonthPaniScreen(rows: khet.where((row) => thisMonth(row) && row['type'] == 'PANI' && row['ledgerMode'] != 'PERSON').toList(), storage: storage, monthTitle: DateFormat('MMMM yyyy').format(selectedDate)),
            )),
            child: _MetricCard(title: 'Pani total', value: '${monthPani ~/ 60}h ${monthPani % 60}m', icon: Icons.water_drop, tint: const Color(0xFFE7F3FA)),
          )),
        ]),
        const SizedBox(height: 8),
      ],
    );
  }

}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.title, required this.value, required this.icon, required this.tint});
  final String title, value;
  final IconData icon;
  final Color tint;
  @override
  Widget build(BuildContext context) => Card(child: Padding(
    padding: const EdgeInsets.all(14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      CircleAvatar(backgroundColor: tint, child: Icon(icon)),
      const SizedBox(height: 10),
      Text(title, style: const TextStyle(color: Colors.black54, fontSize: 12)),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
    ]),
  ));
}

class _MonthPersonLedgerScreen extends StatelessWidget {
  const _MonthPersonLedgerScreen({required this.rows, required this.monthTitle});
  final List<Map<String, dynamic>> rows;
  final String monthTitle;

  double _amount(dynamic value) => value is num ? value.toDouble() :
      double.tryParse((value ?? '').toString().replaceAll(',', '').replaceAll('₹', '').trim()) ?? 0;
  String _person(Map<String, dynamic> row) {
    final name = (row['personName'] ?? '').toString().trim();
    return name.isEmpty ? 'Unknown person' : name;
  }
  double _delta(Map<String, dynamic> row) {
    final amount = _amount(row['amount']);
    return row['direction'] == 'PAID' ? -amount : amount;
  }

  @override
  Widget build(BuildContext context) {
    final people = <String, List<Map<String, dynamic>>>{};
    for (final row in rows.where((r) => r['category'] == 'Len-Den')) {
      people.putIfAbsent(_person(row), () => []).add(row);
    }
    final money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final sorted = people.keys.toList()..sort();
    return Scaffold(
      appBar: AppBar(title: Text('$monthTitle · Person Hisab')),
      body: sorted.isEmpty
          ? const Center(child: Text('Is month person-to-person Len-Den entries nahi hain.'))
          : ListView(padding: const EdgeInsets.all(16), children: sorted.map((name) {
              final personRows = people[name]!..sort((a,b) =>
                (DateTime.tryParse(b['date'] as String? ?? '') ?? DateTime(0))
                  .compareTo(DateTime.tryParse(a['date'] as String? ?? '') ?? DateTime(0)));
              final net = personRows.fold<double>(0, (s,r) => s + _delta(r));
              return Card(
                child: ListTile(
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('Entries: ${personRows.length} · Tap for full details'),
                  trailing: Text('${net >= 0 ? '+' : '−'}${money.format(net.abs())}',
                    style: TextStyle(fontWeight: FontWeight.w800, color: net >= 0 ? Colors.green : Colors.red)),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => _PersonMonthDetailScreen(name: name, rows: personRows),
                  )),
                ),
              );
            }).toList()),
    );
  }
}


class _MonthPaniScreen extends StatelessWidget {
  const _MonthPaniScreen({required this.rows, required this.storage, required this.monthTitle});
  final List<Map<String, dynamic>> rows;
  final StorageBackupService storage;
  final String monthTitle;

  int _num(Map<String, dynamic> row, String key) {
    final v = row[key];
    return v is num ? v.toInt() : int.tryParse('$v') ?? 0;
  }
  int _minutes(Map<String, dynamic> row) => _num(row, 'minutes');
  int _own(Map<String, dynamic> row) {
    if (row['ownMinutes'] is num) return _num(row, 'ownMinutes');
    final borrowed = _num(row, 'borrowedMinutes');
    if (borrowed > 0) return (_minutes(row) - borrowed).clamp(0, 999999);
    if ((row['direction'] ?? '').toString().toLowerCase().contains('liya')) return 0;
    return _minutes(row);
  }
  int _borrowedNahar(Map<String, dynamic> row) {
    if (row['borrowedNaharMinutes'] is num) return _num(row, 'borrowedNaharMinutes');
    final source = (row['borrowedSource'] ?? row['source'] ?? '').toString().toLowerCase();
    return source.contains('nahar') ? _num(row, 'borrowedMinutes') : 0;
  }
  int _borrowedKua(Map<String, dynamic> row) {
    if (row['borrowedKuaMinutes'] is num) return _num(row, 'borrowedKuaMinutes');
    final source = (row['borrowedSource'] ?? row['source'] ?? '').toString().toLowerCase();
    return source.contains('kua') || source.contains('ku') ? _num(row, 'borrowedMinutes') : 0;
  }
  String _fmt(int m) => '${m ~/ 60}h ${m % 60}m';
  void _open(BuildContext context, String title, List<Map<String,dynamic>> data, String kind) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _PaniCategoryDetail(title: title, rows: data, storage: storage, kind: kind),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final ownRows = rows.where((r) => _own(r) > 0).toList();
    final naharRows = rows.where((r) => _borrowedNahar(r) > 0).toList();
    final kuaRows = rows.where((r) => _borrowedKua(r) > 0).toList();
    final ownTotal = ownRows.fold<int>(0, (s,r)=>s+_own(r));
    final naharTotal = naharRows.fold<int>(0, (s,r)=>s+_borrowedNahar(r));
    final kuaTotal = kuaRows.fold<int>(0, (s,r)=>s+_borrowedKua(r));
    final borrowedTotal = naharTotal+kuaTotal;
    return Scaffold(
      appBar: AppBar(title: Text('$monthTitle · Pani total')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('PANI TOTAL', style: TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
        Card(child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.water_drop)),
          title: const Text('Apna pani'),
          subtitle: const Text('Apni baari + apne kua ka apni zameen par laga pani'),
          trailing: Text(_fmt(ownTotal),style: const TextStyle(fontWeight:FontWeight.bold,color:Colors.blue)),
          onTap: ()=>_open(context,'Apna pani',ownRows,'own'),
        )),
        Card(child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.water_drop_outlined)),
          title: const Text('Liya pani · Total'),
          subtitle: Text('Nahar ${_fmt(naharTotal)}  •  Kua ${_fmt(kuaTotal) }'),
          trailing: Text(_fmt(borrowedTotal),style: const TextStyle(fontWeight:FontWeight.bold,color:Colors.orange)),
        )),
        Card(child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.water)),
          title: const Text('Nahar se liya pani'),
          subtitle: Text('${naharRows.length} records · Tap for details'),
          trailing: Text(_fmt(naharTotal),style: const TextStyle(fontWeight:FontWeight.bold,color:Colors.blue)),
          onTap: ()=>_open(context,'Nahar se liya pani',naharRows,'nahar'),
        )),
        Card(child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.water)),
          title: const Text('Kua se liya pani'),
          subtitle: Text('${kuaRows.length} records · Tap for details'),
          trailing: Text(_fmt(kuaTotal),style: const TextStyle(fontWeight:FontWeight.bold,color:Colors.blue)),
          onTap: ()=>_open(context,'Kua se liya pani',kuaRows,'kua'),
        )),
      ]),
    );
  }
}

class _PaniCategoryDetail extends StatelessWidget {
  const _PaniCategoryDetail({required this.title, required this.rows, required this.storage, required this.kind});
  final String title;
  final List<Map<String,dynamic>> rows;
  final StorageBackupService storage;
  final String kind;

  int _n(Map<String,dynamic> r,String k) {final v=r[k];return v is num?v.toInt():int.tryParse('$v')??0;}
  int _amount(Map<String,dynamic> r) {
    if(kind=='own') return r['ownMinutes'] is num ? _n(r,'ownMinutes') : (_n(r,'minutes')-_n(r,'borrowedMinutes')).clamp(0,999999);
    if(kind=='nahar') return r['borrowedNaharMinutes'] is num ? _n(r,'borrowedNaharMinutes') : ((r['borrowedSource']??r['source']??'').toString().toLowerCase().contains('nahar') ? _n(r,'borrowedMinutes'):0);
    return r['borrowedKuaMinutes'] is num ? _n(r,'borrowedKuaMinutes') : ((r['borrowedSource']??r['source']??'').toString().toLowerCase().contains('kua') ? _n(r,'borrowedMinutes'):0);
  }
  String _fmt(int m)=>'${m~/60}h ${m%60}m';
  @override Widget build(BuildContext context) {
    final sorted=[...rows]..sort((a,b)=>(DateTime.tryParse(a['date']?.toString()??'')??DateTime(0)).compareTo(DateTime.tryParse(b['date']?.toString()??'')??DateTime(0)));
    final total=sorted.fold<int>(0,(s,r)=>s+_amount(r));
    return Scaffold(appBar:AppBar(title:Text(title)),body:ListView(padding:const EdgeInsets.all(16),children:[
      Card(child:ListTile(title:const Text('TOTAL'),trailing:Text(_fmt(total),style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)))),
      if(sorted.isEmpty) const Padding(padding:EdgeInsets.all(20),child:Text('Koi record nahi mila.')),
      ...sorted.map((r){
        final date=DateTime.tryParse(r['date']?.toString()??'');
        final plot=r['plotId']==null?'Khet':plotLabelForId(storage,r['plotId']);
        final contact=(r['borrowedContact']??r['contact']??'').toString();
        final source=(kind=='own'?(r['source']??r['wellType']??'Apna pani'):(kind=='nahar'?'Nahar':'Kua')).toString();
        return Card(child:ListTile(
          title:Text('$plot · $source'),
          subtitle:Text('${date==null?'':DateFormat('dd MMM yyyy').format(date)}${contact.isEmpty?'':'\nKis se: $contact'}${(r['note']??'').toString().isEmpty?'':'\n${r['note']}'}'),
          trailing:Text(_fmt(_amount(r)),style:const TextStyle(fontWeight:FontWeight.bold,color:Colors.blue)),
        ));
      }),
    ]));
  }
}

class _PersonMonthDetailScreen extends StatelessWidget {
  const _PersonMonthDetailScreen({required this.name, required this.rows});
  final String name;
  final List<Map<String, dynamic>> rows;

  double _amount(dynamic value) => value is num ? value.toDouble() :
      double.tryParse((value ?? '').toString().replaceAll(',', '').replaceAll('₹', '').trim()) ?? 0;
  @override
  Widget build(BuildContext context) {
    final sorted = [...rows]..sort((a,b) =>
      (DateTime.tryParse(a['date'] as String? ?? '') ?? DateTime(0))
        .compareTo(DateTime.tryParse(b['date'] as String? ?? '') ?? DateTime(0)));
    final given = sorted.where((r) => r['direction'] == 'PAID').fold<double>(0, (s,r)=>s+_amount(r['amount']));
    final taken = sorted.where((r) => r['direction'] != 'PAID').fold<double>(0, (s,r)=>s+_amount(r['amount']));
    final net = taken-given;
    final money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    return Scaffold(
      appBar: AppBar(title: Text(name, overflow: TextOverflow.ellipsis)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('NET BALANCE', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('${net >= 0 ? '+' : '−'}${money.format(net.abs())}', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: net >= 0 ? Colors.green : Colors.red)),
          const SizedBox(height: 8),
          Text('Paise liye: ${money.format(taken)}   ·   Paise diye: ${money.format(given)}'),
        ]))),
        const SizedBox(height: 10),
        const Text('Transaction history', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        ...sorted.map((row) {
          final paid = row['direction'] == 'PAID';
          final date = DateTime.tryParse(row['date'] as String? ?? '');
          final amount = _amount(row['amount']);
          return Card(child: ListTile(
            leading: Icon(paid ? Icons.arrow_upward : Icons.arrow_downward, color: paid ? Colors.red : Colors.green),
            title: Text(paid ? 'Paise diye' : 'Paise liye'),
            subtitle: Text('${date == null ? 'Date unavailable' : DateFormat('dd MMM yyyy · hh:mm a').format(date)}${(row['note'] ?? '').toString().trim().isEmpty ? '' : '\n${row['note']}'}'),
            trailing: Text('${paid ? '−' : '+'}${money.format(amount)}', style: TextStyle(fontWeight: FontWeight.w800, color: paid ? Colors.red : Colors.green)),
          ));
        }),
      ]),
    );
  }
}

class _KhetExpensesScreen extends StatefulWidget {
 const _KhetExpensesScreen({required this.rows, required this.money, this.initialMonth});
 final List<Map<String,dynamic>> rows;
 final NumberFormat money;
 final String? initialMonth;
 @override State<_KhetExpensesScreen> createState()=>_KhetExpensesScreenState();
}
class _KhetExpensesScreenState extends State<_KhetExpensesScreen>{
 String? _selectedMonth;
 String _monthKey(DateTime d)=>'${d.year}-${d.month.toString().padLeft(2,'0')}';
 @override Widget build(BuildContext context){
  final expenses=widget.rows.where((r)=>r['type']!='PANI'&&r['type']!='TRACTOR').toList();
  double amount(dynamic v)=>v is num?v.toDouble():double.tryParse(v?.toString()??'')??0;
  final monthKeys=expenses.map((r)=>DateTime.tryParse(r['date']?.toString()??'')).whereType<DateTime>().map(_monthKey).toSet().toList()..sort((a,b)=>b.compareTo(a));
  if(_selectedMonth==null && monthKeys.isNotEmpty)_selectedMonth=widget.initialMonth ?? monthKeys.first;
  if(_selectedMonth!=null && !monthKeys.contains(_selectedMonth))_selectedMonth=monthKeys.isNotEmpty?monthKeys.first:null;
  final selected=_selectedMonth;
  final monthly=expenses.where((r){final d=DateTime.tryParse(r['date']?.toString()??'');return d!=null && _monthKey(d)==selected;}).toList()..sort((a,b)=>(DateTime.tryParse(b['date']?.toString()??'')??DateTime(0)).compareTo(DateTime.tryParse(a['date']?.toString()??'')??DateTime(0)));
  final total=monthly.fold<double>(0,(s,r)=>s+amount(r['price']));
  return Scaffold(appBar:AppBar(title:const Text('All Khet Expenses')),body:ListView(padding:const EdgeInsets.all(16),children:[
    if (monthKeys.isNotEmpty)
      Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: selected,
              hint: const Text('Month choose karein'),
              items: monthKeys.map((key) {
                final parts = key.split('-');
                final date = DateTime(int.parse(parts[0]), int.parse(parts[1]));
                return DropdownMenuItem(value: key, child: Text(DateFormat('MMMM yyyy').format(date)));
              }).toList(),
              onChanged: (v) => setState(() => _selectedMonth = v),
            ),
          ),
        ),
      ),
    Card(
      child: ListTile(
        title: Text('${selected == null ? 'All months' : DateFormat('MMMM yyyy').format(DateTime(int.parse(selected.split('-')[0]), int.parse(selected.split('-')[1])))} · ${monthly.length} expense records'),
        trailing: Text(widget.money.format(total), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      ),
    ),
    if (monthly.isEmpty)
      const Center(child: Padding(padding: EdgeInsets.all(30), child: Text('Is month ka koi expense record nahi hai.'))),
    ...monthly.map((r) {
      final d = DateTime.tryParse(r['date']?.toString() ?? '');
      return Card(
        child: ListTile(
          title: Text(r['type']?.toString() ?? 'Expense'),
          subtitle: Text('${r['description'] ?? r['name'] ?? ''}${d == null ? '' : '\n' + DateFormat('dd MMM yyyy').format(d)}'),
          trailing: Text(widget.money.format(amount(r['price']))),
        ),
      );
    }),
  ]));
 }
}
class _PendingPaymentsScreen extends StatefulWidget {
  const _PendingPaymentsScreen({
    required this.rows,
    required this.waterRows,
    required this.money,
    required this.storage,
    required this.monthTitle,
  });

  final List<Map<String, dynamic>> rows;
  final List<Map<String, dynamic>> waterRows;
  final NumberFormat money;
  final StorageBackupService storage;
  final String monthTitle;

  @override
  State<_PendingPaymentsScreen> createState() => _PendingPaymentsScreenState();
}

class _PendingPaymentsScreenState extends State<_PendingPaymentsScreen> {
  double _amount(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(
          (value ?? '').toString().replaceAll(',', '').replaceAll('₹', ''),
        ) ??
        0;
  }

  double _balance(Map<String, dynamic> row) {
    final explicit = row['balance'];
    if (explicit is num) return explicit.toDouble();
    return (_amount(row['totalAmount'] ?? row['price']) -
            _amount(row['paidAmount']))
        .clamp(0, double.infinity)
        .toDouble();
  }

  Future<void> _updateWaterStatus(Map<String,dynamic> row) async {
    final noteController = TextEditingController(text: (row['waterPaymentNote'] ?? '').toString());
    String status = (row['waterPaymentStatus'] ?? 'PENDING').toString();
    final saved = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) => AlertDialog(
      title: Text('Pani pending · ${row['borrowedContact'] ?? row['contact'] ?? 'Person'}'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(value: status, items: const [
          DropdownMenuItem(value: 'PENDING', child: Text('Pending')),
          DropdownMenuItem(value: 'PAID', child: Text('Payment mil gaya')),
          DropdownMenuItem(value: 'WATER_EXCHANGE', child: Text('Badle mein pani liya')),
        ], onChanged: (v) => setDialog(() { status = v ?? 'PENDING'; })),
        TextField(controller: noteController, decoration: const InputDecoration(labelText: 'Note')),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save'))],
    )));
    if (saved != true) { noteController.dispose(); return; }
    final updated = Map<String,dynamic>.from(row)
      ..['waterPaymentStatus'] = status
      ..['waterPaymentPending'] = status == 'PENDING'
      ..['waterPaymentNote'] = noteController.text.trim();
    await widget.storage.updateRecord('khet', row['id'].toString(), updated);
    noteController.dispose();
    if (mounted) setState(() {});
  }

  Future<void> _addPlan() async {
    final titleController = TextEditingController();
    final noteController = TextEditingController();
    DateTime? scheduledAt;

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('Future Plan / Reminder'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'Kya karna hai?',
                    ),
                  ),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(
                      labelText: 'Details (optional)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final now = DateTime.now();
                      final date = await showDatePicker(
                        context: dialogContext,
                        initialDate: now.add(const Duration(days: 1)),
                        firstDate: DateTime(now.year, now.month, now.day),
                        lastDate: DateTime(now.year + 10),
                      );
                      if (date == null || !dialogContext.mounted) return;
                      final time = await showTimePicker(
                        context: dialogContext,
                        initialTime: const TimeOfDay(hour: 9, minute: 0),
                      );
                      if (time == null) return;
                      setDialogState(() {
                        scheduledAt = DateTime(
                          date.year,
                          date.month,
                          date.day,
                          time.hour,
                          time.minute,
                        );
                      });
                    },
                    icon: const Icon(Icons.alarm),
                    label: Text(
                      scheduledAt == null
                          ? 'Reminder date/time choose karein'
                          : DateFormat('dd MMM yyyy, hh:mm a')
                              .format(scheduledAt!),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (shouldSave != true) return;
    if (titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kaam ka naam likhein.')),
      );
      return;
    }
    if (scheduledAt == null || !scheduledAt!.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Future date aur time choose karein.')),
      );
      return;
    }

    final id = DateTime.now().millisecondsSinceEpoch;
    final notificationId = id % 2147483647;
    final record = <String, dynamic>{
      'id': 'plan-$id',
      'notificationId': notificationId,
      'title': titleController.text.trim(),
      'note': noteController.text.trim(),
      'date': scheduledAt!.toIso8601String(),
      'done': false,
      'createdAt': DateTime.now().toIso8601String(),
    };

    await widget.storage.addRecord('plans', record);
    try {
      await FarmReminderService.schedule(
        id: notificationId,
        scheduledAt: scheduledAt!,
        title: 'KHATA Reminder: ${record['title']}',
        body: record['note'] as String,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Plan save hua, lekin notification set nahi hui: $error',
            ),
          ),
        );
      }
    }
    titleController.dispose();
    noteController.dispose();
    if (mounted) setState(() {});
  }

  Future<void> _deletePlan(Map<String, dynamic> plan) async {
    final notificationId = plan['notificationId'];
    if (notificationId is num) {
      await FarmReminderService.cancel(notificationId.toInt());
    }
    if (plan['_source'] == 'khet-reminder') {
      final sourceId = plan['sourceRecordId']?.toString();
      final matches = widget.storage
          .records('khet')
          .where((row) => row['id']?.toString() == sourceId);
      if (matches.isNotEmpty) {
        final updated = Map<String, dynamic>.from(matches.first)
          ..['reminderDate'] = null
          ..['reminderId'] = null;
        await widget.storage.updateRecord('khet', sourceId!, updated);
      }
    } else {
      await widget.storage.deleteRecord('plans', plan['id'].toString());
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final plans = <Map<String, dynamic>>[
      ...widget.storage
          .records('plans')
          .where((plan) => plan['done'] != true),
      ...widget.storage.records('khet').where((row) {
        final reminderAt =
            DateTime.tryParse(row['reminderDate']?.toString() ?? '');
        return reminderAt != null && reminderAt.isAfter(now);
      }).map((row) => <String, dynamic>{
            'id': 'khet-reminder-${row['id']}',
            'sourceRecordId': row['id'],
            '_source': 'khet-reminder',
            'notificationId': row['reminderId'],
            'title': row['title'] ?? 'Farm reminder',
            'note': row['purpose'] ?? row['note'] ?? '',
            'date': row['reminderDate'],
          }),
    ]..sort((a, b) {
        final dateA =
            DateTime.tryParse(a['date']?.toString() ?? '') ?? DateTime(9999);
        final dateB =
            DateTime.tryParse(b['date']?.toString() ?? '') ?? DateTime(9999);
        return dateA.compareTo(dateB);
      });

    final pendingTotal = widget.rows.fold<double>(
      0,
      (sum, row) => sum + _balance(row),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Pending / Future Plans')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addPlan,
        icon: const Icon(Icons.add_alarm),
        label: const Text('Add Future Plan'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              title: const Text('Pending Tractor Payments'),
              subtitle: Text('${widget.rows.length} records'),
              trailing: Text(
                widget.money.format(pendingTotal),
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ),
          ...widget.rows.map((row) {
            final due =
                DateTime.tryParse(row['dueDate']?.toString() ?? '');
            return Card(
              child: ListTile(
                title: Text(
                  (row['customerName'] ?? row['contact'] ?? 'Customer')
                      .toString(),
                ),
                subtitle: Text(
                  '${row['work'] ?? row['title'] ?? 'Tractor work'}'
                  '${due == null ? '' : '\nDue: ${DateFormat('dd MMM yyyy').format(due)}'}',
                ),
                trailing: Text(
                  widget.money.format(_balance(row)),
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
          const Text('Pending Pani', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ...widget.waterRows.where((row) => row['waterPaymentPending'] == true).map((row) {
            final date = DateTime.tryParse(row['date']?.toString() ?? '');
            final mins = (row['borrowedMinutes'] as num?)?.toInt() ?? 0;
            final source = (row['borrowedSource'] ?? row['source'] ?? 'Pani').toString();
            return Card(child: ListTile(
              title: Text('${row['borrowedContact'] ?? row['contact'] ?? 'Person'} · $source'),
              subtitle: Text('$mins min · ${date == null ? '' : DateFormat('dd MMM yyyy').format(date)}\n${row['note'] ?? ''}'),
              trailing: const Icon(Icons.edit_note),
              onTap: () => _updateWaterStatus(row),
            ));
          }),
          const SizedBox(height: 16),
          const Text('Pending Work / Reminders', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          if (plans.isEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Koi plan nahi. Add Future Plan se banayein.'),
            ),
          ...plans.map((plan) {
            final date = DateTime.tryParse(plan['date']?.toString() ?? '');
            return Card(
              child: ListTile(
                leading: const Icon(
                  Icons.notifications_active,
                  color: Colors.orange,
                ),
                title: Text(plan['title']?.toString() ?? ''),
                subtitle: Text(
                  '${plan['note'] ?? ''}'
                  '${date == null ? '' : '\n${DateFormat('dd MMM yyyy, hh:mm a').format(date)}'}',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _deletePlan(plan),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
