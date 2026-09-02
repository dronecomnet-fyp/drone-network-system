/// Settings (file 04 screen 7): node base URL, fleet CA for real pinning
/// (file 09 F1), offline map file, MAVLink target presets (file 08), and
/// the clearly-labeled break-glass key.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart' show showLoginDialog;
import '../services/connectivity.dart';
import '../state/app_state.dart';
import '../state/data_store.dart' show formatAge;

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

    Widget sectionHeader(String title, {IconData? icon, Color? iconColor}) {
      return Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: iconColor ?? Colors.white54),
            const SizedBox(width: 8),
          ],
          Text(title.toUpperCase(),
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.white54,
                  letterSpacing: 1)),
        ],
      );
    }

    Widget sectionContainer(Widget child, {Color? borderColor}) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.02),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor ?? Colors.white.withOpacity(0.05)),
        ),
        child: child,
      );
    }

    InputDecoration styledInput(String label, {String? hint}) {
      return InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 13),
        filled: true,
        fillColor: Colors.white.withOpacity(0.03),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.orangeAccent, width: 1.5),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Professional Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: const Color(0xFF1A0F0A),
            border: Border(
                bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orangeAccent.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.orangeAccent.withOpacity(0.3)),
                ),
                child: const Icon(Icons.settings, color: Colors.orangeAccent, size: 18),
              ),
              const SizedBox(width: 14),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SYSTEM SETTINGS',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 1.5,
                      )),
                  SizedBox(height: 4),
                  Text('Configure node, fleet trust, and AI tools',
                      style: TextStyle(fontSize: 11, color: Colors.white38, letterSpacing: 0.3)),
                ],
              ),
              const Spacer(),
              FilledButton.icon(
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
                        const SnackBar(content: Text('Settings saved successfully', style: TextStyle(fontWeight: FontWeight.w600))));
                  }
                },
                icon: const Icon(Icons.save, size: 16),
                label: const Text('Save all', style: TextStyle(fontWeight: FontWeight.w700)),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.orangeAccent.withOpacity(0.15),
                  foregroundColor: Colors.orangeAccent,
                  side: BorderSide(color: Colors.orangeAccent.withOpacity(0.3)),
                ),
              ),
            ],
          ),
        ),

        // Content
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              // --- Operator session -------------------------------------------------
              sectionContainer(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    sectionHeader('Operator Session', icon: Icons.person_outline),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text('Signed in as: ', style: TextStyle(color: Colors.white54, fontSize: 13)),
                        Text(app.operatorLabel, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        if (app.session != null)
                          OutlinedButton.icon(
                            onPressed: () => app.logout(),
                            icon: const Icon(Icons.logout, size: 16),
                            label: const Text('Log out'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white54,
                              side: BorderSide(color: Colors.white.withOpacity(0.15)),
                            ),
                          )
                        else
                          FilledButton.icon(
                            onPressed: () => showLoginDialog(context),
                            icon: const Icon(Icons.login, size: 16),
                            label: const Text('Log in with PIN'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white.withOpacity(0.1),
                              foregroundColor: Colors.white,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // --- Node connection ---------------------------------------------------
              sectionContainer(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    sectionHeader('Node Connection', icon: Icons.router),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _baseUrlCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: styledInput('Node base URL').copyWith(
                        helperText: 'Every drone AP serves the API at https://10.42.0.1:8443',
                        helperStyle: const TextStyle(color: Colors.white38),
                      ),
                      onSubmitted: (v) => app.updateSettings(newBaseUrl: v),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(app.fleetCaPem.isEmpty ? Icons.warning_amber : Icons.verified_user, 
                            color: app.fleetCaPem.isEmpty ? Colors.orangeAccent : Colors.greenAccent, size: 24),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              app.fleetCaPem.isEmpty
                                  ? 'FLEET CA NOT LOADED. HTTPS will fail closed until you load fleet_ca.crt.'
                                  : 'Fleet CA loaded (${app.fleetCaPem.length} chars). Connections trust ONLY this root.',
                              style: TextStyle(fontSize: 12, color: app.fleetCaPem.isEmpty ? Colors.orangeAccent : Colors.white70, height: 1.4),
                            ),
                          ),
                          const SizedBox(width: 16),
                          OutlinedButton.icon(
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
                            icon: const Icon(Icons.upload_file, size: 16),
                            label: const Text('Load CA'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: BorderSide(color: Colors.white.withOpacity(0.2)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: app.allowInsecure ? Colors.redAccent.withOpacity(0.4) : Colors.white.withOpacity(0.05)),
                        borderRadius: BorderRadius.circular(10),
                        color: app.allowInsecure ? Colors.redAccent.withOpacity(0.05) : Colors.transparent,
                      ),
                      child: SwitchListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        title: Text('Accept ANY certificate (INSECURE)', style: TextStyle(color: app.allowInsecure ? Colors.redAccent : Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: Text(
                            'Dev/bench only. Defeats evil-twin protection; never use in the field.',
                            style: TextStyle(color: app.allowInsecure ? Colors.redAccent.withOpacity(0.8) : Colors.white38, fontSize: 11)),
                        value: app.allowInsecure,
                        activeColor: Colors.redAccent,
                        onChanged: (v) => app.updateSettings(newAllowInsecure: v),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // --- Offline map --------------------------------------------------------
              sectionContainer(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    sectionHeader('Offline Map', icon: Icons.map),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.layers, color: Colors.cyanAccent, size: 24),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              app.mbtilesPath.isEmpty
                                  ? 'No MBTiles file loaded. Prepare the region file BEFORE deployment.'
                                  : 'Tiles: ${app.mbtilesPath}',
                              style: const TextStyle(fontSize: 12, color: Colors.white70, height: 1.4),
                            ),
                          ),
                          const SizedBox(width: 16),
                          OutlinedButton.icon(
                            onPressed: () async {
                              final result = await FilePicker.platform.pickFiles(
                                  dialogTitle: 'Select region .mbtiles file');
                              final path = result?.files.single.path;
                              if (path != null) {
                                await app.updateSettings(newMbtilesPath: path);
                              }
                            },
                            icon: const Icon(Icons.map, size: 16),
                            label: const Text('Load .mbtiles'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.cyanAccent,
                              side: BorderSide(color: Colors.cyanAccent.withOpacity(0.3)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // --- Drone link (file 08 presets) ----------------------------------------
              sectionContainer(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    sectionHeader('MAVLink Target (System Drone)', icon: Icons.flight_takeoff),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            key: ValueKey(app.mavlinkTarget),
                            initialValue: app.mavlinkTarget,
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
                            decoration: styledInput('host:port'),
                            onFieldSubmitted: (v) =>
                                app.updateSettings(newMavlinkTarget: v.trim()),
                          ),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton(
                          onPressed: () => app.updateSettings(
                              newMavlinkTarget: 'udp:10.42.0.1:14550'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                            side: BorderSide(color: Colors.white.withOpacity(0.2)),
                          ),
                          child: const Text('DIRECT (RESCUE_S)'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () => app.updateSettings(
                              newMavlinkTarget: 'udp:10.99.0.3:14550'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                            side: BorderSide(color: Colors.white.withOpacity(0.2)),
                          ),
                          child: const Text('RELAY (via mesh)'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'DIRECT: join RESCUE_S and use 10.42.0.1:14550. RELAY: join '
                      'a volunteer AP (RESCUE_A/B) and use 10.99.0.3:14550, routed '
                      'live across the mesh to the drone. Both reach the same Pi '
                      'MAVLink gateway on the system drone.',
                      style: TextStyle(fontSize: 11, color: Colors.white38, height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // --- Product site (M7c) --------------------------------------------------
              sectionContainer(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    sectionHeader('Product Site (Spec lookup, online)', icon: Icons.storefront),
                    const SizedBox(height: 16),
                    const _InternetStatusRow(),
                    const SizedBox(height: 16),
                    const Text(
                      'When online at HQ, the Mission tab fetches a unit\'s specs '
                      'by ID from our product site and caches them into the '
                      'mission file, so the field stays offline. The anon key is '
                      'public by design (row-level security guards the data).',
                      style: TextStyle(fontSize: 12, color: Colors.white54, height: 1.4),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _prodUrlCtrl,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: styledInput('Supabase URL', hint: 'https://xxxx.supabase.co'),
                            onSubmitted: (v) => app.updateSettings(newProductApiUrl: v),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _prodKeyCtrl,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: styledInput('Anon key'),
                            onSubmitted: (v) => app.updateSettings(newProductApiKey: v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(app.productApiConfigured ? Icons.check_circle : Icons.info_outline, 
                            size: 14, color: app.productApiConfigured ? Colors.greenAccent : Colors.orangeAccent),
                        const SizedBox(width: 6),
                        Text(
                          app.productApiConfigured
                              ? 'Configured and ready.'
                              : 'Not configured: spec fetch is disabled; enter specs manually.',
                          style: TextStyle(fontSize: 11, color: app.productApiConfigured ? Colors.greenAccent : Colors.orangeAccent, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // --- AI deployment advisor (M7e) -----------------------------------------
              sectionContainer(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    sectionHeader('AI Deployment Advisor (Online)', icon: Icons.auto_awesome),
                    const SizedBox(height: 16),
                    const Text(
                      'OpenAI-compatible endpoint used at HQ to suggest a drone '
                      'deployment from the mission (free tiers work: Groq, '
                      'OpenRouter). The suggestion is always validated and the '
                      'operator approves it; the field plans manually offline.',
                      style: TextStyle(fontSize: 12, color: Colors.white54, height: 1.4),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Text('Presets:', style: TextStyle(fontSize: 12, color: Colors.white54, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 12),
                        OutlinedButton(
                          onPressed: () {
                            _aiEndpointCtrl.text = 'https://api.groq.com/openai/v1';
                            _aiModelCtrl.text = 'llama-3.3-70b-versatile';
                            app.updateSettings(
                                newAiEndpoint: _aiEndpointCtrl.text,
                                newAiModel: _aiModelCtrl.text);
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: BorderSide(color: Colors.white.withOpacity(0.2)),
                          ),
                          child: const Text('Groq'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () {
                            _aiEndpointCtrl.text = 'https://openrouter.ai/api/v1';
                            _aiModelCtrl.text = 'nvidia/nemotron-3-super-120b-a12b:free';
                            app.updateSettings(
                                newAiEndpoint: _aiEndpointCtrl.text,
                                newAiModel: _aiModelCtrl.text);
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: BorderSide(color: Colors.white.withOpacity(0.2)),
                          ),
                          child: const Text('OpenRouter'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _aiEndpointCtrl,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: styledInput('Base URL (…/v1)'),
                            onSubmitted: (v) => app.updateSettings(newAiEndpoint: v),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 1,
                          child: TextField(
                            controller: _aiModelCtrl,
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            decoration: styledInput('Model'),
                            onSubmitted: (v) => app.updateSettings(newAiModel: v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _aiKeyCtrl,
                      obscureText: true,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: styledInput('API key'),
                      onSubmitted: (v) => app.updateSettings(newAiApiKey: v),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(app.aiConfigured ? Icons.check_circle : Icons.info_outline, 
                            size: 14, color: app.aiConfigured ? Colors.greenAccent : Colors.orangeAccent),
                        const SizedBox(width: 6),
                        Text(
                          app.aiConfigured
                              ? 'Configured and ready.'
                              : 'Not configured: the AI suggest button is disabled.',
                          style: TextStyle(fontSize: 11, color: app.aiConfigured ? Colors.greenAccent : Colors.orangeAccent, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // --- Break-glass -----------------------------------------------------------
              sectionContainer(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    sectionHeader('Break-Glass HQ Key', icon: Icons.warning_amber_rounded, iconColor: Colors.orangeAccent),
                    const SizedBox(height: 16),
                    const Text(
                      'Recovery credential for when the personnel table is '
                      'empty (fresh fleet) or PIN login is unavailable. Stored '
                      'offline in the field; PIN login is the normal path.',
                      style: TextStyle(fontSize: 12, color: Colors.white54, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _apiKeyCtrl,
                      obscureText: true,
                      style: const TextStyle(color: Colors.orangeAccent, fontSize: 13, fontFamily: 'monospace'),
                      decoration: styledInput('HQ API key').copyWith(
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Colors.orangeAccent, width: 1.5),
                        ),
                      ),
                      onSubmitted: (v) => app.updateSettings(newApiKey: v),
                    ),
                  ],
                ),
                borderColor: Colors.orangeAccent.withOpacity(0.3),
              ),
              const SizedBox(height: 48), // Bottom padding
            ],
          ),
        ),
      ],
    );
  }
}

/// Live internet status with a manual re-check, sitting next to the online
/// features that depend on it. The app cannot infer this from the drone
/// link: joining a drone AP gives a working node connection and no
/// internet, which is the normal field state rather than a fault.
class _InternetStatusRow extends StatelessWidget {
  const _InternetStatusRow();

  @override
  Widget build(BuildContext context) {
    final net = context.watch<ConnectivityService>();
    final colour = switch (net.status) {
      NetStatus.online => Colors.greenAccent,
      NetStatus.portal => Colors.amberAccent,
      NetStatus.offline => Colors.orangeAccent,
      NetStatus.unknown => Colors.white54,
    };
    final checked = net.lastChecked;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colour.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colour.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(net.isOnline ? Icons.public : Icons.public_off, size: 24, color: colour),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(net.checking ? 'CHECKING CONNECTION...' : net.label.toUpperCase(),
                    style: TextStyle(fontWeight: FontWeight.w800, color: colour, fontSize: 11, letterSpacing: 1)),
                const SizedBox(height: 4),
                Text(net.detail, style: const TextStyle(fontSize: 12, color: Colors.white70)),
                if (checked != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Last checked ${formatAge(DateTime.now().difference(checked))}',
                    style: TextStyle(fontSize: 10, color: colour.withOpacity(0.7)),
                  ),
                ],
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: net.checking ? null : net.check,
            icon: net.checking 
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh, size: 16),
            label: Text(net.checking ? 'Checking' : 'Check now'),
            style: OutlinedButton.styleFrom(
              foregroundColor: colour,
              side: BorderSide(color: colour.withOpacity(0.4)),
            ),
          ),
        ],
      ),
    );
  }
}
