/// Local distribution server (task E): turns the ground laptop into a
/// pop-up download point at a disaster site where there is no internet.
///
/// The operator copies the field bundle onto the laptop beforehand (from a
/// USB stick): the rescue-app APK, offline region map files (.mbtiles), and
/// anything else personnel need. On site, everyone joins the same local
/// Wi-Fi (a cheap travel router, or the laptop's own hotspot). The operator
/// points this server at that folder and starts it; the GCC shows a link
/// and a QR code. A rescuer scans the QR, opens a plain web page in their
/// phone browser, and taps to download the APK and maps. No internet, no
/// app store, no cables.
///
/// This is a ChangeNotifier held ABOVE the screens (a root provider) so the
/// server keeps running while the operator uses other tabs; the shell only
/// keeps the selected screen mounted.
///
/// Scope: this serves ONLY the chosen folder's top-level files over plain
/// HTTP on the local network. That is intentional (public installers and
/// map files, handed out on purpose); there is no upload path and filenames
/// are validated so a request cannot escape the folder.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// One file offered for download.
class SharedFile {
  const SharedFile({required this.name, required this.sizeBytes});

  final String name;
  final int sizeBytes;

  String get humanSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    if (sizeBytes < 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class DistributionServer extends ChangeNotifier {
  static const int defaultPort = 8080;

  HttpServer? _server;
  String? _folderPath;
  int _port = defaultPort;
  bool _running = false;
  String? _error;
  List<SharedFile> _files = const [];
  List<String> _urls = const [];

  String? get folderPath => _folderPath;
  int get port => _port;
  bool get running => _running;
  String? get error => _error;
  List<SharedFile> get files => _files;

  /// One URL per usable LAN address, e.g. http://10.42.0.1:8080/. The first
  /// entry is the best guess to show as the primary link and QR code.
  List<String> get urls => _urls;
  String? get primaryUrl => _urls.isEmpty ? null : _urls.first;

  /// Point the server at a folder and read its top-level files. Safe to call
  /// whether or not the server is running; refreshes the shared list.
  Future<void> setFolder(String path) async {
    _folderPath = path;
    _error = null;
    await _rescan();
    notifyListeners();
  }

  /// Re-read the folder (the operator may have copied more files across).
  Future<void> refresh() async {
    await _rescan();
    notifyListeners();
  }

  Future<void> _rescan() async {
    final path = _folderPath;
    if (path == null) {
      _files = const [];
      return;
    }
    try {
      final dir = Directory(path);
      final entries = await dir.list(followLinks: false).toList();
      final files = <SharedFile>[];
      for (final e in entries) {
        if (e is File) {
          final name = _basename(e.path);
          if (name.startsWith('.')) continue; // skip hidden/system files
          files.add(SharedFile(name: name, sizeBytes: await e.length()));
        }
      }
      files.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _files = files;
    } catch (e) {
      _error = 'Could not read folder: $e';
      _files = const [];
    }
  }

  Future<void> start({int? port}) async {
    if (_running) return;
    final path = _folderPath;
    if (path == null) {
      _error = 'Choose a folder to share first.';
      notifyListeners();
      return;
    }
    _port = port ?? _port;
    try {
      await _rescan();
      final server =
          await HttpServer.bind(InternetAddress.anyIPv4, _port, shared: true);
      _server = server;
      _running = true;
      _error = null;
      _urls = await _lanUrls();
      server.listen(_handle, onError: (Object e) {
        _error = 'Server error: $e';
        notifyListeners();
      });
    } catch (e) {
      _running = false;
      _error = 'Could not start on port $_port: $e';
    }
    notifyListeners();
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _running = false;
    _urls = const [];
    notifyListeners();
  }

  @override
  Future<void> dispose() async {
    await _server?.close(force: true);
    super.dispose();
  }

  // --- request handling ------------------------------------------------------

  Future<void> _handle(HttpRequest req) async {
    try {
      final segments = req.uri.pathSegments;
      if (segments.isEmpty) {
        await _serveIndex(req);
        return;
      }
      if (segments.length == 2 && segments.first == 'files') {
        await _serveFile(req, segments[1]);
        return;
      }
      req.response.statusCode = HttpStatus.notFound;
      req.response.headers.contentType = ContentType.text;
      req.response.write('Not found');
      await req.response.close();
    } catch (_) {
      try {
        req.response.statusCode = HttpStatus.internalServerError;
        await req.response.close();
      } catch (_) {
        // Client already gone; nothing to do.
      }
    }
  }

  Future<void> _serveIndex(HttpRequest req) async {
    req.response.statusCode = HttpStatus.ok;
    req.response.headers.contentType = ContentType.html;
    req.response.write(_indexHtml());
    await req.response.close();
  }

  Future<void> _serveFile(HttpRequest req, String rawName) async {
    final name = Uri.decodeComponent(rawName);
    final folder = _folderPath;
    // Reject anything that could escape the chosen folder.
    if (folder == null ||
        name.isEmpty ||
        name.contains('/') ||
        name.contains(r'\') ||
        name.contains('..')) {
      req.response.statusCode = HttpStatus.forbidden;
      await req.response.close();
      return;
    }
    final file = File('$folder${Platform.pathSeparator}$name');
    if (!await file.exists()) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    req.response.statusCode = HttpStatus.ok;
    req.response.headers.contentType = _contentTypeFor(name);
    req.response.headers.set('Content-Length', await file.length());
    req.response.headers
        .set('Content-Disposition', 'attachment; filename="$name"');
    await req.response.addStream(file.openRead());
    await req.response.close();
  }

  ContentType _contentTypeFor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.apk')) {
      return ContentType('application', 'vnd.android.package-archive');
    }
    if (lower.endsWith('.html') || lower.endsWith('.htm')) {
      return ContentType.html;
    }
    if (lower.endsWith('.txt') || lower.endsWith('.md')) {
      return ContentType.text;
    }
    // .mbtiles, .zip, .pdf, and anything else: a generic binary download.
    return ContentType.binary;
  }

  String _indexHtml() {
    final rows = StringBuffer();
    if (_files.isEmpty) {
      rows.write('<p>No files are being shared yet.</p>');
    } else {
      rows.write('<ul class="files">');
      for (final f in _files) {
        final href = '/files/${Uri.encodeComponent(f.name)}';
        rows.write(
          '<li><a href="$href" download>${_escapeHtml(f.name)}</a>'
          '<span class="size">${f.humanSize}</span></li>',
        );
      }
      rows.write('</ul>');
    }
    // Self-contained page: phones at a disaster site have no internet, so no
    // external CSS or fonts. Kept deliberately plain.
    return '''
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Rescue Mesh downloads</title>
<style>
  body { font-family: system-ui, sans-serif; margin: 0; background:#f5f5f5;
         color:#222; }
  header { background:#b91c1c; color:#fff; padding:16px 20px; }
  header h1 { margin:0; font-size:1.2rem; }
  main { padding:16px 20px; max-width:640px; }
  p.hint { color:#555; }
  ul.files { list-style:none; padding:0; }
  ul.files li { background:#fff; border:1px solid #e2e2e2; border-radius:8px;
                padding:14px 16px; margin-bottom:10px; display:flex;
                justify-content:space-between; align-items:center; }
  ul.files a { font-weight:600; color:#b91c1c; text-decoration:none;
               font-size:1.05rem; word-break:break-all; }
  ul.files .size { color:#777; font-size:0.85rem; margin-left:12px;
                   white-space:nowrap; }
  footer { padding:8px 20px 24px; color:#999; font-size:0.8rem; }
</style>
</head>
<body>
<header><h1>Rescue Mesh field downloads</h1></header>
<main>
<p class="hint">Tap a file to download it to this phone. To install the
APK you may need to allow "install from unknown sources" once.</p>
$rows
</main>
<footer>Served locally by the Ground Control Center. No internet needed.</footer>
</body>
</html>
''';
  }

  Future<List<String>> _lanUrls() async {
    final urls = <String>[];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          urls.add('http://${addr.address}:$_port/');
        }
      }
    } catch (_) {
      // Fall through: no interfaces enumerable.
    }
    if (urls.isEmpty) {
      urls.add('http://localhost:$_port/');
    }
    return urls;
  }

  String _basename(String p) {
    final norm = p.replaceAll('\\', '/');
    final idx = norm.lastIndexOf('/');
    return idx < 0 ? norm : norm.substring(idx + 1);
  }

  String _escapeHtml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
