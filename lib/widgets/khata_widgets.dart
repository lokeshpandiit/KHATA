import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

String monthKey(DateTime date) => DateFormat('yyyy-MM').format(date);
String monthLabel(String key) => DateFormat('MMMM yyyy').format(DateTime.parse('$key-01'));
String dateLabel(DateTime date) => DateFormat('EEE, d MMM yyyy').format(date);
String timeLabel(DateTime date) => DateFormat('h:mm a').format(date);

List<String> availableMonths(Iterable<Map<String, dynamic>> rows) {
  final months = rows
      .map((row) => row['date'] as String?)
      .whereType<String>()
      .map((date) => monthKey(DateTime.tryParse(date) ?? DateTime.now()))
      .toSet()
      .toList()
    ..sort((a, b) => b.compareTo(a));
  return ['All months', ...months];
}

Widget monthFilter(
  String value,
  List<String> options,
  ValueChanged<String?> onChanged,
) {
  return DropdownButtonFormField<String>(
    value: value,
    isExpanded: true,
    decoration: const InputDecoration(
      prefixIcon: Icon(Icons.calendar_month_outlined),
      labelText: 'Month',
      border: OutlineInputBorder(),
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
    items: options
        .map((option) => DropdownMenuItem(
              value: option,
              child: Text(
                option == 'All months' ? option : monthLabel(option),
                overflow: TextOverflow.ellipsis,
              ),
            ))
        .toList(),
    onChanged: onChanged,
  );
}

Widget mediaThumbnail(String? path, {double size = 68}) {
  if (path == null || path.isEmpty || !File(path).existsSync()) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF1EC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.image_outlined, color: Color(0xFF648173)),
    );
  }
  return ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: Image.file(
      File(path),
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => Container(
        width: size,
        height: size,
        color: const Color(0xFFEAF1EC),
        child: const Icon(Icons.broken_image_outlined),
      ),
    ),
  );
}

Widget searchField(ValueChanged<String> onChanged) => TextField(
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Search',
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE8ECE8)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE8ECE8)),
        ),
      ),
    );

Widget emptyState(String title, String subtitle) => Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_outlined, size: 52, color: Colors.black38),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );

Widget recordDateTime(String value) {
  final date = DateTime.tryParse(value);
  if (date == null) return Text(value);
  return Text('${dateLabel(date)}  ·  ${timeLabel(date)}');
}
