/// An unapproved deployment must not appear on the operations map (field
/// backlog #3c).
///
/// This is a safety property dressed as a UI preference. A proposal drawn
/// on the same map as the live operation is indistinguishable from a
/// decision, and the proposal here comes from a language model that has
/// never seen the ground. The rule is that a draft is visible while
/// planning and nowhere else.
///
/// Tested against the rule itself rather than by pixel-hunting a map
/// widget, because the rule is what has to hold.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gcc_app/state/mission_state.dart';

/// The same predicate map_screen.dart applies before drawing placements.
bool visibleOnMap(MissionState m) {
  final d = m.activeDeployment;
  return d != null && (d.approved || m.planningMode);
}

MissionState _withPlan({required bool approved}) {
  final m = MissionState();
  m.addDeployment(Deployment(
    name: 'AI plan 1',
    source: 'ai',
    approved: approved,
    placements: [
      DronePlacement(
          name: 'north',
          lat: 6.93,
          lon: 79.86,
          role: kRoleUserAp,
          radiusM: 300),
    ],
  ));
  return m;
}

void main() {
  test('an AI draft is hidden on the operations map', () {
    final m = _withPlan(approved: false);
    m.setPlanningMode(false);
    expect(visibleOnMap(m), isFalse);
  });

  test('the same draft IS visible while planning', () {
    final m = _withPlan(approved: false);
    m.setPlanningMode(true);
    expect(visibleOnMap(m), isTrue);
  });

  test('approving it makes it visible everywhere', () {
    final m = _withPlan(approved: false);
    m.setPlanningMode(false);
    m.approveDeployment(m.activeDeployment!);
    expect(visibleOnMap(m), isTrue);
  });

  test('un-approving hides it again', () {
    // Withdrawing a plan has to actually withdraw it.
    final m = _withPlan(approved: true);
    m.setPlanningMode(false);
    expect(visibleOnMap(m), isTrue);
    m.approveDeployment(m.activeDeployment!, approved: false);
    expect(visibleOnMap(m), isFalse);
  });

  test('a mission with no deployment draws nothing', () {
    final m = MissionState()..setPlanningMode(true);
    expect(visibleOnMap(m), isFalse);
  });

  test('an AI plan arrives unapproved', () {
    // The advisor must never be able to put something on the live map by
    // itself, whatever it returns.
    final m = MissionState();
    m.addDeployment(Deployment(name: 'AI plan 1', source: 'ai'));
    expect(m.activeDeployment!.approved, isFalse);
  });
}
