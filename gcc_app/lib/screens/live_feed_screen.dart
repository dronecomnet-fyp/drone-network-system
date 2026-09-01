/// Live Feed (file 04 screen 2): everything coming IN, with filter and
/// search, claim state, and data age. E2E decryption of encrypted
/// payloads is deferred until the E2E capability is switched on
/// (file 09 D2 keeps it off by default); encrypted rows are labeled.
///
/// Two inbound streams share this screen, chosen with the source toggle:
///
///   VICTIMS       messages from the public, via the captive portal or
///                 the emergency app.
///   FIELD REPORTS what rescuers send up from the field. The rescue app
///                 has always been able to send these, and until now the
///                 GCC had nowhere to read them: they existed only as a
///                 number on Live Ops and a pin on the map. A one-way
///                 channel with no inbox is not a channel.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rescue_mesh_shared/rescue_mesh_shared.dart';

import '../main.dart' show ShellNav, showLoginDialog;
import '../state/app_state.dart';
import '../state/data_store.dart';

class LiveFeedScreen extends StatefulWidget {
  const LiveFeedScreen({super.key});

  @override
  State<LiveFeedScreen> createState() => _LiveFeedScreenState();
}

class _LiveFeedScreenState extends State<LiveFeedScreen> {
  String _query = '';
  String _statusFilter = 'ALL';
  String _source = 'VICTIMS';

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataStore>();
    final app = context.watch<AppState>();
    final nav = context.watch<ShellNav>();

    final requestedSource = nav.takeLiveFeedSource();
    if (requestedSource != null && requestedSource != _source) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _source = requestedSource);
      });
    }

    if (!app.isLoggedIn && app.apiKey.isEmpty) {
      return _LoginPrompt(onLogin: () => showLoginDialog(context));
    }

    final reports = data.gsMessages.items;
    var items = data.messages.items;
    if (_statusFilter != 'ALL') {
      items = items.where((m) => m.status == _statusFilter).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      items = items
          .where((m) =>
              m.content.toLowerCase().contains(q) ||
              m.nodeId.toLowerCase().contains(q) ||
              m.claimedBy.toLowerCase().contains(q) ||
              m.victimDeviceId.toLowerCase().contains(q))
          .toList();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Text('Live Feed', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(width: 12),
              Text('updated ${formatAge(_source == "REPORTS" ? data.gsMessages.age : data.messages.age)}',
                  style: Theme.of(context).textTheme.bodySmall),
              const Spacer(),
              SegmentedButton<String>(
                segments: [
                  const ButtonSegment(
                      value: 'VICTIMS',
                      icon: Icon(Icons.person_pin_circle, size: 16),
                      label: Text('Victims')),
                  ButtonSegment(
                      value: 'REPORTS',
                      icon: const Icon(Icons.flag, size: 16),
                      label: Text('Field reports (${reports.length})')),
                ],
                selected: {_source},
                onSelectionChanged: (s) =>
                    setState(() => _source = s.first),
              ),
              const SizedBox(width: 12),
              if (_source == 'VICTIMS')
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'ALL', label: Text('All')),
                    ButtonSegment(value: 'NEW', label: Text('New')),
                    ButtonSegment(value: 'CLAIMED', label: Text('Claimed')),
                  ],
                  selected: {_statusFilter},
                  onSelectionChanged: (s) =>
                      setState(() => _statusFilter = s.first),
                ),
              const SizedBox(width: 12),
              SizedBox(
                width: 240,
                child: TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search, size: 18),
                    hintText: _source == 'REPORTS'
                        ? 'search report / sender / node'
                        : 'search content / node / claimer',
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _source == 'REPORTS'
              ? _ReportList(reports: reports, query: _query)
              : items.isEmpty
                  ? const Center(child: Text('No messages match.'))
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (ctx, i) => _MessageTile(message: items[i]),
                    ),
        ),
      ],
    );
  }
}

/// Field reports from rescuers, newest first.
class _ReportList extends StatelessWidget {
  const _ReportList({required this.reports, required this.query});

  final List<GsMessage> reports;
  final String query;

  @override
  Widget build(BuildContext context) {
    var items = List<GsMessage>.from(reports);
    if (query.isNotEmpty) {
      final q = query.toLowerCase();
      items = items
          .where((g) =>
              g.content.toLowerCase().contains(q) ||
              g.sender.toLowerCase().contains(q) ||
              g.nodeId.toLowerCase().contains(q))
          .toList();
    }
    items.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No field reports yet.\n\n'
            'Rescuers send these from the HQ Uplink tab of the rescue app. '
            'They replicate like any other record, so one filed at another '
            'drone arrives here after the next sync.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final g = items[i];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            leading: const Icon(Icons.flag, color: Colors.purpleAccent),
            title: Text(g.content, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.person, size: 14),
                      label: Text(g.sender.isEmpty ? 'unknown' : g.sender,
                          style: const TextStyle(fontSize: 11)),
                    ),
                    Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.access_time, size: 14),
                      label: Text(g.timestamp, style: const TextStyle(fontSize: 11)),
                    ),
                    if (g.nodeId.isNotEmpty)
                      Chip(
                        visualDensity: VisualDensity.compact,
                        avatar: const Icon(Icons.hub, size: 14),
                        label: Text('via ${g.nodeId}', style: const TextStyle(fontSize: 11)),
                      ),
                    if (g.hasLocation)
                      Chip(
                        visualDensity: VisualDensity.compact,
                        avatar: const Icon(Icons.place, size: 14, color: Colors.cyanAccent),
                        label: Text(
                          '${g.locationLat!.toStringAsFixed(5)}, ${g.locationLon!.toStringAsFixed(5)}',
                          style: const TextStyle(fontSize: 11, color: Colors.cyanAccent),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            isThreeLine: true,
            trailing: g.hasLocation
                ? OutlinedButton.icon(
                    icon: const Icon(Icons.map, size: 16),
                    label: const Text('View on map'),
                    onPressed: () => context
                        .read<ShellNav>()
                        .goToMapAt(g.locationLat!, g.locationLon!),
                  )
                : null,
          ),
        );
      },
    );
  }
}

class _MessageTile extends StatelessWidget {
  final Message message;

  const _MessageTile({required this.message});

  @override
  Widget build(BuildContext context) {
    final data = context.read<DataStore>();
    final claimed = message.isClaimed;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: Icon(
          claimed ? Icons.check_circle : Icons.warning_amber_rounded,
          color: claimed ? Colors.greenAccent : Colors.orangeAccent,
        ),
        title: Text(
          message.isEncrypted
              ? '[encrypted message: E2E is off by default this phase]'
              : message.content,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text([
          'via ${message.nodeId}',
          // "~" marks a relative (pre-GPS-fix) timestamp (file 05 5.3)
          '${message.isRelativeTime ? "~" : ""}${message.timestamp}',
          if (message.hasUserLocation)
            'GPS ${message.userLat!.toStringAsFixed(5)}, ${message.userLon!.toStringAsFixed(5)}',
          if (claimed) 'claimed by ${message.claimedBy}',
          if (message.victimDeviceId.isNotEmpty)
            'session ${message.victimDeviceId.substring(0, 8)}...',
        ].join('  |  ')),
        trailing: claimed
            ? null
            : FilledButton.tonal(
                onPressed: () async {
                  try {
                    await context
                        .read<AppState>()
                        .client
                        .claimMessage(message.msgId);
                    await data.poll();
                  } on ApiException catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Claim failed: ${e.detail}')));
                    }
                  }
                },
                child: const Text('Claim'),
              ),
      ),
    );
  }
}

class _LoginPrompt extends StatelessWidget {
  final VoidCallback onLogin;

  const _LoginPrompt({required this.onLogin});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock_outline, size: 48),
          const SizedBox(height: 12),
          const Text('Log in with your personnel ID and PIN to view the feed.'),
          const SizedBox(height: 12),
          FilledButton(onPressed: onLogin, child: const Text('Log in')),
        ],
      ),
    );
  }
}
