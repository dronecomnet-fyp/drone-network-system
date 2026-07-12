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
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Log my location twice a day'),
                  subtitle: const Text(
                      'Stored on this phone only. Turn off to stop logging.'),
                  value: c.loggingEnabled,
                  onChanged: (v) => c.setLogging(v),
                ),
                ListTile(
                  title: const Text('Log a point now'),
                  subtitle: const Text(
                      'Also used to test logging without waiting 12 hours.'),
                  trailing: const Icon(Icons.add_location_alt),
                  onTap: () async {
                    final p = await c.logNow();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(p == null
                            ? 'Could not get a location (check permission '
                                'and GPS).'
                            : 'Logged a point.'),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: SwitchListTile(
              title: const Text('Emergency mode (demo)'),
              subtitle: const Text(
                  'Manual flag for the demo. In a full deployment a '
                  'national server would flip this during a real emergency '
                  'to raise the logging rate; that server is out of scope '
                  'this phase.'),
              value: c.emergencyMode,
              onChanged: (v) => c.setEmergencyMode(v),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              title: const Text('Language'),
              subtitle: Text('$_language (translation coming later)'),
              trailing: DropdownButton<String>(
                value: _language,
                items: const [
                  DropdownMenuItem(value: 'English', child: Text('English')),
                  DropdownMenuItem(value: 'Sinhala', child: Text('Sinhala')),
                  DropdownMenuItem(value: 'Tamil', child: Text('Tamil')),
                ],
                onChanged: (v) => setState(() => _language = v ?? 'English'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: const Text('Your data and privacy'),
              subtitle: const Text('See stored points and delete them.'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const YourDataScreen()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
