// SPDX-License-Identifier: GPL-3.0-or-later
// Thin client for the Trobar device API (Bearer-token half of the server,
// same endpoints the Android app uses).

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'models.dart';

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

  Future<DeviceInfo> getInfo() async =>
      DeviceInfo.fromJson(await _getJson('/api/device/info'));

  Future<ChangeSet> getChanges() async =>
      ChangeSet.fromJson(await _getJson('/api/device/changes'));

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

  /// bytesOnDevice = what actually landed on the card (gitea#2) — for a
  /// plain copy that's the original size, for a transcode (M3) the MP3's.
  Future<void> ack(int trackId, String status, {int? bytesOnDevice}) =>
      _postJson('/api/device/ack', {
        'track_id': trackId,
        'status': status,
        if (bytesOnDevice != null) 'bytes_on_device': bytesOnDevice,
      });

  Future<void> reportStorage({int? freeBytes, int? totalBytes}) =>
      _postJson('/api/device/storage',
          {'free_bytes': freeBytes, 'total_bytes': totalBytes});

  /// gitea#127 — the artist picture for one artist folder, downscaled
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

  /// gitea#49 — records the user's decision about tracks found missing on
  /// the card: re-queue for download, or mark excluded (stay deleted).
  Future<void> resolveMissing(
          {List<int> redownload = const [], List<int> exclude = const []}) =>
      _postJson('/api/device/missing-tracks',
          {'redownload': redownload, 'exclude': exclude});

  void close() => _http.close();
}
