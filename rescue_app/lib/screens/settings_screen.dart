/// Settings (file 05): connection, trust material, and the labeled
/// break-glass admin path. Changes vs Phase 1:
///   - fleet CA paste field: HTTPS trusts ONLY this root and fails closed
///     without it (file 09 F1; replaces accept-any-cert-for-10.42.0.1)
///   - API key demoted to optional break-glass (PIN login is the normal
///     path); private key optional (E2E is off by default, file 09 D2)
///   - logout button (file 05 task 5.1)
///   - node health strip (file 05 task 5.3, useful during field tests)
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rescue_mesh_shared/rescue_mesh_shared.dart' as shared;

import '../config/api_config.dart';
import '../providers/auth_provider.dart';
import '../providers/message_provider.dart';
import '../services/api_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _baseUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _privateKeyController = TextEditingController();
  final _fleetCaController = TextEditingController();
  bool _allowInsecure = false;
  bool _loading = true;
  bool _saving = false;

  shared.NodeHealth? _health;
  String? _healthError;
  bool _healthLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final cfg = await ApiConfigStore.load();
    if (!mounted) {
      return;
    }

    _baseUrlController.text = cfg.baseUrl;
    _apiKeyController.text = cfg.apiKey;
    _privateKeyController.text = cfg.rescuePrivateKey;
    _fleetCaController.text = cfg.fleetCaPem;
    setState(() {
      _allowInsecure = cfg.allowInsecure;
      _loading = false;
    });
    _refreshHealth();
  }

  Future<void> _refreshHealth() async {
    setState(() {
      _healthLoading = true;
      _healthError = null;
    });
    try {
      final health = await APIService.getHealth();
      if (mounted) {
        setState(() => _health = health);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _healthError = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _healthLoading = false);
      }
    }
  }

  Future<void> _save() async {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) {
      return;
    }

    setState(() {
      _saving = true;
    });

    await ApiConfigStore.save(
      baseUrl: _baseUrlController.text,
      apiKey: _apiKeyController.text,
      rescuePrivateKey: _privateKeyController.text,
      fleetCaPem: _fleetCaController.text,
      allowInsecure: _allowInsecure,
    );

    if (!mounted) {
      return;
    }

    await Provider.of<AuthProvider>(context, listen: false)
        .refreshBreakGlass();
    if (!mounted) {
      return;
    }
    final provider = Provider.of<MessageProvider>(context, listen: false);
    provider.resumePollingAfterCredentialsUpdate();
    await provider.fetchMessages();

    setState(() {
      _saving = false;
    });

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved.')),
    );
    _refreshHealth();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _privateKeyController.dispose();
    _fleetCaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // --- Session --------------------------------------------
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(
                              auth.isLoggedIn
                                  ? Icons.verified_user
                                  : Icons.no_accounts,
                              color: auth.isLoggedIn
                                  ? Colors.green
                                  : Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                auth.isLoggedIn
                                    ? 'Logged in as ${auth.displayName}'
                                    : (auth.breakGlassAccepted
                                        ? 'Break-glass admin mode (no PIN '
                                            'session)'
                                        : 'Not logged in'),
                              ),
                            ),
                            if (auth.isLoggedIn)
                              TextButton(
                                onPressed: () async {
                                  await auth.logout();
                                },
                                child: const Text('Log out'),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // --- Node health strip (file 05 task 5.3) ----------------
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text('Connected node',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(Icons.refresh, size: 18),
                                  onPressed:
                                      _healthLoading ? null : _refreshHealth,
                                ),
                              ],
                            ),
                            if (_health != null)
                              Text(
                                [
                                  _health!.nodeId,
                                  'clock: ${_health!.clockSource}',
                                  if (_health!.battery.aV != null)
                                    'bat A ${_health!.battery.aV!.toStringAsFixed(2)} V',
                                  if (_health!.battery.bV != null)
                                    'bat B ${_health!.battery.bV!.toStringAsFixed(2)} V',
                                  _health!.gps.hasFix
                                      ? 'GPS fix (${_health!.gps.sats} sats)'
                                      : 'no GPS fix',
                                ].join('  |  '),
                                style: Theme.of(context).textTheme.bodySmall,
                              )
                            else
                              Text(
                                _healthError ??
                                    'No node reachable. Join a RESCUE_x '
                                        'WiFi.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: Colors.grey.shade600),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // --- Connection -------------------------------------------
                    Text(
                      'Connection',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _baseUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Backend URL',
                        hintText: 'https://10.42.0.1:8443',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Backend URL is required';
                        }
                        if (!ApiConfigStore.isValidHttpUrl(value)) {
                          return 'Use full HTTP or HTTPS URL including port';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _fleetCaController,
                      decoration: const InputDecoration(
                        labelText: 'Fleet CA certificate (PEM)',
                        hintText: 'Paste fleet_ca.crt contents',
                        helperText:
                            'The app trusts ONLY this certificate authority '
                            'for HTTPS. Without it, connections fail closed '
                            'by design (evil-twin protection). Get it from '
                            'the operator (deploy/secrets/fleet_ca.crt).',
                        helperMaxLines: 4,
                        border: OutlineInputBorder(),
                      ),
                      minLines: 3,
                      maxLines: 6,
                      validator: (value) {
                        final v = (value ?? '').trim();
                        if (v.isEmpty) {
                          return null; // optional, but HTTPS will fail closed
                        }
                        if (!v.contains('BEGIN CERTIFICATE')) {
                          return 'Paste a PEM certificate (BEGIN CERTIFICATE)';
                        }
                        return null;
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Accept ANY certificate (INSECURE)'),
                      subtitle: const Text(
                          'Dev/bench only. Defeats evil-twin protection; '
                          'never enable in the field.'),
                      value: _allowInsecure,
                      onChanged: (v) => setState(() => _allowInsecure = v),
                    ),
                    const SizedBox(height: 16),

                    // --- Break-glass + E2E key -----------------------------------
                    Text(
                      'Break-glass / advanced',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _apiKeyController,
                      decoration: const InputDecoration(
                        labelText: 'Admin API key (break-glass, optional)',
                        helperText:
                            'Recovery credential only. Normal use is PIN '
                            'login; leave empty unless HQ gave you the key.',
                        helperMaxLines: 3,
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _privateKeyController,
                      decoration: const InputDecoration(
                        labelText: 'Rescue private key PEM (optional)',
                        hintText:
                            'Only needed if E2E victim encryption is enabled',
                        helperText:
                            'E2E encryption is OFF by default this phase; '
                            'paste the key only if your fleet enabled it.',
                        helperMaxLines: 3,
                        border: OutlineInputBorder(),
                      ),
                      minLines: 3,
                      maxLines: 6,
                      validator: (value) {
                        final v = (value ?? '').trim();
                        if (v.isEmpty) {
                          return null; // optional (file 09 D2)
                        }
                        if (!v.contains('BEGIN') ||
                            !v.contains('PRIVATE KEY')) {
                          return 'Paste a valid PEM private key';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Save Settings'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
