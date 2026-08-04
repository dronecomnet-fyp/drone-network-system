/// Connected flow (file 06 screen 4): on connectivity to the drone, POST
/// the stored points to /checkin (marking them uploaded locally), then
/// show the SOS composer which posts a checkin with sos=true so it enters
/// the rescue message queue (file 02 behavior).
///
/// Rebuilt for field backlog #11 to match the captive portal: the victim
/// TAPS what they need instead of typing it, and location is shared unless
/// they opt out. Two reasons this matters more than it looks:
///
///  1. Typing is the thing people cannot do here. Wet hands, a cracked
///     screen, a language the keyboard is not set to, panic. Every tester
///     comment about the portal applied equally to this screen, which had
///     an empty text box as its only input.
///  2. The options come FROM THE NODE, so the app and the portal offer the
///     same list. If the operator edits the options for this mission, a
///     victim with the app and a victim with a browser report the same
///     vocabulary, and the rescue team's tally means something.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rescue_mesh_shared/rescue_mesh_shared.dart' as shared;

import '../constants.dart';
import '../services/upload_service.dart';
import '../state/app_controller.dart';
import 'conversation_screen.dart';

class ConnectedScreen extends StatefulWidget {
  const ConnectedScreen({super.key});

  @override
  State<ConnectedScreen> createState() => _ConnectedScreenState();
}

class _ConnectedScreenState extends State<ConnectedScreen> {
  final _noteController = TextEditingController();
  bool _uploading = false;
  bool _sending = false;
  String? _uploadMessage;
  bool _sosSent = false;

  /// Stock until the node answers. Never null, so there is always
  /// something to tap even against a node running older code.
  shared.PortalOptions _options = shared.PortalOptions.stock;
  final Set<String> _selected = {};

  /// Opt OUT, not opt in. A rescue team that knows only that somebody
  /// needs help cannot act on it.
  bool _shareLocation = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_uploadStored);
    Future.microtask(_loadOptions);
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    final client = shared.RescueMeshClient(
        baseUrl: kDroneBaseUrl, timeout: const Duration(seconds: 5));
    try {
      final opts = await client.getPortalOptions();
      if (!mounted || opts.situations.isEmpty) return;
      setState(() => _options = opts);
    } catch (_) {
      // Older node, or a slow link. The stock list is already showing and
      // is deliberately need-based, so it is never wrong, only less
      // tailored. Saying nothing is right: this is not the victim's
      // problem to solve.
    } finally {
      client.close();
    }
  }

  Future<void> _uploadStored() async {
    setState(() => _uploading = true);
    try {
      final UploadResult r = await context.read<AppController>().uploadStored();
      if (!mounted) return;
      setState(() => _uploadMessage =
          'Sent ${r.stored} saved location point(s) to the rescue team.');
      await context.read<AppController>().refreshPoints();
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadMessage =
          'Could not upload yet: check you are on the drone Wi-Fi. ($e)');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// What the rescue team reads. Tapped labels first because they are the
  /// structured part, then anything typed. Built here rather than on the
  /// node so the message is identical whichever route it arrived by.
  String _composeText() {
    final labels = _options.situations
        .where((s) => _selected.contains(s.id))
        .map((s) => s.label)
        .toList();
    final note = _noteController.text.trim();
    if (labels.isEmpty) return note.isEmpty ? 'SOS, no details given' : note;
    final joined = labels.join('; ');
    return note.isEmpty ? joined : '$joined. $note';
  }

  Future<void> _sendSos() async {
    setState(() => _sending = true);
    try {
      await context
          .read<AppController>()
          .sendSos(_composeText(), includeLocation: _shareLocation);
      if (!mounted) return;
      setState(() {
        _sosSent = true;
        _sending = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('SOS failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connected to rescue drone'),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Colors.green.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (_uploading)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const Icon(Icons.cloud_done, color: Colors.green),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(_uploading
                        ? 'Sending your saved locations...'
                        : (_uploadMessage ?? 'Ready.')),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (_sosSent) _sentCard() else ..._composer(),
        ],
      ),
    );
  }

  Widget _sentCard() {
    return Card(
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Icon(Icons.check_circle, color: Colors.red, size: 40),
            const SizedBox(height: 8),
            // Says the DRONE has it, not "the rescue team has it": at this
            // moment nobody has read it yet, and implying otherwise is the
            // one thing these screens must not do.
            Text(
              _shareLocation
                  ? 'SOS sent. The drone has your location and message. '
                      'Stay where you are and keep this Wi-Fi on.'
                  : 'SOS sent. The drone has your message. You chose not to '
                      'share your location, so the team knows what you need '
                      'but not where you are.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.forum, size: 18),
              label: const Text('See if the team has replied'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ConversationScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _composer() {
    return [
      Text(
        _options.headline.isEmpty
            ? 'Tap what you need. You can tap more than one.'
            : _options.headline,
        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 4),
      const Text('Nothing here has to be typed.',
          style: TextStyle(fontSize: 14, color: Colors.black54)),
      const SizedBox(height: 12),
      // Already urgent-first: the node sorts them, and the stock list is
      // written in that order too.
      for (final s in _options.situations) _optionButton(s),
      const SizedBox(height: 16),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _shareLocation,
        onChanged: (v) => setState(() => _shareLocation = v),
        title: const Text('Share my location',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        subtitle: Text(
          _shareLocation
              ? 'On. The team can find you.'
              : 'Off. The team will know what you need but not where you are.',
          style: const TextStyle(fontSize: 14),
        ),
      ),
      const SizedBox(height: 8),
      const Text('Anything else the team should know (optional)',
          style: TextStyle(fontSize: 15)),
      const SizedBox(height: 6),
      TextField(
        controller: _noteController,
        maxLines: 3,
        maxLength: 400,
        style: const TextStyle(fontSize: 17),
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          hintText: 'e.g. two adults, one injured, on the roof',
        ),
      ),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        height: 64,
        child: FilledButton.icon(
          icon: const Icon(Icons.sos),
          label: Text(_sending ? 'Sending...' : 'SEND SOS NOW',
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
          // Deliberately NOT disabled when nothing is selected. An SOS with
          // no detail still says a person is here and needs help, and that
          // is worth far more than making them tick a box first.
          onPressed: _sending ? null : _sendSos,
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Your message is stored on the drone and carried to the rescue team '
        'when the drones next meet. That can take minutes.',
        style: TextStyle(fontSize: 13, color: Colors.black54),
      ),
    ];
  }

  Widget _optionButton(shared.PortalSituation s) {
    final on = _selected.contains(s.id);
    final accent = s.urgent ? Colors.red.shade700 : Colors.blueGrey.shade700;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => setState(() {
          if (!_selected.add(s.id)) _selected.remove(s.id);
        }),
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: on ? accent.withValues(alpha: 0.12) : Colors.white,
            border: Border.all(
                color: on ? accent : Colors.grey.shade400, width: on ? 2 : 1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(on ? Icons.check_circle : Icons.circle_outlined,
                  color: on ? accent : Colors.grey.shade500),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  s.label,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: on ? FontWeight.w600 : FontWeight.normal,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
