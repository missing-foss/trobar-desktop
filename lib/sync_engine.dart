// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// The sync loop — same shape as the Android SyncEngine: server-computed
// diff in, per-track ack out, files written atomically (.part + rename) so
// an interrupted sync never leaves a half-written track under its real name.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'api_client.dart';
import 'card_store.dart';
import 'models.dart';

/// #85: kept aligned with trobar-android's AUDIO_FILE_EXTENSIONS
/// (FolderScan.kt) — both clients talk to the same server-side matcher, so
/// the two lists drifting apart would silently change what "an audio file"
/// means per-client. Update both together if this ever changes. The server
/// scans the same formats; ALAC lives in .m4a (there is no .alac extension).
const audioExtensions = {
  'flac', 'wav', 'aiff', 'aif', 'mp3', 'm4a', 'ogg', 'opus', 'aac',
};

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

  /// Playlists made on the device and sent to the server this sync.
  final int devicePlaylistCount;

  /// Entries of those playlists the server matched to no track in the
  /// library; they wait in the web app's unknown-tracks review.
  final int deviceUnknownEntries;
  final String? firstError;

  /// Set when downloads didn't start because the card can't hold them: at
  /// least `needed` bytes against `free`. The caller words it.
  final ({int needed, int free})? notEnoughSpace;

  /// Set when the card filled up during a download; the remaining
  /// downloads were not tried.
  final bool diskFull;

  /// Set when the caller stopped the sync: what was downloaded stays, the
  /// track in progress was dropped, and nothing after the downloads ran.
  final bool cancelled;

  const SyncResult({
    this.downloadedCount = 0,
    this.deletedCount = 0,
    this.playlistCount = 0,
    this.devicePlaylistCount = 0,
    this.deviceUnknownEntries = 0,
    this.firstError,
    this.notEnoughSpace,
    this.diskFull = false,
    this.cancelled = false,
  });
}

/// "No space left on device": ENOSPC on Linux and macOS (28), and
/// ERROR_HANDLE_DISK_FULL (39) or ERROR_DISK_FULL (112) on Windows.
bool isDiskFull(Object e) {
  final code = e is FileSystemException ? e.osError?.errorCode : null;
  if (code == null) return false;
  return Platform.isWindows ? (code == 39 || code == 112) : code == 28;
}

/// Thrown when a server-supplied path would resolve outside the sync root — a
/// '..' component, an absolute path, a Windows drive/UNC prefix, etc. A
/// hostile or compromised Trobar server (pairing is just a URL + token) could
/// otherwise return crafted `relative_path` / playlist `filename` values and
/// write arbitrary files anywhere the desktop user can — shell rc files,
/// desktop autostart entries, SSH authorized_keys — escalating an ordinary
/// sync to code execution. The Android client is immune (SAF treats '..' as a
/// literal child within the granted tree); this closes the desktop-only gap
/// and mirrors the server's own relative_to(root) confinement.
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

  /// How a playlist file on the card is read: [File.readAsBytes], unless a
  /// test needs a read that fails whoever the process runs as.
  final Future<List<int>> Function(File) readFile;

  /// The card's free space, [volumeSpace] unless a test supplies its own.
  final Future<({int free, int total})?> Function(Directory) space;

  /// How a download waits before trying again; tests don't wait.
  final Future<void> Function(Duration) wait;

  /// Tries per track, the first included, before it counts as failed.
  static const downloadAttempts = 3;

  SyncEngine(this.api, this.root,
      {this.artistImages,
      Future<List<int>> Function(File)? readFile,
      Future<({int free, int total})?> Function(Directory)? space,
      Future<void> Function(Duration)? wait})
      : readFile = readFile ?? ((f) => f.readAsBytes()),
        space = space ?? volumeSpace,
        wait = wait ?? ((d) => Future<void>.delayed(d));

  /// Worth another try: the server failing (5xx, its "busy transcoding" 503
  /// included), or the connection dropping or stalling. A refusal (4xx) or
  /// a full card is not.
  static bool _retryable(Object e) => e is ApiException
      ? e.statusCode == null || e.statusCode! >= 500
      : e is http.ClientException || e is SocketException || e is HttpException;

  /// One track into [part], tried up to [downloadAttempts] times. An
  /// original resumes from what an earlier try in this same run wrote; a
  /// transcoded track, encoded afresh for each request, starts over. The
  /// wait between tries is what the server asked for, or a few seconds,
  /// never over a minute.
  ///
  /// A [part] already there before the first try is left by a run that
  /// didn't finish (a crash, an unplugged card) and is deleted, not
  /// resumed: the file may have changed on the server since, and a bare
  /// Range would join the old file's head to the new one's tail, at the
  /// right length, with nothing to show for it.
  Future<int> _download(TrackChange t, File part, bool Function()? isCancelled) async {
    if (await part.exists()) await part.delete();
    for (var attempt = 1;; attempt++) {
      final have = attempt > 1 && !t.transcode && await part.exists()
          ? await part.length()
          : 0;
      try {
        return await api.downloadTrack(t.trackId, part,
            resumeFrom: have, cancelled: isCancelled);
      } catch (e) {
        if (e is ApiException && e.statusCode == 416) {
          // The part no longer fits the file (it changed on the server):
          // drop it and fetch the whole file.
          await part.delete();
          if (attempt < downloadAttempts) continue;
        }
        if (attempt >= downloadAttempts || !_retryable(e)) rethrow;
        final asked = e is ApiException ? e.retryAfter : null;
        final delay = asked ?? Duration(seconds: 2 * attempt);
        await wait(delay > const Duration(minutes: 1)
            ? const Duration(minutes: 1)
            : delay);
        // A stop asked for during the wait is honoured before the next try.
        if (isCancelled?.call() ?? false) throw SyncCancelled();
      }
    }
  }

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

  /// [isCancelled] is asked before each track and while one downloads
  /// (see [ApiClient.downloadTrack]): once it answers true the sync stops
  /// there, keeps what it downloaded, drops the track in progress, and
  /// skips what comes after the downloads.
  Future<SyncResult> run(ChangeSet changes,
      {void Function(SyncProgress)? onProgress,
      bool Function()? isCancelled}) async {
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

    // Before any download, and after the deletions above have freed what
    // they free: a card that can't hold even the untranscoded tracks of
    // known size is reported as such, instead of every download failing on
    // it in turn. Only those count, so this never refuses a sync that
    // would fit; a transcoded track's final size isn't known in advance.
    // No figure (an unsupported platform) means no check.
    final needed = changes.toDownload
        .where((t) => !t.transcode)
        .fold<int>(0, (sum, t) => sum + (t.size ?? 0));
    final before = needed > 0 ? await space(root) : null;
    final notEnoughSpace = before != null && needed > before.free
        ? (needed: needed, free: before.free)
        : null;
    var diskFull = false;

    final queue =
        notEnoughSpace == null ? changes.toDownload : const <TrackChange>[];
    final total = queue.length;
    var done = 0;
    var cancelled = false;
    for (final t in queue) {
      if (diskFull) break;
      if (isCancelled?.call() ?? false) {
        cancelled = true;
        break;
      }
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
          final bytes = await _download(t, part, isCancelled);
          await part.rename(dest.path);
          await api.ack(t.trackId, 'downloaded', bytesOnDevice: bytes);
          downloaded++;
        } catch (e) {
          if (await part.exists()) await part.delete();
          rethrow;
        }
      } catch (e) {
        if (e is SyncCancelled) {
          cancelled = true;
          break;
        }
        if (isDiskFull(e)) {
          // Every later download would fail the same way.
          diskFull = true;
        } else {
          firstError ??= '${t.relativePath}: $e';
        }
      }
    }

    // Asked once more after the loop, so a stop is seen even when there was
    // nothing to download and the loop never ran.
    if (!cancelled && (isCancelled?.call() ?? false)) cancelled = true;
    if (cancelled) {
      return SyncResult(
          downloadedCount: downloaded,
          deletedCount: deleted,
          firstError: firstError,
          cancelled: true);
    }

    var playlistCount = 0;
    try {
      playlistCount = await _writePlaylists(changes.playlists);
    } catch (e) {
      firstError ??= 'playlists: $e';
    }

    // After the write, so the set read here is the card as it now stands.
    var devicePlaylistCount = 0;
    var deviceUnknownEntries = 0;
    try {
      final own = await collectUserPlaylists();
      final read = await api.postDevicePlaylists(own);
      if (read != null) {
        devicePlaylistCount = own.length;
        deviceUnknownEntries = read.unknown;
      }
    } catch (e) {
      firstError ??= 'device playlists: $e';
    }

    if (artistImages == 'small' || artistImages == 'full') {
      await _downloadArtistImages(small: artistImages == 'small');
    }

    final after = await space(root);
    if (after != null) {
      try {
        await api.reportStorage(freeBytes: after.free, totalBytes: after.total);
      } catch (_) {
        // decorative — a failed storage report never fails the sync
      }
    }

    return SyncResult(
      downloadedCount: downloaded,
      deletedCount: deleted,
      playlistCount: playlistCount,
      devicePlaylistCount: devicePlaylistCount,
      deviceUnknownEntries: deviceUnknownEntries,
      firstError: firstError,
      notEnoughSpace: notEnoughSpace,
      diskFull: diskFull,
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
      // A playlist the person made, under the same name: theirs stays, and
      // the Trobar one isn't written this sync.
      if (current != null && !_isTrobarManaged(current)) continue;
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

  static bool _isTrobarManaged(String text) {
    final lines = const LineSplitter().convert(text); // a BOM only touches line 1
    return lines.length > 1 && lines[1].trim() == m3uMarker;
  }

  static const _playlistExtensions = {'.m3u', '.m3u8'};

  /// Whether [file] is one of Trobar's own playlists. One that can't be read
  /// counts as the user's: never offered for deletion on a guess.
  Future<bool> _isTrobarPlaylist(File file) async {
    try {
      return _isTrobarManaged(_decode(await readFile(file)));
    } on FileSystemException {
      return false;
    }
  }

  /// Every playlist on the card a person made: .m3u and .m3u8 files,
  /// except those whose second line is [m3uMarker] (Trobar's own, the same
  /// line the server's .m3u reader checks), and except anything under a
  /// name starting with a dot: `.trobar/`, hidden folders, and the `._`
  /// files macOS writes beside every file on a FAT or exFAT card. Entries
  /// are the non-blank, non-comment lines, as written; the server resolves
  /// them. A file that isn't valid UTF-8 is read as Latin-1, the usual
  /// encoding of an older .m3u.
  ///
  /// All or nothing: the server removes any playlist missing from an
  /// upload, so a file that can't be read throws, rather than being left
  /// out and its playlist deleted with its settings and mirrors.
  Future<List<DevicePlaylist>> collectUserPlaylists() async {
    final found = <DevicePlaylist>[];
    await for (final e in root.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      if (!_playlistExtensions.contains(p.extension(e.path).toLowerCase())) continue;
      final parts = p.split(p.relative(e.path, from: root.path));
      if (parts.any((part) => part.startsWith('.'))) continue;
      final String text;
      try {
        text = _decode(await readFile(e));
      } on FileSystemException catch (err) {
        throw FileSystemException(
            "can't read ${parts.join('/')}, so no playlists were sent this sync", err.path, err.osError);
      }
      if (_isTrobarManaged(text)) continue;
      found.add(DevicePlaylist(path: parts.join('/'), entries: [
        // trim() also drops a BOM on the first line.
        for (final line in const LineSplitter().convert(text))
          if (line.trim().isNotEmpty && !line.trim().startsWith('#')) line.trim()
      ]));
    }
    found.sort((a, b) => a.path.compareTo(b.path));
    return found;
  }

  static String _decode(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes);
    }
  }

  /// Files on the card no current track claims: old-extension leftovers
  /// after a transcode-format change, stray.part files, or
  /// anything else. `.trobar/` is never considered, and neither is a
  /// playlist the user made on the card ([collectUserPlaylists] uploads it
  /// as theirs; offering to delete it straight after would undo that).
  /// Only Trobar's own playlist files can be leftovers. Detection only — the
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
      if (expected.contains(rel)) continue;
      if (_playlistExtensions.contains(p.extension(e.path).toLowerCase()) &&
          !await _isTrobarPlaylist(e)) {
        continue;
      }
      orphans.add(rel);
    }
    orphans.sort();
    return orphans;
  }

  /// #82: every audio file already on the card, as manifest-upload
  /// candidates for a freshly (re-)paired device the server has no record
  /// of yet — most commonly a card whose `.trobar/` was lost (metadata
  /// corruption, a cleared hidden folder) while the music itself survived,
  /// forcing re-enrollment under a brand-new device id. Reuses
  /// [findOrphans]' own walk with an empty [ChangeSet]: nothing is
  /// "expected" yet, so everything it would otherwise flag as a leftover is
  /// a candidate — but findOrphans is deliberately unfiltered (right for
  /// orphan *detection*, where a hand-placed file matters too), so #85
  /// narrows the result here rather than changing that walk: only
  /// [audioExtensions] go to the server, not playlists Trobar itself wrote
  /// or unrelated files the user put on the card by hand. Both because the
  /// server doesn't need those paths, and because record_device_manifest's
  /// `unmatched` count is a diagnostic someone reads after a recovery
  /// didn't go as expected — inflated by non-audio files, it stops meaning
  /// "Trobar files the server couldn't place".
  Future<List<String>> collectManifestPaths() async {
    final all = await findOrphans(
        const ChangeSet(toDownload: [], toDelete: [], downloaded: []));
    return [
      for (final path in all)
        if (audioExtensions.contains(p.extension(path).replaceFirst('.', '').toLowerCase()))
          path
    ];
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
