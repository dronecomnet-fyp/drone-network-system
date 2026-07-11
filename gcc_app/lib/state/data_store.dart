/// DataStore: polls the connected node every 5 s (file 04: same cadence
/// as the Phase 1 dashboard) and exposes the datasets with a last-updated
/// timestamp each, so every screen can show data age honestly.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:rescue_mesh_shared/rescue_mesh_shared.dart';

import 'app_state.dart';

class Dataset<T> {
  List<T> items = [];
  DateTime? lastUpdated;

  Duration? get age =>
      lastUpdated == null ? null : DateTime.now().difference(lastUpdated!);
}

class DataStore extends ChangeNotifier {
  final AppState app;
  Timer? _timer;
  bool _polling = false;

  final messages = Dataset<Message>();
  final gsMessages = Dataset<GsMessage>();
  final announcements = Dataset<Announcement>();
  final personnel = Dataset<Personnel>();
  final checkins = Dataset<Checkin>();
  NodeHealth? health;
  DateTime? healthUpdated;

  String? lastError;
  bool get isConnected =>
      healthUpdated != null &&
      DateTime.now().difference(healthUpdated!) < const Duration(seconds: 15);

  DataStore(this.app);

  void start({Duration interval = const Duration(seconds: 5)}) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => poll());
    poll();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  bool get _hasCredentials => app.isLoggedIn || app.apiKey.isNotEmpty;

  Future<void> poll() async {
    if (_polling) return;
    _polling = true;
    try {
      final c = app.client;
      // Health is public: poll it even before login so the operator sees
      // the node come into range.
      try {
        health = await c.getHealth();
        healthUpdated = DateTime.now();
        lastError = null;
      } on SocketException {
        lastError = 'Node unreachable (join a RESCUE_x WiFi)';
      } on HandshakeException {
        lastError = 'TLS rejected: check the fleet CA in Settings';
      } on ApiException catch (e) {
        lastError = 'Node error: ${e.detail}';
      }

      if (_hasCredentials) {
        await _pull(messages, c.getMessages);
        await _pull(gsMessages, c.getGsMessages);
        await _pull(announcements, c.getAnnouncements);
        await _pull(checkins, c.getCheckins);
        if (app.isHq) {
          await _pull(personnel, c.getPersonnel);
        }
      }
    } finally {
      _polling = false;
      notifyListeners();
    }
  }

  Future<void> _pull<T>(Dataset<T> ds, Future<List<T>> Function() fetch) async {
    try {
      ds.items = await fetch();
      ds.lastUpdated = DateTime.now();
    } on ApiException catch (e) {
      if (e.isAuthFailure) {
        lastError = 'Auth rejected: ${e.detail}';
      }
      // keep the stale dataset; its age display tells the story
    } on SocketException {
      // node dropped mid-poll; health branch reports it
    } on HandshakeException {
      // reported by the health branch
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}

String formatAge(Duration? age) {
  if (age == null) return 'never';
  if (age.inSeconds < 10) return 'just now';
  if (age.inSeconds < 60) return '${age.inSeconds}s ago';
  if (age.inMinutes < 60) return '${age.inMinutes}m ago';
  return '${age.inHours}h ${age.inMinutes % 60}m ago';
}
