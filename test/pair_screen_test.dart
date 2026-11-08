// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// The pairing screen's own checks, made before anything is sent: no request
// goes out for a missing server URL, a code that can't be one, or a blank
// device name. (Redeeming itself is covered in enrollment_test.dart.)

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trobar_desktop/card_store.dart';
import 'package:trobar_desktop/l10n/gen/app_localizations.dart';
import 'package:trobar_desktop/main.dart';
import 'package:trobar_desktop/models.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('trobar_pair_screen'));
  tearDown(() => root.deleteSync(recursive: true));

  Future<AppLocalizations> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PairScreen(root: root),
    ));
    return AppLocalizations.of(tester.element(find.byType(PairScreen)));
  }

  Finder field(String label) => find.widgetWithText(TextField, label);

  // No ensureVisible: it waits for the screen to settle, which a focused
  // field's blinking cursor never does. The window above is tall enough.
  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump();
  }

  testWidgets('the device name starts as the folder name', (tester) async {
    final l10n = await pump(tester);
    final name = tester.widget<TextField>(field(l10n.pairNameLabel));
    expect(name.controller!.text, root.uri.pathSegments.where((s) => s.isNotEmpty).last);
  });

  testWidgets('a missing server URL, a bad code, a blank name: no pairing', (tester) async {
    final l10n = await pump(tester);
    final pair = find.widgetWithText(FilledButton, l10n.pairButton);

    await tester.enterText(field(l10n.pairCodeLabel), 'ABCD2345');
    await tap(tester, pair);
    expect(find.text(l10n.pairMissingServer), findsOneWidget);

    await tester.enterText(field(l10n.pairServerUrlLabel), 'https://music.example');
    await tester.enterText(field(l10n.pairCodeLabel), 'ABCD0000');
    await tap(tester, pair);
    expect(find.text(l10n.pairInvalidCode), findsOneWidget);

    await tester.enterText(field(l10n.pairCodeLabel), 'abcd-2345');
    await tester.enterText(field(l10n.pairNameLabel), '  ');
    await tap(tester, pair);
    expect(find.text(l10n.pairMissingName), findsOneWidget);

    // File I/O runs on the real clock, not the test's fake one.
    expect(await tester.runAsync(() => readConfig(root)), isNull);
  });

  testWidgets('a server URL without http:// or https:// is caught before sending', (tester) async {
    var sent = false;
    final client = MockClient((_) async {
      sent = true;
      return http.Response('{}', 500);
    });
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PairScreen(root: root, client: client),
    ));
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pump();
    final l10n = AppLocalizations.of(tester.element(find.byType(PairScreen)));

    await tester.enterText(field(l10n.pairServerUrlLabel), 'music.example');
    await tester.enterText(field(l10n.pairCodeLabel), 'ABCD2345');
    await tap(tester, find.widgetWithText(FilledButton, l10n.pairButton));
    expect(find.text(l10n.pairBadServerUrl), findsOneWidget);

    // The same check for a pasted enrollment payload.
    await tester.enterText(find.byWidgetPredicate((w) => w is TextField && w.maxLines == 4),
        '{"server_url": "music.example", "enroll_code": "ABCD2345"}');
    await tap(tester, find.widgetWithText(OutlinedButton, l10n.pairConfigButton));
    expect(find.text(l10n.pairBadServerUrl), findsOneWidget);
    expect(sent, isFalse);
  });

  testWidgets('a code redeems with the typed name and the app language, pops the config, and shows the server name',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late http.Request sent;
    final client = MockClient((req) async {
      sent = req;
      return http.Response(jsonEncode({'id': 4, 'name': 'Name on the server', 'token': 'device-token'}), 200);
    });
    DeviceConfig? popped;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
          builder: (context) => Scaffold(
              body: TextButton(
                  onPressed: () async => popped = await Navigator.of(context).push<DeviceConfig>(
                      MaterialPageRoute(builder: (_) => PairScreen(root: root, client: client))),
                  child: const Text('open')))),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(tester.element(find.byType(PairScreen)));

    await tester.enterText(field(l10n.pairServerUrlLabel), 'https://music.example/');
    await tester.enterText(field(l10n.pairCodeLabel), 'abcd 2345');
    await tester.enterText(field(l10n.pairNameLabel), 'My card');
    // Redeeming writes the card: real file and process I/O, on the real clock.
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, l10n.pairButton));
      for (var i = 0; i < 100 && popped == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
    await tester.pump();

    expect(jsonDecode(sent.body), {'code': 'ABCD2345', 'name': 'My card', 'device_type': 'sdcard'});
    expect(sent.headers['Accept-Language'], 'fr');
    expect(sent.url.toString(), 'https://music.example/api/enrollment/redeem');
    expect((popped?.serverUrl, popped?.token), ('https://music.example', 'device-token'));
    expect(find.text(l10n.pairedAs('Name on the server')), findsOneWidget);
  });

  testWidgets('a pasted device config still pairs the card', (tester) async {
    final l10n = await pump(tester);
    await tester.enterText(
        find.byWidgetPredicate((w) => w is TextField && w.maxLines == 4),
        '{"server_url": "https://x", "token": "raw-token"}');
    final button = find.widgetWithText(OutlinedButton, l10n.pairConfigButton);
    // Writing the card is real file and process I/O, which the test's fake
    // clock doesn't drive: run it on the real one and wait for the file.
    final stored = await tester.runAsync(() async {
      await tester.tap(button);
      for (var i = 0; i < 50; i++) {
        final config = await readConfig(root);
        if (config != null) return config;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      return null;
    });
    expect(stored?.token, 'raw-token');
  });
}
