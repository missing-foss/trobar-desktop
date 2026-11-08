// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';

import 'l10n/gen/app_localizations.dart';

/// What the person chose about files on the card that no track claims.
class OrphansChoice {
  /// The files to delete; empty keeps them all.
  final List<String> delete;

  /// "Always keep files Trobar didn't put here": stop asking.
  final bool alwaysKeep;

  const OrphansChoice(this.delete, {this.alwaysKeep = false});
}

/// The question after a manual sync: every file, each with its own box,
/// nothing ticked, so keeping is what happens unless someone picks files to
/// delete. Keep is the emphasised choice; these may be files the person put
/// on the card on purpose. Pops an [OrphansChoice], or null when dismissed,
/// which keeps them too.
class OrphansDialog extends StatefulWidget {
  final List<String> orphans;

  const OrphansDialog({super.key, required this.orphans});

  @override
  State<OrphansDialog> createState() => _OrphansDialogState();
}

class _OrphansDialogState extends State<OrphansDialog> {
  final Set<String> _selected = {};
  bool _alwaysKeep = false;

  bool? get _all => _selected.isEmpty
      ? false
      : _selected.length == widget.orphans.length
          ? true
          : null;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final orphans = widget.orphans;
    return AlertDialog(
      title: Text(l.orphansTitle(orphans.length)),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l.orphansIntro),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              tristate: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(l.orphansSelectAll),
              value: _all,
              onChanged: _alwaysKeep
                  ? null
                  : (_) => setState(() {
                        if (_selected.length == orphans.length) {
                          _selected.clear();
                        } else {
                          _selected.addAll(orphans);
                        }
                      }),
            ),
            const Divider(height: 1),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final f in orphans)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(f, maxLines: 2, overflow: TextOverflow.ellipsis),
                        value: _selected.contains(f),
                        onChanged: _alwaysKeep
                            ? null
                            : (on) => setState(() =>
                                on == true ? _selected.add(f) : _selected.remove(f)),
                      ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(l.orphansAlwaysKeep),
              value: _alwaysKeep,
              onChanged: (on) => setState(() {
                _alwaysKeep = on == true;
                if (_alwaysKeep) _selected.clear();
              }),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(context,
                  OrphansChoice([for (final f in orphans) if (_selected.contains(f)) f])),
          child: Text(l.orphansDeleteSelected(_selected.length)),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, OrphansChoice(const [], alwaysKeep: _alwaysKeep)),
          child: Text(l.keep),
        ),
      ],
    );
  }
}
