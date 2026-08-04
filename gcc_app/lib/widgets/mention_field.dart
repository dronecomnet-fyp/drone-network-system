/// A composer that lets the operator attach objects by typing "@" (field
/// backlog #14).
///
/// The problem it solves is not typing speed. An announcement saying "the
/// drone in the north is down, go to the victim near the school" is
/// ambiguous to everyone who reads it, and the operator has no way to name
/// things the way the system names them without reading ids off another
/// tab and copying them by hand. Attaching an object writes the id AND the
/// coordinates, so a rescuer reading it on a phone has something they can
/// act on.
///
/// Deliberately PLAIN TEXT. Announcements already replicate as text across
/// the mesh and render in the rescue app as text; inventing a structured
/// attachment format would mean changing the wire contract, migrating the
/// nodes, and leaving older apps showing an empty message. A line like
/// "@DRONE_B (6.92710, 79.86120)" needs none of that and is readable even
/// in a log file.
library;

import 'package:flutter/material.dart';

/// Something the operator can attach.
class Mentionable {
  const Mentionable({
    required this.kind,
    required this.label,
    required this.token,
    this.subtitle = '',
    this.icon = Icons.link,
    this.color,
  });

  /// Grouping for the picker: "Degraded", "Drones", "Victims", "Rescuers".
  final String kind;

  /// What the operator recognises in the list.
  final String label;

  /// What is written into the message. Includes coordinates when known,
  /// because a name without a position is not actionable in the field.
  final String token;

  final String subtitle;
  final IconData icon;
  final Color? color;

  bool matches(String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return label.toLowerCase().contains(q) ||
        kind.toLowerCase().contains(q) ||
        subtitle.toLowerCase().contains(q);
  }
}

/// Replace the "@" that triggered the picker with [token].
///
/// Pure, and separated out because the off-by-one here is exactly the kind
/// of thing that silently eats a character in the middle of a sentence
/// somebody is composing under pressure. [atIndex] is the index of the "@"
/// itself. Returns the new text and where the caret should end up.
({String text, int caret}) applyMention(
    String text, int atIndex, String token) {
  if (atIndex < 0 || atIndex >= text.length || text[atIndex] != '@') {
    // The "@" moved or was deleted while the picker was open. Append
    // rather than corrupting a position we can no longer trust.
    final joined = text.isEmpty || text.endsWith(' ') ? '$text$token ' : '$text $token ';
    return (text: joined, caret: joined.length);
  }
  final before = text.substring(0, atIndex);
  final after = text.substring(atIndex + 1);
  // Only add the trailing space if the text does not already continue with
  // one. Attaching mid sentence otherwise leaves a double space, which
  // looks like a typo in a message that gets read out over a radio.
  final inserted = after.startsWith(' ') ? token : '$token ';
  return (text: '$before$inserted$after', caret: before.length + inserted.length);
}

class MentionField extends StatefulWidget {
  const MentionField({
    super.key,
    required this.controller,
    required this.options,
    this.decoration = const InputDecoration(labelText: 'Body'),
    this.maxLines = 4,
  });

  final TextEditingController controller;
  final List<Mentionable> options;
  final InputDecoration decoration;
  final int maxLines;

  @override
  State<MentionField> createState() => _MentionFieldState();
}

class _MentionFieldState extends State<MentionField> {
  String _previous = '';
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    _previous = widget.controller.text;
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final text = widget.controller.text;
    // Only react to the operator TYPING an "@", not to us inserting text,
    // and not to a paste that happens to contain one. Anything else would
    // make the picker jump out at unpredictable moments.
    final grewByOne = text.length == _previous.length + 1;
    final caret = widget.controller.selection.baseOffset;
    _previous = text;
    if (_picking || !grewByOne || caret <= 0 || caret > text.length) return;
    if (text[caret - 1] != '@') return;
    _openPicker(atIndex: caret - 1);
  }

  Future<void> _openPicker({required int atIndex}) async {
    _picking = true;
    final picked = await showMentionPicker(context, widget.options);
    _picking = false;
    if (picked == null) return; // leave the "@" they typed alone
    final r = applyMention(widget.controller.text, atIndex, picked.token);
    widget.controller.value = TextEditingValue(
      text: r.text,
      selection: TextSelection.collapsed(offset: r.caret),
    );
    _previous = r.text;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: widget.controller,
          maxLines: widget.maxLines,
          decoration: widget.decoration,
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            // The hint is not decoration: nobody discovers an "@" trigger
            // on their own, and an operator who never finds it goes back to
            // describing drones in prose.
            const Expanded(
              child: Text('Type @ to attach a drone, victim or rescuer',
                  style: TextStyle(fontSize: 11, color: Colors.white54)),
            ),
            TextButton.icon(
              icon: const Icon(Icons.alternate_email, size: 16),
              label: const Text('Attach'),
              onPressed: () async {
                final picked =
                    await showMentionPicker(context, widget.options);
                if (picked == null) return;
                final text = widget.controller.text;
                final joined = text.isEmpty || text.endsWith(' ')
                    ? '$text${picked.token} '
                    : '$text ${picked.token} ';
                widget.controller.value = TextEditingValue(
                  text: joined,
                  selection: TextSelection.collapsed(offset: joined.length),
                );
                _previous = joined;
              },
            ),
          ],
        ),
      ],
    );
  }
}

/// The picker itself. Grouped by kind, with degraded drones first because
/// that is the thing an operator is most often writing about in a hurry.
Future<Mentionable?> showMentionPicker(
    BuildContext context, List<Mentionable> options) {
  return showDialog<Mentionable>(
    context: context,
    builder: (ctx) {
      final search = TextEditingController();
      return StatefulBuilder(
        builder: (ctx, setState) {
          final q = search.text.trim();
          final matching = options.where((o) => o.matches(q)).toList();
          final kinds = <String, List<Mentionable>>{};
          for (final o in matching) {
            kinds.putIfAbsent(o.kind, () => []).add(o);
          }
          return AlertDialog(
            title: const Text('Attach to this message'),
            content: SizedBox(
              width: 460,
              height: 420,
              child: Column(
                children: [
                  TextField(
                    controller: search,
                    autofocus: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Filter',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: matching.isEmpty
                        ? const Center(
                            child: Text(
                              'Nothing to attach yet. Drones, victims and '
                              'rescuers appear here once the node has '
                              'reported them.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white54),
                            ),
                          )
                        : ListView(
                            children: [
                              for (final entry in kinds.entries) ...[
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                                  child: Text(entry.key.toUpperCase(),
                                      style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white60)),
                                ),
                                for (final o in entry.value)
                                  ListTile(
                                    dense: true,
                                    leading: Icon(o.icon, color: o.color),
                                    title: Text(o.label),
                                    subtitle: o.subtitle.isEmpty
                                        ? null
                                        : Text(o.subtitle,
                                            style:
                                                const TextStyle(fontSize: 11)),
                                    onTap: () => Navigator.of(ctx).pop(o),
                                  ),
                              ],
                            ],
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      );
    },
  );
}
