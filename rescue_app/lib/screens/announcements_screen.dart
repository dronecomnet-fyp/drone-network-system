/// Announcements (file 05 task 5.3): now wired to the REAL
/// /announcements endpoints from backend v2. The Phase 1 version of this
/// screen showed gs_messages as a stand-in because the backend had no
/// announcements support yet; field reports still live on the HQ Uplink
/// screen's log.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:rescue_mesh_shared/rescue_mesh_shared.dart' as shared;

import '../providers/message_provider.dart';

class AnnouncementsScreen extends StatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  static const Map<String, Color> _priorityColors = {
    'LOW': Colors.blueGrey,
    'NORMAL': Colors.blue,
    'HIGH': Colors.orange,
    'URGENT': Colors.red,
  };

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) {
        return;
      }
      Provider.of<MessageProvider>(context, listen: false)
          .fetchAnnouncements();
    });
  }

  String _formatTime(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) {
      return iso;
    }
    return DateFormat('MMM d, HH:mm').format(parsed.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HQ Announcements'),
        actions: [
          IconButton(
            onPressed: () =>
                Provider.of<MessageProvider>(context, listen: false)
                    .fetchAnnouncements(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Consumer<MessageProvider>(
        builder: (context, messageProvider, child) {
          final announcements = messageProvider.announcements;
          final authError =
              messageProvider.apiError?.isCredentialFailure ?? false;

          if (announcements.isEmpty) {
            return RefreshIndicator(
              onRefresh: () => messageProvider.fetchAnnouncements(),
              child: ListView(
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.75,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0.0, end: 1.0),
                            duration: const Duration(milliseconds: 600),
                            builder: (context, v, child) => Opacity(
                              opacity: v,
                              child: Transform.scale(scale: 0.8 + 0.2 * v, child: child),
                            ),
                            child: Icon(Icons.campaign_outlined,
                                size: 96, color: Colors.grey.shade300),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            authError
                                ? 'Authorization Required'
                                : 'No Announcements',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF1A1A2E)),
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              authError
                                  ? 'Log in again or check credentials in Settings.'
                                  : 'HQ broadcasts published from the ground control center appear here.',
                              style: const TextStyle(
                                  color: Color(0xFF757575), height: 1.4),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => messageProvider.fetchAnnouncements(),
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: announcements.length,
              itemBuilder: (context, index) {
                final shared.Announcement a = announcements[index];
                final color = _priorityColors[a.priority] ?? Colors.blue;

                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.07),
                        blurRadius: 18,
                        offset: const Offset(0, 4),
                      ),
                    ],
                    border: Border(
                      left: BorderSide(color: color, width: 5),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: color.withValues(alpha: 0.5)),
                              ),
                              child: Text(
                                a.priority,
                                style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              _formatTime(a.createdAt),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: Colors.grey.shade600,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          a.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A2E),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          a.body,
                          style: const TextStyle(
                            fontSize: 15,
                            color: Color(0xFF212121),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
