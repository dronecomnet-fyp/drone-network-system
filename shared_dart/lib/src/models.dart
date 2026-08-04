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

  /// One-scan sign-in code for the rescue app: the signed record plus the
  /// PIN. Carries the PIN deliberately, which is only defensible because
  /// credentials are scoped to a mission (CHANGES.md item 41).
  final String signinCode;

  const IssuedPersonnel({
    required this.personnelId,
    required this.name,
    required this.role,
    required this.expiresAt,
    required this.pin,
    this.signinCode = '',
  });

  factory IssuedPersonnel.fromJson(Map<String, dynamic> json) => IssuedPersonnel(
        personnelId: json['personnel_id'] as String,
        name: (json['name'] ?? '') as String,
        role: (json['role'] ?? 'RESCUE_TEAM') as String,
        expiresAt: (json['expires_at'] ?? '') as String,
        pin: json['pin'] as String,
        signinCode: (json['signin_code'] ?? '') as String,
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

  /// Which mission this node is running. Credentials are scoped to it, so a
  /// node on a different mission will reject rescuers holding credentials
  /// from another one.
  final String missionId;

  /// "stock" when nobody ever pushed to this node, "pushed" otherwise.
  /// Stock is a valid working state, not a fault.
  final String source;
  final String missionName;
  final String disasterType;
  final String updatedAt;
  final int situationCount;

  const MissionConfigSummary({
    this.configId = 'stock',
    this.missionId = '',
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
              missionId: (json['mission_id'] ?? '') as String,
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

/// How far one of a victim's own messages has actually got.
///
/// Modelled on the tick idiom people already know, with one state the
/// familiar apps do not have. Their ticks imply seconds; this network is
/// delay tolerant and a message can genuinely sit for hours waiting for a
/// drone to come back overhead. Without [waiting] as a distinct, visible
/// state, a victim with no drone in range sees nothing happening and
/// concludes they were ignored, when the system is working as designed.
enum DeliveryState {
  /// On the phone. No drone in range yet, so nobody has it.
  waiting,

  /// Stored and signed on a drone. It exists outside the victim's phone.
  onDrone,

  /// A rescuer has claimed it. Someone has actually read it.
  ///
  /// This must never be presented as "help is coming": claiming means
  /// seen, not dispatched, and a victim who stops seeking other help
  /// because of a tick would be badly served.
  seen,
}

/// One entry in a victim's own conversation: either something they sent or
/// something the rescue team replied.
class ConversationEntry {
  final String id;
  final String body;
  final String at;

  /// True when the victim wrote it, false when the rescue team did.
  final bool fromVictim;

  /// Only meaningful for victim messages.
  final DeliveryState state;

  /// Who replied, for rescue entries.
  final String sender;
  final double? lat;
  final double? lon;

  const ConversationEntry({
    required this.id,
    required this.body,
    required this.at,
    required this.fromVictim,
    this.state = DeliveryState.onDrone,
    this.sender = '',
    this.lat,
    this.lon,
  });

  bool get hasLocation => lat != null && lon != null;
}

/// A victim's whole thread, oldest first, ready to render as a chat.
class Conversation {
  final List<ConversationEntry> entries;

  const Conversation(this.entries);

  bool get isEmpty => entries.isEmpty;

  /// Newest state among the victim's own messages, for a summary line.
  DeliveryState? get latestOwnState {
    for (final e in entries.reversed) {
      if (e.fromVictim) return e.state;
    }
    return null;
  }

  factory Conversation.fromJson(Map<String, dynamic> json) {
    final out = <ConversationEntry>[];
    for (final m in (json['messages'] as List<dynamic>? ?? [])) {
      final row = m as Map<String, dynamic>;
      out.add(ConversationEntry(
        id: (row['msg_id'] ?? '') as String,
        body: (row['content'] ?? '') as String,
        at: (row['timestamp'] ?? '') as String,
        fromVictim: true,
        // Anything the node can tell us about is at least on a drone; the
        // waiting state is tracked by the phone, not the node.
        state: (row['status'] ?? 'NEW') == 'CLAIMED'
            ? DeliveryState.seen
            : DeliveryState.onDrone,
        lat: _toDouble(row['user_lat']),
        lon: _toDouble(row['user_lon']),
      ));
    }
    for (final r in (json['replies'] as List<dynamic>? ?? [])) {
      final row = r as Map<String, dynamic>;
      out.add(ConversationEntry(
        id: (row['id'] ?? '') as String,
        body: (row['body'] ?? '') as String,
        at: (row['created_at'] ?? '') as String,
        fromVictim: false,
        sender: (row['sender'] ?? 'Rescue team') as String,
      ));
    }
    out.sort((a, b) => a.at.compareTo(b.at));
    return Conversation(out);
  }
}

/// One tappable option in the victim-facing portal and app.
class PortalSituation {
  const PortalSituation(
      {required this.id, required this.label, required this.urgent});

  final String id;
  final String label;

  /// Urgent options sort first and are flagged to the rescue team. Someone
  /// skimming in an emergency reads the top of a list and may never reach
  /// the bottom, so this is ordering information, not decoration.
  final bool urgent;

  factory PortalSituation.fromJson(Map<String, dynamic> j) => PortalSituation(
        id: (j['id'] ?? '') as String,
        label: (j['label'] ?? '') as String,
        urgent: j['urgent'] == true,
      );
}

/// What one node is currently offering victims.
class PortalOptions {
  const PortalOptions(
      {required this.configId,
      required this.headline,
      required this.situations});

  /// Fingerprint of the content, so the app can tell whether a node is on
  /// stock options or on what the operator pushed for this mission.
  final String configId;
  final String headline;
  final List<PortalSituation> situations;

  factory PortalOptions.fromJson(Map<String, dynamic> j) => PortalOptions(
        configId: (j['config_id'] ?? 'stock') as String,
        headline: (j['headline'] ?? '') as String,
        situations: ((j['situations'] as List?) ?? const [])
            .map((e) => PortalSituation.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  /// What ships in the app, matching backend STOCK_CONFIG. Used when the
  /// node cannot be asked, so the victim always has something to tap.
  static const PortalOptions stock = PortalOptions(
    configId: 'stock',
    headline: 'Tap what you need. You can tap more than one.',
    situations: [
      PortalSituation(
          id: 'trapped',
          label: 'I am trapped and cannot get out',
          urgent: true),
      PortalSituation(
          id: 'injured', label: 'Someone here is injured', urgent: true),
      PortalSituation(
          id: 'medical', label: 'I need medicine or a doctor', urgent: true),
      PortalSituation(
          id: 'water_food',
          label: 'I need drinking water or food',
          urgent: false),
      PortalSituation(
          id: 'shelter', label: 'I need shelter or evacuation', urgent: false),
      PortalSituation(
          id: 'safe',
          label: 'I am safe, reporting my location',
          urgent: false),
    ],
  );
}

/// One LoRa frame a node heard (field backlog #13).
///
/// `heardBy` matters as much as `aboutNode`: the same beacon picked up by
/// two nodes produces two of these, and two independent receptions are
/// better evidence that a drone is where it says it is than one.
class LoraEvent {
  const LoraEvent({
    required this.id,
    required this.kind,
    required this.aboutNode,
    required this.heardBy,
    required this.receivedAt,
    this.rssi,
    this.snr,
    this.lat,
    this.lon,
    this.gpsFix = false,
    this.batAV,
    this.batBV,
    this.lastMsg = '',
    this.raw = '',
  });

  final String id;

  /// "fallback" for a beacon from a node whose Pi died, "lora_rx" for
  /// anything else heard on the radio.
  final String kind;

  /// Empty for a frame we could not attribute to a node.
  final String aboutNode;
  final String heardBy;
  final String receivedAt;
  final double? rssi;
  final double? snr;
  final double? lat;
  final double? lon;
  final bool gpsFix;
  final double? batAV;
  final double? batBV;

  /// The last victim message that node was carrying when it went down.
  /// This is the payload the fallback beacon exists to rescue.
  final String lastMsg;
  final String raw;

  bool get isFallback => kind == 'fallback';
  bool get hasPosition => lat != null && lon != null && gpsFix;

  factory LoraEvent.fromJson(Map<String, dynamic> j) => LoraEvent(
        id: (j['id'] ?? '') as String,
        kind: (j['kind'] ?? '') as String,
        aboutNode: (j['about_node'] ?? '') as String,
        heardBy: (j['heard_by'] ?? '') as String,
        receivedAt: (j['received_at'] ?? '') as String,
        rssi: (j['rssi'] as num?)?.toDouble(),
        snr: (j['snr'] as num?)?.toDouble(),
        lat: (j['lat'] as num?)?.toDouble(),
        lon: (j['lon'] as num?)?.toDouble(),
        gpsFix: ((j['gps_fix'] as num?)?.toInt() ?? 0) == 1,
        batAV: (j['bat_a_v'] as num?)?.toDouble(),
        batBV: (j['bat_b_v'] as num?)?.toDouble(),
        lastMsg: (j['last_msg'] ?? '') as String,
        raw: (j['raw'] ?? '') as String,
      );
}
