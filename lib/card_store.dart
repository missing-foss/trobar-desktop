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
  } on FormatException {
    return null;
  } on FileSystemException {
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
