/// NetworkBinder: force this app's traffic onto Wi-Fi (file 06, bench
/// finding 2026-07-14).
///
/// The drone AP has no internet by design, so Android will not make it the
/// default network. With mobile data on, requests leave over cellular where
/// 10.42.0.1 has no route, so the checkin upload and the SOS fail silently
/// while the phone is sitting on RESCUE_A.
///
/// This matters most in THIS app: it is aimed at ordinary citizens, who
/// cannot be expected to know they must turn mobile data off before asking
/// for help. Binding the process to the Wi-Fi network makes it just work.
///
/// Safe to call repeatedly; a no-op on platforms without the channel.
library;

import 'package:flutter/services.dart';

class NetworkBinder {
  static const MethodChannel _channel = MethodChannel('rescue_mesh/network');

  /// Route this app over Wi-Fi (even a Wi-Fi with no internet).
  static Future<void> bindToWifi() async {
    try {
      await _channel.invokeMethod<bool>('bindToWifi');
    } on PlatformException {
      // Older Android or missing permission: fall back to default routing.
    } on MissingPluginException {
      // Not Android (or channel unavailable in tests): nothing to do.
    }
  }

  /// Release the binding and go back to the system default network.
  static Future<void> unbind() async {
    try {
      await _channel.invokeMethod<bool>('unbind');
    } on PlatformException {
      // ignore
    } on MissingPluginException {
      // ignore
    }
  }
}
