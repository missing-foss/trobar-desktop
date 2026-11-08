// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// desktop#26: a sync can be stopped. Between tracks, during a download
// (the track in progress is dropped, its .part with it) and during a wait
// before a retry; what was downloaded stays, and nothing after the
// downloads runs.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:trobar_desktop/api_client.dart';
import 'package:trobar_desktop/models.dart';
import 'package:trobar_desktop/sync_engine.dart';

const _config = DeviceConfig(serverUrl: 'http://srv', token: 't0k');

TrackChange _track(int id) =>
    TrackChange(trackId: id, relativePath: 'A/B/0$id - T.flac');

void main() {
  late Directory card;
  setUp(() async => card = await Directory.systemTemp.createTemp('trobar-cancel-'));
  tearDown(() => card.delete(recursive: true));

  Iterable<File> parts() => card
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.part'));

  /// Records file requests, acks and the device-playlists upload; each file
  /// answer comes from [file].
  ApiClient server(List<int> requested, List<String> other,
      Future<http.StreamedResponse> Function(int id) file) {
    return ApiClient(_config, httpClient: MockClient.streaming((req, body) async {
      if (req.url.path.startsWith('/api/device/file/')) {
        final id = int.parse(req.url.pathSegments.last);
        requested.add(id);
        return file(id);
      }
      other.add(req.url.path);
      return http.StreamedResponse(
          Stream.value(utf8.encode('{"status":"ok"}')), 200);
    }));
  }

  test('a stop while the first track downloads: nothing after runs',
      () async {
    final requested = <int>[], other = <String>[];
    var stop = false;
    final engine = SyncEngine(
        server(requested, other, (id) async {
          stop = true; // asked to stop while track 1 downloads
          return http.StreamedResponse(Stream.value([id]), 200);
        }),
        card,
        space: (_) async => null);

    final result = await engine.run(
        ChangeSet(
          toDownload: [_track(1), _track(2)],
          toDelete: const [],
          downloaded: const [],
          playlists: const [PlaylistFile(name: 'P', filename: 'P.m3u8', content: '#EXTM3U\n')],
        ),
        isCancelled: () => stop);

    expect(result.cancelled, isTrue);
    expect(requested, [1]); // track 2 never asked for
    expect(result.downloadedCount, 0); // track 1's last chunk saw the stop
    expect(other.where((p) => p == '/api/device/playlists'), isEmpty);
    expect(File(p.join(card.path, 'P.m3u8')).existsSync(), isFalse);
    expect(parts(), isEmpty);
  });

  test('a finished track before the stop is kept and acked', () async {
    // The stop comes as track 2 starts: its request goes out, its first
    // chunk sees the stop, and it is dropped.
    final requested = <int>[], other = <String>[];
    var stop = false;
    final engine = SyncEngine(
        server(requested, other,
            (id) async => http.StreamedResponse(Stream.value([id]), 200)),
        card,
        space: (_) async => null);

    final result = await engine.run(
        ChangeSet(
            toDownload: [_track(1), _track(2)],
            toDelete: const [],
            downloaded: const []),
        onProgress: (pr) => stop = pr.done == 2, // stop as track 2 starts
        isCancelled: () => stop);

    expect(result.cancelled, isTrue);
    expect(result.downloadedCount, 1);
    expect(File(p.join(card.path, 'A', 'B', '01 - T.flac')).existsSync(), isTrue);
    expect(other.where((p) => p == '/api/device/ack'), hasLength(1));
    expect(requested, [1, 2]);
    expect(File(p.join(card.path, 'A', 'B', '02 - T.flac')).existsSync(), isFalse);
    expect(parts(), isEmpty);
  });

  test('a stop between two tracks never asks for the second', () async {
    // The stop arrives with track 1's ack: track 1 is done and kept, and
    // the check before track 2 stops there, without requesting it.
    final requested = <int>[];
    var stop = false;
    final api = ApiClient(_config, httpClient: MockClient.streaming((req, _) async {
      if (req.url.path.startsWith('/api/device/file/')) {
        requested.add(int.parse(req.url.pathSegments.last));
        return http.StreamedResponse(Stream.value([1]), 200);
      }
      if (req.url.path == '/api/device/ack') stop = true;
      return http.StreamedResponse(
          Stream.value(utf8.encode('{"status":"ok"}')), 200);
    }));
    final engine = SyncEngine(api, card, space: (_) async => null);

    final result = await engine.run(
        ChangeSet(
            toDownload: [_track(1), _track(2)],
            toDelete: const [],
            downloaded: const []),
        isCancelled: () => stop);

    expect(result.cancelled, isTrue);
    expect(result.downloadedCount, 1);
    expect(requested, [1]);
  });

  test('a stop during a download drops it, .part and all', () async {
    final requested = <int>[], other = <String>[];
    var stop = false;
    final body = StreamController<List<int>>();
    final engine = SyncEngine(
        server(requested, other, (id) async {
          return http.StreamedResponse(body.stream, 200);
        }),
        card,
        space: (_) async => null);

    final running = engine.run(
        ChangeSet(
            toDownload: [_track(1)], toDelete: const [], downloaded: const []),
        isCancelled: () => stop);
    body.add([1, 2]);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    stop = true;
    body.add([3, 4]); // the next chunk sees the stop
    final result = await running;
    await body.close();

    expect(result.cancelled, isTrue);
    expect(result.downloadedCount, 0);
    expect(parts(), isEmpty);
    expect(File(p.join(card.path, 'A', 'B', '01 - T.flac')).existsSync(), isFalse);
    expect(other.where((p) => p == '/api/device/ack'), isEmpty);
  });

  test('a stop during the wait before a retry tries no more', () async {
    final requested = <int>[], other = <String>[];
    var stop = false;
    final engine = SyncEngine(
        server(requested, other,
            (id) async => http.StreamedResponse(const Stream.empty(), 500)),
        card,
        space: (_) async => null,
        wait: (_) async => stop = true);

    final result = await engine.run(
        ChangeSet(
            toDownload: [_track(1), _track(2)],
            toDelete: const [],
            downloaded: const []),
        isCancelled: () => stop);

    expect(result.cancelled, isTrue);
    expect(requested, [1]); // no second try, and track 2 never asked for
  });

  test('a stop with nothing to download still stops: nothing after runs',
      () async {
    final requested = <int>[], other = <String>[];
    final engine = SyncEngine(
        server(requested, other,
            (id) async => http.StreamedResponse(Stream.value([id]), 200)),
        card,
        space: (_) async => null);

    final result = await engine.run(
        const ChangeSet(
          toDownload: [],
          toDelete: [],
          downloaded: [],
          playlists: [PlaylistFile(name: 'P', filename: 'P.m3u8', content: '#EXTM3U\n')],
        ),
        isCancelled: () => true);

    expect(result.cancelled, isTrue);
    expect(File(p.join(card.path, 'P.m3u8')).existsSync(), isFalse);
    expect(other.where((p) => p == '/api/device/playlists'), isEmpty);
  });
}
