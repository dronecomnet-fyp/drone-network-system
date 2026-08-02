/// Emergency public app (file 06). Android-first: keeps a small local
/// location log, watches for a rescue drone's BLE advertisement, and once
/// joined to the drone WiFi uploads stored locations and lets the user
/// send an SOS. Privacy is a design goal: nothing leaves the phone until
/// the user is at a drone or presses SOS.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/drone_found_screen.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/ble_watch_service.dart';
import 'services/location_logger.dart';
import 'services/network_binder.dart';
import 'services/notification_service.dart';
import 'state/app_controller.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Route this app over Wi-Fi even though the drone AP has no internet;
  // otherwise Android sends everything out over mobile data, where
  // 10.42.0.1 has no route, and the SOS would silently fail (bench finding
  // 2026-07-14). A citizen cannot be expected to know to disable mobile
  // data before asking for help.
  await NetworkBinder.bindToWifi();

  // Best-effort service init; each guards its own platform availability so
  // the app still renders in tests / on desktop.
  try {
    await LocationLogger.initialize();
  } catch (_) {}
  try {
    await BleWatchService.initForegroundTask();
  } catch (_) {}
  try {
    await NotificationService.initialize(onTap: _handleNotificationTap);
  } catch (_) {}

  final controller = AppController();
  await controller.load();
  runApp(EmergencyApp(controller: controller));
}

void _handleNotificationTap(String payload) {
  // payload = "drone:<nodeLabel>|<ssid>"
  if (!payload.startsWith(NotificationService.dronePayloadPrefix)) return;
  final body = payload.substring(NotificationService.dronePayloadPrefix.length);
  final parts = body.split('|');
  if (parts.length < 2) return;
  navigatorKey.currentState?.push(
    MaterialPageRoute(
      builder: (_) =>
          DroneFoundScreen(nodeLabel: parts[0], ssid: parts[1]),
    ),
  );
}

class EmergencyApp extends StatefulWidget {
  final AppController controller;

  const EmergencyApp({super.key, required this.controller});

  @override
  State<EmergencyApp> createState() => _EmergencyAppState();
}

class _EmergencyAppState extends State<EmergencyApp> {
  @override
  void initState() {
    super.initState();
    // Auto-open lives here rather than in the controller because it is
    // navigation. Only fires for a NEW drone and only with consent; see
    // AppController._onSighting.
    widget.controller.onAutoOpen = _openDroneFound;
  }

  @override
  void dispose() {
    widget.controller.onAutoOpen = null;
    super.dispose();
  }

  void _openDroneFound(DroneSighting s) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    // Do not stack a second copy if they are already looking at it.
    if (_droneScreenOpen) return;
    _droneScreenOpen = true;
    nav
        .push(MaterialPageRoute(
          builder: (_) =>
              DroneFoundScreen(nodeLabel: s.nodeLabel, ssid: s.ssid),
        ))
        .then((_) => _droneScreenOpen = false);
  }

  bool _droneScreenOpen = false;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ChangeNotifierProvider.value(
      value: controller,
      child: MaterialApp(
        title: 'Rescue Emergency',
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.red,
            brightness: Brightness.light,
          ),
        ),
        home: Consumer<AppController>(
          builder: (context, c, _) =>
              c.onboarded ? const HomeScreen() : const OnboardingScreen(),
        ),
      ),
    );
  }
}
