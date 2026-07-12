import 'package:flutter_test/flutter_test.dart';
import 'package:rescue_app/models/api_error_model.dart';
import 'package:rescue_app/models/message_model.dart';
import 'package:rescue_mesh_shared/rescue_mesh_shared.dart' as shared;

void main() {
  group('Message (schema v3, file 05 task 5.3)', () {
    final sharedMsg = shared.Message.fromJson({
      'msg_id': 'abc12345-6789',
      'content': 'trapped near the bridge',
      'user_lat': 6.9271,
      'user_lon': 79.8612,
      'node_lat': 6.93,
      'node_lon': 79.86,
      'timestamp': '2026-07-12T04:30:00.000000Z',
      'time_source': 'relative',
      'node_id': 'DRONE_A',
      'status': 'CLAIMED',
      'claimed_by': 'R-014',
      'claimed_at': '2026-07-12T05:00:00.000000Z',
      'synced_from': 'DRONE_B',
      'is_encrypted': 0,
      'victim_device_id': 'aaaabbbb-cccc-dddd-eeee-ffff00001111',
    });

    test('fromShared maps every v3 field', () {
      final m = Message.fromShared(sharedMsg);
      expect(m.msgId, 'abc12345-6789');
      expect(m.userLat, 6.9271);
      expect(m.nodeLat, 6.93);
      expect(m.timeSource, 'relative');
      expect(m.nodeId, 'DRONE_A');
      expect(m.claimedBy, 'R-014');
      expect(m.syncedFrom, 'DRONE_B');
      expect(m.isClaimed, isTrue);
      expect(m.hasGpsLocation, isTrue);
    });

    test('relative time_source shows the ~ approximate hint', () {
      final m = Message.fromShared(sharedMsg);
      expect(m.isRelativeTime, isTrue);
      expect(m.displayTime, startsWith('~'));
    });

    test('gps time_source shows no hint', () {
      final gpsMsg = shared.Message.fromJson({
        'msg_id': 'x',
        'content': 'c',
        'timestamp': '2026-07-12T04:30:00.000000Z',
        'time_source': 'gps',
        'node_id': 'DRONE_A',
        'status': 'NEW',
      });
      final m = Message.fromShared(gpsMsg);
      expect(m.isRelativeTime, isFalse);
      expect(m.displayTime.startsWith('~'), isFalse);
    });

    test('claim copyWith carries the claimer identity', () {
      final m = Message.fromShared(sharedMsg)
          .copyWith(status: 'CLAIMED', claimedBy: 'R-055');
      expect(m.claimedBy, 'R-055');
      expect(m.isClaimed, isTrue);
    });

    test('shortDeviceId truncates long ids', () {
      final m = Message.fromShared(sharedMsg);
      expect(m.shortDeviceId, 'aaaabbbb...1111');
    });
  });

  group('GSMessage v3', () {
    test('ISO timestamp renders through displayTime', () {
      final g = GSMessage.fromShared(shared.GsMessage.fromJson({
        'id': 'g1',
        'content': 'road blocked',
        'sender': 'R-014',
        'timestamp': '2026-07-12T04:30:00.000000Z',
        'node_id': 'DRONE_B',
        'location_lat': 6.95,
        'location_lon': 79.9,
      }));
      expect(g.hasGpsLocation, isTrue);
      expect(g.displayTime, isNot(contains('T')));
      expect(g.shortCoords, contains('6.95'));
    });
  });

  group('ApiException taxonomy (file 05 task 5.1)', () {
    test('credential failures route to login', () {
      const expired = ApiException(
          type: ApiErrorType.sessionExpired, message: 'x', statusCode: 401);
      const revoked = ApiException(
          type: ApiErrorType.revoked, message: 'x', statusCode: 403);
      const network =
          ApiException(type: ApiErrorType.networkError, message: 'x');
      const pinning =
          ApiException(type: ApiErrorType.pinningFailed, message: 'x');
      expect(expired.isCredentialFailure, isTrue);
      expect(revoked.isCredentialFailure, isTrue);
      expect(network.isCredentialFailure, isFalse);
      // pinning failure is NOT a credential problem: logging in again on a
      // fake network must not be suggested
      expect(pinning.isCredentialFailure, isFalse);
    });
  });
}
