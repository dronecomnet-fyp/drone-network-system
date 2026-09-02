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
import 'screens/degraded_screen.dart';
import 'screens/distribution_screen.dart';
import 'screens/drone_control_screen.dart';
import 'screens/live_feed_screen.dart';
import 'screens/live_ops_screen.dart';
import 'screens/map_screen.dart';
import 'screens/mission_screen.dart';
import 'screens/nodes_screen.dart';
import 'screens/personnel_screen.dart';
import 'screens/settings_screen.dart';
import 'services/connectivity.dart';
import 'services/distribution_server.dart';
import 'state/app_state.dart';
import 'state/data_store.dart';
import 'state/drone_controller.dart';
import 'state/fleet_state.dart';
import 'state/mission_state.dart';

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
        ChangeNotifierProvider(create: (_) => MissionState()),
        ChangeNotifierProvider(create: (_) => DroneController()),
        // Field Share (task E): held here, above the shell, so the local
        // download server keeps running while the operator uses other tabs.
        ChangeNotifierProvider(create: (_) => DistributionServer()),
        // Is there real internet right now (CHANGES.md item 32)? Separate
        // from "am I talking to a drone node": the two are unrelated, and
        // at a deployment the healthy answer is node yes, internet no.
        ChangeNotifierProvider(create: (_) => ConnectivityService(), lazy: false),
        ChangeNotifierProvider(create: (_) => ShellNav()),
        ChangeNotifierProvider(
          create: (ctx) {
            final drone = ctx.read<DroneController>();
            return FleetState(
              onRealDeploy: (d) =>
                  drone.deploySequence(d.targetLat, d.targetLon, 30),
              onRealRecall: (_) => drone.returnToLaunch(),
            );
          },
        ),
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

/// Lets a screen send the operator to another tab.
///
/// Testers said planning "is not straightforward" because it is split: you
/// name a mission on one tab and draw its area on another, with the Mission
/// tab reduced to printing instructions like "draw the area on the Map
/// tab". Rather than merge two large screens into one crowded one, the
/// instructions become buttons that take you there and switch the map into
/// the right mode, so the workflow is continuous even though the screens
/// stay separate and each stays readable.
class ShellNav extends ChangeNotifier {
  static const int mapTab = 0;
  static const int liveOpsTab = 1;
  static const int missionTab = 2;
  static const int liveFeedTab = 3;
  static const int nodesTab = 4;
  static const int degradedTab = 5;
  static const int personnelTab = 6;
  static const int announcementsTab = 7;
  static const int droneTab = 8;
  static const int fieldShareTab = 9;
  static const int settingsTab = 10;

  int? _requested;
  String? _liveFeedSource;
  double? _targetMapLat;
  double? _targetMapLon;

  int? takeRequest() {
    final r = _requested;
    _requested = null;
    return r;
  }

  String? takeLiveFeedSource() {
    final s = _liveFeedSource;
    _liveFeedSource = null;
    return s;
  }

  (double, double)? takeTargetMapCoord() {
    if (_targetMapLat == null || _targetMapLon == null) return null;
    final c = (_targetMapLat!, _targetMapLon!);
    _targetMapLat = null;
    _targetMapLon = null;
    return c;
  }

  void go(int tabIndex) {
    _requested = tabIndex;
    notifyListeners();
  }

  void goToLiveFeed({String source = 'VICTIMS'}) {
    _liveFeedSource = source;
    _requested = liveFeedTab;
    notifyListeners();
  }

  void goToMapAt(double lat, double lon) {
    _targetMapLat = lat;
    _targetMapLon = lon;
    _requested = mapTab;
    notifyListeners();
  }
}

class GccShell extends StatefulWidget {
  const GccShell({super.key});

  @override
  State<GccShell> createState() => _GccShellState();
}

class _GccShellState extends State<GccShell> {
  int _index = 0;

  static const _screens = <Widget>[
    MapScreen(),
    LiveOpsScreen(),
    MissionScreen(),
    LiveFeedScreen(),
    NodesScreen(),
    DegradedScreen(),
    PersonnelScreen(),
    AnnouncementsScreen(),
    DroneControlScreen(),
    DistributionScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<ShellNav>();
    final data = context.watch<DataStore>();
    final requested = nav.takeRequest();
    if (requested != null && requested != _index) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _index = requested);
      });
    }

    final newVictimCount = data.messages.items.where((m) => m.status == 'NEW').length;
    final fieldReportsCount = data.gsMessages.items.length;

    return Scaffold(
      body: Row(
        children: [
          _PremiumSidebar(
            selectedIndex: _index,
            newVictimCount: newVictimCount,
            fieldReportsCount: fieldReportsCount,
            onSelect: (i) => setState(() => _index = i),
          ),
          Expanded(child: _screens[_index]),
        ],
      ),
    );
  }
}

/// ── Premium sidebar ──────────────────────────────────────────────────────────
class _PremiumSidebar extends StatelessWidget {
  final int selectedIndex;
  final int newVictimCount;
  final int fieldReportsCount;
  final ValueChanged<int> onSelect;

  const _PremiumSidebar({
    required this.selectedIndex,
    required this.newVictimCount,
    required this.fieldReportsCount,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final totalAlerts = newVictimCount + fieldReportsCount;

    final items = [
      _SidebarItem(index: 0, icon: Icons.map_outlined, selectedIcon: Icons.map, label: 'Map'),
      _SidebarItem(index: 1, icon: Icons.monitor_heart_outlined, selectedIcon: Icons.monitor_heart, label: 'Live Ops'),
      _SidebarItem(index: 2, icon: Icons.assignment_outlined, selectedIcon: Icons.assignment, label: 'Mission'),
      _SidebarItem(
        index: 3,
        icon: Icons.inbox_outlined,
        selectedIcon: Icons.inbox,
        label: 'Live Feed',
        badge: totalAlerts > 0 ? totalAlerts : null,
        badgeColor: fieldReportsCount > 0 ? Colors.purpleAccent : Colors.redAccent,
      ),
      _SidebarItem(index: 4, icon: Icons.router_outlined, selectedIcon: Icons.router, label: 'Nodes'),
      _SidebarItem(index: 5, icon: Icons.warning_amber_outlined, selectedIcon: Icons.warning_amber, label: 'Degraded'),
      _SidebarItem(index: 6, icon: Icons.badge_outlined, selectedIcon: Icons.badge, label: 'Personnel'),
      _SidebarItem(index: 7, icon: Icons.campaign_outlined, selectedIcon: Icons.campaign, label: 'Announce'),
      _SidebarItem(index: 8, icon: Icons.flight_outlined, selectedIcon: Icons.flight, label: 'Drone'),
      _SidebarItem(index: 9, icon: Icons.wifi_tethering_outlined, selectedIcon: Icons.wifi_tethering, label: 'Field Share'),
      _SidebarItem(index: 10, icon: Icons.settings_outlined, selectedIcon: Icons.settings, label: 'Settings'),
    ];

    return Container(
      width: 72,
      decoration: BoxDecoration(
        color: const Color(0xFF0F0A07),
        border: Border(
          right: BorderSide(color: Colors.white.withOpacity(0.07), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 12,
            offset: const Offset(4, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Logo / brand mark ──
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF6D00), Color(0xFFB91C1C)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF6D00).withOpacity(0.4),
                        blurRadius: 12,
                        spreadRadius: -2,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.cell_tower, color: Colors.white, size: 20),
                ),
                const SizedBox(height: 6),
                const Text(
                  'GCC',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: Colors.white38,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),

          Container(height: 1, color: Colors.white.withOpacity(0.05)),
          const SizedBox(height: 6),

          // ── Nav items ──
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              children: items.map((item) {
                final selected = selectedIndex == item.index;
                return _SidebarNavTile(
                  item: item,
                  selected: selected,
                  onTap: () => onSelect(item.index),
                );
              }).toList(),
            ),
          ),

          // ── Connection status footer ──
          const _ConnectionBadge(),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class _SidebarItem {
  final int index;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int? badge;
  final Color badgeColor;

  const _SidebarItem({
    required this.index,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badge,
    this.badgeColor = Colors.redAccent,
  });
}

class _SidebarNavTile extends StatefulWidget {
  final _SidebarItem item;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarNavTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_SidebarNavTile> createState() => _SidebarNavTileState();
}

class _SidebarNavTileState extends State<_SidebarNavTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final item = widget.item;

    return Tooltip(
      message: item.label,
      preferBelow: false,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: selected
                  ? Colors.orangeAccent.withOpacity(0.15)
                  : _hovered
                      ? Colors.white.withOpacity(0.05)
                      : Colors.transparent,
              border: selected
                  ? Border.all(color: Colors.orangeAccent.withOpacity(0.3), width: 1)
                  : Border.all(color: Colors.transparent, width: 1),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: Colors.orangeAccent.withOpacity(0.15),
                        blurRadius: 12,
                        spreadRadius: -2,
                      ),
                    ]
                  : [],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      selected ? item.selectedIcon : item.icon,
                      size: 22,
                      color: selected
                          ? Colors.orangeAccent
                          : _hovered
                              ? Colors.white70
                              : Colors.white38,
                    ),
                    if (item.badge != null)
                      Positioned(
                        top: -6,
                        right: -10,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                          decoration: BoxDecoration(
                            color: item.badgeColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${item.badge}',
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    color: selected
                        ? Colors.orangeAccent
                        : _hovered
                            ? Colors.white60
                            : Colors.white30,
                    letterSpacing: 0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ── Connection status (footer of sidebar) ────────────────────────────────────
class _ConnectionBadge extends StatelessWidget {
  const _ConnectionBadge();

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataStore>();
    final app = context.watch<AppState>();
    final net = context.watch<ConnectivityService>();
    final connected = data.isConnected;

    final netColour = switch (net.status) {
      NetStatus.online => Colors.lightBlueAccent,
      NetStatus.portal => Colors.amberAccent,
      NetStatus.offline => Colors.white38,
      NetStatus.unknown => Colors.white24,
    };

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.06), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: connected
                ? 'Connected to ${data.health?.nodeId ?? "node"} as ${app.operatorLabel}'
                : (data.lastError ?? 'Not connected to a drone node'),
            child: Column(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: connected ? Colors.greenAccent : Colors.redAccent,
                    boxShadow: [
                      BoxShadow(
                        color: (connected ? Colors.greenAccent : Colors.redAccent)
                            .withOpacity(0.6),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  connected ? (data.health?.nodeId ?? 'node') : 'no node',
                  style: const TextStyle(fontSize: 9, color: Colors.white38, letterSpacing: 0.5),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Tooltip(
            message: '${net.detail}\n\nClick to re-check now.',
            child: InkWell(
              onTap: net.checking ? null : net.check,
              borderRadius: BorderRadius.circular(6),
              child: Column(
                children: [
                  Icon(
                    net.isOnline ? Icons.public : Icons.public_off,
                    color: netColour,
                    size: 16,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    net.checking ? '...' : net.label,
                    style: TextStyle(fontSize: 9, color: netColour.withOpacity(0.8)),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
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
