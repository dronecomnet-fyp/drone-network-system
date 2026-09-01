import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rescue_mesh_shared/rescue_mesh_shared.dart' as shared;

import '../services/api_service.dart';

class RescueAudioPlayerWidget extends StatefulWidget {
  final shared.MediaAttachment attachment;

  const RescueAudioPlayerWidget({
    super.key,
    required this.attachment,
  });

  @override
  State<RescueAudioPlayerWidget> createState() => _RescueAudioPlayerWidgetState();
}

class _RescueAudioPlayerWidgetState extends State<RescueAudioPlayerWidget> {
  late final AudioPlayer _player;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  String? _localFilePath;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();

    _player.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() => _isPlaying = state == PlayerState.playing);
      }
    });

    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });

    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });

    _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _player.pause();
      return;
    }

    try {
      if (_localFilePath == null) {
        setState(() => _isLoading = true);
        final bytes = await APIService.getMediaBytes(widget.attachment.id);
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/rescue_audio_${widget.attachment.id}.m4a');
        await file.writeAsBytes(bytes);
        _localFilePath = file.path;
        await _player.setSourceDeviceFile(_localFilePath!);
      }
      setState(() => _isLoading = false);
      await _player.resume();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to play audio: $e')),
        );
      }
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isLoading)
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          else
            IconButton(
              iconSize: 32,
              icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
              color: const Color(0xFF1D4ED8),
              onPressed: _togglePlay,
            ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                children: [
                  Icon(Icons.mic, size: 14, color: Color(0xFF1D4ED8)),
                  SizedBox(width: 4),
                  Text(
                    'Victim Voice Note',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E3A8A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                _position > Duration.zero
                    ? '${_formatDuration(_position)} / ${_formatDuration(_duration)}'
                    : (_duration > Duration.zero
                        ? _formatDuration(_duration)
                        : '${widget.attachment.sizeBytes ~/ 1024} KB'),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class RescueImageViewerWidget extends StatefulWidget {
  final shared.MediaAttachment attachment;

  const RescueImageViewerWidget({
    super.key,
    required this.attachment,
  });

  @override
  State<RescueImageViewerWidget> createState() => _RescueImageViewerWidgetState();
}

class _RescueImageViewerWidgetState extends State<RescueImageViewerWidget> {
  Uint8List? _imageBytes;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final bytes = await APIService.getMediaBytes(widget.attachment.id);
      if (!mounted) return;
      setState(() {
        _imageBytes = Uint8List.fromList(bytes);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        width: 140,
        height: 100,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_error != null || _imageBytes == null) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image, size: 16, color: Colors.red),
            SizedBox(width: 6),
            Text('Image unavailable', style: TextStyle(fontSize: 12, color: Colors.red)),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _FullScreenBytesViewer(
              imageBytes: _imageBytes!,
              filename: widget.attachment.filename,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: const BoxConstraints(maxWidth: 240, maxHeight: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.memory(
          _imageBytes!,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class _FullScreenBytesViewer extends StatelessWidget {
  final Uint8List imageBytes;
  final String filename;

  const _FullScreenBytesViewer({required this.imageBytes, required this.filename});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(filename, style: const TextStyle(color: Colors.white, fontSize: 16)),
      ),
      body: Center(
        child: InteractiveViewer(
          panEnabled: true,
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.memory(imageBytes, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
