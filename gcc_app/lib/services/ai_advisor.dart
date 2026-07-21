/// AiAdvisor (M7e): asks an LLM to propose a drone deployment for the
/// current mission, then VALIDATES the answer before it is shown.
///
/// The flow (the "tool" is this app; there is no separate AI server):
///   1. Build a prompt FROM the mission (area, resources, cached specs).
///   2. POST it to an OpenAI-compatible chat endpoint (free tiers work:
///      Groq, OpenRouter). Config is entered in Settings, never committed.
///   3. Parse the JSON reply and validate it against the mission (free
///      models are unreliable, so the validator is the real guarantee).
///   4. Return placements as an UNAPPROVED deployment; the operator reviews
///      and approves on the map. The AI never commands a drone.
///
/// Online only (HQ phase). Offline, the operator plans manually with the
/// existing marker tools. Parsing and validation are pure top-level
/// functions so they can be unit-tested with no network.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../state/mission_state.dart';
import 'geo.dart';

class AiAdvisorException implements Exception {
  final String message;
  AiAdvisorException(this.message);
  @override
  String toString() => message;
}

/// A validated suggestion: placements the operator can review, a short
/// human summary, and warnings the validator (or the model) raised.
class AiSuggestion {
  final List<DronePlacement> placements;
  final String summary;
  final List<String> warnings;

  const AiSuggestion({
    required this.placements,
    required this.summary,
    required this.warnings,
  });
}

class AiAdvisor {
  final String endpoint; // e.g. https://api.groq.com/openai/v1
  final String model;
  final String apiKey;
  final http.Client _http;

  AiAdvisor({
    required this.endpoint,
    required this.model,
    required this.apiKey,
    http.Client? client,
  }) : _http = client ?? http.Client();

  Future<AiSuggestion> suggest(MissionState mission) async {
    if (endpoint.isEmpty || apiKey.isEmpty) {
      throw AiAdvisorException(
          'AI advisor not configured (set the endpoint and key in Settings)');
    }
    if (mission.area.length < 3) {
      throw AiAdvisorException(
          'Draw the operation area (a polygon) on the Map first, so the AI '
          'knows where to place drones');
    }

    final system = _systemPrompt();
    final user = buildUserPrompt(mission);

    // One automatic retry: if the model returns unparseable JSON, ask again
    // with the parse error appended (a common free-model failure).
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      final messages = <Map<String, dynamic>>[
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
        if (attempt > 0)
          {
            'role': 'user',
            'content':
                'Your previous reply was not valid JSON ($lastError). Reply '
                    'with ONLY the JSON object, no prose, no code fences.'
          },
      ];
      final content = await _chat(messages);
      try {
        final raw = parseSuggestionJson(content);
        return validateSuggestion(raw, mission);
      } on FormatException catch (e) {
        lastError = e.message;
      }
    }
    throw AiAdvisorException(
        'The AI did not return usable JSON after a retry: $lastError');
  }

  Future<String> _chat(List<Map<String, dynamic>> messages) async {
    final uri = Uri.parse('$endpoint/chat/completions');
    final headers = {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
    };
    final body = {
      'model': model,
      'messages': messages,
      // JSON mode where supported; parsing also strips fences as a fallback.
      'response_format': {'type': 'json_object'},
    };

    http.Response resp;
    try {
      resp = await _http
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 45));
    } on SocketException {
      throw AiAdvisorException('AI planning needs internet (HQ phase). '
          'Offline, plan manually on the Map.');
    } catch (e) {
      throw AiAdvisorException('Could not reach the AI endpoint: $e');
    }

    // Some providers reject response_format for some models: retry once
    // without it before giving up.
    if (resp.statusCode == 400 && body.containsKey('response_format')) {
      body.remove('response_format');
      resp = await _http.post(uri, headers: headers, body: jsonEncode(body));
    }

    if (resp.statusCode == 401) {
      throw AiAdvisorException('AI rejected the key (401): check the API key');
    }
    if (resp.statusCode == 429) {
      throw AiAdvisorException('AI rate limit (429): free tier is busy, '
          'wait a moment and retry');
    }
    if (resp.statusCode != 200) {
      throw AiAdvisorException('AI endpoint error ${resp.statusCode}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final choices = data['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw AiAdvisorException('AI returned no choices');
    }
    final msg = (choices.first as Map<String, dynamic>)['message']
        as Map<String, dynamic>?;
    final content = msg?['content'];
    if (content is! String || content.trim().isEmpty) {
      throw AiAdvisorException('AI returned an empty message');
    }
    return content;
  }

  String _systemPrompt() =>
      'You are a communications-network planner for disaster response. You '
      'place drone-mounted mesh nodes to maximise coverage of an operation '
      'area while keeping the nodes connected to each other. Roles: '
      '"user_ap" (covers victims/rescuers), "mesh_relay" (links the network), '
      '"system_drone" (the one flyable drone, at most one). '
      'Reply with ONLY a JSON object of this exact shape, no prose, no code '
      'fences:\n'
      '{"placements":[{"name":"","lat":0,"lon":0,'
      '"role":"user_ap|mesh_relay|system_drone","radius_m":0,"rationale":""}],'
      '"summary":"","warnings":[""]}\n'
      'All placements must be inside the given area polygon. Do not exceed the '
      'number of available drones. Keep each placement within the mesh range '
      'of at least one other so the network stays connected.';

  void close() => _http.close();
}

/// Build the mission-specific user prompt. Pure so it can be unit-tested.
String buildUserPrompt(MissionState mission) {
  final b = StringBuffer();
  b.writeln('Mission: ${mission.missionName} (${mission.disasterType}).');
  if (mission.challenges.isNotEmpty) {
    b.writeln('Challenges: ${mission.challenges.join(", ")}.');
  }
  b.writeln('Available drones: ${mission.drones.length}. '
      'Spare modules: ${mission.modules.where((m) => m.attachedTo.isEmpty).length}.');

  // Spec ranges from cached products (coverage sizing).
  final aps = <double>[];
  final meshes = <double>[];
  for (final info in mission.productCache.values) {
    if (info.apRangeM != null) aps.add(info.apRangeM!);
    if (info.meshRangeM != null) meshes.add(info.meshRangeM!);
  }
  if (aps.isNotEmpty) {
    b.writeln('Typical user-AP coverage radius: '
        '${(aps.reduce((a, c) => a + c) / aps.length).round()} m.');
  }
  if (meshes.isNotEmpty) {
    b.writeln('Typical mesh link range: '
        '${(meshes.reduce((a, c) => a + c) / meshes.length).round()} m.');
  }

  b.writeln('Operation area polygon (lat, lon), in order:');
  for (final p in mission.area) {
    b.writeln('  ${p.lat.toStringAsFixed(6)}, ${p.lon.toStringAsFixed(6)}');
  }
  b.writeln('Propose placements covering this area with the drones available.');
  return b.toString();
}

/// Decode the model's reply into a map, tolerating markdown code fences and
/// leading/trailing prose. Throws FormatException if no JSON object is found.
Map<String, dynamic> parseSuggestionJson(String content) {
  var text = content.trim();
  // Strip ```json ... ``` or ``` ... ``` fences.
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```', multiLine: true);
  final m = fence.firstMatch(text);
  if (m != null) text = m.group(1)!.trim();
  // Otherwise, slice from the first { to the last } (handles stray prose).
  if (!text.startsWith('{')) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start >= 0 && end > start) text = text.substring(start, end + 1);
  }
  final decoded = jsonDecode(text);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('top-level JSON is not an object');
  }
  return decoded;
}

/// Turn a parsed reply into validated placements plus warnings. Pure so it
/// can be unit-tested against canned responses. Never throws on a
/// semantically-wrong-but-parseable answer: it clamps, drops bad rows, and
/// records warnings, because the operator reviews before approving.
AiSuggestion validateSuggestion(
    Map<String, dynamic> raw, MissionState mission) {
  final warnings = <String>[
    ...((raw['warnings'] as List<dynamic>?) ?? [])
        .whereType<String>()
        .map((w) => w.trim())
        .where((w) => w.isNotEmpty),
  ];
  final summary = (raw['summary'] ?? '') as String;

  final rawPlacements = raw['placements'];
  if (rawPlacements is! List || rawPlacements.isEmpty) {
    throw const FormatException('reply has no "placements" list');
  }

  final polygon = mission.area.map((p) => [p.lat, p.lon]).toList();
  final meshRange = _missionMeshRange(mission);
  final placements = <DronePlacement>[];

  for (final item in rawPlacements) {
    if (item is! Map) continue;
    final lat = _num(item['lat']);
    final lon = _num(item['lon']);
    if (lat == null || lon == null) continue;
    if (lat < -90 || lat > 90 || lon < -180 || lon > 180) continue;

    var role = (item['role'] ?? kRoleUserAp).toString();
    if (!kPlacementRoles.contains(role)) role = kRoleUserAp;

    var radius = _num(item['radius_m']) ?? 300;
    radius = radius.clamp(50, 5000).toDouble();

    final name = (item['name'] ?? 'placement ${placements.length + 1}')
        .toString()
        .trim();

    if (polygon.length >= 3 && !pointInPolygon(lat, lon, polygon)) {
      warnings.add('"$name" is outside the operation area; move it inside.');
    }

    placements.add(DronePlacement(
      name: name.isEmpty ? 'placement ${placements.length + 1}' : name,
      lat: lat,
      lon: lon,
      role: role,
      radiusM: radius,
      rationale: (item['rationale'] ?? '').toString(),
    ));
  }

  if (placements.isEmpty) {
    throw const FormatException('no valid placements in the reply');
  }

  // Count vs inventory.
  final available = mission.drones.length;
  if (available > 0 && placements.length > available) {
    warnings.add('Suggests ${placements.length} placements but only '
        '$available drones are available.');
  }

  // At most one system drone.
  final systemCount =
      placements.where((p) => p.role == kRoleSystemDrone).length;
  if (systemCount > 1) {
    warnings.add('More than one system-drone placement; only one drone can '
        'be flown.');
  }

  // Mesh connectivity: every placement within mesh range of another.
  if (placements.length > 1) {
    for (final p in placements) {
      final linked = placements.any((o) =>
          !identical(o, p) &&
          haversineM(p.lat, p.lon, o.lat, o.lon) <= meshRange);
      if (!linked) {
        warnings.add('"${p.name}" may be out of mesh range '
            '(${meshRange.round()} m) of every other node.');
      }
    }
  }

  return AiSuggestion(
      placements: placements, summary: summary, warnings: warnings);
}

double _missionMeshRange(MissionState mission) {
  final meshes = mission.productCache.values
      .map((i) => i.meshRangeM)
      .whereType<double>()
      .toList();
  if (meshes.isEmpty) return 900; // default small-node mesh range, Low
  return meshes.reduce((a, b) => a > b ? a : b);
}

double? _num(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}
