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

/// Which way current is flowing in a battery line.
///
/// Both battery channels on the aux module's INA3221 are BIDIRECTIONAL:
/// a pack that is being charged reads a negative current. The firmware
/// publishes the sign (positive discharging, negative charging, see
/// firmware/aux1/src/main.cpp) and the apps classify it here, so the rule
/// lives in exactly one place.
enum BatteryFlow { charging, discharging, idle, unknown }

/// Below this magnitude a reading is called idle rather than given a
/// direction. The INA3221 resolves 0.4 mA per count, so a resting line
/// jitters either side of zero; without a deadband the UI would flap
/// between "charging" and "discharging" on noise alone.
const double kBatteryIdleMa = 5.0;

BatteryFlow batteryFlowFor(double? ma) {
  if (ma == null) return BatteryFlow.unknown;
  if (ma.abs() < kBatteryIdleMa) return BatteryFlow.idle;
  return ma < 0 ? BatteryFlow.charging : BatteryFlow.discharging;
}

class BatteryState {
  final double? aV;
  final double? aMa;
  final double? bV;
  final double? bMa;

  const BatteryState({this.aV, this.aMa, this.bV, this.bMa});

  BatteryFlow get flowA => batteryFlowFor(aMa);
  BatteryFlow get flowB => batteryFlowFor(bMa);

  /// Current magnitude without the direction, for "120 mA" style display
  /// where the direction is already shown as a word or an icon.
  double? get aMaAbs => aMa?.abs();
  double? get bMaAbs => bMa?.abs();

  factory BatteryState.fromJson(Map<String, dynamic>? json) => json == null
      ? const BatteryState()
      : BatteryState(
          aV: _toDouble(json['a_v']),
          aMa: _toDouble(json['a_ma']),
          bV: _toDouble(json['b_v']),
          bMa: _toDouble(json['b_ma']),
        );
}

/// A node we are hearing on the mesh.
///
/// `lastSeen` is when its signed DTN beacon last arrived, so it answers "is
/// this node up". Everything below that comes from a different place: the
/// peer's own /health, fetched over the sync channel and stamped locally as
/// [healthTs]. The two ages are deliberately separate, because a node can be
/// beaconing right now while its cached position is minutes old, and the UI
/// must not imply otherwise. Older nodes send neither, so all of it is
/// nullable.
class PeerInfo {
  final String nodeId;
  final String ip;
  final String lastSeen;

  /// When WE last fetched this peer's health. Null if never reached.
  final String? healthTs;
  final double? lat;
  final double? lon;
  final int gpsFix;
  final double? batAV;
  final double? batAMa;
  final double? batBV;
  final double? batBMa;
  final int? uptimeS;
  final String? clockSource;

  const PeerInfo({
    required this.nodeId,
    required this.ip,
    required this.lastSeen,
    this.healthTs,
    this.lat,
    this.lon,
    this.gpsFix = 0,
    this.batAV,
    this.batAMa,
    this.batBV,
    this.batBMa,
    this.uptimeS,
    this.clockSource,
  });

  bool get hasLocation => lat != null && lon != null;
  bool get hasFix => gpsFix == 1 && hasLocation;

  /// True once we have any cached health at all for this peer.
  bool get hasHealth => healthTs != null && healthTs!.isNotEmpty;

  factory PeerInfo.fromJson(Map<String, dynamic> json) => PeerInfo(
        nodeId: (json['node_id'] ?? '') as String,
        ip: (json['ip'] ?? '') as String,
        lastSeen: (json['last_seen'] ?? '') as String,
        healthTs: json['health_ts'] as String?,
        lat: _toDouble(json['lat']),
        lon: _toDouble(json['lon']),
        gpsFix: _toInt(json['gps_fix']),
        batAV: _toDouble(json['bat_a_v']),
        batAMa: _toDouble(json['bat_a_ma']),
        batBV: _toDouble(json['bat_b_v']),
        batBMa: _toDouble(json['bat_b_ma']),
        uptimeS: json['uptime_s'] == null ? null : _toInt(json['uptime_s']),
        clockSource: json['clock_source'] as String?,
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
/// Which victim-portal config a node is serving.
///
/// The operator needs this BEFORE deploying: a fleet where one node still
/// shows stock options while the others show mission-specific ones is a
/// real and easy-to-miss state, so every node reports its own version and
/// the GCC shows it per node rather than assuming a push reached everyone.
class MissionConfigSummary {
  /// Hash of the option content this node is serving. There is no version
  /// counter on purpose: comparing ids answers the question the operator
  /// actually has ("does this node match what I have loaded?") exactly,
  /// rather than approximately via a number that some laptop has to keep
  /// correct.
  final String configId;

  /// "stock" when nobody ever pushed to this node, "pushed" otherwise.
  /// Stock is a valid working state, not a fault.
  final String source;
  final String missionName;
  final String disasterType;
  final String updatedAt;
  final int situationCount;

  const MissionConfigSummary({
    this.configId = 'stock',
    this.source = 'stock',
    this.missionName = '',
    this.disasterType = '',
    this.updatedAt = '',
    this.situationCount = 0,
  });

  bool get isStock => source != 'pushed';

  /// True when this node serves exactly the options [candidateId] describes.
  bool matches(String candidateId) =>
      !isStock && configId.isNotEmpty && configId == candidateId;

  factory MissionConfigSummary.fromJson(Map<String, dynamic>? json) =>
      json == null
          ? const MissionConfigSummary()
          : MissionConfigSummary(
              configId: (json['config_id'] ?? 'stock') as String,
              source: (json['source'] ?? 'stock') as String,
              missionName: (json['mission_name'] ?? '') as String,
              disasterType: (json['disaster_type'] ?? '') as String,
              updatedAt: (json['updated_at'] ?? '') as String,
              situationCount: _toInt(json['situation_count']),
            );
}

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
  final MissionConfigSummary missionConfig;

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
    this.missionConfig = const MissionConfigSummary(),
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
        missionConfig: MissionConfigSummary.fromJson(
            json['mission_config'] as Map<String, dynamic>?),
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
