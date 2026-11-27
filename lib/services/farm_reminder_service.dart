import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class FarmReminderService {
  FarmReminderService._();

  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    tzdata.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    }
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(settings);
    _initialized = true;
  }

  static Future<void> schedule({
    required int id,
    required DateTime scheduledAt,
    required String title,
    required String body,
  }) async {
    await initialize();
    if (!scheduledAt.isAfter(DateTime.now())) {
      throw ArgumentError('Reminder date and time must be in the future.');
    }
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final permission = await android?.requestNotificationsPermission();
    if (permission == false) {
      throw StateError('KHATA notifications permission was not granted.');
    }
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(scheduledAt, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'khata_farm_reminders',
          'Kheti reminders',
          channelDescription: 'Future dawai and farm activity reminders',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: 'khata-farm-reminder-' + id.toString(),
    );
  }

  static Future<void> cancel(int id) async {
    await initialize();
    await _plugin.cancel(id);
  }
}
