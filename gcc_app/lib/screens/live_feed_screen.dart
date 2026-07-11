/// Live Feed (file 04 screen 2): all victim messages with filter/search,
/// claim state visibility, and data age. E2E decryption of encrypted
/// payloads is deferred until the E2E capability is switched on
/// (file 09 D2 keeps it off by default); encrypted rows are labeled.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rescue_mesh_shared/rescue_mesh_shared.dart';

import '../main.dart' show showLoginDialog;
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

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataStore>();
    final app = context.watch<AppState>();

    if (!app.isLoggedIn && app.apiKey.isEmpty) {
      return _LoginPrompt(onLogin: () => showLoginDialog(context));
    }

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
              Text('updated ${formatAge(data.messages.age)}',
                  style: Theme.of(context).textTheme.bodySmall),
              const Spacer(),
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
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search, size: 18),
                    hintText: 'search content / node / claimer',
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
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
