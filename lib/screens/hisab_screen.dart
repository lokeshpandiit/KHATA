import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:record/record.dart';

import '../services/contact_picker_service.dart';
import '../services/khata_sharing_service.dart';
import '../services/storage_backup_service.dart';
import '../widgets/khata_widgets.dart';
import '../widgets/voice_note_player.dart';
import '../widgets/voice_dictation_field.dart';

class HisabScreen extends StatefulWidget {
  const HisabScreen({super.key});

  @override
  State<HisabScreen> createState() => _HisabScreenState();
}

class _HisabScreenState extends State<HisabScreen> {
  final _storage = StorageBackupService.instance;
  String _category = 'All';
  String _month = 'All months';

  List<Map<String, dynamic>> get _rows => _storage.records('hisabs');


  Future<void> _addHisab() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => AddHisabScreen(initialCategory: _category == 'All' ? 'Khet' : _category)),
    );
    if (mounted) setState(() {});
  }

  List<String> _photos(Map<String, dynamic> row) {
    final paths = (row['photos'] as List? ?? const []).whereType<String>().toList();
    final legacy = row['photo'];
    if (legacy is String && legacy.isNotEmpty && !paths.contains(legacy)) {
      paths.insert(0, legacy);
    }
    return paths.where((path) => File(path).existsSync()).toList();
  }

  List<Map<String, dynamic>> get _filtered {
    return _rows.where((row) {
      final date = DateTime.tryParse(row['date'] as String? ?? '');
      final categoryMatch = _category == 'All' || row['category'] == _category;
      final monthMatch = _month == 'All months' ||
          (date != null && monthKey(date) == _month);
      return categoryMatch && monthMatch;
    }).toList()
      ..sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
  }

  Future<void> _share(Map<String, dynamic> row) async {
    final mode = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(children: [
          const ListTile(title: Text('Choose what to share', style: TextStyle(fontWeight: FontWeight.w800))),
          ListTile(leading: const Icon(Icons.text_fields), title: const Text('Only text'), onTap: () => Navigator.pop(sheetContext, 'text')),
          ListTile(leading: const Icon(Icons.image_outlined), title: const Text('Text + images'), onTap: () => Navigator.pop(sheetContext, 'images')),
          ListTile(leading: const Icon(Icons.mic_none), title: const Text('Text + voice note'), onTap: () => Navigator.pop(sheetContext, 'voice')),
          ListTile(leading: const Icon(Icons.attach_file), title: const Text('Text + images + voice note'), onTap: () => Navigator.pop(sheetContext, 'all')),
        ]),
      ),
    );
    if (mode == null) return;
    final date = DateTime.tryParse(row['date'] as String? ?? '');
    final direction = row['direction'] == 'PAID' ? 'PAID / GIVEN (−)' : 'RECEIVED (+)';
    final text = [
      'KHATA - ${_storage.senderName}',
      'Category: ${row['category'] ?? ''}',
      if ((row['personName'] as String? ?? '').isNotEmpty) 'Person: ${row['personName']}',
      if ((row['title'] as String? ?? '').isNotEmpty) 'Title: ${row['title']}',
      if ((row['amount'] as String? ?? '').isNotEmpty) 'Amount: ${row['direction'] == 'PAID' ? '−' : '+'}₹${row['amount']}',
      if (row['category'] == 'Len-Den' || row['category'] == 'Studio') 'Type: $direction',
      if ((row['note'] as String? ?? '').isNotEmpty) 'Note: ${row['note']}',
      if (date != null) 'Date: ${dateLabel(date)}',
    ].join('\n');
    final photos = mode == 'images' || mode == 'all' ? _photos(row) : <String>[];
    final voice = mode == 'voice' || mode == 'all' ? row['voice'] as String? : null;
    final callRecording = mode == 'voice' || mode == 'all' ? row['callRecording'] as String? : null;
    final files = [
      ...photos,
      if (voice != null && File(voice).existsSync()) voice,
      if (callRecording != null && File(callRecording).existsSync()) callRecording,
    ];
    try {
      await KhataSharingService.share(
        text: text,
        phone: row['personPhone'] as String?,
        files: files,
      );
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not share record: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    final months = availableMonths(_rows);
    final customCategories = _rows
        .map((row) => (row['category'] ?? '').toString().trim())
        .where((category) => category.isNotEmpty && !const ['Khet', 'Studio', 'Len-Den', 'Other'].contains(category))
        .toSet()
        .toList()..sort();
    final categoryOptions = ['All', 'Khet', 'Studio', 'Len-Den', 'Other', ...customCategories];
    if (!months.contains(_month)) _month = 'All months';
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              children: [
                monthFilter(_month, months, (value) {
                  if (value != null) setState(() => _month = value);
                }),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: categoryOptions
                        .map((item) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(item),
                                selected: _category == item,
                                onSelected: (_) => setState(() => _category = item),
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? emptyState('No hisab entries', 'Add a record to start your history.')
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                    children: _buildDateGroups(rows),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addHisab,
        icon: const Icon(Icons.add),
        label: const Text('Add Hisab'),
      ),
    );
  }

  List<Widget> _buildDateGroups(List<Map<String, dynamic>> rows) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final date = DateTime.tryParse(row['date'] as String? ?? '');
      final key = date == null ? 'Date unavailable' : dateLabel(date);
      groups.putIfAbsent(key, () => []).add(row);
    }
    return groups.entries.expand((entry) => [
      Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF176B52))),
      ),
      ...entry.value.map(_hisabCard),
    ]).toList();
  }

  Widget _hisabCard(Map<String, dynamic> row) {
    final amount = row['amount']?.toString() ?? '';
    final isPaid = row['direction'] == 'PAID';
    final photos = _photos(row);
    final voice = row['voice'] as String?;
    final person = (row['personName'] as String? ?? '').trim();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(
              (row['title'] as String? ?? '').isEmpty ? row['category'] as String? ?? 'Hisab' : row['title'] as String,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            )),
            if (amount.isNotEmpty)
              Text('${isPaid ? '−' : '+'}₹$amount',
                style: TextStyle(color: isPaid ? Colors.red : Colors.green, fontWeight: FontWeight.w900, fontSize: 16)),
            IconButton(tooltip: 'Share', onPressed: () => _share(row), icon: const Icon(Icons.share_outlined)),
          ]),
          if (person.isNotEmpty)
            Text('Person: $person${(row['personPhone'] as String? ?? '').isEmpty ? '' : ' · ${row['personPhone']}'}',
              style: const TextStyle(color: Colors.black54)),
          Text(row['category'] as String? ?? 'Other', style: const TextStyle(color: Colors.black54)),
          if ((row['note'] as String? ?? '').isNotEmpty) ...[
            const SizedBox(height: 7), Text(row['note'] as String),
          ],
          if (photos.isNotEmpty) ...[
            const SizedBox(height: 9),
            Wrap(spacing: 7, runSpacing: 7, children: photos.map((path) => InkWell(
              onTap: () => _preview(path), child: mediaThumbnail(path, size: 76),
            )).toList()),
          ],
          if (voice != null && voice.isNotEmpty) ...[
            const SizedBox(height: 8),
            VoiceNotePlayer(path: voice),
          ],
          if ((row['callRecording'] as String? ?? '').isNotEmpty)
            const Chip(avatar: Icon(Icons.call, size: 18), label: Text('Call recording attached')),
        ]),
      ),
    );
  }

  void _preview(String path) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(child: InteractiveViewer(child: Image.file(File(path)))),
    );
  }
}

class AddHisabScreen extends StatefulWidget {
  const AddHisabScreen({super.key, this.initialCategory = 'Khet'});

  final String initialCategory;

  @override
  State<AddHisabScreen> createState() => _AddHisabScreenState();
}

class _AddHisabScreenState extends State<AddHisabScreen> {
  final _storage = StorageBackupService.instance;
  final _picker = ImagePicker();
  final _recorder = AudioRecorder();
  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _personName = TextEditingController();
  final _personPhone = TextEditingController();
  final _customCategory = TextEditingController();
  final List<String> _photos = [];
  late String _category = widget.initialCategory;
  String _direction = 'RECEIVED';
  String? _voice;
  String? _callRecording;
  bool _recording = false;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _note.dispose();
    _personName.dispose();
    _personPhone.dispose();
    _customCategory.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _pickContact() async {
    try {
      final picked = await ContactPickerService.pickPhoneContact();
      if (picked == null) return;
      if (!mounted) return;
      setState(() {
        _personName.text = picked['name']!;
        _personPhone.text = picked['phone']!;
      });
    } catch (error) {
      _error('Could not pick contact: $error');
    }
  }

  Future<void> _pickPhotos(ImageSource source) async {
    try {
      final images = source == ImageSource.gallery
          ? await _picker.pickMultiImage(imageQuality: 88)
          : [if (await _picker.pickImage(source: source, imageQuality: 88) case final image?) image];
      for (final image in images) {
        final permanent = await _storage.keepFile(image.path, folder: 'Photos');
        if (!_photos.contains(permanent)) _photos.add(permanent);
      }
      if (mounted) setState(() {});
    } catch (error) {
      _error('Could not save photos: $error');
    }
  }

  Future<void> _pickCallRecording() async {
    try {
      final picked = await FilePicker.platform.pickFiles(type: FileType.audio);
      final path = picked?.files.single.path;
      if (path == null) return;
      final permanent = await _storage.keepFile(path, folder: 'CallRecordings');
      if (mounted) setState(() => _callRecording = permanent);
    } catch (error) {
      _error('Could not save call recording: $error');
    }
  }

  Future<void> _toggleRecording() async {
    try {
      if (_recording) {
        final path = await _recorder.stop();
        if (path != null) {
          final permanent = await _storage.keepFile(path, folder: 'VoiceNotes');
          if (mounted) setState(() {
            _voice = permanent;
            _recording = false;
          });
        } else if (mounted) {
          setState(() => _recording = false);
        }
      } else {
        if (!await _recorder.hasPermission()) {
          _error('Microphone permission is required to record a voice note');
          return;
        }
        final temp = await Directory.systemTemp.createTemp('khata_voice_');
        final path = '${temp.path}/${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
        if (mounted) setState(() => _recording = true);
      }
    } catch (error) {
      _error('Could not record voice note: $error');
      if (mounted) setState(() => _recording = false);
    }
  }

  void _error(String message) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    if (_saving) return;
    final savedCategory = _category == 'Custom' ? _customCategory.text.trim() : _category.trim();
    if (savedCategory.isEmpty) {
      _error('Category ka naam likhein');
      return;
    }
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      await _storage.addRecord('hisabs', {
        'id': now.microsecondsSinceEpoch.toString(),
        'category': savedCategory,
        'title': _title.text.trim(),
        'amount': _amount.text.trim(),
        'direction': _direction,
        'personName': _personName.text.trim(),
        'personPhone': _personPhone.text.trim(),
        'note': _note.text.trim(),
        'photo': _photos.isEmpty ? null : _photos.first,
        'photos': _photos,
        'voice': _voice,
        'callRecording': _callRecording,
        'date': now.toIso8601String(),
      });
      if (mounted) Navigator.pop(context);
    } catch (error) {
      _error('Could not save hisab: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveCategory = _category == 'Custom' ? _customCategory.text.trim() : _category;
    final showPerson = effectiveCategory == 'Len-Den' || effectiveCategory == 'Studio';
    final formCategories = <String>['Khet', 'Studio', 'Len-Den', 'Other', 'Custom'];
    if (!formCategories.contains(widget.initialCategory)) {
      formCategories.insert(formCategories.length - 1, widget.initialCategory);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Add New Hisab')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: formCategories
                .map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
            onChanged: (value) => setState(() => _category = value ?? _category),
          ),
          if (_category == 'Custom') ...[
            const SizedBox(height: 10),
            TextField(controller: _customCategory, textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Apni category ka naam likhein', hintText: 'Jaise: Ghar, Personal, Repair, Udhaar')),
          ],
          const SizedBox(height: 12),
          TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title (optional)')),
          const SizedBox(height: 12),
          if (showPerson) ...[
            TextField(controller: _personName, textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Person name')),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: _pickContact, icon: const Icon(Icons.contacts_outlined),
              label: const Text('Pick from phone contacts')),
            if (_personPhone.text.isNotEmpty)
              Text('Phone: ${_personPhone.text}', style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 12),
          ],
          TextField(controller: _amount, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount (₹, optional)')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _direction,
            decoration: const InputDecoration(labelText: 'Money direction'),
            items: const [
              DropdownMenuItem(value: 'RECEIVED', child: Text('Paise mile (+) · Green')),
              DropdownMenuItem(value: 'PAID', child: Text('Paise diye (−) · Red')),
            ],
            onChanged: (value) => setState(() => _direction = value ?? _direction),
          ),
          const SizedBox(height: 12),
          VoiceDictationField(
            controller: _note,
            label: 'Text note (optional)',
          ),
          const SizedBox(height: 18),
          const Text('Attachments', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(onPressed: () => _pickPhotos(ImageSource.camera),
              icon: const Icon(Icons.camera_alt_outlined), label: const Text('Camera')),
            OutlinedButton.icon(onPressed: () => _pickPhotos(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined), label: const Text('Add multiple photos')),
            OutlinedButton.icon(onPressed: _toggleRecording,
              icon: Icon(_recording ? Icons.stop : Icons.mic_none),
              label: Text(_recording ? 'Stop recording' : 'Voice note')),
            OutlinedButton.icon(onPressed: _pickCallRecording,
              icon: const Icon(Icons.call), label: const Text('Call recording')),
          ]),
          if (_photos.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 7, runSpacing: 7, children: _photos.map((path) => Stack(
              alignment: Alignment.topRight,
              children: [
                mediaThumbnail(path, size: 76),
                IconButton(visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _photos.remove(path)),
                  icon: const Icon(Icons.cancel, color: Colors.red)),
              ],
            )).toList()),
          ],
          if (_voice != null) ...[
            const SizedBox(height: 8),
            VoiceNotePlayer(path: _voice!),
          ],
          if (_callRecording != null)
            const ListTile(leading: Icon(Icons.call), title: Text('Call recording saved')),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving || _recording ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving…' : 'Save Hisab'),
          ),
          const SizedBox(height: 6),
          const Text('All fields are optional. Save even an attachment-only entry.',
            textAlign: TextAlign.center, style: TextStyle(color: Colors.black54, fontSize: 12)),
          const SizedBox(height: 10),
          Text('Created ${DateFormat('d MMM yyyy, h:mm a').format(DateTime.now())}',
            textAlign: TextAlign.center, style: const TextStyle(color: Colors.black45, fontSize: 12)),
        ],
      ),
    );
  }
}
