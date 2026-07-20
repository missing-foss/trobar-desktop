// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// #25: pure Connect Four game logic for the "duel the bard" easter egg — no
// Flutter, so it's unit-testable (the widget stays thin). Cells are 0 empty,
// 1 human, 2 bard. Row 0 is the bottom of a column.

const cfCols = 7;
const cfRows = 6;

const cfEmpty = 0;
const cfHuman = 1;
const cfBard = 2;
const cfDraw = 3; // winner value when the board fills with no line

class ConnectFour {
  // _cols[c] is a bottom-up stack of discs (length 0..cfRows).
  final List<List<int>> _cols =
      List.generate(cfCols, (_) => <int>[], growable: false);

  int? lastCol;
  int? lastRow;

  /// 0 = in progress, 1/2 = that player won, 3 = draw.
  int winner = cfEmpty;

  bool get isOver => winner != cfEmpty;

  bool canDrop(int col) =>
      col >= 0 && col < cfCols && _cols[col].length < cfRows;

  bool get isFull => _cols.every((c) => c.length >= cfRows);

  /// Disc at [col],[row] (row 0 = bottom), or 0 if empty/out of range.
  int cellAt(int col, int row) {
    if (col < 0 || col >= cfCols || row < 0 || row >= cfRows) return cfEmpty;
    return row < _cols[col].length ? _cols[col][row] : cfEmpty;
  }

  /// Drop a disc for [player] (1 or 2) into [col]. Returns the landing row, or
  /// null if the move is illegal (column full, or the game is over).
  int? drop(int col, int player) {
    if (isOver || !canDrop(col)) return null;
    _cols[col].add(player);
    final row = _cols[col].length - 1;
    lastCol = col;
    lastRow = row;
    if (_wins(col, row, player)) {
      winner = player;
    } else if (isFull) {
      winner = cfDraw;
    }
    return row;
  }

  /// The bard's move (player 2): win if it can, else block the human's winning
  /// move, else prefer the centre. A deliberately simple heuristic — a credible
  /// opponent without minimax. Returns the chosen column, or null if none.
  int? bardMove() {
    if (isOver) return null;
    for (var c = 0; c < cfCols; c++) {
      if (canDrop(c) && _wouldWin(c, cfBard)) return c;
    }
    for (var c = 0; c < cfCols; c++) {
      if (canDrop(c) && _wouldWin(c, cfHuman)) return c;
    }
    for (final c in const [3, 2, 4, 1, 5, 0, 6]) {
      if (canDrop(c)) return c;
    }
    return null;
  }

  bool _wouldWin(int col, int player) {
    final row = _cols[col].length; // where a disc would land
    _cols[col].add(player);
    final win = _wins(col, row, player);
    _cols[col].removeLast();
    return win;
  }

  bool _wins(int col, int row, int player) {
    // Four directions; count the run through (col,row) both ways.
    const dirs = [
      [1, 0], // horizontal
      [0, 1], // vertical
      [1, 1], // diagonal /
      [1, -1], // diagonal \
    ];
    for (final d in dirs) {
      final run =
          1 + _count(col, row, d[0], d[1], player) +
              _count(col, row, -d[0], -d[1], player);
      if (run >= 4) return true;
    }
    return false;
  }

  int _count(int col, int row, int dc, int dr, int player) {
    var n = 0;
    var c = col + dc;
    var r = row + dr;
    while (cellAt(c, r) == player) {
      n++;
      c += dc;
      r += dr;
    }
    return n;
  }
}
