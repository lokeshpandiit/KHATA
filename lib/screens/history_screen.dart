import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/storage_backup_service.dart';
import '../widgets/khata_widgets.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _storage = StorageBackupService.instance;
  final _search = TextEditingController();
  String _filter = 'All';

  DateTime _date(Map<String, dynamic> row) {
    for (final key in ['date', 'createdAt', 'updatedAt']) {
      final value = row[key];
      if (value is String) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) return parsed;
      }
    }
    return DateTime.now();
  }

  String _str(dynamic value) => cleanDisplayText(value).trim();
  String _minutes(dynamic value) {
    final m = value is int ? value : int.tryParse('$value') ?? 0;
    return m >= 60 ? '${m ~/ 60} hr ${m % 60} min' : '$m min';
  }

  List<_Item> _items() {
    final all = <_Item>[];
    void addPaymentRows(Map<String, dynamic> r, String type, String baseTitle) {
      final payments = r['payments'];
      if (payments is! List) return;
      for (final p in payments.whereType<Map>()) {
        final paymentDate = DateTime.tryParse((p['date'] ?? '').toString()) ?? DateTime.now();
        final amount = p['amount'];
        final direction = _str(p['direction']);
        final note = _str(p['note']);
        final balance = p['balanceAfter'];
        all.add(_Item(type, 'Payment · $baseTitle', [
          direction, if (amount != null && amount.toString().isNotEmpty) '₹$amount',
          if (balance != null) 'Remaining ₹$balance', if (note.isNotEmpty) note,
        ].where((s)=>s.isNotEmpty).join(' · '), paymentDate));
      }
    }
    for (final r in _storage.records('hisabs')) {
      final title = _str(r['title']).isEmpty ? _str(r['category']) : _str(r['title']);
      // Standalone person-to-person payments are individual history events.
      if (r['paymentKind'] == 'PERSON_PAYMENT' || r['entryType'] == 'PAYMENT') {
        final person = _str(r['personName']);
        final paymentTitle = _str(r['title']).isNotEmpty ? _str(r['title']) : (r['direction'] == 'PAID' ? 'आपने पैसे दिए' : 'आपको पैसे मिले');
        final amount = _str(r['amount']);
        final balance = r['balanceAfter'];
        all.add(_Item('HISAB', '$paymentTitle${person.isNotEmpty ? ' · $person' : ''}', [
          if (_str(r['direction']).isNotEmpty) _str(r['direction']),
          if (amount.isNotEmpty) '₹$amount',
          if (balance != null) 'Balance ₹$balance',
          if (_str(r['note']).isNotEmpty) _str(r['note']),
        ].where((s)=>s.isNotEmpty).join(' · '), _date(r)));
        continue;
      }
      all.add(_Item('HISAB', title,
        [_str(r['category']), if (_str(r['amount']).isNotEmpty) '₹${r['amount']}', _str(r['note'])].where((s)=>s.isNotEmpty).join(' · '), _date(r)));
      addPaymentRows(r, 'HISAB', title);
    }
    for (final r in _storage.records('khet')) {
      final water = r.containsKey('source') || r.containsKey('minutes') || r.containsKey('direction');
      final type = water ? 'PANI' : 'KHET';
      final title = water ? '${_str(r['contact']).isEmpty ? 'Pani' : _str(r['contact'])} · ${_str(r['source'])}' : (_str(r['title']).isEmpty ? _str(r['type']) : _str(r['title']));
      all.add(_Item(type, title,
        water ? '${_str(r['direction'])} · ${_minutes(r['minutes'])}' : [_str(r['type']), if (_str(r['price']).isNotEmpty) '₹${r['price']}', _str(r['note'])].where((s)=>s.isNotEmpty).join(' · '), _date(r)));
      addPaymentRows(r, type, title);
    }
    for (final r in _storage.records('members')) {
      final docs = (r['documents'] as List? ?? []).length;
      all.add(_Item('DOCUMENTS', 'Member · ${_str(r['name'])}', docs == 0 ? 'Member record' : '$docs document(s)', _date(r)));
    }
    for (final r in _storage.records('products')) {
      all.add(_Item('DOCUMENTS', 'Product · ${_str(r['name'])}', _str(r['note']), _date(r)));
    }
    all.sort((a,b)=>b.date.compareTo(a.date));
    final q=_search.text.trim().toLowerCase();
    return all.where((i)=>(_filter=='All'||i.type==_filter)&&('${i.type} ${i.title} ${i.subtitle}').toLowerCase().contains(q)).toList();
  }

  @override
  void dispose(){_search.dispose();super.dispose();}
  @override
  Widget build(BuildContext context) {
    final rows = _items();
    const filters = ['All', 'HISAB', 'KHET', 'PANI', 'DOCUMENTS'];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search history',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _search.clear()),
                    ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: filters
                .map(
                  (f) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(f),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('No history records found'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final item = rows[index];
                    final icon = switch (item.type) {
                      'HISAB' => Icons.receipt_long_outlined,
                      'KHET' => Icons.agriculture_outlined,
                      'PANI' => Icons.water_drop_outlined,
                      _ => Icons.folder_outlined,
                    };
                    final subtitle = item.subtitle.isEmpty
                        ? DateFormat('dd MMM yyyy · hh:mm a').format(item.date)
                        : '${item.subtitle}\n${DateFormat('dd MMM yyyy · hh:mm a').format(item.date)}';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: CircleAvatar(child: Icon(icon)),
                        title: Text(
                          item.title.isEmpty ? item.type : item.title,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(subtitle),
                        isThreeLine: item.subtitle.isNotEmpty,
                        trailing: Text(
                          item.type,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _Item {
  _Item(this.type,this.title,this.subtitle,this.date);
  final String type,title,subtitle;
  final DateTime date;
}
