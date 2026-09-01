/// Drone found (file 06 screen 3): reached by tapping the notification.
/// Shows the node name and SSID parsed from the BLE service data, and a
/// JOIN WIFI button.
///
/// Per file 06, the reliable path is implemented FIRST: a one-tap "Open
/// Wi-Fi settings" intent with the SSID shown large (this always works).
/// The platform WiFi-suggestion API is noted as the later refinement; the
/// open network has no password, so joining from settings is one tap.
library;

import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/app_controller.dart';
import 'connected_screen.dart';

class DroneFoundScreen extends StatefulWidget {
  final String nodeLabel;
  final String ssid;

  const DroneFoundScreen({
    super.key,
    required this.nodeLabel,
    required this.ssid,
  });

  @override
  State<DroneFoundScreen> createState() => _DroneFoundScreenState();
}

class _DroneFoundScreenState extends State<DroneFoundScreen> {
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    // Ask about auto-open HERE, the first time a drone is actually found,
    // rather than during onboarding. At onboarding "open automatically when
    // a drone is found" is an abstraction; standing here having just been
    // found, the person knows exactly what it means. Asked once ever.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAskAutoOpen());
  }

  Future<void> _maybeAskAutoOpen() async {
    final c = context.read<AppController>();
    if (c.autoOpenOnDrone != null) return; // already answered, never nag
    if (!mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Open automatically next time?'),
        content: const Text(
          'When a rescue drone comes into range, this app can open by '
          'itself so you do not have to notice the notification.\n\n'
          'You can change this later in Settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No, just notify me'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes, open it'),
          ),
        ],
      ),
    );
    if (yes == null || !mounted) return;
    await c.setAutoOpenOnDrone(yes);
  }

  Future<void> _openWifiSettings() async {
    await Clipboard.setData(ClipboardData(text: widget.ssid));
    await AppSettings.openAppSettings(type: AppSettingsType.wifi);
  }

  Future<void> _checkConnection() async {
    setState(() => _checking = true);
    final onDrone = await context.read<AppController>().checkOnDrone();
    if (!mounted) return;
    setState(() => _checking = false);
    if (onDrone) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ConnectedScreen()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Not connected yet. Join the Wi-Fi, then '
                'tap "I have joined".')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rescue drone nearby'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            Icon(Icons.airplanemode_active,
                size: 88, color: Colors.red.shade600),
            const SizedBox(height: 16),
            Text(
              'A rescue drone (${widget.nodeLabel}) is nearby.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text('Join this open Wi-Fi network:',
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 8),
                    SelectableText(
                      widget.ssid,
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text('(No password. Network name copied for you.)',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.wifi),
              label: const Text('Open Wi-Fi settings'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: Colors.red.shade600,
              ),
              onPressed: _openWifiSettings,
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _checking ? null : _checkConnection,
              child: _checking
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('I have joined the Wi-Fi'),
            ),
            const Spacer(),
            Text(
              'Stay where you are once connected. The next screen sends '
              'your saved locations and lets you send an SOS.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
