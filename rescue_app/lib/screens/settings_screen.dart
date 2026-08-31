library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rescue_mesh_shared/rescue_mesh_shared.dart' as shared;

import '../config/api_config.dart';
import '../config/app_theme.dart';
import '../providers/auth_provider.dart';
import '../providers/heartbeat_provider.dart';
import '../providers/message_provider.dart';
import '../services/api_service.dart';
import '../widgets/custom_snackbar.dart';

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
  bool _obscureApiKey = true;

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

    CustomSnackBar.show(context, 'Settings saved successfully.',
        type: SnackBarType.success);
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
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.kPrimary),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Session Card ────────────────────────────────────────
                    _sectionLabel('Account'),
                    _card(
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: (auth.isLoggedIn
                                      ? AppTheme.kSuccess
                                      : Colors.grey.shade400)
                                  .withOpacity(0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              auth.isLoggedIn
                                  ? Icons.verified_user_rounded
                                  : Icons.no_accounts_rounded,
                              color: auth.isLoggedIn
                                  ? AppTheme.kSuccess
                                  : Colors.grey.shade500,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  auth.isLoggedIn
                                      ? auth.displayName ?? 'Logged in'
                                      : (auth.breakGlassAccepted
                                          ? 'Break-glass admin'
                                          : 'Not logged in'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    color: Color(0xFF1A1A2E),
                                  ),
                                ),
                                Text(
                                  auth.isLoggedIn
                                      ? 'Active session'
                                      : (auth.breakGlassAccepted
                                          ? 'No PIN session active'
                                          : 'Sign in to send and receive messages'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (auth.isLoggedIn)
                            TextButton(
                              onPressed: () async {
                                await auth.logout();
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: AppTheme.kDanger,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                              ),
                              child: const Text(
                                'Log out',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Location sharing ─────────────────────────────────────
                    _sectionLabel('Location'),
                    Consumer<HeartbeatProvider>(
                      builder: (context, hb, _) {
                        final last = hb.lastSent;
                        final subtitle = !hb.enabled
                            ? 'Your position is not shared.'
                            : (last == null
                                ? 'Sends your location while logged in (every 90 s).'
                                : 'Last sent ${DateFormat.Hms().format(last.toLocal())}.');
                        return _card(
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: (hb.enabled
                                          ? AppTheme.kPrimary
                                          : Colors.grey.shade400)
                                      .withOpacity(0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.my_location_rounded,
                                  color: hb.enabled
                                      ? AppTheme.kPrimary
                                      : Colors.grey.shade500,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Share my location',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                        color: Color(0xFF1A1A2E),
                                      ),
                                    ),
                                    Text(
                                      subtitle,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: hb.enabled,
                                onChanged: (v) async {
                                  if (v) {
                                    final serviceEnabled =
                                        await Geolocator.isLocationServiceEnabled();
                                    if (!serviceEnabled) {
                                      if (context.mounted) {
                                        CustomSnackBar.show(
                                          context,
                                          'Please enable Location Services in your device settings.',
                                          type: SnackBarType.error,
                                        );
                                      }
                                      await Geolocator.openLocationSettings();
                                    }
                                    var perm = await Geolocator.checkPermission();
                                    if (perm == LocationPermission.denied) {
                                      perm = await Geolocator.requestPermission();
                                    }
                                    if (perm == LocationPermission.deniedForever) {
                                      if (context.mounted) {
                                        CustomSnackBar.show(
                                          context,
                                          'Location permissions are permanently denied. Please enable them in app settings.',
                                          type: SnackBarType.error,
                                        );
                                      }
                                      await Geolocator.openAppSettings();
                                    }
                                  }
                                  hb.setEnabled(value: v);
                                },
                                activeColor: AppTheme.kPrimary,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 20),

                    // ── Node Health ───────────────────────────────────────────
                    _sectionLabel('Node Status'),
                    _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _healthLoading
                                      ? Colors.orange
                                      : (_health != null
                                          ? AppTheme.kSuccess
                                          : Colors.grey.shade400),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _healthLoading
                                    ? 'Checking node...'
                                    : (_health != null
                                        ? 'Node connected'
                                        : 'No node reachable'),
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: _health != null
                                      ? const Color(0xFF1A1A2E)
                                      : Colors.grey.shade600,
                                ),
                              ),
                              const Spacer(),
                              GestureDetector(
                                onTap: _healthLoading ? null : _refreshHealth,
                                child: AnimatedOpacity(
                                  opacity: _healthLoading ? 0.4 : 1.0,
                                  duration: const Duration(milliseconds: 200),
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF5F7FA),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.refresh_rounded,
                                        size: 16,
                                        color: AppTheme.kPrimary),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_health != null) ...[
                            const SizedBox(height: 10),
                            const Divider(height: 1),
                            const SizedBox(height: 10),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _healthChip(Icons.flight_rounded, 'Drone: ${_health!.nodeId}'),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _health!.battery.aV != null || _health!.battery.bV != null
                                      ? Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            if (_health!.battery.aV != null)
                                              _healthChip(Icons.battery_charging_full_rounded,
                                                  'Battery A: ${_health!.battery.aV!.toStringAsFixed(2)}V'),
                                            if (_health!.battery.bV != null)
                                              Padding(
                                                padding: EdgeInsets.only(top: _health!.battery.aV != null ? 6 : 0),
                                                child: _healthChip(Icons.battery_charging_full_rounded,
                                                    'Battery B: ${_health!.battery.bV!.toStringAsFixed(2)}V'),
                                              ),
                                          ],
                                        )
                                      : _healthChip(Icons.battery_unknown_rounded, 'Battery: N/A'),
                                ),
                              ],
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: _healthChip(
                                _health!.gps.hasFix
                                    ? Icons.gps_fixed_rounded
                                    : Icons.gps_not_fixed_rounded,
                                _health!.gps.hasFix
                                    ? 'GPS fix (${_health!.gps.sats} sats)'
                                    : 'No GPS fix',
                              ),
                            ),
                          ] else if (!_healthLoading) ...[
                            const SizedBox(height: 8),
                            Text(
                              _healthError ??
                                  'Join a RESCUE_x Wi-Fi network to connect.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Connection ─────────────────────────────────────────
                    _sectionLabel('Connection'),
                    _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [

                          _inputField(
                            controller: _fleetCaController,
                            label: 'Fleet CA certificate (PEM)',
                            hint: 'Paste fleet_ca.crt contents',
                            icon: Icons.security_rounded,
                            minLines: 3,
                            maxLines: 6,
                            validator: (value) {
                              final v = (value ?? '').trim();
                              if (v.isEmpty) {
                                return null;
                              }
                              if (!v.contains('BEGIN CERTIFICATE')) {
                                return 'Paste a PEM certificate (BEGIN CERTIFICATE)';
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 12),
                          _switchRow(
                            icon: Icons.warning_amber_rounded,
                            iconColor: AppTheme.kWarning,
                            title: 'Accept ANY certificate',
                            subtitle: 'Dev/bench only — never enable in field.',
                            value: _allowInsecure,
                            onChanged: (v) =>
                                setState(() => _allowInsecure = v),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),

                    // ── Break-glass / Advanced ────────────────────────────────
                    /*
                    _sectionLabel('Break-glass / Advanced'),
                    _card(
                      child: Column(
                        children: [
                          _inputField(
                            controller: _apiKeyController,
                            label: 'Admin API key (optional)',
                            hint: 'Break-glass only',
                            icon: Icons.vpn_key_rounded,
                            obscureText: _obscureApiKey,
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureApiKey
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: Colors.grey.shade600,
                              ),
                              onPressed: () => setState(
                                  () => _obscureApiKey = !_obscureApiKey),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.only(left: 4, top: 4),
                            child: Text(
                              'Recovery credential only. Normal use is PIN login; leave empty unless HQ issued the key.',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade600),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _inputField(
                            controller: _privateKeyController,
                            label: 'Rescue private key PEM (optional)',
                            hint: 'Only needed if E2E encryption is enabled',
                            icon: Icons.lock_outline_rounded,
                            minLines: 3,
                            maxLines: 6,
                            validator: (value) {
                              final v = (value ?? '').trim();
                              if (v.isEmpty) {
                                return null;
                              }
                              if (!v.contains('BEGIN') ||
                                  !v.contains('PRIVATE KEY')) {
                                return 'Paste a valid PEM private key';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.only(left: 4, top: 4),
                            child: Text(
                              'E2E encryption is OFF by default. Paste key only if your fleet enabled it.',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade600),
                            ),
                          ),
                        ],
                      ),
                    ),
                    */

                    // ── Save Button ────────────────────────────────────────────
                    SizedBox(
                      height: 52,
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.kPrimary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _saving
                            ?
                             const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              )
                            : const Text(
                                'Save Settings',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  letterSpacing: 0.5,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _sectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Colors.grey.shade500,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }

  Widget _inputField({
    required TextEditingController controller,
    required String label,
    String? hint,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    int minLines = 1,
    int? maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      minLines: minLines,
      maxLines: maxLines,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xFFF5F7FA),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.kPrimary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.kDanger, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppTheme.kDanger, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _switchRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14)),
              Text(subtitle,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: AppTheme.kPrimary,
        ),
      ],
    );
  }

  Widget _healthChip(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey.shade500),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ),
      ],
    );
  }
}
