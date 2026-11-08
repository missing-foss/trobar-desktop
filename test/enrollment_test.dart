// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// Pairing with a short enrollment code: what the pairing screen accepts, the
// redeem request and its failures, and what lands on the card. The server is
// a MockClient answering as POST /api/enrollment/redeem does.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trobar_desktop/card_store.dart';
import 'package:trobar_desktop/enrollment.dart';
import 'package:trobar_desktop/models.dart';

http.Response _json(int status, Object body) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

void main() {
  group('parsePairingInput', () {
    test('a device config (also what trobar-device.json holds)', () {
      final input = parsePairingInput('{"server_url": " https://music.example/ ", "token": "tok"}');
      expect(input, isA<TokenInput>());
      final config = (input as TokenInput).config;
      expect(config.serverUrl, 'https://music.example/');
      expect(config.token, 'tok');
    });

    test('an enrollment payload, as the web app QR code carries it', () {
      final input = parsePairingInput('{"server_url": "https://music.example", "enroll_code": "abcd 2345"}');
      expect(input, isA<EnrollInput>());
      expect((input as EnrollInput).serverUrl, 'https://music.example');
      expect(input.code, 'ABCD2345');
    });

    test('a leading byte-order mark is ignored', () {
      expect(parsePairingInput('\uFEFF{"server_url": "https://x", "token": "t"}'), isA<TokenInput>());
    });

    test('anything else is null', () {
      for (final raw in [
        '',
        'not json',
        '[1, 2]',
        '{"token": "t"}',
        '{"server_url": "https://x"}',
        '{"server_url": 3, "token": "t"}',
        '{"server_url": "https://x", "enroll_code": "TOOSHORT1"}',
        '{"server_url": "https://x", "enroll_code": "ABCD0OIL"}',
      ]) {
        expect(parsePairingInput(raw), isNull, reason: raw);
      }
    });
  });

  group('normalizeEnrollCode', () {
    test('drops spaces and dashes, upper-cases', () {
      expect(normalizeEnrollCode(' abcd-2345 '), 'ABCD2345');
    });

    test('rejects a wrong length or a character outside the alphabet', () {
      expect(normalizeEnrollCode('ABCD234'), isNull);
      expect(normalizeEnrollCode('ABCD23456'), isNull);
      for (final c in ['0', 'O', '1', 'I', 'L', '!']) {
        expect(normalizeEnrollCode('ABCD234$c'), isNull, reason: c);
      }
    });
  });

  test('isUsableServerUrl: http or https, with a host', () {
    for (final ok in ['https://music.example', 'http://192.0.2.10:5000/', ' https://x/trobar ']) {
      expect(isUsableServerUrl(ok), isTrue, reason: ok);
    }
    for (final bad in ['', 'music.example', 'music.example:5000', 'ftp://music.example', 'https://', 'https:///x', 'not a url']) {
      expect(isUsableServerUrl(bad), isFalse, reason: bad);
    }
  });

  group('redeemEnrollment', () {
    test('posts the code, the name and the card type, with no auth header', () async {
      late http.Request sent;
      final client = MockClient((req) async {
        sent = req;
        return _json(200, {'id': 7, 'name': 'Old name', 'token': 'device-token'});
      });
      final result = await redeemEnrollment(
          serverUrl: 'https://music.example//', code: 'ABCD2345', name: 'Card',
          language: 'fr', client: client);

      expect(sent.method, 'POST');
      expect(sent.url.toString(), 'https://music.example/api/enrollment/redeem');
      expect(jsonDecode(sent.body), {'code': 'ABCD2345', 'name': 'Card', 'device_type': 'sdcard'});
      expect(sent.headers['Accept-Language'], 'fr');
      expect(sent.headers.containsKey('Authorization'), isFalse);
      // The server's name wins: a re-pair code keeps the device's own.
      expect((result.id, result.name, result.token), (7, 'Old name', 'device-token'));
    });

    test('no language, no Accept-Language header', () async {
      late http.Request sent;
      final client = MockClient((req) async {
        sent = req;
        return _json(200, {'id': 1, 'name': 'n', 'token': 't'});
      });
      await redeemEnrollment(serverUrl: 'https://x', code: 'ABCD2345', name: 'n', client: client);
      expect(sent.headers.containsKey('Accept-Language'), isFalse);
    });

    Future<EnrollException> failure(http.Response resp) async {
      try {
        await redeemEnrollment(
            serverUrl: 'https://x', code: 'ABCD2345', name: 'n',
            client: MockClient((_) async => resp));
      } on EnrollException catch (e) {
        return e;
      }
      fail('expected an EnrollException');
    }

    test('400 is an invalid code, 429 rate limiting, with the server message', () async {
      final invalid = await failure(_json(400, {'error': 'Code invalide ou expiré.'}));
      expect(invalid.kind, EnrollFailure.invalidCode);
      expect(invalid.serverMessage, 'Code invalide ou expiré.');
      expect((await failure(_json(429, {'error': 'Too many attempts.'}))).kind, EnrollFailure.rateLimited);
    });

    test('another status, or a body that is not the expected JSON', () async {
      final server = await failure(http.Response('<html>Bad gateway</html>', 502));
      expect(server.kind, EnrollFailure.other);
      expect(server.serverMessage, isNull);
      expect((await failure(_json(200, {'id': 'x'}))).kind, EnrollFailure.other);
    });

    test('an unreachable server is a network failure', () async {
      try {
        await redeemEnrollment(
            serverUrl: 'https://x', code: 'ABCD2345', name: 'n',
            client: MockClient((_) async => throw const SocketException('refused')));
        fail('expected an EnrollException');
      } on EnrollException catch (e) {
        expect(e.kind, EnrollFailure.network);
      }
    });
  });

  test('a URL package:http refuses is a network failure, not an uncaught error', () async {
    // A real client: the fake one would never see the URL rejected.
    for (final url in ['music.example', 'ftp://music.example']) {
      try {
        await redeemEnrollment(serverUrl: url, code: 'ABCD2345', name: 'n');
        fail('expected an EnrollException for $url');
      } on EnrollException catch (e) {
        expect(e.kind, EnrollFailure.network, reason: url);
      }
    }
  });

  group('pairWithCode', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('trobar_enroll_test'));
    tearDown(() => root.deleteSync(recursive: true));

    test('a redeemed code writes device.json and marks the manifest pending', () async {
      final client = MockClient((_) async => _json(200, {'id': 3, 'name': 'Card', 'token': 'device-token'}));
      final (config, result) = await pairWithCode(root,
          serverUrl: 'https://music.example/', code: 'ABCD2345', name: 'Card', client: client);

      expect(result.name, 'Card');
      final stored = await readConfig(root);
      expect(stored, isNotNull);
      expect((stored!.serverUrl, stored.token), ('https://music.example', 'device-token'));
      expect((config.serverUrl, config.token), (stored.serverUrl, stored.token));
      expect(await manifestPending(root), isTrue);
    });

    test('a rejected code leaves no file behind', () async {
      final client = MockClient((_) async => _json(400, {'error': 'Invalid or expired enrollment code.'}));
      await expectLater(
          pairWithCode(root, serverUrl: 'https://x', code: 'ABCD2345', name: 'Card', client: client),
          throwsA(isA<EnrollException>()));
      expect(await readConfig(root), isNull);
      expect(await manifestPending(root), isFalse);
      expect(root.listSync(), isEmpty);
    });
  });

  test('a card paired with a raw token still loads', () async {
    final root = Directory.systemTemp.createTempSync('trobar_legacy_test');
    addTearDown(() => root.deleteSync(recursive: true));
    await writeConfig(root, const DeviceConfig(serverUrl: 'https://x', token: 'raw-token'));
    final read = await readConfig(root);
    expect((read!.serverUrl, read.token), ('https://x', 'raw-token'));
  });
}
