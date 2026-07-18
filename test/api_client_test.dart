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
}
