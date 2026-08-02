/// Victim conversation parsing and the delivery-state mapping.
///
/// The tick states are the part worth pinning. They borrow a familiar
/// idiom, and the risk of borrowing it is that people also borrow its
/// TIMING expectations: the apps everyone knows deliver in seconds, while
/// this network can genuinely take hours. So the mapping has to stay
/// honest, and "seen" must never creep into meaning "help is coming".
library;

import 'package:rescue_mesh_shared/rescue_mesh_shared.dart';
import 'package:test/test.dart';

void main() {
  Map<String, dynamic> node({String status = 'NEW', List<dynamic>? replies}) => {
        'messages': [
          {
            'msg_id': 'm1',
            'content': 'I am trapped by water',
            'timestamp': '2026-08-02T10:00:00.000000Z',
            'status': status,
            'user_lat': 6.92,
            'user_lon': 79.86,
          }
        ],
        'replies': replies ?? [],
      };

  group('delivery state', () {
    test('a stored message is on the drone, not yet seen', () {
      final c = Conversation.fromJson(node());
      expect(c.entries.single.state, DeliveryState.onDrone);
    });

    test('a claimed message is seen', () {
      final c = Conversation.fromJson(node(status: 'CLAIMED'));
      expect(c.entries.single.state, DeliveryState.seen);
    });

    test('waiting is a real state the node can never report', () {
      // The node only ever knows about messages it already has, so
      // "waiting on the phone" has to be tracked client side. If it were
      // folded into onDrone, a victim with no drone overhead would see a
      // tick implying the message had left their phone when it had not.
      final c = Conversation.fromJson(node());
      expect(c.entries.every((e) => e.state != DeliveryState.waiting), isTrue);
    });
  });

  group('thread assembly', () {
    test('victim messages and replies interleave in time order', () {
      final c = Conversation.fromJson({
        'messages': [
          {'msg_id': 'm1', 'content': 'first', 'timestamp': '2026-08-02T10:00:00Z',
           'status': 'CLAIMED'},
          {'msg_id': 'm2', 'content': 'third', 'timestamp': '2026-08-02T12:00:00Z',
           'status': 'NEW'},
        ],
        'replies': [
          {'id': 'r1', 'body': 'second', 'created_at': '2026-08-02T11:00:00Z',
           'sender': 'RESCUE_01'},
        ],
      });
      expect(c.entries.map((e) => e.body).toList(), ['first', 'second', 'third']);
      expect(c.entries[1].fromVictim, isFalse);
      expect(c.entries[1].sender, 'RESCUE_01');
    });

    test('an empty thread is empty, not an error', () {
      final c = Conversation.fromJson({'messages': [], 'replies': []});
      expect(c.isEmpty, isTrue);
      expect(c.latestOwnState, isNull);
    });

    test('missing keys entirely are tolerated', () {
      expect(Conversation.fromJson({}).isEmpty, isTrue);
    });

    test('latestOwnState ignores replies and reports the newest own message',
        () {
      final c = Conversation.fromJson({
        'messages': [
          {'msg_id': 'm1', 'content': 'old', 'timestamp': '2026-08-02T10:00:00Z',
           'status': 'CLAIMED'},
          {'msg_id': 'm2', 'content': 'new', 'timestamp': '2026-08-02T13:00:00Z',
           'status': 'NEW'},
        ],
        'replies': [
          {'id': 'r1', 'body': 'reply', 'created_at': '2026-08-02T14:00:00Z',
           'sender': 'RESCUE_01'},
        ],
      });
      expect(c.latestOwnState, DeliveryState.onDrone);
    });

    test('a victim message keeps its location for the map pin', () {
      final c = Conversation.fromJson(node());
      expect(c.entries.single.hasLocation, isTrue);
      expect(c.entries.single.lat, 6.92);
    });
  });
}
