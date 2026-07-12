/// Onboarding (file 06 screen 1): explains what the app does, then asks
/// for each permission ONE AT A TIME with a plain-language reason. The
/// order matches the platform's expectations (notifications, then
/// while-in-use location, then background location, then BLE scan).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/location_logger.dart';
import '../services/notification_service.dart';
import '../services/permissions.dart';
import '../state/app_controller.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;

  late final List<_PermStep> _steps = [
    _PermStep(
      icon: Icons.notifications_active,
      title: 'Alerts when a drone is near',
      body: 'If a rescue drone comes within Bluetooth range, we show you a '
          'high-priority notification. Tapping it opens the connect screen. '
          'No app can force itself open on its own, so the notification is '
          'how you find out.',
      button: 'Allow notifications',
      request: () async {
        await NotificationService.requestPermission();
        return Permissions.requestNotifications();
      },
    ),
    _PermStep(
      icon: Icons.my_location,
      title: 'Your location, kept on your phone',
      body: 'We save a small location log ON YOUR PHONE (about twice a day). '
          'Nothing is sent anywhere until you reach a rescue drone or press '
          'SOS.',
      button: 'Allow location',
      request: Permissions.requestLocationWhenInUse,
    ),
    _PermStep(
      icon: Icons.location_on,
      title: 'Background location ("Allow all the time")',
      body: 'To keep logging about twice a day even when the app is closed, '
          'Android needs the "Allow all the time" setting. The system may '
          'shift the exact times by a few hours; that is fine for this use.',
      button: 'Allow in background',
      request: Permissions.requestLocationAlways,
    ),
    _PermStep(
      icon: Icons.bluetooth_searching,
      title: 'Scan for nearby devices',
      body: 'We scan only for the rescue drone signal, nothing else. On '
          'Android 12 and later this needs the "nearby devices" permission.',
      button: 'Allow scanning',
      request: Permissions.requestBleScan,
    ),
  ];

  Future<void> _handleRequest() async {
    await _steps[_step].request();
    if (!mounted) return;
    if (_step < _steps.length - 1) {
      setState(() => _step++);
    } else {
      // Schedule background logging now that permissions have been asked.
      try {
        await LocationLogger.schedule();
      } catch (_) {}
      if (!mounted) return;
      await context.read<AppController>().completeOnboarding();
    }
  }

  Future<void> _skip() async {
    if (_step < _steps.length - 1) {
      setState(() => _step++);
    } else {
      if (!mounted) return;
      await context.read<AppController>().completeOnboarding();
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_step];
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: (_step + 1) / _steps.length,
              ),
              const Spacer(),
              Icon(step.icon, size: 88, color: Colors.red.shade600),
              const SizedBox(height: 24),
              Text(
                step.title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Text(
                step.body,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _handleRequest,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: Colors.red.shade600,
                  ),
                  child: Text(step.button),
                ),
              ),
              TextButton(
                onPressed: _skip,
                child: Text(_step < _steps.length - 1
                    ? 'Not now'
                    : 'Finish without this'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermStep {
  final IconData icon;
  final String title;
  final String body;
  final String button;
  final Future<bool> Function() request;

  _PermStep({
    required this.icon,
    required this.title,
    required this.body,
    required this.button,
    required this.request,
  });
}
