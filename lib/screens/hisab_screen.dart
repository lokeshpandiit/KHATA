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
import '../widgets/plot_selector.dart';

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

  double _amount(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse((value ?? '').toString().replaceAll(',', '').replaceAll('₹', '').trim()) ?? 0;


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

  String _expensePlotSummary(Map<String, dynamic> row) {
    final ids = (row['plotIds'] as List? ?? const [])
        .map((id) => id.toString()).where((id) => id.isNotEmpty).toList();
    if (ids.isNotEmpty) {
      final savedLabels = (row['plotLabelsSnapshot'] as List? ?? const [])
          .map((label) => label.toString()).where((label) => label.isNotEmpty).toList();
      final labels = savedLabels.isNotEmpty
          ? savedLabels
          : _storage.records('plots')
              .where((plot) => ids.contains(plot['id'].toString()))
              .map(plotLabel).toList();
      return 'सामूहिक · ${ids.length} किले${labels.isEmpty ? '' : ': ${labels.join(', ')}'}';
    }
    if (row['plotId'] != null) {
      final label = plotLabelForId(_storage, row['plotId']);
      return label.isEmpty ? 'एक किले के लिए' : label;
    }
    return 'पूरे खेत के लिए';
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
    final direction = row['entryType'] == 'EXPENSE'
        ? 'KHET EXPENSE (−)'
        : row['direction'] == 'PAID' ? 'PAID / GIVEN' : 'RECEIVED';
    final text = [
      'KHATA - ${_storage.senderName}',
      'Category: ${row['category'] ?? ''}',
      if ((row['personName'] as String? ?? '').isNotEmpty) 'Person: ${row['personName']}',
      if ((row['title'] as String? ?? '').isNotEmpty) 'Title: ${row['title']}',
      if (row['entryType'] == 'EXPENSE') 'Killa / Field: ${_expensePlotSummary(row)}',
      if ((row['amount'] as String? ?? '').isNotEmpty) 'Amount: ${row['direction'] == 'PAID' ? '−' : '+'}₹${row['amount']}',
      if (row['category'] == 'Len-Den' || row['category'] == 'Studio') 'Type: $direction',
      if ((row['note'] as String? ?? '').isNotEmpty) 'Note: ${cleanDisplayText(row['note'])}',
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

  Future<void> _recordHisabExpensePayment(Map<String, dynamic> row) async {
    final records = _storage.records('hisabs')
        .where((r) => r['id']?.toString() == row['id']?.toString())
        .toList();
    if (records.isEmpty) return;
    final original = records.first;
    final total = _amount(original['totalAmount'] ?? original['amount']);
    final paid = _amount(original['paidAmount']);
    final before = (total - paid).clamp(0, double.infinity).toDouble();
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    String direction = 'Diya';
    DateTime paymentDate = DateTime.now();
    final history = (original['payments'] as List? ?? const [])
        .whereType<Map>().map((entry) => Map<String, dynamic>.from(entry)).toList();
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) => AlertDialog(
        title: Text('Payment · ${original['personName'] ?? 'Expense'}'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Total ₹${total.toStringAsFixed(0)} · Paid ₹${paid.toStringAsFixed(0)} · Baki ₹${before.toStringAsFixed(0)}'),
          DropdownButtonFormField<String>(
            value: direction,
            decoration: const InputDecoration(labelText: 'Payment type'),
            items: const [
              DropdownMenuItem(value: 'Diya', child: Text('Paise diye')),
              DropdownMenuItem(value: 'Liya', child: Text('Paise wapas liye')),
            ],
            onChanged: (value) => setDialog(() => direction = value ?? direction),
          ),
          TextField(controller: amountController, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: direction == 'Diya' ? 'Kitne paise diye?' : 'Kitne paise wapas mile?')),
          Text('Baad mein baki ₹${(direction == 'Diya' ? before - _amount(amountController.text) : before + _amount(amountController.text)).clamp(0, double.infinity).toStringAsFixed(0)}'),
          TextField(controller: noteController, decoration: const InputDecoration(labelText: 'Note (optional)')),
          OutlinedButton.icon(icon: const Icon(Icons.calendar_today),
            label: Text('Date: ${DateFormat('dd MMM yyyy').format(paymentDate)}'),
            onPressed: () async {
              final picked = await showDatePicker(context: ctx, initialDate: paymentDate,
                firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 3650)));
              if (picked != null) setDialog(() => paymentDate = picked);
            }),
          if (history.isNotEmpty) ...[
            const Divider(),
            Align(alignment: Alignment.centerLeft, child: Text('Payment history: ${history.length} entries')),
          ],
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            final amount = _amount(amountController.text);
            final limit = direction == 'Diya' ? before : paid;
            if (amount <= 0 || amount > limit + 0.009) {
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('1 se ₹${limit.toStringAsFixed(0)} ke beech amount bharein')));
              return;
            }
            Navigator.pop(ctx, {'amount': amount, 'direction': direction, 'date': paymentDate, 'note': noteController.text.trim()});
          }, child: const Text('Save payment')),
        ],
      )),
    );
    amountController.dispose();
    noteController.dispose();
    if (result == null) return;
    final amount = (result['amount'] as num).toDouble();
    direction = result['direction'] as String;
    final newPaid = direction == 'Diya' ? paid + amount : paid - amount;
    final after = (total - newPaid).clamp(0, double.infinity).toDouble();
    history.add({
      'amount': amount,
      'direction': direction,
      'date': (result['date'] as DateTime).toIso8601String(),
      'note': result['note'],
      'balanceBefore': before,
      'balanceAfter': after,
    });
    final updated = Map<String, dynamic>.from(original)
      ..['paidAmount'] = newPaid
      ..['balance'] = after
      ..['status'] = after <= 0.009 ? 'PAID' : (newPaid > 0 ? 'PARTIAL' : 'PENDING')
      ..['payments'] = history;
    await _storage.updateRecord('hisabs', original['id'].toString(), updated);
    if (mounted) setState(() {});
  }

  Widget _hisabCard(Map<String, dynamic> row) {
    final amount = row['amount']?.toString() ?? '';
    final isExpense = row['entryType'] == 'EXPENSE';
    final isPaid = row['direction'] == 'PAID' || isExpense;
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
              Text('${isExpense || isPaid ? '−' : '+'}₹$amount',
                style: TextStyle(color: isExpense || isPaid ? Colors.red : Colors.green, fontWeight: FontWeight.w900, fontSize: 16)),
            IconButton(tooltip: 'Share', onPressed: () => _share(row), icon: const Icon(Icons.share_outlined)),
          ]),
          if (person.isNotEmpty)
            Text('Person: $person${(row['personPhone'] as String? ?? '').isEmpty ? '' : ' · ${row['personPhone']}'}',
              style: const TextStyle(color: Colors.black54)),
          Text(
            isExpense ? 'Khet expense · ${row['expenseCategory'] ?? 'Other'}' : (row['category'] as String? ?? 'Other'),
            style: const TextStyle(color: Colors.black54),
          ),
          if (isExpense) ...[
            Text(
              'Paid ₹${row['paidAmount'] ?? 0} · Pending ₹${row['balance'] ?? 0} · ${_expensePlotSummary(row)}',
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
            if (_amount(row['balance'] ?? (_amount(row['totalAmount'] ?? row['amount']) - _amount(row['paidAmount']))) > 0.009 || _amount(row['paidAmount']) > 0.009)
              Align(alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _recordHisabExpensePayment(row),
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Add / Update Payment'),
                )),
            ...((row['payments'] as List? ?? const []).whereType<Map>().map((p) {
              final date = DateTime.tryParse((p['date'] ?? '').toString());
              return Text(
                '${date == null ? '' : DateFormat('dd MMM yyyy').format(date)} · ${p['direction'] ?? 'Diya'} ₹${_amount(p['amount']).toStringAsFixed(0)} · Pehle ₹${_amount(p['balanceBefore']).toStringAsFixed(0)} · Baad mein ₹${_amount(p['balanceAfter']).toStringAsFixed(0)}',
                style: const TextStyle(color: Colors.black54, fontSize: 11),
              );
            })),
          ],
          if ((row['note'] as String? ?? '').isNotEmpty) ...[
            const SizedBox(height: 7), Text(cleanDisplayText(row['note'])),
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
  final _paidAmount = TextEditingController(text: '0');
  final List<String> _photos = [];
  late String _category = widget.initialCategory;
  String _direction = 'RECEIVED';
  String _entryType = 'RECEIVED';
  String _expenseCategory = 'Tractor';
  String _tractorWork = 'Bijai';
  String? _plotId;
  String _plotScope = 'KHET';
  final List<String> _plotIds = [];
  DateTime _entryDate = DateTime.now();

  bool get _isKhetExpense => _category == 'Khet' && _entryType == 'EXPENSE';
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
    _paidAmount.dispose();
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

  List<Map<String, dynamic>> get _ownedPlots => _storage.records('plots')
      .where((plot) => plot['isMine'] == true)
      .toList();

  List<String> _selectedPlotLabels() {
    final labels = <String>[];
    for (final plot in _ownedPlots.where((plot) => _plotIds.contains(plot['id'].toString()))) {
      final crop = currentCropForPlot(_storage, plot['id']);
      labels.add(crop.isEmpty ? plotLabel(plot) : '${plotLabel(plot)} ($crop)');
    }
    return labels;
  }

  Future<void> _pickMultiplePlots() async {
    final plots = _ownedPlots;
    if (plots.isEmpty) {
      _error('Pehle Khet Map mein apne kille add karein.');
      return;
    }
    final picked = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final temporary = List<String>.from(_plotIds);
        return StatefulBuilder(
          builder: (context, setSheetState) => SafeArea(
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.72,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text('Kille select karein',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      children: plots.map((plot) {
                        final id = plot['id'].toString();
                        final crop = currentCropForPlot(_storage, id);
                        final label = crop.isEmpty
                            ? '${plotLabel(plot)} (Fasal nahi)'
                            : '${plotLabel(plot)} ($crop)';
                        return CheckboxListTile(
                          value: temporary.contains(id),
                          title: Text(label),
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (checked) => setSheetState(() {
                            if (checked == true) {
                              if (!temporary.contains(id)) temporary.add(id);
                            } else {
                              temporary.remove(id);
                            }
                          }),
                        );
                      }).toList(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(sheetContext, temporary),
                        child: Text('Done · ${temporary.length} kille selected'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (picked != null && mounted) {
      setState(() => _plotIds
        ..clear()
        ..addAll(picked));
    }
  }

  Widget _plotScopeFields() {
    if (_expenseCategory == 'Rassi / Samaan') {
      return const InputDecorator(
        decoration: InputDecoration(
          labelText: 'Killa / Field',
          prefixIcon: Icon(Icons.grid_view_outlined),
        ),
        child: Text('पूरा खेत · किसी एक किले से लिंक नहीं'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _plotScope,
          decoration: const InputDecoration(
            labelText: 'Killa / Field',
            prefixIcon: Icon(Icons.grid_view_outlined),
          ),
          items: const [
            DropdownMenuItem(value: 'KHET', child: Text('पूरा खेत')),
            DropdownMenuItem(value: 'SINGLE', child: Text('एक किला')),
            DropdownMenuItem(value: 'MULTIPLE', child: Text('कई किले (Multiple Selection)')),
          ],
          onChanged: (value) => setState(() {
            _plotScope = value ?? 'KHET';
            if (_plotScope != 'SINGLE') _plotId = null;
            if (_plotScope != 'MULTIPLE') _plotIds.clear();
          }),
        ),
        if (_plotScope == 'SINGLE') ...[
          const SizedBox(height: 10),
          KhetPlotDropdown(
            selectedId: _plotId,
            onChanged: (value) => setState(() => _plotId = value),
          ),
        ],
        if (_plotScope == 'MULTIPLE') ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _pickMultiplePlots,
            icon: const Icon(Icons.checklist),
            label: Text(_plotIds.isEmpty
                ? 'Kille select karein'
                : '${_plotIds.length} kille selected · ${_selectedPlotLabels().join(', ')}'),
          ),
        ],
      ],
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _entryDate,
      firstDate: DateTime(now.year - 8),
      lastDate: DateTime(now.year + 8),
    );
    if (picked != null && mounted) {
      setState(() => _entryDate = picked);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final savedCategory = _category == 'Custom' ? _customCategory.text.trim() : _category.trim();
    if (savedCategory.isEmpty) {
      _error('Category ka naam likhein');
      return;
    }

    final isExpense = _isKhetExpense;
    final total = double.tryParse(_amount.text.trim()) ?? 0;
    final paid = double.tryParse(_paidAmount.text.trim().isEmpty ? '0' : _paidAmount.text.trim()) ?? 0;
    final person = _personName.text.trim();
    final expenseTitle = _title.text.trim().isNotEmpty
        ? _title.text.trim()
        : (_expenseCategory == 'Tractor' ? _tractorWork : _expenseCategory);

    if (!isExpense && _category == 'Khet') {
      if (person.isEmpty) {
        _error('Paise lene ya dene par vyakti ka naam zaroor bharein');
        return;
      }
      if (total <= 0) {
        _error('Paise lene ya dene ki sahi rakam bharein');
        return;
      }
    }

    if (isExpense) {
      if (expenseTitle.isEmpty || total <= 0 || paid < 0 || paid > total) {
        _error('Kharcha ka naam, total amount aur paid amount sahi bharein');
        return;
      }
      if (total - paid > 0.009 && person.isEmpty) {
        _error('Udhar baaki hai to kisko dena hai, us vyakti ka naam zaroor bharein');
        return;
      }
      if (_expenseCategory != 'Rassi / Samaan' && _plotScope == 'SINGLE' && _plotId == null) {
        _error('Ek killa select karein, ya poora khet choose karein');
        return;
      }
      if (_expenseCategory != 'Rassi / Samaan' && _plotScope == 'MULTIPLE' && _plotIds.isEmpty) {
        _error('Kam se kam ek killa select karein');
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final entryDate = DateTime(
        _entryDate.year,
        _entryDate.month,
        _entryDate.day,
        now.hour,
        now.minute,
      );
      final id = now.microsecondsSinceEpoch.toString();

      if (isExpense) {
        await _storage.addRecord('hisabs', {
          'id': id,
          'category': 'Khet',
          'entryType': 'EXPENSE',
          'direction': 'EXPENSE',
          'expenseCategory': _expenseCategory,
          'workType': _expenseCategory == 'Tractor' ? _tractorWork : null,
          'title': expenseTitle,
          'amount': total.toString(),
          'totalAmount': total,
          'price': total,
          'paidAmount': paid,
          'balance': total - paid,
          'status': paid >= total ? 'PAID' : (paid > 0 ? 'PARTIAL' : 'PENDING'),
          'personName': person,
          'personPhone': _personPhone.text.trim(),
          'plotScope': _expenseCategory == 'Rassi / Samaan' ? 'KHET' : _plotScope,
          'plotId': _expenseCategory != 'Rassi / Samaan' && _plotScope == 'SINGLE' ? _plotId : null,
          'plotIds': _expenseCategory != 'Rassi / Samaan' && _plotScope == 'MULTIPLE'
              ? List<String>.from(_plotIds)
              : <String>[],
          'plotLabelsSnapshot': _expenseCategory != 'Rassi / Samaan' && _plotScope == 'MULTIPLE'
              ? _selectedPlotLabels()
              : _expenseCategory != 'Rassi / Samaan' && _plotScope == 'SINGLE' && _plotId != null
                  ? [
                      for (final plot in _ownedPlots.where((plot) => plot['id'] == _plotId))
                        currentCropForPlot(_storage, _plotId).isEmpty
                            ? plotLabel(plot)
                            : '${plotLabel(plot)} (${currentCropForPlot(_storage, _plotId)})'
                    ]
                  : <String>[],
          'note': _note.text.trim(),
          'photo': _photos.isEmpty ? null : _photos.first,
          'photos': _photos,
          'voice': _voice,
          'callRecording': _callRecording,
          'payments': paid > 0
              ? [{'amount': paid, 'direction': 'PAID', 'date': entryDate.toIso8601String(), 'balanceBefore': total, 'balanceAfter': (total - paid).clamp(0, double.infinity)}]
              : <Map<String, dynamic>>[],
          'date': entryDate.toIso8601String(),
        });
      } else {
        await _storage.addRecord('hisabs', {
          'id': id,
          'category': savedCategory,
          'title': _title.text.trim(),
          'amount': _amount.text.trim(),
          'direction': _category == 'Khet' ? _entryType : _direction,
          'entryType': _category == 'Khet' ? _entryType : null,
          'personName': person,
          'personPhone': _personPhone.text.trim(),
          'note': _note.text.trim(),
          'photo': _photos.isEmpty ? null : _photos.first,
          'photos': _photos,
          'voice': _voice,
          'callRecording': _callRecording,
          'date': entryDate.toIso8601String(),
        });
      }
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
    final showPerson = _category == 'Khet' || effectiveCategory == 'Len-Den' || effectiveCategory == 'Studio';
    final formCategories = <String>['Khet', 'Studio', 'Len-Den', 'Other', 'Custom'];
    if (!formCategories.contains(widget.initialCategory)) {
      formCategories.insert(formCategories.length - 1, widget.initialCategory);
    }
    final amountValue = double.tryParse(_amount.text.trim()) ?? 0;
    final paidValue = double.tryParse(_paidAmount.text.trim()) ?? 0;
    final pendingValue = (amountValue - paidValue).clamp(0, double.infinity).toDouble();

    return Scaffold(
      appBar: AppBar(title: const Text('Add New Hisab')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: formCategories.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
            onChanged: (value) => setState(() => _category = value ?? _category),
          ),
          if (_category == 'Custom') ...[
            const SizedBox(height: 10),
            TextField(
              controller: _customCategory,
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Apni category ka naam likhein',
                hintText: 'Jaise: Ghar, Personal, Repair, Udhaar',
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (_category == 'Khet') ...[
            DropdownButtonFormField<String>(
              initialValue: _entryType,
              decoration: const InputDecoration(labelText: 'Khet mein kis tarah ki entry?'),
              items: const [
                DropdownMenuItem(value: 'RECEIVED', child: Text('Paise liye')),
                DropdownMenuItem(value: 'PAID', child: Text('Paise diye')),
                DropdownMenuItem(value: 'EXPENSE', child: Text('Khareeda / Kharcha')),
              ],
              onChanged: (value) => setState(() => _entryType = value ?? _entryType),
            ),
            const SizedBox(height: 12),
          ],
          if (_isKhetExpense) ...[
            DropdownButtonFormField<String>(
              initialValue: _expenseCategory,
              decoration: const InputDecoration(labelText: 'Kharcha kis cheez ka hai?'),
              items: const [
                DropdownMenuItem(value: 'Tractor', child: Text('Tractor ka kaam')),
                DropdownMenuItem(value: 'Dawai', child: Text('Dawai')),
                DropdownMenuItem(value: 'Khaad', child: Text('Khaad')),
                DropdownMenuItem(value: 'Diesel', child: Text('Diesel')),
                DropdownMenuItem(value: 'Rassi / Samaan', child: Text('Rassi / Samaan')),
                DropdownMenuItem(value: 'Pani / Sinchai', child: Text('Pani / Sinchai')),
                DropdownMenuItem(value: 'Mazdoori', child: Text('Mazdoori')),
                DropdownMenuItem(value: 'Other', child: Text('Other')),
              ],
              onChanged: (value) => setState(() {
                _expenseCategory = value ?? _expenseCategory;
                if (_expenseCategory == 'Rassi / Samaan') {
                  _plotScope = 'KHET';
                  _plotId = null;
                  _plotIds.clear();
                }
              }),
            ),
            if (_expenseCategory == 'Tractor') ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _tractorWork,
                decoration: const InputDecoration(labelText: 'Tractor ka kaam'),
                items: const [
                  DropdownMenuItem(value: 'Bijai', child: Text('Bijai')),
                  DropdownMenuItem(value: 'Jutai', child: Text('Jutai')),
                  DropdownMenuItem(value: 'Rotavator', child: Text('Rotavator')),
                  DropdownMenuItem(value: 'Leveling', child: Text('Leveling')),
                  DropdownMenuItem(value: 'Other tractor work', child: Text('Other tractor work')),
                ],
                onChanged: (value) => setState(() => _tractorWork = value ?? _tractorWork),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: _expenseCategory == 'Tractor' ? 'Kaam / fasal ka naam' : 'Samaan ka naam',
                hintText: _expenseCategory == 'Tractor' ? 'Jaise: Gehu ki bijai' : 'Jaise: DAP, diesel, rassi',
              ),
            ),
            const SizedBox(height: 10),
            _plotScopeFields(),
            const SizedBox(height: 10),
          ] else ...[
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title (optional)'),
            ),
          ],
          if (showPerson) ...[
            TextField(
              controller: _personName,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: _isKhetExpense ? 'Dukaan wala / tractor wala (optional)' : 'Person name (optional)',
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _pickContact,
              icon: const Icon(Icons.contacts_outlined),
              label: const Text('Pick from phone contacts'),
            ),
            if (_personPhone.text.isNotEmpty)
              Text('Phone: ${_personPhone.text}', style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: _isKhetExpense ? 'Total kharcha / bill (₹)' : 'Amount (₹, optional)',
            ),
          ),
          if (_isKhetExpense) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _paidAmount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Abhi kitne paise diye? (₹)'),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Baaki dena hai: ₹${pendingValue.toStringAsFixed(0)}',
                style: TextStyle(fontWeight: FontWeight.w800, color: pendingValue > 0 ? Colors.red : Colors.green),
              ),
            ),
          ],
          if (_category != 'Khet') ...[
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
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_month_outlined),
            label: Text('Date: ${DateFormat('dd MMM yyyy').format(_entryDate)}'),
          ),
          const SizedBox(height: 12),
          VoiceDictationField(controller: _note, label: 'Text note (optional)'),
          const SizedBox(height: 18),
          const Text('Attachments', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              onPressed: () => _pickPhotos(ImageSource.camera),
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('Camera'),
            ),
            OutlinedButton.icon(
              onPressed: () => _pickPhotos(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Add multiple photos'),
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
          ]),
          if (_photos.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 7, runSpacing: 7, children: _photos.map((path) => Stack(
              alignment: Alignment.topRight,
              children: [
                mediaThumbnail(path, size: 76),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _photos.remove(path)),
                  icon: const Icon(Icons.cancel, color: Colors.red),
                ),
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
          Text(
            _isKhetExpense
                ? 'Total kharcha poora record hoga; paid aur baki alag track honge.'
                : 'All fields are optional. Save even an attachment-only entry.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54, fontSize: 12),
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
