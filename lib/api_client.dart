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
  ApiException(this.message);
  @override
  String toString() => message;
}

class ApiClient {
  final DeviceConfig config;
  final http.Client _http;

  ApiClient(this.config, {http.Client? httpClient})
      : _http = httpClient ?? http.Client();

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
    final resp = await _http.get(_uri(path), headers: _headers);
    if (resp.statusCode != 200) {
      throw ApiException('GET $path — HTTP ${resp.statusCode}');
    }
    return jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
  }

  Future<void> _postJson(String path, Map<String, dynamic> body) async {
    final resp =
        await _http.post(_uri(path), headers: _headers, body: jsonEncode(body));
    if (resp.statusCode != 200) {
      throw ApiException('POST $path — HTTP ${resp.statusCode}');
    }
  }

  Future<void> _patchJson(String path, Map<String, dynamic> body) async {
    final resp = await _http.patch(_uri(path),
        headers: _headers, body: jsonEncode(body));
    if (resp.statusCode != 200) {
      throw ApiException('PATCH $path — HTTP ${resp.statusCode}');
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
    final resp = await _http.get(uri, headers: _headers);
    if (resp.statusCode != 200) {
      throw ApiException('fingerprints — HTTP ${resp.statusCode}');
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
    final resp = await _http.post(_uri('/api/device/provenance'),
        headers: _headers,
        body: jsonEncode(
            {'entries': [for (final e in entries) e.toPushJson()]}));
    if (resp.statusCode != 200) {
      throw ApiException('provenance — HTTP ${resp.statusCode}');
    }
    return ProvenancePushResult.fromJson(
        jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>);
  }

  /// Streams the original file straight to [dest] (no buffering in memory —
  /// FLAC originals are large). Returns the byte count written.
  Future<int> downloadTrack(int trackId, File dest) async {
    final req = http.Request('GET', _uri('/api/device/file/$trackId'));
    req.headers['Authorization'] = 'Bearer ${config.token}';
    final resp = await _http.send(req);
    if (resp.statusCode != 200) {
      throw ApiException('file/$trackId — HTTP ${resp.statusCode}');
    }
    final sink = dest.openWrite();
    try {
      await resp.stream.pipe(sink);
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
    final resp = await _http.get(uri,
        headers: {'Authorization': 'Bearer ${config.token}'});
    if (resp.statusCode == 404) return null;
    if (resp.statusCode != 200) {
      throw ApiException('artist-image — HTTP ${resp.statusCode}');
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
