// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// desktop#27: a stalled server fails a request instead of hanging it. Each
// JSON call waits at most requestTimeout for the whole answer; a download
// waits at most requestTimeout for its headers and then idleTimeout
// between chunks.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trobar_desktop/api_client.dart';
import 'package:trobar_desktop/models.dart';

const _config = DeviceConfig(serverUrl: 'http://srv', token: 't0k');
const _short = Duration(milliseconds: 50);

ApiClient _client(http.Client http) => ApiClient(
  _config,
  httpClient: http,
  requestTimeout: _short,
  idleTimeout: _short,
);

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('trobar-timeout-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test(
    'a JSON call to a server that never answers throws ApiException',
    () async {
      final never = Completer<http.Response>();
      final api = _client(MockClient((req) => never.future));
      await expectLater(api.getChanges(), throwsA(isA<ApiException>()));
    },
  );

  test('every JSON call is bounded, writes included', () async {
    final never = Completer<http.Response>();
    final api = _client(MockClient((req) => never.future));
    for (final call in <Future<Object?> Function()>[
      api.getInfo,
      () => api.ack(1, 'downloaded'),
      () => api.updateLimit(1),
      () => api.postManifest(const []),
      () => api.pushProvenance(const []),
      () => api.postDevicePlaylists(const []),
      () => api.getFingerprintsPage(0),
      () => api.getArtistImage('A'),
    ]) {
      await expectLater(call(), throwsA(isA<ApiException>()));
    }
  });

  test('a download whose headers never arrive throws ApiException', () async {
    final never = Completer<http.StreamedResponse>();
    final api = _client(MockClient.streaming((req, body) => never.future));
    await expectLater(
      api.downloadTrack(1, File('${tmp.path}/a.part')),
      throwsA(isA<ApiException>()),
    );
  });

  test('a download that stalls mid-file throws ApiException', () async {
    // One chunk, then silence: the connection is open but nothing comes.
    final body = StreamController<List<int>>();
    body.add([1, 2, 3]);
    final api = _client(
      MockClient.streaming(
        (req, _) async => http.StreamedResponse(body.stream, 200),
      ),
    );
    await expectLater(
      api.downloadTrack(1, File('${tmp.path}/b.part')),
      throwsA(isA<ApiException>()),
    );
    await body.close();
  });

  test('a slow but steady download is not cut off', () async {
    // Every chunk arrives inside idleTimeout, though the whole file takes
    // longer than it: only silence counts, not total time.
    Stream<List<int>> steady() async* {
      for (var i = 0; i < 4; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        yield [i];
      }
    }

    final api = _client(
      MockClient.streaming(
        (req, _) async => http.StreamedResponse(steady(), 200),
      ),
    );
    final written = await api.downloadTrack(1, File('${tmp.path}/c.part'));
    expect(written, 4);
  });
}
