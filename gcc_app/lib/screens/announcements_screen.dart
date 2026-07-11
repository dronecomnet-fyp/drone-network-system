/// Announcements (file 04 screen 5): HQ composes with a priority; the
/// list mirrors what the rescue app shows after DTN sync.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rescue_mesh_shared/rescue_mesh_shared.dart';

import '../state/app_state.dart';
import '../state/data_store.dart';

class AnnouncementsScreen extends StatelessWidget {
  const AnnouncementsScreen({super.key});

  static const _priorityColors = {
    'LOW': Colors.blueGrey,
    'NORMAL': Colors.blue,
    'HIGH': Colors.orange,
    'URGENT': Colors.red,
  };

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataStore>();
    final app = context.watch<AppState>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Text('Announcements',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(width: 12),
              Text('updated ${formatAge(data.announcements.age)}',
                  style: Theme.of(context).textTheme.bodySmall),
              const Spacer(),
              if (app.isHq)
                FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Compose'),
                  onPressed: () => _showComposeDialog(context),
                ),
            ],
          ),
        ),
        Expanded(
          child: data.announcements.items.isEmpty
              ? const Center(child: Text('No announcements.'))
              : ListView(
                  children: data.announcements.items
                      .map((a) => Card(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            child: ListTile(
                              leading: Icon(Icons.campaign,
                                  color: _priorityColors[a.priority]),
                              title: Text(a.title),
                              subtitle: Text(
                                  '${a.body}\n${a.priority}  |  by ${a.createdBy}  |  ${a.createdAt}'),
                              isThreeLine: true,
                            ),
                          ))
                      .toList(),
                ),
        ),
      ],
    );
  }

  Future<void> _showComposeDialog(BuildContext context) async {
    final app = context.read<AppState>();
    final data = context.read<DataStore>();
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    String priority = 'NORMAL';
    String? error;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Compose announcement'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                TextField(
                  controller: bodyCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Body'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: priority,
                  decoration: const InputDecoration(labelText: 'Priority'),
                  items: const [
                    DropdownMenuItem(value: 'LOW', child: Text('Low')),
                    DropdownMenuItem(value: 'NORMAL', child: Text('Normal')),
                    DropdownMenuItem(value: 'HIGH', child: Text('High')),
                    DropdownMenuItem(value: 'URGENT', child: Text('Urgent')),
                  ],
                  onChanged: (v) => setState(() => priority = v ?? 'NORMAL'),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(error!,
                        style: const TextStyle(color: Colors.redAccent)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                try {
                  await app.client.postAnnouncement(
                      titleCtrl.text.trim(), bodyCtrl.text.trim(),
                      priority: priority);
                  await data.poll();
                  if (ctx.mounted) Navigator.of(ctx).pop();
                } on ApiException catch (e) {
                  setState(() => error = e.detail);
                }
              },
              child: const Text('Publish'),
            ),
          ],
        ),
      ),
    );
  }
}
