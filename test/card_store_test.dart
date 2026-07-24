// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// #20: the last-sync outcome is persisted on the card (.trobar/last_sync.json)
// so it survives reopening — these cover the round-trip, the absent-file case,
// and the "Clear error" transform.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
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

  group('discoverLocalFolders (#66)', () {
    test('finds a valid config at a persisted path', () async {
      await writeConfig(
          root, const DeviceConfig(serverUrl: 'https://x', token: 't'));
      final found = await discoverLocalFolders([root.path]);
      expect(found, hasLength(1));
      expect(found.single.$1.path, root.path);
      expect(found.single.$2.serverUrl, 'https://x');
    });

    test('a path that no longer exists is silently dropped', () async {
      final gone = p.join(root.path, 'never-existed');
      expect(await discoverLocalFolders([gone]), isEmpty);
    });

    test('a path that exists but has no pairing file is dropped', () async {
      expect(await discoverLocalFolders([root.path]), isEmpty);
    });

    test('a path with a corrupt config is dropped, not thrown', () async {
      await configFileFor(root).parent.create(recursive: true);
      await configFileFor(root).writeAsString('{ not json');
      expect(await discoverLocalFolders([root.path]), isEmpty);
    });

    test('one bad path among several does not affect the good ones',
        () async {
      await writeConfig(
          root, const DeviceConfig(serverUrl: 'https://x', token: 't'));
      final gone = p.join(root.path, 'never-existed');
      final found = await discoverLocalFolders([gone, root.path]);
      expect(found, hasLength(1));
      expect(found.single.$1.path, root.path);
    });
  });

  group('isRemovable (#66)', () {
    test('an arbitrary folder outside any mount convention is not removable',
        () {
      // root is a systemTemp dir — never under /media, /run/media, /Volumes,
      // or (on Windows) equal to a bare drive-letter root.
      expect(isRemovable(root), isFalse);
    });

    test('a path under the Linux removable-mount convention is removable',
        () {
      final user = Platform.environment['USER'] ?? '';
      expect(isRemovable(Directory('/media/$user/SomeCard')), isTrue);
    }, skip: Platform.isLinux ? null : 'Linux-specific mount convention');
  });

  group('parentDiskDevice (#66)', () {
    // Regression test: an earlier version's regex had the 'p' separator
    // *inside* the captured group, so it was greedily consumed even for
    // mmcblk/nvme devices — /dev/nvme1n1p2 came back as "/dev/nvme1n1p"
    // rather than "/dev/nvme1n1", which lsblk would then fail to find.
    test('strips a partition suffix for sd/mmcblk/nvme devices', () {
      expect(parentDiskDevice('/dev/sda1'), '/dev/sda');
      expect(parentDiskDevice('/dev/sda'), '/dev/sda');
      expect(parentDiskDevice('/dev/sdb2'), '/dev/sdb');
      expect(parentDiskDevice('/dev/mmcblk0p1'), '/dev/mmcblk0');
      expect(parentDiskDevice('/dev/mmcblk0'), '/dev/mmcblk0');
      expect(parentDiskDevice('/dev/nvme1n1p2'), '/dev/nvme1n1');
      expect(parentDiskDevice('/dev/nvme0n1'), '/dev/nvme0n1');
    });

    test('an unrecognised device path is passed through as-is', () {
      expect(parentDiskDevice('/dev/mapper/luks-abc123'),
          '/dev/mapper/luks-abc123');
    });
  });
}
