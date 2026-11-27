import 'package:flutter/material.dart';
import '../services/storage_backup_service.dart';

String plotLabel(Map<String, dynamic> plot) {
  final number = (plot['number'] as String? ?? '').trim();
  final name = (plot['name'] as String? ?? '').trim();
  if (number.isEmpty && name.isEmpty) return 'Killa';
  if (number.isEmpty) return name;
  if (name.isEmpty) return 'Killa $number';
  return 'Killa $number · $name';
}

String plotLabelForId(StorageBackupService storage, dynamic plotId) {
  if (plotId == null || plotId.toString().isEmpty) return '';
  for (final plot in storage.records('plots')) {
    if (plot['id'] == plotId) return plotLabel(plot);
  }
  return '';
}

class KhetPlotDropdown extends StatelessWidget {
  const KhetPlotDropdown({required this.selectedId, required this.onChanged, super.key});
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final plots = StorageBackupService.instance.records('plots')
        .where((plot) => plot['isMine'] == true)
        .toList();
    final current = plots.any((plot) => plot['id'] == selectedId) ? selectedId : null;
    return DropdownButtonFormField<String>(
      initialValue: current,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Killa / Field (optional)',
        prefixIcon: Icon(Icons.grid_view_outlined),
      ),
      items: plots.map((plot) => DropdownMenuItem<String>(
        value: plot['id'] as String,
        child: Text(plotLabel(plot), overflow: TextOverflow.ellipsis),
      )).toList(),
      onChanged: onChanged,
    );
  }
}
