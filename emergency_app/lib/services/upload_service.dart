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

  /// Probe the drone by fetching /health on the victim gateway. Returns
  /// the node_id when reachable, else null. (The health endpoint is public
  /// and served on 8443, but from the AP a plain probe of the portal is
  /// enough to know we are connected; we try health over http first.)
  Future<bool> isOnDrone() async {
    final client = shared.RescueMeshClient(baseUrl: kDroneBaseUrl);
    try {
      // The victim plane is HTTP; a successful GET of the portal root
      // means we are on a drone AP.
      await client.getHealth();
      return true;
    } on shared.ApiException {
      // A structured API error still means the node answered.
      return true;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

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
