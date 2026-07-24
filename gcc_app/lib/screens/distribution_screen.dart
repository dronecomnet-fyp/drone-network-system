/// Field Share screen (task E): the operator-facing control for the local
/// distribution server (services/distribution_server.dart).
///
/// Flow at a disaster site with no internet: the operator has already
/// copied the field bundle (rescue-app APK, offline .mbtiles region maps)
/// onto the laptop from a USB stick. Everyone joins the same local Wi-Fi (a
/// travel router or the laptop hotspot). Here the operator picks that
/// folder, taps Start, and shows the phone screen: a link and a QR code.
/// Personnel scan the QR, open a plain web page, and download what they
/// need. The server keeps running while the operator works in other tabs
/// (it lives as a root provider).
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/distribution_server.dart';

class DistributionScreen extends StatelessWidget {
  const DistributionScreen({super.key});

  Future<void> _chooseFolder(BuildContext context) async {
    final server = context.read<DistributionServer>();
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose the folder to share (APKs, map files)',
    );
    if (path != null) {
      await server.setFolder(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final server = context.watch<DistributionServer>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Field Share'),
        actions: [
          if (server.folderPath != null)
            IconButton(
              tooltip: 'Rescan folder',
              icon: const Icon(Icons.refresh),
              onPressed: server.refresh,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Hand out the app and offline maps over local Wi-Fi, no internet '
            'needed. Copy the files onto this laptop first, connect everyone '
            'to the same router or this laptop\'s hotspot, then start sharing.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          _FolderCard(server: server, onChoose: () => _chooseFolder(context)),
          const SizedBox(height: 16),
          _ServerCard(server: server),
          if (server.error != null) ...[
            const SizedBox(height: 16),
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline),
                    const SizedBox(width: 10),
                    Expanded(child: Text(server.error!)),
                  ],
                ),
              ),
            ),
          ],
          if (server.running && server.primaryUrl != null) ...[
            const SizedBox(height: 16),
            _ShareCard(server: server),
          ],
          const SizedBox(height: 16),
          _FilesCard(server: server),
        ],
      ),
    );
  }
}

class _FolderCard extends StatelessWidget {
  const _FolderCard({required this.server, required this.onChoose});

  final DistributionServer server;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final path = server.folderPath;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('1. Folder to share',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              path ?? 'No folder chosen yet.',
              style: TextStyle(
                color: path == null ? Colors.orange : null,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onChoose,
              icon: const Icon(Icons.folder_open),
              label: Text(path == null ? 'Choose folder' : 'Change folder'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerCard extends StatelessWidget {
  const _ServerCard({required this.server});

  final DistributionServer server;

  @override
  Widget build(BuildContext context) {
    final running = server.running;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('2. Sharing',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(width: 10),
                Chip(
                  label: Text(running ? 'ON (port ${server.port})' : 'OFF'),
                  backgroundColor:
                      running ? Colors.green.shade800 : Colors.grey.shade800,
                  labelStyle: const TextStyle(color: Colors.white),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: server.folderPath == null
                      ? null
                      : (running ? server.stop : server.start),
                  icon: Icon(running ? Icons.stop : Icons.wifi_tethering),
                  style: running
                      ? FilledButton.styleFrom(backgroundColor: Colors.red)
                      : null,
                  label: Text(running ? 'Stop sharing' : 'Start sharing'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareCard extends StatelessWidget {
  const _ShareCard({required this.server});

  final DistributionServer server;

  @override
  Widget build(BuildContext context) {
    final url = server.primaryUrl!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('3. Personnel scan or type this',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                color: Colors.white,
                child: QrImageView(
                  data: url,
                  size: 220,
                  backgroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 16),
            SelectableText(
              url,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
            if (server.urls.length > 1) ...[
              const SizedBox(height: 8),
              Text('Other addresses on this laptop:',
                  style: Theme.of(context).textTheme.bodySmall),
              for (final u in server.urls.skip(1))
                SelectableText(u,
                    style: const TextStyle(fontFamily: 'monospace')),
            ],
            const SizedBox(height: 8),
            Text(
              'The phone must be on the same Wi-Fi as this laptop.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _FilesCard extends StatelessWidget {
  const _FilesCard({required this.server});

  final DistributionServer server;

  @override
  Widget build(BuildContext context) {
    final files = server.files;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Files being shared (${files.length})',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (server.folderPath == null)
              const Text('Choose a folder to see its files.')
            else if (files.isEmpty)
              const Text('This folder has no files yet.')
            else
              ...files.map(
                (f) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_iconFor(f.name)),
                  title: Text(f.name),
                  trailing: Text(f.humanSize),
                ),
              ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.apk')) return Icons.android;
    if (lower.endsWith('.mbtiles')) return Icons.map;
    if (lower.endsWith('.pdf') || lower.endsWith('.txt')) {
      return Icons.description;
    }
    return Icons.insert_drive_file;
  }
}
