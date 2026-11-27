import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'farm_reminder_service.dart';
import 'storage_backup_service.dart';

class FutureDateReminderPrompt {
  FutureDateReminderPrompt._();

  static Future<void> check(
    BuildContext context, {
    required DateTime date,
    required String taskTitle,
    String details = '',
  }) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final selectedDay = DateUtils.dateOnly(date);
    if (!selectedDay.isAfter(today) || !context.mounted) return;

    final addReminder = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Future date selected'),
        content: Text(
          'Aapne future ki date chuni hai: '
          '${DateFormat('dd MMM yyyy').format(selectedDay)}.\n\n'
          'Kya aap ye kaam us din karenge? Kya KHATA aapko is tarikh par '
          'yaad dilaye?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Sirf date save karein'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.notifications_active_outlined),
            label: const Text('Reminder lagayein'),
          ),
        ],
      ),
    );

    if (addReminder != true || !context.mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
    );
    if (time == null || !context.mounted) return;

    final scheduledAt = DateTime(
      selectedDay.year,
      selectedDay.month,
      selectedDay.day,
      time.hour,
      time.minute,
    );
    if (!scheduledAt.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reminder ka time abhi se future mein hona chahiye.'),
        ),
      );
      return;
    }

    final id = DateTime.now().microsecondsSinceEpoch;
    final notificationId = id % 2147483647;
    final record = <String, dynamic>{
      'id': 'plan-$id',
      'notificationId': notificationId,
      'title': taskTitle.trim().isEmpty ? 'Future farm work' : taskTitle.trim(),
      'note': details,
      'date': scheduledAt.toIso8601String(),
      'done': false,
      'createdAt': DateTime.now().toIso8601String(),
    };

    final storage = StorageBackupService.instance;
    await storage.addRecord('plans', record);
    try {
      await FarmReminderService.schedule(
        id: notificationId,
        scheduledAt: scheduledAt,
        title: 'KHATA Reminder: ${record['title']}',
        body: details.isEmpty ? 'Aaj ka planned kaam yaad rakhein.' : details,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Future reminder set ho gaya.')),
        );
      }
    } catch (error) {
      await storage.deleteRecord('plans', record['id'] as String);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reminder set nahi hua: $error')),
        );
      }
    }
  }
}
