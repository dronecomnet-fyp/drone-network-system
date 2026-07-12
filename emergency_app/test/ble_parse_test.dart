import 'package:emergency_app/services/ble_watch_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BLE service-data parsing (file 03 payload nodeId|ssid)', () {
    test('parses a well-formed advertisement payload', () {
      final s = BleWatchService.parsePayloadBytes('A|RESCUE_A'.codeUnits);
      expect(s, isNotNull);
      expect(s!.nodeLabel, 'A');
      expect(s.ssid, 'RESCUE_A');
    });

    test('ssid may itself be the full name', () {
      final s = BleWatchService.parsePayloadBytes('S|RESCUE_S'.codeUnits,
          rssi: -72);
      expect(s!.ssid, 'RESCUE_S');
      expect(s.rssi, -72);
    });

    test('empty or malformed payloads are ignored (no false alerts)', () {
      expect(BleWatchService.parsePayloadBytes(<int>[]), isNull);
      expect(BleWatchService.parsePayloadBytes('nopipe'.codeUnits), isNull);
    });
  });
}
