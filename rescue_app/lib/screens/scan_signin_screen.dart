/// Camera view for scanning the sign-in QR the GCC shows when HQ issues
/// credentials (field backlog #17).
///
/// Returns the raw scanned string to the caller and does nothing else with
/// it, so all the decoding and network work stays testable in
/// AuthProvider rather than being tangled up with a camera.
library;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ScanSigninScreen extends StatefulWidget {
  const ScanSigninScreen({super.key});

  @override
  State<ScanSigninScreen> createState() => _ScanSigninScreenState();
}

class _ScanSigninScreenState extends State<ScanSigninScreen> {
  /// A camera reports the same barcode many times a second. Without this,
  /// one scan would pop the screen repeatedly and fire several sign-ins.
  bool _handled = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null || value.isEmpty) continue;
      _handled = true;
      Navigator.of(context).pop(value);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan sign-in code'),
        backgroundColor: Colors.deepOrange.shade700,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          MobileScanner(onDetect: _onDetect),
          // A plain aiming box. Nothing clever: in daylight on a cracked
          // screen, a visible target beats a subtle one.
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: Colors.black87,
              padding: const EdgeInsets.all(16),
              child: const Text(
                'Point at the QR code on the HQ laptop. You do not need to '
                'type anything, and this works on any drone.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
