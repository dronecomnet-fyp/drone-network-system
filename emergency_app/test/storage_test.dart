import 'package:emergency_app/constants.dart';
import 'package:emergency_app/models/stored_point.dart';
import 'package:emergency_app/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

StoredPoint _pt(int hour) => StoredPoint(
      lat: 6.9 + hour * 0.001,
      lon: 79.8,
      accuracy: 10,
      recordedAt: '2026-07-12T${hour.toString().padLeft(2, '0')}:00:00Z',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('device_id is generated once and stable', () async {
    final s = StorageService();
    final id1 = await s.deviceId();
    final id2 = await s.deviceId();
    expect(id1, isNotEmpty);
    expect(id1, id2);
  });

  test('appendPoint keeps the ring buffer at kMaxStoredPoints, oldest out',
      () async {
    final s = StorageService();
    for (var h = 0; h < kMaxStoredPoints + 5; h++) {
      await s.appendPoint(_pt(h));
    }
    final pts = await s.points();
    expect(pts.length, kMaxStoredPoints);
    // Oldest five dropped: first kept is hour 5.
    expect(pts.first.recordedAt, contains('05:00:00'));
    expect(pts.last.recordedAt,
        contains('${(kMaxStoredPoints + 4).toString().padLeft(2, '0')}:00:00'));
  });

  test('markUploaded flags only the matching points', () async {
    final s = StorageService();
    await s.appendPoint(_pt(1));
    await s.appendPoint(_pt(2));
    await s.markUploaded({'2026-07-12T01:00:00Z'});
    final pts = await s.points();
    expect(pts.firstWhere((p) => p.recordedAt.contains('01:00')).uploaded,
        isTrue);
    expect(pts.firstWhere((p) => p.recordedAt.contains('02:00')).uploaded,
        isFalse);
  });

  test('deleteAllData clears the log', () async {
    final s = StorageService();
    await s.appendPoint(_pt(1));
    await s.deleteAllData();
    expect(await s.points(), isEmpty);
  });

  test('toCheckinPoint has the shape POST /checkin expects', () {
    final json = _pt(3).toCheckinPoint();
    expect(json.keys,
        containsAll(['lat', 'lon', 'accuracy', 'recorded_at']));
    expect(json.containsKey('uploaded'), isFalse);
  });

  test('StoredPoint JSON round trip preserves uploaded flag', () {
    final p = _pt(4).copyWith(uploaded: true);
    final back = StoredPoint.fromJson(p.toJson());
    expect(back.uploaded, isTrue);
    expect(back.lat, p.lat);
    expect(back.recordedAt, p.recordedAt);
  });
}
