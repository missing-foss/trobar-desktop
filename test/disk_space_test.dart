// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// desktop#27: a card that can't hold the downloads is said so up front, and
// a card that fills up mid-sync stops the downloads instead of failing every
// one that's left in turn.

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

/// Serves `file/<id>` from [files] (or [failWith] for an id there), records
/// every file request in [requested], and acks everything.
ApiClient _server(Map<int, List<int>> files, List<int> requested,
    {Map<int, Object> failWith = const {}}) {
  return ApiClient(_config, httpClient: MockClient.streaming((req, body) async {
    if (req.url.path.startsWith('/api/device/file/')) {
      final id = int.parse(req.url.pathSegments.last);
      requested.add(id);
      final error = failWith[id];
      if (error != null) {
        return http.StreamedResponse(Stream<List<int>>.error(error), 200);
      }
      return http.StreamedResponse(Stream.value(files[id]!), 200);
    }
    return http.StreamedResponse(
        Stream.value(utf8.encode('{"status":"ok"}')), 200);
  }));
}

Future<({int free, int total})?> Function(Directory) _free(int free) =>
    (_) async => (free: free, total: free * 10);

TrackChange _track(int id, {int? size, bool transcode = false}) =>
    TrackChange(
        trackId: id,
        relativePath: 'A/B/0$id - T.flac',
        size: size,
        transcode: transcode);

// "No space left on device", as the platform reports it.
FileSystemException _noSpace() => FileSystemException('write failed', 'x',
    OSError('No space left on device', Platform.isWindows ? 112 : 28));

void main() {
  late Directory card;
  setUp(() async => card = await Directory.systemTemp.createTemp('trobar-space-'));
  tearDown(() => card.delete(recursive: true));

  test('downloads that cannot fit are not started, and say how short it is',
      () async {
    final requested = <int>[];
    final engine = SyncEngine(
        _server({1: [1], 2: [2]}, requested), card,
        space: _free(1000));

    final result = await engine.run(ChangeSet(
      toDownload: [_track(1, size: 800), _track(2, size: 700)],
      toDelete: const [],
      downloaded: const [],
    ));

    expect(result.notEnoughSpace, (needed: 1500, free: 1000));
    expect(result.downloadedCount, 0);
    expect(requested, isEmpty);
  });

  test('downloads that fit go ahead', () async {
    final requested = <int>[];
    final engine = SyncEngine(
        _server({1: [1], 2: [2]}, requested), card,
        space: _free(1500));

    final result = await engine.run(ChangeSet(
      toDownload: [_track(1, size: 800), _track(2, size: 700)],
      toDelete: const [],
      downloaded: const [],
    ));

    expect(result.notEnoughSpace, isNull);
    expect(result.downloadedCount, 2);
  });

  test('a transcoded track does not count: its final size is not known',
      () async {
    // The FLAC sizes would never fit, but what lands is the server's MP3.
    final requested = <int>[];
    final engine = SyncEngine(
        _server({1: [1], 2: [2]}, requested), card,
        space: _free(100));

    final result = await engine.run(ChangeSet(
      toDownload: [
        _track(1, size: 30000000, transcode: true),
        _track(2, size: 40000000, transcode: true),
      ],
      toDelete: const [],
      downloaded: const [],
    ));

    expect(result.notEnoughSpace, isNull);
    expect(requested, [1, 2]);
  });

  test('no free-space figure means no check', () async {
    final requested = <int>[];
    final engine = SyncEngine(_server({1: [1]}, requested), card,
        space: (_) async => null);

    final result = await engine.run(ChangeSet(
      toDownload: [_track(1, size: 1 << 40)],
      toDelete: const [],
      downloaded: const [],
    ));

    expect(result.notEnoughSpace, isNull);
    expect(result.downloadedCount, 1);
  });

  test('deletions run first and their space counts', () async {
    // The freed bytes are what the second figure reports.
    final old = File(p.join(card.path, 'Old', 'X', '01 - Gone.flac'));
    await old.create(recursive: true);
    final requested = <int>[];
    var calls = 0;
    final engine = SyncEngine(_server({1: [1]}, requested), card,
        space: (_) async {
      calls++;
      // Before the deletion this would not fit; the check runs after it.
      return (free: await old.exists() ? 10 : 1000, total: 10000);
    });

    final result = await engine.run(ChangeSet(
      toDownload: [_track(1, size: 500)],
      toDelete: const [
        TrackChange(trackId: 9, relativePath: 'Old/X/01 - Gone.flac')
      ],
      downloaded: const [],
    ));

    expect(result.notEnoughSpace, isNull);
    expect(result.downloadedCount, 1);
    expect(calls, greaterThan(0));
  });

  test('a card that fills up stops the downloads that are left', () async {
    final requested = <int>[];
    final engine = SyncEngine(
        _server({1: [1], 3: [3]}, requested, failWith: {2: _noSpace()}), card,
        space: (_) async => null);

    final result = await engine.run(ChangeSet(
      toDownload: [_track(1), _track(2), _track(3)],
      toDelete: const [],
      downloaded: const [],
    ));

    expect(result.diskFull, isTrue);
    expect(result.firstError, isNull); // said once, by diskFull
    expect(result.downloadedCount, 1);
    expect(requested, [1, 2]); // 3 was never asked for
    expect(
        card
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.part')),
        isEmpty);
  });

  test('any other write error leaves the rest of the sync alone', () async {
    final requested = <int>[];
    final other = FileSystemException(
        'write failed', 'x', const OSError('Permission denied', 13));
    final engine = SyncEngine(
        _server({1: [1], 3: [3]}, requested, failWith: {2: other}), card,
        space: (_) async => null);

    final result = await engine.run(ChangeSet(
      toDownload: [_track(1), _track(2), _track(3)],
      toDelete: const [],
      downloaded: const [],
    ));

    expect(result.diskFull, isFalse);
    expect(result.firstError, isNotNull);
    expect(requested, [1, 2, 3]);
    expect(result.downloadedCount, 2);
  });
}
