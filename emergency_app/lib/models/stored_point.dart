/// A single locally-stored location point (file 06 data design). Nothing
/// leaves the phone until the user is at a drone or presses SOS.
library;

class StoredPoint {
  final double lat;
  final double lon;
  final double? accuracy;

  /// ISO 8601 UTC.
  final String recordedAt;

  /// Set locally once this point has been uploaded to a drone, so the
  /// "Your data" screen can show what has and has not left the phone.
  final bool uploaded;

  const StoredPoint({
    required this.lat,
    required this.lon,
    this.accuracy,
    required this.recordedAt,
    this.uploaded = false,
  });

  StoredPoint copyWith({bool? uploaded}) => StoredPoint(
        lat: lat,
        lon: lon,
        accuracy: accuracy,
        recordedAt: recordedAt,
        uploaded: uploaded ?? this.uploaded,
      );

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lon': lon,
        'accuracy': accuracy,
        'recorded_at': recordedAt,
        'uploaded': uploaded,
      };

  factory StoredPoint.fromJson(Map<String, dynamic> json) => StoredPoint(
        lat: (json['lat'] as num).toDouble(),
        lon: (json['lon'] as num).toDouble(),
        accuracy: json['accuracy'] == null
            ? null
            : (json['accuracy'] as num).toDouble(),
        recordedAt: json['recorded_at'] as String,
        uploaded: json['uploaded'] as bool? ?? false,
      );

  /// The shape POST /checkin expects for each point (file 02).
  Map<String, dynamic> toCheckinPoint() => {
        'lat': lat,
        'lon': lon,
        'accuracy': accuracy,
        'recorded_at': recordedAt,
      };
}
