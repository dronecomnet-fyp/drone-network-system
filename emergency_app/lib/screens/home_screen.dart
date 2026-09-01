/// Home (file 06 screen 2): Main Dashboard containing the persistent BottomNavigationBar
library;

import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/stored_point.dart';
import '../state/app_controller.dart';
import 'area_map_screen.dart';
import 'connected_screen.dart';
import 'conversation_screen.dart';
import 'settings_screen.dart';
import 'your_data_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  void _onNavTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      // No AppBar here, as individual tabs (like AreaMapScreen and ConversationScreen) have their own AppBars.
      // (_HomeTabContent also provides its own AppBar so it looks natural).
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          _HomeTabContent(),
          AreaMapScreen(),
          ConversationScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onNavTapped,
        backgroundColor: Colors.white,
        elevation: 10,
        shadowColor: Colors.black12,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_filled),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            label: 'Map',
          ),
          NavigationDestination(
            icon: Icon(Icons.forum_outlined),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _HomeTabContent extends StatefulWidget {
  const _HomeTabContent();

  @override
  State<_HomeTabContent> createState() => _HomeTabContentState();
}

class _HomeTabContentState extends State<_HomeTabContent>
    with SingleTickerProviderStateMixin {
  bool _busy = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    Future.microtask(() {
      if (mounted) context.read<AppController>().checkOnDrone();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _ago(String iso) {
    final t = DateTime.tryParse(iso);
    if (t == null) return iso;
    final d = DateTime.now().difference(t.toLocal());
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }

  Future<void> _toggleArmed(AppController c) async {
    setState(() => _busy = true);
    String? err;
    if (c.armed) {
      await c.disarm();
    } else {
      err = await c.arm();
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err)));
    }
  }

  void _handleSosTap(AppController c) {
    if (c.onDrone) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ConnectedScreen()),
      );
    } else {
      _showConnectModal();
    }
  }

  void _showConnectModal() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Icon(Icons.wifi_find_rounded, size: 56, color: Colors.orange.shade700),
            const SizedBox(height: 16),
            const Text(
              'Not Connected to Drone',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'You need to be connected to a rescue drone to send an SOS. '
              'Please go to your Wi-Fi settings and join the open "RESCUE" network.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.black87, height: 1.4),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              icon: const Icon(Icons.settings),
              label: const Text('Open Wi-Fi Settings', style: TextStyle(fontSize: 16)),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                backgroundColor: Theme.of(context).primaryColor,
              ),
              onPressed: () {
                Navigator.pop(context);
                AppSettings.openAppSettings(type: AppSettingsType.wifi);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBanner(AppController c) {
    final bool online = c.onDrone;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      decoration: BoxDecoration(
        color: online ? Colors.green.shade50 : Colors.orange.shade50,
        border: Border(
          bottom: BorderSide(
            color: online ? Colors.green.shade200 : Colors.orange.shade200,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (!online)
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Opacity(
                  opacity: 0.4 + (_pulseController.value * 0.6),
                  child: Icon(Icons.radar, color: Colors.orange.shade800, size: 18),
                );
              },
            )
          else
            const Icon(Icons.check_circle, color: Colors.green, size: 18),
          const SizedBox(width: 8),
          Text(
            online ? 'Connected to Rescue Network' : 'Scanning for rescue drones...',
            style: TextStyle(
              color: online ? Colors.green.shade900 : Colors.orange.shade900,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCentralSos(AppController c) {
    return Column(
      children: [
        const Text(
          'Emergency Assistance',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        const SizedBox(height: 8),
        Text(
          'Tap below to alert the rescue team.',
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 16),
        Container(
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.red.withOpacity(0.3),
                blurRadius: 30,
                spreadRadius: 10,
                offset: const Offset(0, 10),
              ),
            ],
            gradient: const LinearGradient(
              colors: [Color(0xFFE53935), Color(0xFFC62828)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => _handleSosTap(c),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset('assets/emegency.png', width: 86, height: 86, color: Colors.white),
                    const SizedBox(height: 2),
                    const Text(
                      'EMERGENCY',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSystemStatusCard(AppController c, StoredPoint? last) {
    return Card(
      color: Colors.white,
      elevation: 2,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          // Bluetooth Row
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: c.armed ? Colors.green.shade50 : Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                c.armed ? Icons.bluetooth_searching : Icons.bluetooth_disabled,
                color: c.armed ? Colors.green.shade700 : Colors.grey.shade600,
                size: 24,
              ),
            ),
            title: const Text('Bluetooth Radar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            subtitle: Text(
              c.armed ? 'Active' : 'Inactive',
              style: TextStyle(
                color: c.armed ? Colors.green.shade700 : Colors.grey.shade600,
                fontWeight: FontWeight.w600,
              ),
            ),
            trailing: Switch(
              value: c.armed,
              activeColor: Colors.green,
              onChanged: _busy ? null : (_) => _toggleArmed(c),
            ),
          ),
          Divider(height: 1, color: Colors.grey.shade100),
          // Location Row
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const YourDataScreen()),
            ),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.location_on, color: Colors.blue.shade700, size: 24),
            ),
            title: const Text('Location Logger', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            subtitle: Text(
              last == null ? 'Waiting for GPS...' : 'Ready (${_ago(last.recordedAt)})',
              style: TextStyle(
                color: Colors.blue.shade800,
                fontWeight: FontWeight.w600,
              ),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final StoredPoint? last = c.points.isEmpty ? null : c.points.last;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('AERO-LINK Emergency'),
      ),
      body: Column(
        children: [
          _buildStatusBanner(c),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await c.refreshPoints();
                await c.checkOnDrone();
              },
              child: ListView(
                // Padding reduced to eliminate scrolling
                padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 20),
                children: [
                  _buildCentralSos(c),
                  const SizedBox(height: 24),
                  _buildSystemStatusCard(c, last),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
