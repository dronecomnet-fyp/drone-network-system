/// LoginScreen (file 05 task 5.1): personnel_id + PIN -> signed session
/// token, verifiable offline by ANY node. Shown whenever no valid session
/// exists. The break-glass admin path stays available through Settings
/// (clearly labeled there).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/message_provider.dart';
import 'scan_signin_screen.dart';
import 'settings_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController();
  final _pinController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _idController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  /// Scan the QR the GCC shows when credentials are issued.
  ///
  /// Works on ANY drone, including one that has never heard of this person,
  /// because the code carries their signed record as well as the PIN.
  Future<void> _scanToSignIn() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScanSigninScreen()),
    );
    if (code == null || !mounted) return;
    setState(() => _busy = true);
    final err = await context.read<AuthProvider>().signInWithCode(code);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  Future<void> _login() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final err = await auth.login(
      _idController.text.trim(),
      _pinController.text.trim(),
    );
    if (!mounted) {
      return;
    }
    if (err != null) {
      setState(() {
        _busy = false;
        _error = err;
      });
      return;
    }
    // Session installed: resume polling with the new token.
    Provider.of<MessageProvider>(context, listen: false)
        .resumePollingAfterCredentialsUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final logoutReason = auth.lastLogoutReason;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.health_and_safety,
                      size: 64, color: Colors.deepOrange.shade700),
                  const SizedBox(height: 12),
                  Text(
                    'Rescue Mesh',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Join any RESCUE_x WiFi first, then log in with the '
                    'personnel ID and PIN issued by HQ. Your login works on '
                    'every drone in the fleet.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  if (logoutReason != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        border: Border.all(color: Colors.orange.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        logoutReason,
                        style: TextStyle(color: Colors.orange.shade900),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: _idController,
                    decoration: const InputDecoration(
                      labelText: 'Personnel ID',
                      hintText: 'e.g. R-014',
                      prefixIcon: Icon(Icons.badge),
                      border: OutlineInputBorder(),
                    ),
                    textCapitalization: TextCapitalization.characters,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Personnel ID is required'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _pinController,
                    decoration: const InputDecoration(
                      labelText: 'PIN',
                      prefixIcon: Icon(Icons.pin),
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    validator: (v) => (v == null || v.trim().length < 4)
                        ? 'Enter the PIN you were issued'
                        : null,
                    onFieldSubmitted: (_) => _busy ? null : _login(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                  ],
                  const SizedBox(height: 20),
                  // Offered FIRST because it is the easy path: HQ shows a
                  // QR, you scan it, you are working. Typing a six-digit
                  // PIN with cold or wet hands is the fallback, not the
                  // default (field backlog #17).
                  FilledButton.icon(
                    onPressed: _busy ? null : _scanToSignIn,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('SCAN CODE FROM HQ'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.deepOrange.shade700,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Row(children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('or type your PIN',
                          style: TextStyle(fontSize: 12)),
                    ),
                    Expanded(child: Divider()),
                  ]),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _busy ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepOrange.shade700,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            'LOG IN',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const SettingsScreen(),
                              ),
                            ),
                    child: const Text(
                        'Connection settings / break-glass admin key'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
