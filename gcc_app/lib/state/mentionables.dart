/// Turns whatever the fleet currently knows about into things the operator
/// can attach to a message (field backlog #14).
///
/// Kept out of the widget so it can be unit tested and so the ordering
/// rule lives in one place: degraded drones first, then victims who have
/// not been claimed, then everything else. That order is the operator's
/// priority order, not alphabetical, because the picker is used mid
/// sentence and the first screenful is all most people will read.
library;

import 'package:flutter/material.dart';
import 'package:rescue_mesh_shared/rescue_mesh_shared.dart';

import '../widgets/mention_field.dart';

String _coords(double? lat, double? lon) =>
    (lat == null || lon == null)
        ? ''
        : ' (${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)})';

/// Short, stable handle for a victim. The full device id is a uuid and
/// unreadable in a sentence; the first 8 characters are what every other
/// screen already shows, so operator and rescuer are looking at the same
/// string.
String victimHandle(String deviceId) =>
    deviceId.substring(0, deviceId.length.clamp(0, 8));

List<Mentionable> buildMentionables({
  NodeHealth? health,
  required List<Message> messages,
  required List<PersonnelLocation> rescuers,
}) {
  final out = <Mentionable>[];

  for (final d in health?.degradedNodes ?? const <DegradedNode>[]) {
    out.add(Mentionable(
      kind: 'Degraded',
      label: d.nodeId,
      token: '@${d.nodeId}${_coords(d.lat, d.lon)}',
      subtitle: 'Pi down, last beacon ${d.ts}',
      icon: Icons.airplanemode_inactive,
      color: Colors.redAccent,
    ));
  }

  // Unclaimed victims before claimed ones: an unanswered call for help is
  // the thing most likely to be the subject of an urgent message.
  final victims = messages.where((m) => m.victimDeviceId.isNotEmpty).toList()
    ..sort((a, b) {
      if (a.isClaimed != b.isClaimed) return a.isClaimed ? 1 : -1;
      return b.timestamp.compareTo(a.timestamp);
    });
  final seen = <String>{};
  for (final m in victims) {
    if (!seen.add(m.victimDeviceId)) continue;
    final handle = victimHandle(m.victimDeviceId);
    out.add(Mentionable(
      kind: 'Victims',
      label: 'victim $handle',
      token: '@victim-$handle${_coords(m.userLat, m.userLon)}',
      subtitle: m.isClaimed
          ? 'claimed by ${m.claimedBy}: ${m.content}'
          : 'NEW: ${m.content}',
      icon: Icons.location_pin,
      color: m.isClaimed ? Colors.greenAccent : Colors.redAccent,
    ));
  }

  final connected = health?.nodeId ?? '';
  if (connected.isNotEmpty) {
    final gps = health?.gps;
    out.add(Mentionable(
      kind: 'Drones',
      label: '$connected (connected)',
      token: '@$connected${gps != null && gps.hasFix ? _coords(gps.lat, gps.lon) : ''}',
      subtitle: 'the node this GCC is joined to',
      icon: Icons.airplanemode_active,
      color: Colors.cyanAccent,
    ));
  }
  for (final p in health?.peers ?? const <PeerInfo>[]) {
    out.add(Mentionable(
      kind: 'Drones',
      label: p.nodeId,
      token: '@${p.nodeId}${p.gpsFix == 1 ? _coords(p.lat, p.lon) : ''}',
      subtitle: 'peer, last seen ${p.lastSeen}',
      icon: Icons.airplanemode_active,
      color: Colors.cyanAccent,
    ));
  }

  for (final r in rescuers.where((r) => r.hasLocation)) {
    out.add(Mentionable(
      kind: 'Rescuers',
      label: r.personnelId,
      token: '@${r.personnelId}${_coords(r.lat, r.lon)}',
      subtitle: 'last reported ${r.updatedAt}',
      icon: Icons.person_pin_circle,
      color: Colors.tealAccent,
    ));
  }

  return out;
}
