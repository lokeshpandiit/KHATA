import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../screens/khet_screen.dart';
import '../services/storage_backup_service.dart';
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

  DateTime? _date(Map<String, dynamic> row) {
    for (final key in ['date', 'sowingDate', 'applicationDate']) {
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

  Future<void> _markHarvested(Map<String, dynamic> crop) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 8),
      lastDate: DateTime(now.year + 8),
    );
    if (picked == null || !mounted) return;
    final updated = Map<String, dynamic>.from(crop)
      ..['harvested'] = true
      ..['harvestDate'] = DateTime(picked.year, picked.month, picked.day).toIso8601String()
      ..['harvestedAt'] = DateTime.now().toIso8601String();
    await StorageBackupService.instance.updateRecord('khet', crop['id'].toString(), updated);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fasal katne ka record save ho gaya. Ab nayi fasal add kar sakte hain.')));
      setState(() {});
    }
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
        final entries = _latest(storage.records('khet').where((row) =>
          row['plotId'] == widget.plot['id'] &&
          row['season'] == _season &&
          row['year'] == _year
        ).toList());
        final pani = entries.where((row) => row['type'] == 'PANI').toList();
        final crops = entries.where((row) => row['type'] == 'FASAL').toList();
        final fodder = entries.where((row) => row['type'] == 'HARA_BEEJ').toList();
        final dawai = entries.where((row) => row['type'] == 'DAWAI').toList();
        final latestPani = pani.isEmpty ? null : pani.first;
        final activeCrops = crops.where((row) => row['harvested'] != true).toList();
        final latestCrop = activeCrops.isEmpty ? null : activeCrops.first;
        final totalKyaris = (widget.plot['totalKyaris'] as num?)?.toInt() ?? 0;
        final wetKyaris = (latestPani?['wetKyaris'] as num?)?.toInt() ?? 0;
        final remainingKyaris = latestPani == null
            ? totalKyaris
            : ((latestPani['remainingKyaris'] as num?)?.toInt() ?? (totalKyaris - wetKyaris).clamp(0, totalKyaris));
        final totalMinutes = pani.fold<int>(0, (sum, row) => sum + ((row['minutes'] as num?)?.toInt() ?? 0));
        final cropName = latestCrop == null ? 'Fasal record nahi hai' : (latestCrop['cropName'] ?? latestCrop['title'] ?? 'Fasal').toString() + (latestCrop['harvested'] == true ? ' (Kat chuki)' : '');

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
              SeasonYearFields(
                season: _season,
                year: _year,
                onSeasonChanged: (value) => setState(() => _season = value),
                onYearChanged: (value) => setState(() => _year = value),
              ),
              const SizedBox(height: 8),
              Text('Sirf $_season $_year ka khet record', style: const TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 10),
              Expanded(
                child: ListView(children: [
                  _section('Khet summary', [
                    _line('Total kyari', totalKyaris == 0 ? 'Map Edit mein set karein' : totalKyaris.toString()),
                    _line('Current fasal', cropName),
                    _line('Paani entries', pani.length.toString() + ' baar'),
                    _line('Total paani time', formatMinutes(totalMinutes)),
                    if (latestPani != null) ...[
                      _line('Is baar bheegi kyari', wetKyaris.toString()),
                      _line('Abhi baaki kyari', remainingKyaris.toString()),
                    ],
                  ]),
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
                  _section('Paani history', pani.isEmpty
                    ? [const Text('Abhi paani ki entry nahi hai.')]
                    : pani.map((row) => _activity(
                        row,
                        formatMinutes((row['minutes'] as num?)?.toInt() ?? 0) + ' · ' + (row['source'] ?? '').toString(),
                        'Bheegi ' + (row['wetKyaris'] ?? 0).toString() + ' / ' + (row['totalKyarisSnapshot'] ?? totalKyaris).toString() + ', baaki ' + (row['remainingKyaris'] ?? '-').toString(),
                      )).toList()),
                ]),
              ),
              const SizedBox(height: 8),
              if (widget.plot['isMine'] == true)
                Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AddPaniScreen(initialPlotId: widget.plot['id'] as String))),
                    icon: const Icon(Icons.water_drop_outlined), label: const Text('Add Pani'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AddKhetItemScreen(
                      type: 'FASAL',
                      initialPlotId: widget.plot['id'] as String,
                      initialSeason: _season,
                      initialYear: _year,
                    ))),
                    icon: const Icon(Icons.grass_outlined), label: const Text('Nayi Fasal Shuru Karein'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AddKhetItemScreen(type: 'HARA_BEEJ', initialPlotId: widget.plot['id'] as String))),
                    icon: const Icon(Icons.pets_outlined), label: const Text('Add Hara Beej'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AddKhetItemScreen(type: 'DAWAI', initialPlotId: widget.plot['id'] as String, initialSeason: _season, initialYear: _year))),
                    icon: const Icon(Icons.medication_outlined), label: const Text('Add Dawai'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AddKhetItemScreen(type: 'KHAD', initialPlotId: widget.plot['id'] as String, initialSeason: _season, initialYear: _year))),
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
