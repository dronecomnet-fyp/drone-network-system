import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class MediaService {
  final AudioRecorder _audioRecorder = AudioRecorder();
  final ImagePicker _picker = ImagePicker();

  bool _isRecording = false;
  String? _currentRecordingPath;
  DateTime? _recordingStartTime;

  bool get isRecording => _isRecording;
  Duration get recordingDuration => _recordingStartTime == null
      ? Duration.zero
      : DateTime.now().difference(_recordingStartTime!);

  Future<bool> startVoiceRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getTemporaryDirectory();
        final path = '${dir.path}/sos_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
        _currentRecordingPath = path;

        const config = RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 32000,
          sampleRate: 22050,
          numChannels: 1,
        );

        await _audioRecorder.start(config, path: path);
        _isRecording = true;
        _recordingStartTime = DateTime.now();
        return true;
      }
      return false;
    } catch (_) {
      _isRecording = false;
      return false;
    }
  }

  Future<String?> stopVoiceRecording() async {
    try {
      if (_isRecording) {
        final path = await _audioRecorder.stop();
        _isRecording = false;
        _recordingStartTime = null;
        return path ?? _currentRecordingPath;
      }
      return null;
    } catch (_) {
      _isRecording = false;
      _recordingStartTime = null;
      return null;
    }
  }

  Future<void> cancelVoiceRecording() async {
    try {
      if (_isRecording) {
        await _audioRecorder.stop();
      }
      if (_currentRecordingPath != null) {
        final f = File(_currentRecordingPath!);
        if (await f.exists()) {
          await f.delete();
        }
      }
    } catch (_) {
    } finally {
      _isRecording = false;
      _recordingStartTime = null;
      _currentRecordingPath = null;
    }
  }

  Future<XFile?> pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 75,
      );
      return picked;
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _audioRecorder.dispose();
  }
}
