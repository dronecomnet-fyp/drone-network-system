/// The victim's conversation with the rescue team (CHANGES.md item 37).
///
/// Deliberately built as the messaging screen everyone already knows:
/// bubbles, right for you, left for them, a tick under yours. Testers
/// asked for that idiom because it costs nothing to learn at the worst
/// moment of someone's life.
///
/// The one place it must NOT copy those apps is timing. Their ticks mean
/// seconds. This network is delay tolerant: a message can sit on the phone
/// until a drone flies over, then sit on the drone until it meets another
/// node. So there is a third state they do not have, "waiting for a
/// drone", and the wording under each tick says what is actually true
/// rather than leaving the icon to imply it.
///
/// It also never says help is coming. Two ticks means a rescuer has READ
/// it, and a victim who stopped trying other things because of an icon
/// would be badly served by us.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rescue_mesh_shared/rescue_mesh_shared.dart' as shared;

import '../constants.dart';
import '../state/app_controller.dart';
import '../widgets/media_widgets.dart';

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({super.key});

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  /// Only polls while this screen is open and only while on a drone AP.
  /// The victim's battery may be the thing that gets them found.
  static const Duration _refreshEvery = Duration(seconds: 20);

  Timer? _timer;
  shared.Conversation? _convo;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(_refreshEvery, (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final c = context.read<AppController>();
    final client = shared.RescueMeshClient(
        baseUrl: kDroneBaseUrl, timeout: const Duration(seconds: 8));
    try {
      final convo = await client.getMyConversation(c.deviceId);
      if (!mounted) return;
      setState(() {
        _convo = convo;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      // Keep whatever we last managed to read. Out of range is the normal
      // case here, not a failure worth throwing the screen away over.
      setState(() {
        _loading = false;
        _error = 'Not connected to a drone right now.';
      });
    } finally {
      client.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = _convo?.entries ?? const <shared.ConversationEntry>[];
    return Scaffold(
      backgroundColor: const Color(0xFFEFEAE2),
      appBar: AppBar(
        title: Row(
          children: [
            const CircleAvatar(
              backgroundColor: Colors.white24,
              child: Icon(Icons.health_and_safety, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Rescue Team', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text('Official Emergency Support', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.9))),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_error != null) _OfflineStrip(message: _error!),
          Expanded(
            child: _loading && entries.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : entries.isEmpty
                    ? const _EmptyThread()
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: entries.length,
                        itemBuilder: (_, i) => _Bubble(entry: entries[i]),
                      ),
          ),
          const _ThreadFooter(),
        ],
      ),
    );
  }
}

class _OfflineStrip extends StatelessWidget {
  const _OfflineStrip({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.amber.shade100,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 1, offset: Offset(0, 1))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.wifi_off, size: 16, color: Colors.amber.shade900),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '$message Messages will send when a drone passes.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.amber.shade900, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      );
}

class _EmptyThread extends StatelessWidget {
  const _EmptyThread();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.all(28),
        child: Center(
          child: Text(
            'Nothing here yet.\n\nWhen you send an SOS it will appear here, '
            'and any reply from the rescue team will show up underneath it.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, height: 1.5),
          ),
        ),
      );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.entry});
  final shared.ConversationEntry entry;

  String get _time {
    final t = DateTime.tryParse(entry.at);
    if (t == null) return '';
    final l = t.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:'
        '${l.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final mine = entry.fromVictim;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        decoration: BoxDecoration(
          color: mine ? const Color(0xFFE7FFDB) : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(mine ? 14 : 2),
            bottomRight: Radius.circular(mine ? 2 : 14),
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 1,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!mine)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  entry.sender.isEmpty ? 'Rescue team' : entry.sender,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade900),
                ),
              ),
            if (entry.hasAttachments) ...[
              for (final att in entry.attachments)
                if (att.isAudio)
                  AudioBubblePlayer(attachment: att, isSender: mine)
                else if (att.isImage)
                  ImageBubbleViewer(attachment: att),
              const SizedBox(height: 4),
            ],
            if (entry.body.isNotEmpty)
              Text(entry.body, style: const TextStyle(fontSize: 17)),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_time,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                if (mine) ...[
                  const SizedBox(width: 6),
                  _Ticks(state: entry.state),
                ],
              ],
            ),
            if (mine) _StateLine(state: entry.state),
          ],
        ),
      ),
    );
  }
}

/// The tick glyph. Colour alone never carries the meaning: the wording
/// underneath says it too, for colour-blind users and bright sunlight.
class _Ticks extends StatelessWidget {
  const _Ticks({required this.state});
  final shared.DeliveryState state;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case shared.DeliveryState.waiting:
        return Icon(Icons.schedule, size: 15, color: Colors.grey.shade600);
      case shared.DeliveryState.onDrone:
        return Icon(Icons.check, size: 16, color: Colors.grey.shade700);
      case shared.DeliveryState.seen:
        return const Icon(Icons.done_all, size: 16, color: Color(0xFF16A34A));
    }
  }
}

class _StateLine extends StatelessWidget {
  const _StateLine({required this.state});
  final shared.DeliveryState state;

  @override
  Widget build(BuildContext context) {
    final (text, colour) = switch (state) {
      // Says where the message physically is, because the honest answer to
      // "why has nothing happened" is usually "no drone has come yet".
      shared.DeliveryState.waiting => (
          'Waiting for a drone to come near',
          Colors.grey.shade700
        ),
      shared.DeliveryState.onDrone => (
          'The drone has your message',
          Colors.grey.shade700
        ),
      // Carefully NOT "help is on the way": claimed means read, and a
      // victim who stops seeking other help because of a tick would be
      // badly served.
      shared.DeliveryState.seen => (
          'A rescue team member has read this',
          const Color(0xFF15803D)
        ),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(text, style: TextStyle(fontSize: 10, color: colour.withOpacity(0.7), fontStyle: FontStyle.italic)),
    );
  }
}

class _ThreadFooter extends StatelessWidget {
  const _ThreadFooter();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.yellow.shade100,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 1, offset: Offset(0, 1))],
          ),
          child: Text(
            'Messages can take a while to arrive. Both drones and rescuers '
            'move around, so nothing is lost if it is not instant.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.brown.shade800),
          ),
        ),
      );
}
