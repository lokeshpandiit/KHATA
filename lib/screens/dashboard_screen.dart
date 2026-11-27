import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/storage_backup_service.dart';
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
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 0);
    bool thisMonth(Map<String, dynamic> row) {
      final date = _date(row);
      return date != null && date.year == now.year && date.month == now.month;
    }
    bool today(Map<String, dynamic> row) {
      final date = _date(row);
      return date != null && date.year == now.year && date.month == now.month && date.day == now.day;
    }

    final monthHisabAmount = hisabs.where(thisMonth).fold<double>(
      0, (sum, row) => sum + _amount(row['amount']),
    );
    final monthKhetAmount = khet.where(thisMonth)
        .where((row) => row['type'] != 'PANI' && row['type'] != 'TRACTOR')
        .fold<double>(0, (sum, row) => sum + _amount(row['price']));
    final monthTractorAmount = khet.where((row) => thisMonth(row) && row['type'] == 'TRACTOR')
        .fold<double>(0, (sum, row) => sum + _amount(row['totalAmount'] ?? row['price']));
    final monthPani = khet.where(thisMonth)
        .where((row) => row['type'] == 'PANI' && row['ledgerMode'] != 'PERSON')
        .fold<int>(0, (sum, row) => sum + ((row['minutes'] as num?)?.toInt() ?? int.tryParse('${row['minutes']}') ?? 0));
    final todayCount = hisabs.where(today).length + khet.where(today).length;
    final pending = khet.where((row) => row['type'] == 'TRACTOR' && _balance(row) > 0).toList()
      ..sort((a, b) => (DateTime.tryParse(a['dueDate'] as String? ?? '') ?? DateTime(9999))
          .compareTo(DateTime.tryParse(b['dueDate'] as String? ?? '') ?? DateTime(9999)));
    final pendingTotal = pending.fold<double>(0, (sum, row) => sum + _balance(row));
    final recent = <_Recent>[];
    for (final row in hisabs) {
      recent.add(_Recent('HISAB', (row['title'] ?? row['category'] ?? 'Hisab').toString(),
        _amount(row['amount']), _date(row), row['direction'] as String?));
    }
    for (final row in khet) {
      final type = row['type'] == 'PANI' ? 'PANI' : (row['type'] == 'TRACTOR' ? 'TRACTOR' : 'KHET');
      recent.add(_Recent(
        type,
        row['type'] == 'PANI'
            ? 'Pani · ${row['plotId'] == null ? 'Khet' : plotLabelForId(storage, row['plotId'])}'
            : (row['title'] ?? row['contact'] ?? row['customerName'] ?? row['type'] ?? 'Khet').toString(),
        _amount(row['price'] ?? row['totalAmount']),
        _date(row),
        null,
        row['type'] == 'PANI'
            ? [
                if ((row['direction'] ?? '').toString().isNotEmpty) 'Len-den: ${row['direction']}',
                if ((row['wellType'] ?? '').toString().isNotEmpty) 'Kua: ${row['wellType']}',
                if ((row['source'] ?? '').toString().isNotEmpty) 'Source: ${row['source']}',
                if (row['contact'] != null) 'Contact: ${row['contact']}',
                if ((row['minutes'] as num?)?.toInt() != null) 'Time: ${row['minutes']} min',
                if (row['wetKyaris'] != null) 'Kyari: ${row['wetKyaris']} bheegi',
                if (row['season'] != null || row['year'] != null) 'Season: ${row['season'] ?? ''} ${row['year'] ?? ''}',
              ].join(' · ')
            : null,
      ));
    }
    recent.sort((a, b) => (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)));
    final money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final range = '${DateFormat('dd MMM yyyy').format(monthStart)} – ${DateFormat('dd MMM yyyy').format(monthEnd)}';

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
          Expanded(child: _MetricCard(title: 'Today records', value: todayCount.toString(), icon: Icons.today, tint: const Color(0xFFE5F2EC))),
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
          Expanded(child: _MetricCard(title: 'Khet expenses', value: money.format(monthKhetAmount), icon: Icons.agriculture, tint: const Color(0xFFF8EEDC))),
          const SizedBox(width: 10),
          Expanded(child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => _MonthPaniScreen(rows: khet.where((row) => thisMonth(row) && row['type'] == 'PANI' && row['ledgerMode'] != 'PERSON').toList(), storage: storage),
            )),
            child: _MetricCard(title: 'Pani total', value: '${monthPani ~/ 60}h ${monthPani % 60}m', icon: Icons.water_drop, tint: const Color(0xFFE7F3FA)),
          )),
        ]),
        const SizedBox(height: 22),
        const Text('This month at a glance', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 3),
        Text(range, style: const TextStyle(color: Colors.black54, fontSize: 12)),
        const SizedBox(height: 8),
        Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
          _SummaryLine(label: 'Hisab records', value: hisabs.where(thisMonth).length.toString()),
          const Divider(height: 18),
          _SummaryLine(label: 'Khet records', value: khet.where(thisMonth).where((r) => r['type'] != 'PANI').length.toString()),
          const Divider(height: 18),
          _SummaryLine(label: 'Pani entries', value: khet.where(thisMonth).where((r) => r['type'] == 'PANI' && r['ledgerMode'] != 'PERSON').length.toString()),
          const Divider(height: 18),
          _SummaryLine(label: 'Tractor work amount', value: money.format(monthTractorAmount)),
          const Divider(height: 18),
          _SummaryLine(label: 'Combined entries amount', value: money.format(monthHisabAmount + monthKhetAmount + monthTractorAmount), bold: true),
        ]))),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Pending tractor payments', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            Text(money.format(pendingTotal), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 8),
        if (pending.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(14), child: Text('No pending tractor payments.')))
        else
          ...pending.take(6).map((row) {
            final due = DateTime.tryParse(row['dueDate'] as String? ?? '');
            final isOverdue = due != null && due.isBefore(DateTime(now.year, now.month, now.day));
            return Card(
              margin: const EdgeInsets.only(bottom: 7),
              child: ListTile(
                leading: Icon(Icons.pending_actions, color: isOverdue ? Colors.red : Colors.orange),
                title: Text((row['customerName'] ?? row['contact'] ?? 'Customer').toString()),
                subtitle: Text('${row['work'] ?? row['title'] ?? 'Tractor work'}${due == null ? '' : ' · Due ${DateFormat('dd MMM yyyy').format(due)}'}'),
                trailing: Text(money.format(_balance(row)), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
              ),
            );
          }),
        const SizedBox(height: 18),
        const Text('Recent activity', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (recent.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No records yet. Add your first entry in HISAB or KHET.'))),
        ...recent.take(8).map((item) => Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(child: Icon(item.type == 'HISAB' ? Icons.receipt_long : item.type == 'PANI' ? Icons.water_drop : Icons.agriculture)),
            title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${item.type} · ${item.date == null ? 'Date unavailable' : DateFormat('dd MMM, hh:mm a').format(item.date!)}${item.details == null || item.details!.isEmpty ? '' : '\\n${item.details}'}'),
            trailing: item.amount > 0
                ? Text('${item.direction == 'PAID' ? '−' : '+'}${money.format(item.amount)}',
                    style: TextStyle(color: item.direction == 'PAID' ? Colors.red : Colors.green, fontWeight: FontWeight.w700))
                : null,
          ),
        )),
      ],
    );
  }

}

class _Recent {
  _Recent(this.type, this.title, this.amount, this.date, this.direction, [this.details]);
  final String type, title;
  final double amount;
  final DateTime? date;
  final String? direction;
  final String? details;
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

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.label, required this.value, this.bold = false});
  final String label, value;
  final bool bold;
  @override
  Widget build(BuildContext context) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
    Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.normal)),
    Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
  ]);
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
  int mins(Map<String, dynamic> r) => r['minutes'] is num ? (r['minutes'] as num).toInt() : int.tryParse('\${r['minutes']}') ?? 0;
  String fmt(int m) => '\${m ~/ 60}h \${m % 60}m';
  String person(Map<String, dynamic> r) => (r['contact'] ?? '').toString().trim().isEmpty ? 'Naam nahi diya' : r['contact'].toString();
  @override
  Widget build(BuildContext context) {
    final groups = <String,List<Map<String,dynamic>>>{};
    for(final r in rows){ groups.putIfAbsent(person(r),()=>[]).add(r); }
    final names=groups.keys.toList()..sort();
    final total=rows.fold<int>(0,(s,r)=>s+mins(r));
    return Scaffold(appBar: AppBar(title: const Text('This month · Pani total')),
      body: rows.isEmpty ? const Center(child: Text('Is month pani entries nahi hain.')) :
      ListView(padding: const EdgeInsets.all(16),children:[
        Card(child: Padding(padding: const EdgeInsets.all(16),child: Column(crossAxisAlignment: CrossAxisAlignment.start,children:[
          const Text('MONTH TOTAL',style: TextStyle(color: Colors.black54,fontWeight: FontWeight.w700)),
          const SizedBox(height: 6), Text(fmt(total),style: const TextStyle(fontSize:26,fontWeight:FontWeight.w900,color:Colors.blue)),
          Text('\${rows.length} entries · \${names.length} people'),
        ]))),
        const SizedBox(height:10), const Text('Person-wise pani',style:TextStyle(fontSize:17,fontWeight:FontWeight.w800)),
        ...names.map((n){final rs=groups[n]!..sort((a,b)=>(DateTime.tryParse(b['date'] as String? ?? '')??DateTime(0)).compareTo(DateTime.tryParse(a['date'] as String? ?? '')??DateTime(0))); final sum=rs.fold<int>(0,(s,r)=>s+mins(r));
          return Card(child:ListTile(leading:const CircleAvatar(child:Icon(Icons.water_drop)),title:Text(n,style:const TextStyle(fontWeight:FontWeight.w700)),subtitle:Text('\${rs.length} entries · Tap for details'),trailing:Text(fmt(sum),style:const TextStyle(fontWeight:FontWeight.w800,color:Colors.blue)),onTap:()=>Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>_MonthPaniDetail(name:n,rows:rs,storage:storage))));
        }),
      ]));
  }
}
class _MonthPaniDetail extends StatelessWidget {
  const _MonthPaniDetail({required this.name,required this.rows,required this.storage});
  final String name; final List<Map<String,dynamic>> rows; final StorageBackupService storage;
  int mins(Map<String,dynamic> r)=>r['minutes'] is num?(r['minutes'] as num).toInt():int.tryParse('\${r['minutes']}')??0;
  String fmt(int m)=>'\${m ~/ 60}h \${m % 60}m';
  @override
  Widget build(BuildContext context){
    final rs=[...rows]..sort((a,b)=>(DateTime.tryParse(a['date'] as String? ?? '')??DateTime(0)).compareTo(DateTime.tryParse(b['date'] as String? ?? '')??DateTime(0)));
    final total=rs.fold<int>(0,(s,r)=>s+mins(r));
    return Scaffold(appBar:AppBar(title:Text(name,overflow:TextOverflow.ellipsis)),body:ListView(padding:const EdgeInsets.all(16),children:[
      Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('TOTAL PANI',style:TextStyle(color:Colors.black54,fontWeight:FontWeight.w700)),const SizedBox(height:5),Text(fmt(total),style:const TextStyle(fontSize:26,fontWeight:FontWeight.w900,color:Colors.blue)),Text('\${rs.length} entries')]))),
      const SizedBox(height:10),const Text('Pani history',style:TextStyle(fontSize:17,fontWeight:FontWeight.w800)),
      ...rs.map((r){final date=DateTime.tryParse(r['date'] as String? ?? '');final plot=r['plotId']==null?'Khet':plotLabelForId(storage,r['plotId']);final direction=(r['direction']??'Apni baari').toString();final source=(r['source']??'').toString();final m=mins(r);final borrowed=r['borrowedMinutes'] is num?(r['borrowedMinutes'] as num).toInt():0;final own=r['ownMinutes'] is num?(r['ownMinutes'] as num).toInt():m;
        return Card(child:ListTile(leading:const CircleAvatar(child:Icon(Icons.water_drop)),title:Text('\${plot} · \${direction}'),subtitle:Text([if(date!=null)DateFormat('dd MMM yyyy').format(date),fmt(m),if(source.isNotEmpty)'Source: \${source}',if(borrowed>0)'Apna: \${fmt(own)} · Liya: \${fmt(borrowed)}',if((r['season']??r['year'])!=null)'Fasal/Year: \${r['season']??''} \${r['year']??''}',if((r['note']??'').toString().trim().isNotEmpty)r['note'].toString()].join(' · ')),trailing:Text(fmt(m),style:const TextStyle(fontWeight:FontWeight.w800,color:Colors.blue))));
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
