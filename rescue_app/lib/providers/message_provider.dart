import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rescue_mesh_shared/rescue_mesh_shared.dart' as shared;

import '../models/api_error_model.dart';
import '../models/message_model.dart';
import '../services/api_service.dart';
import '../services/message_crypto_service.dart';

class MessageProvider with ChangeNotifier {
  static const Duration _normalPollDelay = Duration(seconds: 5);
  static const Duration _maxPollDelay = Duration(minutes: 2);

  /// Invoked when the backend rejects our credentials (expired token or
  /// revoked personnel): AuthProvider clears the session and routes to
  /// the login screen with the reason (file 05 task 5.1).
  final void Function(ApiException error)? onCredentialFailure;

  List<Message> _messages = [];
  List<GSMessage> _gsMessages = [];
  List<shared.Announcement> _announcements = [];
  bool _isLoading = false;
  String? _error;
  ApiException? _apiError;
  Timer? _pollTimer;
  Duration _currentPollDelay = _normalPollDelay;
  bool _pollPausedForAuth = false;

  List<Message> get messages => _messages;
  List<GSMessage> get gsMessages => _gsMessages;
  List<shared.Announcement> get announcements => _announcements;
  bool get isLoading => _isLoading;
  String? get error => _error;
  ApiException? get apiError => _apiError;
  bool get requiresCredentialUpdate =>
      _apiError?.isCredentialFailure ?? false;

  MessageProvider({this.onCredentialFailure}) {
    _startPolling();
  }

  void _startPolling() {
    _scheduleNextPoll(immediate: true);
  }

  void _scheduleNextPoll({bool immediate = false}) {
    _pollTimer?.cancel();
    if (_pollPausedForAuth) {
      return;
    }

    final delay = immediate ? Duration.zero : _currentPollDelay;
    _pollTimer = Timer(delay, () async {
      await fetchMessages(fromPoller: true);
    });
  }

  void _setError(Object error) {
    if (error is ApiException) {
      _apiError = error;
      _error = error.message;
      if (error.type == ApiErrorType.sessionExpired ||
          error.type == ApiErrorType.revoked) {
        onCredentialFailure?.call(error);
      }
    } else {
      _apiError = ApiException(
        type: ApiErrorType.unknown,
        message: error.toString(),
      );
      _error = error.toString();
    }
  }

  void _handlePollingOutcomeSuccess() {
    _currentPollDelay = _normalPollDelay;
    _pollPausedForAuth = false;
    _scheduleNextPoll();
  }

  void _handlePollingOutcomeFailure() {
    final type = _apiError?.type;
    if (_apiError?.isCredentialFailure ?? false) {
      _pollPausedForAuth = true;
      _pollTimer?.cancel();
      return;
    }

    if (type == ApiErrorType.rateLimited ||
        type == ApiErrorType.serviceUnavailable ||
        type == ApiErrorType.networkError ||
        type == ApiErrorType.pinningFailed ||
        type == ApiErrorType.timeout ||
        type == ApiErrorType.serverError) {
      final nextSeconds = (_currentPollDelay.inSeconds * 2)
          .clamp(_normalPollDelay.inSeconds, _maxPollDelay.inSeconds);
      _currentPollDelay = Duration(seconds: nextSeconds);
    }

    _scheduleNextPoll();
  }

  Future<void> fetchMessages({bool fromPoller = false}) async {
    if (_isLoading) {
      return;
    }

    _isLoading = true;
    if (!fromPoller) {
      _error = null;
      _apiError = null;
    }
    notifyListeners();

    try {
      final fetchedMessages = await APIService.getMessages();
      _messages = await MessageCryptoService.decryptMessages(fetchedMessages);
      _error = null;
      _apiError = null;
      _handlePollingOutcomeSuccess();
    } catch (e) {
      _setError(e);
      debugPrint('[ERROR] Failed to fetch messages: $_error');
      _handlePollingOutcomeFailure();
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> claimMessage(String msgId) async {
    try {
      final claimedBy = await APIService.claimMessage(msgId);
      final index = _messages.indexWhere((m) => m.msgId == msgId);
      if (index != -1) {
        _messages[index] = _messages[index].copyWith(
          status: 'CLAIMED',
          claimedBy: claimedBy,
        );
        _error = null;
        _apiError = null;
        notifyListeners();
      }
    } catch (e) {
      _setError(e);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> submitGSUplink(
    String content,
    String sender, {
    double? locationLat,
    double? locationLon,
    double? locationAccuracy,
  }) async {
    try {
      final success = await APIService.submitGSUplink(
        content,
        sender,
        locationLat: locationLat,
        locationLon: locationLon,
        locationAccuracy: locationAccuracy,
      );
      if (success) {
        _error = null;
        _apiError = null;
        await fetchGSMessages();
      }
    } catch (e) {
      _setError(e);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> fetchGSMessages() async {
    try {
      final fetchedGSMessages = await APIService.getGSMessages();
      _gsMessages = fetchedGSMessages;
      _error = null;
      _apiError = null;
    } catch (e) {
      _setError(e);
      debugPrint('[ERROR] Failed to fetch GS messages: $_error');
    }
    notifyListeners();
  }

  /// Real announcements from file 02's /announcements endpoints (the
  /// Phase 1 screen showed gs_messages as a stand-in; file 05 task 5.3).
  Future<void> fetchAnnouncements() async {
    try {
      _announcements = await APIService.getAnnouncements();
      _error = null;
      _apiError = null;
    } catch (e) {
      _setError(e);
      debugPrint('[ERROR] Failed to fetch announcements: $_error');
    }
    notifyListeners();
  }

  void resumePollingAfterCredentialsUpdate() {
    _pollPausedForAuth = false;
    _currentPollDelay = _normalPollDelay;
    _scheduleNextPoll(immediate: true);
    notifyListeners();
  }

  List<String> getActiveNodes() {
    final nodes = <String>{};
    for (final msg in _messages) {
      nodes.add(msg.nodeId);
    }
    return nodes.toList();
  }

  int getNewMessageCount() => _messages.where((m) => m.isNew).length;

  int getClaimedMessageCount() => _messages.where((m) => m.isClaimed).length;

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
