import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/storage_backup_service.dart';
import '../services/farm_reminder_service.dart';
import '../widgets/khet_map_widget.dart';
import '../widgets/plot_selector.dart';
import '../widgets/khata_widgets.dart';

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
    // Purchase records may use invoiceDate even when date is missing.
    for (final key in ['invoiceDate', 'date', 'createdAt', 'updatedAt', 'billDate']) {
      final value = row[key];
      if (value is DateTime) return value;
      if (value != null) {
        final parsed = DateTime.tryParse(value.toString());
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

  int _kuaWaterOwedMinutes(Map<String, dynamic> row) {
    final explicit = _amount(row['waterOwedMinutes'] ?? row['exchangeMinutes']).toInt();
    if (explicit > 0) return explicit;
    final wellMinutes = row['wellMinutes'];
    if (wellMinutes is Map) {
      return wellMinutes.values.fold<int>(0, (sum, value) => sum + _amount(value).toInt());
    }
    return 0;
  }

  int _kuaWaterReturnedMinutes(Map<String, dynamic> row) {
    final history = row['waterExchangeHistory'];
    if (history is List) {
      return history.fold<int>(0, (sum, item) =>
          sum + (item is Map ? _amount(item['minutes']).toInt() : 0));
    }
    return _amount(row['waterExchangedMinutes']).toInt();
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
    final allPersonLedgerRows = <Map<String, dynamic>>[
      ...hisabs.where((row) => (row['personName'] ?? '').toString().trim().isNotEmpty).map((row) => <String, dynamic>{...row, 'ledgerSource': 'HISAB'}),
      ...khet.where((row) => const ['TRACTOR', 'KHET_PURCHASE', 'KHET_PURCHASE_PAYMENT'].contains(row['type']))
          .map((row) {
            final person = row['type'] == 'TRACTOR'
                ? (row['customerName'] ?? row['ownerName'] ?? row['contact'] ?? '').toString()
                : (row['vendorName'] ?? row['contact'] ?? '').toString();
            return <String, dynamic>{...row, 'personName': person, 'ledgerSource': 'KHET'};
          }).where((row) => (row['personName'] ?? '').toString().trim().isNotEmpty),
      ...khet.where((row) => row['type'] == 'KUA' && _amount(row['cashAmount']) > 0)
          .map((row) => <String, dynamic>{
            ...row,
            'personName': row['contact'] ?? 'Samne wala',
            'totalAmount': _amount(row['cashAmount']),
            'amount': _amount(row['cashAmount']),
            'paidAmount': _amount(row['cashPaid']),
            'ledgerSource': 'KHET',
          }),
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
    final tractorPending = khet.where((row) => row['type'] == 'TRACTOR' && _balance(row) > 0).map((row) => <String, dynamic>{...row, 'pendingKind': 'TRACTOR', 'pendingSource': 'khet'}).toList();
    final vendorPurchases = khet.where((row) => row['type'] == 'KHET_PURCHASE' && thisMonth(row)).toList();
    final monthVendorTotal = vendorPurchases.fold<double>(
      0, (sum, row) => sum + _amount(row['totalAmount'] ?? row['amount'] ?? row['price']),
    );
    // Payments are allocated to each vendor's oldest bill first. Count the
    // amount actually settled on the selected month's bills.
    var monthVendorPaid = 0.0;
    final vendorIds = vendorPurchases.map((r)=>r['vendorId']).where((id)=>id!=null).toSet();
    final vendorPending = <Map<String,dynamic>>[];
    for(final vendorId in vendorIds){
      final purchases=khet.where((r)=>r['type']=='KHET_PURCHASE'&&r['vendorId']==vendorId).toList()
        ..sort((a,b)=>(a['invoiceDate']??a['date']??'').toString().compareTo((b['invoiceDate']??b['date']??'').toString()));
      var payments=khet.where((r)=>r['type']=='KHET_PURCHASE_PAYMENT'&&r['vendorId']==vendorId)
        .fold<double>(0,(sum,r)=>sum+_amount(r['amount']));
      for(final purchase in purchases){
        final initiallyPaid = _amount(purchase['paidAmount']);
        final base=(_amount(purchase['totalAmount'])-initiallyPaid).clamp(0,double.infinity).toDouble();
        final applied=payments<base?payments:base;
        payments-=applied;
        final balance=base-applied;
        if (thisMonth(purchase)) {
          monthVendorPaid += initiallyPaid + applied;
          if(balance>0)vendorPending.add({...purchase,'dashboardBalance':balance,'pendingKind':'PURCHASE','pendingSource':'khet'});
        }
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
        if (remaining > 0.009) {
          khetExpensePending.add({
            ...expense,
            'dashboardBalance': remaining,
            'pendingKind': 'KHET_EXPENSE',
            'pendingSource': 'hisabs',
          });
        }
      }
    }
    final allVendorIds = khet.where((r) => r['type'] == 'KHET_PURCHASE').map((r) => r['vendorId']).where((id) => id != null).toSet();
    final vendorPendingAll = <Map<String, dynamic>>[];
    for (final vendorId in allVendorIds) {
      final purchases = khet.where((r) => r['type'] == 'KHET_PURCHASE' && r['vendorId'] == vendorId).toList()
        ..sort((a, b) => (a['invoiceDate'] ?? a['date'] ?? '').toString().compareTo((b['invoiceDate'] ?? b['date'] ?? '').toString()));
      var available = khet.where((r) => r['type'] == 'KHET_PURCHASE_PAYMENT' && r['vendorId'] == vendorId)
          .fold<double>(0, (sum, r) => sum + _amount(r['amount']));
      for (final purchase in purchases) {
        final base = (_amount(purchase['totalAmount']) - _amount(purchase['paidAmount'])).clamp(0, double.infinity).toDouble();
        final applied = available < base ? available : base;
        available -= applied;
        final balance = base - applied;
        if (balance > 0.009) vendorPendingAll.add({...purchase, 'dashboardBalance': balance, 'pendingKind': 'PURCHASE', 'pendingSource': 'khet'});
      }
    }
    final kuaCashPending = khet.where((row) => row['type'] == 'KUA' && _amount(row['cashBalance'] ?? (_amount(row['cashAmount']) - _amount(row['cashPaid']))) > 0.009).map((row) => <String, dynamic>{
      ...row,
      'totalAmount': _amount(row['cashAmount']),
      'paidAmount': _amount(row['cashPaid']),
      'balance': _amount(row['cashBalance'] ?? (_amount(row['cashAmount']) - _amount(row['cashPaid']))),
      'pendingKind': 'KUA_CASH',
      'pendingSource': 'khet',
    }).toList();
    final pending=[...tractorPending,...vendorPendingAll,...khetExpensePending,...kuaCashPending]
      ..sort((a,b)=>(DateTime.tryParse(a['dueDate'] as String? ?? '')??DateTime(9999))
          .compareTo(DateTime.tryParse(b['dueDate'] as String? ?? '')??DateTime(9999)));
    final pendingTotal=pending.fold<double>(0,(sum,row)=>sum+_balance(row));
    final monthVendorPending = vendorPending.fold<double>(0,(sum,row)=>sum+_balance(row));
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
              builder: (_) => _PendingPaymentsScreen(rows: pending, waterRows: khet.where((r) => (r['type'] == 'PANI' && r['waterPaymentPending'] == true) || (r['type'] == 'KUA' && _kuaWaterOwedMinutes(r) > _kuaWaterReturnedMinutes(r))).toList(), money: money, storage: storage, monthTitle: DateFormat('MMMM yyyy').format(selectedDate)),
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
          subtitle: Text('Bought ${money.format(monthVendorTotal)} · Paid ${money.format(monthVendorPaid)} · Pending ${money.format(monthVendorPending)}'),
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
    if (type == 'KUA') return _amount(row['cashAmount']) - _amount(row['cashPaid']);
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

class _PersonMonthDetailScreen extends StatefulWidget {
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

  @override
  State<_PersonMonthDetailScreen> createState() => _PersonMonthDetailScreenState();
}

class _PersonMonthDetailScreenState extends State<_PersonMonthDetailScreen> {
  late List<Map<String, dynamic>> _rows;

  String get name => widget.name;
  List<Map<String, dynamic>> get rows => _rows;
  String get monthTitle => widget.monthTitle;
  String get selectedMonth => widget.selectedMonth;

  @override
  void initState() {
    super.initState();
    _rows = List<Map<String, dynamic>>.from(widget.rows);
  }

  double _amount(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse((value ?? '').toString().replaceAll(',', '').replaceAll('₹', '').trim()) ?? 0;

  double _delta(Map<String, dynamic> row) {
    final type = row['type'];
    if (row['entryType'] == 'EXPENSE' || type == 'KHET_PURCHASE' || type == 'TRACTOR') {
      return _amount(row['paidAmount']) - _amount(row['totalAmount'] ?? row['amount'] ?? row['price']);
    }
    if (type == 'KHET_PURCHASE_PAYMENT') return _amount(row['amount']);
    if (type == 'KUA') return _amount(row['cashAmount']) - _amount(row['cashPaid']);
    return row['direction'] == 'PAID' ? _amount(row['amount']) : -_amount(row['amount']);
  }

  String _personForRow(Map<String, dynamic> row) =>
      (row['personName'] ?? row['vendorName'] ?? row['customerName'] ?? row['ownerName'] ?? row['contact'] ?? '').toString().trim();

  Future<void> _refreshPersonRows() async {
    final storage = StorageBackupService.instance;
    final target = name.toLowerCase();
    final hisabs = storage.records('hisabs').where((row) =>
      _personForRow(row).toLowerCase() == target
    ).map((row) => <String, dynamic>{...row, 'ledgerSource': 'HISAB'}).toList();
    final khet = storage.records('khet').where((row) {
      if (!const ['TRACTOR', 'KHET_PURCHASE', 'KHET_PURCHASE_PAYMENT', 'KUA'].contains(row['type'])) return false;
      return _personForRow(row).toLowerCase() == target;
    }).map((row) => <String, dynamic>{
      ...row,
      'personName': _personForRow(row),
      'ledgerSource': 'KHET',
    }).toList();
    if (mounted) setState(() => _rows = [...hisabs, ...khet]);
  }

  Future<void> _recordPersonPayment() async {
    final beforeNet = rows.fold<double>(0, (sum, row) => sum + _delta(row));
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    String direction = beforeNet < -0.009 ? 'Diya' : 'Liya';
    DateTime paymentDate = DateTime.now();
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) => AlertDialog(
        title: Text('Payment · $name'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            beforeNet > 0.009
                ? 'Pehle lena baki: ₹${beforeNet.toStringAsFixed(0)}'
                : beforeNet < -0.009
                    ? 'Pehle dena baki: ₹${beforeNet.abs().toStringAsFixed(0)}'
                    : 'Purana hisab barabar hai',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          DropdownButtonFormField<String>(
            value: direction,
            decoration: const InputDecoration(labelText: 'Payment type'),
            items: const [
              DropdownMenuItem(value: 'Diya', child: Text('💸 Humne paise diye')),
              DropdownMenuItem(value: 'Liya', child: Text('💰 Humne paise liye')),
            ],
            onChanged: (value) => setDialog(() => direction = value ?? direction),
          ),
          TextField(
            controller: amountController,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Kitne rupaye?'),
            onChanged: (_) => setDialog(() {}),
          ),
          Builder(builder: (context) {
            final amount = _amount(amountController.text);
            final after = beforeNet + (direction == 'Diya' ? amount : -amount);
            final label = after > 0.009
                ? 'Ab ₹${after.toStringAsFixed(0)} lena baki'
                : after < -0.009
                    ? 'Ab ₹${after.abs().toStringAsFixed(0)} dena baki'
                    : 'Hisab ₹0 · Clear';
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Align(alignment: Alignment.centerLeft, child: Text(label)),
            );
          }),
          TextField(controller: noteController, decoration: const InputDecoration(labelText: 'Note (optional)')),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today),
            label: Text('Date: ${DateFormat('dd MMM yyyy').format(paymentDate)}'),
            onPressed: () async {
              final picked = await showDatePicker(
                context: ctx,
                initialDate: paymentDate,
                firstDate: DateTime(2000),
                lastDate: DateTime.now().add(const Duration(days: 3650)),
              );
              if (picked != null) setDialog(() => paymentDate = picked);
            },
          ),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (_amount(amountController.text) <= 0) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Sahi amount bharein')));
                return;
              }
              Navigator.pop(ctx, {
                'amount': _amount(amountController.text),
                'direction': direction,
                'date': paymentDate,
                'note': noteController.text.trim(),
              });
            },
            child: const Text('Save payment'),
          ),
        ],
      )),
    );
    amountController.dispose();
    noteController.dispose();
    if (result == null) return;

    final amount = (result['amount'] as num).toDouble();
    direction = result['direction'] as String;
    final date = (result['date'] as DateTime).toIso8601String();
    final note = (result['note'] ?? '').toString();
    final storage = StorageBackupService.instance;
    var remaining = amount;
    var allocated = 0.0;

    // Allocate each payment/refund against the same person's oldest matching records.
    final debts = [...rows.where((row) =>
      row['entryType'] == 'EXPENSE' || row['type'] == 'TRACTOR'
    )]..sort((a, b) {
      final cmp = (a['date'] ?? '').toString().compareTo((b['date'] ?? '').toString());
      return direction == 'Diya' ? cmp : -cmp;
    });
    for (final debt in debts) {
      if (remaining <= 0.009) break;
      final table = debt['ledgerSource'] == 'HISAB' || debt['entryType'] == 'EXPENSE' ? 'hisabs' : 'khet';
      final source = storage.records(table).where((row) => row['id']?.toString() == debt['id']?.toString()).toList();
      if (source.isEmpty) continue;
      final original = source.first;
      final total = _amount(original['totalAmount'] ?? original['amount'] ?? original['price']);
      final oldPaid = _amount(original['paidAmount']);
      final dueBefore = (total - oldPaid).clamp(0, double.infinity).toDouble();
      final available = direction == 'Diya' ? dueBefore : oldPaid;
      if (available <= 0.009) continue;
      final take = remaining < available ? remaining : available;
      final newPaid = direction == 'Diya' ? oldPaid + take : (oldPaid - take).clamp(0, double.infinity).toDouble();
      final dueAfter = (total - newPaid).clamp(0, double.infinity).toDouble();
      final history = (original['payments'] as List? ?? const [])
          .whereType<Map>().map((entry) => Map<String, dynamic>.from(entry)).toList()
        ..add({
          'amount': take,
          'direction': direction,
          'date': date,
          'note': note,
          'balanceBefore': dueBefore,
          'balanceAfter': dueAfter,
        });
      final updated = Map<String, dynamic>.from(original)
        ..['paidAmount'] = newPaid
        ..['balance'] = dueAfter
        ..['payments'] = history
        ..['status'] = dueAfter <= 0.009 ? 'PAID' : (newPaid > 0 ? 'PARTIAL' : 'PENDING')
        ..['updatedAt'] = DateTime.now().toIso8601String();
      await storage.updateRecord(table, original['id'].toString(), updated);
      remaining -= take;
      allocated += take;
    }

    // Vendor purchases use separate signed payment records so a refund
    // increases the vendor balance and a payment reduces it.
    final vendorIds = rows.where((row) => row['type'] == 'KHET_PURCHASE')
        .map((row) => row['vendorId']).where((id) => id != null).toSet();
    for (final vendorId in vendorIds) {
      if (remaining <= 0.009) break;
      final vendorBills = storage.records('khet').where((row) =>
        row['type'] == 'KHET_PURCHASE' && row['vendorId'] == vendorId
      ).toList();
      final vendorPayments = storage.records('khet').where((row) =>
        row['type'] == 'KHET_PURCHASE_PAYMENT' && row['vendorId'] == vendorId
      ).toList();
      final vendorPaymentNet = vendorPayments.fold<double>(0, (sum, row) => sum + _amount(row['amount']));
      final initialPaid = vendorBills.fold<double>(0, (sum, row) => sum + _amount(row['paidAmount']));
      final vendorDue = (vendorBills.fold<double>(0, (sum, row) =>
        sum + _amount(row['totalAmount']) - _amount(row['paidAmount'])) - vendorPaymentNet);
      final available = direction == 'Diya'
          ? vendorDue.clamp(0, double.infinity).toDouble()
          : (initialPaid + vendorPaymentNet).clamp(0, double.infinity).toDouble();
      if (available <= 0.009) continue;
      final take = remaining < available ? remaining : available;
      final signedAmount = direction == 'Diya' ? take : -take;
      await storage.addRecord('khet', {
        'id': DateTime.now().microsecondsSinceEpoch.toString(),
        'type': 'KHET_PURCHASE_PAYMENT',
        'vendorId': vendorId,
        'vendorName': vendorBills.first['vendorName'] ?? name,
        'amount': signedAmount,
        'direction': direction,
        'date': date,
        'note': note,
        'allocationMethod': 'OLDEST_BILL_FIRST',
        'balanceBefore': vendorDue,
        'balanceAfter': vendorDue - signedAmount,
      });
      remaining -= take;
      allocated += take;
    }

    // Kua cash/rent is money the person owes us. A receipt reduces it;
    // returning money increases it again.
    final kuaRows = [...rows.where((row) => row['type'] == 'KUA')]
      ..sort((a, b) {
        final cmp = (a['date'] ?? '').toString().compareTo((b['date'] ?? '').toString());
        return direction == 'Liya' ? cmp : -cmp;
      });
    for (final kua in kuaRows) {
      if (remaining <= 0.009) break;
      final source = storage.records('khet').where((row) =>
        row['id']?.toString() == kua['id']?.toString() && row['type'] == 'KUA'
      ).toList();
      if (source.isEmpty) continue;
      final original = source.first;
      final total = _amount(original['cashAmount']);
      final oldPaid = _amount(original['cashPaid']);
      final dueBefore = (total - oldPaid).clamp(0, double.infinity).toDouble();
      final available = direction == 'Liya' ? dueBefore : oldPaid;
      if (available <= 0.009) continue;
      final take = remaining < available ? remaining : available;
      final newPaid = direction == 'Liya' ? oldPaid + take : (oldPaid - take).clamp(0, double.infinity).toDouble();
      final dueAfter = (total - newPaid).clamp(0, double.infinity).toDouble();
      final history = (original['payments'] as List? ?? const [])
          .whereType<Map>().map((entry) => Map<String, dynamic>.from(entry)).toList()
        ..add({
          'amount': take,
          'direction': direction,
          'date': date,
          'note': note,
          'balanceBefore': dueBefore,
          'balanceAfter': dueAfter,
        });
      final updated = Map<String, dynamic>.from(original)
        ..['cashPaid'] = newPaid
        ..['cashBalance'] = dueAfter
        ..['cashStatus'] = dueAfter <= 0.009 ? 'PAID' : (newPaid > 0 ? 'PARTIAL' : 'PENDING')
        ..['payments'] = history
        ..['updatedAt'] = DateTime.now().toIso8601String();
      await storage.updateRecord('khet', original['id'].toString(), updated);
      remaining -= take;
      allocated += take;
    }

    // Any amount not assigned to a specific bill is retained as a person
    // account transaction (advance/settlement) instead of being discarded.
    if (remaining > 0.009 || allocated <= 0.009) {
      final isKhetPerson = rows.any((row) =>
        row['category'] == 'Khet' || row['type'] == 'TRACTOR' ||
        row['type'] == 'KHET_PURCHASE' || row['type'] == 'KUA'
      );
      final afterNet = beforeNet + (direction == 'Diya' ? amount : -amount);
      await storage.addRecord('hisabs', {
        'id': DateTime.now().microsecondsSinceEpoch.toString(),
        'category': isKhetPerson ? 'Khet' : 'Len-Den',
        'title': direction == 'Diya' ? 'Person payment · Paise diye' : 'Person payment · Paise liye',
        'amount': (remaining > 0.009 ? remaining : amount).toString(),
        'direction': direction == 'Diya' ? 'PAID' : 'RECEIVED',
        'entryType': 'PAYMENT',
        'paymentKind': 'PERSON_PAYMENT',
        'balanceBefore': beforeNet + (direction == 'Diya' ? allocated : -allocated),
        'balanceAfter': afterNet,
        'personName': name,
        'personPhone': rows.map((row) => row['personPhone'] ?? row['customerPhone'] ?? row['contactPhone']).where((v) => v != null && v.toString().trim().isNotEmpty).cast<String?>().firstWhere((v) => true, orElse: () => null),
        'date': date,
        'note': note,
      });
    }
    await _refreshPersonRows();
  }

  String _title(Map<String, dynamic> row) {
    if (row['paymentKind'] == 'PERSON_PAYMENT') return row['direction'] == 'PAID' ? 'आपने पैसे दिए' : 'आपको पैसे मिले';
    if (row['entryType'] == 'EXPENSE') return '${row['expenseCategory'] ?? 'Khet'} · ${row['title'] ?? 'Kharcha'}';
    if (row['type'] == 'KHET_PURCHASE') return 'खरीद · ${row['title'] ?? 'Samaan'}';
    if (row['type'] == 'KHET_PURCHASE_PAYMENT') return 'दुकानदार को भुगतान';
    if (row['type'] == 'KUA') return 'कुएँ का पानी · Cash/Rent';
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
      final history = (row['payments'] as List? ?? const []).whereType<Map>().toList();
      if (history.isNotEmpty) parts.add('Payment history: ${history.map((p) { final dt=DateTime.tryParse((p['date']??'').toString()); final before=p['balanceBefore']==null?'':'pehle ${money.format(_amount(p['balanceBefore']))}'; final after=p['balanceAfter']==null?'':'baad mein ${money.format(_amount(p['balanceAfter']))}'; return '${dt==null?'':DateFormat('dd MMM yyyy').format(dt)} ${p['direction'] ?? 'Diya'} ${money.format(_amount(p['amount']))} · $before · $after'; }).join(' → ')}');
      final plot = plotLabelForId(StorageBackupService.instance, row['plotId']);
      if (plot.isNotEmpty) parts.add(plot);
      final category = row['expenseCategory'] ?? row['purchaseCategory'];
      if (category != null && category.toString().isNotEmpty) parts.add(category.toString());
    } else if (row['type'] == 'KUA') {
      final total = _amount(row['cashAmount']);
      final paid = _amount(row['cashPaid']);
      parts.add('Cash/Rent ${money.format(total)} · Mila ${money.format(paid)} · Baki ${money.format((total - paid).clamp(0, double.infinity))}');
      final history = (row['payments'] as List? ?? const []).whereType<Map>().toList();
      if (history.isNotEmpty) parts.add('Payment history: ${history.map((p) { final dt = DateTime.tryParse((p['date'] ?? '').toString()); return '${dt == null ? '' : DateFormat('dd MMM yyyy').format(dt)} ${p['direction'] ?? ''} ${money.format(_amount(p['amount']))} · pehle ${money.format(_amount(p['balanceBefore']))} · baad mein ${money.format(_amount(p['balanceAfter']))}'; }).join(' → ')}');
    } else if (row['type'] == 'KHET_PURCHASE_PAYMENT') {
      parts.add('${row['direction'] == 'Liya' ? 'Refund received' : 'Dukandar ko payment'} ${money.format(_amount(row['amount']).abs())}');
      if (row['balanceBefore'] != null || row['balanceAfter'] != null) parts.add('Pehle baki ${money.format(_amount(row['balanceBefore']))} · baad mein ${money.format(_amount(row['balanceAfter']))}');
    } else {
      parts.add('Amount ${money.format(_amount(row['amount']))}');
      if (row['paymentKind'] == 'PERSON_PAYMENT') {
        parts.add('Pehle baki ${money.format(_amount(row['balanceBefore']).abs())} · Baad mein baki ${money.format(_amount(row['balanceAfter']).abs())}');
      }
    }
    final note = (row['note'] ?? '').toString().trim();
    if (note.isNotEmpty) parts.add(note);
    return cleanDisplayText(parts.join(' · '));
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...rows]..sort((a, b) =>
      (DateTime.tryParse((a['date'] ?? a['invoiceDate'] ?? '').toString()) ?? DateTime(0))
        .compareTo(DateTime.tryParse((b['date'] ?? b['invoiceDate'] ?? '').toString()) ?? DateTime(0)));
    final runningBalances = <String, double>{};
    double running = 0;
    for (final row in sorted) {
      running += _delta(row);
      runningBalances[row['id']?.toString() ?? ''] = running;
    }
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
      appBar: AppBar(title: Text(name, overflow: TextOverflow.ellipsis), actions: [IconButton(tooltip: 'Payment add karein', onPressed: _recordPersonPayment, icon: const Icon(Icons.add_card))]),
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
          final balanceAfter = runningBalances[row['id']?.toString() ?? ''] ?? 0;
          final balanceLabel = balanceAfter >= 0
              ? '${money.format(balanceAfter.abs())} lena baki'
              : '${money.format(balanceAfter.abs())} dena baki';
          return Card(child: ListTile(
            leading: Icon(
              isCost ? Icons.shopping_bag_outlined
                  : row['type'] == 'KHET_PURCHASE_PAYMENT' || row['direction'] == 'PAID'
                      ? Icons.payments_outlined
                      : Icons.call_received,
            ),
            title: Text(_title(row)),
            subtitle: Text('${_subtitle(row, money)}\nBalance after: $balanceLabel'),
            trailing: Text(
              delta.abs() < 0.009 ? '₹0' : '${delta > 0 ? '+' : '−'}${money.format(delta.abs())}',
              style: TextStyle(fontWeight: FontWeight.w800, color: delta > 0 ? Colors.green : delta < 0 ? Colors.red : Colors.black54),
            ),
          ));
        }),
      ]),
      floatingActionButton: FloatingActionButton.extended(onPressed: _recordPersonPayment, icon: const Icon(Icons.payments), label: const Text('Add Payment')),
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

  String _plotSummary(Map<String, dynamic> row) {
    final ids = (row['plotIds'] as List? ?? const [])
        .map((id) => id.toString()).where((id) => id.isNotEmpty).toList();
    if (ids.isNotEmpty) {
      final savedLabels = (row['plotLabelsSnapshot'] as List? ?? const [])
          .map((label) => label.toString()).where((label) => label.isNotEmpty).toList();
      final labels = savedLabels.isNotEmpty
          ? savedLabels
          : StorageBackupService.instance.records('plots')
              .where((plot) => ids.contains(plot['id'].toString()))
              .map(plotLabel).toList();
      return 'सामूहिक खर्च · ${ids.length} किले${labels.isEmpty ? '' : ': ${labels.join(', ')}'}';
    }
    if (row['plotId'] != null) {
      final label = plotLabelForId(StorageBackupService.instance, row['plotId']);
      return label.isEmpty ? 'एक किले के लिए' : label;
    }
    return 'पूरे खेत के लिए';
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
          final plot = _plotSummary(row);
          final title = (row['title'] ?? row['work'] ?? row['workType'] ?? _category(row)).toString();
          final details = <String>[
            if (date != null) DateFormat('dd MMM yyyy').format(date),
            if (person.isNotEmpty) 'Person: $person',
            if (plot.isNotEmpty) plot,
            'Paid ${widget.money.format(paid)}',
            'Pending ${widget.money.format(remainingById[(row['id'] ?? '').toString()] ?? (amount - paid).clamp(0, double.infinity).toDouble())}',
            if ((row['note'] ?? '').toString().trim().isNotEmpty) row['note'].toString().trim(),
          ];
          final pendingAmount = remainingById[(row['id'] ?? '').toString()] ??
              (amount - paid).clamp(0, double.infinity).toDouble();
          return Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.agriculture_outlined)),
              title: Text('${_category(row)} · $title'),
              subtitle: Text(details.join(' · ')),
              trailing: Text(widget.money.format(amount), style: const TextStyle(fontWeight: FontWeight.w800)),
              onTap: pendingAmount > 0.009 ? () {
                if (row['type'] == 'KHET_PURCHASE') {
                  Navigator.push(context, MaterialPageRoute<void>(builder: (_) =>
                    KhetVendorLedgerDashboardScreen(
                      vendorId: row['vendorId'].toString(),
                      vendorName: (row['vendorName'] ?? 'Shop').toString(),
                      rows: StorageBackupService.instance.records('khet'),
                    )));
                } else {
                  final pendingRow = <String, dynamic>{
                    ...row,
                    'dashboardBalance': pendingAmount,
                    'pendingKind': row['type'] == 'TRACTOR' ? 'TRACTOR' : 'KHET_EXPENSE',
                    'pendingSource': row['entryType'] == 'EXPENSE' ? 'hisabs' : 'khet',
                  };
                  Navigator.push(context, MaterialPageRoute<void>(builder: (_) =>
                    _PendingPaymentsScreen(
                      rows: [pendingRow],
                      waterRows: const [],
                      money: widget.money,
                      storage: StorageBackupService.instance,
                      monthTitle: selected == null ? 'All months' : DateFormat('MMMM yyyy').format(DateTime(int.parse(selected.split('-')[0]), int.parse(selected.split('-')[1]))),
                    )));
                }
              } : null,
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
    final dashboardBalance = row['dashboardBalance'];
    if (dashboardBalance is num) return dashboardBalance.toDouble();
    final explicit = row['balance'];
    if (explicit is num) return explicit.toDouble();
    return (_amount(row['totalAmount'] ?? row['price']) -
            _amount(row['paidAmount']))
        .clamp(0, double.infinity)
        .toDouble();
  }

  int _waterOwedMinutes(Map<String, dynamic> row) {
    if (row['type'] == 'KUA') {
      final explicit = _amount(row['waterOwedMinutes'] ?? row['exchangeMinutes']).toInt();
      if (explicit > 0) return explicit;
      final wellMinutes = row['wellMinutes'];
      if (wellMinutes is Map) return wellMinutes.values.fold<int>(0, (sum, value) => sum + _amount(value).toInt());
      return 0;
    }
    final nahar = _amount(row['borrowedNaharMinutes']).toInt();
    final kua = _amount(row['borrowedKuaMinutes']).toInt();
    final splitTotal = nahar + kua;
    return splitTotal > 0 ? splitTotal : _amount(row['borrowedMinutes']).toInt();
  }

  int _waterExchangedMinutes(Map<String, dynamic> row) {
    if (row['waterSettlementMode'] == 'CASH') return _waterOwedMinutes(row);
    final history = row['waterExchangeHistory'];
    if (history is List) return history.fold<int>(0, (sum, item) => sum + (item is Map ? _amount(item['minutes']).toInt() : 0));
    return _amount(row['waterExchangedMinutes']).toInt();
  }

  Future<void> _updateWaterStatus(Map<String, dynamic> row) async {
    final noteController = TextEditingController(text: (row['waterPaymentNote'] ?? '').toString());
    final minutesController = TextEditingController();
    final cashDueController = TextEditingController(
      text: (row['waterCashDueAmount'] ?? '').toString(),
    );
    final cashAmountController = TextEditingController();
    final cashMode = row['waterSettlementMode'] == 'CASH';
    String status = cashMode ? 'CASH_PAYMENT' : 'PENDING';
    DateTime activityDate = DateTime.now();
    final owed = _waterOwedMinutes(row);
    final exchanged = _waterExchangedMinutes(row);
    final remaining = (owed - exchanged).clamp(0, 999999);
    final oldCashPaid = _amount(row['waterCashPaidAmount']);
    final oldCashDue = _amount(row['waterCashDueAmount']);
    final oldCashBalance = (oldCashDue - oldCashPaid).clamp(0, double.infinity).toDouble();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) => AlertDialog(
        title: Text('Pani pending · ${row['borrowedContact'] ?? row['contact'] ?? 'Person'}'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (cashMode)
            Text('Cash due: ${widget.money.format(oldCashDue)}\nPaid: ${widget.money.format(oldCashPaid)}\nBaki cash: ${widget.money.format(oldCashBalance)}',
              style: const TextStyle(fontWeight: FontWeight.w600))
          else
            Text('${row['type'] == 'KUA' ? 'Humein is vyakti se pani lena hai' : 'Total pani udhaar'}: $owed min\nBadle mein mila: $exchanged min\nBaki: $remaining min\n${row['type'] == 'KUA' ? 'Kua: ${row['wellSelection'] ?? 'Solar'}' : ''}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          DropdownButtonFormField<String>(
            value: status,
            items: [
              const DropdownMenuItem(value: 'PENDING', child: Text('Pending')),
              if (!cashMode)
                const DropdownMenuItem(value: 'WATER_EXCHANGE', child: Text('Badle mein pani liya')),
              if (row['type'] != 'KUA')
                const DropdownMenuItem(value: 'CASH_PAYMENT', child: Text('Rupaye dekar settle karein')),
            ],
            onChanged: (v) => setDialog(() { status = v ?? 'PENDING'; }),
          ),
          if (status == 'WATER_EXCHANGE') ...[
            TextField(
              controller: minutesController,
              keyboardType: const TextInputType.numberWithOptions(decimal: false),
              decoration: const InputDecoration(labelText: 'Badle mein kitne minute pani mila?'),
              onChanged: (_) => setDialog(() {}),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today),
              label: Text('Pani liya: ${DateFormat('dd MMM yyyy').format(activityDate)}'),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: ctx,
                  initialDate: activityDate,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now().add(const Duration(days: 3650)),
                );
                if (picked != null) setDialog(() => activityDate = DateTime(
                  picked.year, picked.month, picked.day, activityDate.hour, activityDate.minute,
                ));
              },
            ),
            Text('Iske baad baki: ${(remaining - (int.tryParse(minutesController.text) ?? 0)).clamp(0, 999999)} min'),
          ],
          if (status == 'CASH_PAYMENT') ...[
            TextField(
              controller: cashDueController,
              readOnly: oldCashDue > 0,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Total cash due (₹)'),
              onChanged: (_) => setDialog(() {}),
            ),
            TextField(
              controller: cashAmountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Ab kitne rupaye diye?'),
              onChanged: (_) => setDialog(() {}),
            ),
            Text('Iske baad cash baki: ${widget.money.format((_amount(cashDueController.text) - oldCashPaid - _amount(cashAmountController.text)).clamp(0, double.infinity))}'),
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today),
              label: Text('Payment date: ${DateFormat('dd MMM yyyy').format(activityDate)}'),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: ctx,
                  initialDate: activityDate,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now().add(const Duration(days: 3650)),
                );
                if (picked != null) setDialog(() => activityDate = DateTime(
                  picked.year, picked.month, picked.day, activityDate.hour, activityDate.minute,
                ));
              },
            ),
          ],
          TextField(controller: noteController, decoration: const InputDecoration(labelText: 'Note')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            if (status == 'WATER_EXCHANGE') {
              final m = int.tryParse(minutesController.text.trim()) ?? 0;
              if (m <= 0 || m > remaining) {
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('1 se $remaining minute enter karein')));
                return;
              }
            }
            if (status == 'CASH_PAYMENT') {
              final due = _amount(cashDueController.text);
              final amount = _amount(cashAmountController.text);
              final cashBalanceBefore = (due - oldCashPaid).clamp(0, double.infinity).toDouble();
              if (due <= 0 || due < oldCashPaid - 0.009 || amount <= 0 || amount > cashBalanceBefore + 0.009) {
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                  content: Text('Total cash due aur payment sahi bharein. Abhi baki ${widget.money.format(cashBalanceBefore)} hai.'),
                ));
                return;
              }
            }
            Navigator.pop(ctx, true);
          }, child: const Text('Save')),
        ],
      )),
    );

    if (saved != true) {
      noteController.dispose();
      minutesController.dispose();
      cashDueController.dispose();
      cashAmountController.dispose();
      return;
    }

    final updated = Map<String, dynamic>.from(row);
    final history = row['waterExchangeHistory'] is List
        ? List<Map<String, dynamic>>.from((row['waterExchangeHistory'] as List)
            .whereType<Map>().map((e) => Map<String, dynamic>.from(e)))
        : <Map<String, dynamic>>[];
    final cashHistory = (row['waterCashPaymentHistory'] as List? ?? const [])
        .whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    final totalExchangedBefore = history.fold<int>(
      0, (sum, e) => sum + _amount(e['minutes']).toInt(),
    );
    if (status == 'WATER_EXCHANGE') {
      final minutes = int.parse(minutesController.text.trim());
      final before = (owed - totalExchangedBefore).clamp(0, 999999);
      history.add({
        'minutes': minutes,
        'date': activityDate.toIso8601String(),
        'note': noteController.text.trim(),
        'balanceBefore': before,
        'balanceAfter': (before - minutes).clamp(0, 999999),
      });
    }

    final totalExchanged = history.fold<int>(
      0, (sum, e) => sum + _amount(e['minutes']).toInt(),
    );
    final left = (owed - totalExchanged).clamp(0, 999999);
    final newCashDue = status == 'CASH_PAYMENT' ? _amount(cashDueController.text) : oldCashDue;
    final newCashPaid = status == 'CASH_PAYMENT'
        ? oldCashPaid + _amount(cashAmountController.text)
        : oldCashPaid;
    final newCashBalance = (newCashDue - newCashPaid).clamp(0, double.infinity).toDouble();

    if (status == 'CASH_PAYMENT') {
      final amount = _amount(cashAmountController.text);
      final before = (newCashDue - oldCashPaid).clamp(0, double.infinity).toDouble();
      cashHistory.add({
        'amount': amount,
        'direction': 'Diya',
        'date': activityDate.toIso8601String(),
        'note': noteController.text.trim(),
        'balanceBefore': before,
        'balanceAfter': (before - amount).clamp(0, double.infinity),
      });
    }

    final cashSettlementMode = cashMode || status == 'CASH_PAYMENT';
    updated
      ..['waterExchangeHistory'] = history
      ..['waterExchangedMinutes'] = totalExchanged
      ..['waterCashPaymentHistory'] = cashHistory
      ..['waterCashDueAmount'] = newCashDue
      ..['waterCashPaidAmount'] = newCashPaid
      ..['waterCashBalance'] = newCashBalance
      ..['waterSettlementMode'] = cashSettlementMode ? 'CASH' : 'WATER'
      ..['waterRemainingMinutes'] = cashSettlementMode ? 0 : left
      ..['waterPaymentStatus'] = cashSettlementMode
          ? (newCashBalance <= 0.009 ? 'PAID' : 'PENDING')
          : (left > 0 ? 'PENDING' : 'PAID')
      ..['waterPaymentPending'] = cashSettlementMode
          ? newCashBalance > 0.009
          : left > 0
      ..['waterPaymentNote'] = noteController.text.trim();

    await widget.storage.updateRecord('khet', row['id'].toString(), updated);
    noteController.dispose();
    minutesController.dispose();
    cashDueController.dispose();
    cashAmountController.dispose();
    if (mounted) setState(() {});
  }

    Future<void> _recordExpensePayment(Map<String, dynamic> pendingRow) async {
    final sourceTable = pendingRow['pendingSource'] == 'hisabs' ? 'hisabs' : 'khet';
    final source = widget.storage.records(sourceTable)
        .where((r) => r['id']?.toString() == pendingRow['id']?.toString())
        .toList();
    if (source.isEmpty) return;
    final original = source.first;
    final total = _amount(original['totalAmount'] ?? original['amount'] ?? original['price']);
    final paid = _amount(original['paidAmount']);
    final before = _amount(pendingRow['dashboardBalance'] ?? (total - paid)).clamp(0, double.infinity).toDouble();
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    String direction = 'Diya';
    DateTime paymentDate = DateTime.now();
    final oldHistory = (original['payments'] as List? ?? const [])
        .whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    final historyText = oldHistory.isEmpty
        ? 'Abhi payment history nahi hai.'
        : oldHistory.map((p) {
            final dt = DateTime.tryParse((p['date'] ?? '').toString());
            final b = p['balanceBefore'] == null ? '' : ' · Pehle baki ₹${_amount(p['balanceBefore']).toStringAsFixed(0)}';
            final a = p['balanceAfter'] == null ? '' : ' · Baad mein baki ₹${_amount(p['balanceAfter']).toStringAsFixed(0)}';
            return '${dt == null ? '' : DateFormat('dd MMM yyyy').format(dt)} · ${p['direction'] ?? 'Diya'} ₹${_amount(p['amount']).toStringAsFixed(0)}$b$a';
          }).join('\n');
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) => AlertDialog(
        title: Text('Payment · ${original['personName'] ?? original['vendorName'] ?? original['customerName'] ?? original['contact'] ?? 'Person'}'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Total: ${widget.money.format(total)}\nPehle baki: ${widget.money.format(before)}', style: const TextStyle(fontWeight: FontWeight.w600)),
          DropdownButtonFormField<String>(
            value: direction,
            decoration: const InputDecoration(labelText: 'Payment type'),
            items: const [
              DropdownMenuItem(value: 'Diya', child: Text('Paise diye')),
              DropdownMenuItem(value: 'Liya', child: Text('Paise wapas liye')),
            ],
            onChanged: (v) => setDialog(() => direction = v ?? direction),
          ),
          TextField(controller: amountController, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: direction == 'Diya' ? 'Kitne paise diye?' : 'Kitne paise wapas mile?'),
            onChanged: (_) => setDialog(() {})),
          Builder(builder: (context) {
            final entered = _amount(amountController.text);
            final remaining = direction == 'Diya'
                ? (before - entered).clamp(0, double.infinity).toDouble()
                : before + entered;
            final exceeds = direction == 'Diya' && entered > before + 0.009;
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.45),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Hisab: ${widget.money.format(before)} ${direction == 'Diya' ? '−' : '+'} ${widget.money.format(entered)}'),
                const SizedBox(height: 4),
                Text(
                  exceeds ? 'Baki se zyada amount hai!' : 'Ab baki: ${widget.money.format(remaining)}',
                  style: TextStyle(fontWeight: FontWeight.bold, color: exceeds ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary),
                ),
              ]),
            );
          }),
          TextField(controller: noteController, decoration: const InputDecoration(labelText: 'Note (optional)')),
          OutlinedButton.icon(icon: const Icon(Icons.calendar_today),
            label: Text('Date: ${DateFormat('dd MMM yyyy').format(paymentDate)}'),
            onPressed: () async {
              final picked = await showDatePicker(context: ctx, initialDate: paymentDate,
                firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 3650)));
              if (picked != null) setDialog(() => paymentDate = picked);
            }),
          const Divider(),
          Align(alignment: Alignment.centerLeft, child: Text('Payment history\n$historyText')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            final amount = _amount(amountController.text);
            final limit = direction == 'Diya' ? before : paid;
            if (amount <= 0 || amount > limit + 0.009) {
              final label = direction == 'Diya' ? 'baki' : 'pehle diye gaye paise';
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('1 se ${widget.money.format(limit)} ke beech amount bharein ($label)')));
              return;
            }
            Navigator.pop(ctx, {'amount': amount, 'date': paymentDate, 'note': noteController.text.trim(), 'direction': direction});
          }, child: const Text('Save payment')),
        ],
      )),
    );
    amountController.dispose(); noteController.dispose();
    if (result == null) return;
    final amount = (result['amount'] as num).toDouble();
    direction = result['direction'] as String;
    final newPaid = direction == 'Diya' ? paid + amount : (paid - amount).clamp(0, double.infinity).toDouble();
    final storedAfter = (total - newPaid).clamp(0, double.infinity).toDouble();
    final after = (before - (direction == 'Diya' ? amount : -amount)).clamp(0, double.infinity).toDouble();
    final history = oldHistory..add({
      'amount': amount,
      'direction': direction,
      'date': (result['date'] as DateTime).toIso8601String(),
      'note': result['note'],
      'balanceBefore': before,
      'balanceAfter': after,
    });
    final updated = Map<String, dynamic>.from(original)
      ..['paidAmount'] = newPaid
      ..['payments'] = history
      ..['balance'] = storedAfter
      ..['paymentStatus'] = storedAfter <= 0.009 ? 'PAID' : (newPaid > 0 ? 'PARTIAL' : 'PENDING')
      ..['updatedAt'] = DateTime.now().toIso8601String();
    await widget.storage.updateRecord(sourceTable, original['id'].toString(), updated);
    final index = widget.rows.indexWhere((r) => r['id']?.toString() == original['id']?.toString());
    if (index >= 0) {
      if (after <= 0.009) {
        widget.rows.removeAt(index);
      } else {
        widget.rows[index] = {...widget.rows[index], 'paidAmount': newPaid, 'balance': after, 'dashboardBalance': after};
      }
    }
    if (mounted) setState(() {});
  }

    Future<void> _recordKuaCashPayment(Map<String, dynamic> pendingRow) async {
    final matches = widget.storage.records('khet')
        .where((r) => r['id']?.toString() == pendingRow['id']?.toString() && r['type'] == 'KUA')
        .toList();
    if (matches.isEmpty) return;
    final original = matches.first;
    final total = _amount(original['cashAmount']);
    final paid = _amount(original['cashPaid']);
    final before = (total - paid).clamp(0, double.infinity).toDouble();
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    String direction = 'Liya';
    DateTime paymentDate = DateTime.now();
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) => AlertDialog(
        title: Text('Kua cash payment · ${original['contact'] ?? 'Person'}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Pehle baki: ${widget.money.format(before)}'),
          DropdownButtonFormField<String>(
            value: direction,
            decoration: const InputDecoration(labelText: 'Payment type'),
            items: const [
              DropdownMenuItem(value: 'Liya', child: Text('Paise mile')),
              DropdownMenuItem(value: 'Diya', child: Text('Paise wapas diye')),
            ],
            onChanged: (value) => setDialog(() => direction = value ?? direction),
          ),
          TextField(controller: amountController, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: direction == 'Liya' ? 'Ab kitne paise mile?' : 'Kitne paise wapas diye?')),
          TextField(controller: noteController, decoration: const InputDecoration(labelText: 'Note (optional)')),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today),
            label: Text('Date: ${DateFormat('dd MMM yyyy').format(paymentDate)}'),
            onPressed: () async {
              final picked = await showDatePicker(context: ctx, initialDate: paymentDate,
                firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 3650)));
              if (picked != null) setDialog(() => paymentDate = picked);
            },
          ),
          Text('Iske baad baki: ${widget.money.format(before + (direction == 'Liya' ? -_amount(amountController.text) : _amount(amountController.text)))}'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            final amount = double.tryParse(amountController.text.trim()) ?? 0;
            final limit = direction == 'Liya' ? before : paid;
            if (amount <= 0 || amount > limit + 0.009) {
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('1 se ${widget.money.format(limit)} ke beech rakam bharein')));
              return;
            }
            Navigator.pop(ctx, {'amount': amount, 'date': paymentDate, 'note': noteController.text.trim(), 'direction': direction});
          }, child: const Text('Save payment')),
        ],
      )),
    );
    amountController.dispose();
    noteController.dispose();
    if (result == null) return;
    final amount = (result['amount'] as num).toDouble();
    direction = result['direction'] as String;
    final newPaid = direction == 'Liya' ? paid + amount : (paid - amount).clamp(0, double.infinity).toDouble();
    final after = (total - newPaid).clamp(0, double.infinity).toDouble();
    final history = (original['payments'] as List? ?? const [])
        .whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    history.add({
      'amount': amount,
      'direction': direction,
      'date': (result['date'] as DateTime).toIso8601String(),
      'note': result['note'],
      'balanceBefore': before,
      'balanceAfter': after,
    });
    final updated = Map<String, dynamic>.from(original)
      ..['cashPaid'] = newPaid
      ..['cashBalance'] = after
      ..['cashStatus'] = after <= 0.009 ? 'PAID' : (newPaid > 0 ? 'PARTIAL' : 'PENDING')
      ..['payments'] = history
      ..['updatedAt'] = DateTime.now().toIso8601String();
    await widget.storage.updateRecord('khet', original['id'].toString(), updated);
    final index = widget.rows.indexWhere((r) => r['id']?.toString() == original['id'].toString() && r['pendingKind'] == 'KUA_CASH');
    if (index >= 0) {
      if (after <= 0.009) {
        widget.rows.removeAt(index);
      } else {
        widget.rows[index] = {...widget.rows[index], 'paidAmount': newPaid, 'balance': after, 'dashboardBalance': after};
      }
    }
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
              title: const Text('Pending Payments (Tractor + Khet Expenses + Purchase + Kua)'),
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
            final isKuaCash = row['pendingKind'] == 'KUA_CASH';
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
                      : isKuaCash
                          ? 'Kua rent/cash ₹${total.toStringAsFixed(0)} · Paid ₹${paid.toStringAsFixed(0)}'
                          : isKhetExpense
                              ? '${row['expenseCategory'] ?? 'Khet expense'} · Total ₹${total.toStringAsFixed(0)} · Paid ₹${paid.toStringAsFixed(0)}'
                              : '${row['work'] ?? row['title'] ?? 'Tractor work'}'
                                '${due == null ? '' : '\nDue: ${DateFormat('dd MMM yyyy').format(due)}'}',
                ),
                trailing: Text(widget.money.format(_balance(row)), style: const TextStyle(color: Colors.red,fontWeight: FontWeight.bold)),
                onTap: isPurchase
                    ? () {
                        Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => KhetVendorLedgerDashboardScreen(
                            vendorId: row['vendorId'].toString(),
                            vendorName: (row['vendorName'] ?? 'Shop').toString(),
                            rows: widget.storage.records('khet'),
                          ),
                        ));
                      }
                    : isKuaCash ? () => _recordKuaCashPayment(row) : (isKhetExpense || row['pendingKind'] == 'TRACTOR') ? () => _recordExpensePayment(row) : null,
              ),
            );
          }),
          const SizedBox(height: 16),
          const Text('Pending Pani', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ...widget.waterRows.where((row) => row['waterPaymentPending'] == true || (row['type'] == 'KUA' && _waterOwedMinutes(row) > _waterExchangedMinutes(row))).map((row) {
            final date = DateTime.tryParse(row['date']?.toString() ?? '');
            final mins = _waterOwedMinutes(row);
            final exchanged = _waterExchangedMinutes(row);
            final remaining = (mins - exchanged).clamp(0, 999999);
            final cashMode = row['waterSettlementMode'] == 'CASH';
            final cashDue = _amount(row['waterCashDueAmount']);
            final cashPaid = _amount(row['waterCashPaidAmount']);
            final cashRemaining = (cashDue - cashPaid).clamp(0, double.infinity).toDouble();
            final source = (row['borrowedSource'] ?? row['source'] ?? 'Pani').toString();
            return Card(child: ListTile(
              title: Text('${row['type'] == 'KUA' ? (row['contact'] ?? 'Person') : (row['borrowedContact'] ?? row['contact'] ?? 'Person')} · ${row['type'] == 'KUA' ? 'Kua: ${row['wellSelection'] ?? 'Solar'}' : source}'),
              subtitle: Text(
                cashMode
                    ? 'Cash due: ${widget.money.format(cashDue)} · Paid: ${widget.money.format(cashPaid)} · Baki: ${widget.money.format(cashRemaining)}\n${date == null ? '' : DateFormat('dd MMM yyyy').format(date)}\n${(row['waterExchangeHistory'] as List? ?? const []).map((e) { final dt=DateTime.tryParse((e['date']??'').toString()); return '${dt==null?'':DateFormat('dd MMM yyyy').format(dt)}: ${e['minutes']} min pani liya · baki ${e['balanceAfter'] ?? ''} min'; }).join('\n')}\n${(row['waterCashPaymentHistory'] as List? ?? const []).map((e) { final dt=DateTime.tryParse((e['date']??'').toString()); return '${dt==null?'':DateFormat('dd MMM yyyy').format(dt)}: ${e['direction'] ?? 'Diya'} ${widget.money.format(_amount(e['amount']))} · Pehle ${widget.money.format(_amount(e['balanceBefore']))} · Baad mein ${widget.money.format(_amount(e['balanceAfter']))}'; }).join('\n')}\n${cleanDisplayText(row['note'])}'
                    : 'Udhaar: $mins min · Mila: $exchanged min · Baki: $remaining min\n${date == null ? '' : DateFormat('dd MMM yyyy').format(date)}\n${(row['waterExchangeHistory'] as List? ?? const []).map((e) { final dt=DateTime.tryParse((e['date']??'').toString()); return '${dt==null?'':DateFormat('dd MMM yyyy').format(dt)}: ${e['minutes']} min pani liya · pehle ${e['balanceBefore'] ?? ''} min · baki ${e['balanceAfter'] ?? ''} min'; }).join('\n')}\n${cleanDisplayText(row['note'])}'
              ),
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
  const KhetVendorLedgerDashboardScreen({
    required this.vendorId,
    required this.vendorName,
    required this.rows,
    super.key,
  });

  final String vendorId, vendorName;
  final List<Map<String, dynamic>> rows;

  @override
  State<KhetVendorLedgerDashboardScreen> createState() =>
      _KhetVendorLedgerDashboardScreenState();
}

class _KhetVendorLedgerDashboardScreenState
    extends State<KhetVendorLedgerDashboardScreen> {
  double n(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse((value ?? '').toString()) ?? 0;

  List<Map<String, dynamic>> get purchases => widget.rows
      .where((row) => row['type'] == 'KHET_PURCHASE' &&
          row['vendorId'] == widget.vendorId)
      .toList();

  List<Map<String, dynamic>> get payments => widget.rows
      .where((row) => row['type'] == 'KHET_PURCHASE_PAYMENT' &&
          row['vendorId'] == widget.vendorId)
      .toList();

  double get balance =>
      purchases.fold<double>(0, (sum, row) =>
          sum + n(row['totalAmount']) - n(row['paidAmount'])) -
      payments.fold<double>(0, (sum, row) => sum + n(row['amount']));

  Future<void> pay() async {
    final controller = TextEditingController();
    final noteController = TextEditingController();
    final before = balance;
    final refundablePaid = purchases.fold<double>(0, (sum, row) => sum + n(row['paidAmount'])) +
        payments.fold<double>(0, (sum, row) => sum + n(row['amount']));
    String direction = 'Diya';
    DateTime paymentDate = DateTime.now();
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) => AlertDialog(
        title: Text('Payment · ${widget.vendorName}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Current balance: ₹${before.toStringAsFixed(0)}'),
          DropdownButtonFormField<String>(
            value: direction,
            decoration: const InputDecoration(labelText: 'Payment type'),
            items: const [
              DropdownMenuItem(value: 'Diya', child: Text('Paise diye')),
              DropdownMenuItem(value: 'Liya', child: Text('Paise wapas liye')),
            ],
            onChanged: (value) => setDialog(() => direction = value ?? direction),
          ),
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: direction == 'Diya' ? 'Payment amount (full/partial)' : 'Refund received'),
          ),
          TextField(controller: noteController, decoration: const InputDecoration(labelText: 'Note (optional)')),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today),
            label: Text('Date: ${DateFormat('dd MMM yyyy').format(paymentDate)}'),
            onPressed: () async {
              final picked = await showDatePicker(
                context: ctx, initialDate: paymentDate,
                firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 3650)),
              );
              if (picked != null) setDialog(() => paymentDate = picked);
            },
          ),
          Text('Iske baad balance: ₹${(before + (direction == 'Diya' ? -n(controller.text) : n(controller.text))).toStringAsFixed(0)}'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            final value = double.tryParse(controller.text.trim()) ?? 0;
            final limit = direction == 'Diya' ? before.clamp(0, double.infinity).toDouble() : refundablePaid.clamp(0, double.infinity).toDouble();
            if (value <= 0 || value > limit + 0.009) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(content: Text('1 se ₹${limit.toStringAsFixed(0)} ke beech amount bharein')),
              );
              return;
            }
            Navigator.pop(ctx, {
              'amount': value,
              'direction': direction,
              'date': paymentDate,
              'note': noteController.text.trim(),
            });
          }, child: const Text('Save')),
        ],
      )),
    );
    controller.dispose();
    noteController.dispose();
    if (result == null) return;
    final rawAmount = (result['amount'] as num).toDouble();
    direction = result['direction'] as String;
    final signedAmount = direction == 'Diya' ? rawAmount : -rawAmount;
    final after = before - signedAmount;
    await StorageBackupService.instance.addRecord('khet', {
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'type': 'KHET_PURCHASE_PAYMENT',
      'vendorId': widget.vendorId,
      'vendorName': widget.vendorName,
      'amount': signedAmount,
      'direction': direction,
      'date': (result['date'] as DateTime).toIso8601String(),
      'note': result['note'],
      'allocationMethod': 'OLDEST_BILL_FIRST',
      'balanceBefore': before,
      'balanceAfter': after,
    });
    if (mounted) setState(() {});
  }

    @override
  Widget build(BuildContext context) {
    final bills = purchases
      ..sort((a, b) => (a['date'] ?? '').toString().compareTo((b['date'] ?? '').toString()));
    final paymentRows = payments
      ..sort((a, b) => (a['date'] ?? '').toString().compareTo((b['date'] ?? '').toString()));
    final bought = bills.fold<double>(0, (sum, row) => sum + n(row['totalAmount']));
    final paidAtPurchase = bills.fold<double>(0, (sum, row) => sum + n(row['paidAmount']));
    final paidLater = paymentRows.fold<double>(0, (sum, row) => sum + n(row['amount']));
    final money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(title: Text('${widget.vendorName} · Khata')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: ListTile(title: const Text('Total purchase'), trailing: Text(money.format(bought)))),
        Card(child: ListTile(title: const Text('Paid at purchase'), trailing: Text(money.format(paidAtPurchase)))),
        Card(child: ListTile(title: const Text('Payments later'), trailing: Text(money.format(paidLater)))),
        Card(child: ListTile(
          title: Text(balance >= 0 ? 'Net pending' : 'Advance'),
          trailing: Text(money.format(balance.abs()), style: TextStyle(fontWeight: FontWeight.bold, color: balance > 0 ? Colors.red : Colors.green)),
        )),
        const SizedBox(height: 10),
        const Text('Bills', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        ...bills.map((row) {
          final outstanding = (n(row['totalAmount']) - n(row['paidAmount'])).clamp(0, double.infinity);
          final date = DateTime.tryParse((row['invoiceDate'] ?? row['date'] ?? '').toString());
          return Card(child: ListTile(
            title: Text((row['title'] ?? 'Purchase').toString()),
            subtitle: Text('Bill ${money.format(n(row['totalAmount']))} · Paid ${money.format(n(row['paidAmount']))} · ${date == null ? '' : DateFormat('dd MMM yyyy').format(date)}'),
            trailing: Text(money.format(outstanding), style: TextStyle(color: outstanding > 0 ? Colors.red : Colors.green, fontWeight: FontWeight.bold)),
          ));
        }),
        const SizedBox(height: 12),
        const Text('Payment history', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        if (paymentRows.isEmpty) const Padding(
          padding: EdgeInsets.all(12),
          child: Text('Abhi koi later payment record nahi hai.'),
        ),
        ...paymentRows.reversed.map((row) {
          final date = DateTime.tryParse((row['date'] ?? '').toString());
          final before = row['balanceBefore'] == null ? null : n(row['balanceBefore']);
          final after = row['balanceAfter'] == null ? null : n(row['balanceAfter']);
          return Card(child: ListTile(
            leading: const Icon(Icons.payments_outlined),
            title: Text('${row['direction'] == 'Liya' ? 'Refund received' : 'Payment given'} ${money.format(n(row['amount']).abs())}'),
            subtitle: Text('${date == null ? '' : DateFormat('dd MMM yyyy').format(date)}${before == null || after == null ? '' : '\nPehle baki ${money.format(before)} · Baad mein baki ${money.format(after)}'}${(row['note'] ?? '').toString().trim().isEmpty ? '' : '\n${row['note']}'}'),
          ));
        }),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: pay,
        icon: const Icon(Icons.payments),
        label: const Text('Full / Partial Payment'),
      ),
    );
  }
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
