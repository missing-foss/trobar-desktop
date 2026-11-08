// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// desktop#27: what a finished sync says, and the /changes field the space
// check depends on.

import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:trobar_desktop/api_client.dart';
import 'package:trobar_desktop/l10n/gen/app_localizations.dart';
import 'package:trobar_desktop/models.dart';
import 'package:trobar_desktop/sync_engine.dart';
import 'package:trobar_desktop/sync_messages.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));

  group('syncErrorText', () {
    test('a card too small names what is needed and what is free', () {
      final text = syncErrorText(
          const SyncResult(
              notEnoughSpace: (needed: 1500000000, free: 1000000000),
              firstError: 'x'),
          en);
      expect(text, en.syncNotEnoughSpace('1.5', '1.0'));
    });

    test('a stopped sync says how far it got', () {
      expect(
          syncErrorText(
              const SyncResult(cancelled: true, downloadedCount: 3), en),
          en.syncStopped(3));
    });

    test('a card that filled up says so', () {
      expect(syncErrorText(const SyncResult(diskFull: true, firstError: 'x'), en),
          en.syncCardFull);
    });

    test('otherwise the first error, or nothing', () {
      expect(syncErrorText(const SyncResult(firstError: 'A/B: boom'), en),
          'A/B: boom');
      expect(syncErrorText(const SyncResult(), en), isNull);
    });

    test('a near miss never reads as if it fit', () {
      // 1.04 GB needed, 0.96 GB free: plain rounding gives "1.0" for both.
      final text = syncErrorText(
          const SyncResult(
              notEnoughSpace: (needed: 1040000000, free: 960000000)),
          en);
      expect(text, en.syncNotEnoughSpace('1.1', '0.9'));
    });
  });

  test('the sync screen words its error through syncErrorText', () {
    // A source check, not a behaviour test: nothing short of driving a
    // whole sync through the widget sees which string the screen keeps, so
    // this pins the one call that decides it.
    final src = File('lib/main.dart').readAsStringSync();
    expect(RegExp(r'syncError = syncErrorText\(result, l\);').allMatches(src),
        hasLength(1));
    expect(src.contains('syncError = result.firstError'), isFalse);
  });

  group('errorText', () {
    test('401 and 403 read as a revoked pairing', () {
      for (final code in [401, 403]) {
        final e = ApiException('GET /x — HTTP $code', statusCode: code);
        expect(isRevoked(e), isTrue);
        expect(errorText(e, en), en.pairingRevoked);
      }
    });

    test('anything else reads as it was reported', () {
      final server = ApiException('GET /x — HTTP 500', statusCode: 500);
      final timeout = ApiException('No answer from the server in 30 s');
      for (final e in <Object>[server, timeout, StateError('boom')]) {
        expect(isRevoked(e), isFalse);
        expect(errorText(e, en), '$e');
      }
    });
  });

  group('TrackChange.fromJson', () {
    test('reads the transcode flag the server sends', () {
      final t = TrackChange.fromJson(
          {'track_id': 1, 'relative_path': 'A/B/01.mp3', 'size': 9, 'transcode': true});
      expect(t.transcode, isTrue);
    });

    test('an older server, with no flag, means not transcoded', () {
      final t = TrackChange.fromJson(
          {'track_id': 1, 'relative_path': 'A/B/01.flac', 'size': 9});
      expect(t.transcode, isFalse);
    });

    test('a /changes answer carries it through to the space check', () {
      final changes = ChangeSet.fromJson({
        'to_download': [
          {'track_id': 1, 'relative_path': 'A/B/01.mp3', 'size': 9, 'transcode': true},
          {'track_id': 2, 'relative_path': 'A/B/02.flac', 'size': 9, 'transcode': false},
        ],
        'to_delete': [],
        'downloaded': [],
      });
      expect([for (final t in changes.toDownload) t.transcode], [true, false]);
    });
  });

  group('after a sync (desktop#25)', () {
    SyncOutcome o({int down = 0, int del = 0, int written = 0, int read = 0, int unknown = 0}) =>
        SyncOutcome(syncedAt: DateTime(2026), downloaded: down, deleted: del,
            playlists: written, devicePlaylists: read, unknownEntries: unknown);

    test('the playlists line, with unknown entries only when there are some', () {
      expect(syncPlaylistsLine(o(written: 3, read: 2), en), en.syncPlaylists(3, 2));
      expect(syncPlaylistsLine(o(written: 3, read: 2, unknown: 4), en),
          '${en.syncPlaylists(3, 2)} ${en.syncUnknownEntries(4)}');
      expect(syncPlaylistsLine(o(down: 5), en), isNull);
    });

    test('the notification carries the playlists line', () {
      expect(syncCompleteBody(o(down: 1, written: 3, read: 2, unknown: 4), en),
          '${en.syncSummary(1, 0)}\n${en.syncPlaylists(3, 2)} ${en.syncUnknownEntries(4)}');
      expect(syncCompleteBody(o(down: 1), en), en.syncSummary(1, 0));
    });

    test('unknown entries are worth a notification on their own; rewritten playlists are not', () {
      expect(syncCompleteBody(o(written: 3, read: 1, unknown: 2), en), isNotNull);
      expect(syncCompleteBody(o(written: 3, read: 1), en), isNull);
      expect(syncCompleteBody(o(), en), isNull);
    });
  });
}
