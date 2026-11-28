import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/history_projection.dart';
import '../services/storage_backup_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _storage = StorageBackupService.instance;
  final _search = TextEditingController();
  String _filter = 'All';

  List<HistoryEntry> _items() {
    final all = HistoryProjection.build(
      hisabs: _storage.records('hisabs'),
      khet: _storage.records('khet'),
      members: _storage.records('members'),
      products: _storage.records('products'),
    );
    final query = _search.text.trim().toLowerCase();
    return all.where((item) =>
      (_filter == 'All' || item.type == _filter) &&
      ('${item.type} ${item.title} ${item.subtitle}').toLowerCase().contains(query)
    ).toList();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

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
            children: filters.map((filter) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(filter),
                selected: _filter == filter,
                onSelected: (_) => setState(() => _filter = filter),
              ),
            )).toList(),
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
                    final dateText = item.date == null
                        ? 'Date unavailable'
                        : DateFormat('dd MMM yyyy · hh:mm a').format(item.date!);
                    final subtitle = item.subtitle.isEmpty
                        ? dateText
                        : '${item.subtitle}\n$dateText';
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
