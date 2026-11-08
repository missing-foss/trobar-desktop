// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// Thin client for the Trobar device API (Bearer-token half of the server,
// same endpoints the Android app uses).

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'models.dart';

/// #239/#80: matches the server's own _PROVENANCE_PUSH_MAX (main.py) —
/// sending more than this in one POST is a 400, not a truncation, so the
/// push loop in provenance.dart pages at exactly this cap.
const provenancePushMax = 500;

class ApiException implements Exception {
  final String message;

  /// The HTTP status the server answered with, when it answered at all.
  final int? statusCode;

  /// How long the server asked to be left alone (`Retry-After` in seconds,
  /// as on its "busy transcoding" 503), when it said.
  final Duration? retryAfter;
  ApiException(this.message, {this.statusCode, this.retryAfter});

  /// The server no longer accepts this card's token: the device was removed
  /// or re-paired elsewhere. Only pairing again fixes it.
  bool get isRevoked => statusCode == 401 || statusCode == 403;

  @override
  String toString() => message;
}

/// Thrown inside a download when its caller asked to stop.
class SyncCancelled implements Exception {
  @override
  String toString() => 'sync cancelled';
}

class ApiClient {
  final DeviceConfig config;
  final http.Client _http;

  /// How long any request waits for the server's answer (its status line
  /// and headers, or the whole body for a JSON call), and how long a
  /// download may go without a single byte arriving. Without them a
  /// stalled connection kept the Sync button disabled and its spinner
  /// running forever; with them it fails like any other request.
  final Duration requestTimeout;
  final Duration idleTimeout;

  ApiClient(this.config,
      {http.Client? httpClient,
      this.requestTimeout = const Duration(seconds: 30),
      this.idleTimeout = const Duration(seconds: 60)})
      : _http = httpClient ?? http.Client();

  Future<T> _timed<T>(Future<T> request) => request.timeout(requestTimeout,
      onTimeout: () => throw ApiException(
          'No answer from the server in ${requestTimeout.inSeconds} s'));

  Uri _uri(String path) {
    final base = config.serverUrl.endsWith('/')
        ? config.serverUrl.substring(0, config.serverUrl.length - 1)
        : config.serverUrl;
    return Uri.parse('$base$path');
  }

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${config.token}',
        'Content-Type': 'application/json',
      };

  Future<Map<String, dynamic>> _getJson(String path) async {
    final resp = await _timed(_http.get(_uri(path), headers: _headers));
    if (resp.statusCode != 200) {
      throw ApiException('GET $path — HTTP ${resp.statusCode}',
          statusCode: resp.statusCode);
    }
    return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
  }

  Future<void> _postJson(String path, Map<String, dynamic> body) async {
    final resp =
        await _timed(_http.post(_uri(path), headers: _headers, body: jsonEncode(body)));
    if (resp.statusCode != 200) {
      throw ApiException('POST $path — HTTP ${resp.statusCode}',
          statusCode: resp.statusCode);
    }
  }

  Future<void> _patchJson(String path, Map<String, dynamic> body) async {
    final resp = await _timed(_http.patch(_uri(path),
        headers: _headers, body: jsonEncode(body)));
    if (resp.statusCode != 200) {
      throw ApiException('PATCH $path — HTTP ${resp.statusCode}',
          statusCode: resp.statusCode);
    }
  }

  Future<DeviceInfo> getInfo() async =>
      DeviceInfo.fromJson(await _getJson('/api/device/info'));

  Future<ChangeSet> getChanges() async =>
      ChangeSet.fromJson(await _getJson('/api/device/changes'));

  /// #239/#77: one page of this device's server-computed fingerprints,
  /// cursor-paginated on ascending track_id — walk with `after =
  /// page.nextAfter` until it's null (see provenance.dart). `limit` is
  /// clamped server-side regardless of what's asked for here.
  Future<FingerprintPage> getFingerprintsPage(int after,
      {int limit = 200}) async {
    final uri = _uri('/api/device/fingerprints').replace(queryParameters: {
      'after': '$after',
      'limit': '$limit',
    });
    final resp = await _timed(_http.get(uri, headers: _headers));
    if (resp.statusCode != 200) {
      throw ApiException('fingerprints — HTTP ${resp.statusCode}',
          statusCode: resp.statusCode);
    }
    return FingerprintPage.fromJson(
        jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>);
  }

  /// #239 PR2/#80: push this device's locally-held provenance back to the
  /// server for recovery matching. At most [provenancePushMax] entries
  /// per call — more is a 400, not a truncation (server-enforced,
  /// all-or-nothing per page); paging is the caller's job (see
  /// provenance.dart), this just sends what it's given.
  Future<ProvenancePushResult> pushProvenance(
      List<ProvenanceRecord> entries) async {
    final resp = await _timed(_http.post(_uri('/api/device/provenance'),
        headers: _headers,
        body: jsonEncode(
            {'entries': [for (final e in entries) e.toPushJson()]})));
    if (resp.statusCode != 200) {
      throw ApiException('provenance — HTTP ${resp.statusCode}',
          statusCode: resp.statusCode);
    }
    return ProvenancePushResult.fromJson(
        jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>);
  }

  /// #63/#82: tells the server this device won't be pruned for tracks no
  /// selection currently requires (survives a server database loss).
  /// Callers pair this with [postManifest], setting it FIRST — the
  /// manifest match writes 'downloaded' rows directly, but only this
  /// setting stops the next recompute from pruning them back out from
  /// under a device that hasn't been assigned matching selections yet.
  Future<void> setSourceOfTruth(String value) =>
      _patchJson('/api/device/source-of-truth', {'source_of_truth': value});

  /// #63/#82: a (re-)paired device reports the relative paths it already
  /// holds — the same device_path() wire form [getChanges] speaks — and the
  /// server matches them against the library, marking matches 'downloaded'
  /// so they aren't re-fetched. See [setSourceOfTruth] for the ordering
  /// this depends on.
  Future<ManifestResult> postManifest(List<String> paths) async {
    final resp = await _timed(_http.post(_uri('/api/device/manifest'),
        headers: _headers, body: jsonEncode({'paths': paths})));
    if (resp.statusCode != 200) {
      throw ApiException('manifest — HTTP ${resp.statusCode}',
          statusCode: resp.statusCode);
    }
    return ManifestResult.fromJson(
        jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>);
  }

  /// The playlists a person made on this device (see
  /// [SyncEngine.collectUserPlaylists]), the whole set found this sync; the
  /// server makes each one a playlist of the device's owner and removes one
  /// missing from a later upload. Null when the server predates this (404),
  /// so a newer app on an older server just carries on.
  Future<DevicePlaylistsResult?> postDevicePlaylists(
      List<DevicePlaylist> playlists) async {
    final resp = await _timed(_http.post(_uri('/api/device/playlists'),
        headers: _headers,
        body: jsonEncode({'playlists': [for (final pl in playlists) pl.toJson()]})));
    if (resp.statusCode == 404) return null;
    if (resp.statusCode != 200) {
      throw ApiException('device playlists — HTTP ${resp.statusCode}',
          statusCode: resp.statusCode);
    }
    return DevicePlaylistsResult.fromJson(
        jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>);
  }

  /// Streams the original file straight to [dest] (no buffering in memory —
  /// FLAC originals are large). Returns the byte count written.
  ///
  /// [resumeFrom] is how many bytes of the file [dest] already holds (an
  /// interrupted original): the rest is asked for with `Range`, and a 206
  /// appends it. A 200 means the server sent the whole file instead, which
  /// rewrites [dest] from the start.
  ///
  /// [cancelled] is asked between chunks: true stops the download with
  /// [SyncCancelled], so a stop doesn't wait for the end of a large file.
  Future<int> downloadTrack(int trackId, File dest,
      {int resumeFrom = 0, bool Function()? cancelled}) async {
    final req = http.Request('GET', _uri('/api/device/file/$trackId'));
    req.headers['Authorization'] = 'Bearer ${config.token}';
    if (resumeFrom > 0) req.headers['Range'] = 'bytes=$resumeFrom-';
    final resp = await _timed(_http.send(req));
    final resumed = resumeFrom > 0 && resp.statusCode == 206;
    if (resp.statusCode != 200 && !resumed) {
      final seconds = int.tryParse(resp.headers['retry-after'] ?? '');
      throw ApiException('file/$trackId — HTTP ${resp.statusCode}',
          statusCode: resp.statusCode,
          retryAfter: seconds == null ? null : Duration(seconds: seconds));
    }
    final sink =
        dest.openWrite(mode: resumed ? FileMode.append : FileMode.write);
    try {
      // A loop rather than pipe(): an error through pipe() closes the sink
      // itself, and the close() below then reports "File closed" instead of
      // what went wrong.
      await for (final chunk in resp.stream.timeout(idleTimeout,
          onTimeout: (events) => events.addError(ApiException(
              'file/$trackId — no data from the server in '
              '${idleTimeout.inSeconds} s')))) {
        if (cancelled?.call() ?? false) throw SyncCancelled();
        sink.add(chunk);
      }
    } finally {
      await sink.close();
    }
    return dest.length();
  }

  /// bytesOnDevice = what actually landed on the card — the size of the file
  /// the server served (already-transcoded MP3 for a transcoding device).
  Future<void> ack(int trackId, String status, {int? bytesOnDevice}) =>
      _postJson('/api/device/ack', {
        'track_id': trackId,
        'status': status,
        'bytes_on_device': ?bytesOnDevice,
      });

  /// Set this device's storage allocation (#18). `null` clears the limit
  /// (sent as JSON null, mirroring the web UI's "no limit"); the server
  /// validates it (a non-negative integer or null).
  Future<void> updateLimit(int? maxSizeBytes) =>
      _patchJson('/api/device/limit', {'max_size_bytes': maxSizeBytes});

  /// One sync finished with no error: the server only counts it. A server
  /// older than this call answers 404, which the caller ignores.
  Future<void> reportSyncCompleted() =>
      _postJson('/api/device/sync-completed', {});

  Future<void> reportStorage({int? freeBytes, int? totalBytes}) =>
      _postJson('/api/device/storage',
          {'free_bytes': freeBytes, 'total_bytes': totalBytes});

  /// the artist picture for one artist folder, downscaled
  /// server-side when the device asked for 'small'. Null on 404 (no image
  /// anywhere) — a normal outcome, not an error.
  Future<List<int>?> getArtistImage(String artist, {bool small = false}) async {
    final uri = _uri('/api/device/artist-image').replace(queryParameters: {
      'artist': artist,
      if (small) 'size': 'small',
    });
    final resp = await _timed(_http.get(uri,
        headers: {'Authorization': 'Bearer ${config.token}'}));
    if (resp.statusCode == 404) return null;
    if (resp.statusCode != 200) {
      throw ApiException('artist-image — HTTP ${resp.statusCode}',
          statusCode: resp.statusCode);
    }
    return resp.bodyBytes;
  }

  /// records the user's decision about tracks found missing on
  /// the card: re-queue for download, or mark excluded (stay deleted).
  Future<void> resolveMissing(
          {List<int> redownload = const [], List<int> exclude = const []}) =>
      _postJson('/api/device/missing-tracks',
          {'redownload': redownload, 'exclude': exclude});

  void close() => _http.close();
}
