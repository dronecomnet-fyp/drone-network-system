/// NotificationService: the high-priority "drone found" notification
/// (file 06). This is the achievable behavior per master plan R4: no
/// mobile OS lets an app foreground itself from a background scan, so the
/// deliverable is detection -> high-priority notification with sound ->
/// user taps -> app opens on the Drone found screen.
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String _channelId = 'rescue_drone_found';
  static const int droneFoundId = 1001;

  /// Payload key so the app can route to the Drone found screen when the
  /// user taps the notification.
  static const String dronePayloadPrefix = 'drone:';

  static Future<void> initialize(
      {void Function(String payload)? onTap}) async {
    const androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          onTap?.call(payload);
        }
      },
    );

    // High-importance channel: heads-up with sound, so a locked phone
    // surfaces it (file 06 acceptance 1).
    const channel = AndroidNotificationChannel(
      _channelId,
      'Rescue drone nearby',
      description: 'Alerts when a rescue drone is detected over Bluetooth.',
      importance: Importance.max,
      playSound: true,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  static Future<void> requestPermission() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// [nodeLabel] and [ssid] come from the aux module's BLE service data
  /// (`nodeId|ssid`, file 03).
  static Future<void> showDroneFound(String nodeLabel, String ssid) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        'Rescue drone nearby',
        channelDescription:
            'Alerts when a rescue drone is detected over Bluetooth.',
        importance: Importance.max,
        priority: Priority.high,
        fullScreenIntent: true,
        category: AndroidNotificationCategory.alarm,
      ),
    );
    await _plugin.show(
      droneFoundId,
      'Rescue drone nearby',
      'Tap to connect and send your location. Network: $ssid',
      details,
      payload: '$dronePayloadPrefix$nodeLabel|$ssid',
    );
  }

  static Future<void> cancelDroneFound() async {
    await _plugin.cancel(droneFoundId);
  }
}
