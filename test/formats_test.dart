// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// desktop#31: dates in the user's language with the year, decimal commas
// accepted, plurals that agree with their count, and the `df` parsing.

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:trobar_desktop/card_store.dart';
import 'package:trobar_desktop/formats.dart';
import 'package:trobar_desktop/l10n/gen/app_localizations.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr');
    await initializeDateFormatting('en');
  });

  group('syncTimeText', () {
    final when = DateTime(2026, 10, 16, 14, 5);
    test('French: day first, the year, 24-hour time', () {
      expect(syncTimeText(when, 'fr'), '16/10/2026 14:05');
    });
    test('English: month first, the year', () {
      expect(syncTimeText(when, 'en'), '10/16/2026 14:05');
    });
  });

  group('parseGigabytes', () {
    test('a decimal point or a decimal comma', () {
      expect(parseGigabytes('1.5'), 1.5);
      expect(parseGigabytes('1,5'), 1.5);
      expect(parseGigabytes(' 32 '), 32);
    });
    test('not a number, or a grouped one, is refused', () {
      expect(parseGigabytes('abc'), isNull);
      expect(parseGigabytes('1,000.5'), isNull);
      expect(parseGigabytes('1.000,5'), isNull);
    });
  });

  group('plurals', () {
    final en = lookupAppLocalizations(const Locale('en'));
    final fr = lookupAppLocalizations(const Locale('fr'));
    test('English agrees with the count', () {
      expect(en.missingTitle(1), '1 track missing on this card');
      expect(en.missingTitle(3), '3 tracks missing on this card');
      expect(en.orphansTitle(1), '1 file on this card is not managed by Trobar');
      expect(en.orphansTitle(2), '2 files on this card are not managed by Trobar');
    });
    test('French agrees with each count, 0 and 1 singular', () {
      expect(fr.missingTitle(1), '1 morceau introuvable sur cette carte');
      expect(fr.missingTitle(2), '2 morceaux introuvables sur cette carte');
      expect(fr.syncSummary(1, 0), 'Synchronisé : 1 téléchargé, 0 supprimé');
      expect(fr.syncSummary(5, 2), 'Synchronisé : 5 téléchargés, 2 supprimés');
      expect(fr.orphansTitle(4),
          '4 fichiers sur cette carte ne sont pas gérés par Trobar');
      expect(fr.syncStopped(1), startsWith('Synchro arrêtée : 1 téléchargé avant'));
    });
  });

  group('parseDfOutput', () {
    test('Linux and macOS `df -kP`: kilobyte columns to bytes', () {
      const out = 'Filesystem     1024-blocks      Used Available Capacity Mounted on\n'
          '/dev/sdb1         62504960  12500992  50004000      21% /media/u/CARD\n';
      expect(parseDfOutput(out), (free: 50004000 * 1024, total: 62504960 * 1024));
    });
    test('a mount point with spaces only lengthens the last column', () {
      const out = 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
          '/dev/disk4s1 1000 400 600 40% /Volumes/MY CARD\n';
      expect(parseDfOutput(out), (free: 600 * 1024, total: 1000 * 1024));
    });
    test('anything else is no figure, not a wrong one', () {
      expect(parseDfOutput(''), isNull);
      expect(parseDfOutput('Filesystem 1024-blocks Used Available\n'), isNull);
      expect(parseDfOutput('h\n/dev/x lots some more 9% /m\n'), isNull);
      // Too few columns to be `df -P`, even though the numbers would read.
      expect(parseDfOutput('h\n/dev/x 100 50 50\n'), isNull);
    });
  });
}
