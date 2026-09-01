import 'package:rescue_mesh_shared/rescue_mesh_shared.dart';
import 'package:test/test.dart';

void main() {
  group('MediaAttachment models', () {
    test('MediaAttachment parses correctly from JSON', () {
      final json = {
        'id': 'att-123',
        'parent_id': 'msg-456',
        'filename': 'voice.m4a',
        'mime_type': 'audio/m4a',
        'size_bytes': 2048,
        'sha256': 'abcdef123',
        'created_at': '2026-09-02T02:00:00.000000Z',
      };

      final att = MediaAttachment.fromJson(json);
      expect(att.id, equals('att-123'));
      expect(att.parentId, equals('msg-456'));
      expect(att.filename, equals('voice.m4a'));
      expect(att.mimeType, equals('audio/m4a'));
      expect(att.sizeBytes, equals(2048));
      expect(att.isAudio, isTrue);
      expect(att.isImage, isFalse);
    });

    test('Message includes parsed attachments', () {
      final json = {
        'msg_id': 'msg-99',
        'content': 'Need help here',
        'timestamp': '2026-09-02T02:00:00.000000Z',
        'time_source': 'gps',
        'node_id': 'DRONE_A',
        'status': 'NEW',
        'attachments': [
          {
            'id': 'photo-1',
            'parent_id': 'msg-99',
            'filename': 'scene.jpg',
            'mime_type': 'image/jpeg',
            'size_bytes': 45000,
            'created_at': '2026-09-02T02:00:00.000000Z',
          }
        ],
      };

      final msg = Message.fromJson(json);
      expect(msg.hasAttachments, isTrue);
      expect(msg.hasImage, isTrue);
      expect(msg.hasAudio, isFalse);
      expect(msg.attachments.length, equals(1));
      expect(msg.attachments.first.filename, equals('scene.jpg'));
    });

    test('Conversation parses attachments per entry', () {
      final convoJson = {
        'messages': [
          {
            'msg_id': 'm1',
            'content': 'Trapped inside',
            'timestamp': '2026-09-02T02:00:00.000000Z',
            'status': 'NEW',
            'attachments': [
              {
                'id': 'a1',
                'parent_id': 'm1',
                'filename': 'voice.aac',
                'mime_type': 'audio/aac',
                'size_bytes': 15000,
                'created_at': '2026-09-02T02:00:00.000000Z',
              }
            ],
          }
        ],
        'replies': [],
      };

      final convo = Conversation.fromJson(convoJson);
      expect(convo.entries.length, equals(1));
      final entry = convo.entries.first;
      expect(entry.hasAttachments, isTrue);
      expect(entry.attachments.first.id, equals('a1'));
      expect(entry.attachments.first.isAudio, isTrue);
    });
  });
}
