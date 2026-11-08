// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// What the OS says about removable volumes, so Home looks at a drive only
// when one arrives instead of probing every candidate every few seconds.
// Windows: the runner forwards WM_DEVICECHANGE volume broadcasts (media
// inserted into a reader that's already there included) over the
// "trobar/volumes" channel. macOS and Linux: a watch on the mount roots,
// where a new volume appears as a new directory.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'card_store.dart' show mountRoots;

class VolumeEvent {
  /// The drive roots that arrived or went (Windows). Null: something changed
  /// under a mount root and the whole of it should be scanned again.
  final List<Directory>? roots;

  /// Arrived (or changed), as opposed to removed.
  final bool arrived;

  const VolumeEvent({required this.arrived, required this.roots});

  const VolumeEvent.rescan()
      : arrived = true,
        roots = null;
}

const _channel = EventChannel('trobar/volumes');

/// Drive roots for the letters in [letters] ("EF" -> E:\, F:\).
List<Directory> driveRoots(String letters) =>
    [for (final c in letters.split('')) Directory('$c:\\')];

/// This platform's volume events, or null where none can be set up; the
/// caller then polls as before. A stream that errors or ends means the same.
Stream<VolumeEvent>? platformVolumeEvents() {
  if (Platform.isWindows) {
    return _channel.receiveBroadcastStream().map((event) {
      final m = event as Map;
      return VolumeEvent(
          arrived: m['arrived'] == true,
          roots: driveRoots(m['letters'] as String? ?? ''));
    });
  }
  if (Platform.isMacOS || Platform.isLinux) {
    final roots = [for (final d in mountRoots()) if (d.existsSync()) d];
    if (roots.isEmpty) return null;
    return watchRoots(roots);
  }
  return null;
}

/// One rescan event for any change directly under [roots]; an error from any
/// of the watches is passed on, so the caller falls back to polling.
Stream<VolumeEvent> watchRoots(List<Directory> roots) {
  final subs = <StreamSubscription<FileSystemEvent>>[];
  late final StreamController<VolumeEvent> out;
  out = StreamController<VolumeEvent>(
    onListen: () {
      for (final root in roots) {
        subs.add(root.watch().listen(
              (_) => out.add(const VolumeEvent.rescan()),
              onError: out.addError,
              onDone: () => out.addError(StateError('watch on ${root.path} ended')),
            ));
      }
    },
    onCancel: () async {
      for (final s in subs) {
        await s.cancel();
      }
    },
  );
  return out.stream;
}
