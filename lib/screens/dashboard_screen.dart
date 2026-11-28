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
    final dashboardBalance = row['dashboardBalance'];
    if (dashboardBalance is num) return dashboardBalance.toDouble();
    final explicit = row['balance'];
    if (explicit is num) return explicit.toDouble();
    final total = _amount(row['totalAmount'] ?? row['price']);
    final paid = _amount(row['paidAmount']);
    return (total - paid).clamp(0, double.infinity).toDouble();
  }

  bool _isKhetCostRecord(Map<String, dynamic> row) {
    final type = row['type'];
    if (const ['TRACTOR', 'KHET_PURCHASE', 'KHET_EXPENSE'].contains(type)) return true;
    return const ['DAWAI', 'KHAD', 'OTHER'].contains(type) && _amount(row['price']) > 0;
  }

  double _khetCostAmount(Map<String, dynamic> row) =>
      _amount(row['totalAmount'] ?? row['amount'] ?? row['price']);

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
    final allPersonLedgerRows = <Map<String, dynamic>>[
      ...hisabs.where((row) => (row['personName'] ?? '').toString().trim().isNotEmpty),
      ...khet.where((row) => const ['TRACTOR', 'KHET_PURCHASE', 'KHET_PURCHASE_PAYMENT'].contains(row['type']))
          .map((row) {
            final person = row['type'] == 'TRACTOR'
                ? (row['customerName'] ?? row['ownerName'] ?? row['contact'] ?? '').toString()
                : (row['vendorName'] ?? row['contact'] ?? '').toString();
            return <String, dynamic>{...row, 'personName': person, 'ledgerSource': 'KHET'};
          }).where((row) => (row['personName'] ?? '').toString().trim().isNotEmpty),
    ];
    final monthPersonRows = allPersonLedgerRows.where(thisMonth).toList();
    final activePersonCount = monthPersonRows
        .map((row) => (row['personName'] ?? '').toString().trim().toLowerCase())
        .where((name) => name.isNotEmpty).toSet().length;
    final monthPersonAmount = monthPersonRows.fold<double>(
      0,
      (sum, row) => sum + _amount(row['totalAmount'] ?? row['amount'] ?? row['price']),
    );
    final expenseRows = <Map<String, dynamic>>[
      ...khet.where(_isKhetCostRecord),
      ...hisabs.where((row) => row['category'] == 'Khet' && row['entryType'] == 'EXPENSE'),
    ];
    final monthExpenseRows = expenseRows.where(thisMonth).toList();
    final monthKhetAmount = monthExpenseRows.fold<double>(
      0, (sum, row) => sum + _khetCostAmount(row),
    );
    final monthPani = khet.where(thisMonth)
        .where((row) => row['type'] == 'PANI' && row['ledgerMode'] != 'PERSON')
        .fold<int>(0, (sum, row) => sum + ((row['minutes'] as num?)?.toInt() ?? 0));
    final tractorPending = khet.where((row) => row['type'] == 'TRACTOR' && _balance(row) > 0 && thisMonth(row)).toList();
    final vendorPurchases = khet.where((row) => row['type'] == 'KHET_PURCHASE' && thisMonth(row)).toList();
    final monthVendorTotal = vendorPurchases.fold<double>(0,(sum,row)=>sum+_amount(row['totalAmount']));
    final monthVendorPaid = vendorPurchases.fold<double>(0,(sum,row)=>sum+_amount(row['paidAmount']));
    final vendorIds = vendorPurchases.map((r)=>r['vendorId']).where((id)=>id!=null).toSet();
    final vendorPending = <Map<String,dynamic>>[];
    for(final vendorId in vendorIds){
      final purchases=khet.where((r)=>r['type']=='KHET_PURCHASE'&&r['vendorId']==vendorId).toList()
        ..sort((a,b)=>(a['invoiceDate']??a['date']??'').toString().compareTo((b['invoiceDate']??b['date']??'').toString()));
      var payments=khet.where((r)=>r['type']=='KHET_PURCHASE_PAYMENT'&&r['vendorId']==vendorId)
        .fold<double>(0,(sum,r)=>sum+_amount(r['amount']));
      for(final purchase in purchases){
        final base=(_amount(purchase['totalAmount'])-_amount(purchase['paidAmount'])).clamp(0,double.infinity).toDouble();
        final applied=payments<base?payments:base;
        payments-=applied;
        final balance=base-applied;
        if(balance>0&&thisMonth(purchase))vendorPending.add({...purchase,'dashboardBalance':balance,'pendingKind':'PURCHASE'});
      }
    }
    final khetExpensePending = <Map<String, dynamic>>[];
    final expensesByPerson = <String, List<Map<String, dynamic>>>{};
    for (final expense in hisabs.where((row) =>
        row['category'] == 'Khet' && row['entryType'] == 'EXPENSE')) {
      final person = (expense['personName'] ?? '').toString().trim().toLowerCase();
      if (person.isEmpty) continue;
      expensesByPerson.putIfAbsent(person, () => []).add(expense);
    }
    for (final entry in expensesByPerson.entries) {
      final personPayments = hisabs.where((row) =>
          (row['personName'] ?? '').toString().trim().toLowerCase() == entry.key &&
          row['direction'] == 'PAID' &&
          row['entryType'] != 'EXPENSE').fold<double>(
        0, (sum, row) => sum + _amount(row['amount']),
      );
      var availablePayments = personPayments;
      final expenses = entry.value
        ..sort((a, b) => (a['date'] ?? '').toString().compareTo((b['date'] ?? '').toString()));
      for (final expense in expenses) {
        final total = _amount(expense['totalAmount'] ?? expense['amount']);
        final initiallyPaid = _amount(expense['paidAmount']);
        final unpaid = (total - initiallyPaid).clamp(0, double.infinity).toDouble();
        final applied = availablePayments < unpaid ? availablePayments : unpaid;
        availablePayments -= applied;
        final remaining = unpaid - applied;
        if (remaining > 0.009 && thisMonth(expense)) {
          khetExpensePending.add({
            ...expense,
            'dashboardBalance': remaining,
            'pendingKind': 'KHET_EXPENSE',
          });
        }
      }
    }
    final pending=[...tractorPending,...vendorPending,...khetExpensePending]
      ..sort((a,b)=>(DateTime.tryParse(a['dueDate'] as String? ?? '')??DateTime(9999))
          .compareTo(DateTime.tryParse(b['dueDate'] as String? ?? '')??DateTime(9999)));
    final pendingTotal=pending.fold<double>(0,(sum,row)=>sum+_balance(row));
    final monthVendorPending = vendorPending.fold<double>(0,(sum,row)=>sum+_balance(row));
    final monthVendorLaterPayments = khet.where((row)=>row['type']=='KHET_PURCHASE_PAYMENT'&&thisMonth(row)).fold<double>(0,(sum,row)=>sum+_amount(row['amount']));
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
              builder: (_) => _MonthPersonLedgerScreen(
                rows: allPersonLedgerRows,
                monthTitle: DateFormat('MMMM yyyy').format(selectedDate),
                selectedMonth: _selectedMonth!,
              ),
            )),
            child: _MetricCard(title: 'Person-to-person', value: '${activePersonCount} people · ${money.format(monthPersonAmount)}', icon: Icons.people_alt_outlined, tint: const Color(0xFFEAF0FA)),
          )),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: InkWell(onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => _KhetExpensesScreen(rows: [...khet, ...hisabs], money: money, initialMonth: _selectedMonth))), child: _MetricCard(title: 'Khet expenses', value: money.format(monthKhetAmount), icon: Icons.agriculture, tint: const Color(0xFFF8EEDC)))),
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
        Card(child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.storefront_outlined)),
          title: Text('${DateFormat('MMMM yyyy').format(selectedDate)} · Dawai/Khaad purchases'),
          subtitle: Text('Bought ${money.format(monthVendorTotal)} · Paid ${money.format(monthVendorPaid+monthVendorLaterPayments)} · Pending ${money.format(monthVendorPending)}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _MonthVendorPurchasesScreen(rows: vendorPurchases, allRows: khet, monthTitle: DateFormat('MMMM yyyy').format(selectedDate), money: money))),
        )),
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
  const _MonthPersonLedgerScreen({
    required this.rows,
    required this.monthTitle,
    required this.selectedMonth,
  });

  final List<Map<String, dynamic>> rows;
  final String monthTitle;
  final String selectedMonth;

  double _amount(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse((value ?? '').toString().replaceAll(',', '').replaceAll('₹', '').trim()) ?? 0;

  String _person(Map<String, dynamic> row) {
    final name = (row['personName'] ?? row['vendorName'] ?? row['customerName'] ?? row['contact'] ?? '').toString().trim();
    return name.isEmpty ? 'Unknown person' : name;
  }

  DateTime? _date(Map<String, dynamic> row) => DateTime.tryParse((row['date'] ?? row['invoiceDate'] ?? '').toString());

  double _delta(Map<String, dynamic> row) {
    final type = row['type'];
    if (row['entryType'] == 'EXPENSE' || type == 'KHET_PURCHASE' || type == 'TRACTOR') {
      final total = _amount(row['totalAmount'] ?? row['amount'] ?? row['price']);
      return _amount(row['paidAmount']) - total;
    }
    if (type == 'KHET_PURCHASE_PAYMENT') return _amount(row['amount']);
    final amount = _amount(row['amount']);
    return row['direction'] == 'PAID' ? amount : -amount;
  }

  @override
  Widget build(BuildContext context) {
    final people = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final name = _person(row);
      if (name == 'Unknown person') continue;
      people.putIfAbsent(name, () => []).add(row);
    }
    final money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final sorted = people.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return Scaffold(
      appBar: AppBar(title: Text('$monthTitle · Person-to-person')),
      body: sorted.isEmpty
          ? const Center(child: Text('Abhi koi person-to-person record nahi hai.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: sorted.map((name) {
                final personRows = people[name]!;
                final currentMonthRows = personRows.where((row) {
                  final date = _date(row);
                  return date != null && '${date.year}-${date.month.toString().padLeft(2, '0')}' == selectedMonth;
                }).toList();
                final monthNet = currentMonthRows.fold<double>(0, (sum, row) => sum + _delta(row));
                final overallNet = personRows.fold<double>(0, (sum, row) => sum + _delta(row));
                final monthStatus = monthNet > 0.009
                    ? '₹${money.format(monthNet.abs())} लेना बाकी'
                    : monthNet < -0.009
                        ? '₹${money.format(monthNet.abs())} देना बाकी'
                        : 'इस महीने बराबर ₹0';
                final overallStatus = overallNet > 0.009
                    ? 'कुल ₹${money.format(overallNet.abs())} लेना बाकी'
                    : overallNet < -0.009
                        ? 'कुल ₹${money.format(overallNet.abs())} देना बाकी'
                        : 'कुल हिसाब बराबर';
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text('${currentMonthRows.length} entries this month · $overallStatus'),
                    trailing: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 145),
                      child: Text(
                        monthStatus,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: monthNet > 0.009 ? Colors.green : monthNet < -0.009 ? Colors.red : Colors.black54,
                        ),
                      ),
                    ),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => _PersonMonthDetailScreen(
                        name: name,
                        rows: personRows,
                        monthTitle: monthTitle,
                        selectedMonth: selectedMonth,
                      ),
                    )),
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class _PersonMonthDetailScreen extends StatelessWidget {
  const _PersonMonthDetailScreen({
    required this.name,
    required this.rows,
    required this.monthTitle,
    required this.selectedMonth,
  });

  final String name;
  final List<Map<String, dynamic>> rows;
  final String monthTitle;
  final String selectedMonth;

  double _amount(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse((value ?? '').toString().replaceAll(',', '').replaceAll('₹', '').trim()) ?? 0;

  double _delta(Map<String, dynamic> row) {
    final type = row['type'];
    if (row['entryType'] == 'EXPENSE' || type == 'KHET_PURCHASE' || type == 'TRACTOR') {
      return _amount(row['paidAmount']) - _amount(row['totalAmount'] ?? row['amount'] ?? row['price']);
    }
    if (type == 'KHET_PURCHASE_PAYMENT') return _amount(row['amount']);
    return row['direction'] == 'PAID' ? _amount(row['amount']) : -_amount(row['amount']);
  }

  String _title(Map<String, dynamic> row) {
    if (row['entryType'] == 'EXPENSE') return '${row['expenseCategory'] ?? 'Khet'} · ${row['title'] ?? 'Kharcha'}';
    if (row['type'] == 'KHET_PURCHASE') return 'खरीद · ${row['title'] ?? 'Samaan'}';
    if (row['type'] == 'KHET_PURCHASE_PAYMENT') return 'दुकानदार को भुगतान';
    if (row['type'] == 'TRACTOR') return 'ट्रैक्टर · ${row['work'] ?? row['title'] ?? 'काम'}';
    return row['direction'] == 'PAID' ? 'आपने पैसे दिए' : 'आपको पैसे मिले';
  }

  String _subtitle(Map<String, dynamic> row, NumberFormat money) {
    final date = DateTime.tryParse((row['date'] ?? row['invoiceDate'] ?? '').toString());
    final parts = <String>[
      if (date != null) DateFormat('dd MMM yyyy').format(date),
    ];
    if (row['entryType'] == 'EXPENSE' || row['type'] == 'KHET_PURCHASE' || row['type'] == 'TRACTOR') {
      final total = _amount(row['totalAmount'] ?? row['amount'] ?? row['price']);
      final paid = _amount(row['paidAmount']);
      parts.add('Total ${money.format(total)} · Paid ${money.format(paid)} · Pending ${money.format((total - paid).clamp(0, double.infinity))}');
      final plot = plotLabelForId(StorageBackupService.instance, row['plotId']);
      if (plot.isNotEmpty) parts.add(plot);
      final category = row['expenseCategory'] ?? row['purchaseCategory'];
      if (category != null && category.toString().isNotEmpty) parts.add(category.toString());
    } else if (row['type'] == 'KHET_PURCHASE_PAYMENT') {
      parts.add('Payment ${money.format(_amount(row['amount']))}');
    } else {
      parts.add('Amount ${money.format(_amount(row['amount']))}');
    }
    final note = (row['note'] ?? '').toString().trim();
    if (note.isNotEmpty) parts.add(note);
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...rows]..sort((a, b) =>
      (DateTime.tryParse((a['date'] ?? a['invoiceDate'] ?? '').toString()) ?? DateTime(0))
        .compareTo(DateTime.tryParse((b['date'] ?? b['invoiceDate'] ?? '').toString()) ?? DateTime(0)));
    final net = sorted.fold<double>(0, (sum, row) => sum + _delta(row));
    final currentMonthRows = sorted.where((row) {
      final date = DateTime.tryParse((row['date'] ?? row['invoiceDate'] ?? '').toString());
      return date != null && '${date.year}-${date.month.toString().padLeft(2, '0')}' == selectedMonth;
    }).toList();
    final monthNet = currentMonthRows.fold<double>(0, (sum, row) => sum + _delta(row));
    final expenseTotal = sorted.where((row) =>
      row['entryType'] == 'EXPENSE' || row['type'] == 'KHET_PURCHASE' || row['type'] == 'TRACTOR'
    ).fold<double>(0, (sum, row) => sum + _amount(row['totalAmount'] ?? row['amount'] ?? row['price']));
    final money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final status = net > 0.009
        ? '${money.format(net.abs())} लेना बाकी'
        : net < -0.009
            ? '${money.format(net.abs())} देना बाकी'
            : 'हिसाब बराबर ₹0';

    return Scaffold(
      appBar: AppBar(title: Text(name, overflow: TextOverflow.ellipsis)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('NET BALANCE', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text('Overall: $status', style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w900,
                color: net > 0.009 ? Colors.green : net < -0.009 ? Colors.red : Colors.black54,
              )),
              const SizedBox(height: 6),
              Text('$monthTitle net: ${monthNet > 0.009 ? '₹${money.format(monthNet)} लेना बाकी' : monthNet < -0.009 ? '₹${money.format(monthNet.abs())} देना बाकी' : '₹0 बराबर'}'),
              const SizedBox(height: 8),
              Text('Total purchases / expenses: ${money.format(expenseTotal)}'),
              Text('$monthTitle: ${currentMonthRows.length} transactions · All-time history: ${sorted.length}'),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        const Text('Transaction history', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        ...sorted.reversed.map((row) {
          final delta = _delta(row);
          final isCost = row['entryType'] == 'EXPENSE' || row['type'] == 'KHET_PURCHASE' || row['type'] == 'TRACTOR';
          return Card(child: ListTile(
            leading: Icon(
              isCost ? Icons.shopping_bag_outlined
                  : row['type'] == 'KHET_PURCHASE_PAYMENT' || row['direction'] == 'PAID'
                      ? Icons.payments_outlined
                      : Icons.call_received,
            ),
            title: Text(_title(row)),
            subtitle: Text(_subtitle(row, money)),
            trailing: Text(
              delta.abs() < 0.009 ? '₹0' : '${delta > 0 ? '+' : '−'}${money.format(delta.abs())}',
              style: TextStyle(fontWeight: FontWeight.w800, color: delta > 0 ? Colors.green : delta < 0 ? Colors.red : Colors.black54),
            ),
          ));
        }),
      ]),
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

class _KhetExpensesScreen extends StatefulWidget {
  const _KhetExpensesScreen({required this.rows, required this.money, this.initialMonth});
  final List<Map<String, dynamic>> rows;
  final NumberFormat money;
  final String? initialMonth;

  @override
  State<_KhetExpensesScreen> createState() => _KhetExpensesScreenState();
}

class _KhetExpensesScreenState extends State<_KhetExpensesScreen> {
  String? _selectedMonth;

  String _monthKey(DateTime date) => '${date.year}-${date.month.toString().padLeft(2, '0')}';

  double _amount(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse((value ?? '').toString().replaceAll(',', '').replaceAll('₹', '').trim()) ?? 0;

  bool _isExpense(Map<String, dynamic> row) {
    if (row['category'] == 'Khet' && row['entryType'] == 'EXPENSE') return true;
    if (const ['TRACTOR', 'KHET_PURCHASE', 'KHET_EXPENSE'].contains(row['type'])) return true;
    return const ['DAWAI', 'KHAD', 'OTHER'].contains(row['type']) && _amount(row['price']) > 0;
  }

  double _total(Map<String, dynamic> row) =>
      _amount(row['totalAmount'] ?? row['amount'] ?? row['price']);

  String _category(Map<String, dynamic> row) {
    if (row['expenseCategory'] != null) {
      final category = row['expenseCategory'].toString();
      final work = (row['workType'] ?? '').toString().trim();
      return category == 'Tractor' && work.isNotEmpty ? 'Tractor · $work' : category;
    }
    if (row['purchaseCategory'] != null) return row['purchaseCategory'].toString();
    if (row['type'] == 'TRACTOR') return 'Tractor';
    if (row['type'] == 'DAWAI') return 'Dawai';
    if (row['type'] == 'KHAD') return 'Khaad';
    return 'Other';
  }

  String _personKey(Map<String, dynamic> row) {
    return (row['personName'] ?? row['vendorName'] ?? row['customerName'] ?? row['contact'] ?? '')
        .toString().trim().toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final expenses = widget.rows.where(_isExpense).toList();
    final monthKeys = expenses
        .map((row) => DateTime.tryParse((row['date'] ?? row['invoiceDate'] ?? '').toString()))
        .whereType<DateTime>()
        .map(_monthKey)
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    if (_selectedMonth == null && monthKeys.isNotEmpty) {
      _selectedMonth = widget.initialMonth ?? monthKeys.first;
    }
    if (_selectedMonth != null && !monthKeys.contains(_selectedMonth)) {
      _selectedMonth = monthKeys.isNotEmpty ? monthKeys.first : null;
    }

    final selected = _selectedMonth;
    final monthly = expenses.where((row) {
      final date = DateTime.tryParse((row['date'] ?? row['invoiceDate'] ?? '').toString());
      return date != null && _monthKey(date) == selected;
    }).toList()
      ..sort((a, b) => (DateTime.tryParse((b['date'] ?? b['invoiceDate'] ?? '').toString()) ?? DateTime(0))
          .compareTo(DateTime.tryParse((a['date'] ?? a['invoiceDate'] ?? '').toString()) ?? DateTime(0)));
    final total = monthly.fold<double>(0, (sum, row) => sum + _total(row));
    final sortedCategories = <String, double>{};
    for (final row in monthly) {
      final category = _category(row);
      sortedCategories[category] = (sortedCategories[category] ?? 0) + _total(row);
    }
    final categoryEntries = sortedCategories.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Apply later person payments to the oldest unpaid expense first.
    final paymentsByPerson = <String, double>{};
    for (final row in widget.rows) {
      final isVendorPayment = row['type'] == 'KHET_PURCHASE_PAYMENT';
      final isPersonPayment = row['category'] == 'Khet' &&
          row['direction'] == 'PAID' && row['entryType'] != 'EXPENSE';
      if (!isVendorPayment && !isPersonPayment) continue;
      final key = _personKey(row);
      if (key.isEmpty) continue;
      paymentsByPerson[key] = (paymentsByPerson[key] ?? 0) +
          _amount(isVendorPayment ? row['amount'] : row['amount']);
    }
    final orderedExpenses = [...expenses]
      ..sort((a, b) => (a['date'] ?? a['invoiceDate'] ?? '').toString()
          .compareTo((b['date'] ?? b['invoiceDate'] ?? '').toString()));
    final remainingById = <String, double>{};
    for (final expense in orderedExpenses) {
      final id = (expense['id'] ?? '').toString();
      final key = _personKey(expense);
      final basePending = (_total(expense) - _amount(expense['paidAmount']))
          .clamp(0, double.infinity).toDouble();
      final available = key.isEmpty ? 0.0 : (paymentsByPerson[key] ?? 0.0);
      final applied = available < basePending ? available : basePending;
      if (key.isNotEmpty) paymentsByPerson[key] = available - applied;
      remainingById[id] = basePending - applied;
    }
    final pending = monthly.fold<double>(0, (sum, row) =>
        sum + (remainingById[(row['id'] ?? '').toString()] ?? 0));

    return Scaffold(
      appBar: AppBar(title: const Text('All Khet Expenses')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
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
                  onChanged: (value) => setState(() => _selectedMonth = value),
                ),
              ),
            ),
          ),
        Card(
          child: ListTile(
            title: Text('${selected == null ? 'All months' : DateFormat('MMMM yyyy').format(DateTime(int.parse(selected.split('-')[0]), int.parse(selected.split('-')[1])))} · ${monthly.length} expense records'),
            subtitle: Text('Total expense ${widget.money.format(total)} · Pending ${widget.money.format(pending)}'),
            trailing: const Icon(Icons.account_balance_wallet_outlined),
          ),
        ),
        if (categoryEntries.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Category-wise expenses', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                ...categoryEntries.map((entry) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(entry.key),
                    Text(widget.money.format(entry.value), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ]),
                )),
              ]),
            ),
          ),
        if (monthly.isEmpty)
          const Center(child: Padding(
            padding: EdgeInsets.all(30),
            child: Text('Is month ka koi expense record nahi hai.'),
          )),
        ...monthly.map((row) {
          final date = DateTime.tryParse((row['date'] ?? row['invoiceDate'] ?? '').toString());
          final amount = _total(row);
          final paid = _amount(row['paidAmount']);
          final person = (row['personName'] ?? row['vendorName'] ?? row['customerName'] ?? row['contact'] ?? '').toString().trim();
          final plot = plotLabelForId(StorageBackupService.instance, row['plotId']);
          final title = (row['title'] ?? row['work'] ?? row['workType'] ?? _category(row)).toString();
          final details = <String>[
            if (date != null) DateFormat('dd MMM yyyy').format(date),
            if (person.isNotEmpty) 'Person: $person',
            if (plot.isNotEmpty) plot,
            'Paid ${widget.money.format(paid)}',
            'Pending ${widget.money.format(remainingById[(row['id'] ?? '').toString()] ?? (amount - paid).clamp(0, double.infinity).toDouble())}',
            if ((row['note'] ?? '').toString().trim().isNotEmpty) row['note'].toString().trim(),
          ];
          return Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.agriculture_outlined)),
              title: Text('${_category(row)} · $title'),
              subtitle: Text(details.join(' · ')),
              trailing: Text(widget.money.format(amount), style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          );
        }),
      ]),
    );
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
              title: const Text('Pending Payments (Tractor + Khet Purchase)'),
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
            final due = DateTime.tryParse(row['dueDate']?.toString() ?? '');
            final isPurchase = row['pendingKind'] == 'PURCHASE';
            final isKhetExpense = row['pendingKind'] == 'KHET_EXPENSE';
            final person = (row['personName'] ?? row['vendorName'] ?? row['customerName'] ?? row['contact'] ?? 'Person').toString();
            final total = _amount(row['totalAmount'] ?? row['amount']);
            final paid = _amount(row['paidAmount']);
            return Card(
              child: ListTile(
                title: Text(
                  isPurchase
                      ? '${row['vendorName'] ?? 'Shop'} · ${row['title'] ?? 'Purchase'}'
                      : isKhetExpense
                          ? '$person · ${row['title'] ?? 'Khet expense'}'
                          : (row['customerName'] ?? row['contact'] ?? 'Customer').toString(),
                ),
                subtitle: Text(
                  isPurchase
                      ? 'Purchase bill ₹${total.toStringAsFixed(0)} · Paid ₹${paid.toStringAsFixed(0)}'
                        '${due == null ? '' : '\nDue: ${DateFormat('dd MMM yyyy').format(due)}'}'
                      : isKhetExpense
                          ? '${row['expenseCategory'] ?? 'Khet expense'} · Total ₹${total.toStringAsFixed(0)} · Paid ₹${paid.toStringAsFixed(0)}'
                          : '${row['work'] ?? row['title'] ?? 'Tractor work'}'
                            '${due == null ? '' : '\nDue: ${DateFormat('dd MMM yyyy').format(due)}'}',
                ),
                trailing: Text(widget.money.format(_balance(row)), style: const TextStyle(color: Colors.red,fontWeight: FontWeight.bold)),
                onTap: isPurchase ? () {
                  Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => KhetVendorLedgerDashboardScreen(
                      vendorId: row['vendorId'].toString(),
                      vendorName: (row['vendorName'] ?? 'Shop').toString(),
                      rows: widget.storage.records('khet'),
                    ),
                  ));
                } : null,
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
class KhetVendorLedgerDashboardScreen extends StatefulWidget {
 const KhetVendorLedgerDashboardScreen({required this.vendorId,required this.vendorName,required this.rows,super.key});
 final String vendorId,vendorName; final List<Map<String,dynamic>> rows;
 @override State<KhetVendorLedgerDashboardScreen> createState()=>_KhetVendorLedgerDashboardScreenState();
}
class _KhetVendorLedgerDashboardScreenState extends State<KhetVendorLedgerDashboardScreen>{
 double n(dynamic v)=>v is num?v.toDouble():double.tryParse((v??'').toString())??0;
 List<Map<String,dynamic>> get purchases=>widget.rows.where((r)=>r['type']=='KHET_PURCHASE'&&r['vendorId']==widget.vendorId).toList();
 List<Map<String,dynamic>> get payments=>widget.rows.where((r)=>r['type']=='KHET_PURCHASE_PAYMENT'&&r['vendorId']==widget.vendorId).toList();
 double get balance=>purchases.fold<double>(0,(s,r)=>s+n(r['totalAmount'])-n(r['paidAmount']))-payments.fold<double>(0,(s,r)=>s+n(r['amount']));
 Future<void> pay()async{final c=TextEditingController();final result=await showDialog<double>(context:context,builder:(ctx)=>AlertDialog(title:Text('Payment · ${widget.vendorName}'),content:Column(mainAxisSize:MainAxisSize.min,children:[Text('Remaining: ₹${balance.toStringAsFixed(0)}'),TextField(controller:c,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:const InputDecoration(labelText:'Payment amount (full/partial)'))]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),FilledButton(onPressed:(){final v=double.tryParse(c.text);if(v!=null&&v>0)Navigator.pop(ctx,v);},child:const Text('Save'))]));c.dispose();if(result==null)return;await StorageBackupService.instance.addRecord('khet',{'id':DateTime.now().microsecondsSinceEpoch.toString(),'type':'KHET_PURCHASE_PAYMENT','vendorId':widget.vendorId,'vendorName':widget.vendorName,'amount':result,'date':DateTime.now().toIso8601String(),'allocationMethod':'OLDEST_BILL_FIRST'});if(mounted)setState((){});}
 @override Widget build(BuildContext context){final p=purchases..sort((a,b)=>(a['date']??'').toString().compareTo((b['date']??'').toString()));final paidAt=p.fold<double>(0,(s,r)=>s+n(r['paidAmount'])),paidLater=payments.fold<double>(0,(s,r)=>s+n(r['amount']));final fmt=NumberFormat.currency(locale:'en_IN',symbol:'₹',decimalDigits:0);return Scaffold(appBar:AppBar(title:Text('${widget.vendorName} · Khata')),body:ListView(padding:const EdgeInsets.all(16),children:[Card(child:ListTile(title:const Text('Total purchase'),trailing:Text(fmt.format(p.fold<double>(0,(s,r)=>s+n(r['totalAmount'])))))),Card(child:ListTile(title:const Text('Paid at purchase'),trailing:Text(fmt.format(paidAt)))),Card(child:ListTile(title:const Text('Payments later'),trailing:Text(fmt.format(paidLater)))),Card(child:ListTile(title:Text(balance>=0?'Net pending':'Advance'),trailing:Text(fmt.format(balance.abs()),style:TextStyle(fontWeight:FontWeight.bold,color:balance>0?Colors.red:Colors.green)))),const SizedBox(height:10),const Text('Bills',style:TextStyle(fontWeight:FontWeight.bold,fontSize:18)),...p.map((r){final b=n(r['totalAmount'])-n(r['paidAmount']);return Card(child:ListTile(title:Text((r['title']??'Purchase').toString()),subtitle:Text('Bill ${fmt.format(n(r['totalAmount']))} · Paid ${fmt.format(n(r['paidAmount']))} · ${DateFormat('dd MMM yyyy').format(DateTime.tryParse(r['invoiceDate']??r['date']??'')??DateTime.now())}'),trailing:Text(fmt.format(b.clamp(0,double.infinity)),style:TextStyle(color:b>0?Colors.red:Colors.green,fontWeight:FontWeight.bold))));})]),floatingActionButton:FloatingActionButton.extended(onPressed:pay,icon:const Icon(Icons.payments),label:const Text('Full / Partial Payment')));}
}
class _MonthVendorPurchasesScreen extends StatelessWidget {
  const _MonthVendorPurchasesScreen({
    required this.rows, required this.allRows, required this.monthTitle, required this.money,
  });
  final List<Map<String, dynamic>> rows, allRows;
  final String monthTitle;
  final NumberFormat money;
  double n(dynamic v) => v is num ? v.toDouble() : double.tryParse((v ?? '').toString()) ?? 0;

  @override
  Widget build(BuildContext context) {
    final byPerson = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      byPerson.putIfAbsent((r['vendorName'] ?? 'Shop').toString(), () => []).add(r);
    }
    final names = byPerson.keys.toList()..sort();
    final total = rows.fold<double>(0, (s, r) => s + n(r['totalAmount']));
    return Scaffold(
      appBar: AppBar(title: Text('$monthTitle · Purchase Hisab')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: ListTile(
          title: const Text('Month total purchases'), trailing: Text(money.format(total)),
        )),
        ...names.map((name) {
          final list = byPerson[name]!;
          final bought = list.fold<double>(0, (s, r) => s + n(r['totalAmount']));
          final paid = list.fold<double>(0, (s, r) => s + n(r['paidAmount']));
          final id = list.first['vendorId']?.toString() ?? '';
          return Card(child: ListTile(
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('${list.length} bills · Bought ${money.format(bought)} · Paid ${money.format(paid)} · Pending ${money.format(bought - paid)}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute<void>(
              builder: (_) => KhetVendorLedgerDashboardScreen(vendorId: id, vendorName: name, rows: allRows),
            )),
          ));
        }),
        ...rows.map((r) => Card(child: ListTile(
          title: Text('${r['title'] ?? 'Purchase'} · ${r['vendorName'] ?? ''}'),
          subtitle: Text('${r['purchaseCategory'] ?? ''} · ${DateFormat('dd MMM yyyy').format(DateTime.tryParse((r['invoiceDate'] ?? r['date'] ?? '').toString()) ?? DateTime.now())}'),
          trailing: Text(money.format(n(r['totalAmount']))),
        ))),
      ]),
    );
  }
}
