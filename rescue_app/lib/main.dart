import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/alerts_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/heartbeat_provider.dart';
import 'providers/message_provider.dart';
import 'screens/announcements_screen.dart';
import 'screens/hq_uplink_screen.dart';
import 'screens/login_screen.dart';
import 'screens/map_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/victim_requests_screen.dart';
import 'services/network_binder.dart';
import 'widgets/alert_banner.dart';
import 'config/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Route this app over Wi-Fi even though the drone AP has no internet;
  // otherwise Android sends everything out over mobile data, where
  // 10.42.0.1 has no route (bench finding 2026-07-14). The binding also
  // takes effect if the user joins RESCUE_x after the app is already open.
  NetworkBinder.bindToWifi();
  runApp(const RescueApp());
}

class RescueApp extends StatelessWidget {
  const RescueApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()..load()),
        ChangeNotifierProxyProvider<AuthProvider, MessageProvider>(
          create: (context) => MessageProvider(
            onCredentialFailure: (error) =>
                context.read<AuthProvider>().handleCredentialFailure(error),
          ),
          update: (_, __, provider) => provider!,
        ),
        // Location heartbeat (M7d): only active while logged in AND in the
        // foreground. Deferred to a microtask so toggling loggedIn does not
        // notify listeners during the provider update (build) phase.
        ChangeNotifierProxyProvider<AuthProvider, HeartbeatProvider>(
          create: (_) => HeartbeatProvider(),
          update: (_, auth, hb) {
            Future.microtask(() => hb!.setLoggedIn(value: auth.isLoggedIn));
            return hb!;
          },
        ),
        // Fallback alerts (task C): polls /health for drones on LoRa
        // fallback so a red banner can warn rescuers across every tab.
        ChangeNotifierProvider(create: (_) => AlertsProvider()),
      ],
      child: MaterialApp(
        title: 'AERO-LINK',
        theme: AppTheme.darkTheme(),
        home: const SplashScreen(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

/// Routes to LoginScreen until a valid session exists (file 05 task 5.1).
/// The break-glass key path is reachable from the login screen's settings
/// link; once a key is saved, "continue with admin key" appears here too.
class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.isLoaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!auth.isLoggedIn && !auth.breakGlassAccepted) {
      return const LoginScreen();
    }
    return const MainApp();
  }
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> with WidgetsBindingObserver {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const VictimRequestsScreen(),
    const HQUplinkScreen(),
    const AnnouncementsScreen(),
    const MapScreen(),
    const SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The main app is only shown while logged in, so mark the heartbeat
    // foreground now; lifecycle changes below pause it in the background.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<HeartbeatProvider>().setForeground(value: true);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) {
      return;
    }
    context
        .read<HeartbeatProvider>()
        .setForeground(value: state == AppLifecycleState.resumed);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const RescueAlertBanner(),
          Expanded(child: _screens[_selectedIndex]),
        ],
      ),
      bottomNavigationBar: Consumer<MessageProvider>(
        builder: (context, messageProvider, child) {
          final newCount = messageProvider.getNewMessageCount();

          return NavigationBarTheme(
            data: NavigationBarThemeData(
              labelTextStyle: MaterialStateProperty.resolveWith((states) {
                if (states.contains(MaterialState.selected)) {
                  return const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 10);
                }
                return const TextStyle(color: Colors.white, fontSize: 10);
              }),
              iconTheme: MaterialStateProperty.resolveWith((states) {
                if (states.contains(MaterialState.selected)) {
                  return const IconThemeData(color: Colors.white);
                }
                return const IconThemeData(color: Colors.white70);
              }),
            ),
            child: NavigationBar(
              backgroundColor: AppTheme.kPrimary,
              indicatorColor: Colors.white.withOpacity(0.25),
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) {
                setState(() => _selectedIndex = index);
              },
              destinations: [
                NavigationDestination(
                  icon: Badge(
                    label: Text(
                      newCount.toString(),
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    isLabelVisible: newCount > 0,
                    backgroundColor: Colors.white,
                    child: const Icon(Icons.list_outlined),
                  ),
                  selectedIcon: Badge(
                    label: Text(
                      newCount.toString(),
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    isLabelVisible: newCount > 0,
                    backgroundColor: Colors.white,
                    child: const Icon(Icons.list),
                  ),
                  label: 'Requests',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.message_outlined),
                  selectedIcon: Icon(Icons.message),
                  label: 'HQ Uplink',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.campaign_outlined),
                  selectedIcon: Icon(Icons.campaign),
                  label: 'Announcements',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.map_outlined),
                  selectedIcon: Icon(Icons.map),
                  label: 'Map',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: 'Settings',
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
