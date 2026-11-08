// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// desktop#28: an unattended sync (auto-sync on detect, the interval) decides
// nothing for the user. With policy "ask" it no longer tells the server to
// exclude tracks that are missing from the card, and it never asks about
// files no track claims; a manual sync still asks both, with Keep as the
// emphasised choice for the orphans.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trobar_desktop/app_prefs.dart';
import 'package:trobar_desktop/l10n/gen/app_localizations.dart';
import 'package:trobar_desktop/main.dart';
import 'package:trobar_desktop/models.dart';

const _config = DeviceConfig(serverUrl: 'http://srv', token: 't0k');

void main() {
  late Directory root;
  late List<String> paths;
  setUp(() async {
    root = Directory.systemTemp.createTempSync('trobar_unattended');
    paths = [];
    await AppPrefs.load(file: File('${root.path}/prefs.json'));
  });
  tearDown(() => root.deleteSync(recursive: true));

  /// A server that believes track 7 is on the card (it isn't), and records
  /// every request path.
  MockClient server() => MockClient((req) async {
        paths.add(req.url.path);
        if (req.url.path == '/api/device/info') {
          return http.Response('{"name": "Card"}', 200);
        }
        if (req.url.path == '/api/device/changes') {
          return http.Response(
              jsonEncode({
                'to_download': [],
                'to_delete': [],
                'downloaded': [
                  {'track_id': 7, 'relative_path': 'A/B/07 - Gone.flac', 'size': 1}
                ],
              }),
              200);
        }
        return http.Response('{"status": "ok"}', 200);
      });

  Future<AppLocalizations> open(WidgetTester tester, {required bool autoSync}) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CardScreen(
            root: root, config: _config, autoSync: autoSync, client: server()),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    return AppLocalizations.of(tester.element(find.byType(CardScreen)));
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 2));
  }

  testWidgets('an unattended sync with policy "ask" excludes nothing',
      (tester) async {
    // A stray audio file no track claims, too: not asked about either.
    await tester.runAsync(
        () => File('${root.path}/Mine/song.mp3').create(recursive: true));
    await open(tester, autoSync: true);

    expect(paths, contains('/api/device/changes')); // the control: it synced
    expect(paths, isNot(contains('/api/device/missing-tracks')));
    expect(find.byType(AlertDialog), findsNothing);
    await finish(tester);
  });

  testWidgets('an unattended sync with policy "exclude" still applies it',
      (tester) async {
    AppPrefs.instance.missingPolicy = 'exclude';
    await open(tester, autoSync: true);
    expect(paths, contains('/api/device/missing-tracks'));
    await finish(tester);
  });

  testWidgets('a manual sync still asks about the missing tracks',
      (tester) async {
    final l = await open(tester, autoSync: false);
    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.sync));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    expect(find.text(l.missingTitle(1)), findsOneWidget);
    await tester.tap(find.text(l.cancel));
    await tester.pump();
    await finish(tester);
  });

  testWidgets('a manual sync asks about orphans with Keep emphasised',
      (tester) async {
    AppPrefs.instance.missingPolicy = 'exclude'; // no missing-tracks prompt
    await tester.runAsync(
        () => File('${root.path}/Mine/song.mp3').create(recursive: true));
    final l = await open(tester, autoSync: false);
    await tester.runAsync(() async {
      await tester.tap(find.byIcon(Icons.sync));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();

    expect(find.text(l.orphansTitle(1)), findsOneWidget);
    expect(find.widgetWithText(FilledButton, l.keep), findsOneWidget);
    // Nothing is ticked, so deleting is not on offer until something is.
    final delete = tester.widget<TextButton>(find.widgetWithText(TextButton, l.orphansDeleteSelected(0)));
    expect(delete.onPressed, isNull);
    await tester.tap(find.text(l.keep));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    expect(File('${root.path}/Mine/song.mp3').existsSync(), isTrue);
    await finish(tester);
  });
}
