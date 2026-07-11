/// Personnel (file 04 screen 4): create a record and show the one-time
/// PIN LARGE with a copy button (it is never shown again, never stored);
/// list with revoke. The revocation-latency caveat is visible: a revoke
/// reaches other drones at DTN sync speed, not instantly.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:rescue_mesh_shared/rescue_mesh_shared.dart';

import '../state/app_state.dart';
import '../state/data_store.dart';

class PersonnelScreen extends StatelessWidget {
  const PersonnelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final data = context.watch<DataStore>();

    if (!app.isHq) {
      return const Center(
        child: Text('Personnel management needs an HQ login\n'
            '(or the labeled break-glass key in Settings).'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Text('Personnel', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(width: 12),
              Text('updated ${formatAge(data.personnel.age)}',
                  style: Theme.of(context).textTheme.bodySmall),
              const Spacer(),
              FilledButton.icon(
                icon: const Icon(Icons.person_add),
                label: const Text('Issue credentials'),
                onPressed: () => _showCreateDialog(context),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Records sync fleet-wide over DTN. A revocation blocks new '
            'logins everywhere only after each drone has synced it.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: data.personnel.items.isEmpty
              ? const Center(child: Text('No personnel records yet.'))
              : ListView(
                  children: data.personnel.items
                      .map((p) => _PersonnelTile(person: p))
                      .toList(),
                ),
        ),
      ],
    );
  }

  Future<void> _showCreateDialog(BuildContext context) async {
    final app = context.read<AppState>();
    final data = context.read<DataStore>();
    final nameCtrl = TextEditingController();
    String role = 'RESCUE_TEAM';
    int expiresHours = 0;
    String? error;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Issue credentials'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: const [
                  DropdownMenuItem(
                      value: 'RESCUE_TEAM', child: Text('Rescue team')),
                  DropdownMenuItem(value: 'HQ', child: Text('HQ operator')),
                ],
                onChanged: (v) => setState(() => role = v ?? 'RESCUE_TEAM'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: expiresHours,
                decoration:
                    const InputDecoration(labelText: 'Credential expiry'),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('No expiry')),
                  DropdownMenuItem(value: 24, child: Text('24 hours')),
                  DropdownMenuItem(value: 72, child: Text('3 days')),
                  DropdownMenuItem(value: 168, child: Text('7 days')),
                ],
                onChanged: (v) => setState(() => expiresHours = v ?? 0),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(error!,
                      style: const TextStyle(color: Colors.redAccent)),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) {
                  setState(() => error = 'Name required');
                  return;
                }
                try {
                  final issued = await app.client.createPersonnel(
                      nameCtrl.text.trim(),
                      role: role,
                      expiresHours: expiresHours);
                  await data.poll();
                  if (ctx.mounted) {
                    Navigator.of(ctx).pop();
                    await _showPinDialog(context, issued);
                  }
                } on ApiException catch (e) {
                  setState(() => error = e.detail);
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPinDialog(
      BuildContext context, IssuedPersonnel issued) async {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('Credentials for ${issued.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('ID: ${issued.personnelId}',
                style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 16),
            SelectableText(
              issued.pin,
              style: Theme.of(ctx).textTheme.displayMedium?.copyWith(
                  fontFamily: 'monospace', letterSpacing: 8),
            ),
            const SizedBox(height: 16),
            const Text(
              'This PIN is shown ONLY ONCE and is not stored anywhere. '
              'Hand it to the person now; if it is lost, revoke and '
              'issue a new record.',
              style: TextStyle(color: Colors.orangeAccent),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('Copy PIN'),
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: issued.pin)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Done, PIN delivered'),
          ),
        ],
      ),
    );
  }
}

class _PersonnelTile extends StatelessWidget {
  final Personnel person;

  const _PersonnelTile({required this.person});

  @override
  Widget build(BuildContext context) {
    final revoked = !person.isActive;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: Icon(
          revoked ? Icons.person_off : Icons.person,
          color: revoked ? Colors.redAccent : Colors.greenAccent,
        ),
        title: Text('${person.personnelId}  ${person.name}'),
        subtitle: Text([
          person.role,
          person.status,
          'issued ${person.issuedAt}',
          if (person.expiresAt.isNotEmpty) 'expires ${person.expiresAt}',
        ].join('  |  ')),
        trailing: revoked
            ? null
            : OutlinedButton(
                onPressed: () => _confirmRevoke(context),
                child: const Text('Revoke'),
              ),
      ),
    );
  }

  Future<void> _confirmRevoke(BuildContext context) async {
    final app = context.read<AppState>();
    final data = context.read<DataStore>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Revoke ${person.personnelId}?'),
        content: const Text(
            'New logins are blocked immediately on THIS drone. Other '
            'drones enforce it after their next DTN sync; that latency is '
            'a property of the mesh, not a bug.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Revoke')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await app.client.revokePersonnel(person.personnelId);
      await data.poll();
    } on ApiException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Revoke failed: ${e.detail}')));
      }
    }
  }
}
