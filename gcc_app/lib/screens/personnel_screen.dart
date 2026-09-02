/// Personnel (file 04 screen 4): create a record and show the one-time
/// PIN LARGE with a copy button (it is never shown again, never stored);
/// list with revoke. The revocation-latency caveat is visible: a revoke
/// reaches other drones at DTN sync speed, not instantly.
library;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF1A0F0A),
              border: Border(
                  bottom: BorderSide(
                      color: Colors.white.withOpacity(0.08), width: 1)),
            ),
            child: const Text(
              'PERSONNEL',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 2,
              ),
            ),
          ),
          const Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline, size: 48, color: Colors.white24),
                  SizedBox(height: 16),
                  Text(
                    'HQ login required',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white54),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Use the labeled break-glass key in Settings.',
                    style: TextStyle(fontSize: 12, color: Colors.white38),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    final activeCount =
        data.personnel.items.where((p) => p.isActive).length;
    final totalCount = data.personnel.items.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Command-center header ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF1A0F0A),
            border: Border(
              bottom: BorderSide(
                  color: Colors.white.withOpacity(0.08), width: 1),
            ),
          ),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: activeCount > 0
                              ? Colors.greenAccent
                              : Colors.white24,
                          shape: BoxShape.circle,
                          boxShadow: activeCount > 0
                              ? [
                                  BoxShadow(
                                    color:
                                        Colors.greenAccent.withOpacity(0.5),
                                    blurRadius: 6,
                                  ),
                                ]
                              : [],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'PERSONNEL',
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
                    '$activeCount active  ·  $totalCount total  ·  updated ${formatAge(data.personnel.age)}',
                    style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white38,
                        letterSpacing: 0.3),
                  ),
                ],
              ),
              const Spacer(),
              FilledButton.icon(
                icon: const Icon(Icons.person_add, size: 16),
                label: const Text('Issue Credentials',
                    style: TextStyle(fontSize: 13)),
                onPressed: () => _showCreateDialog(context),
              ),
            ],
          ),
        ),

        // ── Sync note ──
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: const Text(
            'Records sync fleet-wide over DTN. Revocation blocks new logins on this drone instantly; other drones enforce it after their next sync.',
            style: TextStyle(fontSize: 11, color: Colors.white38),
          ),
        ),

        // ── List ──
        Expanded(
          child: data.personnel.items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.group_outlined,
                          size: 48, color: Colors.white24),
                      const SizedBox(height: 12),
                      const Text('No personnel records yet.',
                          style: TextStyle(
                              fontSize: 14, color: Colors.white54)),
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: () => _showCreateDialog(context),
                        child: const Text('Issue first credentials'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: data.personnel.items
                        .map((p) => _PersonnelTile(person: p))
                        .toList(),
                  ),
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
    bool busy = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => Dialog(
          backgroundColor: const Color(0xFF1E1612),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          child: SizedBox(
            width: 420,
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
                          color: Colors.cyanAccent.withOpacity(0.1),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color:
                                  Colors.cyanAccent.withOpacity(0.3)),
                        ),
                        child: const Icon(Icons.person_add,
                            size: 18, color: Colors.cyanAccent),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ISSUE CREDENTIALS',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 1,
                            ),
                          ),
                          Text(
                            'Create a new rescuer account',
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
                      const Text('NAME',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white38,
                              letterSpacing: 0.8)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: nameCtrl,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Full name of rescuer',
                          hintStyle: const TextStyle(
                              color: Colors.white24, fontSize: 13),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                                color:
                                    Colors.white.withOpacity(0.12)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                                color:
                                    Colors.white.withOpacity(0.12)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                                color: Colors.cyanAccent, width: 1.5),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Role + Expiry in a row
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                const Text('ROLE',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white38,
                                        letterSpacing: 0.8)),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  value: role,
                                  dropdownColor:
                                      const Color(0xFF1E1612),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13),
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor:
                                        Colors.white.withOpacity(0.05),
                                    border: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.circular(10),
                                      borderSide: BorderSide(
                                          color: Colors.white
                                              .withOpacity(0.12)),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.circular(10),
                                      borderSide: BorderSide(
                                          color: Colors.white
                                              .withOpacity(0.12)),
                                    ),
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 12),
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                        value: 'RESCUE_TEAM',
                                        child: Text('Rescue team')),
                                    DropdownMenuItem(
                                        value: 'HQ',
                                        child: Text('HQ operator')),
                                  ],
                                  onChanged: (v) => setState(
                                      () => role = v ?? 'RESCUE_TEAM'),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                const Text('EXPIRY',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white38,
                                        letterSpacing: 0.8)),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<int>(
                                  value: expiresHours,
                                  dropdownColor:
                                      const Color(0xFF1E1612),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13),
                                  decoration: InputDecoration(
                                    filled: true,
                                    fillColor:
                                        Colors.white.withOpacity(0.05),
                                    border: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.circular(10),
                                      borderSide: BorderSide(
                                          color: Colors.white
                                              .withOpacity(0.12)),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.circular(10),
                                      borderSide: BorderSide(
                                          color: Colors.white
                                              .withOpacity(0.12)),
                                    ),
                                    contentPadding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 12),
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                        value: 0,
                                        child: Text('No expiry')),
                                    DropdownMenuItem(
                                        value: 24,
                                        child: Text('24 hours')),
                                    DropdownMenuItem(
                                        value: 72,
                                        child: Text('3 days')),
                                    DropdownMenuItem(
                                        value: 168,
                                        child: Text('7 days')),
                                  ],
                                  onChanged: (v) => setState(
                                      () => expiresHours = v ?? 0),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      if (error != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color:
                                    Colors.redAccent.withOpacity(0.4)),
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
                                    color:
                                        Colors.white.withOpacity(0.15)),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(10)),
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
                                      if (nameCtrl.text.trim().isEmpty) {
                                        setState(() =>
                                            error = 'Name required');
                                        return;
                                      }
                                      setState(() => busy = true);
                                      try {
                                        final issued = await app.client
                                            .createPersonnel(
                                          nameCtrl.text.trim(),
                                          role: role,
                                          expiresHours: expiresHours,
                                        );
                                        await data.poll();
                                        if (ctx.mounted) {
                                          Navigator.of(ctx).pop();
                                          await _showPinDialog(
                                              context, issued);
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
                                  : const Icon(Icons.badge_outlined,
                                      size: 16),
                              label: Text(
                                  busy ? 'Creating...' : 'Issue'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(10)),
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

  Future<void> _showPinDialog(
      BuildContext context, IssuedPersonnel issued) async {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1E1612),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                        color: Colors.greenAccent.withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.greenAccent.withOpacity(0.3)),
                      ),
                      child: const Icon(Icons.verified_user_outlined,
                          size: 18, color: Colors.greenAccent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'CREDENTIALS ISSUED',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 1,
                            ),
                          ),
                          Text(
                            issued.name,
                            style: const TextStyle(
                                fontSize: 11, color: Colors.white54),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Body
              SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ID chip
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.1)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.badge_outlined,
                              size: 13, color: Colors.white38),
                          const SizedBox(width: 8),
                          const Text('ID  ',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.white38,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8)),
                          Text(issued.personnelId,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),

                    if (issued.signinCode.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      const Row(
                        children: [
                          Icon(Icons.qr_code_scanner,
                              size: 14, color: Colors.cyanAccent),
                          SizedBox(width: 8),
                          Text(
                            'SCAN QR CODE IN RESCUE APP',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.cyanAccent,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: QrImageView(
                            data: issued.signinCode,
                            size: 380,
                            errorCorrectionLevel: QrErrorCorrectLevel.L,
                            backgroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Works on ANY drone — even ones that have never heard of this person.',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(fontSize: 11, color: Colors.white38),
                      ),
                      const SizedBox(height: 20),
                      Divider(color: Colors.white.withOpacity(0.08)),
                      const SizedBox(height: 12),
                      const Row(
                        children: [
                          Icon(Icons.pin_outlined,
                              size: 13, color: Colors.white38),
                          SizedBox(width: 8),
                          Text(
                            'OR TYPE THIS PIN',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white38,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],

                    // PIN display
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Colors.cyanAccent.withOpacity(0.3)),
                        ),
                        child: SelectableText(
                          issued.pin,
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            color: Colors.cyanAccent,
                            fontFamily: 'monospace',
                            letterSpacing: 10,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Warning banner
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orangeAccent.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Colors.orangeAccent.withOpacity(0.3)),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              size: 16, color: Colors.orangeAccent),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Shown ONCE and stored nowhere. Hand it over now. If lost, revoke and re-issue. Do not leave this on screen in a shared space.',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.orangeAccent),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.copy, size: 15),
                            label: const Text('Copy PIN'),
                            onPressed: () => Clipboard.setData(
                                ClipboardData(text: issued.pin)),
                            style: OutlinedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                              side: BorderSide(
                                  color: Colors.white.withOpacity(0.2)),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            icon: const Icon(Icons.check, size: 15),
                            label: const Text('Done, PIN delivered'),
                            onPressed: () => Navigator.of(ctx).pop(),
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  Colors.greenAccent.withOpacity(0.2),
                              foregroundColor: Colors.greenAccent,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: const BorderSide(
                                    color: Colors.greenAccent, width: 1),
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
    );
  }
}

class _PersonnelTile extends StatelessWidget {
  final Personnel person;

  const _PersonnelTile({required this.person});

  @override
  Widget build(BuildContext context) {
    final revoked = !person.isActive;
    final roleColor =
        person.role == 'HQ' ? Colors.amberAccent : Colors.cyanAccent;
    final statusColor =
        revoked ? Colors.redAccent : Colors.greenAccent;

    return SizedBox(
      width: 270,
      child: Container(
        decoration: BoxDecoration(
          color: revoked
              ? Colors.white.withOpacity(0.03)
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: revoked
                ? Colors.white.withOpacity(0.07)
                : roleColor.withOpacity(0.2),
            width: revoked ? 1 : 1.2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Card header ──
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar + name row
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: revoked
                              ? Colors.redAccent.withOpacity(0.1)
                              : roleColor.withOpacity(0.12),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: revoked
                                ? Colors.redAccent.withOpacity(0.3)
                                : roleColor.withOpacity(0.4),
                          ),
                        ),
                        child: Icon(
                          revoked
                              ? Icons.person_off_outlined
                              : Icons.person_outline,
                          color: revoked ? Colors.redAccent : roleColor,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          person.name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: revoked ? Colors.white38 : Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Badges row
                  Row(
                    children: [
                      _badge(person.role, roleColor),
                      const SizedBox(width: 6),
                      _badge(
                          revoked ? 'REVOKED' : 'ACTIVE', statusColor),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Meta info tiles
                  _metaRow(
                      Icons.badge_outlined, 'ID', person.personnelId),
                  const SizedBox(height: 6),
                  _metaRow(Icons.calendar_today_outlined, 'ISSUED',
                      person.issuedAt),
                  if (person.expiresAt.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _metaRow(Icons.timer_off_outlined, 'EXPIRES',
                        person.expiresAt),
                  ],
                ],
              ),
            ),

            // ── Revoke button at the bottom of the card ──
            if (!revoked)
              GestureDetector(
                onTap: () => _confirmRevoke(context),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.1),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(14),
                      bottomRight: Radius.circular(14),
                    ),
                    border: Border(
                      top: BorderSide(
                          color: Colors.redAccent.withOpacity(0.3)),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.block, size: 13, color: Colors.redAccent),
                      SizedBox(width: 6),
                      Text(
                        'REVOKE ACCESS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.redAccent,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.03),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(14),
                    bottomRight: Radius.circular(14),
                  ),
                  border: Border(
                    top: BorderSide(
                        color: Colors.white.withOpacity(0.06)),
                  ),
                ),
                child: const Center(
                  child: Text(
                    'ACCESS REVOKED',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white24,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _metaRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 11, color: Colors.white38),
        const SizedBox(width: 5),
        Text(
          '$label  ',
          style: const TextStyle(
            fontSize: 10,
            color: Colors.white38,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 10, color: Colors.white54),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Future<void> _confirmRevoke(BuildContext context) async {
    final app = context.read<AppState>();
    final data = context.read<DataStore>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1E1612),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.05),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                  border: Border(
                    bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.warning_amber_rounded,
                          color: Colors.redAccent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'CONFIRM REVOCATION',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Colors.redAccent,
                              letterSpacing: 1,
                            ),
                          ),
                          Text(
                            'Revoke access for ${person.name}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.white54),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Body
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Text(
                      'Are you sure you want to revoke this credential?',
                      style: TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                          fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Access is blocked immediately on this drone. Other drones in the fleet will enforce this revocation after their next sync.',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.6),
                          height: 1.4),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white54,
                              side: BorderSide(
                                  color: Colors.white.withOpacity(0.15)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.redAccent.withOpacity(0.2),
                              foregroundColor: Colors.redAccent,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: const BorderSide(
                                    color: Colors.redAccent, width: 1),
                              ),
                            ),
                            child: const Text('Revoke Now',
                                style: TextStyle(fontWeight: FontWeight.w700)),
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
