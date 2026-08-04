/// The @-attach composer (field backlog #14).
///
/// Two things are worth testing without a UI: the text surgery, because an
/// off-by-one there silently eats a character from a sentence somebody is
/// composing under pressure, and the ordering, because the first screenful
/// of the picker is all most people read.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gcc_app/state/mentionables.dart';
import 'package:gcc_app/widgets/mention_field.dart';
import 'package:rescue_mesh_shared/rescue_mesh_shared.dart';

Message _msg({
  required String device,
  String content = 'help',
  bool claimed = false,
  double? lat,
  double? lon,
  String ts = '2026-08-05T09:00:00Z',
}) =>
    Message(
      msgId: 'm-$device',
      content: content,
      userLat: lat,
      userLon: lon,
      timestamp: ts,
      timeSource: 'gps',
      nodeId: 'DRONE_A',
      status: claimed ? 'CLAIMED' : 'NEW',
      claimedBy: claimed ? 'RESC-01' : '',
      victimDeviceId: device,
    );

void main() {
  group('applyMention', () {
    test('replaces the @ in the middle of a sentence', () {
      final r = applyMention('send help to @ now', 13, '@victim-ab12cd34');
      // One space, not two: the text after the @ already had one.
      expect(r.text, 'send help to @victim-ab12cd34 now');
      expect(r.caret, 'send help to @victim-ab12cd34'.length);
    });

    test('replaces an @ at the very end', () {
      final r = applyMention('go to @', 6, '@DRONE_B');
      expect(r.text, 'go to @DRONE_B ');
      expect(r.caret, r.text.length);
    });

    test('appends instead of corrupting text when the @ has moved', () {
      // The operator deleted the @ while the picker was open.
      final r = applyMention('go to the school', 6, '@DRONE_B');
      expect(r.text, 'go to the school @DRONE_B ');
    });

    test('does not double the space when the text already ends in one', () {
      final r = applyMention('go now ', 99, '@DRONE_B');
      expect(r.text, 'go now @DRONE_B ');
    });
  });

  group('buildMentionables', () {
    test('a degraded drone carries its last known position', () {
      final list = buildMentionables(
        health: NodeHealth.fromJson({
          'node_id': 'DRONE_A',
          'degraded_nodes': [
            {'node_id': 'DRONE_B', 'lat': 6.9271, 'lon': 79.8612,
             'ts': '2026-08-05T09:00:00Z'}
          ],
        }),
        messages: const [],
        rescuers: const [],
      );
      final b = list.firstWhere((m) => m.label == 'DRONE_B');
      expect(b.token, '@DRONE_B (6.92710, 79.86120)');
      expect(b.kind, 'Degraded');
    });

    test('degraded drones come before victims and drones', () {
      final list = buildMentionables(
        health: NodeHealth.fromJson({
          'node_id': 'DRONE_A',
          'degraded_nodes': [
            {'node_id': 'DRONE_B', 'ts': '2026-08-05T09:00:00Z'}
          ],
        }),
        messages: [_msg(device: 'aaaabbbbcccc')],
        rescuers: const [],
      );
      expect(list.first.kind, 'Degraded');
    });

    test('unclaimed victims sort above claimed ones', () {
      final list = buildMentionables(
        messages: [
          _msg(device: 'claimed-one', claimed: true),
          _msg(device: 'unclaimed-one'),
        ],
        rescuers: const [],
      );
      final victims = list.where((m) => m.kind == 'Victims').toList();
      expect(victims.first.label, 'victim unclaime');
      expect(victims.first.subtitle, startsWith('NEW'));
    });

    test('one victim with several messages appears once', () {
      final list = buildMentionables(
        messages: [
          _msg(device: 'same-device', content: 'first'),
          _msg(device: 'same-device', content: 'second'),
        ],
        rescuers: const [],
      );
      expect(list.where((m) => m.kind == 'Victims').length, 1);
    });

    test('a victim with no position still attaches, without fake coords', () {
      final list = buildMentionables(
        messages: [_msg(device: 'nolocation1')],
        rescuers: const [],
      );
      final v = list.firstWhere((m) => m.kind == 'Victims');
      expect(v.token, '@victim-nolocati');
      expect(v.token.contains('('), isFalse);
    });
  });

  testWidgets('typing @ opens the picker and inserts the token',
      (tester) async {
    final ctrl = TextEditingController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MentionField(
          controller: ctrl,
          options: const [
            Mentionable(
                kind: 'Drones',
                label: 'DRONE_B',
                token: '@DRONE_B (6.92710, 79.86120)'),
          ],
        ),
      ),
    ));

    // Typed a character at a time, the way a keyboard delivers it. The
    // widget deliberately ignores a whole-string paste containing an @,
    // so that the picker never jumps out at an unpredictable moment.
    await tester.enterText(find.byType(TextField).first, 'go to');
    await tester.enterText(find.byType(TextField).first, 'go to ');
    await tester.enterText(find.byType(TextField).first, 'go to @');
    await tester.pumpAndSettle();
    expect(find.text('Attach to this message'), findsOneWidget);

    await tester.tap(find.text('DRONE_B').last);
    await tester.pumpAndSettle();
    expect(ctrl.text, 'go to @DRONE_B (6.92710, 79.86120) ');
  });
}
