import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gcc_app/main.dart';
import 'package:gcc_app/state/app_state.dart';
import 'package:gcc_app/state/data_store.dart';
import 'package:gcc_app/state/drone_controller.dart';
import 'package:gcc_app/state/plan_state.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _shell(AppState app) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: app),
        // DataStore deliberately NOT started: no timers, no network.
        ChangeNotifierProvider(create: (_) => DataStore(app)),
        ChangeNotifierProvider(create: (_) => PlanState()),
        // DroneController not connected: no socket, no MAVLink.
        ChangeNotifierProvider(create: (_) => DroneController()),
      ],
      child: MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFFB91C1C), brightness: Brightness.dark),
          useMaterial3: true,
        ),
        home: const GccShell(),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('every tab renders its honest empty/gated state',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final app = AppState();
    await app.load();

    await tester.pumpWidget(_shell(app));
    await tester.pump();

    // Map (home): no-offline-map banner because nothing is configured.
    expect(find.textContaining('No offline map loaded'), findsOneWidget);

    // Live Feed: gated behind login when no credentials exist.
    await tester.tap(find.text('Live Feed'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Log in with your personnel ID'), findsOneWidget);

    // Nodes: no node in range yet.
    await tester.tap(find.text('Nodes'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No node in range yet'), findsOneWidget);

    // Personnel: HQ gate.
    await tester.tap(find.text('Personnel'));
    await tester.pumpAndSettle();
    expect(find.textContaining('needs an HQ login'), findsOneWidget);

    // Announcements renders (empty list state).
    await tester.tap(find.text('Announcements'));
    await tester.pumpAndSettle();
    expect(find.text('No announcements.'), findsOneWidget);

    // Drone tab: disconnected, so no command surfaces. The safety
    // invariant is that Arm never appears without a live MAVLink link.
    await tester.tap(find.text('Drone'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Not connected to the flight controller'),
        findsOneWidget);
    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Arm'), findsNothing);
    expect(find.text('Motor 1'), findsNothing);

    // Settings: pinning state is explicit when no CA is loaded.
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Fleet CA: NOT LOADED'), findsOneWidget);
    expect(find.textContaining('Break-glass HQ key'), findsOneWidget);
  });

  testWidgets('HQ break-glass key unlocks personnel and compose surfaces',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({'hq_api_key': 'bg_key'});
    final app = AppState();
    await app.load();

    await tester.pumpWidget(_shell(app));
    await tester.pump();

    await tester.tap(find.text('Personnel'));
    await tester.pumpAndSettle();
    expect(find.text('Issue credentials'), findsOneWidget);
    expect(find.textContaining('Records sync fleet-wide'), findsOneWidget);

    await tester.tap(find.text('Announcements'));
    await tester.pumpAndSettle();
    expect(find.text('Compose'), findsOneWidget);
  });
}
