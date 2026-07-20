// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// The sync loop — same shape as the Android SyncEngine: server-computed
// diff in, per-track ack out, files written atomically (.part + rename) so
// an interrupted sync never leaves a half-written track under its real name.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'api_client.dart';
import 'card_store.dart';
import 'models.dart';

class SyncProgress {
  final int done;
  final int total;
  final String currentPath;
  const SyncProgress(this.done, this.total, this.currentPath);
}

class SyncResult {
  final int downloadedCount;
  final int deletedCount;
  final int playlistCount;
  final String? firstError;

  const SyncResult({
    this.downloadedCount = 0,
    this.deletedCount = 0,
    this.playlistCount = 0,
    this.firstError,
  });
}

/// Thrown when a server-supplied path would resolve outside the sync root — a
/// '..' component, an absolute path, a Windows drive/UNC prefix, etc. A
/// hostile or compromised Trobar server (pairing is just a URL + token) could
/// otherwise return crafted `relative_path` / playlist `filename` values and
/// write arbitrary files anywhere the desktop user can — shell rc files,
/// desktop autostart entries, SSH authorized_keys — escalating an ordinary
/// sync to code execution. The Android client is immune (SAF treats '..' as a
/// literal child within the granted tree); this closes the desktop-only gap
/// and mirrors the server's own relative_to(root) confinement. See #11.
class UnsafePathException implements Exception {
  final String path;
  UnsafePathException(this.path);
  @override
  String toString() => 'unsafe server path rejected: $path';
}

class SyncEngine {
  final ApiClient api;
  final Directory root;

  /// device-level artist pictures: null = off, 'small'/'full'.
  final String? artistImages;

  SyncEngine(this.api, this.root, {this.artistImages});

  /// Join a server-supplied relative path under [root], REJECTING anything
  /// that would escape it (#11). Throws [UnsafePathException] on an absolute
  /// path, a drive/UNC prefix, or any empty / '.' / '..' component; then
  /// confirms containment against the canonicalised root — the belt-and-braces
  /// catch for whatever the component checks miss (e.g. backslash separators
  /// on Windows). The two write paths (tracks, playlists) share this guard.
  File _fileFor(String relativePath) {
    if (p.isAbsolute(relativePath) || p.rootPrefix(relativePath).isNotEmpty) {
      throw UnsafePathException(relativePath);
    }
    final segments = relativePath.split('/');
    for (final seg in segments) {
      if (seg.isEmpty ||
          seg == '.' ||
          seg == '..' ||
          p.isAbsolute(seg) ||
          p.rootPrefix(seg).isNotEmpty) {
        throw UnsafePathException(relativePath);
      }
    }
    final dest = File(p.joinAll([root.path, ...segments]));
    final rootCanon = p.canonicalize(root.path);
    final destCanon = p.canonicalize(dest.path);
    if (destCanon != rootCanon && !p.isWithin(rootCanon, destCanon)) {
      throw UnsafePathException(relativePath);
    }
    return dest;
  }

  // spot check: tracks the server believes are on the card but
  /// aren't. The caller (UI) asks the user what to do and calls
  /// [ApiClient.resolveMissing] — this only detects.
  Future<List<TrackChange>> findMissing(ChangeSet changes) async {
    final missing = <TrackChange>[];
    for (final t in changes.downloaded) {
      try {
        if (!await _fileFor(t.relativePath).exists()) missing.add(t);
      } on UnsafePathException {
        // A crafted server path — never report it as "missing" (that would
        // prompt a re-download of it); ignore it entirely.
      }
    }
    return missing;
  }

  Future<SyncResult> run(ChangeSet changes,
      {void Function(SyncProgress)? onProgress}) async {
    var downloaded = 0;
    var deleted = 0;
    String? firstError;

    for (final t in changes.toDelete) {
      try {
        final f = _fileFor(t.relativePath);
        if (await f.exists()) await f.delete();
        await _pruneEmptyParents(f);
        await api.ack(t.trackId, 'removed');
        deleted++;
      } catch (e) {
        firstError ??= '${t.relativePath}: $e';
      }
    }

    final total = changes.toDownload.length;
    var done = 0;
    for (final t in changes.toDownload) {
      done++;
      onProgress?.call(SyncProgress(done, total, t.relativePath));
      try {
        // The server serves the already-converted bytes for a transcoding
        // device (the track's relativePath already carries the .mp3
        // extension), so the client just downloads whatever it's given —
        // atomic .part + rename, same as any other track.
        final dest = _fileFor(t.relativePath);
        await dest.parent.create(recursive: true);
        final part = File('${dest.path}.part');
        try {
          final bytes = await api.downloadTrack(t.trackId, part);
          await part.rename(dest.path);
          await api.ack(t.trackId, 'downloaded', bytesOnDevice: bytes);
          downloaded++;
        } catch (e) {
          if (await part.exists()) await part.delete();
          rethrow;
        }
      } catch (e) {
        firstError ??= '${t.relativePath}: $e';
      }
    }

    var playlistCount = 0;
    try {
      playlistCount = await _writePlaylists(changes.playlists);
    } catch (e) {
      firstError ??= 'playlists: \$e';
    }

    if (artistImages == 'small' || artistImages == 'full') {
      await _downloadArtistImages(small: artistImages == 'small');
    }

    final space = await volumeSpace(root);
    if (space != null) {
      try {
        await api.reportStorage(freeBytes: space.free, totalBytes: space.total);
      } catch (_) {
        // decorative — a failed storage report never fails the sync
      }
    }

    return SyncResult(
      downloadedCount: downloaded,
      deletedCount: deleted,
      playlistCount: playlistCount,
      firstError: firstError,
    );
  }

  /// one artist.jpg per artist folder on the card. Walks every
  /// top-level directory (so pictures backfill for artists synced before the
  /// setting was turned on), never overwrites an existing file (a hand-
  /// placed picture always wins), and stays silent on failure — decorative,
  /// never worth failing a sync over.
  Future<void> _downloadArtistImages({required bool small}) async {
    await for (final e in root.list(followLinks: false)) {
      if (e is! Directory) continue;
      final artist = p.basename(e.path);
      if (artist.startsWith('.')) continue;
      final dest = File(p.join(e.path, 'artist.jpg'));
      if (await dest.exists()) continue;
      try {
        final bytes = await api.getArtistImage(artist, small: small);
        if (bytes != null) await dest.writeAsBytes(bytes, flush: true);
      } catch (_) {
        // decorative — ignore
      }
    }
  }

  /// the marker the server writes into every generated playlist;
  /// only files carrying it are ever deleted here.
  static const m3uMarker = '# Generated by Trobar';

  /// Write the device's playlist files at the card root and remove
  /// Trobar-managed .m3u8 files that no longer correspond to an assigned
  /// playlist. The user's own playlist files (no marker) are never touched.
  Future<int> _writePlaylists(List<PlaylistFile> playlists) async {
    final expected = <String>{};
    var written = 0;
    for (final pl in playlists) {
      File f;
      try {
        f = _fileFor(pl.filename); // #11: same path-traversal guard as tracks
      } on UnsafePathException {
        continue; // skip a crafted playlist filename, keep writing the rest
      }
      expected.add(pl.filename);
      final current =
          await f.exists() ? await f.readAsString() : null;
      if (current != pl.content) {
        await f.writeAsString(pl.content, flush: true);
      }
      written++;
    }
    await for (final e in root.list(followLinks: false)) {
      if (e is! File || !e.path.toLowerCase().endsWith('.m3u8')) continue;
      final name = p.basename(e.path);
      if (expected.contains(name)) continue;
      try {
        final head = await e
            .openRead(0, 256)
            .transform(const Utf8Decoder(allowMalformed: true))
            .join();
        if (head.contains(m3uMarker)) await e.delete();
      } on FileSystemException {
        // unreadable — leave it alone
      }
    }
    return written;
  }

  /// Files on the card no current track claims: old-extension leftovers
  /// after a transcode-format change, stray.part files, or
  /// anything else. `.trobar/` is never considered. Detection only — the
  /// UI confirms with the user before [deleteOrphans]; a DAP card may
  /// legitimately hold music the user put there by hand.
  Future<List<String>> findOrphans(ChangeSet changes) async {
    final expected = <String>{
      for (final t in changes.downloaded) t.relativePath,
      for (final t in changes.toDownload) t.relativePath,
      for (final pl in changes.playlists) pl.filename,
    };
    final orphans = <String>[];
    await for (final e in root.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final parts = p.split(p.relative(e.path, from: root.path));
      if (parts.first == configDirName) continue;
      // artist.jpg is written by the artist-images feature —
      // and a hand-placed one is deliberate either way.
      if (parts.last == 'artist.jpg') continue;
      final rel = parts.join('/');
      if (!expected.contains(rel)) orphans.add(rel);
    }
    orphans.sort();
    return orphans;
  }

  Future<void> deleteOrphans(List<String> relativePaths) async {
    for (final rel in relativePaths) {
      File f;
      try {
        f = _fileFor(rel);
      } on UnsafePathException {
        continue; // never delete through an escaping path
      }
      if (await f.exists()) await f.delete();
      await _pruneEmptyParents(f);
    }
  }

  /// After deleting a track, drop now-empty Album/Artist folders so removed
  /// selections don't leave a skeleton tree the DAP still browses into.
  Future<void> _pruneEmptyParents(File f) async {
    var dir = f.parent;
    while (dir.path != root.path &&
        p.isWithin(root.path, dir.path) &&
        await dir.exists() &&
        await dir.list().isEmpty) {
      await dir.delete();
      dir = dir.parent;
    }
  }
}
