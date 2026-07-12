/// Home (file 06 screen 2): status card (last logged point + time, watch
/// armed on/off), a big SOS button (disabled until connected to a drone,
/// with the reason shown), and a link to "Your data".
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/stored_point.dart';
import '../state/app_controller.dart';
import 'connected_screen.dart';
import 'settings_screen.dart';
import 'your_data_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) context.read<AppController>().checkOnDrone();
    });
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

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final StoredPoint? last =
        c.points.isEmpty ? null : c.points.last;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rescue Emergency'),
        backgroundColor: Colors.red.shade600,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await c.refreshPoints();
          await c.checkOnDrone();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Watch status
            Card(
              color: c.armed ? Colors.green.shade50 : null,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          c.armed
                              ? Icons.bluetooth_searching
                              : Icons.bluetooth_disabled,
                          color: c.armed ? Colors.green : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            c.armed
                                ? 'Watch armed: scanning for a rescue drone'
                                : 'Watch off',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Switch(
                          value: c.armed,
                          onChanged:
                              _busy ? null : (_) => _toggleArmed(c),
                        ),
                      ],
                    ),
                    if (c.armed)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'A notification will appear if a drone is near. '
                          'You can lock your phone.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    if (c.lastSighting != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Last drone seen: ${c.lastSighting!.ssid} '
                          '(signal ${c.lastSighting!.rssi} dBm)',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.green.shade800),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Location log status
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Your location log',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(last == null
                        ? 'No points logged yet.'
                        : 'Last point ${_ago(last.recordedAt)} '
                            '(${c.points.length}/${c.maxPoints} kept)'),
                    const SizedBox(height: 4),
                    Text(
                      'Stored only on this phone. Nothing is sent until you '
                      'reach a drone or press SOS.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const YourDataScreen()),
                        ),
                        child: const Text('Your data'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // SOS
            Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 72,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.sos, size: 28),
                    label: const Text('SEND SOS',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold)),
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          c.onDrone ? Colors.red.shade700 : Colors.grey,
                    ),
                    onPressed: c.onDrone
                        ? () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => const ConnectedScreen()),
                            )
                        : null,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  c.onDrone
                      ? 'Connected to a rescue drone. Tap SOS to send.'
                      : 'SOS is available once you join a rescue drone Wi-Fi '
                          '(a notification will guide you when one is near).',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
