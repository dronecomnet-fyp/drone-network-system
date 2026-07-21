/// Settings (file 04 screen 7): node base URL, fleet CA for real pinning
/// (file 09 F1), offline map file, MAVLink target presets (file 08), and
/// the clearly-labeled break-glass key.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart' show showLoginDialog;
import '../state/app_state.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _baseUrlCtrl;
  late final TextEditingController _apiKeyCtrl;
  late final TextEditingController _prodUrlCtrl;
  late final TextEditingController _prodKeyCtrl;
  late final TextEditingController _aiEndpointCtrl;
  late final TextEditingController _aiModelCtrl;
  late final TextEditingController _aiKeyCtrl;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _baseUrlCtrl = TextEditingController(text: app.baseUrl);
    _apiKeyCtrl = TextEditingController(text: app.apiKey);
    _prodUrlCtrl = TextEditingController(text: app.productApiUrl);
    _prodKeyCtrl = TextEditingController(text: app.productApiKey);
    _aiEndpointCtrl = TextEditingController(text: app.aiEndpoint);
    _aiModelCtrl = TextEditingController(text: app.aiModel);
    _aiKeyCtrl = TextEditingController(text: app.aiApiKey);
  }

  @override
  void dispose() {
    _baseUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    _prodUrlCtrl.dispose();
    _prodKeyCtrl.dispose();
    _aiEndpointCtrl.dispose();
    _aiModelCtrl.dispose();
    _aiKeyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Settings', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),

        // --- Operator session -------------------------------------------------
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Operator', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Text('Signed in as: ${app.operatorLabel}'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    FilledButton(
                      onPressed: () => showLoginDialog(context),
                      child: const Text('Log in with PIN'),
                    ),
                    const SizedBox(width: 8),
                    if (app.session != null)
                      OutlinedButton(
                        onPressed: () => app.logout(),
                        child: const Text('Log out'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // --- Node connection ---------------------------------------------------
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Node connection',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                TextField(
                  controller: _baseUrlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Node base URL',
                    helperText:
                        'Every drone AP serves the API at https://10.42.0.1:8443',
                  ),
                  onSubmitted: (v) => app.updateSettings(newBaseUrl: v),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(app.fleetCaPem.isEmpty
                          ? 'Fleet CA: NOT LOADED. HTTPS will fail closed '
                              '(by design, file 09) until you load '
                              'fleet_ca.crt from deploy/secrets/.'
                          : 'Fleet CA loaded '
                              '(${app.fleetCaPem.length} chars). Connections '
                              'trust ONLY this root; evil twins fail.'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () async {
                        final result = await FilePicker.platform.pickFiles(
                            dialogTitle: 'Select fleet_ca.crt');
                        final path = result?.files.single.path;
                        if (path == null) return;
                        final err = await app.loadCaFromFile(path);
                        if (err != null && context.mounted) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text(err)));
                        }
                      },
                      child: const Text('Load CA'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Accept ANY certificate (INSECURE)'),
                  subtitle: const Text(
                      'Dev/bench only. Defeats evil-twin protection; never '
                      'use in the field.'),
                  value: app.allowInsecure,
                  onChanged: (v) => app.updateSettings(newAllowInsecure: v),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // --- Offline map --------------------------------------------------------
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Offline map',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Text(app.mbtilesPath.isEmpty
                    ? 'No MBTiles file loaded. There is no internet at a '
                        'deployment: prepare the region file BEFORE the '
                        'mission (see docs/OFFLINE_MAPS.md).'
                    : 'Tiles: ${app.mbtilesPath}'),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () async {
                    final result = await FilePicker.platform.pickFiles(
                        dialogTitle: 'Select region .mbtiles file');
                    final path = result?.files.single.path;
                    if (path != null) {
                      await app.updateSettings(newMbtilesPath: path);
                    }
                  },
                  child: const Text('Load .mbtiles'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // --- Drone link (file 08 presets) ----------------------------------------
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('MAVLink target (system drone)',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                // Free-form host:port so it can point at whatever the drone
                // exposes. Preset chips fill the two live paths to the Pi
                // MAVLink gateway on DRONE_S (DIRECT on RESCUE_S, RELAY via
                // the mesh).
                TextFormField(
                  key: ValueKey(app.mavlinkTarget),
                  initialValue: app.mavlinkTarget,
                  decoration: const InputDecoration(
                    labelText: 'host:port',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onFieldSubmitted: (v) =>
                      app.updateSettings(newMavlinkTarget: v.trim()),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ActionChip(
                      label: const Text('DIRECT (RESCUE_S)'),
                      onPressed: () => app.updateSettings(
                          newMavlinkTarget: 'udp:10.42.0.1:14550'),
                    ),
                    ActionChip(
                      label: const Text('RELAY (via mesh)'),
                      onPressed: () => app.updateSettings(
                          newMavlinkTarget: 'udp:10.99.0.3:14550'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'DIRECT: join RESCUE_S and use 10.42.0.1:14550. RELAY: join '
                  'a volunteer AP (RESCUE_A/B) and use 10.99.0.3:14550, routed '
                  'live across the mesh to the drone. Both reach the same Pi '
                  'MAVLink gateway on the system drone.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // --- Product site (M7c) --------------------------------------------------
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Product site (spec lookup, online)',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                const Text(
                  'When online at HQ, the Mission tab fetches a unit\'s specs '
                  'by ID from our product site and caches them into the '
                  'mission file, so the field stays offline. The anon key is '
                  'public by design (row-level security guards the data).',
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _prodUrlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Supabase URL',
                    hintText: 'https://xxxx.supabase.co',
                  ),
                  onSubmitted: (v) => app.updateSettings(newProductApiUrl: v),
                ),
                TextField(
                  controller: _prodKeyCtrl,
                  decoration: const InputDecoration(labelText: 'Anon key'),
                  onSubmitted: (v) => app.updateSettings(newProductApiKey: v),
                ),
                const SizedBox(height: 6),
                Text(
                  app.productApiConfigured
                      ? 'Configured.'
                      : 'Not configured: spec fetch is disabled; enter specs '
                          'manually on the Mission tab.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // --- AI deployment advisor (M7e) -----------------------------------------
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AI deployment advisor (online)',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                const Text(
                  'OpenAI-compatible endpoint used at HQ to suggest a drone '
                  'deployment from the mission (free tiers work: Groq, '
                  'OpenRouter). The suggestion is always validated and the '
                  'operator approves it; the field plans manually offline.',
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ActionChip(
                      label: const Text('Groq'),
                      onPressed: () {
                        _aiEndpointCtrl.text = 'https://api.groq.com/openai/v1';
                        _aiModelCtrl.text = 'llama-3.3-70b-versatile';
                        app.updateSettings(
                            newAiEndpoint: _aiEndpointCtrl.text,
                            newAiModel: _aiModelCtrl.text);
                      },
                    ),
                    ActionChip(
                      label: const Text('OpenRouter'),
                      onPressed: () {
                        _aiEndpointCtrl.text = 'https://openrouter.ai/api/v1';
                        _aiModelCtrl.text =
                            'meta-llama/llama-3.3-70b-instruct:free';
                        app.updateSettings(
                            newAiEndpoint: _aiEndpointCtrl.text,
                            newAiModel: _aiModelCtrl.text);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _aiEndpointCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Base URL (…/v1)'),
                  onSubmitted: (v) => app.updateSettings(newAiEndpoint: v),
                ),
                TextField(
                  controller: _aiModelCtrl,
                  decoration: const InputDecoration(labelText: 'Model'),
                  onSubmitted: (v) => app.updateSettings(newAiModel: v),
                ),
                TextField(
                  controller: _aiKeyCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'API key'),
                  onSubmitted: (v) => app.updateSettings(newAiApiKey: v),
                ),
                const SizedBox(height: 6),
                Text(
                  app.aiConfigured
                      ? 'Configured.'
                      : 'Not configured: the AI suggest button is disabled.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // --- Break-glass -----------------------------------------------------------
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: Colors.orangeAccent, size: 18),
                    const SizedBox(width: 6),
                    Text('Break-glass HQ key',
                        style: Theme.of(context).textTheme.titleSmall),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Recovery credential for when the personnel table is '
                  'empty (fresh fleet) or PIN login is unavailable. Stored '
                  'offline in the field; PIN login is the normal path '
                  '(file 09 plane 2).',
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _apiKeyCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'HQ API key'),
                  onSubmitted: (v) => app.updateSettings(newApiKey: v),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: FilledButton(
            onPressed: () async {
              await app.updateSettings(
                newBaseUrl: _baseUrlCtrl.text,
                newApiKey: _apiKeyCtrl.text,
                newProductApiUrl: _prodUrlCtrl.text,
                newProductApiKey: _prodKeyCtrl.text,
                newAiEndpoint: _aiEndpointCtrl.text,
                newAiModel: _aiModelCtrl.text,
                newAiApiKey: _aiKeyCtrl.text,
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Settings saved')));
              }
            },
            child: const Text('Save all'),
          ),
        ),
      ],
    );
  }
}
