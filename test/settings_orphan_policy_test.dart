// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// The standing answer about files Trobar didn't put on the card is chosen in
// Settings too, and Settings is the only way back out of "always keep".

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trobar_desktop/api_client.dart';
import 'package:trobar_desktop/app_prefs.dart';
import 'package:trobar_desktop/l10n/gen/app_localizations.dart';
import 'package:trobar_desktop/models.dart';
import 'package:trobar_desktop/settings_screen.dart';

const _config = DeviceConfig(serverUrl: 'http://srv', token: 't0k');

void main() {
  late Directory root;
  setUp(() async {
    root = Directory.systemTemp.createTempSync('trobar_settings_orphans');
    await AppPrefs.load(file: File('${root.path}/prefs.json'));
  });
  // As in settings_limit_test: the save can still be writing on Windows.
  tearDown(() async {
    for (var attempt = 0;; attempt++) {
      try {
        root.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        if (attempt >= 20) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  });

  /// Opens Settings, picks [choice] from the orphan dropdown and saves.
  Future<void> pick(
      WidgetTester tester, String Function(AppLocalizations) choice) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = ApiClient(_config,
        httpClient: MockClient((req) async => http.Response('{}', 200)));
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsScreen(root: root, config: _config, api: api),
    ));
    await tester.pump();
    final l = AppLocalizations.of(tester.element(find.byType(SettingsScreen)));
    final dropdown = find.ancestor(
        of: find.text(l.settingsOrphanPolicy),
        matching: find.byType(DropdownButtonFormField<String>));
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text(choice(l)).last);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('settingsSave')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
  }

  testWidgets('"Always keep them" is saved', (tester) async {
    await pick(tester, (l) => l.settingsOrphanKeep);
    expect(AppPrefs.instance.orphanPolicy, 'keep');
  });

  testWidgets('"Ask each time" takes a standing "keep" back', (tester) async {
    AppPrefs.instance.orphanPolicy = 'keep';
    await pick(tester, (l) => l.settingsOrphanAsk);
    expect(AppPrefs.instance.orphanPolicy, 'ask');
  });
}
