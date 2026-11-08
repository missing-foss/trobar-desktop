// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// desktop#31: the home screen with no card, with one, and a card that
// appears while it's open.

import 'dart:async';
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
    root = Directory.systemTemp.createTempSync('trobar_home');
    await AppPrefs.load(file: File('${root.path}/prefs.json'));
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<AppLocalizations> pump(WidgetTester tester,
      Future<List<(Directory, DeviceConfig)>> Function() discover) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: HomeScreen(discover: discover),
    ));
    await tester.pump();
    return AppLocalizations.of(tester.element(find.byType(HomeScreen)));
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  }

  testWidgets('no card: says so', (tester) async {
    final l = await pump(tester, () async => []);
    expect(find.text(l.noCardDetected), findsOneWidget);
    await finish(tester);
  });

  testWidgets('a paired folder is listed', (tester) async {
    final card = Directory('${root.path}/Card')..createSync();
    await pump(tester, () async => [(card, _config)]);
    expect(find.text(card.path), findsOneWidget);
    await finish(tester);
  });

  testWidgets('a card that appears while open is listed on the next poll',
      (tester) async {
    final card = Directory('${root.path}/Card')..createSync();
    var found = <(Directory, DeviceConfig)>[];
    final l = await pump(tester, () async => found);
    expect(find.text(l.noCardDetected), findsOneWidget);

    found = [(card, _config)];
    await tester.pump(const Duration(seconds: 8)); // the poll
    await tester.pump();
    expect(find.text(card.path), findsOneWidget);
    await finish(tester);
  });

  testWidgets('the poll waits for a scan already running rather than start another',
      (tester) async {
    final card = Directory('${root.path}/Card')..createSync();
    var calls = 0;
    final pending = Completer<List<(Directory, DeviceConfig)>>();
    await pump(tester, () {
      calls++;
      return pending.future;
    });
    expect(calls, 1); // the launch scan, still running

    await tester.pump(const Duration(seconds: 8)); // the poll fires meanwhile
    expect(calls, 1);

    pending.complete([(card, _config)]);
    await tester.pump();
    expect(find.text(card.path), findsOneWidget);

    await tester.pump(const Duration(seconds: 8)); // the next poll scans again
    expect(calls, 2);
    await finish(tester);
  });

  testWidgets('the card screen dates the last sync in French, with the year',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => writeSyncOutcome(
        root,
        SyncOutcome(
            syncedAt: DateTime(2026, 10, 16, 14, 5),
            downloaded: 2,
            deleted: 0)));
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CardScreen(
            root: root,
            config: _config,
            client: MockClient((_) async => http.Response('{"name": "Card"}', 200))),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    final l = AppLocalizations.of(tester.element(find.byType(CardScreen)));
    expect(find.text(l.lastSync('16/10/2026 14:05')), findsOneWidget);
    expect(find.text(l.syncSummary(2, 0)), findsOneWidget);
    await finish(tester);
  });
}
