/// Small pure-Dart geometry helpers shared by the planner, the fleet
/// manager, and the AI advisor validator. No dependencies, so they are
/// trivially unit-testable with no Flutter or network.
library;

import 'dart:math' as math;

/// Great-circle distance in metres (haversine). Source: standard
/// haversine formula, Earth radius 6371000 m. Confidence: High.
double haversineM(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  final dLat = _rad(lat2 - lat1);
  final dLon = _rad(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_rad(lat1)) *
          math.cos(_rad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _rad(double deg) => deg * math.pi / 180.0;

/// Ray-casting point-in-polygon. [polygon] is a list of [lat, lon] pairs
/// (a lat/lon degree plane is fine at operation scale). Returns false for
/// a degenerate polygon (< 3 vertices). Confidence: High.
bool pointInPolygon(double lat, double lon, List<List<double>> polygon) {
  if (polygon.length < 3) return false;
  var inside = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final yi = polygon[i][0], xi = polygon[i][1];
    final yj = polygon[j][0], xj = polygon[j][1];
    final intersect = ((yi > lat) != (yj > lat)) &&
        (lon < (xj - xi) * (lat - yi) / (yj - yi) + xi);
    if (intersect) inside = !inside;
  }
  return inside;
}
