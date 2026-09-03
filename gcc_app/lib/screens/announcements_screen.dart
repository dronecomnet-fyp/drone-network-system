/// Announcements (file 04 screen 5): HQ composes with a priority; the
/// list mirrors what the rescue app shows after DTN sync.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rescue_mesh_shared/rescue_mesh_shared.dart';

import '../state/app_state.dart';
import '../state/data_store.dart';
import '../state/mentionables.dart';
import '../widgets/mention_field.dart';

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
    final activeCount = data.announcements.items.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Professional Header ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: const Color(0xFF1A0F0A),
            border: Border(
                bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
          ),
          child: Row(
            children: [
              // Glowing dot indicator
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: activeCount > 0
                      ? Colors.orangeAccent
                      : Colors.white24,
                  shape: BoxShape.circle,
                  boxShadow: activeCount > 0
                      ? [
                          BoxShadow(
                              color: Colors.orangeAccent.withOpacity(0.4),
                              blurRadius: 8,
                              spreadRadius: 2)
                        ]
                      : [],
                ),
              ),
              const SizedBox(width: 14),
              // Title block
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ANNOUNCEMENTS',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$activeCount active  ·  updated ${formatAge(data.announcements.age)}',
                    style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white38,
                        letterSpacing: 0.3),
                  ),
                ],
              ),
              const Spacer(),
              if (app.isHq)
                FilledButton.icon(
                  icon: const Icon(Icons.edit_note, size: 16),
                  label: const Text('Compose', style: TextStyle(fontSize: 13)),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.orangeAccent.withOpacity(0.15),
                    foregroundColor: Colors.orangeAccent,
                    side: BorderSide(
                        color: Colors.orangeAccent.withOpacity(0.3)),
                  ),
                  onPressed: () => _showComposeDialog(context),
                ),
            ],
          ),
        ),

        // ── Not-connected banner ──
        if (!data.isConnected)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.withOpacity(0.25)),
            ),
            child: Row(
              children: [
                const Icon(Icons.signal_wifi_off_rounded,
                    color: Colors.redAccent, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    data.lastError ??
                        'Not connected to a node — join a RESCUE_x Wi-Fi network.',
                    style: const TextStyle(
                        color: Colors.redAccent, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),

        // ── List ──
        Expanded(
          child: data.announcements.items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        data.isConnected
                            ? Icons.campaign_outlined
                            : Icons.cloud_off_rounded,
                        size: 48,
                        color: Colors.white24,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        data.isConnected
                            ? 'No announcements yet.'
                            : 'Cannot fetch announcements — not connected.',
                        style: const TextStyle(
                            fontSize: 14, color: Colors.white54),
                        textAlign: TextAlign.center,
                      ),
                      if (app.isHq && data.isConnected) ...[
                        const SizedBox(height: 6),
                        TextButton(
                          onPressed: () => _showComposeDialog(context),
                          child: const Text('Compose first message'),
                        ),
                      ],
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: data.announcements.items.length,
                  separatorBuilder: (ctx, i) => const SizedBox(height: 12),
                  itemBuilder: (ctx, i) {
                    final a = data.announcements.items[i];
                    final pColor =
                        _priorityColors[a.priority] ?? Colors.white54;

                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.06)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Priority color bar
                          Container(
                            width: 6,
                            decoration: BoxDecoration(
                              color: pColor,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(12),
                                bottomLeft: Radius.circular(12),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.campaign,
                                          size: 16, color: pColor),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          a.title.toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                            color: pColor,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: pColor.withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          border: Border.all(
                                              color:
                                                  pColor.withOpacity(0.3)),
                                        ),
                                        child: Text(
                                          a.priority,
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                            color: pColor,
                                            letterSpacing: 0.8,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    a.body,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.white,
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      const Icon(Icons.person_outline,
                                          size: 13, color: Colors.white38),
                                      const SizedBox(width: 4),
                                      Text(
                                        a.createdBy,
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.white54,
                                            fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(width: 16),
                                      const Icon(Icons.schedule,
                                          size: 13, color: Colors.white38),
                                      const SizedBox(width: 4),
                                      Text(
                                        a.createdAt,
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.white38),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _showComposeDialog(BuildContext context) async {
    final app = context.read<AppState>();
    final data = context.read<DataStore>();
    final mentionables = buildMentionables(
      health: data.health,
      messages: data.messages.items,
      rescuers: data.personnelLocations.items,
    );
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    String priority = 'NORMAL';
    String? error;
    bool busy = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Dialog(
          backgroundColor: const Color(0xFF1E1612),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          child: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A0F0A),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                    border: Border(
                        bottom: BorderSide(
                            color: Colors.white.withOpacity(0.08))),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orangeAccent.withOpacity(0.1),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.orangeAccent.withOpacity(0.3)),
                        ),
                        child: const Icon(Icons.campaign,
                            size: 18, color: Colors.orangeAccent),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'COMPOSE ANNOUNCEMENT',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 1,
                            ),
                          ),
                          Text(
                            'Broadcast to all field personnel',
                            style: TextStyle(
                                fontSize: 11, color: Colors.white38),
                          ),
                        ],
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close,
                            size: 18, color: Colors.white38),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                ),

                // Form body
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('TITLE',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white38,
                                        letterSpacing: 0.8)),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: titleCtrl,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 13),
                                  decoration: InputDecoration(
                                    hintText: 'Brief subject',
                                    hintStyle: const TextStyle(
                                        color: Colors.white24),
                                    filled: true,
                                    fillColor: Colors.white.withOpacity(0.05),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(
                                          color: Colors.white
                                              .withOpacity(0.12)),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(
                                          color: Colors.white
                                              .withOpacity(0.12)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                          color: Colors.orangeAccent,
                                          width: 1.5),
                                    ),
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 1,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('PRIORITY',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white38,
                                        letterSpacing: 0.8)),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  value: priority,
                                  dropdownColor: const Color(0xFF1E1612),
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 13),
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor: Colors.white.withOpacity(0.05),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(
                                          color: Colors.white
                                              .withOpacity(0.12)),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(
                                          color: Colors.white
                                              .withOpacity(0.12)),
                                    ),
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 12),
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                        value: 'LOW', child: Text('Low')),
                                    DropdownMenuItem(
                                        value: 'NORMAL',
                                        child: Text('Normal')),
                                    DropdownMenuItem(
                                        value: 'HIGH', child: Text('High')),
                                    DropdownMenuItem(
                                        value: 'URGENT',
                                        child: Text('Urgent')),
                                  ],
                                  onChanged: (v) => setState(
                                      () => priority = v ?? 'NORMAL'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      const Text('MESSAGE',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white38,
                              letterSpacing: 0.8)),
                      const SizedBox(height: 6),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: Colors.white.withOpacity(0.12)),
                        ),
                        child: MentionField(
                          controller: bodyCtrl,
                          options: mentionables,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            hintText: 'Type announcement...',
                            hintStyle: TextStyle(
                                color: Colors.white24, fontSize: 13),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.all(14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Type "@" to mention drones or personnel (adds actionable coordinates).',
                        style:
                            TextStyle(fontSize: 10, color: Colors.white38),
                      ),

                      if (error != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: Colors.redAccent.withOpacity(0.4)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline,
                                  size: 14, color: Colors.redAccent),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(error!,
                                    style: const TextStyle(
                                        color: Colors.redAccent,
                                        fontSize: 12)),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // Action buttons
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white54,
                                side: BorderSide(
                                    color: Colors.white.withOpacity(0.15)),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: busy
                                  ? null
                                  : () async {
                                      if (titleCtrl.text.trim().isEmpty ||
                                          bodyCtrl.text.trim().isEmpty) {
                                        setState(() => error =
                                            'Title and message required');
                                        return;
                                      }
                                      setState(() => busy = true);
                                      try {
                                        await app.client.postAnnouncement(
                                          titleCtrl.text.trim(),
                                          bodyCtrl.text.trim(),
                                          priority: priority,
                                        );
                                        await data.poll();
                                        if (ctx.mounted) {
                                          Navigator.of(ctx).pop();
                                        }
                                      } on ApiException catch (e) {
                                        setState(() {
                                          error = e.detail;
                                          busy = false;
                                        });
                                      }
                                    },
                              icon: busy
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white))
                                  : const Icon(Icons.send_rounded,
                                      size: 16),
                              label: Text(busy ? 'Sending...' : 'Publish'),
                              style: FilledButton.styleFrom(
                                backgroundColor:
                                    Colors.orangeAccent.withOpacity(0.2),
                                foregroundColor: Colors.orangeAccent,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  side: const BorderSide(
                                      color: Colors.orangeAccent, width: 1),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
