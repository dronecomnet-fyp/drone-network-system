/// Data models mirroring backend schema v3 (backend/models.py, file 02).
/// Field names match the JSON the backend serves; keep the two in sync
/// via the contract test in test/client_live_test.dart.
library;

double? _toDouble(dynamic v) =>
    v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));

int _toInt(dynamic v, [int fallback = 0]) =>
    v == null ? fallback : (v is num ? v.toInt() : int.tryParse('$v') ?? fallback);

/// A victim/rescue message (schema v3: user vs node coordinates,
/// time_source, claimed_by).
class Message {
  final String msgId;
  final String content;
  final double? userLat;
  final double? userLon;
  final double? nodeLat;
  final double? nodeLon;
  final String timestamp;

  /// "gps" when the origin node clock was GPS-synced, "relative" when the
  /// timestamp is approximate (pre-fix boot). UIs show relative times with
  /// a "~" hint (file 05 task 5.3).
  final String timeSource;
  final String nodeId;
  final String status;
  final String claimedBy;
  final String claimedAt;
  final String syncedFrom;
  final bool isEncrypted;
  final String encryptionAlg;
  final String encryptionKid;
  final String victimDeviceId;

  const Message({
    required this.msgId,
    required this.content,
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

  bool get isClaimed => status == 'CLAIMED';
  bool get isRelativeTime => timeSource != 'gps';
  bool get hasUserLocation => userLat != null && userLon != null;

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        msgId: json['msg_id'] as String,
        content: (json['content'] ?? '') as String,
        userLat: _toDouble(json['user_lat']),
        userLon: _toDouble(json['user_lon']),
        nodeLat: _toDouble(json['node_lat']),
        nodeLon: _toDouble(json['node_lon']),
        timestamp: (json['timestamp'] ?? '') as String,
        timeSource: (json['time_source'] ?? 'relative') as String,
        nodeId: (json['node_id'] ?? '') as String,
        status: (json['status'] ?? 'NEW') as String,
        claimedBy: (json['claimed_by'] ?? '') as String,
        claimedAt: (json['claimed_at'] ?? '') as String,
        syncedFrom: (json['synced_from'] ?? '') as String,
        isEncrypted: _toInt(json['is_encrypted']) == 1,
        encryptionAlg: (json['encryption_alg'] ?? '') as String,
        encryptionKid: (json['encryption_kid'] ?? '') as String,
        victimDeviceId: (json['victim_device_id'] ?? '') as String,
      );
}

/// A field report filed by rescue personnel (gs_messages table; now
/// replicated fleet-wide, CHANGES.md item 9).
class GsMessage {
  final String id;
  final String content;
  final String sender;
  final String timestamp;
  final String nodeId;
  final double? locationLat;
  final double? locationLon;
  final double? locationAccuracy;

  const GsMessage({
    required this.id,
    required this.content,
    required this.sender,
    required this.timestamp,
    required this.nodeId,
    this.locationLat,
    this.locationLon,
    this.locationAccuracy,
  });

  bool get hasLocation => locationLat != null && locationLon != null;

  factory GsMessage.fromJson(Map<String, dynamic> json) => GsMessage(
        id: json['id'] as String,
        content: (json['content'] ?? '') as String,
        sender: (json['sender'] ?? '') as String,
        timestamp: (json['timestamp'] ?? '') as String,
        nodeId: (json['node_id'] ?? '') as String,
        locationLat: _toDouble(json['location_lat']),
        locationLon: _toDouble(json['location_lon']),
        locationAccuracy: _toDouble(json['location_accuracy']),
      );
}

class Announcement {
  final String id;
  final String title;
  final String body;
  final String priority; // LOW | NORMAL | HIGH | URGENT
  final String createdBy;
  final String createdAt;

  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.priority,
    required this.createdBy,
    required this.createdAt,
  });

  factory Announcement.fromJson(Map<String, dynamic> json) => Announcement(
        id: json['id'] as String,
        title: (json['title'] ?? '') as String,
        body: (json['body'] ?? '') as String,
        priority: (json['priority'] ?? 'NORMAL') as String,
        createdBy: (json['created_by'] ?? '') as String,
        createdAt: (json['created_at'] ?? '') as String,
      );
}

/// Personnel record as served by GET /personnel (no hash material).
class Personnel {
  final String personnelId;
  final String name;
  final String role; // RESCUE_TEAM | HQ
  final String issuedAt;
  final String expiresAt;
  final String status; // ACTIVE | REVOKED
  final String updatedAt;

  const Personnel({
    required this.personnelId,
    required this.name,
    required this.role,
    required this.issuedAt,
    required this.expiresAt,
    required this.status,
    required this.updatedAt,
  });

  bool get isActive => status == 'ACTIVE';

  factory Personnel.fromJson(Map<String, dynamic> json) => Personnel(
        personnelId: json['personnel_id'] as String,
        name: (json['name'] ?? '') as String,
        role: (json['role'] ?? 'RESCUE_TEAM') as String,
        issuedAt: (json['issued_at'] ?? '') as String,
        expiresAt: (json['expires_at'] ?? '') as String,
        status: (json['status'] ?? 'ACTIVE') as String,
        updatedAt: (json['updated_at'] ?? '') as String,
      );
}

/// POST /personnel response; [pin] is shown ONCE and never stored
/// (file 02 task 2.4).
class IssuedPersonnel {
  final String personnelId;
  final String name;
  final String role;
  final String expiresAt;
  final String pin;

  const IssuedPersonnel({
    required this.personnelId,
    required this.name,
    required this.role,
    required this.expiresAt,
    required this.pin,
  });

  factory IssuedPersonnel.fromJson(Map<String, dynamic> json) => IssuedPersonnel(
        personnelId: json['personnel_id'] as String,
        name: (json['name'] ?? '') as String,
        role: (json['role'] ?? 'RESCUE_TEAM') as String,
        expiresAt: (json['expires_at'] ?? '') as String,
        pin: json['pin'] as String,
      );
}

/// Emergency-app checkin point (checkins table).
class Checkin {
  final String id;
  final String deviceId;
  final double? lat;
  final double? lon;
  final double? accuracy;
  final String recordedAt;
  final String uploadedAt;
  final String nodeId;
  final bool sos;

  const Checkin({
    required this.id,
    required this.deviceId,
    this.lat,
    this.lon,
    this.accuracy,
    required this.recordedAt,
    required this.uploadedAt,
    required this.nodeId,
    required this.sos,
  });

  factory Checkin.fromJson(Map<String, dynamic> json) => Checkin(
        id: json['id'] as String,
        deviceId: (json['device_id'] ?? '') as String,
        lat: _toDouble(json['lat']),
        lon: _toDouble(json['lon']),
        accuracy: _toDouble(json['accuracy']),
        recordedAt: (json['recorded_at'] ?? '') as String,
        uploadedAt: (json['uploaded_at'] ?? '') as String,
        nodeId: (json['node_id'] ?? '') as String,
        sos: _toInt(json['sos']) == 1,
      );
}

class GpsState {
  final double? lat;
  final double? lon;
  final int fix;
  final int sats;
  final double? hdop;

  const GpsState({this.lat, this.lon, this.fix = 0, this.sats = 0, this.hdop});

  bool get hasFix => fix == 1 && lat != null && lon != null;

  factory GpsState.fromJson(Map<String, dynamic>? json) => json == null
      ? const GpsState()
      : GpsState(
          lat: _toDouble(json['lat']),
          lon: _toDouble(json['lon']),
          fix: _toInt(json['fix']),
          sats: _toInt(json['sats']),
          hdop: _toDouble(json['hdop']),
        );
}

class BatteryState {
  final double? aV;
  final double? aMa;
  final double? bV;
  final double? bMa;

  const BatteryState({this.aV, this.aMa, this.bV, this.bMa});

  factory BatteryState.fromJson(Map<String, dynamic>? json) => json == null
      ? const BatteryState()
      : BatteryState(
          aV: _toDouble(json['a_v']),
          aMa: _toDouble(json['a_ma']),
          bV: _toDouble(json['b_v']),
          bMa: _toDouble(json['b_ma']),
        );
}

class PeerInfo {
  final String nodeId;
  final String ip;
  final String lastSeen;

  const PeerInfo({required this.nodeId, required this.ip, required this.lastSeen});

  factory PeerInfo.fromJson(Map<String, dynamic> json) => PeerInfo(
        nodeId: (json['node_id'] ?? '') as String,
        ip: (json['ip'] ?? '') as String,
        lastSeen: (json['last_seen'] ?? '') as String,
      );
}

class DegradedNode {
  final String nodeId;
  final String ts;
  final double? lat;
  final double? lon;
  final double? batAV;
  final double? batBV;

  const DegradedNode({
    required this.nodeId,
    required this.ts,
    this.lat,
    this.lon,
    this.batAV,
    this.batBV,
  });

  factory DegradedNode.fromJson(Map<String, dynamic> json) => DegradedNode(
        nodeId: (json['node_id'] ?? '') as String,
        ts: (json['ts'] ?? '') as String,
        lat: _toDouble(json['lat']),
        lon: _toDouble(json['lon']),
        batAV: _toDouble(json['bat_a_v']),
        batBV: _toDouble(json['bat_b_v']),
      );
}

/// GET /health payload (file 02 task 2.5). The GCC Nodes screen renders
/// this per node with a last-updated age, never pretending remote nodes
/// are live (file 04 connectivity model).
class NodeHealth {
  final String nodeId;
  final String aux; // "present" | "absent"
  final GpsState gps;
  final BatteryState battery;
  final int uptimeS;
  final String clockSource;
  final Map<String, int> messageCounts;
  final Map<String, int> tableCounts;
  final List<PeerInfo> peers;
  final List<DegradedNode> degradedNodes;

  const NodeHealth({
    required this.nodeId,
    required this.aux,
    required this.gps,
    required this.battery,
    required this.uptimeS,
    required this.clockSource,
    required this.messageCounts,
    required this.tableCounts,
    required this.peers,
    required this.degradedNodes,
  });

  factory NodeHealth.fromJson(Map<String, dynamic> json) => NodeHealth(
        nodeId: (json['node_id'] ?? '') as String,
        aux: (json['aux'] ?? 'absent') as String,
        gps: GpsState.fromJson(json['gps'] as Map<String, dynamic>?),
        battery: BatteryState.fromJson(json['battery'] as Map<String, dynamic>?),
        uptimeS: _toInt(json['uptime_s']),
        clockSource: (json['clock_source'] ?? 'relative') as String,
        messageCounts: (json['message_counts'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, _toInt(v))),
        tableCounts: (json['table_counts'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, _toInt(v))),
        peers: (json['peers'] as List<dynamic>? ?? [])
            .map((p) => PeerInfo.fromJson(p as Map<String, dynamic>))
            .toList(),
        degradedNodes: (json['degraded_nodes'] as List<dynamic>? ?? [])
            .map((d) => DegradedNode.fromJson(d as Map<String, dynamic>))
            .toList(),
      );
}

/// POST /auth/login response.
class AuthSession {
  final String token;
  final int expiresAt; // epoch seconds
  final String personnelId;
  final String role;
  final String name;

  const AuthSession({
    required this.token,
    required this.expiresAt,
    required this.personnelId,
    required this.role,
    required this.name,
  });

  bool get isExpired =>
      DateTime.now().millisecondsSinceEpoch ~/ 1000 >= expiresAt;

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        token: json['token'] as String,
        expiresAt: _toInt(json['expires_at']),
        personnelId: (json['personnel_id'] ?? '') as String,
        role: (json['role'] ?? 'RESCUE_TEAM') as String,
        name: (json['name'] ?? '') as String,
      );

  Map<String, dynamic> toJson() => {
        'token': token,
        'expires_at': expiresAt,
        'personnel_id': personnelId,
        'role': role,
        'name': name,
      };

  factory AuthSession.fromStoredJson(Map<String, dynamic> json) =>
      AuthSession.fromJson(json);
}

/// A rescuer's last known location (M7d). Latest-per-personnel: the GCC
/// shows one marker per rescuer, as fresh as the heartbeat plus DTN sync.
class PersonnelLocation {
  final String personnelId;
  final double? lat;
  final double? lon;
  final double? accuracyM;
  final int? batteryPct;
  final String recordedAt;
  final String nodeId;
  final String updatedAt;

  const PersonnelLocation({
    required this.personnelId,
    this.lat,
    this.lon,
    this.accuracyM,
    this.batteryPct,
    required this.recordedAt,
    required this.nodeId,
    required this.updatedAt,
  });

  bool get hasLocation => lat != null && lon != null;

  factory PersonnelLocation.fromJson(Map<String, dynamic> json) =>
      PersonnelLocation(
        personnelId: (json['personnel_id'] ?? '') as String,
        lat: _toDouble(json['lat']),
        lon: _toDouble(json['lon']),
        accuracyM: _toDouble(json['accuracy_m']),
        batteryPct:
            json['battery_pct'] == null ? null : _toInt(json['battery_pct']),
        recordedAt: (json['recorded_at'] ?? '') as String,
        nodeId: (json['node_id'] ?? '') as String,
        updatedAt: (json['updated_at'] ?? '') as String,
      );
}
