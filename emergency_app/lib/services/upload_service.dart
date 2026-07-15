/// UploadService: once the phone is on a drone AP, push stored points and
/// optional SOS to the victim plane (file 06 connected flow). Uses the
/// shared RescueMeshClient against the PUBLIC HTTP endpoint (port 80, no
/// auth, no TLS: file 09 F3), the same contract the GCC and rescue app
/// use elsewhere.
library;

import 'package:rescue_mesh_shared/rescue_mesh_shared.dart' as shared;

import '../constants.dart';
import 'storage_service.dart';

class UploadResult {
  final int stored;
  final String? sosMsgId;

  const UploadResult({required this.stored, this.sosMsgId});
}

class UploadService {
  final StorageService storage;

  UploadService(this.storage);

  /// The node we are connected to (e.g. "DRONE_A"), or null if the phone is
  /// not on a rescue drone AP. Uses the victim plane's JSON probe (/probe on
  /// port 80). NOTE: do NOT probe /health here: that only exists on the
  /// authenticated plane (8443), so on port 80 the catch-all returns the
  /// portal HTML, JSON parsing fails, and the app wrongly concludes it is
  /// not connected (which disabled SOS entirely).
  Future<String?> connectedNodeId() async {
    // Short timeout: this runs on a 4 s connectivity poll, and when NOT on a
    // drone the probe should fail fast rather than hang for the default 8 s.
    final client = shared.RescueMeshClient(
        baseUrl: kDroneBaseUrl, timeout: const Duration(seconds: 3));
    try {
      final nodeId = await client.probeDrone();
      return (nodeId != null && nodeId.isNotEmpty) ? nodeId : null;
    } finally {
      client.close();
    }
  }

  Future<bool> isOnDrone() async => (await connectedNodeId()) != null;

  /// Upload all not-yet-uploaded points, optionally with an SOS. Marks the
  /// uploaded points locally on success (file 06). [sosText] is ignored
  /// unless [sos] is true.
  Future<UploadResult> upload({bool sos = false, String sosText = ''}) async {
    final deviceId = await storage.deviceId();
    final allPoints = await storage.points();
    final pending = sos
        ? allPoints // an SOS uploads everything for context
        : allPoints.where((p) => !p.uploaded).toList();

    final client = shared.RescueMeshClient(baseUrl: kDroneBaseUrl);
    try {
      final result = await client.postCheckin(
        deviceId: deviceId,
        points: pending.map((p) => p.toCheckinPoint()).toList(),
        sos: sos,
        sosText: sosText,
      );
      await storage
          .markUploaded(pending.map((p) => p.recordedAt).toSet());
      return UploadResult(
        stored: (result['stored'] as num?)?.toInt() ?? pending.length,
        sosMsgId: result['sos_msg_id'] as String?,
      );
    } finally {
      client.close();
    }
  }
}
