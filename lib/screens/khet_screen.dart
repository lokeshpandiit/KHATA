import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../services/contact_picker_service.dart';
import '../services/khata_sharing_service.dart';
import '../services/storage_backup_service.dart';
import '../widgets/khata_widgets.dart';
import '../widgets/plot_selector.dart';
import '../widgets/farm_fields.dart';
import '../services/farm_reminder_service.dart';
import '../widgets/farm_fields.dart';

class KhetScreen extends StatefulWidget {
  const KhetScreen({super.key});

  @override
  State<KhetScreen> createState() => _KhetScreenState();
}

class _KhetScreenState extends State<KhetScreen> {
  final _storage = StorageBackupService.instance;
  final _search = TextEditingController();
  String _tab = 'ALL';
  String _month = 'All months';
  String _seasonFilter = 'All seasons';
  int? _yearFilter;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _entries => _storage.records('khet');
  List<Map<String, dynamic>> get _contacts => _storage.records('contacts');

  String _plotLabel(dynamic id) => plotLabelForId(_storage, id);

  double _amount(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString().replaceAll(',', '').replaceAll('₹', '').trim()) ?? 0;
  }

  double _balance(Map<String, dynamic> row) {
    final value = row['balance'];
    if (value is num) return value.toDouble();
    return (_amount(row['totalAmount'] ?? row['price']) - _amount(row['paidAmount']))
        .clamp(0, double.infinity).toDouble();
  }

  List<Map<String, dynamic>> get _filtered {
    final query = _search.text.trim().toLowerCase();
    return _entries.where((row) {
      final date = DateTime.tryParse(row['date'] as String? ?? '');
      final category = row['type'] as String? ?? '';
      final isPending = category == 'TRACTOR' && _balance(row) > 0;
      final typeMatch = _tab == 'ALL' ||
          (_tab == 'PENDING' ? isPending : category == _tab);
      final monthMatch = _month == 'All months' ||
          (date != null && monthKey(date) == _month);
      final seasonMatch = _seasonFilter == 'All seasons' || row['season'] == _seasonFilter;
      final yearMatch = _yearFilter == null || row['year'] == _yearFilter;
      final searchable =
          '${row['title'] ?? ''} ${row['note'] ?? ''} ${row['contact'] ?? ''} ${row['source'] ?? ''} ${row['customerName'] ?? ''} ${row['farmName'] ?? ''} ${row['work'] ?? ''} ${row['cropName'] ?? ''} ${row['seedName'] ?? ''} ${row['purpose'] ?? ''}'
              .toLowerCase();
      return typeMatch && monthMatch && seasonMatch && yearMatch && searchable.contains(query);
    }).toList()
      ..sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
  }

  Future<void> _addEntry() async {
    if (_tab == 'ALL') {
      await _chooseEntryType();
    } else if (_tab == 'PENDING') {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const AddTractorWorkScreen(),
      ));
    } else if (_tab == 'PANI') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const AddPaniScreen()),
      );
    } else if (_tab == 'TRACTOR') {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const AddTractorWorkScreen(),
      ));
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AddKhetItemScreen(type: _tab),
        ),
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _chooseEntryType() async {
    final type = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: ['DAWAI', 'FASAL', 'HARA_BEEJ', 'PANI', 'TRACTOR', 'OTHER']
              .map((item) => ListTile(
                    leading: Icon(item == 'TRACTOR' ? Icons.agriculture : Icons.add_circle_outline),
                    title: Text(item),
                    onTap: () => Navigator.pop(context, item),
                  ))
              .toList(),
        ),
      ),
    );
    if (type == null || !mounted) return;
    setState(() => _tab = type);
    await _addEntry();
  }

  Future<void> _addContact() async {
    try {
      final picked = await ContactPickerService.pickPhoneContact();
      if (picked == null) return;
      final phone = KhataSharingService.normalizePhone(picked['phone']!);
      final existing = _contacts.where(
        (item) => KhataSharingService.normalizePhone((item['phone'] ?? '').toString()) == phone,
      );
      if (existing.isEmpty) {
        final now = DateTime.now();
        await _storage.addRecord('contacts', {
          'id': now.microsecondsSinceEpoch.toString(),
          'name': picked['name'],
          'phone': picked['phone'],
          'date': now.toIso8601String(),
        });
      }
      if (mounted) setState(() {});
    } catch (error) {
      _error('Could not pick contact: $error');
    }
  }

  void _error(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _sharePani(Map<String, dynamic> row) async {
    final date = DateTime.tryParse(row['date'] as String? ?? '');
    final contact = _contacts.where((item) => item['id'] == row['contactId']).toList();
    final phone = (row['contactPhone'] ?? (contact.isEmpty ? null : contact.first['phone']))?.toString();
    final note = (row['note'] as String? ?? '').trim();
    var includeNote = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Share Pani Hisab'),
          content: CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: includeNote,
            onChanged: note.isEmpty
                ? null
                : (value) => setDialogState(() => includeNote = value ?? false),
            title: const Text('Note bhi bhejna hai?'),
            subtitle: Text(
              note.isEmpty ? 'Is entry mein koi note nahi hai.' : note,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Share'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    await KhataSharingService.share(
      phone: phone,
      text: [
        'Pani Hisab - ${_storage.senderName}',
        'Source: ${row['source']}',
        'Kaam: ${row['direction']} / ${formatMinutes((row['minutes'] as num?)?.toInt() ?? 0)}',
        if (row['plotId'] != null && _plotLabel(row['plotId']).isNotEmpty) 'Killa: ${_plotLabel(row['plotId'])}',
        if (row['wetKyaris'] != null) 'Kyari: ${row['wetKyaris']} bheegi, ${row['remainingKyaris']} baaki',
        if (row['season'] != null || row['year'] != null) 'Season: ${row['season'] ?? ''} ${row['year'] ?? ''}',
        if (date != null) 'Date: ${dateLabel(date)}',
        if (includeNote && note.isNotEmpty) 'Note: $note',
      ].join('\n'),
    );
  }

  Future<void> _shareKhet(Map<String, dynamic> row) async {
    final date = DateTime.tryParse(row['date'] as String? ?? '');
    final files = _paths(row, 'itemPhotos', 'itemPhoto') +
        _paths(row, 'billPhotos', 'billPhoto');
    await KhataSharingService.share(
      text: [
        'Khet Hisab - ${_storage.senderName}',
        'Type: ${row['type']}',
        if (row['plotId'] != null && _plotLabel(row['plotId']).isNotEmpty) 'Killa: ${_plotLabel(row['plotId'])}',
        if (row['season'] != null || row['year'] != null) 'Season: ${row['season'] ?? ''} ${row['year'] ?? ''}',
        if (row['purpose'] != null) 'Dawai type: ${row['purpose']}',
        if (row['cropAtUse'] != null) 'Current crop: ${row['cropAtUse']}',
        if (row['kyariNumber'] != null) 'Kyari: ${row['kyariNumber']}',
        if ((row['title'] as String? ?? '').isNotEmpty) 'Name: ${row['title']}',
        if ((row['price'] as String? ?? '').isNotEmpty) 'Price: ₹${row['price']}',
        if ((row['note'] as String? ?? '').isNotEmpty) 'Note: ${row['note']}',
        if (date != null) 'Date: ${dateLabel(date)} ${timeLabel(date)}',
      ].join('\n'),
      files: files,
    );
  }

  List<String> _paths(Map<String, dynamic> row, String listKey, String legacyKey) {
    final list = (row[listKey] as List? ?? const []).whereType<String>().toList();
    final legacy = row[legacyKey];
    if (legacy is String && legacy.isNotEmpty && !list.contains(legacy)) list.insert(0, legacy);
    return list.where((path) => File(path).existsSync()).toList();
  }

  Future<void> _shareTractor(Map<String, dynamic> row) async {
    final due = DateTime.tryParse(row['dueDate'] as String? ?? '');
    final files = (_paths(row, 'billPhotos', 'billPhoto') +
        _paths(row, 'itemPhotos', 'itemPhoto')).toSet().toList();
    await KhataSharingService.share(
      phone: row['customerPhone'] as String?,
      text: [
        'TRACTOR WORK BILL - ${_storage.senderName}',
        'Customer: ${row['customerName'] ?? ''}',
        'Field: ${row['farmName'] ?? ''}',
        if (row['plotId'] != null && _plotLabel(row['plotId']).isNotEmpty) 'Killa: ${_plotLabel(row['plotId'])}',
        'Work: ${row['work'] ?? ''}',
        'Total: ₹${row['totalAmount'] ?? 0}',
        'Paid: ₹${row['paidAmount'] ?? 0}',
        'Pending: ₹${_balance(row).toStringAsFixed(0)}',
        if (due != null) 'Payment due by: ${DateFormat('dd MMM yyyy').format(due)}',
      ].join('\n'),
      files: files,
    );
  }

  Future<void> _shareNet(Map<String, dynamic> contact) async {
    final contactId = contact['id'];
    final matching = _entries.where(
      (row) => row['type'] == 'PANI' && row['contactId'] == contactId,
    );
    final balances = {'Tubewell': 0, 'Nahar': 0};
    for (final row in matching) {
      final source = row['source'] as String? ?? 'Tubewell';
      final minutes = (row['minutes'] as num?)?.toInt() ?? 0;
      final delta = row['direction'] == 'Diya' ? minutes : -minutes;
      balances[source] = (balances[source] ?? 0) + delta;
    }
    await KhataSharingService.share(
      phone: contact['phone'] as String?,
      text: [
        'Pani Net Hisab - ${_storage.senderName}',
        'Tubewell: ${formatSignedMinutes(balances['Tubewell'] ?? 0)}',
        'Nahar: ${formatSignedMinutes(balances['Nahar'] ?? 0)}',
      ].join('\n'),
    );
  }

  Future<void> _recordTractorPayment(Map<String, dynamic> row) async {
    final controller = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add received payment'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Received amount (₹)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(controller.text.trim());
              if (value != null && value > 0) Navigator.pop(dialogContext, value);
            },
            child: const Text('Save payment'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (amount == null) return;
    final total = _amount(row['totalAmount'] ?? row['price']);
    final oldPaid = _amount(row['paidAmount']);
    final oldBalance = (total - oldPaid).clamp(0, double.infinity).toDouble();
    if (amount > oldBalance) {
      _error('Payment cannot be greater than pending balance ₹${oldBalance.toStringAsFixed(0)}');
      return;
    }
    final paid = oldPaid + amount;
    final balance = (total - paid).clamp(0, double.infinity).toDouble();
    final updated = Map<String, dynamic>.from(row)
      ..['paidAmount'] = paid
      ..['balance'] = balance
      ..['status'] = balance <= 0 ? 'PAID' : (paid > 0 ? 'PARTIAL' : 'PENDING')
      ..['payments'] = [
        ...(row['payments'] as List? ?? const []),
        {'amount': amount, 'date': DateTime.now().toIso8601String()},
      ]
      ..['updatedAt'] = DateTime.now().toIso8601String();
    await _storage.updateRecord('khet', row['id'] as String, updated);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final months = availableMonths(_entries);
    if (!months.contains(_month)) _month = 'All months';
    final rows = _filtered;
    const tabs = ['ALL', 'DAWAI', 'FASAL', 'PANI', 'TRACTOR', 'OTHER', 'PENDING'];
    final addLabel = switch (_tab) {
      'DAWAI' => 'Add Dawai',
      'FASAL' => 'Add Fasal',
      'HARA_BEEJ' => 'Add Hara Beej',
      'PANI' => 'Add Pani',
      'TRACTOR' || 'PENDING' => 'Add Tractor',
      'OTHER' => 'Add Other',
      _ => 'Add Khet',
    };
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Column(
              children: [
                searchField((_) => setState(() {})),
                const SizedBox(height: 10),
                monthFilter(_month, months, (value) {
                  if (value != null) setState(() => _month = value);
                }),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: DropdownButtonFormField<String>(
                    initialValue: _seasonFilter,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Season', isDense: true),
                    items: const [
                      DropdownMenuItem(value: 'All seasons', child: Text('All seasons')),
                      DropdownMenuItem(value: 'Rabi', child: Text('Rabi')),
                      DropdownMenuItem(value: 'Kharif', child: Text('Kharif')),
                    ],
                    onChanged: (value) => setState(() => _seasonFilter = value ?? 'All seasons'),
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: DropdownButtonFormField<int?>(
                    initialValue: _yearFilter,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Year', isDense: true),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('All years')),
                      ...List.generate(9, (i) => DateTime.now().year - 3 + i)
                        .map((year) => DropdownMenuItem<int?>(value: year, child: Text(year.toString()))),
                    ],
                    onChanged: (value) => setState(() => _yearFilter = value),
                  )),
                ]),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: tabs.map((tab) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(tab),
                        selected: _tab == tab,
                        onSelected: (_) => setState(() => _tab = tab),
                      ),
                    )).toList(),
                  ),
                ),
              ],
            ),
          ),
          if (_tab == 'PANI')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _addContact,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('+ Pick Phone Contact'),
                ),
              ),
            ),
          if (_tab == 'PANI' && _contacts.isNotEmpty)
            SizedBox(
              height: 54,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                children: _contacts.map((contact) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    avatar: const Icon(Icons.account_balance_wallet_outlined),
                    label: Text('Net: ${contact['name']}'),
                    onPressed: () => _shareNet(contact),
                  ),
                )).toList(),
              ),
            ),
          Expanded(
            child: rows.isEmpty
                ? emptyState(
                    _tab == 'PENDING' ? 'No pending payments' : 'No Khet entries',
                    _tab == 'PENDING' ? 'Tractor work balances will appear here.' : 'Add farm and water records here.',
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                    children: _buildGroups(rows),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addEntry,
        icon: const Icon(Icons.add),
        label: Text(addLabel),
      ),
    );
  }

  List<Widget> _buildGroups(List<Map<String, dynamic>> rows) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final date = DateTime.tryParse(row['date'] as String? ?? '');
      final label = date == null ? 'Date unavailable' : dateLabel(date);
      groups.putIfAbsent(label, () => []).add(row);
    }
    return groups.entries.expand((group) => [
      Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Text(group.key, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF176B52))),
      ),
      ...group.value.map(_entryCard),
    ]).toList();
  }

  Widget _entryCard(Map<String, dynamic> row) {
    if (row['type'] == 'PANI') {
      final date = DateTime.tryParse(row['date'] as String? ?? '');
      return Card(
        margin: const EdgeInsets.only(bottom: 9),
        child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.water_drop)),
          title: Text([
            (row['contact'] ?? 'Contact').toString(),
            (row['source'] ?? '').toString(),
            (row['direction'] ?? '').toString(),
            if (row['plotId'] != null) _plotLabel(row['plotId']),
          ].where((part) => part.isNotEmpty).join(' · ')),
          subtitle: Text(
            '${formatMinutes((row['minutes'] as num?)?.toInt() ?? 0)}'
            '${row['wetKyaris'] == null ? '' : '\nBheegi: ${row['wetKyaris']} / ${row['totalKyarisSnapshot'] ?? '-'} · Baaki: ${row['remainingKyaris'] ?? '-'}'}'
            '${row['season'] == null ? '' : '\n${row['season']} ${row['year'] ?? ''}'}'
            '${(row['note'] as String? ?? '').isNotEmpty ? '\n${row['note']}' : ''}'
            '${date == null ? '' : '\n${timeLabel(date)}'}',
          ),
          isThreeLine: (row['note'] as String? ?? '').isNotEmpty,
          trailing: IconButton(
            tooltip: 'Share Pani hisab',
            onPressed: () => _sharePani(row),
            icon: const Icon(Icons.share_outlined),
          ),
        ),
      );
    }
    if (row['type'] == 'TRACTOR') {
      final due = DateTime.tryParse(row['dueDate'] as String? ?? '');
      final balance = _balance(row);
      final photos = _paths(row, 'itemPhotos', 'itemPhoto');
      return Card(
        margin: const EdgeInsets.only(bottom: 9),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const CircleAvatar(child: Icon(Icons.agriculture)),
              const SizedBox(width: 10),
              Expanded(child: Text((row['customerName'] ?? 'Customer').toString(),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
              Text(balance <= 0 ? 'PAID' : (balance < _amount(row['totalAmount']) ? 'PARTIAL' : 'PENDING'),
                style: TextStyle(fontWeight: FontWeight.w800, color: balance <= 0 ? Colors.green : Colors.red)),
            ]),
            const SizedBox(height: 6),
            Text('Field: ${row['farmName'] ?? '-'}'),
            if (row['plotId'] != null && _plotLabel(row['plotId']).isNotEmpty)
              Text('Killa: ${_plotLabel(row['plotId'])}'),
            Text('Work: ${row['work'] ?? '-'}'),
            const SizedBox(height: 8),
            Wrap(spacing: 12, runSpacing: 6, children: [
              Text('Total ₹${_amount(row['totalAmount']).toStringAsFixed(0)}'),
              Text('Paid ₹${_amount(row['paidAmount']).toStringAsFixed(0)}', style: const TextStyle(color: Colors.green)),
              Text('Pending ₹${balance.toStringAsFixed(0)}', style: TextStyle(color: balance > 0 ? Colors.red : Colors.green, fontWeight: FontWeight.w800)),
            ]),
            if (due != null)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text('Due date: ${DateFormat('dd MMM yyyy').format(due)}',
                  style: TextStyle(
                    color: due.isBefore(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)) && balance > 0
                        ? Colors.red : Colors.black54,
                  )),
              ),
            if (photos.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(spacing: 6, children: photos.take(5).map((path) => InkWell(
                  onTap: () => _preview(path),
                  child: mediaThumbnail(path, size: 58),
                )).toList()),
              ),
            const Divider(height: 20),
            Wrap(spacing: 8, children: [
              OutlinedButton.icon(
                onPressed: () => _shareTractor(row),
                icon: const Icon(Icons.share_outlined),
                label: const Text('WhatsApp Bill'),
              ),
              if (balance > 0)
                FilledButton.tonalIcon(
                  onPressed: () => _recordTractorPayment(row),
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Add Payment'),
                ),
            ]),
          ]),
        ),
      );
    }
    final date = DateTime.tryParse(row['date'] as String? ?? '');
    final photos = _paths(row, 'itemPhotos', 'itemPhoto') +
        _paths(row, 'billPhotos', 'billPhoto');
    final visiblePhotos = photos.toSet().toList();
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row['title'] as String? ?? row['type'] as String,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (row['plotId'] != null && _plotLabel(row['plotId']).isNotEmpty)
                    Text(_plotLabel(row['plotId']), style: const TextStyle(color: Colors.black54, fontSize: 12)),
                  if ((row['price'] ?? '').toString().isNotEmpty && row['price'] != 0) Text('₹${row['price']}'),
                  if (row['season'] != null || row['year'] != null)
                    Text('Season: ${row['season'] ?? ''} ${row['year'] ?? ''}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  if (row['type'] == 'FASAL' && row['sowingDate'] != null)
                    Text('Beejne ki date: ${dateLabel(DateTime.parse(row['sowingDate'] as String))}'),
                  if (row['type'] == 'HARA_BEEJ')
                    Text('Kyari: ${row['kyariNumber'] ?? '-'}'),
                  if (row['type'] == 'DAWAI') ...[
                    Text('Dawai: ${row['purpose'] ?? '-'}'),
                    Text('Us waqt fasal: ${row['cropAtUse'] ?? 'Not recorded'}'),
                    if (row['reminderDate'] is String)
                      Text('Reminder: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.parse(row['reminderDate'] as String))}', style: const TextStyle(color: Colors.deepOrange)),
                  ],
                  if ((row['note'] as String? ?? '').isNotEmpty) Text(row['note'] as String),
                  if (date != null)
                    Text('${timeLabel(date)} · ${row['type']}',
                      style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  if ((row['billPhoto'] as String? ?? '').isNotEmpty || (row['billPhotos'] as List? ?? []).isNotEmpty)
                    const Text('Bill photo attached', style: TextStyle(fontSize: 12)),
                  if (visiblePhotos.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Wrap(spacing: 6, runSpacing: 6, children: visiblePhotos.map((path) =>
                        InkWell(onTap: () => _preview(path), child: mediaThumbnail(path, size: 58)),
                      ).toList()),
                    ),
                ],
              ),
            ),
            IconButton(tooltip: 'Share', onPressed: () => _shareKhet(row), icon: const Icon(Icons.share_outlined)),
          ],
        ),
      ),
    );
  }

  void _preview(String path) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
        body: Center(child: InteractiveViewer(child: Image.file(File(path)))),
      ),
    ));
  }
}

String formatMinutes(int minutes) {
  final hours = minutes ~/ 60;
  final remaining = minutes % 60;
  if (hours == 0) return '$remaining min';
  if (remaining == 0) return '$hours hr';
  return '$hours hr $remaining min';
}

String formatSignedMinutes(int minutes) {
  final sign = minutes > 0 ? '+' : minutes < 0 ? '-' : '';
  return '$sign${formatMinutes(minutes.abs())}';
}

class AddPaniScreen extends StatefulWidget {
  const AddPaniScreen({this.initialPlotId, super.key});
  final String? initialPlotId;

  @override
  State<AddPaniScreen> createState() => _AddPaniScreenState();
}

class _AddPaniScreenState extends State<AddPaniScreen> {
  final _storage = StorageBackupService.instance;
  final _minutes = TextEditingController();
  final _wetKyaris = TextEditingController();
  final _note = TextEditingController();
  String? _contactId;
  String? _plotId;
  String _source = 'Tubewell';
  String _direction = 'Diya';
  String _season = 'Rabi';
  int _year = DateTime.now().year;
  DateTime _activityDate = DateTime.now();
  bool _saving = false;

  List<Map<String, dynamic>> get _contacts => _storage.records('contacts');

  Map<String, dynamic>? get _selectedPlot {
    final matches = _storage.records('plots').where((item) => item['id'] == _plotId);
    return matches.isEmpty ? null : matches.first;
  }

  int get _totalKyaris => (_selectedPlot?['totalKyaris'] as num?)?.toInt() ?? 0;
  int get _wetCount => int.tryParse(_wetKyaris.text.trim()) ?? 0;
  int get _remainingKyaris => (_totalKyaris - _wetCount).clamp(0, _totalKyaris);

  @override
  void initState() {
    super.initState();
    _plotId = widget.initialPlotId;
    if (_contacts.isNotEmpty) _contactId = _contacts.first['id'] as String;
  }

  @override
  void dispose() {
    _minutes.dispose();
    _wetKyaris.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickContact() async {
    try {
      final picked = await ContactPickerService.pickPhoneContact();
      if (picked == null) return;
      final phone = KhataSharingService.normalizePhone(picked['phone']!);
      final existing = _contacts.where((item) =>
        KhataSharingService.normalizePhone((item['phone'] ?? '').toString()) == phone).toList();
      if (existing.isNotEmpty) {
        setState(() => _contactId = existing.first['id'] as String);
      } else {
        final now = DateTime.now();
        final id = now.microsecondsSinceEpoch.toString();
        await _storage.addRecord('contacts', {
          'id': id, 'name': picked['name'], 'phone': picked['phone'],
          'date': now.toIso8601String(),
        });
        if (mounted) setState(() => _contactId = id);
      }
    } catch (error) {
      _error('Could not select phone contact: ' + error.toString());
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _activityDate,
      firstDate: DateTime(now.year - 8),
      lastDate: DateTime(now.year + 8),
    );
    if (picked != null && mounted) setState(() => _activityDate = picked);
  }

  void _error(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    final minutes = int.tryParse(_minutes.text.trim()) ?? 0;
    if (minutes <= 0) {
      _error('Enter a valid number of minutes');
      return;
    }
    if (_contactId == null) {
      _error('Pick a phone contact before saving Pani hisab');
      return;
    }
    if (_plotId == null || _selectedPlot == null) {
      _error('Select your killa for this water entry');
      return;
    }
    if (_totalKyaris <= 0) {
      _error('Map Edit mein pehle is kille ki total kyari set karein');
      return;
    }
    if (_wetCount <= 0 || _wetCount > _totalKyaris) {
      _error('Bheegi kyari 1 se ' + _totalKyaris.toString() + ' ke beech honi chahiye');
      return;
    }

    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final contact = _contacts.firstWhere((item) => item['id'] == _contactId);
      final entryDate = DateTime(
        _activityDate.year, _activityDate.month, _activityDate.day,
        now.hour, now.minute,
      );
      await _storage.addRecord('khet', {
        'id': now.microsecondsSinceEpoch.toString(),
        'type': 'PANI',
        'contactId': _contactId,
        'plotId': _plotId,
        'contact': contact['name'],
        'contactPhone': contact['phone'],
        'source': _source,
        'direction': _direction,
        'minutes': minutes,
        'wetKyaris': _wetCount,
        'totalKyarisSnapshot': _totalKyaris,
        'remainingKyaris': _remainingKyaris,
        'season': _season,
        'year': _year,
        'note': _note.text.trim(),
        'date': entryDate.toIso8601String(),
      });
      if (mounted) Navigator.pop(context);
    } catch (error) {
      _error('Could not save Pani hisab: ' + error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final contacts = _contacts;
    final selected = contacts.where((item) => item['id'] == _contactId).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Add Pani Hisab')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          OutlinedButton.icon(
            onPressed: _pickContact,
            icon: const Icon(Icons.contacts_outlined),
            label: Text(selected.isEmpty ? 'Pick from Phone Contacts' : selected.first['name'].toString() + ' · ' + (selected.first['phone'] ?? '').toString()),
          ),
          const SizedBox(height: 12),
          if (contacts.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: _contactId,
              decoration: const InputDecoration(labelText: 'Saved contact'),
              items: contacts.map((item) => DropdownMenuItem(
                value: item['id'] as String,
                child: Text(item['name'].toString() + (item['phone'] == null ? '' : ' · ' + item['phone'].toString())),
              )).toList(),
              onChanged: (value) => setState(() => _contactId = value),
            ),
          const SizedBox(height: 12),
          KhetPlotDropdown(selectedId: _plotId, onChanged: (value) {
            setState(() { _plotId = value; _wetKyaris.clear(); });
          }),
          const SizedBox(height: 8),
          Text(
            _selectedPlot == null
                ? 'Killa select karein. Total kyari map ke Edit option mein set hoti hain.'
                : 'Is kille mein total kyari: ' + _totalKyaris.toString(),
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _wetKyaris,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Is baar kitni kyari bheegi?',
              prefixIcon: Icon(Icons.water_drop_outlined),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(child: Text('Bheegi: ' + _wetCount.toString(), style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.w700))),
                  Expanded(child: Text('Baaki: ' + _remainingKyaris.toString(), style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.w700))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          SeasonYearFields(
            season: _season,
            year: _year,
            onSeasonChanged: (value) => setState(() => _season = value),
            onYearChanged: (value) => setState(() => _year = value),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_month_outlined),
            label: Text('Paani date: ' + DateFormat('dd MMM yyyy').format(_activityDate)),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _source,
            decoration: const InputDecoration(labelText: 'Pani Source'),
            items: ['Tubewell', 'Nahar'].map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
            onChanged: (value) => setState(() => _source = value ?? _source),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _direction,
            decoration: const InputDecoration(labelText: 'Len-Den'),
            items: ['Diya', 'Liya'].map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
            onChanged: (value) => setState(() => _direction = value ?? _direction),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _minutes,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Paani kitne minute chala?',
              helperText: 'Duration: ' + formatMinutes(int.tryParse(_minutes.text) ?? 0),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(controller: _note, minLines: 2, maxLines: 4,
            decoration: const InputDecoration(labelText: 'Note (jaise: shaam ko uski baari ke baad)')),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save Pani Hisab'),
          ),
        ],
      ),
    );
  }
}

class AddKhetItemScreen extends StatefulWidget {
  const AddKhetItemScreen({required this.type, this.initialPlotId, super.key});
  final String type;
  final String? initialPlotId;

  @override
  State<AddKhetItemScreen> createState() => _AddKhetItemScreenState();
}

class _AddKhetItemScreenState extends State<AddKhetItemScreen> {
  final _storage = StorageBackupService.instance;
  final _picker = ImagePicker();
  final _title = TextEditingController();
  final _price = TextEditingController();
  final _note = TextEditingController();
  final _kyariNumber = TextEditingController();
  final List<String> _itemPhotos = [];
  final List<String> _billPhotos = [];
  String? _plotId;
  String _season = 'Rabi';
  int _year = DateTime.now().year;
  String _purpose = 'Herbicide (ghas khatam karne wali)';
  DateTime _activityDate = DateTime.now();
  bool _reminderEnabled = false;
  DateTime? _reminderAt;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _plotId = widget.initialPlotId;
  }

  bool get _needsFarmDetails => ['FASAL', 'HARA_BEEJ', 'DAWAI'].contains(widget.type);
  String get _dateLabel => widget.type == 'FASAL' || widget.type == 'HARA_BEEJ'
      ? 'Beejne ki date' : 'Dawai dalne ki date';

  Map<String, dynamic>? get _currentCrop {
    if (_plotId == null) return null;
    final crops = _storage.records('khet')
        .where((row) => row['type'] == 'FASAL' && row['plotId'] == _plotId)
        .toList();
    crops.sort((a, b) =>
      (DateTime.tryParse(b['date'] as String? ?? '') ?? DateTime(0))
      .compareTo(DateTime.tryParse(a['date'] as String? ?? '') ?? DateTime(0)));
    return crops.isEmpty ? null : crops.first;
  }

  @override
  void dispose() {
    _title.dispose();
    _price.dispose();
    _note.dispose();
    _kyariNumber.dispose();
    super.dispose();
  }

  Future<void> _pickActivityDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _activityDate,
      firstDate: DateTime(now.year - 8),
      lastDate: DateTime(now.year + 8),
    );
    if (picked != null && mounted) setState(() => _activityDate = picked);
  }

  Future<void> _pickReminder() async {
    final now = DateTime.now();
    final initial = _reminderAt ?? now.add(const Duration(days: 7));
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 8),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_reminderAt ?? now.add(const Duration(days: 7))),
    );
    if (time == null || !mounted) return;
    setState(() => _reminderAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _pickPhotos(bool bill, ImageSource source) async {
    try {
      final images = source == ImageSource.gallery
          ? await _picker.pickMultiImage(imageQuality: 88)
          : [if (await _picker.pickImage(source: source, imageQuality: 88) case final image?) image];
      final target = bill ? _billPhotos : _itemPhotos;
      for (final image in images) {
        final path = await _storage.keepFile(image.path, folder: 'KhetPhotos');
        if (!target.contains(path)) target.add(path);
      }
      if (mounted) setState(() {});
    } catch (error) {
      _error('Could not save photos: ' + error.toString());
    }
  }

  Future<void> _pickBillFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: true);
      for (final item in result?.files ?? const []) {
        final path = item.path;
        if (path != null) {
          final saved = await _storage.keepFile(path, folder: 'KhetPhotos');
          if (!_billPhotos.contains(saved)) _billPhotos.add(saved);
        }
      }
      if (mounted) setState(() {});
    } catch (error) {
      _error('Could not save bill images: ' + error.toString());
    }
  }

  void _error(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _currentCropName() {
    final crop = _currentCrop;
    if (crop == null) return 'Is kille ke liye fasal ki entry nahi mili';
    final cropName = (crop['cropName'] ?? crop['title'] ?? 'Fasal').toString();
    final season = (crop['season'] ?? '').toString();
    final year = crop['year']?.toString() ?? '';
    return cropName + (season.isEmpty ? '' : ' · ' + season) + (year.isEmpty ? '' : ' ' + year);
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final price = double.tryParse(_price.text.trim()) ?? 0;
    if (title.isEmpty) {
      _error(widget.type == 'FASAL' ? 'Fasal ka naam likhein' : widget.type == 'DAWAI' ? 'Dawai ka naam likhein' : 'Naam likhein');
      return;
    }
    if (_needsFarmDetails && (_plotId == null || _plotId!.isEmpty)) {
      _error('Apna killa select karein');
      return;
    }
    if (widget.type == 'HARA_BEEJ' && _kyariNumber.text.trim().isEmpty) {
      _error('Hara beej wali kyari ka number/name likhein');
      return;
    }
    if (widget.type == 'DAWAI' && _reminderEnabled && _reminderAt == null) {
      _error('Reminder ke liye date aur time set karein');
      return;
    }
    if (widget.type == 'DAWAI' && _reminderEnabled && !_reminderAt!.isAfter(DateTime.now())) {
      _error('Reminder future date/time par set karein');
      return;
    }

    setState(() => _saving = true);
    final now = DateTime.now();
    final activityDate = DateTime(
      _activityDate.year, _activityDate.month, _activityDate.day, now.hour, now.minute);
    final recordId = now.microsecondsSinceEpoch.toString();
    final reminderId = int.parse(recordId) % 2000000000;
    final currentCrop = _currentCrop;
    final record = <String, dynamic>{
      'id': recordId,
      'type': widget.type,
      'plotId': _plotId,
      'title': title,
      'price': price,
      'note': _note.text.trim(),
      'itemPhoto': _itemPhotos.isEmpty ? null : _itemPhotos.first,
      'itemPhotos': _itemPhotos,
      'billPhoto': _billPhotos.isEmpty ? null : _billPhotos.first,
      'billPhotos': _billPhotos,
      'date': activityDate.toIso8601String(),
    };

    if (_needsFarmDetails) {
      record['season'] = _season;
      record['year'] = _year;
      record['activityDate'] = activityDate.toIso8601String();
    }
    if (widget.type == 'FASAL') {
      record['cropName'] = title;
      record['sowingDate'] = activityDate.toIso8601String();
    }
    if (widget.type == 'HARA_BEEJ') {
      record['seedName'] = title;
      record['kyariNumber'] = _kyariNumber.text.trim();
      record['sowingDate'] = activityDate.toIso8601String();
    }
    if (widget.type == 'DAWAI') {
      record['purpose'] = _purpose;
      record['cropAtUse'] = currentCrop == null
          ? 'Fasal record nahi hai'
          : (currentCrop['cropName'] ?? currentCrop['title'] ?? 'Fasal').toString();
      record['applicationDate'] = activityDate.toIso8601String();
      record['reminderDate'] = _reminderEnabled ? _reminderAt?.toIso8601String() : null;
      record['reminderId'] = _reminderEnabled ? reminderId : null;
    }

    try {
      await _storage.addRecord('khet', record);
      String? reminderError;
      if (widget.type == 'DAWAI' && _reminderEnabled && _reminderAt != null) {
        try {
          await FarmReminderService.schedule(
            id: reminderId,
            scheduledAt: _reminderAt!,
            title: 'KHATA: ' + title,
            body: 'Dawai dalni hai · ' + _purpose + ' · Killa: ' + plotLabel(_storage.records('plots').firstWhere((p) => p['id'] == _plotId)),
          );
        } catch (error) {
          reminderError = error.toString();
        }
      }
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context);
        if (reminderError != null) {
          messenger.showSnackBar(SnackBar(content: Text('Entry save ho gayi, reminder nahi laga: ' + reminderError)));
        }
      }
    } catch (error) {
      _error('Could not save Khet entry: ' + error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _photoButtons(String label, bool bill) {
    final paths = bill ? _billPhotos : _itemPhotos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        Wrap(spacing: 8, children: [
          TextButton.icon(onPressed: () => _pickPhotos(bill, ImageSource.camera),
            icon: const Icon(Icons.camera_alt_outlined), label: const Text('Camera')),
          TextButton.icon(onPressed: bill ? _pickBillFiles : () => _pickPhotos(bill, ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined), label: const Text('Add multiple photos')),
        ]),
        if (paths.isNotEmpty)
          Wrap(spacing: 6, runSpacing: 6, children: paths.map((path) => Stack(
            alignment: Alignment.topRight,
            children: [
              mediaThumbnail(path, size: 76),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => paths.remove(path)),
                icon: const Icon(Icons.cancel, color: Colors.red),
              ),
            ],
          )).toList()),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final farmPlot = _needsFarmDetails;
    final titleLabel = widget.type == 'FASAL' ? 'Fasal ka naam'
      : widget.type == 'HARA_BEEJ' ? 'Hara beej / chara ka naam'
      : widget.type == 'DAWAI' ? 'Dawai ka naam' : 'Title / Name';
    return Scaffold(
      appBar: AppBar(title: Text('Add ' + widget.type.replaceAll('_', ' '))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _title,
            decoration: InputDecoration(labelText: titleLabel),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 12),
          KhetPlotDropdown(selectedId: _plotId, onChanged: (value) => setState(() => _plotId = value)),
          if (farmPlot) ...[
            const SizedBox(height: 8),
            if (widget.type == 'DAWAI')
              Card(
                child: ListTile(
                  leading: const Icon(Icons.grass_outlined),
                  title: const Text('Is kille mein abhi kaunsi fasal hai?'),
                  subtitle: Text(_currentCropName()),
                ),
              ),
            if (widget.type == 'HARA_BEEJ') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _kyariNumber,
                decoration: const InputDecoration(labelText: 'Kaunsi kyari? (number / naam)'),
              ),
            ],
            if (widget.type == 'DAWAI') ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _purpose,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Dawai ka kaam'),
                items: const [
                  DropdownMenuItem(value: 'Herbicide (ghas khatam karne wali)', child: Text('Ghas khatam karne wali')),
                  DropdownMenuItem(value: 'Insecticide (keede ki dawa)', child: Text('Keede ki dawa')),
                  DropdownMenuItem(value: 'Fungicide (fungus ki dawa)', child: Text('Fungus ki dawa')),
                  DropdownMenuItem(value: 'Other spray', child: Text('Other spray')),
                ],
                onChanged: (value) => setState(() => _purpose = value ?? _purpose),
              ),
            ],
            const SizedBox(height: 12),
            SeasonYearFields(
              season: _season,
              year: _year,
              onSeasonChanged: (value) => setState(() => _season = value),
              onYearChanged: (value) => setState(() => _year = value),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickActivityDate,
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text(_dateLabel + ': ' + DateFormat('dd MMM yyyy').format(_activityDate)),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: widget.type == 'DAWAI' ? 'Dawai ka kharcha (₹)' : 'Price / kharcha (₹)',
            ),
          ),
          if (widget.type == 'DAWAI') ...[
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Is dawai ke liye future reminder lagayein'),
              value: _reminderEnabled,
              onChanged: (value) => setState(() {
                _reminderEnabled = value;
                if (!value) _reminderAt = null;
              }),
            ),
            if (_reminderEnabled)
              OutlinedButton.icon(
                onPressed: _pickReminder,
                icon: const Icon(Icons.notifications_active_outlined),
                label: Text(_reminderAt == null
                  ? 'Reminder date aur time chunein'
                  : 'Reminder: ' + DateFormat('dd MMM yyyy, hh:mm a').format(_reminderAt!)),
              ),
          ],
          const SizedBox(height: 12),
          TextField(controller: _note, minLines: 2, maxLines: 4,
            decoration: const InputDecoration(labelText: 'Note')),
          const SizedBox(height: 18),
          _photoButtons('Item Photos', false),
          const SizedBox(height: 12),
          _photoButtons('Bill Photos', true),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save ' + widget.type.replaceAll('_', ' ')),
          ),
        ],
      ),
    );
  }
}

class AddTractorWorkScreen extends StatefulWidget {
  const AddTractorWorkScreen({super.key});

  @override
  State<AddTractorWorkScreen> createState() => _AddTractorWorkScreenState();
}

class _AddTractorWorkScreenState extends State<AddTractorWorkScreen> {
  final _storage = StorageBackupService.instance;
  final _farm = TextEditingController();
  final _work = TextEditingController();
  final _total = TextEditingController();
  final _paid = TextEditingController(text: '0');
  final _note = TextEditingController();
  final _photos = <String>[];
  String? _customerName;
  String? _customerPhone;
  String? _plotId;
  DateTime? _dueDate;
  bool _saving = false;

  @override
  void dispose() {
    _farm.dispose();
    _work.dispose();
    _total.dispose();
    _paid.dispose();
    _note.dispose();
    super.dispose();
  }

  void _error(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickCustomer() async {
    try {
      final picked = await ContactPickerService.pickPhoneContact();
      if (picked != null && mounted) {
        setState(() {
          _customerName = picked['name'];
          _customerPhone = picked['phone'];
        });
      }
    } catch (error) {
      _error('Could not pick customer: $error');
    }
  }

  Future<void> _pickPhotos() async {
    try {
      final images = await _picker.pickMultiImage(imageQuality: 88);
      for (final image in images) {
        _photos.add(await _storage.keepFile(image.path, folder: 'KhetPhotos'));
      }
      if (mounted) setState(() {});
    } catch (error) {
      _error('Could not add bill photos: $error');
    }
  }

  final ImagePicker _picker = ImagePicker();

  Future<void> _selectDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null && mounted) setState(() => _dueDate = picked);
  }

  Future<void> _save() async {
    final total = double.tryParse(_total.text.trim()) ?? 0;
    final paid = double.tryParse(_paid.text.trim()) ?? 0;
    if ((_customerName ?? '').isEmpty || (_customerPhone ?? '').isEmpty) {
      _error('Pick customer from phone contacts');
      return;
    }
    if (_farm.text.trim().isEmpty || _work.text.trim().isEmpty || total <= 0 || paid < 0 || paid > total) {
      _error('Enter field, work and valid total/paid amount');
      return;
    }
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final balance = total - paid;
      await _storage.addRecord('khet', {
        'id': now.microsecondsSinceEpoch.toString(),
        'type': 'TRACTOR',
        'customerName': _customerName,
        'customerPhone': _customerPhone,
        'plotId': _plotId,
        'contact': _customerName,
        'farmName': _farm.text.trim(),
        'work': _work.text.trim(),
        'title': _work.text.trim(),
        'totalAmount': total,
        'price': total.toString(),
        'paidAmount': paid,
        'balance': balance,
        'status': balance <= 0 ? 'PAID' : (paid > 0 ? 'PARTIAL' : 'PENDING'),
        'dueDate': _dueDate?.toIso8601String(),
        'itemPhoto': _photos.isEmpty ? null : _photos.first,
        'itemPhotos': _photos,
        'billPhoto': _photos.isEmpty ? null : _photos.first,
        'billPhotos': _photos,
        'note': _note.text.trim(),
        'payments': paid > 0 ? [{'amount': paid, 'date': now.toIso8601String()}] : <Map<String, dynamic>>[],
        'date': now.toIso8601String(),
      });
      if (mounted) Navigator.pop(context);
    } catch (error) {
      _error('Could not save tractor work: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Add Tractor Work')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        OutlinedButton.icon(
          onPressed: _pickCustomer,
          icon: const Icon(Icons.contacts_outlined),
          label: Text(_customerName == null ? 'Pick Customer from Contacts' : '$_customerName · $_customerPhone'),
        ),
        const SizedBox(height: 12),
        TextField(controller: _farm, textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Which field / khet?')),
        const SizedBox(height: 12),
        KhetPlotDropdown(selectedId: _plotId, onChanged: (value) => setState(() => _plotId = value)),
        const SizedBox(height: 12),
        TextField(controller: _work, textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Work done (ploughing, rotavator, sowing...)')),
        const SizedBox(height: 12),
        TextField(controller: _total, keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Total bill amount (₹)')),
        const SizedBox(height: 12),
        TextField(controller: _paid, keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Already paid (₹)')),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _selectDueDate,
          icon: const Icon(Icons.event),
          label: Text(_dueDate == null ? 'Set payment due date (optional)' : 'Due: ${DateFormat('dd MMM yyyy').format(_dueDate!)}'),
        ),
        const SizedBox(height: 12),
        TextField(controller: _note, minLines: 2, maxLines: 4,
          decoration: const InputDecoration(labelText: 'Note (optional)')),
        const SizedBox(height: 12),
        OutlinedButton.icon(onPressed: _pickPhotos, icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Add bill / work photos')),
        if (_photos.isNotEmpty)
          Wrap(spacing: 6, children: _photos.map((path) => mediaThumbnail(path, size: 68)).toList()),
        const SizedBox(height: 22),
        FilledButton(onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save Tractor Work')),
      ],
    ),
  );
}
