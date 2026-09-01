import 'package:flutter_test/flutter_test.dart';
import 'package:rescue_app/models/message_model.dart';
import 'package:rescue_mesh_shared/rescue_mesh_shared.dart' as shared;

void main() {
  group('Rescue App Media Models', () {
    test('Message with attachments from shared', () {
      final sharedMsg = shared.Message(
        msgId: 'msg_101',
        content: 'SOS trapped on roof',
        userLat: 6.9271,
        userLon: 79.8612,
        timestamp: '2026-09-02T10:00:00Z',
        timeSource: 'gps',
        nodeId: 'DRONE_01',
        status: 'NEW',
        attachments: [
          const shared.MediaAttachment(
            id: 'att_audio_1',
            parentId: 'msg_101',
            filename: 'voice.m4a',
            mimeType: 'audio/m4a',
            sizeBytes: 15400,
            sha256: 'deadbeef123',
            createdAt: '2026-09-02T10:00:00Z',
          ),
          const shared.MediaAttachment(
            id: 'att_img_1',
            parentId: 'msg_101',
            filename: 'photo.jpg',
            mimeType: 'image/jpeg',
            sizeBytes: 84000,
            sha256: 'cafebabe456',
            createdAt: '2026-09-02T10:00:00Z',
          ),
        ],
      );

      final msg = Message.fromShared(sharedMsg);
      expect(msg.hasAttachments, isTrue);
      expect(msg.attachments.length, equals(2));
      expect(msg.attachments[0].isAudio, isTrue);
      expect(msg.attachments[1].isImage, isTrue);
    });

    test('GSMessage with attachments from shared', () {
      final sharedGs = shared.GsMessage(
        id: 'gs_101',
        content: 'Field Team report from sector 4',
        sender: 'R-014',
        timestamp: '2026-09-02T10:05:00Z',
        nodeId: 'DRONE_01',
        attachments: [
          const shared.MediaAttachment(
            id: 'att_img_2',
            parentId: 'gs_101',
            filename: 'field.jpg',
            mimeType: 'image/jpeg',
            sizeBytes: 92000,
            sha256: 'aabbccdd',
            createdAt: '2026-09-02T10:05:00Z',
          ),
        ],
      );

      final gsMsg = GSMessage.fromShared(sharedGs);
      expect(gsMsg.hasAttachments, isTrue);
      expect(gsMsg.attachments.first.filename, equals('field.jpg'));
    });
  });
}
