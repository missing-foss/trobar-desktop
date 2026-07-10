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
import 'transcoder.dart';

class SyncProgress {
  final int done;
  final int total;
  final String currentPath;
  const SyncProgress(this.done, this.total, this.currentPath);
}

class SyncResult {
  final int downloadedCount;
  final int transcodedCount;
  final int deletedCount;
  final int playlistCount;

  /// Tracks the server wants transcoded when no encoder is available on
  /// this machine — left `pending` server-side, surfaced in the UI.
  final int skippedTranscode;
  final String? firstError;

  const SyncResult({
    this.downloadedCount = 0,
    this.transcodedCount = 0,
    this.deletedCount = 0,
    this.playlistCount = 0,
    this.skippedTranscode = 0,
    this.firstError,
  });
}

class SyncEngine {
  final ApiClient api;
  final Directory root;

  /// Null = no encoder on this machine; transcode-flagged tracks are then
  /// skipped (they stay pending) instead of failing the sync.
  final Transcoder? transcoder;

  /// The device's transcode_format from /api/device/info — what the
  /// transcoder should produce for flagged tracks.
  final String? transcodeFormat;

  /// gitea#127 — device-level artist pictures: null = off, 'small'/'full'.
  final String? artistImages;

  SyncEngine(this.api, this.root,
      {this.transcoder, this.transcodeFormat, this.artistImages});

  File _fileFor(String relativePath) =>
      File(p.joinAll([root.path, ...relativePath.split('/')]));

  /// gitea#49 spot check: tracks the server believes are on the card but
  /// aren't. The caller (UI) asks the user what to do and calls
  /// [ApiClient.resolveMissing] — this only detects.
  Future<List<TrackChange>> findMissing(ChangeSet changes) async {
    final missing = <TrackChange>[];
    for (final t in changes.downloaded) {
      if (!await _fileFor(t.relativePath).exists()) missing.add(t);
    }
    return missing;
  }

  Future<SyncResult> run(ChangeSet changes,
      {void Function(SyncProgress)? onProgress}) async {
    var downloaded = 0;
    var transcoded = 0;
    var deleted = 0;
    var skippedTranscode = 0;
    String? firstError;
    // The payload's format is authoritative — it's what the flags were
    // computed with; the constructor value is only a fallback for older
    // servers that don't send it.
    final format = changes.transcodeFormat ?? transcodeFormat;

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
      if (t.transcode && (transcoder == null || format == null)) {
        // No encoder here — the track stays `pending` server-side so a
        // machine with ffmpeg (or a later install) picks it up cleanly.
        skippedTranscode++;
        firstError ??=
            'ffmpeg not found — ${t.relativePath} skipped (still pending)';
        continue;
      }
      try {
        final dest = _fileFor(t.relativePath);
        await dest.parent.create(recursive: true);
        final part = File('${dest.path}.part');
        try {
          if (t.transcode) {
            // Original lands in system temp (never on the slow FAT card),
            // ffmpeg writes the MP3 straight to the card's .part file.
            final tmp = await Directory.systemTemp.createTemp('trobar-tc-');
            try {
              final original = File(p.join(tmp.path, 'original'));
              await api.downloadTrack(t.trackId, original);
              await transcoder!.transcode(original, part, format!);
            } finally {
              await tmp.delete(recursive: true);
            }
            await part.rename(dest.path);
            final bytes = await dest.length();
            await api.ack(t.trackId, 'downloaded', bytesOnDevice: bytes);
            transcoded++;
          } else {
            final bytes = await api.downloadTrack(t.trackId, part);
            await part.rename(dest.path);
            await api.ack(t.trackId, 'downloaded', bytesOnDevice: bytes);
            downloaded++;
          }
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
      transcodedCount: transcoded,
      deletedCount: deleted,
      playlistCount: playlistCount,
      skippedTranscode: skippedTranscode,
      firstError: firstError,
    );
  }

  /// gitea#127 — one artist.jpg per artist folder on the card. Walks every
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

  /// gitea#118 — the marker the server writes into every generated playlist;
  /// only files carrying it are ever deleted here.
  static const m3uMarker = '# Generated by Trobar';

  /// Write the device's playlist files at the card root and remove
  /// Trobar-managed .m3u8 files that no longer correspond to an assigned
  /// playlist. The user's own playlist files (no marker) are never touched.
  Future<int> _writePlaylists(List<PlaylistFile> playlists) async {
    final expected = <String>{};
    for (final pl in playlists) {
      expected.add(pl.filename);
      final f = File(p.join(root.path, pl.filename));
      final current =
          await f.exists() ? await f.readAsString() : null;
      if (current != pl.content) {
        await f.writeAsString(pl.content, flush: true);
      }
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
    return playlists.length;
  }

  /// Files on the card no current track claims: old-extension leftovers
  /// after a transcode-format change (gitea#2 M4), stray .part files, or
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
      // artist.jpg is written by the artist-images feature (gitea#127) —
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
      final f = _fileFor(rel);
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
