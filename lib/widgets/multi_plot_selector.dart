import 'package:flutter/material.dart';
import '../services/storage_backup_service.dart';
import 'plot_selector.dart';

/// Select multiple owned plots and choose either the whole plot or a kyari count
/// for each one. The map returned to the parent is plotId -> selected kyari count.
class KhetMultiPlotSelector extends StatefulWidget {
  const KhetMultiPlotSelector({
    required this.initialSelection,
    required this.onChanged,
    super.key,
  });

  final Map<String, int> initialSelection;
  final ValueChanged<Map<String, int>> onChanged;

  @override
  State<KhetMultiPlotSelector> createState() => _KhetMultiPlotSelectorState();
}

class _KhetMultiPlotSelectorState extends State<KhetMultiPlotSelector> {
  final _storage = StorageBackupService.instance;
  late Map<String, int> _selected;

  List<Map<String, dynamic>> get _plots => _storage.records('plots')
      .where((plot) => plot['isMine'] == true).toList();

  @override
  void initState() {
    super.initState();
    _selected = Map<String, int>.from(widget.initialSelection);
  }

  void _publish() => widget.onChanged(Map<String, int>.from(_selected));

  @override
  Widget build(BuildContext context) {
    final plots = _plots;
    if (plots.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text('Pehle Khet Map ke Edit option mein apne kille add karein.'),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Kille select karein (ek se zyada chun sakte hain)',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        ...plots.map((plot) {
          final id = plot['id'] as String;
          final total = (plot['totalKyaris'] as num?)?.toInt() ?? 0;
          final selected = _selected.containsKey(id);
          final selectedCount = _selected[id] ?? total;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                children: [
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: selected,
                    title: Text(plotLabel(plot), style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(total > 0 ? 'Total kyari: $total' : 'Map Edit mein total kyari set karein'),
                    onChanged: (checked) {
                      setState(() {
                        if (checked == true) {
                          _selected[id] = total > 0 ? total : 0;
                        } else {
                          _selected.remove(id);
                        }
                      });
                      _publish();
                    },
                  ),
                  if (selected && total > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 40, right: 8, bottom: 8),
                      child: DropdownButtonFormField<int>(
                        key: ValueKey('$id-$selectedCount'),
                        initialValue: selectedCount > 0 && selectedCount <= total ? selectedCount : total,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Kitni kyari?',
                          isDense: true,
                        ),
                        items: [
                          DropdownMenuItem<int>(
                            value: total,
                            child: Text('Full Killa · sabhi $total kyari'),
                          ),
                          for (var count = 1; count < total; count++)
                            DropdownMenuItem<int>(
                              value: count,
                              child: Text('Partial · $count kyari'),
                            ),
                        ],
                        onChanged: (count) {
                          if (count == null) return;
                          setState(() => _selected[id] = count);
                          _publish();
                        },
                      ),
                    ),
                  if (selected && total <= 0)
                    const Padding(
                      padding: EdgeInsets.only(left: 40, right: 8, bottom: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Is kille ki kyari sankhya Map ke Edit se set karein.',
                            style: TextStyle(color: Colors.red, fontSize: 12)),
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
        if (_selected.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 8),
            child: Text('${_selected.length} kille selected',
                style: const TextStyle(color: Color(0xFF176B52), fontWeight: FontWeight.w700)),
          ),
      ],
    );
  }
}
