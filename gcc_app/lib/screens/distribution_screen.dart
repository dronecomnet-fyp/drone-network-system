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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Professional Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: const Color(0xFF1A0F0A),
            border: Border(
                bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orangeAccent.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.orangeAccent.withOpacity(0.3)),
                ),
                child: const Icon(Icons.wifi_tethering, color: Colors.orangeAccent, size: 18),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('FIELD SHARE',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 1.5,
                        )),
                    const SizedBox(height: 4),
                    const Text('Distribute APKs and offline maps over local Wi-Fi',
                        style: TextStyle(fontSize: 11, color: Colors.white38, letterSpacing: 0.3)),
                  ],
                ),
              ),
              if (server.folderPath != null)
                IconButton(
                  tooltip: 'Rescan folder',
                  icon: const Icon(Icons.refresh, color: Colors.white54, size: 20),
                  onPressed: server.refresh,
                ),
            ],
          ),
        ),

        // Body
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.02),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                ),
                child: const Text(
                  'Hand out the app and offline maps over local Wi-Fi, no internet '
                  'needed. Copy the files onto this laptop first, connect everyone '
                  'to the same router or this laptop\'s hotspot, then start sharing.',
                  style: TextStyle(fontSize: 13, color: Colors.white54, height: 1.5),
                ),
              ),
              const SizedBox(height: 24),
              _FolderCard(server: server, onChoose: () => _chooseFolder(context)),
              const SizedBox(height: 16),
              _ServerCard(server: server),
              if (server.error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent),
                      const SizedBox(width: 12),
                      Expanded(child: Text(server.error!, style: const TextStyle(color: Colors.redAccent))),
                    ],
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
        ),
      ],
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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('1. FOLDER TO SHARE',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.white54,
                  letterSpacing: 1)),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Text(
              path ?? 'No folder chosen yet.',
              style: TextStyle(
                fontSize: 13,
                color: path == null ? Colors.orangeAccent : Colors.cyanAccent,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onChoose,
            icon: const Icon(Icons.folder_open, size: 16),
            label: Text(path == null ? 'CHOOSE FOLDER' : 'CHANGE FOLDER', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.1),
              foregroundColor: Colors.white,
            ),
          ),
        ],
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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('2. SHARING',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white54,
                      letterSpacing: 1)),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: running ? Colors.greenAccent.withOpacity(0.15) : Colors.white24,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: running ? Colors.greenAccent.withOpacity(0.4) : Colors.transparent),
                ),
                child: Text(
                  running ? 'ON (PORT ${server.port})' : 'OFF',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: running ? Colors.greenAccent : Colors.white70,
                      letterSpacing: 1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: server.folderPath == null
                ? null
                : (running ? server.stop : server.start),
            icon: Icon(running ? Icons.stop : Icons.wifi_tethering, size: 16),
            style: FilledButton.styleFrom(
              backgroundColor: running ? Colors.redAccent.withOpacity(0.2) : Colors.orangeAccent.withOpacity(0.2),
              foregroundColor: running ? Colors.redAccent : Colors.orangeAccent,
              side: BorderSide(color: running ? Colors.redAccent : Colors.orangeAccent),
            ),
            label: Text(running ? 'STOP SHARING' : 'START SHARING', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
          ),
        ],
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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.cyanAccent.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('3. PERSONNEL SCAN OR TYPE THIS',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.cyanAccent,
                  letterSpacing: 1)),
          const SizedBox(height: 24),
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: url,
                size: 220,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.cyanAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
              ),
              child: SelectableText(
                url,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  color: Colors.cyanAccent,
                ),
              ),
            ),
          ),
          if (server.urls.length > 1) ...[
            const SizedBox(height: 20),
            const Text('OTHER ADDRESSES ON THIS LAPTOP:',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white38, letterSpacing: 0.8)),
            const SizedBox(height: 8),
            for (final u in server.urls.skip(1))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: SelectableText(u,
                    style: const TextStyle(fontFamily: 'monospace', color: Colors.white54, fontSize: 13)),
              ),
          ],
          const SizedBox(height: 20),
          const Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: Colors.white38),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'The phone must be on the same Wi-Fi as this laptop.',
                  style: TextStyle(fontSize: 12, color: Colors.white38),
                ),
              ),
            ],
          ),
        ],
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
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('FILES BEING SHARED',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white54,
                      letterSpacing: 1)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${files.length}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (server.folderPath == null)
            const Text('Choose a folder to see its files.', style: TextStyle(color: Colors.white38, fontSize: 13))
          else if (files.isEmpty)
            const Text('This folder has no files yet.', style: TextStyle(color: Colors.white38, fontSize: 13))
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: files.length,
              separatorBuilder: (_, __) => Divider(color: Colors.white.withOpacity(0.05), height: 16),
              itemBuilder: (ctx, i) {
                final f = files[i];
                return Row(
                  children: [
                    Icon(_iconFor(f.name), size: 18, color: Colors.white54),
                    const SizedBox(width: 12),
                    Expanded(child: Text(f.name, style: const TextStyle(fontSize: 13, color: Colors.white))),
                    Text(f.humanSize, style: const TextStyle(fontSize: 12, color: Colors.white38)),
                  ],
                );
              },
            ),
        ],
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
