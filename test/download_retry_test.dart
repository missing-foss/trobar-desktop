// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// desktop#27: a track the server fails on, or whose connection drops, is
// tried again before it counts as failed, honouring the server's
// Retry-After; an original resumes from what it already wrote.

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
final _content = List<int>.generate(10, (i) => i);

/// A server whose answer to the n-th file request is `answers[n]`; every
/// file request's Range header goes into [ranges].
ApiClient _server(
    List<http.StreamedResponse Function(http.BaseRequest)> answers,
    List<String?> ranges) {
  var n = 0;
  return ApiClient(_config, httpClient: MockClient.streaming((req, _) async {
    if (req.url.path.startsWith('/api/device/file/')) {
      ranges.add(req.headers['Range']);
      return answers[n++](req);
    }
    return http.StreamedResponse(
        Stream.value(utf8.encode('{"status":"ok"}')), 200);
  }));
}

http.StreamedResponse _ok(http.BaseRequest _) =>
    http.StreamedResponse(Stream.value(_content), 200);
http.StreamedResponse Function(http.BaseRequest) _status(int code,
        {Map<String, String> headers = const {}}) =>
    (_) => http.StreamedResponse(const Stream.empty(), code, headers: headers);

/// The first [n] bytes, then the connection drops.
http.StreamedResponse Function(http.BaseRequest) _dropsAfter(int n) =>
    (_) => http.StreamedResponse(
        Stream.fromIterable([_content.sublist(0, n)]).followedBy(
            Stream.error(http.ClientException('Connection closed'))),
        200);

/// What a Range request asks for, as a 206.
http.StreamedResponse _partial(http.BaseRequest req) {
  final from = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(req.headers['Range']!)![1]!);
  return http.StreamedResponse(Stream.value(_content.sublist(from)), 206);
}

extension<T> on Stream<T> {
  Stream<T> followedBy(Stream<T> next) async* {
    yield* this;
    yield* next;
  }
}

void main() {
  late Directory card;
  setUp(() async => card = await Directory.systemTemp.createTemp('trobar-retry-'));
  tearDown(() => card.delete(recursive: true));

  Future<(SyncResult, List<Duration>)> run(ApiClient api,
      {bool transcode = false}) async {
    final waits = <Duration>[];
    final engine = SyncEngine(api, card,
        space: (_) async => null, wait: (d) async => waits.add(d));
    final result = await engine.run(ChangeSet(
      toDownload: [
        TrackChange(
            trackId: 1, relativePath: 'A/B/01 - T.flac', transcode: transcode)
      ],
      toDelete: const [],
      downloaded: const [],
    ));
    return (result, waits);
  }

  File track() => File(p.join(card.path, 'A', 'B', '01 - T.flac'));
  Iterable<File> parts() => card
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.part'));

  test('a busy server is waited for as long as it asks, then tried again',
      () async {
    final ranges = <String?>[];
    final (result, waits) = await run(_server(
        [_status(503, headers: {'retry-after': '7'}), _ok], ranges));
    expect(result.downloadedCount, 1);
    expect(waits, [const Duration(seconds: 7)]);
    expect(await track().readAsBytes(), _content);
  });

  test('a Retry-After over a minute is waited for a minute', () async {
    final (result, waits) = await run(_server(
        [_status(503, headers: {'retry-after': '600'}), _ok], []));
    expect(result.downloadedCount, 1);
    expect(waits, [const Duration(minutes: 1)]);
  });

  test('a track that keeps failing counts as failed after three tries',
      () async {
    final ranges = <String?>[];
    final (result, waits) = await run(
        _server([_status(500), _status(500), _status(500)], ranges));
    expect(ranges, hasLength(3));
    expect(waits, [const Duration(seconds: 2), const Duration(seconds: 4)]);
    expect(result.downloadedCount, 0);
    expect(result.firstError, contains('HTTP 500'));
    expect(parts(), isEmpty);
  });

  test('a refusal is not tried again', () async {
    final ranges = <String?>[];
    final (result, waits) = await run(_server([_status(404)], ranges));
    expect(ranges, hasLength(1));
    expect(waits, isEmpty);
    expect(result.firstError, contains('HTTP 404'));
  });

  test('a dropped original resumes from what it wrote', () async {
    final ranges = <String?>[];
    final (result, _) = await run(_server([_dropsAfter(4), _partial], ranges));
    expect(ranges, [null, 'bytes=4-']);
    expect(result.downloadedCount, 1);
    expect(await track().readAsBytes(), _content);
  });

  test('a server that sends the whole file anyway is not appended to',
      () async {
    final ranges = <String?>[];
    final (result, _) = await run(_server([_dropsAfter(4), _ok], ranges));
    expect(ranges, [null, 'bytes=4-']);
    expect(await track().readAsBytes(), _content); // not 4 + 10 bytes
    expect(result.downloadedCount, 1);
  });

  test('a transcoded track starts over: there is nothing to resume into',
      () async {
    final ranges = <String?>[];
    final (result, _) =
        await run(_server([_dropsAfter(4), _ok], ranges), transcode: true);
    expect(ranges, [null, null]);
    expect(await track().readAsBytes(), _content);
    expect(result.downloadedCount, 1);
  });

  test('a part the server cannot resume (416) is fetched whole', () async {
    final ranges = <String?>[];
    final (result, _) =
        await run(_server([_dropsAfter(4), _status(416), _ok], ranges));
    expect(ranges, [null, 'bytes=4-', null]);
    expect(await track().readAsBytes(), _content);
    expect(result.downloadedCount, 1);
  });

  test('a part left by an earlier run is not resumed', () async {
    // A crash or an unplugged card left 4 bytes of an older version of the
    // file; resuming it would join that head to the new file's tail.
    final stale = File('${track().path}.part');
    await stale.create(recursive: true);
    await stale.writeAsBytes([90, 90, 90, 90]);
    final ranges = <String?>[];
    final (result, _) = await run(_server([_ok], ranges));
    expect(ranges, [null]); // the whole file was asked for, once
    expect(await track().readAsBytes(), _content);
    expect(result.downloadedCount, 1);
  });
}
