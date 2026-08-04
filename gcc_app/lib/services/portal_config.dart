/// Turning a mission into the option list victims actually tap, and
/// pushing it to each node (CHANGES.md item 34).
///
/// The nodes hold a versioned config and report which version they have,
/// so the operator can see a partially updated fleet BEFORE deploying
/// rather than discovering it from a victim who saw the wrong options.
/// This file owns the two halves the GCC needs: building sensible options
/// for a disaster type, and pushing them one node at a time.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Suggested options per disaster type. These are a STARTING POINT the
/// operator edits, not a fixed taxonomy: the whole reason the config is
/// pushable is that the person running the mission knows the situation
/// better than a lookup table written months earlier.
///
/// Every list is phrased as something a frightened person would recognise
/// about themselves, not as a category name. "I am trapped in a flooded
/// house" beats "Entrapment".
const Map<String, List<Map<String, Object>>> kSuggestedSituations = {
  'flood': [
    {'id': 'trapped_water', 'label': 'I am trapped by water', 'urgent': true},
    {'id': 'roof', 'label': 'We are stuck on a roof or upper floor', 'urgent': true},
    {'id': 'injured', 'label': 'Someone here is injured', 'urgent': true},
    {'id': 'boat', 'label': 'We need a boat to get out', 'urgent': false},
    {'id': 'water_food', 'label': 'We need drinking water or food', 'urgent': false},
    {'id': 'safe', 'label': 'We are safe, reporting our location', 'urgent': false},
  ],
  'landslide': [
    {'id': 'buried', 'label': 'Someone is buried or trapped', 'urgent': true},
    {'id': 'injured', 'label': 'Someone here is injured', 'urgent': true},
    {'id': 'unstable', 'label': 'The ground here is still moving', 'urgent': true},
    {'id': 'cut_off', 'label': 'The road is blocked, we cannot leave', 'urgent': false},
    {'id': 'water_food', 'label': 'We need drinking water or food', 'urgent': false},
    {'id': 'safe', 'label': 'We are safe, reporting our location', 'urgent': false},
  ],
  'cyclone': [
    {'id': 'trapped', 'label': 'I am trapped and cannot get out', 'urgent': true},
    {'id': 'injured', 'label': 'Someone here is injured', 'urgent': true},
    {'id': 'no_shelter', 'label': 'Our building is damaged, we have no shelter',
     'urgent': true},
    {'id': 'water_food', 'label': 'We need drinking water or food', 'urgent': false},
    {'id': 'safe', 'label': 'We are safe, reporting our location', 'urgent': false},
  ],
  'fire': [
    {'id': 'surrounded', 'label': 'We are surrounded by fire or smoke', 'urgent': true},
    {'id': 'injured', 'label': 'Someone here is burned or injured', 'urgent': true},
    {'id': 'cannot_move', 'label': 'We cannot move, we need carrying out',
     'urgent': true},
    {'id': 'evacuate', 'label': 'We need help evacuating', 'urgent': false},
    {'id': 'safe', 'label': 'We are safe, reporting our location', 'urgent': false},
  ],
};

/// Falls back to the need-based list for anything not in the table, which
/// is the same shape the nodes ship as stock. An unusual disaster type
/// gets generic-but-correct options rather than nothing.
const List<Map<String, Object>> kGenericSituations = [
  {'id': 'trapped', 'label': 'I am trapped and cannot get out', 'urgent': true},
  {'id': 'injured', 'label': 'Someone here is injured', 'urgent': true},
  {'id': 'medical', 'label': 'I need medicine or a doctor', 'urgent': true},
  {'id': 'water_food', 'label': 'I need drinking water or food', 'urgent': false},
  {'id': 'shelter', 'label': 'I need shelter or evacuation', 'urgent': false},
  {'id': 'safe', 'label': 'I am safe, reporting my location', 'urgent': false},
];

List<Map<String, Object>> suggestedFor(String disasterType) =>
    kSuggestedSituations[disasterType.trim().toLowerCase()] ??
    kGenericSituations;

/// What a mission will actually publish: the operator's one edit if they
/// made it, otherwise the defaults for the disaster type. Keeping this in
/// one function means the confirm dialog, the fingerprint comparison and
/// the push can never disagree about what is going to be sent.
List<Map<String, Object>> effectiveSituations({
  required List<Map<String, Object>> edited,
  required String disasterType,
}) =>
    edited.isNotEmpty ? edited : suggestedFor(disasterType);

/// Build the payload for POST /mission-config.
///
/// No version number: the node fingerprints the content and orders pushes
/// by updated_at, so nothing here has to keep a counter correct.
Map<String, dynamic> buildPortalConfig({
  required String missionId,
  required String missionName,
  required String disasterType,
  required List<Map<String, Object>> situations,
  String headline = 'Tap what you need. You can tap more than one.',
  bool showRescuerPositions = true,
  bool force = false,
}) =>
    {
      // The node scopes credentials to this, so pushing a different mission
      // retires every credential from the previous one.
      'mission_id': missionId,
      'mission_name': missionName,
      'disaster_type': disasterType,
      'headline': headline,
      'situations': situations,
      'show_rescuer_positions': showRescuerPositions,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'force': force,
    };

/// The id a node WILL report once it is serving these options. Mirrors the
/// node's content_id (backend/mission_config.py) so the GCC can say
/// "this node already matches" without pushing first.
String portalConfigId({
  required List<Map<String, Object>> situations,
  String headline = 'Tap what you need. You can tap more than one.',
  bool showRescuerPositions = true,
}) {
  final payload = jsonEncode({
    'headline': headline,
    'show_rescuer_positions': showRescuerPositions,
    'situations': situations
        .map((s) => {
              'id': s['id'],
              'label': s['label'],
              'urgent': s['urgent'] == true,
            })
        .toList(),
  });
  return sha256.convert(utf8.encode(payload)).toString().substring(0, 12);
}
