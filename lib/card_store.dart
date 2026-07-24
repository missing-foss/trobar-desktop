// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// Card discovery + pairing config. The pairing token lives ON the card
// (.trobar/device.json at its root, decided on): plug the card into
// any machine running this app and it syncs as the right device. The app
// itself keeps no per-device state.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'models.dart';

const configDirName = '.trobar';
const configFileName = 'device.json';
const syncStateFileName = 'last_sync.json';

File configFileFor(Directory root) =>
    File(p.join(root.path, configDirName, configFileName));

File syncStateFileFor(Directory root) =>
    File(p.join(root.path, configDirName, syncStateFileName));

/// The last sync's outcome, persisted alongside the pairing config so it
/// travels with the card and shows on reopen (#20). Missing/corrupt → null.
Future<SyncOutcome?> readSyncOutcome(Directory root) async {
  final f = syncStateFileFor(root);
  try {
    if (!await f.exists()) return null;
    return SyncOutcome.fromJson(
        jsonDecode(await f.readAsString()) as Map<String, dynamic>);
  } catch (_) {
    // #40: never throws. Beyond a missing/corrupt file (FormatException /
    // FileSystemException), valid-JSON-but-wrong-shape (a non-object, or a
    // field of the wrong type) throws a TypeError from the casts in fromJson —
    // all of it means "no usable outcome", so fall back to null.
    return null;
  }
}

Future<void> writeSyncOutcome(Directory root, SyncOutcome outcome) async {
  final f = syncStateFileFor(root);
  await f.parent.create(recursive: true);
  await f.writeAsString('${jsonEncode(outcome.toJson())}\n', flush: true);
}

Future<DeviceConfig?> readConfig(Directory root) async {
  final f = configFileFor(root);
  if (!await f.exists()) return null;
  try {
    return DeviceConfig.fromJson(
        jsonDecode(await f.readAsString()) as Map<String, dynamic>);
  } on FormatException {
    return null;
  }
}

Future<void> writeConfig(Directory root, DeviceConfig config) async {
  final f = configFileFor(root);
  await f.parent.create(recursive: true);
  await f.writeAsString('${jsonEncode(config.toJson())}\n', flush: true);
  // #12: the token is plaintext by design (it must travel with the card), but
  // tighten perms to 0600 where the filesystem supports them — cheap
  // defense-in-depth so it isn't world-readable on a shared machine. A no-op on
  // FAT/exFAT cards and on Windows; the portability model is unchanged. See
  // SECURITY.md.
  if (!Platform.isWindows) {
    try {
      await Process.run('chmod', ['600', f.path]);
    } catch (_) {
      // FAT/exFAT or a restricted environment — best-effort only.
    }
  }
}

/// Mount points where removable volumes show up, per platform. Purely a
/// convenience for auto-detection — any folder can be picked manually.
List<Directory> _candidateRoots() {
  if (Platform.isLinux) {
    final user = Platform.environment['USER'] ?? '';
    return [Directory('/media/$user'), Directory('/run/media/$user')];
  }
  if (Platform.isMacOS) return [Directory('/Volumes')];
  if (Platform.isWindows) {
    return [
      for (var c = 'A'.codeUnitAt(0); c <= 'Z'.codeUnitAt(0); c++)
        Directory('${String.fromCharCode(c)}:\\')
    ];
  }
  return [];
}

/// Every mounted volume carrying a Trobar pairing file.
Future<List<(Directory, DeviceConfig)>> discoverCards() async {
  final found = <(Directory, DeviceConfig)>[];
  for (final parent in _candidateRoots()) {
    // Windows: the drive letters themselves are the volumes; elsewhere the
    // volumes are the children of the mount root.
    final volumes = <Directory>[];
    if (Platform.isWindows) {
      volumes.add(parent);
    } else {
      if (!await parent.exists()) continue;
      await for (final e in parent.list(followLinks: false)) {
        if (e is Directory) volumes.add(e);
      }
    }
    for (final vol in volumes) {
      try {
        final config = await readConfig(vol);
        if (config != null) found.add((vol, config));
      } on FileSystemException {
        // unreadable volume (empty drive letter, permissions) — skip
      }
    }
  }
  return found;
}

/// #66: a manually-picked local folder is never under one of
/// [_candidateRoots], so discoverCards() never finds it again on the next
/// launch — the caller is expected to persist [paths] itself (AppPrefs) and
/// pass them back in here every rescan. An entry whose path no longer exists,
/// or whose pairing file is gone/corrupt, is silently dropped rather than
/// erroring — same "just fall off the list" handling AppPrefs' own
/// out-of-range values get, and it mirrors discoverCards()' own per-volume
/// try/catch.
Future<List<(Directory, DeviceConfig)>> discoverLocalFolders(
    List<String> paths) async {
  final found = <(Directory, DeviceConfig)>[];
  for (final path in paths) {
    final dir = Directory(path);
    try {
      if (!await dir.exists()) continue;
      final config = await readConfig(dir);
      if (config != null) found.add((dir, config));
    } on FileSystemException {
      // unreadable (permissions, unmounted network share) — drop silently
    }
  }
  return found;
}

/// True if [dir] sits under one of this platform's removable-volume mount
/// conventions (the same roots discoverCards() scans) — i.e. it's something
/// you'd expect to be able to unplug, as opposed to a folder picked by hand
/// anywhere else on the machine (#66). A path-prefix heuristic, same
/// precision discoverCards() itself already relies on — not a guarantee (a
/// fixed Windows drive letter matches too, same as discoverCards() already
/// doesn't distinguish fixed from removable there).
bool isRemovable(Directory dir) {
  final target = p.normalize(dir.absolute.path);
  for (final root in _candidateRoots()) {
    final rootPath = p.normalize(root.absolute.path);
    if (p.equals(target, rootPath) || p.isWithin(rootPath, target)) {
      return true;
    }
  }
  return false;
}

/// The icon-relevant kind of a sync target (#66). `local` is free and always
/// correct (Platform.isX at the call site); the removable split needs an
/// actual per-platform probe (see [probeRemovableKind]), which can fail or be
/// inconclusive — `removableUnknown` is that fallback, a normal outcome and
/// not a bug, never a guess presented as a fact.
enum TargetKind { local, removableSd, removableUsb, removableUnknown }

/// Best-effort SD-vs-USB probe for a removable [dir], via each platform's own
/// tooling. Never throws and never blocks discovery: any failure (missing
/// binary, permission error, an exotic mount, an unrecognised platform)
/// degrades to [TargetKind.removableUnknown] rather than propagating — the
/// owner can always correct the type later, so getting this wrong
/// occasionally is fine; crashing or hanging discovery over it is not.
/// Callers should only invoke this once [isRemovable] is already true.
Future<TargetKind> probeRemovableKind(Directory dir) async {
  try {
    if (Platform.isLinux) return await _probeLinux(dir);
    if (Platform.isMacOS) return await _probeMacOS(dir);
    if (Platform.isWindows) return await _probeWindows(dir);
  } catch (_) {
    // fall through to unknown
  }
  return TargetKind.removableUnknown;
}

/// `findmnt` maps the mountpoint to its backing device, then `lsblk`'s
/// `TRAN` column says how that device is attached: `mmc` is unambiguously an
/// SD/MMC card (built-in reader); `usb` covers both a USB stick and a card in
/// a USB reader, so `udevadm`'s `ID_DRIVE_FLASH_SD` narrows that case further
/// where the reader advertises it (many don't, hence the still-generic `usb`
/// fallback for those).
Future<TargetKind> _probeLinux(Directory dir) async {
  final mount = await Process.run('findmnt', ['-no', 'SOURCE', dir.path]);
  if (mount.exitCode != 0) return TargetKind.removableUnknown;
  final device = (mount.stdout as String).trim();
  if (device.isEmpty) return TargetKind.removableUnknown;

  final lsblk = await Process.run(
      'lsblk', ['-no', 'TRAN', '-d', parentDiskDevice(device)]);
  if (lsblk.exitCode != 0) return TargetKind.removableUnknown;
  final tran = (lsblk.stdout as String).trim();
  if (tran == 'mmc') return TargetKind.removableSd;
  if (tran != 'usb') return TargetKind.removableUnknown;

  final udev = await Process.run(
      'udevadm', ['info', '--query=property', '--name=$device']);
  if (udev.exitCode == 0 &&
      (udev.stdout as String).contains('ID_DRIVE_FLASH_SD=1')) {
    return TargetKind.removableSd;
  }
  return TargetKind.removableUsb;
}

/// lsblk -d wants the whole-disk device (e.g. /dev/sda), not a partition
/// (/dev/sda1) — strips a trailing partition-number suffix. Good enough for
/// the common /dev/sdX[N] and /dev/{mmcblk,nvme}X[pN] shapes; an
/// unrecognised pattern is passed through as-is and simply won't match a
/// real device, which lsblk then reports as an error -> removableUnknown
/// upstream. Two separate patterns, not one: sdX's partition suffix has no
/// 'p' separator (sda1) while mmcblk/nvme's does (mmcblk0p1, nvme0n1p1) — a
/// single regex with an optional 'p' *inside* the captured group greedily
/// swallows that 'p' even for the whole-disk case, corrupting the result
/// (caught by a direct test of this function: nvme1n1p2 came back as
/// nvme1n1p, not nvme1n1). Not underscore-prefixed despite being an
/// internal-only helper — the regex logic is exactly the kind of thing that
/// silently regresses without a direct test, and Dart's privacy is
/// per-library, so testing it means exposing it.
String parentDiskDevice(String device) {
  final sd = RegExp(r'^(/dev/sd[a-z]+)\d*$').firstMatch(device);
  if (sd != null) return sd.group(1)!;
  final mmcOrNvme =
      RegExp(r'^(/dev/(?:mmcblk\d+|nvme\d+n\d+))p?\d*$').firstMatch(device);
  return mmcOrNvme?.group(1) ?? device;
}

/// `diskutil info -plist` on the volume gives BusProtocol directly — no
/// device-node indirection needed, unlike Linux.
Future<TargetKind> _probeMacOS(Directory dir) async {
  final result =
      await Process.run('diskutil', ['info', '-plist', dir.path]);
  if (result.exitCode != 0) return TargetKind.removableUnknown;
  final out = result.stdout as String;
  // Extract BusProtocol's own <string> value specifically, not a substring
  // search over the whole plist — a whole-output search could in theory
  // false-match a volume/media *name* containing "USB" or "Secure Digital"
  // rather than the actual bus, even though BusProtocol's real vocabulary
  // ("USB", "Secure Digital", "PCI-Express", "SATA", ...) makes that
  // collision unlikely in practice.
  final match =
      RegExp(r'<key>BusProtocol</key>\s*<string>([^<]*)</string>')
          .firstMatch(out);
  switch (match?.group(1)) {
    case 'Secure Digital':
      return TargetKind.removableSd;
    case 'USB':
      return TargetKind.removableUsb;
    default:
      return TargetKind.removableUnknown;
  }
}

/// `GetDriveType()` is deliberately not used here — confirmed unreliable
/// (many USB drives report DRIVE_FIXED). `Get-PhysicalDisk`'s BusType is the
/// correct signal; matching the drive letter to its physical disk needs
/// `Get-Partition` as the join in between.
Future<TargetKind> _probeWindows(Directory dir) async {
  final driveLetter = p.rootPrefix(dir.absolute.path).replaceAll(r'\', '');
  if (driveLetter.isEmpty) return TargetKind.removableUnknown;
  final script = '(Get-Partition -DriveLetter "${driveLetter.replaceAll(':', '')}" '
      '| Get-Disk | Get-PhysicalDisk).BusType';
  final result =
      await Process.run('powershell', ['-NoProfile', '-Command', script]);
  if (result.exitCode != 0) return TargetKind.removableUnknown;
  final busType = (result.stdout as String).trim();
  if (busType == 'SD') return TargetKind.removableSd;
  if (busType == 'USB') return TargetKind.removableUsb;
  return TargetKind.removableUnknown;
}

/// Free/total bytes of the filesystem holding [root] — reported to the
/// server so the web UI can sanity-check the device's storage limit.
/// Uses `df` on Linux/macOS; unsupported elsewhere (returns null).
Future<({int free, int total})?> volumeSpace(Directory root) async {
  if (!Platform.isLinux && !Platform.isMacOS) return null;
  try {
    final result = await Process.run('df', ['-kP', root.path]);
    if (result.exitCode != 0) return null;
    final lines = (result.stdout as String).trim().split('\n');
    if (lines.length < 2) return null;
    final cols = lines.last.split(RegExp(r'\s+'));
    // df -P: Filesystem 1024-blocks Used Available Capacity Mounted-on
    final total = int.parse(cols[1]) * 1024;
    final free = int.parse(cols[3]) * 1024;
    return (free: free, total: total);
  } catch (_) {
    return null;
  }
}
