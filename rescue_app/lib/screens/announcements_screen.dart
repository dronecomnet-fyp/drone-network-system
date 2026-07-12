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
        backgroundColor: Colors.blue.shade700,
        elevation: 4,
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
                          Icon(Icons.campaign,
                              size: 72, color: Colors.blue.shade300),
                          const SizedBox(height: 16),
                          Text(
                            authError
                                ? 'Authorization required'
                                : 'No announcements yet',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            authError
                                ? 'Log in again or check credentials in Settings.'
                                : 'HQ broadcasts published from the ground '
                                    'control center appear here.',
                            style: Theme.of(context).textTheme.bodyMedium,
                            textAlign: TextAlign.center,
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

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: color),
                              ),
                              child: Text(
                                a.priority,
                                style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              _formatTime(a.createdAt),
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          a.title,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          a.body,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'by ${a.createdBy}',
                          style: Theme.of(context).textTheme.labelSmall,
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
