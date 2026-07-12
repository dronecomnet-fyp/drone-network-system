/// Live contract test: RescueMeshClient against a REAL backend node
/// started from backend/ (api.py + http_app.py on loopback), plus the
/// TLS pinning proof (file 09 T9.1 local equivalent): a client holding
/// the fleet CA connects; a client holding the wrong CA fails closed.
///
/// Run from shared_dart/: dart test
/// Needs the backend venv (backend/.venv) and openssl on PATH.
library;

import 'dart:convert';
import 'dart:io';

import 'package:rescue_mesh_shared/rescue_mesh_shared.dart';
import 'package:test/test.dart';

const apiPort = 18543;
const httpPort = 18091;
const tlsPort = 18544;
const hqKey = 'it_hq_key';
const rescueKey = 'it_rescue_key';

late Directory work;
late String backendDir;
late String py;
final procs = <Process>[];

Future<Process> _startBackend(String script, String envFile) async {
  final p = await Process.start(py, ['$backendDir/$script'],
      workingDirectory: work.path,
      environment: {'NODE_ENV_FILE': envFile});
  procs.add(p);
  // Drain output so the child never blocks on a full pipe.
  p.stdout.listen((_) {});
  p.stderr.listen((_) {});
  return p;
}

Future<void> _waitUp(String url, {String? caPem}) async {
  final client = RescueMeshClient(
      baseUrl: url, fleetCaPem: caPem, allowInsecure: caPem == null);
  for (var i = 0; i < 60; i++) {
    try {
      await client.getHealth();
      client.close();
      return;
    } catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }
  client.close();
  fail('backend at $url never came up');
}

String _env(Map<String, String> extra) {
  final base = {
    'NODE_ID': 'DRONE_IT',
    'USER_AP_SSID': 'RESCUE_IT',
    'NODE_MASTER_SECRET': 'shared_dart_it_secret',
    'RESCUE_API_KEY': rescueKey,
    'HQ_API_KEY': hqKey,
    'API_HOST': '127.0.0.1',
    'HTTP_HOST': '127.0.0.1',
    'AUX_SERIAL': '',
    'RATE_LIMIT_COUNT': '100',
    'GLOBAL_WRITE_LIMIT_COUNT': '500',
    'LOGIN_RATE_LIMIT_COUNT': '50',
    ...extra,
  };
  return base.entries.map((e) => '${e.key}=${e.value}').join('\n');
}

void main() {
  setUpAll(() async {
    work = await Directory.systemTemp.createTemp('shared_dart_it_');
    final repo = Directory.current.parent.path;
    backendDir = '$repo/backend';
    py = '$backendDir/.venv/bin/python';

    // Plain-HTTP node for the contract tests.
    final envPlain = File('${work.path}/plain.env')
      ..writeAsStringSync(_env({
        'API_PORT': '$apiPort',
        'HTTP_PORT': '$httpPort',
        'DB_FILE': '${work.path}/plain.db',
        'AUDIT_LOG_FILE': '${work.path}/plain_audit.log',
        'AUX_STATE_FILE': '${work.path}/plain_aux.json',
        'API_TLS_ENABLED': 'false',
      }));
    await _startBackend('api.py', envPlain.path);
    await _startBackend('http_app.py', envPlain.path);
    await _waitUp('http://127.0.0.1:$apiPort');
  });

  tearDownAll(() async {
    for (final p in procs) {
      p.kill(ProcessSignal.sigkill);
    }
  });

  test('full contract round trip with break-glass key and PIN token', () async {
    final hq = RescueMeshClient(
        baseUrl: 'http://127.0.0.1:$apiPort', apiKey: hqKey);

    // health
    final health = await hq.getHealth();
    expect(health.nodeId, 'DRONE_IT');
    expect(health.aux, 'absent');
    expect(health.clockSource, 'relative');

    // personnel issuance: one-time PIN
    final issued = await hq.createPersonnel('Contract Tester');
    expect(issued.pin.length, 6);
    final listing = await hq.getPersonnel();
    expect(listing.any((p) => p.personnelId == issued.personnelId), isTrue);

    // PIN login installs the token
    final rescuer =
        RescueMeshClient(baseUrl: 'http://127.0.0.1:$apiPort');
    final session = await rescuer.login(issued.personnelId, issued.pin);
    expect(session.role, 'RESCUE_TEAM');
    expect(session.isExpired, isFalse);

    // victim message arrives via the portal plane; rescuer sees and
    // claims it with token identity
    final portal = await HttpClient()
        .postUrl(Uri.parse('http://127.0.0.1:$httpPort/message'));
    portal.headers.contentType = ContentType.json;
    portal.write(jsonEncode({
      'content': 'contract test victim message',
      'user_lat': 6.91,
      'user_lon': 79.86,
    }));
    final portalResp = await portal.close();
    expect(portalResp.statusCode, 200);
    final portalBody =
        jsonDecode(await portalResp.transform(utf8.decoder).join());
    final msgId = portalBody['msg_id'] as String;

    final msgs = await rescuer.getMessages();
    final mine = msgs.firstWhere((m) => m.msgId == msgId);
    expect(mine.status, 'NEW');
    expect(mine.timeSource, 'relative');
    expect(mine.hasUserLocation, isTrue);

    final claim = await rescuer.claimMessage(msgId);
    expect(claim['claimed_by'], issued.personnelId);

    // gs uplink: sender comes from token identity
    await rescuer.postGsUplink('bridge out at km 4', locationLat: 6.95);
    final gs = await hq.getGsMessages();
    expect(gs.first.sender, issued.personnelId);

    // announcements: HQ posts, rescuer token reads
    await hq.postAnnouncement('IT title', 'IT body', priority: 'HIGH');
    final anns = await rescuer.getAnnouncements();
    expect(anns.any((a) => a.title == 'IT title'), isTrue);

    // checkin via portal, read back on the rescue plane
    final chk = await HttpClient()
        .postUrl(Uri.parse('http://127.0.0.1:$httpPort/checkin'));
    chk.headers.contentType = ContentType.json;
    chk.write(jsonEncode({
      'device_id': 'it-dev-1',
      'sos': false,
      'points': [
        {'lat': 6.90, 'lon': 79.80, 'accuracy': 5.0, 'recorded_at': '2026-07-12T01:00:00Z'}
      ],
    }));
    expect((await chk.close()).statusCode, 200);
    final checkins = await rescuer.getCheckins();
    expect(checkins.any((c) => c.deviceId == 'it-dev-1'), isTrue);

    // revoke kills the token (403, surfaced as isAuthFailure)
    await hq.revokePersonnel(issued.personnelId);
    try {
      await rescuer.getMessages();
      fail('revoked token must be rejected');
    } on ApiException catch (e) {
      expect(e.isAuthFailure, isTrue);
    }

    rescuer.close();
    hq.close();
  });

  test('wrong PIN raises ApiException 401', () async {
    final c = RescueMeshClient(baseUrl: 'http://127.0.0.1:$apiPort');
    try {
      await c.login('R-000', '000000');
      fail('login with unknown id must fail');
    } on ApiException catch (e) {
      expect(e.statusCode, 401);
    }
    c.close();
  });

  test('emergency-app checkin upload with SOS (file 06 / file 02 2.5)',
      () async {
    // The emergency app hits the PUBLIC victim plane (port 80), no auth.
    final public = RescueMeshClient(baseUrl: 'http://127.0.0.1:$httpPort');
    final result = await public.postCheckin(
      deviceId: 'emg-app-1',
      sos: true,
      sosText: 'stranded on the roof',
      points: [
        {'lat': 6.90, 'lon': 79.80, 'accuracy': 8.0,
          'recorded_at': '2026-07-12T01:00:00Z'},
        {'lat': 6.91, 'lon': 79.81, 'accuracy': 6.0,
          'recorded_at': '2026-07-12T13:00:00Z'},
      ],
    );
    expect(result['stored'], 2);
    expect(result['sos_msg_id'], isNotNull);
    public.close();

    // The SOS also entered the rescue message queue.
    final hq = RescueMeshClient(
        baseUrl: 'http://127.0.0.1:$apiPort', apiKey: hqKey);
    final msgs = await hq.getMessages();
    expect(msgs.any((m) => m.content.contains('stranded on the roof')), isTrue);
    // and the stored points are readable on the rescue plane
    final checkins = await hq.getCheckins();
    expect(checkins.where((c) => c.deviceId == 'emg-app-1').length, 2);
    hq.close();
  });

  group('TLS pinning (file 09 T9.1 local drill)', () {
    late String fleetCaPem;
    late String wrongCaPem;

    setUpAll(() async {
      // Fleet CA + node cert with SAN IP:127.0.0.1, same recipe as
      // deploy/setup_node.sh; plus a second, unrelated CA (the evil twin).
      Future<void> run(List<String> args) async {
        final r = await Process.run('openssl', args, workingDirectory: work.path);
        if (r.exitCode != 0) fail('openssl ${args.first}: ${r.stderr}');
      }

      // Exactly the deploy recipe (make_fleet_ca.sh + setup_node.sh).
      // Dart's BoringSSL is stricter than curl: without keyUsage on the
      // CA and keyUsage + extendedKeyUsage=serverAuth on the leaf, the
      // handshake fails CERTIFICATE_VERIFY_FAILED even for a trusted
      // root. Verified empirically 2026-07-12; keep in sync with deploy/.
      for (final name in ['fleet', 'wrong']) {
        await run([
          'req', '-x509', '-newkey', 'ec', '-pkeyopt',
          'ec_paramgen_curve:prime256v1', '-keyout', '${name}_ca.key',
          '-out', '${name}_ca.crt', '-days', '30', '-nodes',
          '-subj', '/CN=$name-ca',
          '-addext', 'basicConstraints=critical,CA:TRUE,pathlen:0',
          '-addext', 'keyUsage=critical,keyCertSign,cRLSign',
        ]);
      }
      await run([
        'req', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:prime256v1',
        '-nodes', '-keyout', 'node_key.pem', '-out', 'node.csr',
        '-subj', '/CN=DRONE_IT',
      ]);
      File('${work.path}/ext.cnf').writeAsStringSync(
          'basicConstraints=CA:FALSE\n'
          'keyUsage=digitalSignature,keyEncipherment\n'
          'extendedKeyUsage=serverAuth\n'
          'subjectAltName=IP:127.0.0.1\n');
      await run([
        'x509', '-req', '-in', 'node.csr', '-CA', 'fleet_ca.crt',
        '-CAkey', 'fleet_ca.key', '-CAcreateserial', '-days', '30',
        '-extfile', 'ext.cnf', '-out', 'node_cert.pem',
      ]);
      fleetCaPem = File('${work.path}/fleet_ca.crt').readAsStringSync();
      wrongCaPem = File('${work.path}/wrong_ca.crt').readAsStringSync();

      final envTls = File('${work.path}/tls.env')
        ..writeAsStringSync(_env({
          'API_PORT': '$tlsPort',
          'HTTP_PORT': '18092',
          'DB_FILE': '${work.path}/tls.db',
          'AUDIT_LOG_FILE': '${work.path}/tls_audit.log',
          'AUX_STATE_FILE': '${work.path}/tls_aux.json',
          'API_TLS_ENABLED': 'true',
          'API_TLS_CERT': '${work.path}/node_cert.pem',
          'API_TLS_KEY': '${work.path}/node_key.pem',
        }));
      await _startBackend('api.py', envTls.path);
      await _waitUp('https://127.0.0.1:$tlsPort', caPem: fleetCaPem);
    });

    test('client with the fleet CA connects', () async {
      final c = RescueMeshClient(
          baseUrl: 'https://127.0.0.1:$tlsPort', fleetCaPem: fleetCaPem);
      final h = await c.getHealth();
      expect(h.nodeId, 'DRONE_IT');
      c.close();
    });

    test('client with the WRONG CA fails closed', () async {
      final c = RescueMeshClient(
          baseUrl: 'https://127.0.0.1:$tlsPort', fleetCaPem: wrongCaPem);
      await expectLater(c.getHealth(), throwsA(isA<HandshakeException>()));
      c.close();
    });

    test('client with no CA and no insecure flag fails closed', () async {
      final c = RescueMeshClient(baseUrl: 'https://127.0.0.1:$tlsPort');
      await expectLater(c.getHealth(), throwsA(isA<HandshakeException>()));
      c.close();
    });
  });
}
