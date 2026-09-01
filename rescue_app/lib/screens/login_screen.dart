import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
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
  bool _obscurePin = true;

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
      backgroundColor: const Color(0xFFF8F9FA),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
                border: Border.all(color: const Color(0xFFEEEEEE)),
              ),
              padding: const EdgeInsets.all(32),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Header Icon & Title ────────────────────────────────
                    Image.asset(
                      'assets/logo_login.png',
                      height: 80,
                      errorBuilder: (context, error, stackTrace) => Icon(
                        Icons.health_and_safety_rounded,
                        size: 64,
                        color: AppTheme.kPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'AERO-LINK',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppTheme.kPrimary,
                            letterSpacing: 2.0,
                          ),
                    ),
                    const SizedBox(height: 8),

                    const SizedBox(height: 28),

                    // ── Logout Reason / Error ─────────────────────────────
                    if (logoutReason != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.kWarning.withOpacity(0.1),
                          border: Border.all(color: AppTheme.kWarning.withOpacity(0.3)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, size: 20, color: Colors.orange.shade800),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                logoutReason,
                                style: TextStyle(color: Colors.orange.shade900, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ── Inputs ──────────────────────────────────────────────
                    TextFormField(
                      controller: _idController,
                      decoration: InputDecoration(
                        labelText: 'Personnel ID',
                        hintText: 'e.g. R-014',
                        prefixIcon: const Icon(Icons.badge_outlined),
                        filled: true,
                        fillColor: const Color(0xFFF5F7FA),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: AppTheme.kPrimary, width: 2),
                        ),
                      ),
                      textCapitalization: TextCapitalization.characters,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Personnel ID is required'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _pinController,
                      decoration: InputDecoration(
                        labelText: 'PIN',
                        prefixIcon: const Icon(Icons.password_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePin ? Icons.visibility_off : Icons.visibility,
                            color: Colors.grey.shade600,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePin = !_obscurePin;
                            });
                          },
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF5F7FA),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: AppTheme.kPrimary, width: 2),
                        ),
                      ),
                      obscureText: _obscurePin,
                      keyboardType: TextInputType.number,
                      validator: (v) => (v == null || v.trim().length < 4)
                          ? 'Enter the PIN you were issued'
                          : null,
                      onFieldSubmitted: (_) => _busy ? null : _login(),
                    ),

                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.kDanger.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, size: 16, color: AppTheme.kDanger),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(color: AppTheme.kDanger, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 32),

                    // ── Primary Action: SCAN ──────────────────────────────
                    SizedBox(
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _busy ? null : _scanToSignIn,
                        icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
                        label: const Text(
                          'SCAN CODE FROM HQ',
                          style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.kPrimary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),

                    // ── Divider ─────────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Row(
                        children: [
                          const Expanded(child: Divider()),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'OR TYPE PIN',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade400,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                          const Expanded(child: Divider()),
                        ],
                      ),
                    ),

                    // ── Secondary Action: LOG IN ──────────────────────────
                    SizedBox(
                      height: 52,
                      child: OutlinedButton(
                        onPressed: _busy ? null : _login,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.kPrimary,
                          side: const BorderSide(color: AppTheme.kPrimary, width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(AppTheme.kPrimary),
                                ),
                              )
                            : const Text(
                                'LOG IN',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1,
                                ),
                              ),
                      ),
                    ),

                    // ── Footer link ─────────────────────────────────────────
                    const SizedBox(height: 24),
                    TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const SettingsScreen(),
                                ),
                              ),
                      
                      label: const Text(
                        'Connection Settings',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.kPrimary,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
