import 'package:emergency_app/services/ble_watch_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  _antiSpamTests();
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

/// Anti-spam rule for the drone-found notification.
///
/// Field bug: the scan re-reports an advertiser continuously (the aux
/// module advertises every 0.5 to 1 s), and every result raised a
/// high-priority notification. In range of a drone that fired several
/// alerts per second, which is unusable and teaches people to swipe away
/// the one notification that matters.
void _antiSpamTests() {
  group('drone-found notification anti-spam', () {
    test('the first sighting of a node notifies', () {
      final svc = BleWatchService();
      expect(svc.shouldNotify('DRONE_A', DateTime(2026, 8, 2, 10, 0, 0)), isTrue);
    });

    test('repeat sightings inside the cooldown do NOT notify', () {
      final svc = BleWatchService();
      final t0 = DateTime(2026, 8, 2, 10, 0, 0);
      expect(svc.shouldNotify('DRONE_A', t0), isTrue);
      // What a real scan looks like: many hits per second.
      for (var ms = 500; ms <= 60000; ms += 500) {
        expect(svc.shouldNotify('DRONE_A', t0.add(Duration(milliseconds: ms))),
            isFalse);
      }
    });

    test('a different drone notifies independently', () {
      final svc = BleWatchService();
      final t0 = DateTime(2026, 8, 2, 10, 0, 0);
      expect(svc.shouldNotify('DRONE_A', t0), isTrue);
      expect(svc.shouldNotify('DRONE_B', t0), isTrue,
          reason: 'a second drone in range is genuinely new information');
    });

    test('after the cooldown the same drone notifies again', () {
      final svc = BleWatchService();
      final t0 = DateTime(2026, 8, 2, 10, 0, 0);
      expect(svc.shouldNotify('DRONE_A', t0), isTrue);
      expect(svc.shouldNotify('DRONE_A', t0.add(BleWatchService.renotifyAfter)),
          isTrue);
    });

    test('re-arming clears the cooldown', () {
      final svc = BleWatchService();
      final t0 = DateTime(2026, 8, 2, 10, 0, 0);
      expect(svc.shouldNotify('DRONE_A', t0), isTrue);
      expect(svc.shouldNotify('DRONE_A', t0), isFalse);
      svc.resetNotificationHistory();
      expect(svc.shouldNotify('DRONE_A', t0), isTrue);
    });
  });
}
