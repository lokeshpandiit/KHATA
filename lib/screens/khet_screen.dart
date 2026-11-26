import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../services/storage_backup_service.dart';
import '../widgets/khata_widgets.dart';

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

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _entries => _storage.records('khet');
  List<Map<String, dynamic>> get _contacts => _storage.records('contacts');

  List<Map<String, dynamic>> get _filtered {
    final query = _search.text.trim().toLowerCase();
    return _entries.where((row) {
      final date = DateTime.tryParse(row['date'] as String? ?? '');
      final category = row['type'] as String? ?? '';
      final typeMatch = _tab == 'ALL' || category == _tab;
      final monthMatch = _month == 'All months' ||
          (date != null && monthKey(date) == _month);
      final searchable =
          '${row['title'] ?? ''} ${row['note'] ?? ''} ${row['contact'] ?? ''} ${row['source'] ?? ''}'
              .toLowerCase();
      return typeMatch && monthMatch && searchable.contains(query);
    }).toList()
      ..sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
  }

  Future<void> _addEntry() async {
    if (_tab == 'ALL') {
      await _chooseEntryType();
    } else if (_tab == 'PANI') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const AddPaniScreen()),
      );
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
          children: ['DAWAI', 'FASAL', 'PANI', 'OTHER']
              .map((item) => ListTile(
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
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Pani Contact'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Contact name'),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    final now = DateTime.now();
    await _storage.addRecord('contacts', {
      'id': now.microsecondsSinceEpoch.toString(),
      'name': name,
      'date': now.toIso8601String(),
    });
    if (mounted) setState(() {});
  }

  Future<void> _sharePani(Map<String, dynamic> row) async {
    final date = DateTime.tryParse(row['date'] as String? ?? '');
    await Share.share([
      'Pani Hisab - ${_storage.senderName}',
      'Source: ${row['source']}',
      'Kaam: ${row['direction']} / ${formatMinutes(row['minutes'] as int? ?? 0)}',
      if (date != null) 'Date: ${dateLabel(date)} ${timeLabel(date)}',
      if ((row['note'] as String? ?? '').isNotEmpty) 'Note: ${row['note']}',
    ].join('\n'));
  }

  Future<void> _shareKhet(Map<String, dynamic> row) async {
    final date = DateTime.tryParse(row['date'] as String? ?? '');
    final lines = [
      'Khet Hisab - ${_storage.senderName}',
      'Type: ${row['type']}',
      if ((row['title'] as String? ?? '').isNotEmpty) 'Name: ${row['title']}',
      if ((row['price'] as String? ?? '').isNotEmpty) 'Price: ₹${row['price']}',
      if ((row['note'] as String? ?? '').isNotEmpty) 'Note: ${row['note']}',
      if (date != null) 'Date: ${dateLabel(date)} ${timeLabel(date)}',
    ];
    final files = [
      row['itemPhoto'] as String?,
      row['billPhoto'] as String?,
    ].whereType<String>().where((path) => File(path).existsSync());
    await Share.shareXFiles(files.map(XFile.new).toList(), text: lines.join('\n'));
  }

  Future<void> _shareNet(Map<String, dynamic> contact) async {
    final contactId = contact['id'];
    final matching = _entries.where(
      (row) => row['type'] == 'PANI' && row['contactId'] == contactId,
    );
    final balances = {'Tubewell': 0, 'Nahar': 0};
    for (final row in matching) {
      final source = row['source'] as String? ?? 'Tubewell';
      final minutes = row['minutes'] as int? ?? 0;
      final delta = row['direction'] == 'Diya' ? minutes : -minutes;
      balances[source] = (balances[source] ?? 0) + delta;
    }
    await Share.share([
      'Pani Net Hisab - ${_storage.senderName}',
      'Tubewell: ${formatSignedMinutes(balances['Tubewell'] ?? 0)}',
      'Nahar: ${formatSignedMinutes(balances['Nahar'] ?? 0)}',
    ].join('\n'));
  }

  @override
  Widget build(BuildContext context) {
    final months = availableMonths(_entries);
    if (!months.contains(_month)) _month = 'All months';
    final rows = _filtered;
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
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['ALL', 'DAWAI', 'FASAL', 'PANI', 'OTHER']
                        .map((tab) => Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ChoiceChip(
                                label: Text(tab),
                                selected: _tab == tab,
                                onSelected: (_) => setState(() => _tab = tab),
                              ),
                            ))
                        .toList(),
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
                  label: const Text('+ Add Contact'),
                ),
              ),
            ),
          if (_tab == 'PANI' && _contacts.isNotEmpty)
            SizedBox(
              height: 54,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                children: _contacts
                    .map((contact) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ActionChip(
                            avatar: const Icon(Icons.account_balance_wallet_outlined),
                            label: Text('Net: ${contact['name']}'),
                            onPressed: () => _shareNet(contact),
                          ),
                        ))
                    .toList(),
              ),
            ),
          Expanded(
            child: rows.isEmpty
                ? emptyState('No Khet entries', 'Add farm and water records here.')
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
        label: Text(_tab == 'PANI' ? 'Add Pani' : 'Add Khet'),
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
          leading: CircleAvatar(
            child: Icon(row['source'] == 'Nahar' ? Icons.water : Icons.water_drop),
          ),
          title: Text('${row['source']} · ${row['direction']}'),
          subtitle: Text(
            '${formatMinutes(row['minutes'] as int? ?? 0)}'
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
    final date = DateTime.tryParse(row['date'] as String? ?? '');
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            if ((row['itemPhoto'] as String? ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: mediaThumbnail(row['itemPhoto'] as String),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row['title'] as String? ?? row['type'] as String,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  if ((row['price'] as String? ?? '').isNotEmpty)
                    Text('₹${row['price']}'),
                  if ((row['note'] as String? ?? '').isNotEmpty)
                    Text(row['note'] as String),
                  if (date != null)
                    Text('${timeLabel(date)} · ${row['type']}',
                        style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  if ((row['billPhoto'] as String? ?? '').isNotEmpty)
                    const Text('Bill photo attached', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Share',
              onPressed: () => _shareKhet(row),
              icon: const Icon(Icons.share_outlined),
            ),
          ],
        ),
      ),
    );
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
  const AddPaniScreen({super.key});

  @override
  State<AddPaniScreen> createState() => _AddPaniScreenState();
}

class _AddPaniScreenState extends State<AddPaniScreen> {
  final _storage = StorageBackupService.instance;
  final _minutes = TextEditingController();
  final _note = TextEditingController();
  String? _contactId;
  String _source = 'Tubewell';
  String _direction = 'Diya';
  bool _saving = false;

  List<Map<String, dynamic>> get _contacts => _storage.records('contacts');

  @override
  void initState() {
    super.initState();
    if (_contacts.isNotEmpty) _contactId = _contacts.first['id'] as String;
  }

  @override
  void dispose() {
    _minutes.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final minutes = int.tryParse(_minutes.text.trim()) ?? 0;
    if (_contactId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a contact before saving Pani hisab')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final contact = _contacts.firstWhere((item) => item['id'] == _contactId);
      await _storage.addRecord('khet', {
        'id': now.microsecondsSinceEpoch.toString(),
        'type': 'PANI',
        'contactId': _contactId,
        'contact': contact['name'],
        'source': _source,
        'direction': _direction,
        'minutes': minutes,
        'note': _note.text.trim(),
        'date': now.toIso8601String(),
      });
      if (!context.mounted) return;
      Navigator.pop(context);
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save Pani hisab: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final contacts = _contacts;
    return Scaffold(
      appBar: AppBar(title: const Text('Add Pani Hisab')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (contacts.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('No contacts yet. Go back and add a contact first.'),
            )
          else
            DropdownButtonFormField<String>(
              value: _contactId,
              decoration: const InputDecoration(labelText: 'Contact'),
              items: contacts
                  .map((item) => DropdownMenuItem(
                        value: item['id'] as String,
                        child: Text(item['name'] as String),
                      ))
                  .toList(),
              onChanged: (value) => setState(() => _contactId = value),
            ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _source,
            decoration: const InputDecoration(labelText: 'Pani Source'),
            items: ['Tubewell', 'Nahar']
                .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                .toList(),
            onChanged: (value) => setState(() => _source = value ?? _source),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _direction,
            decoration: const InputDecoration(labelText: 'Len-Den'),
            items: ['Diya', 'Liya']
                .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                .toList(),
            onChanged: (value) => setState(() => _direction = value ?? _direction),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _minutes,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Minutes',
              helperText: 'Duration: ${formatMinutes(int.tryParse(_minutes.text) ?? 0)}',
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Note'),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving || contacts.isEmpty ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save Pani Hisab'),
          ),
        ],
      ),
    );
  }
}

class AddKhetItemScreen extends StatefulWidget {
  const AddKhetItemScreen({required this.type, super.key});

  final String type;

  @override
  State<AddKhetItemScreen> createState() => _AddKhetItemScreenState();
}

class _AddKhetItemScreenState extends State<AddKhetItemScreen> {
  final _storage = StorageBackupService.instance;
  final _picker = ImagePicker();
  final _title = TextEditingController();
  final _price = TextEditingController();
  final _note = TextEditingController();
  String? _itemPhoto;
  String? _billPhoto;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _price.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(bool bill, ImageSource source) async {
    try {
      final image = await _picker.pickImage(source: source, imageQuality: 88);
      if (image == null) return;
      final path = await _storage.keepFile(image.path, folder: 'KhetPhotos');
      setState(() {
        if (bill) {
          _billPhoto = path;
        } else {
          _itemPhoto = path;
        }
      });
    } catch (error) {
      _error('Could not save photo: $error');
    }
  }

  Future<void> _pickBillFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      final path = result?.files.single.path;
      if (path == null) return;
      final permanent = await _storage.keepFile(path, folder: 'KhetPhotos');
      setState(() => _billPhoto = permanent);
    } catch (error) {
      _error('Could not save bill image: $error');
    }
  }

  void _error(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      await _storage.addRecord('khet', {
        'id': now.microsecondsSinceEpoch.toString(),
        'type': widget.type,
        'title': _title.text.trim(),
        'price': _price.text.trim(),
        'note': _note.text.trim(),
        'itemPhoto': _itemPhoto,
        'billPhoto': _billPhoto,
        'date': now.toIso8601String(),
      });
      if (!context.mounted) return;
      Navigator.pop(context);
    } catch (error) {
      _error('Could not save Khet entry: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _photoButtons(String label, bool bill) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: () => _pickPhoto(bill, ImageSource.camera),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Camera'),
              ),
              TextButton.icon(
                onPressed: bill ? _pickBillFile : () => _pickPhoto(bill, ImageSource.gallery),
                icon: Icon(bill ? Icons.upload_file : Icons.photo_library_outlined),
                label: Text(bill ? 'File/Gallery' : 'Gallery'),
              ),
            ],
          ),
          if ((bill ? _billPhoto : _itemPhoto) != null)
            mediaThumbnail(bill ? _billPhoto : _itemPhoto, size: 78),
        ],
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('Add ${widget.type}')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title / Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Price (₹)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Note'),
            ),
            const SizedBox(height: 18),
            _photoButtons('Item Photo', false),
            const SizedBox(height: 12),
            _photoButtons('Bill Photo', true),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save ${widget.type}'),
            ),
          ],
        ),
      );
}
