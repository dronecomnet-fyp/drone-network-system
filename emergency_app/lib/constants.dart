/// Shared constants for the emergency app (file 06).
library;

/// The project-fixed BLE service UUID the aux module advertises (file 03,
/// firmware/aux/src/main.cpp; generated once, hardcoded fleet-wide). The
/// armed-mode scan filters on exactly this UUID so only rescue drones
/// trigger a notification.
const String kRescueServiceUuid = '2b57461c-1c04-49c4-944a-13643c1618da';

/// Victim plane base URL once joined to a drone AP (file 09 F3: the victim
/// flow is plain HTTP on port 80; no certificate, no auth).
const String kDroneBaseUrl = 'http://10.42.0.1';

/// The drone gateway IP used to detect "I am connected to a drone".
const String kDroneGatewayIp = '10.42.0.1';

/// Local location ring buffer size: about 7 days at 2 logs/day (file 06
/// data design). Oldest points drop off first.
const int kMaxStoredPoints = 14;

/// Background location logging period (file 06: about twice per day). The
/// OS may defer WorkManager tasks by minutes to hours; that is acceptable
/// and stated plainly to the user, not promised as exact.
const Duration kLocationLogPeriod = Duration(hours: 12);
