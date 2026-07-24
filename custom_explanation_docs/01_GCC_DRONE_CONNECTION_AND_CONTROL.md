# GCC to Drone: Connection and Control, In Depth

This document answers one question in full depth: **how does the Ground
Control Center (GCC) app connect to and control the system drone, and exactly
what protocols, libraries, and methods make that happen, on both ends of the
link.** Every fact here is checked directly against the code; file paths and
line-level references are given throughout so you can jump straight to the
source.

Only one drone in the fleet has a flight controller the GCC can command:
**DRONE_S** (the AeroSync 5 "system drone"). Every other drone in the fleet
only carries a communication module; this whole document is about the link to
DRONE_S specifically. See `documentation/11_SYSTEM_DRONE.md` for the
higher-level story; this document is the depth-first technical companion to
that chapter.

---

## 1. The big picture: two machines, one wire, one protocol, two networks

There are exactly three participants in a drone control session:

```
 GCC app (Dart/Flutter)          MAVLink Gateway (Python)         Flight Controller
 gcc_app/lib/mavlink/             mavlink_gateway/mav_gateway.py    CC3D Open Revolution Mini
 mav_service.dart                 (runs on DRONE_S's Raspberry      (ArduPilot firmware,
                                   Pi 4, as a systemd service)       already speaks MAVLink)
        |                                    |                              |
        |  MAVLink v2 over UDP               |  MAVLink v2 over            |
        |  (port 14550)                      |  raw serial bytes           |
        |  network: Wi-Fi                    |  (USB-CDC or UART)          |
        +------------------------------------+------------------------------+
                     one continuous MAVLink v2 byte stream,
                     re-encapsulated at the UDP<->serial boundary
                     but never re-interpreted (transparent bridge)
```

Two physically different transports (Wi-Fi/UDP on one side, a serial wire on
the other) carry **the same protocol, MAVLink v2**, unmodified end to end. The
Python gateway is a byte-transparent bridge: it does not decode a command and
re-encode it: it copies the raw bytes it receives on one side straight to the
other side. It only *additionally* peeks at a copy of the FC-to-GCC stream to
harvest telemetry for the node's own use (`/health`), which is a separate,
read-only concern layered on top of the same bytes.

This is deliberate and stated as a hard rule in the code:

> "Bytes are never altered, so a command cannot be corrupted, and nothing is
> ever queued: control is live-only" (`mavlink_gateway/README.md`).

## 2. The two network paths from the GCC to the gateway

The GCC never talks to the flight controller directly; it always talks to the
gateway's UDP socket. There are two ways to reach that socket, and both are
**live-only, never store-and-forward** (unlike the rest of the mesh, which is
a delay-tolerant network; drone control is explicitly exempted from that
because a queued flight command would be dangerous).

### 2.1 Direct path

The laptop joins DRONE_S's own 5 GHz access point, `RESCUE_S`, and talks
straight to it:

```
GCC laptop --Wi-Fi--> RESCUE_S AP (10.42.0.1) --UDP:14550--> mav_gateway.py --serial--> FC
```

Default target string in the app: `udp:10.42.0.1:14550`
(`gcc_app/lib/state/app_state.dart:51`).

### 2.2 Relay path (through a volunteer drone)

The laptop instead joins a **volunteer** drone's AP (`RESCUE_A` or
`RESCUE_B`), and that volunteer node forwards the UDP packets across the 2.4
GHz IBSS mesh to DRONE_S:

```
GCC laptop --Wi-Fi--> RESCUE_A/B AP (10.42.0.1 on that node)
    --nftables forward--> mesh (10.99.0.0/24) --UDP:14550--> DRONE_S (10.99.0.3)
    --> mav_gateway.py --serial--> FC
```

Target string: `udp:10.99.0.3:14550`.

Both presets are one tap away in the GCC's Settings screen
(`gcc_app/lib/screens/settings_screen.dart`, the "DIRECT (RESCUE_S)" /
"RELAY (via mesh)" action chips), and both are wired into
`AppState.mavlinkTarget`, which `DroneController.connect()` reads.

**This relay is not DTN sync.** It is a live IP forward at the network layer,
done by the volunteer node's firewall/NAT rules, not by the application-level
store-and-forward sync engine that carries victim messages. If the relay link
drops mid-command, the command is simply lost, exactly like a direct Wi-Fi
drop; nothing retries it from a queue. See section 8 for the exact firewall
rules that make the relay possible and that also lock it down.

## 3. The protocol: MAVLink v2

MAVLink (Micro Air Vehicle Link) is a lightweight, binary, message-based
protocol originally built for drones. This project uses **MAVLink 2** (the
version with a 24-bit message ID space, extensible field marking, and
optional payload signing). It is *transport-agnostic*: it is defined purely as
a byte format, and different transports (serial, UDP, TCP) carry the exact
same bytes. That is exactly what section 1's diagram shows: the same v2 frame
travels over UDP on the Wi-Fi hop and over a raw serial line on the Pi-to-FC
hop, with no protocol translation in between, only a change of physical
carrier.

### 3.1 Frame anatomy (v2)

Every MAVLink v2 packet has this exact byte layout (from
`dart_mavlink`'s `mavlink_frame.dart`, `_serializeV2()`, and mirrored on the
receive side in `mavlink_parser.dart`):

| Offset | Bytes | Field | Notes |
|--------|-------|-------|-------|
| 0 | 1 | Start-of-frame marker | `0xFD` for v2 (`0xFE` for the older v1) |
| 1 | 1 | Payload length | 0-255 bytes |
| 2 | 1 | Incompatibility flags | bit 0 (`0x01`) means "this packet is signed" |
| 3 | 1 | Compatibility flags | reserved |
| 4 | 1 | Packet sequence number | wraps 0-255; used to detect drops |
| 5 | 1 | System ID | sender's vehicle/GCS ID |
| 6 | 1 | Component ID | sender's sub-system ID |
| 7-9 | 3 | Message ID | 24-bit, little-endian across 3 bytes |
| 10..N | payload length | Payload | the message's own fields, dialect-defined |
| N+1 | 2 | CRC-16/X25 | covers everything from byte 1 onward, plus a per-message "CRC extra" seed |

The CRC is **CRC-16/X25** (`dart_mavlink/lib/crc.dart`, class `CrcX25`), the
same checksum MAVLink has always used. It is accumulated over the header
fields, the payload bytes, and then one extra "CRC_EXTRA" byte that is fixed
per message type (baked into the dialect definition) so that even a
correctly-shaped packet with the wrong CRC_EXTRA (i.e. decoded against the
wrong dialect/message definition) fails the check.

### 3.2 The dialect: ArduPilot-specific messages on top of the MAVLink common set

MAVLink is a **base protocol plus dialects**. The base ("common") message set
defines the widely-used messages (heartbeat, GPS, attitude, generic commands).
Each autopilot family (ArduPilot, PX4, and so on) publishes a *dialect XML*
that adds vendor-specific messages and commands on top of the common set,
while still being able to parse anything in the common set.

This project's flight controller runs **ArduPilot firmware** (a CC3D Open
Revolution Mini), so both ends use the **`ardupilotmega`** dialect:

- GCC (Dart): `MavlinkDialectArdupilotmega()` from
  `package:dart_mavlink/dialects/ardupilotmega.dart`
  (`gcc_app/lib/mavlink/mav_service.dart:26,81`).
- Gateway (Python): `pymavlink`'s `mavutil.mavlink` module, which is
  generated from the same upstream `ardupilotmega.xml` definition
  (`mavlink_gateway/mav_gateway.py:47,104`).

Both libraries are **independently generated from the same MAVLink XML
message-definition schema** (the Dart one from a `tool/generate.dart`
generator in the `dart_mavlink` package; pymavlink from the official
`pymavlink` generator). They do not share code, but they agree on message
IDs, field layouts, and CRC_EXTRA values because they are generated from the
same specification. This is *why* a Dart app and a Python gateway can
losslessly speak to the same flight controller: MAVLink's specification, not
any shared library, is the interoperability contract.

### 3.3 Frame parsing: a byte-at-a-time state machine

`MavlinkParser.parse(Uint8List data)` (`dart_mavlink/lib/mavlink_parser.dart`)
is a classic incremental state machine, not a whole-packet parser. It
processes the incoming byte stream one byte at a time through named states
(`init -> waitPayloadLength -> waitIncompatibilityFlags -> ... ->
waitCrcHighByte`), which means it works correctly even if UDP datagrams
split a MAVLink frame across two packets or coalesce several frames into
one datagram; it does not assume "one read = one message." When a full frame
passes its CRC check, it is decoded via `_dialect.parse(messageId, payload)`
and pushed onto a broadcast `Stream<MavlinkFrame>` that `MavService` listens
to (`mav_service.dart:127`, `_parser.stream.listen(_onFrame)`).

**One consequence worth knowing:** in `mavlink_parser.dart:191-198`, if the
incompatibility-flags byte has bit 0 set (meaning the sender signed the
packet with MAVLink 2's optional message-signing feature), the parser
comments `// TODO Handle the Signature bits.` and simply **drops the frame
silently** rather than verifying or stripping the signature. This library
version cannot receive signed MAVLink traffic at all. This is the exact
detail behind the project's recorded residual risk (`documentation/05_SECURITY.md`,
`documentation/11_SYSTEM_DRONE.md`): MAVLink 2 packet signing is not
implemented, and one concrete reason on the GCC side is that the Dart
library used here has no signature-verification code path yet. If a future
team enables `MAV_CMD_SETUP_SIGNING` on the flight controller, **the GCC
would stop receiving any telemetry or acks at all** until this is fixed, not
merely fail a security check. This is worth testing explicitly before ever
turning signing on.

### 3.4 MAVLink v1 vs v2

The library also supports v1 (`0xFE` marker, 8-byte header, no incompatibility
flags, no signing). This project only ever constructs v2 frames
(`MavlinkFrame.v2(...)` at `mav_service.dart:214`), but the parser accepts
either on receive (it switches on which start byte it sees). In practice the
flight controller replies in v2 as well, since ArduPilot defaults to v2
once it has seen a v2 packet from the GCS.

## 4. The GCC side: `MavService` (Dart)

File: `gcc_app/lib/mavlink/mav_service.dart`. This is the entire client
implementation; there is no other MAVLink code in the app. Everything else
(`DroneController`, `FleetState`, the screens) either commands this class or
listens to its streams.

### 4.1 Library and dialect setup

```dart
import 'package:dart_mavlink/mavlink.dart';
import 'package:dart_mavlink/dialects/ardupilotmega.dart';

final _dialect = MavlinkDialectArdupilotmega();
late final MavlinkParser _parser = MavlinkParser(_dialect);
```

Note the import path: `package:dart_mavlink/mavlink.dart` (the package's
umbrella export file), not `dart_mavlink.dart`. Getting this import wrong is a
real, previously-hit mistake (recorded in the project history) because the
package's actual file is named `mavlink.dart` inside the `dart_mavlink`
package, which reads confusingly at first glance.

### 4.2 Identity constants

```dart
static const int gcsSystemId = 255;       // 255 = conventional "ground station" system id
static const int gcsComponentId = 190;    // MAV_COMP_ID_MISSIONPLANNER
static const int targetSystem = 1;        // the flight controller's system id
static const int targetComponent = 1;     // the flight controller's component id
```

Every MAVLink message carries a system ID and component ID identifying its
sender (and, for targeted commands, its intended recipient). `255` is the
long-standing informal convention for "this is a ground control station, not
a vehicle"; ArduPilot vehicles default to system ID `1`. `190` borrows Mission
Planner's registered component ID purely so any MAVLink-aware tool sniffing
the link recognizes the traffic as coming from a GCS-class application.

### 4.3 Transport: a raw UDP socket, not a MAVLink-aware networking library

```dart
_socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
_socket!.listen(_onSocketEvent);
```

This is Dart's own `dart:io` UDP socket, bound to an **ephemeral local port**
(port `0` means "let the OS choose"). There is no MAVLink-specific networking
library involved; MAVLink only defines the byte format, not how you carry it,
so plain UDP is the transport and `dart_mavlink` only encodes/decodes the
bytes that go in each datagram.

**Learning the peer's address dynamically:** the code deliberately does not
hard-code where replies come from. `_onSocketEvent` runs on every incoming
datagram:

```dart
void _onSocketEvent(RawSocketEvent event) {
  if (event != RawSocketEvent.read) return;
  final dg = _socket?.receive();
  if (dg == null) return;
  _fcAddress = dg.address;   // relearn on every packet
  _fcPort = dg.port;
  _parser.parse(dg.data);
}
```

Every time a datagram arrives, `_fcAddress`/`_fcPort` are overwritten with
wherever it actually came from. This matters because of NAT and relay: on the
relay path, the packet the GCC receives has been re-sourced by the volunteer
node's NAT/forwarding, so the "reply-to" address the GCC should target may not
be exactly what the operator typed in Settings. Re-learning the source
address on every receive keeps outbound commands going to the right place
without the app needing to understand the network topology.

### 4.4 Connecting

```dart
Future<void> connect(String target) async {
  await disconnect();
  final (host, port) = _parseTarget(target);
  _fcAddress = (await InternetAddress.lookup(host)).first;
  _fcPort = port;
  _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  _socket!.listen(_onSocketEvent);
  _parser.stream.listen(_onFrame);
  _gcsHeartbeat = Timer.periodic(const Duration(seconds: 1), (_) => _sendGcsHeartbeat());
  _sendGcsHeartbeat();
}
```

`_parseTarget` (a small static helper) accepts `"host:port"` or
`"udp:host:port"`, defaulting to port `14550` if none is given
(`_parseTarget`, `mav_service.dart:144-152`). "Connect" for a UDP socket does
not mean a handshake occurs (UDP is connectionless); it means the app starts
sending its own heartbeat and starts listening for the FC's. There is no
proof of a live link until a heartbeat is actually received (section 4.6).

### 4.5 The GCS heartbeat: why the GCC also transmits, not just receives

```dart
void _sendGcsHeartbeat() {
  _send(Heartbeat(
    customMode: 0,
    type: mavTypeGcs,               // 6
    autopilot: mavAutopilotInvalid, // 8 (a GCS is not an autopilot)
    baseMode: 0,
    systemStatus: mavStateActive,   // 4
    mavlinkVersion: 3,
  ));
}
```

Sent once per second (`Timer.periodic(const Duration(seconds: 1), ...)`,
`mav_service.dart:131-133`). ArduPilot's GCS-failsafe logic, and some arming
pre-checks, expect to see a ground station heartbeat; sending one is standard
MAVLink GCS behavior, not something specific to this project's flight
controller, but it is required for reliable arming and for the FC to not
declare "GCS lost" failsafes.

### 4.6 The safety gate: `linkFresh`

This is the single most important piece of logic in the whole drone-control
feature.

```dart
static const Duration staleAfter = Duration(seconds: 2);

bool get linkFresh =>
    _lastHeartbeat != null &&
    DateTime.now().difference(_lastHeartbeat!) < staleAfter;
```

`_lastHeartbeat` is stamped only inside `_onFrame` when an incoming `Heartbeat`
message is decoded (`mav_service.dart:172-173`), and only then: only when the
**flight controller's** heartbeat arrives, not the GCC's own outgoing one.
`linkFresh` is `true` only while a real heartbeat from the FC has been seen in
the last 2 seconds. Every command-enabling widget in
`gcc_app/lib/screens/drone_control_screen.dart` reads `drone.linkFresh` (via
`DroneController`, section 6) and disables itself the instant it goes stale;
this is enforced at the UI layer, not the transport layer, so it is a policy
choice rather than a protocol feature: MAVLink itself does not prevent you
from sending a command into a dead link, the app's own gating logic does.
`FleetState`'s battery watchdog and the fleet manager's real-deploy sequence
also check `linkFresh` before issuing anything (`drone_controller.dart:85`,
`deploySequence`).

### 4.7 Receiving and decoding telemetry: `_onFrame`

```dart
void _onFrame(MavlinkFrame frame) {
  final m = frame.message;
  if (m is Heartbeat) { ... }
  else if (m is SysStatus) { ... }
  else if (m is GpsRawInt) { ... }
  else if (m is GlobalPositionInt) { ... }
  else if (m is Attitude) { ... }
  else if (m is Statustext) { ... }
  else if (m is CommandAck) { ... }
}
```

`frame.message` is already a typed Dart object (one of the dialect's
generated message classes), not raw bytes: `_dialect.parse(messageId,
payload)` inside the parser did that decoding. `_onFrame` is a straightforward
type-switch (Dart's `is` pattern) that copies the fields it cares about into
the app's own `Telemetry` object and republishes it on a broadcast stream.
Exact field mapping:

| MAVLink message | Fields read | Mapped to |
|---|---|---|
| `HEARTBEAT` | `baseMode & mavModeFlagSafetyArmed` (bit `0x80`/128) | `telemetry.armed` |
| | `customMode` | `telemetry.customMode` (an ArduCopter flight-mode number) |
| | `systemStatus` | `telemetry.systemStatus` |
| `SYS_STATUS` | `voltageBattery` (millivolts; `0xFFFF` = unknown) | `telemetry.batteryVolts` (divided by 1000.0) |
| | `batteryRemaining` (percent, `-1` = unknown) | `telemetry.batteryRemaining` |
| `GPS_RAW_INT` | `fixType` (>= 3 means 3D fix) | `telemetry.gpsFixType`, and `hasGpsFix` getter |
| | `satellitesVisible` | `telemetry.satellites` |
| `GLOBAL_POSITION_INT` | `lat`/`lon` (degrees * 1e7, an int32 fixed-point encoding) | `telemetry.lat`/`lon` (divided by 1e7) |
| | `relativeAlt` (millimetres) | `telemetry.relAltM` (divided by 1000.0) |
| `ATTITUDE` | `roll`/`pitch`/`yaw` (radians) | `telemetry.rollDeg` etc (multiplied by `180/pi`) |
| `STATUSTEXT` | `text` (a fixed-length byte array, NUL-padded), `severity` | pushed onto `onStatusText` stream as a `MavStatusText` |
| `COMMAND_ACK` | the whole message | pushed onto `onAck` stream, unmodified |

**Why `GPS_RAW_INT` and `GLOBAL_POSITION_INT` are both used:** they are
different MAVLink messages with different purposes. `GPS_RAW_INT` is the raw
GPS receiver's own report (fix type, satellite count, raw lat/lon from the
GPS chip). `GLOBAL_POSITION_INT` is the autopilot's *fused* estimate (its
internal state estimator, EKF, combining GPS with other sensors), and that is
where the app reads the working position. This code deliberately reads
fix-quality from the raw GPS message and position from the fused estimate.

**Integer-encoded coordinates (degrees * 1e7):** MAVLink represents latitude
and longitude as 32-bit integers scaled by 1e7 (so 1 unit = ~1.1 cm at the
equator) rather than as floats, because it keeps the wire format fixed-size
and avoids floating-point precision loss across different platforms. The app
converts back to a plain double by dividing by `1e7` on receive
(`mav_service.dart:188-189`) and multiplies by `1e7` and rounds to an int
before sending a location in the other direction (section 4.9,
`gotoLocation`).

### 4.8 Sending a frame: `_send`

```dart
void _send(MavlinkMessage message) {
  final s = _socket;
  final addr = _fcAddress;
  if (s == null || addr == null) return;
  final frame = MavlinkFrame.v2(_seq++ & 0xFF, gcsSystemId, gcsComponentId, message);
  s.send(frame.serialize(), addr, _fcPort);
}
```

Every outbound message goes through this one method. `_seq++ & 0xFF` is the
per-frame sequence number, wrapping at 256 as the MAVLink spec requires (the
receiver uses gaps in this counter to detect dropped packets, though this
project does not currently act on that). `frame.serialize()` (section 3.1)
produces the exact byte array that goes onto the UDP socket. If there is no
socket or no known FC address yet, the call is a silent no-op rather than a
thrown exception, which matters for the "always call disarm, even before a
connection is confirmed" safety pattern used by the force-disarm button.

### 4.9 The command set: every method, with exact MAVLink semantics

All commands are built through one private helper:

```dart
CommandLong _cmd(int command, {double p1 = 0, ..., double p7 = 0}) {
  return CommandLong(
    param1: p1, ..., param7: p7,
    command: command,
    targetSystem: targetSystem, targetComponent: targetComponent,
    confirmation: 0,
  );
}
```

`COMMAND_LONG` is MAVLink's generic "run this numbered command with up to 7
float parameters" message; it is how nearly all one-shot autopilot commands
are sent. `confirmation: 0` means "this is the first attempt, not a retry" (a
retried command would increment this so the receiver can dedupe).

| Method | MAVLink command | Command ID | Params used | What it does |
|---|---|---|---|---|
| `arm()` | `MAV_CMD_COMPONENT_ARM_DISARM` | 400 | `p1=1` | Arms the flight controller (normal arming checks apply) |
| `disarm({force})` | `MAV_CMD_COMPONENT_ARM_DISARM` | 400 | `p1=0`, `p2=21196` if `force` | Disarms; `p2=21196` is ArduPilot's documented "force" magic number that bypasses in-flight/safety checks. This is what the always-visible kill switch uses. |
| `motorTest(motor, ...)` | `MAV_CMD_DO_MOTOR_TEST` | 209 | `p1`=motor number (1-4), `p2=0` (throttle type = percent), `p3`=throttle percent (default 8), `p4`=seconds (default 3), `p5=0` (motor count, 0 = just this one) | Spins exactly one motor at low throttle for a short time. This is the headline bench demo: it proves the whole command pipeline without arming the whole vehicle for flight. |
| `setMode(copterMode)` | `MAV_CMD_DO_SET_MODE` | 176 | `p1 = MAV_MODE_FLAG_CUSTOM_MODE_ENABLED` (1), `p2 = copterMode` | Switches ArduCopter's flight mode (see `CopterMode` table below) |
| `returnToLaunch()` | `MAV_CMD_NAV_RETURN_TO_LAUNCH` | 20 | none | Commands the vehicle to fly home; works from any flight mode on ArduCopter. Used by both the manual "Recall" button and the fleet manager's automatic low-battery watchdog. |
| `land()` | (calls `setMode(CopterMode.land)`) | 176 (mode 9) | | Switches to LAND mode rather than issuing a separate NAV_LAND command |
| `takeoff(altM)` | `MAV_CMD_NAV_TAKEOFF` | 22 | `p7 = altM` | Commands a guided takeoff to the given altitude (metres). Requires GUIDED mode and armed first. |
| `gotoLocation(lat, lon, altM, ...)` | `MAV_CMD_DO_REPOSITION` | 192 | see below | Commands the vehicle to fly to a lat/lon while in GUIDED mode |

**Why `gotoLocation` uses `CommandInt`, not `CommandLong`:** latitude and
longitude need integer-degrees*1e7 precision (section 4.7), and
`COMMAND_LONG`'s parameters are all IEEE 754 floats, which cannot losslessly
hold an arbitrary 32-bit integer past about 24 significant bits. MAVLink's
answer is a second message, `COMMAND_INT`, which is identical in spirit
(a numbered command with parameters) but carries `x`/`y` as true `int32` and
`z` as a float, plus a coordinate `frame` field:

```dart
void gotoLocation(double lat, double lon, double altM, {double groundSpeed = -1}) {
  _send(CommandInt(
    param1: groundSpeed, // -1 = use ArduPilot's default speed
    param2: 0,           // MAV_DO_REPOSITION_FLAGS (none set)
    param3: 0,
    param4: double.nan,  // yaw: NaN means "keep current heading"
    x: (lat * 1e7).round(),
    y: (lon * 1e7).round(),
    z: altM,
    command: mavCmdDoReposition,   // 192
    targetSystem: targetSystem, targetComponent: targetComponent,
    frame: mavFrameGlobalRelativeAlt,   // altitude is measured relative to home
    current: 0, autocontinue: 0,
  ));
}
```

`mavFrameGlobalRelativeAlt` tells the FC "the altitude I gave you is metres
above your home/launch point," as opposed to above sea level or above the
current position; this is the frame ArduPilot expects for guided reposition
commands in normal operation.

### 4.10 `CopterMode`: ArduPilot's flight-mode numbers

```dart
class CopterMode {
  static const int stabilize = 0;
  static const int guided = 4;
  static const int loiter = 5;
  static const int rtl = 6;
  static const int land = 9;
  static const Map<int, String> names = {
    0: 'STABILIZE', 1: 'ACRO', 2: 'ALT_HOLD', 3: 'AUTO', 4: 'GUIDED',
    5: 'LOITER', 6: 'RTL', 7: 'CIRCLE', 9: 'LAND', 16: 'POSHOLD',
  };
}
```

These numbers are **not part of the generic MAVLink specification**; they are
ArduPilot's own custom-mode enumeration, carried inside the generic
`HEARTBEAT.custom_mode` field (MAVLink's `HEARTBEAT` message has a
`custom_mode` integer field specifically so each autopilot can define its own
mode numbering without needing a MAVLink protocol change). A PX4 autopilot
would use a completely different numbering in the same field. This is why the
dialect is `ardupilotmega` and why this table would be wrong for any other
flight-controller firmware.

### 4.11 `MAV_RESULT`: how a command's outcome is reported

Every `COMMAND_LONG`/`COMMAND_INT` should be answered by the FC with a
`COMMAND_ACK` message (`command`, `result`, optional `progress`). The `result`
field is a `MAV_RESULT` enum (from `dart_mavlink/lib/dialects/ardupilotmega.dart:4025-4075`):

| Value | Name | Meaning |
|---|---|---|
| 0 | `MAV_RESULT_ACCEPTED` | valid and executed |
| 1 | `MAV_RESULT_TEMPORARILY_REJECTED` | valid, but can't run right now (e.g. no GPS lock yet); retry later |
| 2 | `MAV_RESULT_DENIED` | invalid parameters; retrying identically will not help |
| 3 | `MAV_RESULT_UNSUPPORTED` | command not recognized |
| 4 | `MAV_RESULT_FAILED` | valid, but execution failed |
| 5 | `MAV_RESULT_IN_PROGRESS` | executing; more acks may follow |
| 6 | `MAV_RESULT_CANCELLED` | cancelled |
| 7 | `MAV_RESULT_COMMAND_LONG_ONLY` | must be sent as `COMMAND_LONG` |
| 8 | `MAV_RESULT_COMMAND_INT_ONLY` | must be sent as `COMMAND_INT` |

The UI (`_AckLine` in `drone_control_screen.dart:353-375`) only distinguishes
`0` (accepted, shown green) from everything else (shown orange, with the raw
numeric result), which is intentionally simple for an operator-facing
display; the full enum above is what that number means if you need to
diagnose a rejected command.

## 5. `DroneController`: the app-facing bridge

File: `gcc_app/lib/state/drone_controller.dart`. This class does not know
anything about MAVLink bytes; it exists purely to adapt `MavService`'s
stream-based API into a Flutter `ChangeNotifier` that the UI (via `provider`)
can watch, and to add one small piece of orchestration.

- It subscribes to `MavService`'s three streams in its constructor
  (`onTelemetry`, `onStatusText`, `onAck`) and calls `notifyListeners()` on
  each, so any widget watching `DroneController` rebuilds automatically when
  new telemetry, a status text, or a command ack arrives.
- It keeps `statusLog`, a capped (40-entry) rolling list of FC status
  messages, for the "Flight controller messages" panel in the UI.
- It runs its own independent 1-second `Timer.periodic` (separate from
  `MavService`'s heartbeat-send timer) purely so that the **heartbeat-age
  display and the `linkFresh` gate re-render every second even when no new
  MAVLink packet has arrived**, since `linkFresh`'s truth value changes purely
  as a function of wall-clock time, not of any new event.
- It exposes every `MavService` command method one-to-one
  (`arm`, `disarm`, `forceDisarm`, `motorTest`, `setMode`, `land`,
  `returnToLaunch`, `takeoff`, `gotoLocation`), plus one composite method:

```dart
Future<void> deploySequence(double lat, double lon, double altM) async {
  if (!linkFresh) return;                          // never command a dead link
  setMode(CopterMode.guided);
  await Future<void>.delayed(const Duration(milliseconds: 400));
  arm();
  await Future<void>.delayed(const Duration(milliseconds: 800));
  takeoff(altM);
  await Future<void>.delayed(const Duration(milliseconds: 800));
  gotoLocation(lat, lon, altM);
}
```

This encodes the real ArduPilot arming/flight prerequisite order: a vehicle
must be in **GUIDED** mode before it will accept a `MAV_CMD_NAV_TAKEOFF`, and
it must be **armed** before it will take off at all. The fixed millisecond
delays between steps are not a MAVLink requirement; they exist to give the
flight controller's internal state machine time to settle between commands
on real hardware (mode changes and arming both involve internal checks that
are not instantaneous), and are a pragmatic choice rather than a protocol
rule. This method is invoked by the fleet manager, not the manual Drone Control
screen (section 7).

## 6. The system-drone side: `mav_gateway.py` (Python)

File: `mavlink_gateway/mav_gateway.py`. Runs on DRONE_S's Raspberry Pi as
`rescue-mesh-mavgw.service` (installed and enabled only when the node's
config sets `DRONE_CONTROL=true`, which only `deploy/nodes/drone_s.conf`
does). It is a single-file, dependency-light program (`pyserial` +
`pymavlink`, both pure/standard enough to need no compiled extensions on a
Pi) doing two jobs in one process.

### 6.1 Library: `pymavlink`, and why it is used differently here

`pymavlink` is normally used the way `dart_mavlink` is used above: you feed it
bytes, it hands you fully decoded, typed message objects, and you build
messages with generated constructor functions. This gateway uses only the
**decode half** of that (the "telemetry tap," section 6.3), and only as a
read-only side channel:

```python
self.mav = mavutil.mavlink.MAVLink(None)   # no file/stream backing; used purely as a decoder
self.mav.robust_parsing = True
...
msgs = self.mav.parse_buffer(data) or []
```

`robust_parsing = True` tells pymavlink's parser to resynchronize past
corrupt or partial data rather than raising an exception (comment in the code:
"a bad byte must not kill the bridge," `mav_gateway.py:159`). This gateway
never uses pymavlink to *construct* messages, because it never needs to: the
control path (section 6.2) forwards bytes it never decodes at all.

### 6.2 The control bridge: byte-for-byte, both directions

```python
def _on_serial(self):
    data = self.ser.read(4096)
    if not data: return
    self._forward_to_clients(data)          # 1. raw bytes straight out to every known GCS
    msgs = self.mav.parse_buffer(data) or [] # 2. ALSO decode a copy for the telemetry tap
    for m in msgs: self._tap(m)

def _on_udp(self):
    data, addr = self.sock.recvfrom(4096)
    self.clients[addr] = time.monotonic()    # remember this GCS as "active"
    if self.ser is not None:
        self.ser.write(data)                 # raw bytes straight to the FC, unmodified
```

Two things to notice:

1. **The forwarding path never calls into pymavlink's decoder at all.**
   `data` goes from `self.ser.read()` to `sock.sendto()`, or from
   `sock.recvfrom()` to `self.ser.write()`, with nothing but a Python
   `bytes` object passed through. A command byte stream that arrived
   corrupted, malformed, or from a version of MAVLink this gateway does not
   understand would still be forwarded exactly as received; the gateway is
   not a MAVLink-aware router, it is a dumb pipe with a read-only tap on one
   side. This is the literal implementation of the "raw bytes, never altered"
   design rule from section 1.
2. **`self.clients` is a multi-GCS address table with a timeout.**
   `_forward_to_clients` sends the FC's outgoing bytes to *every* UDP
   address that has sent this gateway a packet within the last
   `CLIENT_EXPIRY` seconds (default 30). This is how the gateway supports
   both the direct GCC and a relayed GCC (or, in principle, any number of
   simultaneous listeners) without either side needing to declare who else is
   connected: whoever last sent a packet gets added to the fan-out list, and
   goes quiet if they stop sending (their own periodic GCS heartbeat is what
   keeps them "active" in this table).

### 6.3 The telemetry tap: read-only, and why it exists at all

DRONE_S is the one node in the fleet with **no aux module** (no ESP32-C3, no
INA3221 battery monitor, no separate GPS chip, chapter 7 of the handbook). Its
only source of GPS position, battery voltage, and accurate time is the flight
controller itself, over the exact same serial link the control bridge already
uses. Rather than adding a second serial reader, the gateway parses a *copy*
of the same bytes it is already forwarding:

```python
def _tap(self, m):
    t = m.get_type()
    if t == "GPS_RAW_INT":
        fix = 1 if m.fix_type >= 3 else 0
        self.state["gps"] = {"lat": ..., "lon": ..., "fix": fix,
                             "sats": m.satellites_visible, "hdop": ...}
    elif t == "SYS_STATUS":
        self.state["battery"]["a_v"] = None if m.voltage_battery in (0, 65535) \
            else m.voltage_battery / 1000.0
        self.state["battery"]["a_ma"] = None if m.current_battery == -1 \
            else m.current_battery * 10.0
    elif t == "SYSTEM_TIME":
        self._maybe_set_clock(m.time_unix_usec)
```

This is the same three messages `MavService` decodes on the GCC side
(`GPS_RAW_INT`, `SYS_STATUS`) plus one more the GCC does not need,
`SYSTEM_TIME`, used to set the Pi's own system clock:

```python
def _maybe_set_clock(self, unix_usec):
    if unix_usec < 1_500_000_000_000_000:   # reject boot-time zero/garbage (before mid-2017)
        return
    due = (not self.clock_synced_once or
           time.monotonic() - self.last_clock_sync >= CLOCK_RESYNC_INTERVAL)  # default 3600s
    if not due: return
    utc = datetime.fromtimestamp(unix_usec / 1e6, tz=timezone.utc)
    cmd = [p.replace("{utc}", utc.strftime("%Y-%m-%dT%H:%M:%SZ"))
           for p in shlex.split(DATE_SET_CMD)]   # "sudo -n /bin/date -u -s {utc}"
    subprocess.run(cmd, check=True, capture_output=True, timeout=10)
```

The Pi has no RTC and no internet/NTP in the field, so once, and then hourly,
the gateway sets the OS clock from the FC's GPS-derived time, using the exact
same narrow `sudo -n /bin/date -u -s` mechanism the aux-module bridge uses on
every other node (`backend/aux_bridge.py`, `documentation/06_BACKEND.md`).
This keeps DRONE_S's clock trustworthy for message timestamps even without an
aux module, and every clock change is written to the shared audit log
(`audit()` in `mav_gateway.py:77-84`).

The tapped state is written to `AUX_STATE_FILE`
(`/run/rescue-mesh/aux_state.json` by default) in the same JSON schema the
real aux bridge uses (`backend/aux_state.py`), so `GET /health`
(`backend/api.py`) reads DRONE_S's position/battery/clock-source through the
exact same code path it uses for every other node, regardless of whether the
data came from a real aux module or from this gateway's telemetry tap. The
`gcc_app`'s Nodes and Live Ops screens (`documentation/08_GCC_APP.md`) are
therefore unaware of, and do not need to special-case, DRONE_S's missing aux
hardware.

### 6.4 Reliability: reconnect loop and clean shutdown behavior

```python
def run(self):
    self.open_socket()          # bind UDP once
    while True:
        self.open_serial()      # blocks with exponential backoff until the FC is present
        try:
            while True:
                rlist, _, _ = select.select([self.ser.fileno(), self.sock.fileno()], [], [], 1.0)
                if self.ser.fileno() in rlist: self._on_serial()
                if self.sock.fileno() in rlist: self._on_udp()
                self._flush_state()
        except ConnectionError:
            # serial read/write failed: mark fc_link false, close, loop back to open_serial()
```

`select.select` (a single-threaded, OS-level "wake me when either the serial
port or the UDP socket has data" call) is the whole event loop; there is no
asyncio, no threads. `open_serial()` retries with exponential backoff (2s,
4s, 8s... capped at 30s) if the USB/UART device is missing or errors,
so a flight-controller reboot or a loose cable does not kill the service; the
gateway just waits and reopens. A `ConnectionError` raised from a failed
serial read/write drops back to the outer loop and reopens serial from
scratch, updating `fc_link: false` in the health state so `/health`
immediately reflects that DRONE_S has lost its FC link, distinct from losing
its Wi-Fi/mesh link.

If `FC_SERIAL` is empty (a node with no flight controller configured), the
gateway prints a message and exits cleanly (`main()`,
`mav_gateway.py:275-280`) rather than erroring; the systemd unit is only
installed on DRONE_S in the first place, but this guard makes the script
itself self-describing and harmless if ever run on a non-drone node by
mistake.

## 7. The fleet manager's real-drone path

File: `gcc_app/lib/state/fleet_state.dart`. This is covered at a system level
in `documentation/11_SYSTEM_DRONE.md`; here is exactly how it drives the
MAVLink layer above.

`FleetState` is constructed with two callbacks
(`gcc_app/lib/main.dart:49-57`):

```dart
FleetState(
  onRealDeploy: (d) => drone.deploySequence(d.targetLat, d.targetLon, 30),
  onRealRecall: (_) => drone.returnToLaunch(),
);
```

When a placement is deployed with "command over MAVLink" checked (the
`FleetBoard` deploy dialog, `gcc_app/lib/screens/fleet_board.dart`) **and**
`DroneController.linkFresh` is true at that moment, `FleetState.deploy(...,
real: true)` calls `onRealDeploy`, which runs the exact `deploySequence`
described in section 5 (GUIDED, arm, takeoff to 30 m, reposition to the
placement's lat/lon). If the link is not fresh, the deploy is silently
downgraded to a DEMO simulation instead; there is no "real deploy" path that
can fire without a live heartbeat.

**The battery watchdog**, which is the automatic safety behavior that makes a
"real" deployment more than a fire-and-forget sequence, is fed from the GCC's
own decoded telemetry, not from a separate poll:

```dart
void updateReal(String label, {double? lat, double? lon,
    double? batteryVolts, int cellCount = 3, bool armed = false}) {
  for (final d in deployed.where((d) => d.label == label && d.real)) {
    d.lastHeard = DateTime.now();
    if (lat != null && lon != null) { d.curLat = lat; d.curLon = lon; }
    if (d.phase == FleetPhase.launchRequested && armed) d.phase = FleetPhase.enroute;
    if (batteryVolts != null && cellCount > 0) {
      final perCell = batteryVolts / cellCount;
      if (perCell <= perCellThresholdV && d.phase.isActive) {   // default 3.5 V/cell
        d.note = 'battery watchdog: ${perCell.toStringAsFixed(2)} V/cell, RTL';
        recall(d);   // -> onRealRecall -> drone.returnToLaunch()
      }
    }
  }
}
```

`FleetBoard`'s widget calls `fleet.updateReal(...)` on every `DroneController`
telemetry update (it listens to the same `onTelemetry`/heartbeat-driven
rebuild that the Drone Control screen does), passing in
`telemetry.lat/lon`, `telemetry.batteryVolts`, and an estimated cell count
(`(t.batteryVolts! / 3.7).round()`, assuming a nominal 3.7 V/cell lithium
chemistry, confidence Low, see `fleet_board.dart`). So the real-mode battery
watchdog is not a second connection to the flight controller: it is the same
`MavService`/`DroneController` telemetry stream, re-consumed by
`FleetState` and turned into an automatic `MAV_CMD_NAV_RETURN_TO_LAUNCH` the
instant the estimated per-cell voltage crosses the threshold, exactly the
same command the manual "Recall" button sends.

## 8. Network security around this channel

MAVLink itself carries no built-in authentication in the mode this project
uses (see section 3.3 on why signed MAVLink is not viable with the current
Dart library). The control channel is therefore protected entirely at the
network layer, by firewall rules applied per node
(`documentation/05_SECURITY.md`, plane 4):

**On DRONE_S** (`deploy/files/nftables-drone-s.nft`):

```
table inet rescue_mesh {
    chain input {
        type filter hook input priority -5; policy accept;
        ip saddr 10.42.0.0/24 udp dport 14550 accept        # anyone on DRONE_S's own AP
        ip saddr { 10.99.0.1, 10.99.0.2 } udp dport 14550 accept   # only A and B on the mesh
        udp dport 14550 drop                                 # everything else: dropped
    }
}
```

So the gateway's UDP port only ever *receives* packets that already passed
this filter: a direct client on DRONE_S's own `RESCUE_S` subnet, or a
forwarded packet whose mesh-side source is specifically DRONE_A or DRONE_B
(nothing wider on the mesh can reach it).

**On a volunteer node** (`deploy/files/nftables-volunteer.nft`), the relay
path is equally narrow:

```
chain forward {
    ip saddr 10.42.0.0/24 ip daddr 10.99.0.3 udp dport 14550 accept   # only toward DRONE_S:14550
    ip saddr 10.42.0.0/24 ip daddr 10.99.0.0/24 drop                  # nothing else toward the mesh
}
```

A GCC on a volunteer's user AP can forward MAVLink toward DRONE_S's gateway
port and literally nothing else on the mesh subnet; every other destination
on `10.99.0.0/24` is dropped at the volunteer's own firewall before it ever
leaves that node. This is file 09's "plane 4 layer 1" control: network
isolation compensates for the absence of message-level signing (layer 2,
recorded as future work).

## 9. Timing and reliability constants, all in one place

| Constant | Value | Where | Meaning |
|---|---|---|---|
| `MavService.staleAfter` | 2 s | `mav_service.dart:79` | heartbeat age beyond which `linkFresh` goes false and all commands disable |
| GCS heartbeat send interval | 1 s | `mav_service.dart:131` | how often the GCC announces itself to the FC |
| `DroneController` UI refresh tick | 1 s | `drone_controller.dart:54` | re-render cadence for the age display, independent of new packets |
| `deploySequence` inter-step delay | 400 ms (mode->arm), 800 ms (arm->takeoff), 800 ms (takeoff->goto) | `drone_controller.dart:87,89,91` | lets the FC's internal state machine settle between steps |
| `FleetState.perCellThresholdV` | 3.5 V/cell | `fleet_state.dart` | battery watchdog RTL trigger (standard LiPo low-voltage practice, confidence Moderate) |
| Gateway UDP client expiry | 30 s | `mav_gateway.py`, `CLIENT_EXPIRY` | how long a GCS stays in the fan-out table after its last packet |
| Gateway clock resync interval | 3600 s | `mav_gateway.py`, `CLOCK_RESYNC_INTERVAL` | how often the Pi's clock is re-set from FC GPS time |
| Serial reconnect backoff | 2s, doubling, capped at 30s | `mav_gateway.py`, `open_serial()` | reconnect pacing if the FC serial link drops |
| MAVLink UDP port | 14550 | both sides, `deploy/nodes/drone_s.conf` (`MAVLINK_UDP_PORT`) | the conventional MAVLink-over-UDP port; not project-specific |

## 10. Testing this without any hardware

Both ends of the link have hardware-free automated tests, which is how this
whole feature was verified before any physical flight controller was on the
bench.

- **GCC side:** `gcc_app/test/mav_service_test.dart`. It builds real
  `dart_mavlink` message objects, serializes them with
  `MavlinkFrame.v2(...).serialize()`, feeds the bytes back through a fresh
  `MavlinkParser`, and asserts the round-tripped frame matches (proving the
  wire encoding for heartbeat, arm, force-disarm, motor test, takeoff,
  reposition, and RTL are exactly what section 4.9's table claims). A
  separate group feeds hand-built `Heartbeat`/`GpsRawInt`/`SysStatus` frames
  straight into `MavService.ingest()` (a `@visibleForTesting` seam,
  `mav_service.dart:167-168`) to prove the heartbeat gate and telemetry
  decode work with no socket at all.
- **Gateway side:** `tools/mavgw_pty_test.py`. It creates a pseudo-terminal
  (`pty`) to stand in for the real serial device, plus a real UDP socket to
  stand in for the GCC, and asserts byte-exact forwarding in both directions
  plus correct GPS/battery/clock tap behavior. Nine checks, run with
  `backend/.venv/bin/python tools/mavgw_pty_test.py`.
- **Fleet manager:** `gcc_app/test/fleet_state_test.dart` unit-tests the
  reserve-battery math, the state machine transitions, and (via a fake
  `onRealRecall` callback) that the per-cell watchdog fires exactly once at
  the right voltage.

See `documentation/15_TESTING.md` for how these fit into the full test suite.

## 11. Quick reference: everything in one glance

**Libraries used:**

| Side | Language | MAVLink library | Role |
|---|---|---|---|
| GCC | Dart | `dart_mavlink` (`^0.1.0`, `gcc_app/pubspec.yaml`) | encode outgoing commands, decode incoming telemetry/acks over UDP |
| Gateway | Python | `pymavlink` (`mavlink_gateway/requirements.txt`) | decode-only, read-only telemetry tap on a copy of the forwarded bytes |
| Gateway | Python | `pyserial` | raw serial I/O to the flight controller |

**Protocol:** MAVLink 2, dialect `ardupilotmega`, no message signing (not
implemented on either side; a residual, documented risk).

**Transports chained together for one command:** Dart UDP socket -> Wi-Fi ->
(optionally: volunteer node NAT/forward over the 2.4 GHz IBSS mesh) -> Python
UDP socket -> Python serial write -> flight controller's serial receiver.
Same MAVLink bytes, unmodified, across every hop.

**The one rule that governs everything above it:** no command is ever sent,
and no command is ever considered safe to have been sent, unless a MAVLink
heartbeat from the flight controller has been received within the last two
seconds. That single boolean, `linkFresh`, is threaded through the manual
Drone Control screen, the fleet manager's real-deploy path, and the battery
watchdog, and it is the actual safety mechanism behind the project's
props-off, bench-only flight policy (`documentation/11_SYSTEM_DRONE.md`).
