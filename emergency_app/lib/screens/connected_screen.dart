/// Connected flow (file 06 screen 4): on connectivity to the drone, POST
/// the stored points to /checkin (marking them uploaded locally), then
/// show the SOS composer which posts a checkin with sos=true so it enters
/// the rescue message queue (file 02 behavior).
///
/// Rebuilt for field backlog #11 to match the captive portal: the victim
/// TAPS what they need instead of typing it, and location is shared unless
/// they opt out. Two reasons this matters more than it looks:
///
///  1. Typing is the thing people cannot do here. Wet hands, a cracked
///     screen, a language the keyboard is not set to, panic. Every tester
///     comment about the portal applied equally to this screen, which had
///     an empty text box as its only input.
///  2. The options come FROM THE NODE, so the app and the portal offer the
///     same list. If the operator edits the options for this mission, a
///     victim with the app and a victim with a browser report the same
///     vocabulary, and the rescue team's tally means something.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rescue_mesh_shared/rescue_mesh_shared.dart' as shared;

import '../constants.dart';
import '../services/upload_service.dart';
import '../state/app_controller.dart';
import 'conversation_screen.dart';

class ConnectedScreen extends StatefulWidget {
  const ConnectedScreen({super.key});

  @override
  State<ConnectedScreen> createState() => _ConnectedScreenState();
}

class _ConnectedScreenState extends State<ConnectedScreen>
    with SingleTickerProviderStateMixin {
  final _noteController = TextEditingController();
  bool _uploading = false;
  bool _sending = false;
  String? _uploadMessage;
  bool _sosSent = false;

  /// Stock until the node answers. Never null, so there is always
  /// something to tap even against a node running older code.
  shared.PortalOptions _options = shared.PortalOptions.stock;
  final Set<String> _selected = {};

  /// Opt OUT, not opt in. A rescue team that knows only that somebody
  /// needs help cannot act on it.
  bool _shareLocation = true;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    
    Future.microtask(_uploadStored);
    Future.microtask(_loadOptions);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    final client = shared.RescueMeshClient(
        baseUrl: kDroneBaseUrl, timeout: const Duration(seconds: 5));
    try {
      final opts = await client.getPortalOptions();
      if (!mounted || opts.situations.isEmpty) return;
      setState(() => _options = opts);
    } catch (_) {
      // Older node, or a slow link. The stock list is already showing and
      // is deliberately need-based, so it is never wrong, only less
      // tailored. Saying nothing is right: this is not the victim's
      // problem to solve.
    } finally {
      client.close();
    }
  }

  Future<void> _uploadStored() async {
    setState(() => _uploading = true);
    try {
      final UploadResult r = await context.read<AppController>().uploadStored();
      if (!mounted) return;
      setState(() => _uploadMessage = 'Location synced successfully (${r.stored} points).');
      await context.read<AppController>().refreshPoints();
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadMessage = 'Waiting for strong connection...');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// What the rescue team reads. Tapped labels first because they are the
  /// structured part, then anything typed. Built here rather than on the
  /// node so the message is identical whichever route it arrived by.
  String _composeText() {
    final labels = _options.situations
        .where((s) => _selected.contains(s.id))
        .map((s) => s.label)
        .toList();
    final note = _noteController.text.trim();
    if (labels.isEmpty) return note.isEmpty ? 'SOS, no details given' : note;
    final joined = labels.join('; ');
    return note.isEmpty ? joined : '$joined. $note';
  }

  Future<void> _sendSos() async {
    setState(() => _sending = true);
    try {
      await context
          .read<AppController>()
          .sendSos(_composeText(), includeLocation: _shareLocation);
      if (!mounted) return;
      setState(() {
        _sosSent = true;
        _sending = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('SOS failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('AERO-LINK Emergency Connect'),
      ),
      body: Column(
        children: [
          _buildStatusBanner(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                if (_sosSent) _sentCard() else ..._composer(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: _uploading ? Colors.blue.shade50 : Colors.green.shade50,
        border: Border(
          bottom: BorderSide(
            color: _uploading ? Colors.blue.shade200 : Colors.green.shade200,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_uploading)
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Opacity(
                  opacity: 0.5 + (_pulseController.value * 0.5),
                  child: const Icon(Icons.sync, color: Colors.blue, size: 16),
                );
              },
            )
          else
            const Icon(Icons.check_circle, color: Colors.green, size: 16),
          const SizedBox(width: 8),
          Text(
            _uploading ? 'Syncing Location Data...' : (_uploadMessage ?? 'Location synced successfully.'),
            style: TextStyle(
              color: _uploading ? Colors.blue.shade900 : Colors.green.shade900,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sentCard() {
    return Card(
      color: Colors.white,
      elevation: 4,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Column(
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 800),
              curve: Curves.elasticOut,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_rounded, color: Colors.green, size: 64),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            const Text(
              'SOS Alert Dispatched',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _shareLocation
                  ? 'The rescue team has received your location and situation details. Please remain in your current location and keep your Wi-Fi connected to the drone.'
                  : 'The rescue team has received your situation details. Location sharing was disabled. Please keep your Wi-Fi connected to the drone.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: Colors.black54, height: 1.5),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              icon: const Icon(Icons.forum),
              label: const Text('See if the team has replied'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ConversationScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _composer() {
    return [
      Text(
        _options.headline.isEmpty
            ? 'Please select your current situation:'
            : _options.headline,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.black87),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _options.situations.map((s) => _optionChip(s)).toList(),
      ),
      const SizedBox(height: 20),
      
      // Privacy & Trust Card
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          value: _shareLocation,
          activeColor: Theme.of(context).primaryColor,
          onChanged: (v) => setState(() => _shareLocation = v),
          title: Row(
            children: [
              Icon(Icons.security, size: 20, color: Theme.of(context).primaryColor),
              const SizedBox(width: 8),
              const Text('Share my location',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ],
          ),
          // subtitle: Padding(
          //   padding: const EdgeInsets.only(top: 4),
          //   child: Text(
          //     _shareLocation
          //         ? 'Shared securely only with rescue personnel.'
          //         : 'Location sharing is disabled.',
          //     style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          //   ),
          // ),
        ),
      ),
      const SizedBox(height: 16),
      
      const Text('Additional details (optional)',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87)),
      const SizedBox(height: 6),
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: TextField(
          controller: _noteController,
          maxLines: 2,
          maxLength: 400,
          style: const TextStyle(fontSize: 15),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2),
            ),
            contentPadding: const EdgeInsets.all(16),
            hintText: 'e.g. two adults, one injured, on the roof',
            hintStyle: TextStyle(color: Colors.grey.shade400),
          ),
        ),
      ),
      const SizedBox(height: 20),
      
      // Massive SOS Button
      Container(
        width: double.infinity,
        height: 60,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withOpacity(0.4),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
          gradient: const LinearGradient(
            colors: [Color(0xFFE53935), Color(0xFFC62828)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: _sending ? null : _sendSos,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_sending)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                  )
                else
                  const Icon(Icons.emergency_share, color: Colors.white, size: 28),
                const SizedBox(width: 12),
                Text(
                  _sending ? 'SENDING...' : 'SEND NOW',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 24),
    ];
  }

  Widget _optionChip(shared.PortalSituation s) {
    final on = _selected.contains(s.id);
    final isUrgent = s.urgent;
    
    // Choose appropriate standard icons based on keywords in the label
    IconData getIcon(String label) {
      final l = label.toLowerCase();
      if (l.contains('fire')) return Icons.local_fire_department;
      if (l.contains('medic') || l.contains('injur')) return Icons.medical_services;
      if (l.contains('water') || l.contains('flood')) return Icons.water_drop;
      if (l.contains('trapped')) return Icons.house_siding;
      if (l.contains('food')) return Icons.restaurant;
      if (l.contains('power')) return Icons.power;
      return Icons.info_outline;
    }

    final accentColor = isUrgent ? Colors.red.shade700 : Theme.of(context).primaryColor;

    return FilterChip(
      selected: on,
      showCheckmark: false,
      avatar: Icon(
        getIcon(s.label),
        size: 18,
        color: on ? Colors.white : (isUrgent ? Colors.red.shade700 : Colors.black54),
      ),
      label: Text(
        s.label,
        style: TextStyle(
          fontSize: 15,
          fontWeight: on ? FontWeight.w600 : FontWeight.w500,
          color: on ? Colors.white : Colors.black87,
        ),
      ),
      selectedColor: accentColor,
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: on ? accentColor : Colors.grey.shade300,
          width: 1.5,
        ),
      ),
      elevation: on ? 4 : 0,
      pressElevation: 2,
      shadowColor: accentColor.withOpacity(0.4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      onSelected: (bool selected) {
        setState(() {
          if (selected) {
            _selected.add(s.id);
          } else {
            _selected.remove(s.id);
          }
        });
      },
    );
  }
}
