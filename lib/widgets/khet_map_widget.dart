import 'package:flutter/material.dart';
import '../services/storage_backup_service.dart';
import 'plot_selector.dart';
import 'plot_details_sheet.dart';

class KhetMapWidget extends StatefulWidget {
  const KhetMapWidget({super.key});
  @override
  State<KhetMapWidget> createState() => _KhetMapWidgetState();
}

class _KhetMapWidgetState extends State<KhetMapWidget> {
  final _storage = StorageBackupService.instance;
  bool _editing = false;
  bool _saving = false;

  Future<void> _editPlot(Map<String, dynamic> plot) async {
    final numberController = TextEditingController(text: plot['number'] as String? ?? '');
    final nameController = TextEditingController(text: plot['name'] as String? ?? '');
    final totalKyarisController = TextEditingController(text: (plot['totalKyaris'] as num?)?.toInt().toString() ?? '');
    var isMine = plot['isMine'] as bool? ?? false;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Edit Killa ${plotLabel(plot)}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: numberController, autofocus: true,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Killa number / code', hintText: 'e.g. 3, 5, J, S')),
              const SizedBox(height: 12),
              TextField(controller: nameController, textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Khet name / pehchan', hintText: 'Kuan wala kila, Kothe wala kila')),
              const SizedBox(height: 12),
              TextField(
                controller: totalKyarisController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Is kille mein total kitni kyari hain?'),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: isMine,
                onChanged: (value) => setDialogState(() => isMine = value ?? false),
                title: const Text('Mera khet (dropdown mein dikhaye)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, {
              'number': numberController.text.trim(),
              'name': nameController.text.trim(),
              'isMine': isMine,
              'totalKyaris': int.tryParse(totalKyarisController.text.trim()) ?? 0,
            }), child: const Text('Save')),
          ],
        ),
      ),
    );
    numberController.dispose();
    nameController.dispose();
    totalKyarisController.dispose();
    if (result == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final updated = Map<String, dynamic>.from(plot)
        ..addAll(result)
        ..['updatedAt'] = DateTime.now().toIso8601String();
      await _storage.updateRecord('plots', plot['id'] as String, updated);
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Killa details saved')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save killa: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openPlotDetails(Map<String, dynamic> plot) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.92,
        child: KhetPlotDetailsSheet(plot: plot),
      ),
    );
    if (mounted) setState(() {});
  }

  Widget _plotBadge(Map<String, dynamic> plot, double cellWidth) {
    final number = (plot['number'] as String? ?? '').trim();
    final name = (plot['name'] as String? ?? '').trim();
    final empty = number.isEmpty && name.isEmpty;
    return Container(
      constraints: BoxConstraints(maxWidth: cellWidth * 0.94),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      decoration: BoxDecoration(
        color: empty && !_editing ? Colors.transparent : const Color(0xE6283328),
        borderRadius: BorderRadius.circular(9),
        border: _editing ? Border.all(color: Colors.white, width: 1.4) : null,
      ),
      child: empty
          ? (_editing ? const Icon(Icons.add, color: Colors.white, size: 15) : const SizedBox.shrink())
          : Column(mainAxisSize: MainAxisSize.min, children: [
              if (number.isNotEmpty)
                Text(number, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15, height: 1)),
              if (name.isNotEmpty)
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 8, height: 1.1)),
            ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plots = _storage.records('plots');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
          child: Row(children: [
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Mera Khet Map', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              SizedBox(height: 2),
              Text('Road aur pakka pani nala', style: TextStyle(fontSize: 11, color: Colors.black54)),
            ])),
            if (_saving)
              const Padding(padding: EdgeInsets.all(10), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: LayoutBuilder(builder: (context, constraints) {
              final width = constraints.maxWidth;
              final height = constraints.maxHeight;
              const left = 0.1268, top = 0.1615, cellWidth = 0.1683, cellHeight = 0.1497;
              return ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Stack(fit: StackFit.expand, children: [
                  Image.asset('assets/khet_map.jpg', fit: BoxFit.fill),
                  for (final plot in plots)
                    Positioned(
                      left: width * (left + (plot['column'] as num).toDouble() * cellWidth),
                      top: height * (top + (plot['row'] as num).toDouble() * cellHeight),
                      width: width * cellWidth,
                      height: height * cellHeight,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _editing ? () => _editPlot(plot) : () => _openPlotDetails(plot),
                          child: Center(child: _plotBadge(plot, width * cellWidth)),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 5, right: 5,
                    child: Material(
                      color: Colors.white.withValues(alpha: 0.94),
                      borderRadius: BorderRadius.circular(20),
                      elevation: 2,
                      child: TextButton.icon(
                        onPressed: _saving ? null : () => setState(() => _editing = !_editing),
                        icon: Icon(_editing ? Icons.check : Icons.edit_outlined, size: 15),
                        label: Text(_editing ? 'Done' : 'Edit', style: const TextStyle(fontSize: 11)),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ),
                  ),
                ]),
              );
            }),
          ),
        ),
        if (_editing)
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Text('Kisi bhi kille ke box par tap karke uska number aur naam badlein.',
              style: TextStyle(fontSize: 12, color: Color(0xFF176B52))),
          ),
      ]),
    );
  }
}
