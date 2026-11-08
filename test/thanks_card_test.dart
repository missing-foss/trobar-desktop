// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// The one-time thank-you card: on Home once this install has finished 50
// syncs with no error, gone for good after either button, and each such
// sync counted here and reported to the server, best-effort.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trobar_desktop/api_client.dart';
import 'package:trobar_desktop/app_prefs.dart';
import 'package:trobar_desktop/l10n/gen/app_localizations.dart';
import 'package:trobar_desktop/main.dart';
import 'package:trobar_desktop/models.dart';
import 'package:trobar_desktop/thanks_card.dart';

const _config = DeviceConfig(serverUrl: 'http://srv', token: 't0k');

void main() {
  late Directory root;
  late File prefsFile;
  setUp(() async {
    root = Directory.systemTemp.createTempSync('trobar_thanks');
    prefsFile = File('${root.path}/prefs.json');
    await AppPrefs.load(file: prefsFile);
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<void> pumpHome(WidgetTester tester,
      {Locale locale = const Locale('en'), void Function(Uri)? openUrl}) async {
    tester.view.physicalSize = const Size(1000, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: HomeScreen(discover: () async => [], openUrl: openUrl),
    ));
    await tester.pump();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  }

  Map<String, dynamic> saved() =>
      jsonDecode(prefsFile.readAsStringSync()) as Map<String, dynamic>;

  testWidgets('not before the 50th sync', (tester) async {
    AppPrefs.instance.syncsCompleted = thanksCardSyncs - 1;
    await pumpHome(tester);
    expect(find.byKey(const Key('thanksCard')), findsNothing);
    await finish(tester);
  });

  testWidgets('from the 50th: thanks, says why, and offers Ko-fi', (tester) async {
    AppPrefs.instance.syncsCompleted = thanksCardSyncs;
    await pumpHome(tester);
    expect(find.byKey(const Key('thanksCard')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('thanksCardHeading'))).textSpan!.toPlainText(),
        'Thank you');
    expect(tester.widget<Text>(find.byKey(const Key('thanksCardText'))).data,
        "Trobar has synced 50 times for you.\nIf it's useful, a coffee helps.");
    expect(find.widgetWithText(FilledButton, 'Support on Ko-fi'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('and in French', (tester) async {
    AppPrefs.instance.syncsCompleted = thanksCardSyncs;
    await pumpHome(tester, locale: const Locale('fr'));
    expect(tester.widget<Text>(find.byKey(const Key('thanksCardHeading'))).textSpan!.toPlainText(),
        'Mer ci');
    expect(tester.widget<Text>(find.byKey(const Key('thanksCardText'))).data,
        "Trobar a synchronisé 50 fois pour vous.\nS'il vous est utile, un café aide.");
    await finish(tester);
  });

  testWidgets('the cross dismisses it for good', (tester) async {
    AppPrefs.instance.syncsCompleted = thanksCardSyncs;
    await pumpHome(tester);
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Dismiss'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(find.byKey(const Key('thanksCard')), findsNothing);
    expect(saved()['thanks_card_done'], isTrue);
    await finish(tester);
  });

  testWidgets('Support on Ko-fi opens Ko-fi and dismisses it too', (tester) async {
    AppPrefs.instance.syncsCompleted = thanksCardSyncs;
    final opened = <Uri>[];
    await pumpHome(tester, openUrl: opened.add);
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Support on Ko-fi'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(opened, [Uri.parse('https://ko-fi.com/missingfoss')]);
    expect(find.byKey(const Key('thanksCard')), findsNothing);
    expect(saved()['thanks_card_done'], isTrue);
    await finish(tester);
  });

  test('a successful sync is counted, saved and reported', () async {
    final paths = <String>[];
    final api = ApiClient(_config, httpClient: MockClient((req) async {
      paths.add('${req.method} ${req.url.path}');
      return http.Response('{"status": "ok"}', 200);
    }));
    await recordSuccessfulSync(AppPrefs.instance, api);
    expect(AppPrefs.instance.syncsCompleted, 1);
    expect(saved()['syncs_completed'], 1);
    expect(paths, ['POST /api/device/sync-completed']);
  });

  test('an older server without the call still counts the sync here', () async {
    final api = ApiClient(_config,
        httpClient: MockClient((req) async => http.Response('not found', 404)));
    await recordSuccessfulSync(AppPrefs.instance, api);
    expect(AppPrefs.instance.syncsCompleted, 1);
  });

  testWidgets('a sync that ends in an error is not counted', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CardScreen(
            root: root,
            config: _config,
            autoSync: true,
            client: MockClient((req) async => req.url.path == '/api/device/changes'
                ? http.Response('boom', 500)
                : http.Response('{"name": "Card"}', 200))),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    expect(AppPrefs.instance.syncsCompleted, 0);
    await finish(tester);
  });

  testWidgets('a sync that finishes is counted and reported', (tester) async {
    final paths = <String>[];
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CardScreen(
            root: root,
            config: _config,
            autoSync: true,
            client: MockClient((req) async {
              paths.add(req.url.path);
              if (req.url.path == '/api/device/changes') {
                return http.Response(
                    jsonEncode({'to_download': [], 'to_delete': [], 'downloaded': []}), 200);
              }
              return http.Response('{"name": "Card", "status": "ok"}', 200);
            })),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    expect(AppPrefs.instance.syncsCompleted, 1);
    expect(paths, contains('/api/device/sync-completed'));
    await finish(tester);
  });
}
