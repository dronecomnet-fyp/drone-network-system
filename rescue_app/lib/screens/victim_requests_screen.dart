import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_theme.dart';
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
      ),
      body: Consumer<MessageProvider>(
        builder: (context, messageProvider, child) {
          final messages = messageProvider.messages;
          final isLoading = messageProvider.isLoading;
          final error = messageProvider.apiError;

          if (isLoading && messages.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (error != null && messages.isEmpty) {
            return _buildErrorState(context, error, messageProvider);
          }

          if (messages.isEmpty) {
            return _buildEmptyState(context);
          }

          return RefreshIndicator(
            onRefresh: () => messageProvider.fetchMessages(),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
              itemCount: messages.length,
              itemBuilder: (context, index) => _RequestCard(
                message: messages[index],
                provider: messageProvider,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () => context.read<MessageProvider>().fetchMessages(),
      child: ListView(children: [
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
                  child: Icon(Icons.inbox,
                      size: 96, color: Colors.grey.shade300),
                ),
                const SizedBox(height: 24),
                Text(
                  'No Requests',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1A1A2E)),
                ),
                const SizedBox(height: 8),
                const Text(
                  'All victim requests are claimed or resolved.',
                  style: TextStyle(color: Color(0xFF757575)),
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildErrorState(
      BuildContext context, ApiException error, MessageProvider provider) {
    final isAuth = error.isCredentialFailure;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isAuth ? Icons.lock_outline : Icons.wifi_off,
                size: 72, color: AppTheme.kDanger.withValues(alpha: 0.6)),
            const SizedBox(height: 20),
            Text(isAuth ? 'Authorization Required' : 'Connection Error',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1A1A2E))),
            const SizedBox(height: 12),
            Text(
              isAuth
                  ? 'Log in or update credentials in Settings.'
                  : error.message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF757575)),
            ),
            const SizedBox(height: 24),
            if (isAuth)
              ElevatedButton.icon(
                icon: const Icon(Icons.settings),
                label: const Text('Open Settings'),
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen())),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.kPrimary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                ),
              )
            else
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                onPressed: () => provider.fetchMessages(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.kPrimary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Compact request card – tap anywhere to see full details
// ─────────────────────────────────────────────────────────────────────────────
class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.message, required this.provider});

  final Message message;
  final MessageProvider provider;

  Color get _statusColor =>
      message.isClaimed ? AppTheme.kSuccess : AppTheme.kDanger;

  String get _statusLabel {
    if (message.isClaimed) {
      return message.claimedBy.isEmpty
          ? 'CLAIMED'
          : 'CLAIMED · ${message.claimedBy}';
    }
    return 'NEW';
  }

  // Open Google Maps with the GPS coordinates
  Future<void> _openMaps() async {
    final lat = message.userLat!;
    final lon = message.userLon!;
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$lat,$lon');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showDetails(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _DetailSheet(message: message, provider: provider),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showDetails(context),
      child: Container(
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
            left: BorderSide(color: _statusColor, width: 5),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Status badge ──────────────────────────────────────────────
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: _statusColor.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      _statusLabel,
                      style: TextStyle(
                        color: _statusColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  const Spacer(),
                  // "tap to expand" hint
                  const Icon(Icons.expand_more,
                      size: 20, color: Color(0xFFBDBDBD)),
                ],
              ),

              // ── Message body ──────────────────────────────────────────────
              const SizedBox(height: 12),
              Text(
                message.displayContent,
                style: const TextStyle(
                  fontSize: 16,
                  color: Color(0xFF212121),
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
              ),

              // ── GPS · CLAIM · REPLY — single row ────────────────────────
              const SizedBox(height: 14),
              IntrinsicHeight(
                child: Row(
                  children: [
                    // GPS
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: OutlinedButton(
                          onPressed:
                              message.hasGpsLocation ? _openMaps : null,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: message.hasGpsLocation
                                ? AppTheme.kSuccess
                                : const Color(0xFFBDBDBD),
                            disabledForegroundColor:
                                const Color(0xFFBDBDBD),
                            side: BorderSide(
                              color: message.hasGpsLocation
                                  ? AppTheme.kSuccess
                                  : const Color(0xFFE0E0E0),
                            ),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            padding: EdgeInsets.zero,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.location_on_rounded,
                                size: 18,
                                color: message.hasGpsLocation
                                    ? AppTheme.kSuccess
                                    : const Color(0xFFBDBDBD),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'MAP',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                  color: message.hasGpsLocation
                                      ? AppTheme.kSuccess
                                      : const Color(0xFFBDBDBD),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // CLAIM
                    Expanded(
                      child: SizedBox(
                        height: 46,
                        child: ElevatedButton(
                          onPressed: message.isClaimed
                              ? null
                              : () => _showClaimConfirmation(
                                  context, provider, message.msgId),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.kPrimary,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: const Color(0xFFF0F0F0),
                            disabledForegroundColor: const Color(0xFFBDBDBD),
                            elevation: message.isClaimed ? 0 : 2,
                            shadowColor:
                                AppTheme.kPrimary.withValues(alpha: 0.3),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(
                            message.isClaimed ? 'CLAIMED' : 'CLAIM',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (message.victimDeviceId.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      // REPLY
                      Expanded(
                        child: SizedBox(
                          height: 46,
                          child: OutlinedButton(
                            onPressed: () =>
                                _showReplySheet(context, message.msgId),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.kPrimary,
                              side: const BorderSide(
                                  color: AppTheme.kPrimary, width: 1.5),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text(
                              'REPLY',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

            ],
          ),
        ),
      ),
    );
  }

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
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 20,
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
                    content: Text(
                        'Reply sent. It reaches them when their phone next meets a drone.')));
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
                // Handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(Icons.reply_rounded, color: AppTheme.kPrimary),
                    const SizedBox(width: 8),
                    Text('Reply to Victim',
                        style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1A1A2E))),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'They see this in their app. It may take time to reach them.',
                  style: TextStyle(color: Color(0xFF757575), fontSize: 13),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _quickReplies
                      .map((q) => ActionChip(
                            label: Text(q,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.kPrimary,
                                    fontWeight: FontWeight.w600)),
                            backgroundColor:
                                AppTheme.kPrimary.withValues(alpha: 0.08),
                            side:
                                const BorderSide(color: AppTheme.kPrimary),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            onPressed: sending ? null : () => send(q),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  maxLines: 3,
                  maxLength: 500,
                  decoration: const InputDecoration(
                      hintText: 'Or type your own message...'),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    icon: sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send_rounded, size: 18),
                    label: Text(sending ? 'Sending...' : 'Send Reply'),
                    onPressed: sending ? null : () => send(controller.text),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.kPrimary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
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
        backgroundColor: Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Confirm Claim',
            style: TextStyle(
                color: Color(0xFF1A1A2E), fontWeight: FontWeight.bold)),
        content: const Text(
          'Claim this request under your personnel ID?\n'
          'Other teams on every drone will see it as yours after sync.',
          style: TextStyle(color: Color(0xFF757575)),
        ),
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
                const SnackBar(content: Text('Request claimed!')),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.kPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child:
                const Text('Claim', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full detail sheet — shown when the card is tapped
// ─────────────────────────────────────────────────────────────────────────────
class _DetailSheet extends StatelessWidget {
  const _DetailSheet({required this.message, required this.provider});

  final Message message;
  final MessageProvider provider;

  Future<void> _openMaps() async {
    final lat = message.userLat!;
    final lon = message.userLon!;
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$lat,$lon');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor =
        message.isClaimed ? AppTheme.kSuccess : AppTheme.kDanger;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
          children: [
            // ── Drag handle ─────────────────────────────────────────────
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // ── Header ──────────────────────────────────────────────────
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: statusColor.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    message.isClaimed
                        ? (message.claimedBy.isEmpty
                            ? 'CLAIMED'
                            : 'CLAIMED · ${message.claimedBy}')
                        : 'NEW',
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Message body ─────────────────────────────────────────────
            Text(
              message.displayContent,
              style: const TextStyle(
                fontSize: 18,
                color: Color(0xFF212121),
                height: 1.55,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 24),

            // ── Detail rows ──────────────────────────────────────────────
            _sectionTitle('Request Details'),
            const SizedBox(height: 10),
            _detailCard([
              _DetailRow(
                icon: Icons.tag,
                label: 'Message ID',
                value: message.msgId,
                mono: true,
              ),
              _DetailRow(
                icon: Icons.access_time_rounded,
                label: 'Timestamp',
                value: message.displayTime,
                mono: true,
              ),
              _DetailRow(
                icon: Icons.router,
                label: 'Received via',
                value: message.syncedFrom.isEmpty
                    ? message.nodeId
                    : '${message.nodeId}  ·  synced from ${message.syncedFrom}',
              ),
              if (message.victimDeviceId.isNotEmpty)
                _DetailRow(
                  icon: Icons.smartphone,
                  label: 'Victim device',
                  value: message.victimDeviceId,
                  mono: true,
                ),
              if (message.isClaimed && message.claimedBy.isNotEmpty)
                _DetailRow(
                  icon: Icons.person_pin,
                  label: 'Claimed by',
                  value: message.claimedBy,
                ),
            ]),

            // ── Location ─────────────────────────────────────────────────
            const SizedBox(height: 20),
            _sectionTitle('Location'),
            const SizedBox(height: 10),
            if (message.hasGpsLocation) ...[
              _detailCard([
                _DetailRow(
                  icon: Icons.my_location,
                  label: 'Victim GPS',
                  value:
                      '${message.userLat!.toStringAsFixed(6)}, ${message.userLon!.toStringAsFixed(6)}',
                  mono: true,
                  valueColor: AppTheme.kSuccess,
                ),
              ]),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.map_rounded),
                  label: const Text('Open in Google Maps',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  onPressed: _openMaps,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.kSuccess,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ] else
              _detailCard([
                const _DetailRow(
                  icon: Icons.location_off,
                  label: 'GPS',
                  value: 'No GPS fix — check message text for landmarks.',
                  valueColor: Color(0xFF9E9E9E),
                ),
              ]),

            // ── Encryption ───────────────────────────────────────────────
            if (message.isEncryptedPayload) ...[
              const SizedBox(height: 20),
              _sectionTitle('Encryption'),
              const SizedBox(height: 10),
              _detailCard([
                _DetailRow(
                  icon: message.hasDecryptionIssue
                      ? Icons.lock
                      : Icons.lock_open,
                  label: 'Status',
                  value: message.hasDecryptionIssue
                      ? 'Encrypted — needs key'
                      : 'Decrypted OK',
                  valueColor: message.hasDecryptionIssue
                      ? AppTheme.kWarning
                      : AppTheme.kSuccess,
                ),
                if (message.hasDecryptionIssue &&
                    message.decryptionError != null)
                  _DetailRow(
                    icon: Icons.error_outline,
                    label: 'Error',
                    value: message.decryptionError!,
                    valueColor: AppTheme.kWarning,
                  ),
              ]),
            ],

            // ── Actions ──────────────────────────────────────────────────
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: message.isClaimed
                          ? null
                          : () => Navigator.pop(context),
                      // pop then show claim dialog via provider
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.kPrimary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFFF0F0F0),
                        disabledForegroundColor: const Color(0xFFBDBDBD),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                              message.isClaimed
                                  ? Icons.check_circle_outline
                                  : Icons.assignment_turned_in_outlined,
                              size: 18),
                          const SizedBox(width: 8),
                          Text(
                            message.isClaimed ? 'CLAIMED' : 'CLAIM REQUEST',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) => Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFF9E9E9E),
          letterSpacing: 1,
        ),
      );

  Widget _detailCard(List<Widget> rows) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF8F8F8),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFEEEEEE)),
        ),
        child: Column(
          children: [
            for (int i = 0; i < rows.length; i++) ...[
              rows[i],
              if (i < rows.length - 1)
                const Divider(height: 1, indent: 16, endIndent: 16),
            ],
          ],
        ),
      );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.mono = false,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool mono;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: const Color(0xFF9E9E9E)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF9E9E9E),
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                SelectableText(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    color: valueColor ?? const Color(0xFF212121),
                    fontFamily: mono ? 'monospace' : null,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
