import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/storage_backup_service.dart';

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

  @override
  Widget build(BuildContext context) {
    final storage = StorageBackupService.instance;
    final hisabs = storage.records('hisabs');
    final khet = storage.records('khet');
    final now = DateTime.now();
    bool thisMonth(Map<String, dynamic> row) {
      final date = _date(row);
      return date != null && date.year == now.year && date.month == now.month;
    }
    bool today(Map<String, dynamic> row) {
      final date = _date(row);
      return date != null && date.year == now.year && date.month == now.month && date.day == now.day;
    }
    final monthHisabAmount = hisabs.where(thisMonth).fold<double>(0, (sum, row) => sum + _amount(row['amount']));
    final monthKhetAmount = khet.where(thisMonth).where((row) => row['type'] != 'PANI').fold<double>(0, (sum, row) => sum + _amount(row['price']));
    final monthPani = khet.where(thisMonth).where((row) => row['type'] == 'PANI').fold<int>(0, (sum, row) => sum + ((row['minutes'] as num?)?.toInt() ?? int.tryParse('${row['minutes']}') ?? 0));
    final todayCount = hisabs.where(today).length + khet.where(today).length;
    final recent = <_Recent>[];
    for (final row in hisabs) {
      recent.add(_Recent('HISAB', (row['title'] ?? row['category'] ?? 'Hisab').toString(), _amount(row['amount']), _date(row)));
    }
    for (final row in khet) {
      recent.add(_Recent(row['type'] == 'PANI' ? 'PANI' : 'KHET', (row['title'] ?? row['contact'] ?? row['type'] ?? 'Khet').toString(), _amount(row['price']), _date(row)));
    }
    recent.sort((a, b) => (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)));
    final money = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Namaste, ${storage.senderName} 👋', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(DateFormat('EEEE, dd MMMM yyyy').format(now), style: const TextStyle(color: Colors.black54)),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _MetricCard(title: 'Today records', value: todayCount.toString(), icon: Icons.today, tint: const Color(0xFFE5F2EC))),
          const SizedBox(width: 10),
          Expanded(child: _MetricCard(title: 'This month Hisab', value: money.format(monthHisabAmount), icon: Icons.receipt_long, tint: const Color(0xFFEAF0FA))),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _MetricCard(title: 'Khet expenses', value: money.format(monthKhetAmount), icon: Icons.agriculture, tint: const Color(0xFFF8EEDC))),
          const SizedBox(width: 10),
          Expanded(child: _MetricCard(title: 'Pani total', value: '${monthPani ~/ 60}h ${monthPani % 60}m', icon: Icons.water_drop, tint: const Color(0xFFE7F3FA))),
        ]),
        const SizedBox(height: 22),
        const Text('This month at a glance', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
          _SummaryLine(label: 'Hisab records', value: hisabs.where(thisMonth).length.toString()),
          const Divider(height: 18),
          _SummaryLine(label: 'Khet records', value: khet.where(thisMonth).where((r) => r['type'] != 'PANI').length.toString()),
          const Divider(height: 18),
          _SummaryLine(label: 'Pani entries', value: khet.where(thisMonth).where((r) => r['type'] == 'PANI').length.toString()),
          const Divider(height: 18),
          _SummaryLine(label: 'Combined expenses', value: money.format(monthHisabAmount + monthKhetAmount), bold: true),
        ]))),
        const SizedBox(height: 22),
        const Text('Recent activity', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (recent.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No records yet. Add your first entry in HISAB or KHET.'))),
        ...recent.take(8).map((item) => Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(child: Icon(item.type == 'HISAB' ? Icons.receipt_long : item.type == 'PANI' ? Icons.water_drop : Icons.agriculture)),
            title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${item.type} · ${item.date == null ? 'Date unavailable' : DateFormat('dd MMM, hh:mm a').format(item.date!)}'),
            trailing: item.amount > 0 ? Text(money.format(item.amount), style: const TextStyle(fontWeight: FontWeight.w700)) : null,
          ),
        )),
      ],
    );
  }
}

class _Recent {
  _Recent(this.type, this.title, this.amount, this.date);
  final String type, title;
  final double amount;
  final DateTime? date;
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
