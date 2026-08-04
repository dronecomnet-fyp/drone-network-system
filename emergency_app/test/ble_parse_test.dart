import 'package:emergency_app/services/ble_watch_service.dart';
import 'package:emergency_app/state/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  _autoOpenTests();
  _autoOpenWiringTests();
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

/// Auto-open rule (field backlog #9).
///
/// The bug testers hit: with TWO drones powered, the app opened the
/// drone-found screen over and over and stacked many screens. The first
/// implementation compared each sighting against the single most recent
/// one, which is correct with one drone and wrong with two, because
/// sightings alternate A, B, A, B several times a second and every one of
/// them then counts as "a new drone".
void _autoOpenTests() {
  group('auto-open on sighting', () {
    test('opens once for a drone, not on every advertisement', () {
      final c = AppController();
      final t0 = DateTime(2026, 8, 3, 10, 0, 0);
      expect(c.shouldAutoOpen('DRONE_A', t0), isTrue);
      for (var ms = 500; ms <= 60000; ms += 500) {
        expect(c.shouldAutoOpen('DRONE_A', t0.add(Duration(milliseconds: ms))),
            isFalse);
      }
    });

    test('TWO drones alternating do not reopen forever', () {
      // The exact reported case. Each drone gets one open, then silence.
      final c = AppController();
      final t0 = DateTime(2026, 8, 3, 10, 0, 0);
      var opens = 0;
      for (var i = 0; i < 200; i++) {
        final node = i.isEven ? 'DRONE_A' : 'DRONE_B';
        if (c.shouldAutoOpen(node, t0.add(Duration(milliseconds: i * 500)))) {
          opens++;
        }
      }
      expect(opens, 2, reason: 'one per drone, not one per advertisement');
    });

    test('a genuinely new drone still opens straight away', () {
      final c = AppController();
      final t0 = DateTime(2026, 8, 3, 10, 0, 0);
      expect(c.shouldAutoOpen('DRONE_A', t0), isTrue);
      expect(c.shouldAutoOpen('DRONE_S', t0), isTrue,
          reason: 'a different drone arriving is real news');
    });

    test('after the cooldown the same drone may open again', () {
      final c = AppController();
      final t0 = DateTime(2026, 8, 3, 10, 0, 0);
      expect(c.shouldAutoOpen('DRONE_A', t0), isTrue);
      expect(c.shouldAutoOpen('DRONE_A', t0.add(AppController.reopenAfter)),
          isTrue);
    });
  });
}

/// Field backlog #10: "auto-open exists in Settings but appears not to
/// work". The cooldown rule above was already tested; the DELIVERY was
/// not, and a setting that is stored correctly but never consulted looks
/// exactly like a broken feature from the outside.
///
/// The watch calls onSighting for every advertisement it parses, so
/// driving that callback directly is the same path a real radio takes,
/// minus the radio.
void _autoOpenWiringTests() {
  group('auto-open wiring', () {
    DroneSighting sighting(String node) => DroneSighting(
          nodeLabel: node,
          ssid: 'RESCUE_$node',
          rssi: -60,
          seenAt: DateTime(2026, 8, 5, 10, 0, 0),
        );

    test('a sighting opens the screen when the setting is on', () {
      final c = AppController();
      c.autoOpenOnDrone = true;
      DroneSighting? opened;
      c.onAutoOpen = (s) => opened = s;

      c.watch.onSighting!(sighting('DRONE_A'));
      expect(opened, isNotNull);
      expect(opened!.nodeLabel, 'DRONE_A');
    });

    test('nothing opens while the setting is off', () {
      final c = AppController();
      c.autoOpenOnDrone = false;
      var opens = 0;
      c.onAutoOpen = (_) => opens++;

      c.watch.onSighting!(sighting('DRONE_A'));
      expect(opens, 0);
    });

    test('nothing opens before the operator has been asked', () {
      // null means never answered. Taking over the screen without consent
      // is worse than not taking it over at all.
      final c = AppController();
      expect(c.autoOpenOnDrone, isNull);
      var opens = 0;
      c.onAutoOpen = (_) => opens++;

      c.watch.onSighting!(sighting('DRONE_A'));
      expect(opens, 0);
    });

    test('the sighting is recorded for the UI even when it does not open', () {
      final c = AppController();
      c.autoOpenOnDrone = false;
      c.watch.onSighting!(sighting('DRONE_B'));
      expect(c.lastSighting?.nodeLabel, 'DRONE_B',
          reason: 'the home screen shows this regardless of auto-open');
    });

    test('two drones advertising continuously open twice, not forever', () {
      final c = AppController();
      c.autoOpenOnDrone = true;
      var opens = 0;
      c.onAutoOpen = (_) => opens++;
      for (var i = 0; i < 100; i++) {
        c.watch.onSighting!(sighting(i.isEven ? 'DRONE_A' : 'DRONE_B'));
      }
      expect(opens, 2);
    });
  });
}
