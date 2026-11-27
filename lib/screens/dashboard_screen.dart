import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/storage_backup_service.dart';
import '../services/farm_reminder_service.dart';
import '../widgets/khet_map_widget.dart';
import '../widgets/plot_selector.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

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

  Widget _buildDashboard(BuildContext context, StorageBackupService storage) {
    final hisabs = storage.records('hisabs');
    final khet = storage.records('khet');
    final now = DateTime.now();
    bool thisMonth(Map<String, dynamic> row) {
      final date = _date(row);
      return date != null && date.year == now.year && date.month == now.month;
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
    final pending = khet.where((row) => row['type'] == 'TRACTOR' && _balance(row) > 0).toList()
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
        const KhetMapWidget(),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => _PendingPaymentsScreen(rows: pending, money: money, storage: storage),
            )),
            child: _MetricCard(title: 'Pending payments', value: money.format(pendingTotal), icon: Icons.pending_actions, tint: const Color(0xFFE5F2EC)),
          )),
          const SizedBox(width: 10),
          Expanded(child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => _MonthPersonLedgerScreen(rows: hisabs.where(thisMonth).toList()),
            )),
            child: _MetricCard(title: 'This month Hisab', value: money.format(monthHisabAmount), icon: Icons.receipt_long, tint: const Color(0xFFEAF0FA)),
          )),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: InkWell(onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => _KhetExpensesScreen(rows: khet, money: money))), child: _MetricCard(title: 'Khet expenses', value: money.format(monthKhetAmount), icon: Icons.agriculture, tint: const Color(0xFFF8EEDC)))),
          const SizedBox(width: 10),
          Expanded(child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => _MonthPaniScreen(rows: khet.where((row) => thisMonth(row) && row['type'] == 'PANI' && row['ledgerMode'] != 'PERSON').toList(), storage: storage),
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
  const _MonthPersonLedgerScreen({required this.rows});
  final List<Map<String, dynamic>> rows;

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
      appBar: AppBar(title: const Text('This month · Person Hisab')),
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
  const _MonthPaniScreen({required this.rows, required this.storage});

  final List<Map<String, dynamic>> rows;
  final StorageBackupService storage;

  int _minutes(Map<String, dynamic> row) {
    final value = row['minutes'];
    return value is num ? value.toInt() : int.tryParse('$value') ?? 0;
  }

  String _formatMinutes(int minutes) => '${minutes ~/ 60}h ${minutes % 60}m';

  String _person(Map<String, dynamic> row) {
    final borrowed = (row['borrowedMinutes'] as num?)?.toInt() ?? 0;
    if (borrowed > 0) {
      final borrowedName = (row['borrowedContact'] ?? row['contact'] ?? '').toString().trim();
      return borrowedName.isEmpty ? 'Dusre se liya pani' : borrowedName;
    }
    return 'Apni baari / apna pani';
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      groups.putIfAbsent(_person(row), () => []).add(row);
    }
    final names = groups.keys.toList()..sort();
    final totalMinutes = rows.fold<int>(0, (sum, row) => sum + _minutes(row));

    return Scaffold(
      appBar: AppBar(title: const Text('This month · Pani total')),
      body: rows.isEmpty
          ? const Center(child: Text('Is month pani entries nahi hain.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('MONTH TOTAL',
                            style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Text(_formatMinutes(totalMinutes),
                            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.blue)),
                        Text('${rows.length} entries · ${names.length} groups'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text('Person-wise pani',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                ...names.map((name) {
                  final personRows = groups[name]!
                    ..sort((a, b) =>
                        (DateTime.tryParse(b['date'] as String? ?? '') ?? DateTime(0))
                            .compareTo(DateTime.tryParse(a['date'] as String? ?? '') ?? DateTime(0)));
                  final personMinutes = personRows.fold<int>(0, (sum, row) => sum + _minutes(row));

                  return Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.water_drop)),
                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${personRows.length} entries · Tap for details'),
                      trailing: Text(_formatMinutes(personMinutes),
                          style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.blue)),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => _MonthPaniDetail(
                            name: name,
                            rows: personRows,
                            storage: storage,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }
}

class _MonthPaniDetail extends StatelessWidget {
  const _MonthPaniDetail({
    required this.name,
    required this.rows,
    required this.storage,
  });

  final String name;
  final List<Map<String, dynamic>> rows;
  final StorageBackupService storage;

  int _minutes(Map<String, dynamic> row) {
    final value = row['minutes'];
    return value is num ? value.toInt() : int.tryParse('$value') ?? 0;
  }

  String _formatMinutes(int minutes) => '${minutes ~/ 60}h ${minutes % 60}m';

  @override
  Widget build(BuildContext context) {
    final sortedRows = [...rows]
      ..sort((a, b) =>
          (DateTime.tryParse(a['date'] as String? ?? '') ?? DateTime(0))
              .compareTo(DateTime.tryParse(b['date'] as String? ?? '') ?? DateTime(0)));
    final totalMinutes = sortedRows.fold<int>(0, (sum, row) => sum + _minutes(row));

    return Scaffold(
      appBar: AppBar(title: Text(name, overflow: TextOverflow.ellipsis)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('TOTAL PANI',
                      style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 5),
                  Text(_formatMinutes(totalMinutes),
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.blue)),
                  Text('${sortedRows.length} entries'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Text('Pani history',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          ...sortedRows.map((row) {
            final date = DateTime.tryParse(row['date'] as String? ?? '');
            final plot = row['plotId'] == null
                ? 'Khet'
                : plotLabelForId(storage, row['plotId']);
            final direction = (row['direction'] ?? 'Apni baari').toString();
            final source = (row['source'] ?? '').toString();
            final minutes = _minutes(row);
            final borrowed = (row['borrowedMinutes'] as num?)?.toInt() ?? 0;
            final own = (row['ownMinutes'] as num?)?.toInt() ?? minutes;
            final season = [
              if (row['season'] != null) row['season'].toString(),
              if (row['year'] != null) row['year'].toString(),
            ].join(' ');

            return Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.water_drop)),
                title: Text('$plot · $direction'),
                subtitle: Text([
                  if (date != null) DateFormat('dd MMM yyyy').format(date),
                  _formatMinutes(minutes),
                  if (source.isNotEmpty) 'Source: $source',
                  if (borrowed > 0)
                    'Apna: ${_formatMinutes(own)} · Liya: ${_formatMinutes(borrowed)}',
                  if (season.isNotEmpty) 'Fasal/Year: $season',
                  if ((row['note'] ?? '').toString().trim().isNotEmpty) row['note'].toString(),
                ].join(' · ')),
                trailing: Text(_formatMinutes(minutes),
                    style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.blue)),
              ),
            );
          }),
        ],
      ),
    );
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

class _KhetExpensesScreen extends StatelessWidget {
 const _KhetExpensesScreen({required this.rows,required this.money});
 final List<Map<String,dynamic>> rows; final NumberFormat money;
 @override Widget build(BuildContext context){
  final expenses=rows.where((r)=>r['type']!='PANI'&&r['type']!='TRACTOR').toList();
  double amount(dynamic v)=>v is num?v.toDouble():double.tryParse(v?.toString()??'')??0;
  final total=expenses.fold<double>(0,(s,r)=>s+amount(r['price']));
  return Scaffold(appBar:AppBar(title:const Text('All Khet Expenses')),body:ListView(padding:const EdgeInsets.all(16),children:[
   Card(child:ListTile(title:Text('${expenses.length} expense records'),trailing:Text(money.format(total),style:const TextStyle(fontWeight:FontWeight.bold,fontSize:18)))),
   if(expenses.isEmpty)const Center(child:Padding(padding:EdgeInsets.all(30),child:Text('Koi expense record nahi hai.'))),
   ...expenses.map((r){final d=DateTime.tryParse(r['date']?.toString()??'');return Card(child:ListTile(title:Text(r['type']?.toString()??'Expense'),subtitle:Text('${r['description']??r['name']??''}${d==null?'':'\\n'+DateFormat('dd MMM yyyy').format(d)}'),trailing:Text(money.format(amount(r['price'])))));})
  ]));
 }
}
class _PendingPaymentsScreen extends StatefulWidget {
 const _PendingPaymentsScreen({required this.rows,required this.money,required this.storage});
 final List<Map<String,dynamic>> rows; final NumberFormat money; final StorageBackupService storage;
 @override State<_PendingPaymentsScreen> createState()=>_PendingPaymentsScreenState();
}
class _PendingPaymentsScreenState extends State<_PendingPaymentsScreen>{
 double amount(dynamic v)=>v is num?v.toDouble():double.tryParse((v??'').toString().replaceAll(',','').replaceAll('₹',''))??0;
 double balance(Map<String,dynamic> r){final b=r['balance'];if(b is num)return b.toDouble();return (amount(r['totalAmount']??r['price'])-amount(r['paidAmount'])).clamp(0,double.infinity).toDouble();}
 Future<void> addPlan() async{
  final title=TextEditingController(),note=TextEditingController();DateTime? when;
  final ok=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setD)=>AlertDialog(title:const Text('Future Plan / Reminder'),content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:title,decoration:const InputDecoration(labelText:'Kya karna hai?')),TextField(controller:note,decoration:const InputDecoration(labelText:'Details (optional)')),OutlinedButton.icon(onPressed:()async{final d=await showDatePicker(context:ctx,initialDate:DateTime.now().add(const Duration(days:1)),firstDate:DateTime.now(),lastDate:DateTime.now().add(const Duration(days:3650)));if(d==null)return;final t=await showTimePicker(context:ctx,initialTime:const TimeOfDay(hour:9,minute:0));if(t!=null)setD(()=>when=DateTime(d.year,d.month,d.day,t.hour,t.minute));},icon:const Icon(Icons.alarm),label:Text(when==null?'Date/time choose karein':DateFormat('dd MMM yyyy, hh:mm a').format(when!)))]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Save'))]));
  if(ok!=true||title.text.trim().isEmpty||when==null||!when!.isAfter(DateTime.now()))return;
  final id=DateTime.now().millisecondsSinceEpoch;final rec={'id':'plan-$id','notificationId':id%2147483647,'title':title.text.trim(),'note':note.text.trim(),'date':when!.toIso8601String(),'done':false,'createdAt':DateTime.now().toIso8601String()};
  await widget.storage.addRecord('plans',rec);try{await FarmReminderService.schedule(id:rec['notificationId'] as int,scheduledAt:when!,title:'KHATA Reminder: ${rec['title']}',body:rec['note'] as String);}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Plan save hua, notification permission/check karein: $e')));}if(mounted)setState((){});
 }
 Future<void> deletePlan(Map<String,dynamic> p)async{await FarmReminderService.cancel(p['notificationId'] as int? ?? 0);await widget.storage.deleteRecord('plans',p['id'].toString());setState((){});}
 @override Widget build(BuildContext context){final plans=widget.storage.records('plans').where((p)=>p['done']!=true).toList()..sort((a,b)=>(DateTime.tryParse(a['date']?.toString()??'')??DateTime(9999)).compareTo(DateTime.tryParse(b['date']?.toString()??'')??DateTime(9999)));final total=widget.rows.fold<double>(0,(s,r)=>s+balance(r));
 return Scaffold(appBar:AppBar(title:const Text('Pending / Future Plans')),floatingActionButton:FloatingActionButton.extended(onPressed:addPlan,icon:const Icon(Icons.add_alarm),label:const Text('Add Future Plan')),body:ListView(padding:const EdgeInsets.all(16),children:[Card(child:ListTile(title:const Text('Pending Tractor Payments'),subtitle:Text('${widget.rows.length} records'),trailing:Text(widget.money.format(total),style:const TextStyle(color:Colors.red,fontWeight:FontWeight.bold,fontSize:18)))),...widget.rows.map((r){final due=DateTime.tryParse(r['dueDate']?.toString()??'');return Card(child:ListTile(title:Text((r['customerName']??r['contact']??'Customer').toString()),subtitle:Text('${r['work']??r['title']??'Tractor work'}${due==null?'':'\\nDue: '+DateFormat('dd MMM yyyy').format(due)}'),trailing:Text(widget.money.format(balance(r)),style:const TextStyle(color:Colors.red,fontWeight:FontWeight.bold))));}),const SizedBox(height:16),const Text('Future Plans & Reminders',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),if(plans.isEmpty)const Padding(padding:EdgeInsets.all(12),child:Text('Koi plan nahi. Add Future Plan se banayein.')),...plans.map((p){final d=DateTime.tryParse(p['date']?.toString()??'');return Card(child:ListTile(leading:const Icon(Icons.notifications_active,color:Colors.orange),title:Text(p['title']?.toString()??''),subtitle:Text('${p['note']??''}${d==null?'':'\\n'+DateFormat('dd MMM yyyy, hh:mm a').format(d)}'),trailing:IconButton(icon:const Icon(Icons.delete_outline),onPressed:()=>deletePlan(p))));})]));}
}
