// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// #25: the "duel the bard" Connect Four dialog — a thin view over
// connect_four.dart. Drop with a column click or keys 1-7; the bard replies.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'connect_four.dart';
import 'l10n/gen/app_localizations.dart';

class ConnectFourDialog extends StatefulWidget {
  const ConnectFourDialog({super.key});

  @override
  State<ConnectFourDialog> createState() => _ConnectFourDialogState();
}

class _ConnectFourDialogState extends State<ConnectFourDialog> {
  ConnectFour _game = ConnectFour();
  bool _bardThinking = false;

  void _humanDrop(int col) {
    if (_game.isOver || _bardThinking || !_game.canDrop(col)) return;
    setState(() => _game.drop(col, cfHuman));
    if (_game.isOver) return;
    setState(() => _bardThinking = true);
    // A beat before the bard replies, so its move reads as a response.
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final c = _game.bardMove();
      setState(() {
        if (c != null) _game.drop(c, cfBard);
        _bardThinking = false;
      });
    });
  }

  void _reset() => setState(() {
        _game = ConnectFour();
        _bardThinking = false;
      });

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final n = int.tryParse(e.logicalKey.keyLabel);
    if (n != null && n >= 1 && n <= cfCols) {
      _humanDrop(n - 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String _status(AppLocalizations l) {
    switch (_game.winner) {
      case cfHuman:
        return l.duelYouWin;
      case cfBard:
        return l.duelBardWins;
      case cfDraw:
        return l.duelDraw;
      default:
        return _bardThinking ? l.duelBardThinking : l.duelYourTurn;
    }
  }

  Color _discColor(BuildContext context, int cell) {
    final scheme = Theme.of(context).colorScheme;
    switch (cell) {
      case cfHuman:
        return scheme.primary;
      case cfBard:
        return const Color(0xFFF6C915); // the bard's "coin" gold
      default:
        return scheme.surfaceContainerHighest;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l.duelTitle),
      content: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_status(l),
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              // Rows top (r = cfRows-1) down to bottom (r = 0).
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var r = cfRows - 1; r >= 0; r--)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var c = 0; c < cfCols; c++)
                          GestureDetector(
                            onTap: () => _humanDrop(c),
                            child: Container(
                              width: 34,
                              height: 34,
                              margin: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: _discColor(context, _game.cellAt(c, r)),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(l.duelHint,
                style: Theme.of(context).textTheme.labelSmall,
                textAlign: TextAlign.center),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _reset, child: Text(l.duelPlayAgain)),
        FilledButton(
            onPressed: () => Navigator.of(context).pop(), child: Text(l.close)),
      ],
    );
  }
}
