/// Is this laptop actually on the internet right now?
///
/// The GCC has two completely different network relationships and used to
/// conflate them. It talks to a drone node over the local Wi-Fi (no internet
/// involved, and that is the normal field state), and separately it needs
/// real internet for the HQ-phase online features: fetching unit specs from
/// the product site and asking the AI advisor for a deployment. Before this
/// there was no notion of "online" at all; the app only discovered the
/// truth by failing a request, so joining a home Wi-Fi changed nothing that
/// the operator could see.
///
/// Why not ping: ICMP needs raw sockets (root on desktop) and Dart has no
/// ICMP client, so "ping google" is not actually available to us. The
/// standard substitute, and what phones and laptops genuinely use, is a
/// captive-portal probe: an HTTP request to a URL whose only job is to
/// return "204 No Content".
///
///   204 + empty body -> real internet
///   any other reply  -> something answered, but it is not the internet.
///                       That is a captive portal, which is exactly what a
///                       drone AP looks like, so we can name that state
///                       instead of calling it "offline".
///   no reply at all  -> offline
///
/// Deliberately plain HTTP: a portal can only be spotted by letting it
/// intercept, and HTTPS would just fail the handshake and hide the reason.
/// Nothing sensitive is sent, and the response is never trusted for
/// anything except this classification.
///
/// Several independent providers are probed at once and the first useful
/// answer wins, so one blocked or down provider cannot produce a false
/// "offline". All of it is time-boxed and cheap, because at a disaster site
/// this will fail every single time by design and must cost nothing.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

enum NetStatus {
  /// Not checked yet this session.
  unknown,

  /// A 204 came back: genuinely online.
  online,

  /// Something answered but not with 204: a captive portal or a hijacking
  /// DNS. On a drone AP this is the expected, correct answer.
  portal,

  /// Nothing answered. Normal in the field.
  offline,
}

class ConnectivityService extends ChangeNotifier {
  ConnectivityService({this.autoStart = true}) {
    if (autoStart) {
      check();
      _timer = Timer.periodic(_interval, (_) => check());
    }
  }

  final bool autoStart;

  /// Quiet enough to be invisible on battery, frequent enough that walking
  /// back into range updates the badge without the operator doing anything.
  static const Duration _interval = Duration(seconds: 30);
  static const Duration _timeout = Duration(seconds: 4);

  /// Well-known "generate_204" endpoints. Multiple providers on purpose:
  /// any single one may be blocked on a given network or in a given
  /// country, and that must not read as "no internet".
  ///
  /// Every one of these MUST answer 204-with-no-body on success. Endpoints
  /// that signal success with "200 plus a magic body" (Apple's
  /// hotspot-detect, Microsoft's connecttest) are deliberately excluded: a
  /// captive portal also answers 200, so telling them apart means trusting
  /// the body text, and a wrong guess there reports the field as online.
  static const List<String> probeUrls = [
    'http://clients3.google.com/generate_204',
    'http://cp.cloudflare.com/generate_204',
    'http://connectivitycheck.gstatic.com/generate_204',
  ];

  Timer? _timer;
  bool _checking = false;
  NetStatus _status = NetStatus.unknown;
  DateTime? _lastChecked;

  NetStatus get status => _status;
  bool get checking => _checking;
  DateTime? get lastChecked => _lastChecked;
  bool get isOnline => _status == NetStatus.online;

  String get label {
    switch (_status) {
      case NetStatus.online:
        return 'internet';
      case NetStatus.portal:
        return 'no internet (portal)';
      case NetStatus.offline:
        return 'no internet';
      case NetStatus.unknown:
        return 'checking';
    }
  }

  /// One-line explanation for the Settings screen. Says what it MEANS for
  /// the operator, not just what the probe saw.
  String get detail {
    switch (_status) {
      case NetStatus.online:
        return 'Online. Unit spec lookup and the AI advisor will work.';
      case NetStatus.portal:
        return 'Joined a network that wants a sign-in page, so there is no '
            'usable internet. A drone AP looks exactly like this, which is '
            'normal in the field.';
      case NetStatus.offline:
        return 'No internet. Expected at a deployment; the online features '
            'are an HQ-phase thing and everything else works offline.';
      case NetStatus.unknown:
        return 'Not checked yet.';
    }
  }

  @override
  void notifyListeners() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (hasListeners) super.notifyListeners();
    });
  }

  Future<NetStatus> check() async {
    if (_checking) return _status;
    _checking = true;
    notifyListeners();

    NetStatus result;
    try {
      result = await _probeAll();
    } catch (_) {
      result = NetStatus.offline;
    }

    _status = result;
    _lastChecked = DateTime.now();
    _checking = false;
    notifyListeners();
    return _status;
  }

  /// Race every provider. A 204 anywhere is proof of internet, so return on
  /// the first one instead of waiting for the slowest. If none says 204 but
  /// something replied, we are behind a portal.
  Future<NetStatus> _probeAll() async {
    final completer = Completer<NetStatus>();
    var pending = probeUrls.length;
    var sawAnyReply = false;

    for (final url in probeUrls) {
      // ignore: unawaited_futures
      _probe(url).then((r) {
        if (r == NetStatus.online && !completer.isCompleted) {
          completer.complete(NetStatus.online);
          return;
        }
        if (r == NetStatus.portal) sawAnyReply = true;
        pending--;
        if (pending == 0 && !completer.isCompleted) {
          completer.complete(sawAnyReply ? NetStatus.portal : NetStatus.offline);
        }
      });
    }

    return completer.future.timeout(
      _timeout + const Duration(seconds: 2),
      onTimeout: () => sawAnyReply ? NetStatus.portal : NetStatus.offline,
    );
  }

  Future<NetStatus> _probe(String url) async {
    final client = HttpClient()
      ..connectionTimeout = _timeout
      // A portal redirects; we want to SEE that, not follow it.
      ..userAgent = 'rescue-mesh-gcc';
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(_timeout);
      req.followRedirects = false;
      final resp = await req.close().timeout(_timeout);
      final body = await resp
          .take(1)
          .fold<int>(0, (n, chunk) => n + chunk.length)
          .timeout(_timeout);
      // Only an empty 204 counts. Anything else answered us, so we are on
      // SOME network, just not one with usable internet.
      if (resp.statusCode == 204 && body == 0) return NetStatus.online;
      return NetStatus.portal;
    } on TimeoutException {
      return NetStatus.offline;
    } on SocketException {
      return NetStatus.offline;
    } on HandshakeException {
      return NetStatus.offline;
    } catch (_) {
      return NetStatus.offline;
    } finally {
      client.close(force: true);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
