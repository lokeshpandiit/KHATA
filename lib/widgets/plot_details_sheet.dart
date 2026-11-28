import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../screens/khet_screen.dart';
import '../services/storage_backup_service.dart';
import '../services/future_date_reminder_prompt.dart';
import 'plot_selector.dart';
import 'farm_fields.dart';

class KhetPlotDetailsSheet extends StatefulWidget {
  const KhetPlotDetailsSheet({required this.plot, super.key});
  final Map<String, dynamic> plot;

  @override
  State<KhetPlotDetailsSheet> createState() => _KhetPlotDetailsSheetState();
}

class _KhetPlotDetailsSheetState extends State<KhetPlotDetailsSheet> {
  String _season = 'Rabi';
  int _year = DateTime.now().year;
  String? _selectedCropCycleId;

  DateTime? _date(Map<String, dynamic> row) {
    for (final key in ['eventDate', 'date', 'sowingDate', 'applicationDate']) {
      final value = row[key];
      if (value is String) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  List<Map<String, dynamic>> _latest(List<Map<String, dynamic>> rows) {
    final result = [...rows];
    result.sort((a, b) => (_date(b) ?? DateTime(0)).compareTo(_date(a) ?? DateTime(0)));
    return result;
  }

  String _cycleKey(Map<String, dynamic> crop) {
    final id = crop['cropCycleId']?.toString();
    if (id != null && id.isNotEmpty) return id;
    return 'legacy_${crop['id'] ?? 'unknown'}';
  }

  bool _isCompleted(Map<String, dynamic> crop) =>
      crop['harvested'] == true || crop['cropCycleStatus'] == 'COMPLETED';

  double _amount(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString().replaceAll(',', '').replaceAll('₹', '').trim()) ?? 0;
  }

  bool _belongsToCycle(Map<String, dynamic> row, Map<String, dynamic> crop) {
    if (row['id'] == crop['id']) return true;
    final rowCycleId = row['cropCycleId']?.toString();
    if (rowCycleId != null && rowCycleId.isNotEmpty) {
      return rowCycleId == _cycleKey(crop);
    }

    // Backward compatibility for records saved before cropCycleId existed.
    // Attach only unlinked rows inside this crop's sowing-to-harvest window.
    final sowingDate = DateTime.tryParse(
      (crop['sowingDate'] ?? crop['date'] ?? '').toString(),
    );
    final activityDate = _date(row);
    if (sowingDate == null || activityDate == null) {
      return crop['season'] != null &&
          row['season'] == crop['season'] &&
          (crop['year'] == null || row['year'] == crop['year']);
    }
    final day = DateUtils.dateOnly(activityDate);
    if (day.isBefore(DateUtils.dateOnly(sowingDate))) return false;
    final harvestDate = DateTime.tryParse((crop['harvestDate'] ?? '').toString());
    if (harvestDate != null && day.isAfter(DateUtils.dateOnly(harvestDate))) {
      return false;
    }
    if (crop['season'] != null && row['season'] != null &&
        row['season'] != crop['season']) return false;
    if (crop['year'] != null && row['year'] != null &&
        row['year'] != crop['year']) return false;
    return true;
  }

  Future<void> _markHarvested(Map<String, dynamic> crop) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 8),
      lastDate: DateTime(now.year + 8),
    );
    if (picked == null || !mounted) return;
    final sowingDate = DateTime.tryParse(
      (crop['sowingDate'] ?? crop['date'] ?? '').toString(),
    );
    if (sowingDate != null &&
        DateUtils.dateOnly(picked).isBefore(DateUtils.dateOnly(sowingDate))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('कटाई की तारीख, बुवाई की तारीख से पहले नहीं हो सकती।')),
      );
      return;
    }
    final futureHarvest = DateUtils.dateOnly(picked).isAfter(
      DateUtils.dateOnly(now),
    );
    await FutureDateReminderPrompt.check(
      context,
      date: picked,
      taskTitle: 'Fasal katni - ${crop['title'] ?? 'Fasal'}',
    );
    if (!mounted) return;
    final pickedIso = DateTime(picked.year, picked.month, picked.day).toIso8601String();
    final updated = Map<String, dynamic>.from(crop)
      ..['harvested'] = !futureHarvest
      ..['cropCycleStatus'] = futureHarvest ? 'ACTIVE' : 'COMPLETED'
      ..['harvestDate'] = futureHarvest ? null : pickedIso
      ..['plannedHarvestDate'] = futureHarvest ? pickedIso : null
      ..['harvestedAt'] = futureHarvest ? null : DateTime.now().toIso8601String();
    await StorageBackupService.instance.updateRecord('khet', crop['id'].toString(), updated);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(futureHarvest
              ? 'Fasal katne ki planned date save ho gayi. Fasal abhi kati hui mark nahi hui.'
              : 'Fasal katne ka record save ho gaya. Ab nayi fasal add kar sakte hain.'),
        ),
      );
      setState(() {});
    }
  }

  Future<void> _showWaterDetails(Map<String, dynamic> row, int totalKyaris) async {
    final date = _date(row);
    final minutes = (row['minutes'] as num?)?.toInt() ?? 0;
    final source = (row['source'] ?? row['wellType'] ?? 'Paani').toString();
    final direction = (row['direction'] ?? '').toString();
    final contact = (row['contact'] ?? row['borrowedContact'] ?? '').toString();
    final wet = (row['wetKyaris'] as num?)?.toInt() ?? 0;
    final total = (row['totalKyarisSnapshot'] as num?)?.toInt() ?? totalKyaris;
    final remaining = (row['remainingKyaris'] as num?)?.toInt() ?? (total - wet).clamp(0, total);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(date == null ? 'Paani details' : DateFormat('dd MMM yyyy').format(date)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _line('Paani', formatMinutes(minutes)),
          if (row['ownMinutes'] is num)
            _line('Apni baari / apna pani', formatMinutes((row['ownMinutes'] as num).toInt())),
          if (row['borrowedMinutes'] is num && (row['borrowedMinutes'] as num).toInt() > 0)
            _line('Dusre se liya pani', formatMinutes((row['borrowedMinutes'] as num).toInt())),
          if (row['borrowedNaharMinutes'] is num && (row['borrowedNaharMinutes'] as num).toInt() > 0)
            _line('Nahar se liya', formatMinutes((row['borrowedNaharMinutes'] as num).toInt())),
          if (row['borrowedKuaMinutes'] is num && (row['borrowedKuaMinutes'] as num).toInt() > 0)
            _line('Kua se liya', formatMinutes((row['borrowedKuaMinutes'] as num).toInt())),
          _line('Source', source),
          if (direction.isNotEmpty) _line('Apna / liya / diya', direction),
          if (contact.isNotEmpty) _line('Kis se', contact),
          if (row['borrowedSource'] != null) _line('Liye paani ka source', row['borrowedSource'].toString()),
          if (row['plotId'] != null) _line('Kila', plotLabelForId(StorageBackupService.instance, row['plotId'])),
          if (row['wetKyaris'] != null) _line('Bheegi kyari', '$wet / $total'),
          if (row['remainingKyaris'] != null) _line('Baaki kyari', remaining.toString()),
          if ((row['note'] ?? '').toString().trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Note: ${row['note']}'),
          ],
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close'))],
      ),
    );
  }

  String _seasonYear(Map<String, dynamic> row) {
    final season = (row['season'] ?? '').toString();
    final year = row['year'];
    if (season.isEmpty && year == null) return '';
    return [season, if (year != null) year.toString()].where((part) => part.isNotEmpty).join(' ');
  }

  Widget _section(String title, List<Widget> children) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 8),
        ...children,
      ]),
    ),
  );

  Widget _line(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: Text(label, style: const TextStyle(color: Colors.black54))),
      const SizedBox(width: 8),
      Flexible(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w700))),
    ]),
  );

  Widget _activity(Map<String, dynamic> row, String title, String subtitle) {
    final date = _date(row);
    final seasonYear = _seasonYear(row);
    final details = <String>[
      if (subtitle.isNotEmpty) subtitle,
      if (row['type'] != 'PANI' && row['kyariCount'] != null)
        (row['fullKilla'] == true
            ? 'Full Killa · ${row['kyariCount']} kyari'
            : 'Partial · ${row['kyariCount']} / ${row['totalKyarisSnapshot'] ?? '-'} kyari'),
      if (date != null) DateFormat('dd MMM yyyy').format(date),
      if (seasonYear.isNotEmpty) seasonYear,
    ].join(' · ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(details),
    );
  }

  @override
  Widget build(BuildContext context) {
    final storage = StorageBackupService.instance;
    return ValueListenableBuilder<int>(
      valueListenable: storage.revision,
      builder: (context, _, __) {
        final plotRecords = storage.records('khet').where((row) => row['plotId'] == widget.plot['id']).toList();
        final linkedHisabExpenses = storage.records('hisabs').where((row) {
          if (row['category'] != 'Khet' || row['entryType'] != 'EXPENSE') return false;
          if (row['plotId'] == widget.plot['id']) return true;
          return (row['plotIds'] as List? ?? const [])
              .any((id) => id.toString() == widget.plot['id'].toString());
        }).toList()
          ..sort((a, b) => (_date(b) ?? DateTime(0)).compareTo(_date(a) ?? DateTime(0)));
        final cropCycles = _latest(plotRecords.where((row) => row['type'] == 'FASAL').toList());
        final selectedMatches = cropCycles.where((row) => _cycleKey(row) == _selectedCropCycleId).toList();
        final activeMatches = cropCycles.where((row) => !_isCompleted(row)).toList();
        final selectedCycle = selectedMatches.isNotEmpty ? selectedMatches.first :
            activeMatches.isNotEmpty ? activeMatches.first :
            cropCycles.isNotEmpty ? cropCycles.first : null;
        final selectedCycleId = selectedCycle == null ? null : _cycleKey(selectedCycle);
        if (_selectedCropCycleId == null && selectedCycleId != null) {
          _selectedCropCycleId = selectedCycleId;
        }
        final entries = _latest(plotRecords.where((row) {
          if (selectedCycle != null) return _belongsToCycle(row, selectedCycle);
          return row['cropCycleId'] == null &&
              row['season'] == _season && row['year'] == _year;
        }).toList());
        final pani = entries.where((row) => row['type'] == 'PANI').toList();
        final crops = entries.where((row) => row['type'] == 'FASAL').toList();
        final fodder = entries.where((row) => row['type'] == 'HARA_BEEJ').toList();
        final dawai = entries.where((row) => row['type'] == 'DAWAI').toList();
        final khaad = entries.where((row) => row['type'] == 'KHAD').toList();
        final latestPani = pani.isEmpty ? null : pani.first;
        final latestCrop = selectedCycle != null && !_isCompleted(selectedCycle)
            ? selectedCycle
            : null;
        final selectedCompleted = selectedCycle != null && _isCompleted(selectedCycle);
        final hasActiveCycle = activeMatches.isNotEmpty;
        final totalKyaris = (widget.plot['totalKyaris'] as num?)?.toInt() ?? 0;
        final wetKyaris = (latestPani?['wetKyaris'] as num?)?.toInt() ?? 0;
        final remainingKyaris = latestPani == null
            ? totalKyaris
            : ((latestPani['remainingKyaris'] as num?)?.toInt() ?? (totalKyaris - wetKyaris).clamp(0, totalKyaris));
        final totalMinutes = pani.fold<int>(0, (sum, row) => sum + ((row['minutes'] as num?)?.toInt() ?? 0));
        final ownMinutes = pani.fold<int>(0, (sum, row) {
          final total = (row['minutes'] as num?)?.toInt() ?? 0;
          final borrowed = (row['borrowedMinutes'] as num?)?.toInt() ?? 0;
          return sum + ((row['ownMinutes'] as num?)?.toInt() ?? (total - borrowed).clamp(0, total));
        });
        final borrowedMinutes = pani.fold<int>(0, (sum, row) =>
            sum + ((row['borrowedMinutes'] as num?)?.toInt() ?? 0));
        final borrowedNahar = pani.fold<int>(0, (sum, row) =>
            sum + ((row['borrowedNaharMinutes'] as num?)?.toInt() ?? 0));
        final borrowedKua = pani.fold<int>(0, (sum, row) =>
            sum + ((row['borrowedKuaMinutes'] as num?)?.toInt() ?? 0));
        final cropName = selectedCycle == null
            ? 'Fasal record nahi hai'
            : (selectedCycle['cropName'] ?? selectedCycle['title'] ?? 'Fasal').toString() +
                (_isCompleted(selectedCycle) ? ' (Kat chuki)' : ' (Current)');
        final expenseRows = entries.where((row) =>
            ['FASAL', 'KHAD', 'DAWAI', 'HARA_BEEJ', 'OTHER', 'KHET_STOCK_USE'].contains(row['type']) &&
            _amount(row['price']) > 0).toList();
        final totalCropExpenses = expenseRows.fold<double>(
            0, (sum, row) => sum + _amount(row['price']));
        final expenseByType = <String, double>{};
        for (final row in expenseRows) {
          final type = (row['type'] ?? 'OTHER').toString();
          expenseByType[type] = (expenseByType[type] ?? 0) + _amount(row['price']);
        }
        final timelineRows = <Map<String, dynamic>>[...entries];
        if (selectedCycle != null && selectedCycle['harvestDate'] is String &&
            (selectedCycle['harvestDate'] as String).isNotEmpty) {
          timelineRows.add({
            'id': 'harvest_${_cycleKey(selectedCycle)}',
            'type': 'HARVEST_EVENT',
            'eventDate': selectedCycle['harvestDate'],
            'title': 'Fasal katayi poori',
          });
        } else if (selectedCycle != null && selectedCycle['plannedHarvestDate'] is String &&
            (selectedCycle['plannedHarvestDate'] as String).isNotEmpty) {
          timelineRows.add({
            'id': 'planned_harvest_${_cycleKey(selectedCycle)}',
            'type': 'HARVEST_PLANNED',
            'eventDate': selectedCycle['plannedHarvestDate'],
            'title': 'Planned fasal katayi',
          });
        }
        timelineRows.sort((a, b) =>
            (_date(a) ?? DateTime(0)).compareTo(_date(b) ?? DateTime(0)));

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)))),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: Text(plotLabel(widget.plot), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ]),
              if ((widget.plot['name'] as String? ?? '').isNotEmpty)
                Text(widget.plot['name'] as String, style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 10),
              if (cropCycles.isNotEmpty)
                DropdownButtonFormField<String>(
                  value: selectedCycleId,
                  decoration: const InputDecoration(labelText: 'Crop Cycle / Purani Fasal'),
                  items: cropCycles.map((crop) {
                    final cropTitle = (crop['cropName'] ?? crop['title'] ?? 'Fasal').toString();
                    final date = _date(crop);
                    final status = crop['harvested'] == true ? ' · Complete' : ' · Current';
                    return DropdownMenuItem<String>(
                      value: _cycleKey(crop),
                      child: Text(cropTitle + (date == null ? '' : ' · ${DateFormat('dd MMM yyyy').format(date)}') + status,
                        overflow: TextOverflow.ellipsis),
                    );
                  }).where((item) => item.value != null).toList(),
                  onChanged: (value) => setState(() => _selectedCropCycleId = value),
                )
              else
                SeasonYearFields(
                  season: _season,
                  year: _year,
                  onSeasonChanged: (value) => setState(() => _season = value),
                  onYearChanged: (value) => setState(() => _year = value),
                ),
              const SizedBox(height: 8),
              Text(selectedCycle == null ? 'Purana season/year record' : 'Selected crop ka record', style: const TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 10),
              Expanded(
                child: ListView(children: [
                  _section('Khet summary', [
                    _line('Total kyari', totalKyaris == 0 ? 'Map Edit mein set karein' : totalKyaris.toString()),
                    _line('Selected crop', cropName),
                    if (selectedCycle != null)
                      _line('Buwai date', _date(selectedCycle) == null
                          ? 'Date nahi'
                          : DateFormat('dd MMM yyyy').format(_date(selectedCycle)!)),
                    if (selectedCycle != null)
                      _line('Cycle status', selectedCompleted ? 'Complete / Locked' : 'Active'),
                    _line('Paani entries', '${pani.length} baar'),
                    _line('Total paani time', formatMinutes(totalMinutes)),
                    _line('Apna pani', formatMinutes(ownMinutes)),
                    _line('Dusre se liya pani', formatMinutes(borrowedMinutes)),
                    if (borrowedNahar > 0) _line('Nahar se liya', formatMinutes(borrowedNahar)),
                    if (borrowedKua > 0) _line('Kua se liya', formatMinutes(borrowedKua)),
                    if (latestPani != null) ...[
                      _line('Is baar bheegi kyari', wetKyaris.toString()),
                      _line('Abhi baaki kyari', remainingKyaris.toString()),
                    ],
                  ]),
                  _section('Linked Khet expenses', linkedHisabExpenses.isEmpty
                    ? [const Text('Is kille se juda koi alag ya samuhik Khet kharcha nahi hai.')]
                    : linkedHisabExpenses.map((row) {
                        final total = _amount(row['totalAmount'] ?? row['amount']);
                        final ids = (row['plotIds'] as List? ?? const [])
                            .map((id) => id.toString()).toList();
                        final labels = (row['plotLabelsSnapshot'] as List? ?? const [])
                            .map((label) => label.toString()).where((label) => label.isNotEmpty).toList();
                        final scope = ids.length > 1
                            ? 'सामूहिक खरीद · ${ids.length} किले${labels.isEmpty ? '' : ': ${labels.join(', ')}'}'
                            : 'एक किले का खर्च';
                        final date = _date(row);
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: const Icon(Icons.receipt_long_outlined),
                          title: Text('${row['expenseCategory'] ?? 'खर्च'} · ${row['title'] ?? 'Khet expense'}',
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text([
                            scope,
                            'पूरा बिल ₹${total.toStringAsFixed(0)} (हर किले में पूरा बिल दोबारा नहीं जोड़ा गया है)',
                            if (date != null) DateFormat('dd MMM yyyy').format(date),
                          ].join(' · ')),
                          trailing: Text('₹${total.toStringAsFixed(0)}',
                              style: const TextStyle(fontWeight: FontWeight.w800)),
                        );
                      }).toList()),
                  _section('Crop-wise expenses', expenseRows.isEmpty
                    ? [const Text('Is crop cycle ka koi kharcha record nahi hai.')]
                    : [
                        _line('Total crop expense', '₹${totalCropExpenses.toStringAsFixed(0)}'),
                        ...expenseByType.entries.map((entry) => _line(
                          switch (entry.key) {
                            'FASAL' => 'Buwai / beej',
                            'KHAD' => 'Khaad',
                            'DAWAI' => 'Dawai / spray',
                            'HARA_BEEJ' => 'Hara beej',
                            _ => 'Other',
                          },
                          '₹${entry.value.toStringAsFixed(0)}',
                        )),
                      ]),
                  _section('Crop timeline', timelineRows.isEmpty
                    ? [const Text('Is crop cycle ki timeline abhi khaali hai.')]
                    : timelineRows.map((row) {
                        final type = (row['type'] ?? '').toString();
                        final date = _date(row);
                        final title = switch (type) {
                          'FASAL' => 'Buwai · ${row['cropName'] ?? row['title'] ?? 'Fasal'}',
                          'PANI' => 'Paani diya',
                          'KHAD' => 'Khaad dali',
                          'DAWAI' => 'Dawai / spray',
                          'HARA_BEEJ' => 'Hara beej / chara',
                          'KHET_STOCK_USE' => 'Purchased stock used',
                          'HARVEST_EVENT' => 'Fasal katayi poori',
                          'HARVEST_PLANNED' => 'Planned fasal katayi',
                          _ => type.isEmpty ? 'Activity' : type,
                        };
                        final subtitle = switch (type) {
                          'PANI' => [
                              formatMinutes((row['minutes'] as num?)?.toInt() ?? 0),
                              (row['source'] ?? 'Paani').toString(),
                              if ((row['borrowedMinutes'] as num?)?.toInt() case final borrowed? when borrowed > 0)
                                'Liye: ${formatMinutes(borrowed)}',
                            ].join(' · '),
                          'KHAD' || 'DAWAI' || 'HARA_BEEJ' || 'FASAL' || 'KHET_STOCK_USE' =>
                            [
                              (row['title'] ?? row['purpose'] ?? row['seedName'] ?? '').toString(),
                              if (_amount(row['price']) > 0) '₹${_amount(row['price']).toStringAsFixed(0)}',
                              if ((row['note'] ?? '').toString().trim().isNotEmpty) row['note'].toString(),
                            ].where((part) => part.isNotEmpty).join(' · '),
                          _ => '',
                        };
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: Icon(switch (type) {
                            'PANI' => Icons.water_drop_outlined,
                            'KHAD' => Icons.science_outlined,
                            'DAWAI' => Icons.medication_outlined,
                            'FASAL' => Icons.grass_outlined,
                            'KHET_STOCK_USE' => Icons.inventory_2_outlined,
                            'HARVEST_EVENT' => Icons.agriculture_outlined,
                            'HARVEST_PLANNED' => Icons.event_outlined,
                            _ => Icons.history,
                          }),
                          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text([
                            if (date != null) DateFormat('dd MMM yyyy').format(date),
                            if (subtitle.isNotEmpty) subtitle,
                          ].join(' · ')),
                        );
                      }).toList()),
                  _section('Fasal history', crops.isEmpty
                    ? [const Text('Abhi fasal ki entry nahi hai.')]
                    : crops.map((row) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _activity(
                            row,
                            (row['cropName'] ?? row['title'] ?? 'Fasal').toString(),
                            row['harvested'] == true
                              ? 'Katayi poori · ' + ((row['harvestDate'] ?? '').toString().isEmpty ? '' : DateFormat('dd MMM yyyy').format(DateTime.tryParse(row['harvestDate'].toString()) ?? DateTime.now()))
                              : row['plannedHarvestDate'] is String
                                  ? 'Planned katayi · ' + DateFormat('dd MMM yyyy').format(DateTime.tryParse(row['plannedHarvestDate'].toString()) ?? DateTime.now())
                                  : (row['note'] ?? '').toString(),
                          ),
                          if (row['harvested'] != true && widget.plot['isMine'] == true)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () => _markHarvested(row),
                                icon: const Icon(Icons.done_all),
                                label: const Text('Fasal kat gayi — mark karein'),
                              ),
                            ),
                          const Divider(height: 8),
                        ],
                      )).toList()),
                  _section('Hara beej / pashu chara', fodder.isEmpty
                    ? [const Text('Abhi hara beej ki entry nahi hai.')]
                    : fodder.map((row) => _activity(row, (row['seedName'] ?? row['title'] ?? 'Hara beej').toString(), 'Kyari: ' + (row['kyariNumber'] ?? '-').toString())).toList()),
                  _section('Dawai history', dawai.isEmpty
                    ? [const Text('Abhi dawai ki entry nahi hai.')]
                    : dawai.map((row) => _activity(
                        row,
                        (row['title'] ?? 'Dawai').toString(),
                        (row['purpose'] ?? '').toString() + ' · Fasal: ' + (row['cropAtUse'] ?? 'Not recorded').toString() + ' · ₹' + (row['price'] ?? 0).toString(),
                      )).toList()),
                  _section('Khaad history', khaad.isEmpty
                    ? [const Text('Abhi khaad ki entry nahi hai.')]
                    : khaad.map((row) => _activity(
                        row,
                        (row['title'] ?? 'Khaad').toString(),
                        '${row['fertilizerType'] ?? row['purpose'] ?? ''} · Fasal: ${row['cropAtUse'] ?? 'Not recorded'} · ₹${row['price'] ?? 0}',
                      )).toList()),
                  _section('Paani history', pani.isEmpty
                    ? [const Text('Abhi paani ki entry nahi hai.')]
                    : pani.map((row) {
                        final date = _date(row);
                        final dateText = date == null ? 'Date nahi' : DateFormat('dd MMM yyyy').format(date);
                        final minutes = (row['minutes'] as num?)?.toInt() ?? 0;
                        final source = (row['source'] ?? row['wellType'] ?? 'Paani').toString();
                        final direction = (row['direction'] ?? '').toString();
                        final contact = (row['contact'] ?? row['borrowedContact'] ?? '').toString();
                        final label = [
                          formatMinutes(minutes),
                          source,
                          if (direction.isNotEmpty) direction,
                          if (contact.isNotEmpty) 'Se: $contact',
                        ].join(' · ');
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: const Icon(Icons.water_drop_outlined),
                          title: Text(dateText, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(label),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _showWaterDetails(row, totalKyaris),
                        );
                      }).toList()),
                ]),
              ),
              const SizedBox(height: 8),
              if (widget.plot['isMine'] == true)
                Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton.icon(
                    onPressed: selectedCompleted ? null : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AddPaniScreen(initialPlotId: widget.plot['id'] as String))),
                    icon: const Icon(Icons.water_drop_outlined), label: const Text('Add Pani'),
                  ),
                  OutlinedButton.icon(
                    onPressed: hasActiveCycle ? null : () async {
                      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AddKhetItemScreen(
                        type: 'FASAL',
                        initialPlotId: widget.plot['id'] as String,
                        initialSeason: _season,
                        initialYear: _year,
                      )));
                      if (mounted) setState(() => _selectedCropCycleId = null);
                    },
                    icon: const Icon(Icons.grass_outlined),
                    label: Text(hasActiveCycle ? 'Pehle current fasal ka harvest karein' : 'Nayi Fasal Shuru Karein'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AddKhetItemScreen(type: 'HARA_BEEJ', initialPlotId: widget.plot['id'] as String))),
                    icon: const Icon(Icons.pets_outlined), label: const Text('Add Hara Beej'),
                  ),
                  OutlinedButton.icon(
                    onPressed: selectedCompleted ? null : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AddKhetItemScreen(type: 'DAWAI', initialPlotId: widget.plot['id'] as String, initialSeason: _season, initialYear: _year))),
                    icon: const Icon(Icons.medication_outlined), label: const Text('Add Dawai'),
                  ),
                  OutlinedButton.icon(
                    onPressed: selectedCompleted ? null : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AddKhetItemScreen(type: 'KHAD', initialPlotId: widget.plot['id'] as String, initialSeason: _season, initialYear: _year))),
                    icon: const Icon(Icons.science_outlined), label: const Text('Add Khaad'),
                  ),
                  OutlinedButton.icon(
                    onPressed: latestCrop == null ? null : () => _markHarvested(latestCrop),
                    icon: const Icon(Icons.agriculture_outlined), label: const Text('Crop Cutting'),
                  ),
                ])
              else
                const Text('Yeh side wala killa hai. Iske liye apni entry dropdown se nahi banegi.',
                  style: TextStyle(color: Colors.black54, fontSize: 12)),
            ]),
          ),
        );
      },
    );
  }
}
