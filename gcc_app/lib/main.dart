/// Rescue Mesh Ground Control Center (file 04).
///
/// Delivered as an installable Windows build for the ground laptop
/// (docs/RELEASES.md); the macOS target exists for development. The
/// laptop joins whichever drone AP is in range; this app talks to that
/// one node and shows data age everywhere instead of pretending other
/// nodes are live.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/announcements_screen.dart';
import 'screens/drone_control_screen.dart';
import 'screens/live_feed_screen.dart';
import 'screens/map_screen.dart';
import 'screens/nodes_screen.dart';
import 'screens/personnel_screen.dart';
import 'screens/settings_screen.dart';
import 'state/app_state.dart';
import 'state/data_store.dart';
import 'state/plan_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appState = AppState();
  await appState.load();
  runApp(GccApp(appState: appState));
}

class GccApp extends StatelessWidget {
  final AppState appState;

  const GccApp({super.key, required this.appState});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: appState),
        ChangeNotifierProvider(
            create: (_) => DataStore(appState)..start(), lazy: false),
        ChangeNotifierProvider(create: (_) => PlanState()),
      ],
      child: MaterialApp(
        title: 'Rescue Mesh GCC',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFFB91C1C), brightness: Brightness.dark),
          useMaterial3: true,
        ),
        home: const GccShell(),
      ),
    );
  }
}

class GccShell extends StatefulWidget {
  const GccShell({super.key});

  @override
  State<GccShell> createState() => _GccShellState();
}

class _GccShellState extends State<GccShell> {
  int _index = 0;

  static const _destinations = [
    NavigationRailDestination(
        icon: Icon(Icons.map_outlined),
        selectedIcon: Icon(Icons.map),
        label: Text('Map')),
    NavigationRailDestination(
        icon: Icon(Icons.inbox_outlined),
        selectedIcon: Icon(Icons.inbox),
        label: Text('Live Feed')),
    NavigationRailDestination(
        icon: Icon(Icons.router_outlined),
        selectedIcon: Icon(Icons.router),
        label: Text('Nodes')),
    NavigationRailDestination(
        icon: Icon(Icons.badge_outlined),
        selectedIcon: Icon(Icons.badge),
        label: Text('Personnel')),
    NavigationRailDestination(
        icon: Icon(Icons.campaign_outlined),
        selectedIcon: Icon(Icons.campaign),
        label: Text('Announcements')),
    NavigationRailDestination(
        icon: Icon(Icons.flight_outlined),
        selectedIcon: Icon(Icons.flight),
        label: Text('Drone')),
    NavigationRailDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
        label: Text('Settings')),
  ];

  static const _screens = <Widget>[
    MapScreen(),
    LiveFeedScreen(),
    NodesScreen(),
    PersonnelScreen(),
    AnnouncementsScreen(),
    DroneControlScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          Column(
            children: [
              Expanded(
                child: NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  labelType: NavigationRailLabelType.all,
                  destinations: _destinations,
                ),
              ),
              const _ConnectionBadge(),
              const SizedBox(height: 8),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: _screens[_index]),
        ],
      ),
    );
  }
}

class _ConnectionBadge extends StatelessWidget {
  const _ConnectionBadge();

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataStore>();
    final app = context.watch<AppState>();
    final connected = data.isConnected;
    return Tooltip(
      message: connected
          ? 'Connected to ${data.health?.nodeId ?? "node"} as ${app.operatorLabel}'
          : (data.lastError ?? 'Not connected'),
      child: Column(
        children: [
          Icon(
            connected ? Icons.wifi : Icons.wifi_off,
            color: connected ? Colors.greenAccent : Colors.redAccent,
            size: 20,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              connected ? (data.health?.nodeId ?? '') : 'offline',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Login dialog: HQ operators authenticate with personnel_id + PIN, same
/// as everyone else (file 09 plane 2). Break-glass key lives in Settings.
Future<void> showLoginDialog(BuildContext context) async {
  final app = context.read<AppState>();
  final idCtrl = TextEditingController();
  final pinCtrl = TextEditingController();
  String? error;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('Operator login'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Join a RESCUE_x WiFi first, then log in with the '
                'personnel ID and PIN issued to you.'),
            const SizedBox(height: 12),
            TextField(
              controller: idCtrl,
              decoration: const InputDecoration(
                  labelText: 'Personnel ID', hintText: 'e.g. H-042'),
            ),
            TextField(
              controller: pinCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'PIN'),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(error!,
                    style: const TextStyle(color: Colors.redAccent)),
              ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final err =
                  await app.login(idCtrl.text.trim(), pinCtrl.text.trim());
              if (err == null) {
                if (ctx.mounted) Navigator.of(ctx).pop();
              } else {
                setState(() => error = err);
              }
            },
            child: const Text('Log in'),
          ),
        ],
      ),
    ),
  );
}
