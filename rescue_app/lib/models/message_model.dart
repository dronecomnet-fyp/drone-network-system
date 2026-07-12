/// App-side message models, schema v3 (file 05 task 5.3).
///
/// Wire parsing lives in the shared package (rescue_mesh_shared) so the
/// contract stays in one place for the GCC, this app, and the emergency
/// app (file 04); these classes wrap the shared models with UI-only state
/// (decryption results) and display helpers the screens use.
library;

import 'package:intl/intl.dart';
import 'package:rescue_mesh_shared/rescue_mesh_shared.dart' as shared;

class Message {
  final String msgId;
  final String content;
  final String? decryptedContent;
  final String? decryptionError;

  /// Victim GPS (schema v3 user_lat/user_lon).
  final double? userLat;
  final double? userLon;

  /// Node GPS at ingest (schema v3 node_lat/node_lon).
  final double? nodeLat;
  final double? nodeLon;

  /// ISO 8601 UTC string.
  final String timestamp;

  /// "gps" or "relative"; relative timestamps are approximate (node clock
  /// not yet GPS-synced) and are shown with a ~ prefix (design v3 3.3).
  final String timeSource;
  final String nodeId;
  final String status; // 'NEW' or 'CLAIMED'
  final String claimedBy;
  final String claimedAt;
  final String syncedFrom;
  final bool isEncrypted;
  final String encryptionAlg;
  final String encryptionKid;
  final String victimDeviceId;

  Message({
    required this.msgId,
    required this.content,
    this.decryptedContent,
    this.decryptionError,
    this.userLat,
    this.userLon,
    this.nodeLat,
    this.nodeLon,
    required this.timestamp,
    required this.timeSource,
    required this.nodeId,
    required this.status,
    this.claimedBy = '',
    this.claimedAt = '',
    this.syncedFrom = '',
    this.isEncrypted = false,
    this.encryptionAlg = '',
    this.encryptionKid = '',
    this.victimDeviceId = '',
  });

  factory Message.fromShared(shared.Message m) => Message(
        msgId: m.msgId,
        content: m.content,
        userLat: m.userLat,
        userLon: m.userLon,
        nodeLat: m.nodeLat,
        nodeLon: m.nodeLon,
        timestamp: m.timestamp,
        timeSource: m.timeSource,
        nodeId: m.nodeId,
        status: m.status,
        claimedBy: m.claimedBy,
        claimedAt: m.claimedAt,
        syncedFrom: m.syncedFrom,
        isEncrypted: m.isEncrypted,
        encryptionAlg: m.encryptionAlg,
        encryptionKid: m.encryptionKid,
        victimDeviceId: m.victimDeviceId,
      );

  bool get isClaimed => status == 'CLAIMED';
  bool get isNew => status == 'NEW';

  bool get isEncryptedPayload => isEncrypted;

  bool get isRelativeTime => timeSource != 'gps';

  String get displayContent {
    if (decryptedContent != null && decryptedContent!.trim().isNotEmpty) {
      return decryptedContent!;
    }

    if (isEncryptedPayload) {
      return '[Encrypted message]';
    }

    return content;
  }

  bool get hasDecryptionIssue =>
      isEncryptedPayload &&
      decryptedContent == null &&
      (decryptionError != null && decryptionError!.trim().isNotEmpty);

  /// "HH:mm:ss" local time; prefixed with ~ when the origin clock was not
  /// GPS-synced so rescuers know the time is approximate (file 05 5.3).
  String get displayTime {
    final parsed = DateTime.tryParse(timestamp);
    if (parsed == null) {
      return timestamp;
    }
    final formatted = DateFormat('HH:mm:ss').format(parsed.toLocal());
    return isRelativeTime ? '~$formatted' : formatted;
  }

  Message copyWith({
    String? content,
    String? decryptedContent,
    String? decryptionError,
    String? status,
    String? claimedBy,
    String? claimedAt,
  }) {
    return Message(
      msgId: msgId,
      content: content ?? this.content,
      decryptedContent: decryptedContent ?? this.decryptedContent,
      decryptionError: decryptionError ?? this.decryptionError,
      userLat: userLat,
      userLon: userLon,
      nodeLat: nodeLat,
      nodeLon: nodeLon,
      timestamp: timestamp,
      timeSource: timeSource,
      nodeId: nodeId,
      status: status ?? this.status,
      claimedBy: claimedBy ?? this.claimedBy,
      claimedAt: claimedAt ?? this.claimedAt,
      syncedFrom: syncedFrom,
      isEncrypted: isEncrypted,
      encryptionAlg: encryptionAlg,
      encryptionKid: encryptionKid,
      victimDeviceId: victimDeviceId,
    );
  }

  /// Check if the VICTIM's GPS position is present.
  bool get hasGpsLocation => userLat != null && userLon != null;

  /// Get shortened victim device ID for display (first 8 + last 4 chars)
  String get shortDeviceId {
    if (victimDeviceId.length <= 12) {
      return victimDeviceId.isEmpty ? 'N/A' : victimDeviceId;
    }
    return '${victimDeviceId.substring(0, 8)}...${victimDeviceId.substring(victimDeviceId.length - 4)}';
  }
}

class GSMessage {
  final String id;
  final String content;
  final String sender;

  /// ISO 8601 UTC string (schema v3).
  final String timestamp;
  final String nodeId;
  final double? locationLat;
  final double? locationLon;
  final double? locationAccuracy;

  GSMessage({
    required this.id,
    required this.content,
    required this.sender,
    required this.timestamp,
    required this.nodeId,
    this.locationLat,
    this.locationLon,
    this.locationAccuracy,
  });

  factory GSMessage.fromShared(shared.GsMessage m) => GSMessage(
        id: m.id,
        content: m.content,
        sender: m.sender,
        timestamp: m.timestamp,
        nodeId: m.nodeId,
        locationLat: m.locationLat,
        locationLon: m.locationLon,
        locationAccuracy: m.locationAccuracy,
      );

  bool get hasGpsLocation => locationLat != null && locationLon != null;

  String get shortCoords {
    if (!hasGpsLocation) return 'N/A';
    return '${locationLat!.toStringAsFixed(4)}, ${locationLon!.toStringAsFixed(4)}';
  }

  String get displayTime {
    final parsed = DateTime.tryParse(timestamp);
    if (parsed == null) {
      return timestamp;
    }
    return DateFormat('HH:mm:ss').format(parsed.toLocal());
  }
}
