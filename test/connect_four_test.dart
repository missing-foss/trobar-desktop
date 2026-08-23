// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// #25: the "duel the bard" Connect Four logic — win detection in all four
// directions, draw, and the bard's win/block/centre heuristic. The widget is
// thin; this is where the game is actually verified.

import 'package:flutter_test/flutter_test.dart';
import 'package:trobar_desktop/connect_four.dart';

void main() {
  // Drop a list of (col, player) moves in order.
  ConnectFour play(List<List<int>> moves) {
    final g = ConnectFour();
    for (final m in moves) {
      g.drop(m[0], m[1]);
    }
    return g;
  }

  group('win detection', () {
    test('horizontal four', () {
      final g = play([[0, 1], [1, 1], [2, 1], [3, 1]]);
      expect(g.winner, cfHuman);
    });

    test('vertical four', () {
      final g = play([[0, 2], [0, 2], [0, 2], [0, 2]]);
      expect(g.winner, cfBard);
    });

    test('diagonal / four', () {
      // discs at (0,0),(1,1),(2,2),(3,3) for player 1, on filler for player 2.
      final g = play([
        [0, 1],
        [1, 2], [1, 1],
        [2, 2], [2, 2], [2, 1],
        [3, 2], [3, 2], [3, 2], [3, 1],
      ]);
      expect(g.winner, cfHuman);
    });

    test('diagonal \\ four', () {
      // discs at (3,0),(2,1),(1,2),(0,3) for player 1.
      final g = play([
        [3, 1],
        [2, 2], [2, 1],
        [1, 2], [1, 2], [1, 1],
        [0, 2], [0, 2], [0, 2], [0, 1],
      ]);
      expect(g.winner, cfHuman);
    });

    test('three in a row is not a win', () {
      final g = play([[0, 1], [1, 1], [2, 1]]);
      expect(g.winner, cfEmpty);
      expect(g.isOver, isFalse);
    });
  });

  test('a full board with no line is a draw', () {
    // color(c,r) = (c + 2r) % 5 < 2 ? human : bard. The step is coprime to 5 in
    // every direction, so any 4 consecutive cells hold 4 distinct residues —
    // neither colour can occupy 4 of them. So the full board has no four-run.
    final g = ConnectFour();
    for (var c = 0; c < cfCols; c++) {
      for (var r = 0; r < cfRows; r++) {
        g.drop(c, ((c + 2 * r) % 5 < 2) ? cfHuman : cfBard);
      }
    }
    expect(g.isFull, isTrue);
    expect(g.winner, cfDraw);
  });

  group('illegal moves', () {
    test('drop into a full column returns null', () {
      final g = play([[0, 1], [0, 2], [0, 1], [0, 2], [0, 1], [0, 2]]);
      expect(g.canDrop(0), isFalse);
      expect(g.drop(0, 1), isNull);
    });

    test('no drops once the game is over', () {
      final g = play([[0, 1], [1, 1], [2, 1], [3, 1]]); // human already won
      expect(g.drop(4, 2), isNull);
    });
  });

  group('bard heuristic', () {
    test('prefers the centre on an empty board', () {
      expect(ConnectFour().bardMove(), 3);
    });

    test('takes its own win when available', () {
      // bard has three across cols 0-2 at row 0; the win is col 3.
      final g = play([[0, 2], [1, 2], [2, 2]]);
      expect(g.bardMove(), 3);
    });

    test('blocks the human\'s winning move', () {
      // human threatens four across cols 2-4 (has 2,3,4)? build 3-in-a-row
      // cols 1-3, open ends 0 and 4 — bard must block one of them.
      final g = play([[1, 1], [2, 1], [3, 1]]);
      expect(g.bardMove(), anyOf(0, 4));
    });

    test('its own win beats blocking the human', () {
      // human threatens a horizontal win at col 3 (0,1,2 across); the bard has a
      // vertical three in col 5. It must complete its own win (col 5), not block.
      final g = play([[0, 1], [1, 1], [2, 1], [5, 2], [5, 2], [5, 2]]);
      expect(g.bardMove(), 5);
    });
  });
}
