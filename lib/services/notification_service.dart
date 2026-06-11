import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static final _tapController = StreamController<String?>.broadcast();
  static bool _timeZonesInitialized = false;

  static Stream<String?> get notificationTaps => _tapController.stream;

  final FlutterLocalNotificationsPlugin _plugin;

  Future<void> initialize() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const windows = WindowsInitializationSettings(
      appName: 'Scrap Management System',
      appUserModelId: 'com.mypillar.scrap.scrap_management_system',
      guid: '9d3c0ef5-8f78-4e7e-a6d5-dc26d1d8f21c',
    );
    const settings = InitializationSettings(
      android: android,
      iOS: darwin,
      macOS: darwin,
      windows: windows,
    );
    try {
      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: (response) {
          _tapController.add(response.payload);
        },
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } catch (_) {
      return;
    }
  }

  Future<void> showPaymentReminder({
    required int id,
    required String title,
    required String body,
  }) {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'payments',
        'Payment reminders',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
    );
    return _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }

  Future<void> scheduleDailyStockVerificationReminder({
    required int id,
    required int hour,
    required int minute,
    String payload = 'manual_stock_reminder',
  }) async {
    try {
      _ensureTimeZone();
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'stock_reminders',
          'Stock verification reminders',
          channelDescription: 'Manual WhatsApp stock reminder alerts',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
      );
      await _plugin.zonedSchedule(
        id: id,
        title: 'Daily Stock Verification Reminder',
        body: 'Tap to send WhatsApp reminder to supervisor.',
        scheduledDate: _nextReminderDate(hour, minute),
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: payload,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (_) {
      return;
    }
  }

  Future<void> scheduleDailyPaymentReminder({
    required int id,
    required int hour,
    required int minute,
    required String body,
    String payload = 'payment_reminder',
  }) async {
    try {
      _ensureTimeZone();
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'payments',
          'Payment reminders',
          channelDescription: 'Pending customer payment reminder alerts',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
      );
      await _plugin.zonedSchedule(
        id: id,
        title: 'Pending Payment Reminder',
        body: body,
        scheduledDate: _nextReminderDate(hour, minute),
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: payload,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (_) {
      return;
    }
  }

  Future<void> showStockVerificationReminder({
    required int id,
    String payload = 'manual_stock_reminder',
  }) {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'stock_reminders',
        'Stock verification reminders',
        channelDescription: 'Manual WhatsApp stock reminder alerts',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
    );
    return _plugin.show(
      id: id,
      title: 'Daily Stock Verification Reminder',
      body: 'Tap to send WhatsApp reminder to supervisor.',
      notificationDetails: details,
      payload: payload,
    );
  }

  Future<void> cancel({required int id}) async {
    try {
      await _plugin.cancel(id: id);
    } catch (_) {
      return;
    }
  }

  static void _ensureTimeZone() {
    if (_timeZonesInitialized) {
      return;
    }
    tz_data.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
    } catch (_) {
      // Keep the package default if the bundled location data is unavailable.
    }
    _timeZonesInitialized = true;
  }

  static tz.TZDateTime _nextReminderDate(int hour, int minute) {
    final normalizedHour = hour.clamp(0, 23).toInt();
    final normalizedMinute = minute.clamp(0, 59).toInt();
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      normalizedHour,
      normalizedMinute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
