// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// desktop#27: a card whose token the server refuses says so in words, with
// a way to pair it again, rather than "GET /api/device/info — HTTP 401".

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trobar_desktop/app_prefs.dart';
import 'package:trobar_desktop/card_store.dart';
import 'package:trobar_desktop/l10n/gen/app_localizations.dart';
import 'package:trobar_desktop/main.dart';
import 'package:trobar_desktop/models.dart';

const _config = DeviceConfig(serverUrl: 'http://srv', token: 't0k');

void main() {
  late Directory root;
  setUp(() async {
    root = Directory.systemTemp.createTempSync('trobar_revoked');
    // The card screen reads the auto-sync interval on open; defaults (off).
    await AppPrefs.load(file: File('${root.path}/prefs.json'));
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<AppLocalizations> pump(WidgetTester tester, int status,
      {bool infoOk = false, bool infoOkOnce = false}) async {
    var infoAnswered = 0;
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CardScreen(
            root: root,
            config: _config,
            client: MockClient((req) async =>
                req.url.path == '/api/device/info' &&
                        (infoOk || (infoOkOnce && infoAnswered++ == 0))
                    ? http.Response('{"name": "Card"}', 200)
                    : http.Response('', status))),
      ));
      // The card read and the refused request, outside fake time.
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    return AppLocalizations.of(tester.element(find.byType(CardScreen)));
  }

  testWidgets('a refused token reads as such and offers to pair again',
      (tester) async {
    final l = await pump(tester, 401);
    expect(find.text(l.pairingRevoked), findsOneWidget);
    expect(find.widgetWithText(TextButton, l.pairAgain), findsOneWidget);
    expect(find.textContaining('HTTP 401'), findsNothing);
  });

  testWidgets('403 is a refused token too', (tester) async {
    final l = await pump(tester, 403);
    expect(find.text(l.pairingRevoked), findsOneWidget);
  });

  testWidgets('a server error is shown as it is, with no pairing offer',
      (tester) async {
    final l = await pump(tester, 500);
    expect(find.textContaining('HTTP 500'), findsOneWidget);
    expect(find.widgetWithText(TextButton, l.pairAgain), findsNothing);
  });

  testWidgets('a failed recovery handshake is said once, not swallowed',
      (tester) async {
    // A card holding music, still waiting to tell the server about it.
    await tester.runAsync(() async {
      await File('${root.path}/A/B/01 - One.flac').create(recursive: true);
      await markManifestPending(root);
    });
    final l = await pump(tester, 500, infoOk: true);

    expect(find.textContaining(l.recoveryFailed('').split('(').first.trim()),
        findsOneWidget);
    // Still pending, so the next open tries again.
    expect(await tester.runAsync(() => manifestPending(root)), isTrue);
  });

  testWidgets('a recovery refused for the token offers to pair again',
      (tester) async {
    await tester.runAsync(() async {
      await File('${root.path}/A/B/01 - One.flac').create(recursive: true);
      await markManifestPending(root);
    });
    final l = await pump(tester, 401, infoOk: true);

    expect(find.textContaining(l.pairingRevoked), findsOneWidget);
    expect(find.widgetWithText(TextButton, l.pairAgain), findsOneWidget);
  });

  testWidgets('a sync the server refuses for the token says so too',
      (tester) async {
    // The card opens fine; the device is removed before the sync, so from
    // then on the server refuses the token everywhere.
    final l = await pump(tester, 401, infoOkOnce: true);
    expect(find.text(l.pairingRevoked), findsNothing); // the control

    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.sync));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    // Said by the sync's outcome and by the reload after it, which is
    // refused too: both in words, one offer.
    expect(find.text(l.pairingRevoked), findsWidgets);
    expect(find.widgetWithText(TextButton, l.pairAgain), findsOneWidget);
    expect(find.textContaining('HTTP 401'), findsNothing);
  });

  testWidgets('the offer opens the pairing screen for this card',
      (tester) async {
    final l = await pump(tester, 401);
    await tester.tap(find.widgetWithText(TextButton, l.pairAgain));
    await tester.pumpAndSettle();
    final pair = tester.widget<PairScreen>(find.byType(PairScreen));
    expect(pair.root.path, root.path);
  });

  testWidgets('after pairing again, the card uses the new pairing',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // One fake server: it refuses the old token, redeems a code for a new
    // one, and accepts that.
    final infoTokens = <String?>[];
    final client = MockClient((req) async {
      if (req.url.path == '/api/enrollment/redeem') {
        return http.Response(
            jsonEncode({'id': 4, 'name': 'Card', 'token': 'n3w'}), 200);
      }
      if (req.url.path == '/api/device/info') {
        infoTokens.add(req.headers['Authorization']);
        return req.headers['Authorization'] == 'Bearer n3w'
            ? http.Response('{"name": "Card"}', 200)
            : http.Response('', 401);
      }
      return http.Response('', 404);
    });
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CardScreen(root: root, config: _config, client: client),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    final l = AppLocalizations.of(tester.element(find.byType(CardScreen)));
    expect(find.text(l.pairingRevoked), findsOneWidget); // the control

    await tester.tap(find.widgetWithText(TextButton, l.pairAgain));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, l.pairServerUrlLabel), 'http://srv');
    await tester.enterText(
        find.widgetWithText(TextField, l.pairCodeLabel), 'ABCD2345');
    // Redeeming writes the card: real I/O, on the real clock.
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, l.pairButton));
      for (var i = 0; i < 100 && !infoTokens.contains('Bearer n3w'); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    // The pairing screen's closing transition runs on the test clock.
    await tester.pumpAndSettle();

    expect(find.byType(PairScreen), findsNothing);
    expect(infoTokens.last, 'Bearer n3w');
    expect(find.text(l.pairingRevoked), findsNothing);
    expect(find.widgetWithText(TextButton, l.pairAgain), findsNothing);
  });

  testWidgets('a recovery failure never hides an earlier error',
      (tester) async {
    // The load fails first (500 on info); the handshake then fails too.
    await tester.runAsync(() async {
      await File('${root.path}/A/B/01 - One.flac').create(recursive: true);
      await markManifestPending(root);
    });
    final l = await pump(tester, 500);

    expect(find.textContaining('HTTP 500'), findsOneWidget);
    expect(find.textContaining(l.recoveryFailed('').split('(').first.trim()),
        findsNothing);
  });

  testWidgets('a later successful load takes the refusal back', (tester) async {
    var refuse = true;
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final client = MockClient((req) async => refuse
        ? http.Response('', 403)
        : http.Response('{"name": "Card"}', 200));
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CardScreen(root: root, config: _config, client: client),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    final l = AppLocalizations.of(tester.element(find.byType(CardScreen)));
    expect(find.widgetWithText(TextButton, l.pairAgain), findsOneWidget);

    // The refusal passes; something reloads the card (Settings does).
    refuse = false;
    final state = tester.state(find.byType(CardScreen));
    await tester.runAsync(() async {
      await (state as dynamic).reloadForTest();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();

    expect(find.widgetWithText(TextButton, l.pairAgain), findsNothing);
    expect(find.text(l.pairingRevoked), findsNothing);
  });
}
