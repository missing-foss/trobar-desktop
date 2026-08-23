// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// #18: the new updateLimit() — PATCH /api/device/limit, byte count or JSON
// null (no limit), Bearer-authed, non-200 surfaced.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trobar_desktop/api_client.dart';
import 'package:trobar_desktop/models.dart';

void main() {
  const config = DeviceConfig(serverUrl: 'http://srv', token: 't0k');

  test('updateLimit PATCHes /api/device/limit with the byte count', () async {
    http.Request? seen;
    final api = ApiClient(config, httpClient: MockClient((req) async {
      seen = req;
      return http.Response('{}', 200);
    }));

    await api.updateLimit(5000000000);

    expect(seen!.method, 'PATCH');
    expect(seen!.url.path, '/api/device/limit');
    expect(seen!.headers['Authorization'], 'Bearer t0k');
    expect(jsonDecode(seen!.body), {'max_size_bytes': 5000000000});
  });

  test('updateLimit(null) sends JSON null — no limit', () async {
    http.Request? seen;
    final api = ApiClient(config, httpClient: MockClient((req) async {
      seen = req;
      return http.Response('{}', 200);
    }));

    await api.updateLimit(null);

    expect(jsonDecode(seen!.body), {'max_size_bytes': null});
  });

  test('a non-200 response throws ApiException', () async {
    final api = ApiClient(config,
        httpClient: MockClient((req) async => http.Response('nope', 403)));
    expect(() => api.updateLimit(1), throwsA(isA<ApiException>()));
  });

  test('setSourceOfTruth PATCHes /api/device/source-of-truth', () async {
    http.Request? seen;
    final api = ApiClient(config, httpClient: MockClient((req) async {
      seen = req;
      return http.Response('{"status":"ok"}', 200);
    }));

    await api.setSourceOfTruth('device');

    expect(seen!.method, 'PATCH');
    expect(seen!.url.path, '/api/device/source-of-truth');
    expect(seen!.headers['Authorization'], 'Bearer t0k');
    expect(jsonDecode(seen!.body), {'source_of_truth': 'device'});
  });

  test('postManifest POSTs the paths and returns matched/unmatched',
      () async {
    http.Request? seen;
    final api = ApiClient(config, httpClient: MockClient((req) async {
      seen = req;
      return http.Response('{"matched":2,"unmatched":1}', 200);
    }));

    final result =
        await api.postManifest(['A/1.mp3', 'A/2.mp3', 'A/unknown.mp3']);

    expect(seen!.method, 'POST');
    expect(seen!.url.path, '/api/device/manifest');
    expect(jsonDecode(seen!.body),
        {'paths': ['A/1.mp3', 'A/2.mp3', 'A/unknown.mp3']});
    expect(result.matched, 2);
    expect(result.unmatched, 1);
  });

  test('postManifest on a non-200 response throws ApiException', () async {
    final api = ApiClient(config,
        httpClient: MockClient((req) async => http.Response('nope', 400)));
    expect(() => api.postManifest(['a']), throwsA(isA<ApiException>()));
  });
}
