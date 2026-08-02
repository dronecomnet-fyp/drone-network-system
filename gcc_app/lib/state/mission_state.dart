/// MissionState (M7b): the whole operation in one local JSON file.
///
/// Supersedes PlanState. A mission holds identity (name, disaster type,
/// challenges), the operation area polygon, the resource inventory
/// (personnel, drones, modules, spares), cached product specs fetched
/// from the product site while online, and named deployments (marker
/// sets). Everything is a plain local file: offline in the field the
/// operator can still edit all of it, including adding a volunteer's
/// drone with one of our modules attached.
///
/// Placements are ADVISORY markers (file 04 rule): activating a
/// deployment never commands a drone; M7f's fleet manager is the layer
/// that turns a placement into a deploy action.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Placement roles (coverage semantics drawn from product specs).
const kRoleUserAp = 'user_ap';
const kRoleMeshRelay = 'mesh_relay';
const kRoleSystemDrone = 'system_drone';
const kPlacementRoles = [kRoleUserAp, kRoleMeshRelay, kRoleSystemDrone];

class GeoPoint {
  final double lat;
  final double lon;

  const GeoPoint(this.lat, this.lon);

  Map<String, dynamic> toJson() => {'lat': lat, 'lon': lon};

  factory GeoPoint.fromJson(Map<String, dynamic> json) => GeoPoint(
      (json['lat'] as num).toDouble(), (json['lon'] as num).toDouble());
}

class DronePlacement {
  String name;
  double lat;
  double lon;
  String role;
  double radiusM;
  String rationale;

  /// Set by the fleet manager (M7f) when a drone from the inventory is
  /// assigned to this placement; empty while unassigned.
  String assignedDrone;

  DronePlacement({
    required this.name,
    required this.lat,
    required this.lon,
    this.role = kRoleUserAp,
    required this.radiusM,
    this.rationale = '',
    this.assignedDrone = '',
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'lat': lat,
        'lon': lon,
        'role': role,
        'radius_m': radiusM,
        if (rationale.isNotEmpty) 'rationale': rationale,
        if (assignedDrone.isNotEmpty) 'assigned_drone': assignedDrone,
      };

  factory DronePlacement.fromJson(Map<String, dynamic> json) => DronePlacement(
        name: (json['name'] ?? 'position') as String,
        lat: (json['lat'] as num).toDouble(),
        lon: (json['lon'] as num).toDouble(),
        role: kPlacementRoles.contains(json['role'])
            ? json['role'] as String
            : kRoleUserAp,
        radiusM: (json['radius_m'] as num? ?? 300).toDouble(),
        rationale: (json['rationale'] ?? '') as String,
        assignedDrone: (json['assigned_drone'] ?? '') as String,
      );
}

class Deployment {
  String name;
  String source; // "manual" | "ai"
  bool approved;
  final List<DronePlacement> placements;

  Deployment({
    required this.name,
    this.source = 'manual',
    this.approved = false,
    List<DronePlacement>? placements,
  }) : placements = placements ?? [];

  Map<String, dynamic> toJson() => {
        'name': name,
        'source': source,
        'approved': approved,
        'placements': placements.map((p) => p.toJson()).toList(),
      };

  factory Deployment.fromJson(Map<String, dynamic> json) => Deployment(
        name: (json['name'] ?? 'deployment') as String,
        source: (json['source'] ?? 'manual') as String,
        approved: (json['approved'] ?? false) as bool,
        placements: (json['placements'] as List<dynamic>? ?? [])
            .map((p) => DronePlacement.fromJson(p as Map<String, dynamic>))
            .toList(),
      );
}

/// A drone in the inventory. Three entry paths (all editable any time,
/// including offline in the field):
///  - our brand: unitId set, specs fetched/cached by that ID
///  - volunteer: no unitId; owner + makeModel + one of OUR modules
///    attached, so comm specs resolve via the module's unit ID
///  - minimal: just a label, specs unknown
class DroneResource {
  String label;
  String unitId; // empty for volunteer/minimal
  String makeModel;
  String owner;
  String attachedModuleId; // ModuleResource.unitId, empty if none
  String source; // "brand" | "volunteer"

  DroneResource({
    required this.label,
    this.unitId = '',
    this.makeModel = '',
    this.owner = '',
    this.attachedModuleId = '',
    this.source = 'brand',
  });

  Map<String, dynamic> toJson() => {
        'label': label,
        if (unitId.isNotEmpty) 'unit_id': unitId,
        if (makeModel.isNotEmpty) 'make_model': makeModel,
        if (owner.isNotEmpty) 'owner': owner,
        if (attachedModuleId.isNotEmpty) 'attached_module_id': attachedModuleId,
        'source': source,
      };

  factory DroneResource.fromJson(Map<String, dynamic> json) => DroneResource(
        label: (json['label'] ?? 'drone') as String,
        unitId: (json['unit_id'] ?? '') as String,
        makeModel: (json['make_model'] ?? '') as String,
        owner: (json['owner'] ?? '') as String,
        attachedModuleId: (json['attached_module_id'] ?? '') as String,
        source: (json['source'] ?? 'brand') as String,
      );
}

class ModuleResource {
  String unitId;
  String label;
  String attachedTo; // DroneResource.label, empty = spare stock

  ModuleResource({required this.unitId, required this.label, this.attachedTo = ''});

  Map<String, dynamic> toJson() => {
        'unit_id': unitId,
        'label': label,
        if (attachedTo.isNotEmpty) 'attached_to': attachedTo,
      };

  factory ModuleResource.fromJson(Map<String, dynamic> json) => ModuleResource(
        unitId: (json['unit_id'] ?? '') as String,
        label: (json['label'] ?? 'module') as String,
        attachedTo: (json['attached_to'] ?? '') as String,
      );
}

/// Cached product knowledge for one unit ID: fetched from the product
/// site while online, or entered manually ("manual" source) so the field
/// stays fully offline-capable.
class ProductInfo {
  final String modelNo;
  final String name;
  final Map<String, dynamic> specs;
  final String fetchedAt;
  final String source; // "site" | "manual"

  const ProductInfo({
    required this.modelNo,
    required this.name,
    required this.specs,
    required this.fetchedAt,
    this.source = 'site',
  });

  double? get apRangeM => (specs['ap_range_m'] as num?)?.toDouble();
  double? get meshRangeM => (specs['mesh_range_m'] as num?)?.toDouble();
  double? get batteryWh => (specs['battery_wh'] as num?)?.toDouble();

  Map<String, dynamic> toJson() => {
        'model_no': modelNo,
        'name': name,
        'specs': specs,
        'fetched_at': fetchedAt,
        'source': source,
      };

  factory ProductInfo.fromJson(Map<String, dynamic> json) => ProductInfo(
        modelNo: (json['model_no'] ?? '') as String,
        name: (json['name'] ?? '') as String,
        specs: (json['specs'] as Map<String, dynamic>? ?? {}),
        fetchedAt: (json['fetched_at'] ?? '') as String,
        source: (json['source'] ?? 'site') as String,
      );
}

class MissionState extends ChangeNotifier {
  String missionName = 'unnamed mission';
  String disasterType = 'flood';
  String createdAt = DateTime.now().toUtc().toIso8601String();
  final List<String> challenges = [];
  final List<GeoPoint> area = [];

  int personnelCount = 0;
  int spareBatteries = 0;
  final List<DroneResource> drones = [];
  final List<ModuleResource> modules = [];
  final Map<String, ProductInfo> productCache = {};

  final List<Deployment> deployments = [];
  String activeDeploymentName = '';

  // UI modes (not serialized).
  bool planningMode = false;
  bool areaDrawMode = false;
  String? loadedFrom;

  Deployment? get activeDeployment {
    for (final d in deployments) {
      if (d.name == activeDeploymentName) return d;
    }
    return null;
  }

  // ---- mission identity ----

  void setMissionInfo({String? name, String? type}) {
    if (name != null && name.trim().isNotEmpty) missionName = name.trim();
    if (type != null) disasterType = type;
    notifyListeners();
  }

  void addChallenge(String c) {
    final t = c.trim();
    if (t.isEmpty || challenges.contains(t)) return;
    challenges.add(t);
    notifyListeners();
  }

  void removeChallenge(String c) {
    challenges.remove(c);
    notifyListeners();
  }

  // ---- area polygon ----

  void togglePlanning() {
    planningMode = !planningMode;
    if (!planningMode) areaDrawMode = false;
    notifyListeners();
  }

  void toggleAreaDraw() {
    areaDrawMode = !areaDrawMode;
    notifyListeners();
  }

  void addAreaVertex(double lat, double lon) {
    area.add(GeoPoint(lat, lon));
    notifyListeners();
  }

  void undoAreaVertex() {
    if (area.isNotEmpty) area.removeLast();
    notifyListeners();
  }

  void clearArea() {
    area.clear();
    notifyListeners();
  }

  // ---- resources ----

  void setCounts({int? personnel, int? batteries}) {
    if (personnel != null && personnel >= 0) personnelCount = personnel;
    if (batteries != null && batteries >= 0) spareBatteries = batteries;
    notifyListeners();
  }

  String? addDrone(DroneResource d) {
    if (d.label.trim().isEmpty) return 'Drone needs a label';
    if (drones.any((x) => x.label == d.label)) {
      return 'A drone named "${d.label}" already exists';
    }
    if (d.attachedModuleId.isNotEmpty) {
      final err = _attach(d.attachedModuleId, d.label);
      if (err != null) return err;
    }
    drones.add(d);
    notifyListeners();
    return null;
  }

  void removeDrone(DroneResource d) {
    for (final m in modules.where((m) => m.attachedTo == d.label)) {
      m.attachedTo = '';
    }
    drones.remove(d);
    notifyListeners();
  }

  String? addModule(ModuleResource m) {
    if (m.unitId.trim().isEmpty) return 'Module needs its unit ID';
    if (modules.any((x) => x.unitId == m.unitId)) {
      return 'Module ${m.unitId} is already listed';
    }
    modules.add(m);
    notifyListeners();
    return null;
  }

  void removeModule(ModuleResource m) {
    for (final d in drones.where((d) => d.attachedModuleId == m.unitId)) {
      d.attachedModuleId = '';
    }
    modules.remove(m);
    notifyListeners();
  }

  /// One module can only be on one drone at a time.
  String? _attach(String moduleUnitId, String droneLabel) {
    final matches = modules.where((m) => m.unitId == moduleUnitId).toList();
    if (matches.isEmpty) return 'No module $moduleUnitId in the inventory';
    final m = matches.first;
    if (m.attachedTo.isNotEmpty && m.attachedTo != droneLabel) {
      return 'Module $moduleUnitId is already on ${m.attachedTo}';
    }
    m.attachedTo = droneLabel;
    return null;
  }

  String? attachModule(DroneResource d, String moduleUnitId) {
    if (d.attachedModuleId == moduleUnitId) return null;
    if (moduleUnitId.isEmpty) {
      detachModule(d);
      return null;
    }
    final err = _attach(moduleUnitId, d.label);
    if (err != null) return err;
    if (d.attachedModuleId.isNotEmpty) {
      for (final m in modules.where((m) => m.unitId == d.attachedModuleId)) {
        m.attachedTo = '';
      }
    }
    d.attachedModuleId = moduleUnitId;
    notifyListeners();
    return null;
  }

  void detachModule(DroneResource d) {
    for (final m in modules.where((m) => m.unitId == d.attachedModuleId)) {
      m.attachedTo = '';
    }
    d.attachedModuleId = '';
    notifyListeners();
  }

  void cacheProduct(String unitId, ProductInfo info) {
    productCache[unitId] = info;
    notifyListeners();
  }

  /// Resolve a drone's product knowledge: its own unit ID first (our
  /// brand), else the attached module's unit ID (volunteer drone carrying
  /// our module), else null (specs unknown).
  ProductInfo? specsFor(DroneResource d) {
    if (d.unitId.isNotEmpty && productCache.containsKey(d.unitId)) {
      return productCache[d.unitId];
    }
    if (d.attachedModuleId.isNotEmpty &&
        productCache.containsKey(d.attachedModuleId)) {
      return productCache[d.attachedModuleId];
    }
    return null;
  }

  // ---- deployments ----

  String? addDeployment(Deployment d, {bool activate = true}) {
    if (deployments.any((x) => x.name == d.name)) {
      return 'A deployment named "${d.name}" already exists';
    }
    deployments.add(d);
    if (activate) activeDeploymentName = d.name;
    notifyListeners();
    return null;
  }

  void removeDeployment(Deployment d) {
    deployments.remove(d);
    if (activeDeploymentName == d.name) {
      activeDeploymentName =
          deployments.isEmpty ? '' : deployments.last.name;
    }
    notifyListeners();
  }

  void activateDeployment(String name) {
    if (deployments.any((d) => d.name == name)) {
      activeDeploymentName = name;
      notifyListeners();
    }
  }

  void approveDeployment(Deployment d, {bool approved = true}) {
    d.approved = approved;
    notifyListeners();
  }

  /// Ensure there is an active deployment to draw placements into; used
  /// by the map when the operator starts placing with none selected.
  Deployment ensureActiveDeployment() {
    final existing = activeDeployment;
    if (existing != null) return existing;
    var n = 1;
    while (deployments.any((d) => d.name == 'deployment $n')) {
      n++;
    }
    final d = Deployment(name: 'deployment $n');
    deployments.add(d);
    activeDeploymentName = d.name;
    notifyListeners();
    return d;
  }

  void addPlacement(DronePlacement p) {
    ensureActiveDeployment().placements.add(p);
    notifyListeners();
  }

  void removePlacement(DronePlacement p) {
    activeDeployment?.placements.remove(p);
    notifyListeners();
  }

  void movePlacement(DronePlacement p, double lat, double lon) {
    p.lat = lat;
    p.lon = lon;
    notifyListeners();
  }

  void touch() => notifyListeners();

  // ---- persistence ----

  String toJsonString() => const JsonEncoder.withIndent('  ').convert({
        'schema': 'mission-v1',
        'mission_name': missionName,
        'disaster_type': disasterType,
        'created_at': createdAt,
        'saved_at': DateTime.now().toUtc().toIso8601String(),
        'challenges': challenges,
        'area': area.map((p) => p.toJson()).toList(),
        'resources': {
          'personnel_count': personnelCount,
          'spare_batteries': spareBatteries,
          'drones': drones.map((d) => d.toJson()).toList(),
          'modules': modules.map((m) => m.toJson()).toList(),
        },
        'product_cache':
            productCache.map((k, v) => MapEntry(k, v.toJson())),
        'deployments': deployments.map((d) => d.toJson()).toList(),
        'active_deployment': activeDeploymentName,
      });

  void loadFromJsonString(String jsonString) {
    final data = jsonDecode(jsonString) as Map<String, dynamic>;

    _reset();
    if (data['schema'] == 'mission-v1') {
      missionName = (data['mission_name'] ?? 'unnamed mission') as String;
      disasterType = (data['disaster_type'] ?? 'flood') as String;
      createdAt = (data['created_at'] ?? createdAt) as String;
      challenges.addAll((data['challenges'] as List<dynamic>? ?? [])
          .map((c) => c as String));
      area.addAll((data['area'] as List<dynamic>? ?? [])
          .map((p) => GeoPoint.fromJson(p as Map<String, dynamic>)));
      final res = data['resources'] as Map<String, dynamic>? ?? {};
      personnelCount = (res['personnel_count'] as num? ?? 0).toInt();
      spareBatteries = (res['spare_batteries'] as num? ?? 0).toInt();
      drones.addAll((res['drones'] as List<dynamic>? ?? [])
          .map((d) => DroneResource.fromJson(d as Map<String, dynamic>)));
      modules.addAll((res['modules'] as List<dynamic>? ?? [])
          .map((m) => ModuleResource.fromJson(m as Map<String, dynamic>)));
      (data['product_cache'] as Map<String, dynamic>? ?? {})
          .forEach((k, v) => productCache[k] =
              ProductInfo.fromJson(v as Map<String, dynamic>));
      deployments.addAll((data['deployments'] as List<dynamic>? ?? [])
          .map((d) => Deployment.fromJson(d as Map<String, dynamic>)));
      activeDeploymentName = (data['active_deployment'] ?? '') as String;
    } else if (data.containsKey('markers')) {
      // Legacy operation-plan file (pre-mission PlanState): import its
      // markers as one approved manual deployment so nothing is lost.
      missionName = (data['plan_name'] ?? 'imported plan') as String;
      final d = Deployment(name: 'imported plan', approved: true);
      for (final m in data['markers'] as List<dynamic>? ?? []) {
        final mm = m as Map<String, dynamic>;
        d.placements.add(DronePlacement(
          name: (mm['name'] ?? 'marker') as String,
          lat: (mm['lat'] as num).toDouble(),
          lon: (mm['lon'] as num).toDouble(),
          radiusM: (mm['radius_m'] as num? ?? 300).toDouble(),
        ));
      }
      deployments.add(d);
      activeDeploymentName = d.name;
    } else {
      throw const FormatException('not a mission or plan file');
    }
    notifyListeners();
  }

  void _reset() {
    missionName = 'unnamed mission';
    disasterType = 'flood';
    challenges.clear();
    area.clear();
    personnelCount = 0;
    spareBatteries = 0;
    drones.clear();
    modules.clear();
    productCache.clear();
    deployments.clear();
    activeDeploymentName = '';
  }

  void clearMission() {
    _reset();
    loadedFrom = null;
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
      return 'Not a valid mission file: ${e.message}';
    }
  }
}
