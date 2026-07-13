import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/auth_provider.dart';
import 'providers/message_provider.dart';
import 'screens/announcements_screen.dart';
import 'screens/hq_uplink_screen.dart';
import 'screens/login_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/victim_requests_screen.dart';
import 'services/network_binder.dart';

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
      ],
      child: MaterialApp(
        title: 'Rescue Mesh',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepOrange,
            brightness: Brightness.light,
          ),
        ),
        home: const RootGate(),
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

class _MainAppState extends State<MainApp> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const VictimRequestsScreen(),
    const HQUplinkScreen(),
    const AnnouncementsScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: Consumer<MessageProvider>(
        builder: (context, messageProvider, child) {
          final newCount = messageProvider.getNewMessageCount();

          return BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            backgroundColor: Colors.deepOrange.shade50,
            selectedItemColor: Colors.deepOrange.shade800,
            unselectedItemColor: Colors.grey.shade700,
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
            currentIndex: _selectedIndex,
            onTap: (index) {
              setState(() => _selectedIndex = index);
            },
            items: [
              BottomNavigationBarItem(
                icon: Badge(
                  label: Text(newCount.toString()),
                  isLabelVisible: newCount > 0,
                  backgroundColor: Colors.red,
                  child: const Icon(Icons.list),
                ),
                label: 'Requests',
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.message),
                label: 'HQ Uplink',
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.campaign),
                label: 'Announcements',
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          );
        },
      ),
    );
  }
}
