import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';

import '../services/storage_backup_service.dart';
import '../widgets/khata_widgets.dart';

class HisabScreen extends StatefulWidget {
  const HisabScreen({super.key});

  @override
  State<HisabScreen> createState() => _HisabScreenState();
}

class _HisabScreenState extends State<HisabScreen> {
  final _storage = StorageBackupService.instance;
  final _search = TextEditingController();
  String _category = 'All';
  String _month = 'All months';
  final _player = AudioPlayer();

  List<Map<String, dynamic>> get _rows => _storage.records('hisabs');

  @override
  void dispose() {
    _search.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _addHisab() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AddHisabScreen()),
    );
    if (mounted) setState(() {});
  }

  List<Map<String, dynamic>> get _filtered {
    final query = _search.text.trim().toLowerCase();
    return _rows.where((row) {
      final date = DateTime.tryParse(row['date'] as String? ?? '');
      final categoryMatch = _category == 'All' || row['category'] == _category;
      final monthMatch = _month == 'All months' ||
          (date != null && monthKey(date) == _month);
      final searchable =
          '${row['title'] ?? ''} ${row['note'] ?? ''} ${row['category'] ?? ''}'
              .toLowerCase();
      return categoryMatch && monthMatch && searchable.contains(query);
    }).toList()
      ..sort((a, b) => (b['date'] as String).compareTo(a['date'] as String));
  }

  Future<void> _share(Map<String, dynamic> row) async {
    final date = DateTime.tryParse(row['date'] as String? ?? '');
    final lines = <String>[
      'Hisab - ${_storage.senderName}',
      if ((row['category'] as String? ?? '').isNotEmpty)
        'Category: ${row['category']}',
      if ((row['title'] as String? ?? '').isNotEmpty) 'Title: ${row['title']}',
      if ((row['amount'] as String? ?? '').isNotEmpty)
        'Amount: ₹${row['amount']}',
      if ((row['note'] as String? ?? '').isNotEmpty) 'Note: ${row['note']}',
      if (date != null) 'Date: ${dateLabel(date)}',
    ];
    final paths = [
      row['photo'] as String?,
      row['voice'] as String?,
      row['callRecording'] as String?,
    ].whereType<String>().where((path) => File(path).existsSync()).toList();
    await Share.shareXFiles(
      paths.map(XFile.new).toList(),
      text: lines.join('\n'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    final months = availableMonths(_rows);
    if (!months.contains(_month)) _month = 'All months';
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
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
                    children: ['All', 'Khet', 'Studio', 'Len-Den', 'Other']
                        .map((item) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(item),
                                selected: _category == item,
                                onSelected: (_) =>
                                    setState(() => _category = item),
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
    return groups.entries.expand((entry) {
      return [
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(
            entry.key,
            style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF176B52)),
          ),
        ),
        ...entry.value.map(_hisabCard),
      ];
    }).toList();
  }

  Widget _hisabCard(Map<String, dynamic> row) {
    final voice = row['voice'] as String?;
    final amount = row['amount'] as String? ?? '';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    (row['title'] as String? ?? '').isEmpty
                        ? row['category'] as String? ?? 'Hisab'
                        : row['title'] as String,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
                if (amount.isNotEmpty)
                  Text('₹$amount', style: const TextStyle(fontWeight: FontWeight.w800)),
                IconButton(
                  tooltip: 'Share',
                  onPressed: () => _share(row),
                  icon: const Icon(Icons.share_outlined),
                ),
              ],
            ),
            Text(row['category'] as String? ?? 'Other',
                style: const TextStyle(color: Colors.black54)),
            if ((row['note'] as String? ?? '').isNotEmpty) ...[
              const SizedBox(height: 7),
              Text(row['note'] as String),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if ((row['photo'] as String? ?? '').isNotEmpty)
                  InkWell(
                    onTap: () => _preview(row['photo'] as String),
                    child: mediaThumbnail(row['photo'] as String),
                  ),
                if (voice != null && voice.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () => _player.play(DeviceFileSource(voice)),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Voice note'),
                  ),
                if ((row['callRecording'] as String? ?? '').isNotEmpty)
                  const Chip(
                    avatar: Icon(Icons.call, size: 18),
                    label: Text('Call recording'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _preview(String path) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: InteractiveViewer(child: Image.file(File(path))),
      ),
    );
  }
}

class AddHisabScreen extends StatefulWidget {
  const AddHisabScreen({super.key});

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
  String _category = 'Khet';
  String? _photo;
  String? _voice;
  String? _callRecording;
  bool _recording = false;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _note.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final image = await _picker.pickImage(source: source, imageQuality: 88);
      if (image == null) return;
      final permanent = await _storage.keepFile(image.path, folder: 'Photos');
      setState(() => _photo = permanent);
    } catch (error) {
      _error('Could not save photo: $error');
    }
  }

  Future<void> _pickCallRecording() async {
    try {
      final picked = await FilePicker.platform.pickFiles(type: FileType.audio);
      final path = picked?.files.single.path;
      if (path == null) return;
      final permanent =
          await _storage.keepFile(path, folder: 'CallRecordings');
      setState(() => _callRecording = permanent);
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
          setState(() {
            _voice = permanent;
            _recording = false;
          });
        } else {
          setState(() => _recording = false);
        }
      } else {
        if (!await _recorder.hasPermission()) {
          _error('Microphone permission is required to record a voice note');
          return;
        }
        final temp = await Directory.systemTemp.createTemp('khata_voice_');
        final path =
            '${temp.path}/${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _recorder.start(const RecordConfig(), path: path);
        setState(() => _recording = true);
      }
    } catch (error) {
      _error('Could not record voice note: $error');
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
      await _storage.addRecord('hisabs', {
        'id': now.microsecondsSinceEpoch.toString(),
        'category': _category,
        'title': _title.text.trim(),
        'amount': _amount.text.trim(),
        'note': _note.text.trim(),
        'photo': _photo,
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
    return Scaffold(
      appBar: AppBar(title: const Text('Add New Hisab')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            value: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: ['Khet', 'Studio', 'Len-Den', 'Other']
                .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                .toList(),
            onChanged: (value) => setState(() => _category = value ?? _category),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title (optional)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount (₹, optional)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'Text note (optional)'),
          ),
          const SizedBox(height: 18),
          const Text('Attachments', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _pickPhoto(ImageSource.camera),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Camera'),
              ),
              OutlinedButton.icon(
                onPressed: () => _pickPhoto(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Gallery'),
              ),
              OutlinedButton.icon(
                onPressed: _toggleRecording,
                icon: Icon(_recording ? Icons.stop : Icons.mic_none),
                label: Text(_recording ? 'Stop recording' : 'Voice note'),
              ),
              OutlinedButton.icon(
                onPressed: _pickCallRecording,
                icon: const Icon(Icons.call),
                label: const Text('Call recording'),
              ),
            ],
          ),
          if (_photo != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                mediaThumbnail(_photo),
                const SizedBox(width: 8),
                const Text('Photo saved permanently'),
              ],
            ),
          ],
          if (_voice != null) const ListTile(leading: Icon(Icons.mic), title: Text('Voice note saved')),
          if (_callRecording != null)
            const ListTile(leading: Icon(Icons.call), title: Text('Call recording saved')),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving || _recording ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving…' : 'Save Hisab'),
          ),
          const SizedBox(height: 6),
          const Text(
            'All fields are optional. Save even an attachment-only entry.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Text(
            'Created ${DateFormat('d MMM yyyy, h:mm a').format(DateTime.now())}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black45, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
