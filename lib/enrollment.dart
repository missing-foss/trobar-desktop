// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// Pairing with a short enrollment code: the 8-character code the web app's
// "Add mobile device" and "Re-pair in app" show, the same one the Android app
// redeems. The code is exchanged once for the device's own token, and the
// card then holds exactly the {server_url, token} a raw-token pairing writes,
// so nothing after pairing knows or cares which way the card was paired.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'card_store.dart';
import 'models.dart';

/// The server's code alphabet: no 0/O/1/I/L, so a code read off a screen
/// can't be mistyped into another valid one.
const enrollAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const enrollCodeLength = 8;

/// What can be pasted into the pairing screen: either a device config
/// (`{"server_url", "token"}`, also what `trobar-device.json` holds) or an
/// enrollment payload (`{"server_url", "enroll_code"}`, what the web app's
/// enrollment QR code carries).
sealed class PairingInput {
  const PairingInput();
}

class TokenInput extends PairingInput {
  final DeviceConfig config;
  const TokenInput(this.config);
}

class EnrollInput extends PairingInput {
  final String serverUrl;
  final String code;
  const EnrollInput(this.serverUrl, this.code);
}

/// Parses pasted text, or a loaded file's contents. Null when it is
/// neither shape, including a code that isn't a valid enrollment code.
PairingInput? parsePairingInput(String raw) {
  // trim() also drops the UTF-8 BOM some editors and browsers prepend
  // (Dart counts U+FEFF as whitespace), which jsonDecode would reject.
  final text = raw.trim();
  Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException {
    return null;
  }
  if (json is! Map<String, dynamic> || json['server_url'] is! String) {
    return null;
  }
  if (json['token'] is String) return TokenInput(DeviceConfig.fromJson(json));
  if (json['enroll_code'] is String) {
    final code = normalizeEnrollCode(json['enroll_code'] as String);
    if (code == null) return null;
    return EnrollInput((json['server_url'] as String).trim(), code);
  }
  return null;
}

/// The code as the server expects it, or null if it can't be one. Spaces
/// and dashes are dropped (a code is easier to read out in two halves) and
/// letters upper-cased; what remains must be 8 characters of the alphabet.
String? normalizeEnrollCode(String raw) {
  final code = raw.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
  if (code.length != enrollCodeLength) return null;
  for (final c in code.split('')) {
    if (!enrollAlphabet.contains(c)) return null;
  }
  return code;
}

/// Whether [raw] can be a server URL to redeem at: http or https, with a
/// host. Checked before sending, because package:http reports a URL
/// without a scheme (the likeliest typo) as an ArgumentError, not as a
/// failed request.
bool isUsableServerUrl(String raw) {
  final uri = Uri.tryParse(raw.trim());
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

enum EnrollFailure { invalidCode, rateLimited, network, other }

class EnrollException implements Exception {
  final EnrollFailure kind;

  /// The server's own message, already in the language the request asked
  /// for, when it sent one.
  final String? serverMessage;
  EnrollException(this.kind, [this.serverMessage]);
  @override
  String toString() => serverMessage ?? kind.name;
}

class EnrollmentResult {
  final int id;

  /// The device's name as the server has it. A re-pair code keeps the
  /// existing device's name, whatever name was sent.
  final String name;
  final String token;
  const EnrollmentResult(this.id, this.name, this.token);
}

/// Redeems [code] at [serverUrl]: `POST /api/enrollment/redeem`, no auth
/// header (the single-use code is the credential). A new device is created
/// as an `sdcard` named [name]; a re-pair code re-attaches to its device.
/// [language] goes out as Accept-Language, so the server's error message
/// comes back in the app's language.
Future<EnrollmentResult> redeemEnrollment({
  required String serverUrl,
  required String code,
  required String name,
  String? language,
  http.Client? client,
}) async {
  final base = serverUrl.trim().replaceFirst(RegExp(r'/+$'), '');
  final http.Response resp;
  final httpClient = client ?? http.Client();
  try {
    resp = await httpClient
        .post(Uri.parse('$base/api/enrollment/redeem'),
            headers: {
              'Content-Type': 'application/json',
              'Accept-Language': ?language,
            },
            body: jsonEncode(
                {'code': code, 'name': name, 'device_type': 'sdcard'}))
        .timeout(const Duration(seconds: 30));
  } on Exception catch (e) {
    // Unreachable host, refused connection, timeout, a malformed URL.
    throw EnrollException(EnrollFailure.network, e.toString());
  } on ArgumentError catch (e) {
    // A URL package:http won't send at all (no scheme or host, another
    // scheme). The screen checks first; this keeps any other caller from
    // getting an uncaught error.
    throw EnrollException(EnrollFailure.network, e.message.toString());
  } finally {
    if (client == null) httpClient.close();
  }
  if (resp.statusCode == 200) {
    try {
      final json = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      return EnrollmentResult(json['id'] as int,
          (json['name'] as String?) ?? name, json['token'] as String);
    } on Object {
      throw EnrollException(EnrollFailure.other);
    }
  }
  String? message;
  try {
    final error = (jsonDecode(utf8.decode(resp.bodyBytes)) as Map)['error'];
    if (error is String && error.trim().isNotEmpty) message = error;
  } on Object {
    message = null;
  }
  throw EnrollException(
      switch (resp.statusCode) {
        400 => EnrollFailure.invalidCode,
        429 => EnrollFailure.rateLimited,
        _ => EnrollFailure.other,
      },
      message);
}

/// Redeems the code and pairs [root] with the result: the card gets the
/// same `.trobar/device.json` a raw-token pairing writes, and its manifest
/// is marked pending as for any fresh pairing. Nothing is written unless
/// the redeem succeeded.
Future<(DeviceConfig, EnrollmentResult)> pairWithCode(Directory root, {
  required String serverUrl,
  required String code,
  required String name,
  String? language,
  http.Client? client,
}) async {
  final result = await redeemEnrollment(
      serverUrl: serverUrl, code: code, name: name, language: language, client: client);
  final config = DeviceConfig(
      serverUrl: serverUrl.trim().replaceFirst(RegExp(r'/+$'), ''), token: result.token);
  await writeConfig(root, config);
  await markManifestPending(root);
  return (config, result);
}
