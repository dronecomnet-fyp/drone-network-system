/// Settings (file 06 screen 5): language stub (Sinhala/Tamil/English),
/// logging on/off, manual log-now (for the shortened-interval
/// verification), the emergency-mode demo flag, and data deletion access.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_controller.dart';
import 'your_data_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Language is a STUB structure this phase (file 06): the options exist
  // so the localization scaffold has a home; strings are not translated
  // yet.
  String _language = 'English';

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();

    Widget buildHeader(String title) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
        child: Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade600,
            letterSpacing: 1.2,
          ),
        ),
      );
    }

    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          buildHeader('App Preferences'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              color: Colors.white,
              elevation: 2,
              shadowColor: Colors.black12,
              shape: cardShape,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.language, color: Colors.blueAccent),
                    title: const Text('Language'),
                    subtitle: const Text('Translation coming later'),
                    trailing: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _language,
                        icon: const Icon(Icons.expand_more, size: 20),
                        alignment: Alignment.centerRight,
                        items: const [
                          DropdownMenuItem(value: 'English', child: Text('English')),
                          DropdownMenuItem(value: 'Sinhala', child: Text('Sinhala')),
                          DropdownMenuItem(value: 'Tamil', child: Text('Tamil')),
                        ],
                        onChanged: (v) => setState(() => _language = v ?? 'English'),
                      ),
                    ),
                  ),
                  const Divider(height: 1, indent: 56),
                  SwitchListTile(
                    secondary: const Icon(Icons.flight_takeoff, color: Colors.blueAccent),
                    title: const Text('Auto-open on drone scan'),
                    subtitle: const Text('Brings the app to the front automatically.'),
                    value: c.autoOpenOnDrone ?? false,
                    onChanged: (v) => c.setAutoOpenOnDrone(v),
                    activeColor: Colors.blueAccent,
                  ),
                ],
              ),
            ),
          ),

          buildHeader('Location & Tracking'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              color: Colors.white,
              elevation: 2,
              shadowColor: Colors.black12,
              shape: cardShape,
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.my_location, color: Colors.green),
                    title: const Text('Background location logging'),
                    subtitle: const Text('Locally logs your position twice a day.'),
                    value: c.loggingEnabled,
                    onChanged: (v) => c.setLogging(v),
                    activeColor: Colors.green,
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: const Icon(Icons.add_location_alt, color: Colors.green),
                    title: const Text('Log a point now'),
                    subtitle: const Text('Manually record your current location.'),
                    trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                    onTap: () async {
                      final p = await c.logNow();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(p == null
                              ? 'Could not get a location (check permission and GPS).'
                              : 'Logged a point.'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          buildHeader('Privacy & Data'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              color: Colors.white,
              elevation: 2,
              shadowColor: Colors.black12,
              shape: cardShape,
              child: ListTile(
                leading: const Icon(Icons.shield_outlined, color: Colors.purple),
                title: const Text('Manage your data'),
                subtitle: const Text('View or delete stored location points.'),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const YourDataScreen()),
                ),
              ),
            ),
          ),

          buildHeader('Developer / Demo'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              color: Colors.white,
              elevation: 2,
              shadowColor: Colors.black12,
              shape: cardShape,
              child: SwitchListTile(
                secondary: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                title: const Text('Emergency mode (demo)'),
                subtitle: const Text('Forces high-frequency location logging for demonstration purposes.'),
                value: c.emergencyMode,
                onChanged: (v) => c.setEmergencyMode(v),
                activeColor: Colors.orange,
              ),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
