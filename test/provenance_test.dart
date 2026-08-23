// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// #77/#80: the local provenance cache (.trobar/provenance.json) — fetch
// merges/dedupes correctly, the `pushed` flag survives a no-op refetch and
// resets on a genuine change, and the push loop pages at the server's cap
// and only sends what hasn't already been acknowledged.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trobar_desktop/api_client.dart';
import 'package:trobar_desktop/card_store.dart';
import 'package:trobar_desktop/models.dart';
import 'package:trobar_desktop/provenance.dart';

void main() {
  late Directory root;
  const config = DeviceConfig(serverUrl: 'http://srv', token: 't0k');

  setUp(() => root = Directory.systemTemp.createTempSync('trobar_prov_test'));
  tearDown(() => root.deleteSync(recursive: true));

  group('readProvenance/writeProvenance', () {
    test('no provenance.json yet -> empty map', () async {
      expect(await readProvenance(root), isEmpty);
    });

    test('write then read round-trips every field, including pushed',
        () async {
      await writeProvenance(root, {
        1: const ProvenanceRecord(
            trackId: 1, fingerprint: 'FP1', path: 'A/1.flac', pushed: true),
        2: const ProvenanceRecord(
            trackId: 2, fingerprint: 'FP2', path: 'A/2.flac'),
      });
      final read = await readProvenance(root);
      expect(read, hasLength(2));
      expect(read[1]!.fingerprint, 'FP1');
      expect(read[1]!.path, 'A/1.flac');
      expect(read[1]!.pushed, isTrue);
      expect(read[2]!.pushed, isFalse);
    });

    test('corrupt file -> empty map (never throws)', () async {
      await provenanceFileFor(root).parent.create(recursive: true);
      await provenanceFileFor(root).writeAsString('{ not json');
      expect(await readProvenance(root), isEmpty);
    });

    test('valid JSON of the wrong shape -> empty map, never throws',
        () async {
      await provenanceFileFor(root).parent.create(recursive: true);
      for (final bad in ['[]', '"a string"', '42', '{"entries":"x"}']) {
        await provenanceFileFor(root).writeAsString(bad);
        expect(await readProvenance(root), isEmpty, reason: 'for: $bad');
      }
    });

    test('writeProvenance tightens perms to 0600 (#12-equivalent)', () async {
      await writeProvenance(root, {
        1: const ProvenanceRecord(trackId: 1, fingerprint: 'FP', path: 'A/1.flac')
      });
      final mode = provenanceFileFor(root).statSync().mode & 0x1FF;
      expect(mode, 0x180); // 0600 — owner rw only
    }, skip: Platform.isWindows ? 'no unix permissions on windows' : null);
  });

  group('syncProvenance — fetch (#77)', () {
    // syncProvenance always runs the push half right after the fetch half,
    // and any freshly-fetched entry starts out unpushed — so a fetch-only
    // fake that doesn't also answer POST /api/device/provenance breaks the
    // moment a test fetches anything genuinely new. Route by path instead
    // of by call order, and answer pushes with a generic success — most of
    // this group isn't asserting anything about the push side.
    http.Client fakeServer(List<Map<String, dynamic>> fingerprintPagesInOrder) {
      var call = 0;
      return MockClient((req) async {
        if (req.url.path == '/api/device/provenance') {
          return http.Response(
              jsonEncode({'received': 0, 'stored': 0, 'pending': 0}), 200);
        }
        final body = jsonEncode(fingerprintPagesInOrder[call]);
        call++;
        return http.Response(body, 200);
      });
    }

    test('a single page merges straight into an empty store', () async {
      final api = ApiClient(config,
          httpClient: fakeServer([
            {
              'entries': [
                {'track_id': 1, 'fingerprint': 'FP1', 'path': 'A/1.flac'},
                {'track_id': 2, 'fingerprint': 'FP2', 'path': 'A/2.flac'},
              ],
              'next_after': null,
              'pending': 0,
            }
          ]));
      await syncProvenance(api, root);
      final stored = await readProvenance(root);
      expect(stored, hasLength(2));
      expect(stored[1]!.fingerprint, 'FP1');
      // The fetch merges them in unpushed, but syncProvenance's own push
      // half then immediately sends and acknowledges them in the same
      // call — this is end-to-end, not fetch-in-isolation.
      expect(stored[1]!.pushed, isTrue);
    });

    test('walks multiple pages via next_after until null', () async {
      http.Request? lastFetchReq;
      var fetchCalls = 0;
      final pages = [
        {
          'entries': [
            {'track_id': 1, 'fingerprint': 'FP1', 'path': 'A/1.flac'}
          ],
          'next_after': 1,
          'pending': 0,
        },
        {
          'entries': [
            {'track_id': 2, 'fingerprint': 'FP2', 'path': 'A/2.flac'}
          ],
          'next_after': null,
          'pending': 0,
        },
      ];
      final api = ApiClient(config,
          httpClient: MockClient((req) async {
            if (req.url.path == '/api/device/provenance') {
              return http.Response(
                  jsonEncode({'received': 0, 'stored': 0, 'pending': 0}), 200);
            }
            lastFetchReq = req;
            return http.Response(jsonEncode(pages[fetchCalls++]), 200);
          }));
      await syncProvenance(api, root);
      expect(fetchCalls, 2);
      expect(lastFetchReq!.url.queryParameters['after'], '1');
      final stored = await readProvenance(root);
      expect(stored, hasLength(2));
    });

    test(
        'a no-op refetch (same fingerprint/path) never re-queues an already-pushed row for #80',
        () async {
      // The end state alone ("pushed == true") isn't a real assertion here
      // — syncProvenance's own push half runs right after the fetch and
      // would mark ANY unpushed row pushed by the time the test looks,
      // masking exactly the regression this test exists to catch (a
      // broken "unchanged" check that unconditionally clears `pushed` on
      // every refetch). The actual claim is that no push HTTP call
      // happens at all — nothing needed replaying.
      await writeProvenance(root, {
        1: const ProvenanceRecord(
            trackId: 1, fingerprint: 'FP1', path: 'A/1.flac', pushed: true)
      });
      var pushCalls = 0;
      final api = ApiClient(config,
          httpClient: MockClient((req) async {
            if (req.url.path == '/api/device/provenance') {
              pushCalls++;
              return http.Response(
                  jsonEncode({'received': 0, 'stored': 0, 'pending': 0}), 200);
            }
            return http.Response(
                jsonEncode({
                  'entries': [
                    {'track_id': 1, 'fingerprint': 'FP1', 'path': 'A/1.flac'}
                  ],
                  'next_after': null,
                  'pending': 0,
                }),
                200);
          }));
      await syncProvenance(api, root);
      expect(pushCalls, 0);
      expect((await readProvenance(root))[1]!.pushed, isTrue);
    });

    test(
        'a changed fingerprint for an already-pushed row gets replayed to the server, not silently skipped',
        () async {
      await writeProvenance(root, {
        1: const ProvenanceRecord(
            trackId: 1, fingerprint: 'OLD', path: 'A/1.flac', pushed: true)
      });
      final pushedFingerprints = <String>[];
      final api = ApiClient(config,
          httpClient: MockClient((req) async {
            if (req.url.path == '/api/device/fingerprints') {
              return http.Response(
                  jsonEncode({
                    'entries': [
                      {'track_id': 1, 'fingerprint': 'NEW', 'path': 'A/1.flac'}
                    ],
                    'next_after': null,
                    'pending': 0,
                  }),
                  200);
            }
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            for (final e in body['entries'] as List) {
              pushedFingerprints.add((e as Map)['fingerprint'] as String);
            }
            return http.Response(
                jsonEncode({'received': 1, 'stored': 1, 'pending': 0}), 200);
          }));
      // Without the "reset pushed on change" logic, this row would stay
      // marked pushed from the old fingerprint and #80's push loop would
      // never see it — the server would keep the stale identity forever.
      await syncProvenance(api, root);
      expect(pushedFingerprints, ['NEW']);
      final stored = await readProvenance(root);
      expect(stored[1]!.fingerprint, 'NEW');
      expect(stored[1]!.pushed, isTrue);
    });

    test('a changed path resets pushed to false', () async {
      await writeProvenance(root, {
        1: const ProvenanceRecord(
            trackId: 1, fingerprint: 'FP1', path: 'OLD/1.flac', pushed: true)
      });
      final api = ApiClient(config,
          httpClient: fakeServer([
            {
              'entries': [
                {'track_id': 1, 'fingerprint': 'FP1', 'path': 'NEW/1.flac'}
              ],
              'next_after': null,
              'pending': 0,
            }
          ]));
      await syncProvenance(api, root);
      final stored = await readProvenance(root);
      expect(stored[1]!.path, 'NEW/1.flac');
    });

    test('no entries and no existing rows -> provenance.json is never created',
        () async {
      final api = ApiClient(config,
          httpClient:
              fakeServer([{ 'entries': [], 'next_after': null, 'pending': 0 }]));
      await syncProvenance(api, root);
      expect(await provenanceFileFor(root).exists(), isFalse);
    });
  });

  group('syncProvenance — push (#80)', () {
    test('pushes only unpushed rows, then marks them pushed', () async {
      await writeProvenance(root, {
        1: const ProvenanceRecord(
            trackId: 1, fingerprint: 'FP1', path: 'A/1.flac', pushed: true),
        2: const ProvenanceRecord(
            trackId: 2, fingerprint: 'FP2', path: 'A/2.flac'),
      });
      final pushed = <Map<String, dynamic>>[];
      final api = ApiClient(config,
          httpClient: MockClient((req) async {
            if (req.url.path == '/api/device/fingerprints') {
              return http.Response(
                  jsonEncode({'entries': [], 'next_after': null, 'pending': 0}),
                  200);
            }
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            pushed.addAll(
                (body['entries'] as List).cast<Map<String, dynamic>>());
            return http.Response(
                jsonEncode({'received': 1, 'stored': 1, 'pending': 0}), 200);
          }));
      await syncProvenance(api, root);
      expect(pushed, hasLength(1));
      expect(pushed.single['track_id'], 2);
      expect(pushed.single.containsKey('pushed'), isFalse); // wire shape has no local-only field
      expect((await readProvenance(root))[2]!.pushed, isTrue);
    });

    test('nothing to push -> no POST /api/device/provenance call at all',
        () async {
      await writeProvenance(root, {
        1: const ProvenanceRecord(
            trackId: 1, fingerprint: 'FP1', path: 'A/1.flac', pushed: true)
      });
      var postedProvenance = false;
      final api = ApiClient(config,
          httpClient: MockClient((req) async {
            if (req.url.path == '/api/device/provenance') {
              postedProvenance = true;
            }
            if (req.url.path == '/api/device/fingerprints') {
              return http.Response(
                  jsonEncode({'entries': [], 'next_after': null, 'pending': 0}),
                  200);
            }
            return http.Response(
                jsonEncode({'received': 0, 'stored': 0, 'pending': 0}), 200);
          }));
      await syncProvenance(api, root);
      expect(postedProvenance, isFalse);
    });

    test('pages at provenancePushMax entries per request', () async {
      final many = <int, ProvenanceRecord>{
        for (var i = 1; i <= provenancePushMax + 10; i++)
          i: ProvenanceRecord(trackId: i, fingerprint: 'FP$i', path: 'A/$i.flac'),
      };
      await writeProvenance(root, many);
      final pageSizes = <int>[];
      final api = ApiClient(config,
          httpClient: MockClient((req) async {
            if (req.url.path == '/api/device/fingerprints') {
              return http.Response(
                  jsonEncode({'entries': [], 'next_after': null, 'pending': 0}),
                  200);
            }
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            pageSizes.add((body['entries'] as List).length);
            return http.Response(
                jsonEncode({'received': 0, 'stored': 0, 'pending': 0}), 200);
          }));
      await syncProvenance(api, root);
      expect(pageSizes, [provenancePushMax, 10]);
      expect((await readProvenance(root)).values.every((e) => e.pushed), isTrue);
    });

    test('a non-200 push response throws ApiException, matching the rest of the client',
        () async {
      await writeProvenance(root, {
        1: const ProvenanceRecord(trackId: 1, fingerprint: 'FP1', path: 'A/1.flac')
      });
      final api = ApiClient(config,
          httpClient: MockClient((req) async {
            if (req.url.path == '/api/device/fingerprints') {
              return http.Response(
                  jsonEncode({'entries': [], 'next_after': null, 'pending': 0}),
                  200);
            }
            return http.Response('nope', 403);
          }));
      expect(() => syncProvenance(api, root), throwsA(isA<ApiException>()));
    });
  });
}
