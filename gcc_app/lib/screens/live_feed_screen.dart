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

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rescue_mesh_shared/rescue_mesh_shared.dart';

import '../main.dart' show ShellNav, showLoginDialog;
import '../state/app_state.dart';
import '../state/data_store.dart';
import '../widgets/media_widgets.dart';

String _formatDateTime(String ts) {
  try {
    String clean = ts.replaceAll(RegExp(r'^[~-]+'), '');
    final dt = DateTime.parse(clean).toLocal();
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final day = dt.day.toString().padLeft(2, '0');
    final mon = months[dt.month - 1];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$mon $day · $h:$m';
  } catch (_) {
    if (ts.length > 16) return ts.substring(0, 16);
    return ts;
  }
}

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

    final totalCount = data.messages.items.length;
    final claimedCount = data.messages.items.where((m) => m.isClaimed).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Professional command-center header ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF1A0F0A),
            border: Border(
              bottom: BorderSide(color: Colors.white.withOpacity(0.08), width: 1),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Title block
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.orangeAccent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'LIVE FEED',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'updated ${formatAge(_source == "REPORTS" ? data.gsMessages.age : data.messages.age)}  ·  $totalCount total  ·  $claimedCount claimed',
                        style: const TextStyle(fontSize: 11, color: Colors.white38, letterSpacing: 0.5),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Source toggle
                  SegmentedButton<String>(
                    segments: [
                      const ButtonSegment(
                          value: 'VICTIMS',
                          icon: Icon(Icons.person_pin_circle, size: 15),
                          label: Text('Victims')),
                      ButtonSegment(
                          value: 'REPORTS',
                          icon: const Icon(Icons.flag, size: 15),
                          label: Text('Reports (${reports.length})')),
                    ],
                    selected: {_source},
                    onSelectionChanged: (s) => setState(() => _source = s.first),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (_source == 'VICTIMS') ...[
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'ALL', label: Text('All')),
                        ButtonSegment(value: 'NEW', label: Text('New')),
                        ButtonSegment(value: 'CLAIMED', label: Text('Claimed')),
                      ],
                      selected: {_statusFilter},
                      onSelectionChanged: (s) => setState(() => _statusFilter = s.first),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search, size: 17, color: Colors.white38),
                        hintText: _source == 'REPORTS'
                            ? 'Search reports, sender, node…'
                            : 'Search content, node, claimer…',
                        hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.06),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Colors.orangeAccent),
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // ── Grid feed ──
        Expanded(
          child: _source == 'REPORTS'
              ? _ReportList(reports: reports, query: _query)
              : _VictimGrid(items: items, query: _query),
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

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 460,
        mainAxisExtent: 220,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: items.length,
      itemBuilder: (ctx, i) {
        final g = items[i];
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              colors: [Color(0xFF3E2723), Color(0xFF1F120F)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: Colors.blueAccent.withOpacity(0.12),
                blurRadius: 12,
                spreadRadius: -2,
              ),
            ],
            border: Border.all(color: Colors.white12, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (g.nodeId.isNotEmpty)
                      _DarkMetaChip(icon: Icons.hub, text: g.nodeId),
                    const Spacer(),
                    _DarkMetaChip(icon: Icons.access_time, text: _formatDateTime(g.timestamp)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.flag, color: Colors.blueAccent, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        g.content,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            height: 1.4),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _DarkMetaChip(icon: Icons.person, text: g.sender.isEmpty ? 'unknown' : g.sender),
                    if (g.hasLocation)
                      _DarkMetaChip(
                        icon: Icons.place,
                        text: '${g.locationLat!.toStringAsFixed(4)}, ${g.locationLon!.toStringAsFixed(4)}',
                        iconColor: Colors.blueAccent,
                        onTap: () => context.read<ShellNav>().goToMapAt(g.locationLat!, g.locationLon!),
                      ),
                    if (g.hasAttachments)
                      _DarkMetaChip(icon: Icons.attach_file, text: '${g.attachments.length} file(s)'),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _VictimGrid extends StatefulWidget {
  final List<Message> items;
  final String query;
  const _VictimGrid({required this.items, required this.query});

  @override
  State<_VictimGrid> createState() => _VictimGridState();
}

class _VictimGridState extends State<_VictimGrid> {
  static const int _kInitialCount = 6;
  final Map<String, bool> _expanded = {};

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final query = widget.query;
    var filtered = items.where((m) {
      if (query.isEmpty) return true;
      final q = query.toLowerCase();
      return m.content.toLowerCase().contains(q) ||
          m.nodeId.toLowerCase().contains(q) ||
          m.claimedBy.toLowerCase().contains(q) ||
          m.victimDeviceId.toLowerCase().contains(q);
    }).toList();

    if (filtered.isEmpty) {
      return const Center(
          child: Text('No messages match.', style: TextStyle(color: Colors.white38)));
    }

    final unclaimed = filtered.where((m) => !m.isClaimed).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final claimed = filtered.where((m) => m.isClaimed).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // Group unclaimed by nodeId
    final Map<String, List<Message>> byDrone = {};
    for (final m in unclaimed) {
      final key = m.nodeId.isEmpty ? 'Unknown Node' : m.nodeId;
      byDrone.putIfAbsent(key, () => []).add(m);
    }
    final sortedDrones = byDrone.keys.toList()..sort();

    const gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      mainAxisExtent: 185,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── ACTIVE header ──
        if (unclaimed.isNotEmpty)
          _SectionHeader(
            icon: Icons.warning_amber_rounded,
            label: 'ACTIVE (${unclaimed.length})',
            color: Colors.orangeAccent,
          ),

        // ── Side-by-side drone panels ──
        if (unclaimed.isNotEmpty)
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int di = 0; di < sortedDrones.length; di++) ...[
                  if (di > 0)
                    Container(
                      width: 1,
                      color: Colors.white.withOpacity(0.07),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Drone panel header
                        Container(
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                          decoration: BoxDecoration(
                            color: Colors.orangeAccent.withOpacity(0.06),
                            border: Border(
                              bottom: BorderSide(
                                color: Colors.orangeAccent.withOpacity(0.15),
                                width: 1,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Colors.orangeAccent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                sortedDrones[di],
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.orangeAccent,
                                  letterSpacing: 1.4,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.orangeAccent.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${byDrone[sortedDrones[di]]!.length}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.orangeAccent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Drone card grid — show 6 initially + Show More
                        Expanded(
                          child: Builder(builder: (ctx) {
                            final droneKey = sortedDrones[di];
                            final allCards = byDrone[droneKey]!;
                            final isExpanded = _expanded[droneKey] ?? false;
                            final visibleCards = isExpanded
                                ? allCards
                                : allCards.take(_kInitialCount).toList();
                            final remaining = allCards.length - _kInitialCount;

                            return GridView.builder(
                              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                              gridDelegate: gridDelegate,
                              // +1 for Show More button slot if needed
                              itemCount: visibleCards.length +
                                  ((!isExpanded && remaining > 0) ? 1 : 0),
                              itemBuilder: (ctx, i) {
                                if (!isExpanded &&
                                    remaining > 0 &&
                                    i == visibleCards.length) {
                                  // Show More button tile
                                  return InkWell(
                                    onTap: () => setState(
                                        () => _expanded[droneKey] = true),
                                    borderRadius: BorderRadius.circular(14),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius:
                                            BorderRadius.circular(14),
                                        border: Border.all(
                                            color: Colors.orangeAccent
                                                .withOpacity(0.4),
                                            width: 1.5),
                                        color: Colors.orangeAccent
                                            .withOpacity(0.05),
                                      ),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.expand_more,
                                              color: Colors.orangeAccent,
                                              size: 28),
                                          const SizedBox(height: 6),
                                          Text(
                                            '+$remaining more',
                                            style: const TextStyle(
                                              color: Colors.orangeAccent,
                                              fontSize: 13,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          const Text(
                                            'tap to expand',
                                            style: TextStyle(
                                              color: Colors.white38,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }
                                return _MessageTile(
                                    message: visibleCards[i]);
                              },
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

        // ── CLAIMED section (horizontal scroll) ──
        if (claimed.isNotEmpty) ...[
          _SectionHeader(
            icon: Icons.check_circle,
            label: 'CLAIMED (${claimed.length})',
            color: Colors.greenAccent,
          ),
          SizedBox(
            height: 210,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              scrollDirection: Axis.horizontal,
              itemCount: claimed.length,
              itemBuilder: (ctx, i) => SizedBox(
                width: 340,
                child: Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: _MessageTile(message: claimed[i]),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _SectionHeader({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 1,
              color: color.withOpacity(0.2),
            ),
          ),
        ],
      ),
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
    final accentColor = claimed ? Colors.greenAccent : Colors.orangeAccent;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: [Color(0xFF3E2723), Color(0xFF1F120F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: accentColor.withOpacity(0.12),
            blurRadius: 10,
            spreadRadius: -2,
          ),
        ],
        border: Border.all(color: Colors.white12, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: node + device ID (flexible) + time (fixed right)
            Row(
              children: [
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (message.nodeId.isNotEmpty)
                        _DarkMetaChip(icon: Icons.hub, text: message.nodeId),
                      if (message.victimDeviceId.isNotEmpty) ...[
                        const SizedBox(width: 5),
                        Flexible(
                          child: _DarkMetaChip(
                            icon: Icons.phone_android,
                            text: 'ID: ${message.victimDeviceId.length >= 8 ? message.victimDeviceId.substring(0, 8) : message.victimDeviceId}',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                _DarkMetaChip(
                  icon: Icons.access_time,
                  text: _formatDateTime(message.timestamp),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Row 2: icon + message text
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  claimed ? Icons.check_circle : Icons.warning_amber_rounded,
                  color: accentColor,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message.isEncrypted
                        ? '[encrypted]'
                        : message.content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            // Row 3: location + attachments chip
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                if (message.hasUserLocation)
                  _DarkMetaChip(
                    icon: Icons.place,
                    text: '${message.userLat!.toStringAsFixed(4)}, ${message.userLon!.toStringAsFixed(4)}',
                    iconColor: Colors.blueAccent,
                  ),
                if (claimed)
                  _DarkMetaChip(
                    icon: Icons.person,
                    text: 'Claimed by ${message.claimedBy}',
                    iconColor: Colors.greenAccent,
                  ),
                // Attachment icon buttons
                if (message.hasAttachments)
                  ...message.attachments.map((att) {
                    if (att.isAudio) {
                      return _AttachmentIconButton(
                        icon: Icons.mic,
                        color: Colors.purpleAccent,
                        tooltip: 'Voice note',
                        onTap: () => _showAudioDialog(context, att),
                      );
                    } else if (att.isImage) {
                      return _AttachmentIconButton(
                        icon: Icons.image,
                        color: Colors.blueAccent,
                        tooltip: 'Photo',
                        onTap: () => _showImageDialog(context, att),
                      );
                    }
                    return _AttachmentIconButton(
                      icon: Icons.attach_file,
                      color: Colors.white54,
                      tooltip: att.filename,
                      onTap: () {},
                    );
                  }),
              ],
            ),
            // Row 4: claim button only for unclaimed
            if (!claimed) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 32,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: EdgeInsets.zero,
                  ),
                  icon: const Icon(Icons.pan_tool, size: 14),
                  label: const Text('Claim Request',
                      style: TextStyle(fontSize: 12)),
                  onPressed: () async {
                    try {
                      await context.read<AppState>().client.claimMessage(message.msgId);
                      await data.poll();
                    } on ApiException catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Claim failed: ${e.detail}')));
                      }
                    }
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    ), // closes Container
    ); // closes ClipRRect
  }
}

void _showImageDialog(BuildContext context, MediaAttachment attachment) {
  final client = context.read<AppState>().client;
  final url = '${client.baseUrl}/media/${attachment.id}';
  final headers = {
    if (client.sessionToken != null) 'X-Session-Token': client.sessionToken!,
    if (client.apiKey != null) 'X-API-Key': client.apiKey!,
  };
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          InteractiveViewer(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                url,
                headers: headers,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return FutureBuilder<List<int>>(
                    future: client.getMediaBytes(attachment.id),
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        return Image.memory(Uint8List.fromList(snapshot.data!),
                            fit: BoxFit.contain);
                      }
                      return Container(
                        color: const Color(0xFF1E293B),
                        width: 300,
                        height: 300,
                        child: const Center(
                            child: Icon(Icons.broken_image,
                                color: Colors.white54, size: 48)),
                      );
                    },
                  );
                },
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 32),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ),
        ],
      ),
    ),
  );
}

void _showAudioDialog(BuildContext context, MediaAttachment attachment) {
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: const Color(0xFF1F120F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.mic, color: Colors.purpleAccent, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    attachment.filename.isEmpty
                        ? 'Voice Note'
                        : attachment.filename,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            GccAudioPlayerWidget(attachment: attachment),
          ],
        ),
      ),
    ),
  );
}

class _AttachmentIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;
  const _AttachmentIconButton(
      {required this.icon,
      required this.color,
      required this.tooltip,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.4), width: 1),
          ),
          child: Icon(icon, size: 15, color: color),
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

class _DarkMetaChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? iconColor;
  final VoidCallback? onTap;

  const _DarkMetaChip({required this.icon, required this.text, this.iconColor, this.onTap});

  @override
  Widget build(BuildContext context) {
    Widget child = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 200),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: iconColor ?? Colors.white70),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                text,
                style: const TextStyle(fontSize: 12, color: Colors.white70),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
    if (onTap != null) {
      child = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: child,
      );
    }
    return child;
  }
}

class _StyledImageViewer extends StatefulWidget {
  final MediaAttachment attachment;
  const _StyledImageViewer({required this.attachment});

  @override
  State<_StyledImageViewer> createState() => _StyledImageViewerState();
}

class _StyledImageViewerState extends State<_StyledImageViewer> {
  void _showImageDialog(BuildContext context, String url, Map<String, String> headers) {
    final client = context.read<AppState>().client;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  url,
                  headers: headers,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const Center(child: CircularProgressIndicator());
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return FutureBuilder<List<int>>(
                      future: client.getMediaBytes(widget.attachment.id),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (snapshot.hasError || !snapshot.hasData) {
                          return Container(
                            color: const Color(0xFF1E293B),
                            width: 300,
                            height: 300,
                            child: const Center(
                              child: Icon(Icons.broken_image, color: Colors.white54, size: 48),
                            ),
                          );
                        }
                        return Image.memory(
                          Uint8List.fromList(snapshot.data!),
                          fit: BoxFit.contain,
                        );
                      },
                    );
                  },
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final client = context.read<AppState>().client;
    final url = '${client.baseUrl}/media/${widget.attachment.id}';
    final headers = {
      if (client.sessionToken != null) 'X-Session-Token': client.sessionToken!,
      if (client.apiKey != null) 'X-API-Key': client.apiKey!,
    };
    
    return InkWell(
      onTap: () => _showImageDialog(context, url, headers),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 80,
        width: 120,
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              url,
              headers: headers,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return FutureBuilder<List<int>>(
                  future: client.getMediaBytes(widget.attachment.id),
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      return Image.memory(
                        Uint8List.fromList(snapshot.data!),
                        fit: BoxFit.cover,
                      );
                    }
                    return const Center(child: Icon(Icons.image, color: Colors.white38));
                  },
                );
              },
            ),
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(
                child: Icon(Icons.zoom_in, color: Colors.white, size: 28),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
