/// Connected flow (file 06 screen 4): on connectivity to the drone, POST
/// the stored points to /checkin (marking them uploaded locally), then
/// show the SOS composer (short text, optional current GPS attach) which
/// posts a checkin with sos=true so it enters the rescue message queue
/// (file 02 behavior).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/upload_service.dart';
import '../state/app_controller.dart';

class ConnectedScreen extends StatefulWidget {
  const ConnectedScreen({super.key});

  @override
  State<ConnectedScreen> createState() => _ConnectedScreenState();
}

class _ConnectedScreenState extends State<ConnectedScreen> {
  final _sosController = TextEditingController();
  bool _uploading = false;
  bool _sending = false;
  String? _uploadMessage;
  bool _sosSent = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_uploadStored);
  }

  @override
  void dispose() {
    _sosController.dispose();
    super.dispose();
  }

  Future<void> _uploadStored() async {
    setState(() => _uploading = true);
    try {
      final UploadResult r = await context.read<AppController>().uploadStored();
      if (!mounted) return;
      setState(() => _uploadMessage =
          'Sent ${r.stored} saved location point(s) to the rescue team.');
      await context.read<AppController>().refreshPoints();
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploadMessage =
          'Could not upload yet: check you are on the drone Wi-Fi. ($e)');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _sendSos() async {
    setState(() => _sending = true);
    try {
      await context.read<AppController>().sendSos(_sosController.text.trim());
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
      appBar: AppBar(
        title: const Text('Connected to rescue drone'),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Colors.green.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (_uploading)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const Icon(Icons.cloud_done, color: Colors.green),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(_uploading
                        ? 'Sending your saved locations...'
                        : (_uploadMessage ?? 'Ready.')),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (_sosSent)
            Card(
              color: Colors.red.shade50,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(Icons.check_circle, color: Colors.red, size: 40),
                    SizedBox(height: 8),
                    Text(
                      'SOS sent. The rescue team has your location and '
                      'message. Stay where you are and keep this Wi-Fi.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else ...[
            Text('Send an SOS',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Add a short message (injuries, people with you, anything the '
              'rescue team should know). Your latest location is attached '
              'automatically.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _sosController,
              maxLines: 3,
              maxLength: 400,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'e.g. two adults, one injured, on the roof',
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 60,
              child: FilledButton.icon(
                icon: const Icon(Icons.sos),
                label: Text(_sending ? 'Sending...' : 'SEND SOS NOW',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.shade700),
                onPressed: _sending ? null : _sendSos,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
