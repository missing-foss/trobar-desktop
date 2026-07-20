// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// #20: the last-sync outcome is persisted on the card (.trobar/last_sync.json)
// so it survives reopening — these cover the round-trip, the absent-file case,
// and the "Clear error" transform.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trobar_desktop/card_store.dart';
import 'package:trobar_desktop/models.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('trobar_card_test'));
  tearDown(() => root.deleteSync(recursive: true));

  test('no last_sync.json yet -> null', () async {
    expect(await readSyncOutcome(root), isNull);
  });

  test('write then read round-trips the instant, counts, and error', () async {
    final at = DateTime.parse('2026-07-20T13:45:30');
    await writeSyncOutcome(
        root,
        SyncOutcome(
            syncedAt: at, downloaded: 12, deleted: 3, error: 'disk full'));

    final read = await readSyncOutcome(root);
    expect(read, isNotNull);
    // #39: stored as UTC, so compare the instant (not the tz flag).
    expect(read!.syncedAt.isAtSameMomentAs(at), isTrue);
    expect(read.downloaded, 12);
    expect(read.deleted, 3);
    expect(read.error, 'disk full');
  });

  test('the timestamp is persisted as UTC, not local wall-clock (#39)',
      () async {
    await writeSyncOutcome(
        root, SyncOutcome(syncedAt: DateTime.now(), downloaded: 1, deleted: 0));
    final raw = jsonDecode(await syncStateFileFor(root).readAsString())
        as Map<String, dynamic>;
    // ISO-8601 UTC ends with 'Z' — a local, offset-less string would drift
    // when the card is read in another timezone.
    expect((raw['synced_at'] as String).endsWith('Z'), isTrue);
  });

  test('valid JSON of the wrong shape -> null, never throws (#40)', () async {
    await syncStateFileFor(root).parent.create(recursive: true);
    for (final bad in ['[]', '"a string"', '42', '{"downloaded":1}',
      '{"synced_at":123}', '{"synced_at":"2026-01-01","downloaded":"x"}']) {
      await syncStateFileFor(root).writeAsString(bad);
      expect(await readSyncOutcome(root), isNull, reason: 'for: $bad');
    }
  });

  test('a clean sync persists no error', () async {
    await writeSyncOutcome(root,
        SyncOutcome(syncedAt: DateTime.now(), downloaded: 5, deleted: 0));
    expect((await readSyncOutcome(root))!.error, isNull);
  });

  test('withoutError() keeps time+counts but drops the error', () async {
    final at = DateTime.parse('2026-07-20T09:00:00');
    final cleared = SyncOutcome(
            syncedAt: at, downloaded: 7, deleted: 1, error: 'boom')
        .withoutError();
    expect(cleared.error, isNull);
    expect(cleared.syncedAt, at);
    expect(cleared.downloaded, 7);
    expect(cleared.deleted, 1);
  });

  test('corrupt file -> null (never throws)', () async {
    await syncStateFileFor(root).parent.create(recursive: true);
    await syncStateFileFor(root).writeAsString('{ not json');
    expect(await readSyncOutcome(root), isNull);
  });

  test('writeConfig tightens device.json perms to 0600 (#12)', () async {
    await writeConfig(
        root, const DeviceConfig(serverUrl: 'https://x', token: 't'));
    final mode = configFileFor(root).statSync().mode & 0x1FF; // perm bits
    expect(mode, 0x180); // 0600 — owner rw only
  }, skip: Platform.isWindows ? 'no unix permissions on windows' : null);
}
