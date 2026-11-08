// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// #20: the last-sync outcome is persisted on the card (.trobar/last_sync.json)
// so it survives reopening — these cover the round-trip, the absent-file case,
// and the "Clear error" transform.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:trobar_desktop/card_store.dart';
import 'package:trobar_desktop/models.dart';
import 'package:trobar_desktop/windows_volume.dart';

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

  test('the playlist counts round-trip, and an older file reads them as 0',
      () async {
    await writeSyncOutcome(
        root,
        SyncOutcome(syncedAt: DateTime.now(), playlists: 4, devicePlaylists: 2, unknownEntries: 7));
    final read = (await readSyncOutcome(root))!;
    expect([read.playlists, read.devicePlaylists, read.unknownEntries], [4, 2, 7]);

    await syncStateFileFor(root)
        .writeAsString('{"synced_at":"2026-07-20T09:00:00Z","downloaded":1,"deleted":0}');
    final old = (await readSyncOutcome(root))!;
    expect([old.playlists, old.devicePlaylists, old.unknownEntries], [0, 0, 0]);
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

  group('a folder that does not answer', () {
    test('is dropped after the timeout, and the others are still found',
        () async {
      await writeConfig(
          root, const DeviceConfig(serverUrl: 'https://x', token: 't'));
      final hung = [for (var i = 0; i < 3; i++) p.join(root.path, 'share$i')];
      final clock = Stopwatch()..start();
      final found = await discoverLocalFolders([...hung, root.path],
          timeout: const Duration(milliseconds: 300),
          probe: (dir) => hung.contains(dir.path)
              ? Completer<DeviceConfig?>().future // never answers
              : readConfig(dir));
      clock.stop();
      expect(found.map((f) => f.$1.path), [root.path]);
      // Probed together: three silent shares cost one timeout, not three.
      expect(clock.elapsed, lessThan(const Duration(milliseconds: 800)));
    });
  });

  group('linuxMountUser', () {
    const passwd = 'root:x:0:0::/nonexistent:/bin/false\n'
        'alice:x:1000:1000::/nonexistent:/bin/false\n';
    test('is USER normally', () {
      expect(linuxMountUser({'USER': 'alice'}), 'alice');
    });
    test('is the invoking user under sudo', () {
      expect(linuxMountUser({'USER': 'root', 'SUDO_USER': 'alice'}), 'alice');
    });
    test('is the invoking user under pkexec, by uid', () {
      expect(
          linuxMountUser({'USER': 'root', 'PKEXEC_UID': '1000'},
              passwd: passwd),
          'alice');
    });
    test('falls back to USER for an unknown uid or an empty SUDO_USER', () {
      expect(
          linuxMountUser({'USER': 'root', 'PKEXEC_UID': '4242'},
              passwd: passwd),
          'root');
      expect(linuxMountUser({'USER': 'root', 'SUDO_USER': ''}), 'root');
    });
  });

  group('isRemovable (#66)', () {
    test('an arbitrary folder outside any mount convention is not removable',
        () {
      // root is a systemTemp dir — never under /media, /run/media, /Volumes,
      // or (on Windows) equal to a bare drive-letter root.
      expect(isRemovable(root), isFalse);
    });

    test('on Windows only a removable drive root counts (desktop#45)', () {
      // Everything on E: is on removable media, so only the root check can
      // tell the drive from a folder on it.
      int drive(String path) => path.startsWith('E:') ? driveRemovable : 3;
      expect(windowsTargetIsRemovable(r'E:\', drive), isTrue);
      // A folder on the removable drive is not the drive.
      expect(windowsTargetIsRemovable(r'E:\Music', drive), isFalse);
      // A fixed drive's root, and any folder on it.
      expect(windowsTargetIsRemovable(r'C:\', drive), isFalse);
      expect(
          windowsTargetIsRemovable(r'C:\Users\me\AppData\Local\Temp', drive),
          isFalse);
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

  group('manifest-pending marker (#84)', () {
    test('not pending until markManifestPending is called', () async {
      expect(await manifestPending(root), isFalse);
    });

    test('markManifestPending sets it, clearManifestPending unsets it',
        () async {
      await markManifestPending(root);
      expect(await manifestPending(root), isTrue);

      await clearManifestPending(root);
      expect(await manifestPending(root), isFalse);
    });

    test('clearManifestPending on an already-clear card is a no-op, not '
        'an error', () async {
      await clearManifestPending(root);
      expect(await manifestPending(root), isFalse);
    });

    test('the marker lives under .trobar, same as the rest of the card '
        'state', () async {
      await markManifestPending(root);
      expect(
          File(p.join(root.path, '.trobar', 'manifest_pending')).existsSync(),
          isTrue);
    });
  });
}
