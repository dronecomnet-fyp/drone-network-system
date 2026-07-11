/// Operation planning (file 04 screen 1, PLANNING mode): named advisory
/// markers with coverage circles, saved/loaded as a local JSON file.
/// Markers do NOT command any drone; they are a shared visual plan only.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class PlanMarker {
  String name;
  double lat;
  double lon;
  double radiusM;

  PlanMarker({
    required this.name,
    required this.lat,
    required this.lon,
    required this.radiusM,
  });

  Map<String, dynamic> toJson() =>
      {'name': name, 'lat': lat, 'lon': lon, 'radius_m': radiusM};

  factory PlanMarker.fromJson(Map<String, dynamic> json) => PlanMarker(
        name: (json['name'] ?? '') as String,
        lat: (json['lat'] as num).toDouble(),
        lon: (json['lon'] as num).toDouble(),
        radiusM: (json['radius_m'] as num? ?? 300).toDouble(),
      );
}

class PlanState extends ChangeNotifier {
  String planName = 'unnamed operation';
  final List<PlanMarker> markers = [];
  bool planningMode = false;
  String? loadedFrom;

  void togglePlanning() {
    planningMode = !planningMode;
    notifyListeners();
  }

  void addMarker(PlanMarker m) {
    markers.add(m);
    notifyListeners();
  }

  void removeMarker(PlanMarker m) {
    markers.remove(m);
    notifyListeners();
  }

  void clear() {
    markers.clear();
    loadedFrom = null;
    notifyListeners();
  }

  String toJsonString() => const JsonEncoder.withIndent('  ').convert({
        'plan_name': planName,
        'saved_at': DateTime.now().toUtc().toIso8601String(),
        'markers': markers.map((m) => m.toJson()).toList(),
      });

  void loadFromJsonString(String jsonString) {
    final data = jsonDecode(jsonString) as Map<String, dynamic>;
    planName = (data['plan_name'] ?? 'unnamed operation') as String;
    markers
      ..clear()
      ..addAll((data['markers'] as List<dynamic>? ?? [])
          .map((m) => PlanMarker.fromJson(m as Map<String, dynamic>)));
    notifyListeners();
  }

  Future<String?> saveToFile(String path) async {
    try {
      await File(path).writeAsString(toJsonString());
      loadedFrom = path;
      notifyListeners();
      return null;
    } on FileSystemException catch (e) {
      return 'Save failed: ${e.message}';
    }
  }

  Future<String?> loadFromFile(String path) async {
    try {
      loadFromJsonString(await File(path).readAsString());
      loadedFrom = path;
      notifyListeners();
      return null;
    } on FileSystemException catch (e) {
      return 'Load failed: ${e.message}';
    } on FormatException catch (e) {
      return 'Not a valid plan file: ${e.message}';
    }
  }
}
