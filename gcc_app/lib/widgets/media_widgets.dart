import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rescue_mesh_shared/rescue_mesh_shared.dart';

import '../state/app_state.dart';

class GccAudioPlayerWidget extends StatefulWidget {
  final MediaAttachment attachment;

  const GccAudioPlayerWidget({
    super.key,
    required this.attachment,
  });

  @override
  State<GccAudioPlayerWidget> createState() => _GccAudioPlayerWidgetState();
}

class _GccAudioPlayerWidgetState extends State<GccAudioPlayerWidget> {
  late final AudioPlayer _player;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isLoading = false;
  bool _isSourceSet = false;

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
      if (!_isSourceSet) {
        setState(() => _isLoading = true);
        final client = context.read<AppState>().client;
        final bytes = await client.getMediaBytes(widget.attachment.id);
        await _player.setSourceBytes(Uint8List.fromList(bytes));
        _isSourceSet = true;
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isLoading)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            IconButton(
              iconSize: 28,
              icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
              color: Colors.cyanAccent,
              onPressed: _togglePlay,
            ),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                children: [
                  Icon(Icons.mic, size: 13, color: Colors.cyanAccent),
                  SizedBox(width: 4),
                  Text(
                    'Voice Note',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.cyanAccent,
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
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class GccImageViewerWidget extends StatefulWidget {
  final MediaAttachment attachment;

  const GccImageViewerWidget({
    super.key,
    required this.attachment,
  });

  @override
  State<GccImageViewerWidget> createState() => _GccImageViewerWidgetState();
}

class _GccImageViewerWidgetState extends State<GccImageViewerWidget> {
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
      final client = context.read<AppState>().client;
      final bytes = await client.getMediaBytes(widget.attachment.id);
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
        width: 120,
        height: 80,
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_error != null || _imageBytes == null) {
      return Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.red.shade900.withOpacity(0.3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image, size: 14, color: Colors.redAccent),
            SizedBox(width: 4),
            Text('Image unavailable', style: TextStyle(fontSize: 11, color: Colors.redAccent)),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        showDialog(
          context: context,
          builder: (_) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(24),
            child: Stack(
              alignment: Alignment.topRight,
              children: [
                Center(
                  child: InteractiveViewer(
                    panEnabled: true,
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: Image.memory(_imageBytes!, fit: BoxFit.contain),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: const BoxConstraints(maxWidth: 220, maxHeight: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF334155)),
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
