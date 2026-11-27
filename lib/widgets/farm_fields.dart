import 'package:flutter/material.dart';

class SeasonYearFields extends StatelessWidget {
  const SeasonYearFields({
    required this.season,
    required this.year,
    required this.onSeasonChanged,
    required this.onYearChanged,
    super.key,
  });

  final String season;
  final int year;
  final ValueChanged<String> onSeasonChanged;
  final ValueChanged<int> onYearChanged;

  @override
  Widget build(BuildContext context) {
    final currentYear = DateTime.now().year;
    final years = List<int>.generate(10, (index) => currentYear - 3 + index);
    if (!years.contains(year)) years.add(year);
    years.sort();
    return Row(children: [
      Expanded(child: DropdownButtonFormField<String>(
        initialValue: season,
        decoration: const InputDecoration(labelText: 'Season', prefixIcon: Icon(Icons.wb_sunny_outlined)),
        items: const [
          DropdownMenuItem(value: 'Rabi', child: Text('Rabi')),
          DropdownMenuItem(value: 'Kharif', child: Text('Kharif')),
        ],
        onChanged: (value) { if (value != null) onSeasonChanged(value); },
      )),
      const SizedBox(width: 10),
      Expanded(child: DropdownButtonFormField<int>(
        initialValue: year,
        decoration: const InputDecoration(labelText: 'Year', prefixIcon: Icon(Icons.calendar_today_outlined)),
        items: years.map((value) => DropdownMenuItem(value: value, child: Text(value.toString()))).toList(),
        onChanged: (value) { if (value != null) onYearChanged(value); },
      )),
    ]);
  }
}
