import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/api_error_model.dart';
import '../models/message_model.dart';
import '../providers/message_provider.dart';
import '../services/api_service.dart';
import 'settings_screen.dart';

class VictimRequestsScreen extends StatelessWidget {
  const VictimRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Victim Requests'),
        backgroundColor: Colors.red.shade700,
        elevation: 4,
      ),
      body: Consumer<MessageProvider>(
        builder: (context, messageProvider, child) {
          if (messageProvider.isLoading && messageProvider.messages.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (messageProvider.error != null &&
              messageProvider.messages.isEmpty) {
            final isAuthError =
                messageProvider.apiError?.isCredentialFailure ?? false;
            final isPinningError =
                messageProvider.apiError?.type == ApiErrorType.pinningFailed;
            final title = isAuthError
                ? 'Authorization Required'
                : (isPinningError ? 'Untrusted Node' : 'Connection Error');
            final actionLabel =
                (isAuthError || isPinningError) ? 'Open Settings' : 'Retry';

            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      messageProvider.error ?? 'Unknown error',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      if (isAuthError || isPinningError) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SettingsScreen(),
                          ),
                        );
                      } else {
                        messageProvider.fetchMessages();
                      }
                    },
                    child: Text(actionLabel),
                  ),
                ],
              ),
            );
          }

          if (messageProvider.messages.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(
                    'No Requests',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'All victim requests are claimed or resolved',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => messageProvider.fetchMessages(),
            child: ListView.builder(
              padding: const EdgeInsets.all(8.0),
              itemCount: messageProvider.messages.length,
              itemBuilder: (context, index) {
                final message = messageProvider.messages[index];
                return _buildMessageCard(context, message, messageProvider);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildMessageCard(
      BuildContext context, Message message, MessageProvider provider) {
    final statusColor = message.isClaimed ? Colors.green : Colors.red;
    // File 05 task 5.2: show WHO claimed, not an anonymous badge.
    final statusLabel = message.isClaimed
        ? (message.claimedBy.isEmpty
            ? 'CLAIMED'
            : 'CLAIMED by ${message.claimedBy}')
        : 'NEW';
    final encryptionLabel = message.isEncryptedPayload
        ? (message.hasDecryptionIssue
            ? 'ENCRYPTED · NEEDS PRIVATE KEY'
            : 'ENCRYPTED · DECRYPTED')
        : null;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      elevation: 2,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: statusColor, width: 4),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Message ID: ${message.msgId.substring(0, 8)}...',
                          style: Theme.of(context).textTheme.labelSmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: statusColor),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Tooltip(
                    message: message.isRelativeTime
                        ? 'Approximate: origin node clock was not yet '
                            'GPS-synced when this was stored'
                        : 'GPS-synced timestamp',
                    child: Text(
                      // "~" marks a relative (pre-GPS-fix) timestamp
                      // (design v3 3.3, file 05 task 5.3).
                      message.displayTime,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: message.isRelativeTime
                                ? Colors.orange.shade800
                                : null,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (encryptionLabel != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: message.hasDecryptionIssue
                            ? Colors.orange.withOpacity(0.15)
                            : Colors.blue.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: message.hasDecryptionIssue
                              ? Colors.orange
                              : Colors.blue,
                        ),
                      ),
                      child: Text(
                        encryptionLabel,
                        style: TextStyle(
                          color: message.hasDecryptionIssue
                              ? Colors.orange.shade800
                              : Colors.blue.shade800,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    message.displayContent,
                    style: Theme.of(context).textTheme.bodyMedium,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (message.hasDecryptionIssue) ...[
                    const SizedBox(height: 6),
                    Text(
                      message.decryptionError ??
                          'Encrypted message could not be decrypted.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.orange.shade800),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              // Location info section (schema v3: victim GPS is
              // user_lat/user_lon; free-text landmarks are folded into the
              // message content by the portal, so there is no separate
              // location field anymore)
              if (message.hasGpsLocation)
                Row(
                  children: [
                    const Icon(Icons.my_location,
                        size: 16, color: Colors.green),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${message.userLat?.toStringAsFixed(5)}, '
                        '${message.userLon?.toStringAsFixed(5)}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Colors.green,
                              fontFamily: 'monospace',
                            ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    const Icon(Icons.location_off,
                        size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      'No GPS attached (check message text for landmarks)',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              const SizedBox(height: 8),
              // Victim device ID
              if (message.victimDeviceId.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.devices, size: 14, color: Colors.purple),
                      const SizedBox(width: 4),
                      Text(
                        'Device: ${message.shortDeviceId}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Colors.purple,
                              fontFamily: 'monospace',
                            ),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  const Icon(Icons.cloud_done, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    message.syncedFrom.isEmpty
                        ? 'Node: ${message.nodeId}'
                        : 'Node: ${message.nodeId} (via ${message.syncedFrom})',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: message.isClaimed
                      ? null
                      : () => _showClaimConfirmation(
                          context, provider, message.msgId),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    disabledBackgroundColor: Colors.grey,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(
                    message.isClaimed ? 'ALREADY CLAIMED' : 'CLAIM REQUEST',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              // Replying is only offered when the message came from the
              // emergency app: a captive-portal victim has closed the page
              // and has no way to read an answer, so a reply button there
              // would promise a conversation that cannot happen.
              if (message.victimDeviceId.isNotEmpty) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.reply, size: 18),
                    label: const Text('REPLY TO THIS PERSON'),
                    onPressed: () => _showReplySheet(context, message.msgId),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Quick replies first, free text underneath. During a real event a
  /// rescuer may have dozens of threads, and retyping "stay where you are"
  /// forty times is how a good feature becomes an abandoned one.
  static const List<String> _quickReplies = [
    'We have your location. Stay where you are.',
    'Help is being sent to you now.',
    'Move to higher ground if you safely can.',
    'Are you able to move? Reply if yes.',
    'We cannot reach you yet. Keep this app on.',
  ];

  void _showReplySheet(BuildContext context, String msgId) {
    final controller = TextEditingController();
    var sending = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          left: 16, right: 16, top: 16,
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 16,
        ),
        child: StatefulBuilder(
          builder: (ctx, setSheetState) {
            Future<void> send(String body) async {
              if (body.trim().isEmpty || sending) return;
              setSheetState(() => sending = true);
              final messenger = ScaffoldMessenger.of(context);
              try {
                await APIService.replyToMessage(msgId, body.trim());
                if (ctx.mounted) Navigator.pop(ctx);
                messenger.showSnackBar(const SnackBar(
                    content: Text('Reply sent. It reaches them when their '
                        'phone next meets a drone.')));
              } catch (e) {
                setSheetState(() => sending = false);
                messenger.showSnackBar(
                    SnackBar(content: Text('Could not send reply: $e')));
              }
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Reply to this person',
                    style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'They see this in their app. It may take a while to reach '
                  'them, so avoid anything time-critical.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _quickReplies
                      .map((q) => ActionChip(
                            label: Text(q, style: const TextStyle(fontSize: 12)),
                            onPressed: sending ? null : () => send(q),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLines: 3,
                  maxLength: 500,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Or write your own reply',
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: sending
                        ? const SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send, size: 18),
                    label: Text(sending ? 'Sending...' : 'Send reply'),
                    onPressed: sending ? null : () => send(controller.text),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showClaimConfirmation(
      BuildContext context, MessageProvider provider, String msgId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Claim'),
        content: const Text(
            'Claim this request under your personnel ID? Other teams on '
            'every drone will see it as yours after sync.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              provider.claimMessage(msgId);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Request claimed successfully!')),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
            child: const Text('Claim'),
          ),
        ],
      ),
    );
  }
}
