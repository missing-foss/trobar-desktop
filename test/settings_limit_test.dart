// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// desktop#31: the storage limit takes a decimal comma ("1,5", as a French
// user types it) as well as a point, and sends the same bytes either way.

import 'dart:convert';
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
    root = Directory.systemTemp.createTempSync('trobar_settings');
    await AppPrefs.load(file: File('${root.path}/prefs.json'));
  });
  // Windows won't delete a file that is still open, and the save the test
  // waited 200 ms for can still be writing on a slow machine. Retry briefly
  // rather than fail the test on its own cleanup.
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

  Future<List<Object?>> saveLimit(WidgetTester tester, String typed) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sent = <Object?>[];
    final api = ApiClient(_config, httpClient: MockClient((req) async {
      if (req.url.path == '/api/device/limit') {
        sent.add((jsonDecode(req.body) as Map)['max_size_bytes']);
      }
      return http.Response('{}', 200);
    }));
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('fr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsScreen(root: root, config: _config, api: api),
    ));
    await tester.pump();
    final l = AppLocalizations.of(tester.element(find.byType(SettingsScreen)));
    await tester.enterText(
        find.widgetWithText(TextFormField, l.settingsStorageLimit), typed);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('settingsSave')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    return sent;
  }

  testWidgets('"1,5" is 1.5 GB', (tester) async {
    expect(await saveLimit(tester, '1,5'), [1500000000]);
  });

  testWidgets('"1.5" is the same', (tester) async {
    expect(await saveLimit(tester, '1.5'), [1500000000]);
  });

  testWidgets('"abc" is refused, nothing sent', (tester) async {
    final sent = await saveLimit(tester, 'abc');
    expect(sent, isEmpty);
    final l = AppLocalizations.of(tester.element(find.byType(SettingsScreen)));
    expect(find.text(l.settingsInvalidLimit), findsOneWidget);
  });
}
