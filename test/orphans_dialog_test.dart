// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// What an unattended sync leaves undecided is said on the card screen until
// a manual sync decides it; the files no track claims are offered one by
// one, nothing ticked, with a standing "keep them" that stops the question.

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
import 'package:trobar_desktop/orphans_dialog.dart';

const _config = DeviceConfig(serverUrl: 'http://srv', token: 't0k');

void main() {
  late Directory root;
  late List<String> paths;
  setUp(() async {
    root = Directory.systemTemp.createTempSync('trobar_orphans');
    paths = [];
    await AppPrefs.load(file: File('${root.path}/prefs.json'));
  });
  tearDown(() => root.deleteSync(recursive: true));

  /// A server that believes [missing] tracks are on the card (they aren't).
  MockClient server({int missing = 0}) => MockClient((req) async {
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
                  for (var i = 1; i <= missing; i++)
                    {'track_id': i, 'relative_path': 'A/B/0$i - Gone.flac', 'size': 1}
                ],
              }),
              200);
        }
        return http.Response('{"status": "ok"}', 200);
      });

  /// No sync is running: the button shows its sync icon again.
  bool idle() => find.byIcon(Icons.sync).evaluate().isNotEmpty;

  bool asking() => find.byType(OrphansDialog).evaluate().isNotEmpty;

  int changesAsked() => paths.where((p) => p == '/api/device/changes').length;

  /// Pumps until [done] holds, letting the real work (file I/O, the mock
  /// client) run between pumps, and fails naming [what] if it never does.
  /// A fixed wait here was too short when the machine was busy. The limit
  /// counts real 20 ms waits, because the test's clock is fake.
  Future<void> pumpUntil(WidgetTester tester, bool Function() done, String what) async {
    for (var i = 0; i < 500; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      if (done()) return;
    }
    fail('still waiting after about 10 s for $what '
        '(requests: $paths, idle: ${idle()}, asking: ${asking()})');
  }

  Future<AppLocalizations> open(WidgetTester tester,
      {required bool autoSync, int missing = 0}) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CardScreen(
            root: root, config: _config, autoSync: autoSync, client: server(missing: missing)),
      ));
    });
    await pumpUntil(
        tester,
        () => paths.contains('/api/device/info') && (!autoSync || (changesAsked() > 0 && idle())),
        autoSync ? 'the unattended sync to finish' : 'the card to load');
    return AppLocalizations.of(tester.element(find.byType(CardScreen)));
  }

  /// Starts a sync by hand, then pumps until [until] holds. The tap is made
  /// inside runAsync so the sync's real work runs outside the fake clock.
  Future<void> manualSync(WidgetTester tester, bool Function() until, String what) async {
    await tester.runAsync(() async => tester.tap(find.byIcon(Icons.sync)));
    await pumpUntil(tester, until, what);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 2));
  }

  Future<void> orphans(List<String> names) => Future.wait([
        for (final n in names) File('${root.path}/Mine/$n').create(recursive: true)
      ]);

  testWidgets('what an unattended sync leaves undecided is said, and Decide asks',
      (tester) async {
    final l = await open(tester, autoSync: true, missing: 3);
    expect(find.text(l.missingUndecided(3)), findsOneWidget);
    expect(paths, isNot(contains('/api/device/missing-tracks')));

    await tester.runAsync(() async => tester.tap(find.text(l.decide)));
    await pumpUntil(tester, () => find.text(l.missingTitle(3)).evaluate().isNotEmpty,
        'the missing-tracks question');
    expect(find.text(l.missingTitle(3)), findsOneWidget);
    await finish(tester);
  });

  testWidgets('a manual sync that decides takes the banner away', (tester) async {
    final l = await open(tester, autoSync: true, missing: 2);
    expect(find.text(l.missingUndecided(2)), findsOneWidget); // the control

    // "keep" as well: the prefs file is on the card, and otherwise the sync
    // stops to ask about it, still running, with the banner hidden anyway.
    AppPrefs.instance
      ..missingPolicy = 'exclude'
      ..orphanPolicy = 'keep';
    await manualSync(tester, () => paths.contains('/api/device/missing-tracks') && idle(),
        'the deciding sync to finish');
    expect(paths, contains('/api/device/missing-tracks')); // it decided
    expect(find.text(l.missingUndecided(2)), findsNothing);
    await finish(tester);
  });

  testWidgets('only the ticked files are deleted', (tester) async {
    AppPrefs.instance.missingPolicy = 'exclude';
    await tester.runAsync(() => orphans(['keep.mp3', 'old.flac']));
    final l = await open(tester, autoSync: false);
    await manualSync(tester, asking, 'the orphans question');
    expect(find.text(l.orphansTitle(2)), findsOneWidget);

    await tester.tap(find.widgetWithText(CheckboxListTile, 'Mine/old.flac'));
    await tester.pump();
    await tester.tap(find.text(l.orphansDeleteSelected(1)));
    await pumpUntil(tester, () => !File('${root.path}/Mine/old.flac').existsSync() && idle(),
        'the ticked file to be deleted');
    expect(File('${root.path}/Mine/old.flac').existsSync(), isFalse);
    expect(File('${root.path}/Mine/keep.mp3').existsSync(), isTrue);
    await finish(tester);
  });

  testWidgets('"always keep" is remembered, and the next sync asks nothing',
      (tester) async {
    AppPrefs.instance.missingPolicy = 'exclude';
    await tester.runAsync(() => orphans(['mine.mp3']));
    final l = await open(tester, autoSync: false);
    await manualSync(tester, asking, 'the orphans question');
    await tester.tap(find.text(l.orphansAlwaysKeep));
    await tester.pump();
    await tester.tap(find.text(l.keep));
    await pumpUntil(tester, () => AppPrefs.instance.orphanPolicy == 'keep' && idle(),
        '"always keep" to be saved and the sync to finish');
    // Let the dialog's exit run out on the fake clock: until it has, its
    // barrier takes the next tap and no second sync starts.
    await tester.pump(const Duration(seconds: 1));
    expect(AppPrefs.instance.orphanPolicy, 'keep');
    expect(File('${root.path}/Mine/mine.mp3').existsSync(), isTrue);

    // Any dialog at all, not one with a given count: the prefs file this
    // test saves is on the card too, so a second ask would say "2 files".
    // Wait until the second sync has run and either finished or asked, so
    // "asks nothing" below can't pass before it has even started.
    final before = changesAsked();
    await manualSync(tester, () => changesAsked() > before && (idle() || asking()),
        'the second sync to finish');
    expect(changesAsked(), greaterThan(before)); // the control: the second sync ran
    expect(find.byType(OrphansDialog), findsNothing);
    await finish(tester);
  });

  testWidgets('with "keep" set, a manual sync asks nothing and still syncs',
      (tester) async {
    AppPrefs.instance
      ..missingPolicy = 'exclude'
      ..orphanPolicy = 'keep';
    await tester.runAsync(() => orphans(['mine.mp3']));
    await open(tester, autoSync: false);
    await manualSync(
        tester, () => changesAsked() > 0 && (idle() || asking()), 'the sync to finish');
    expect(paths, contains('/api/device/changes'));
    expect(find.byType(OrphansDialog), findsNothing);
    expect(File('${root.path}/Mine/mine.mp3').existsSync(), isTrue);
    await finish(tester);
  });
}
