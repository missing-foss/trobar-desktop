// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// The About screen's support button: "Support on Ko-fi" in the app's own
// theme, with no colour of its own, where it goes, and the note under it
// saying what the money pays for.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:trobar_desktop/about_screen.dart';
import 'package:trobar_desktop/l10n/gen/app_localizations.dart';

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
        appName: 'trobar_desktop',
        packageName: 'trobar_desktop',
        version: '0.0.0',
        buildNumber: '1',
        buildSignature: '');
  });

  Future<void> pump(WidgetTester tester, Locale locale,
      {void Function(Uri)? openUrl}) async {
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: AboutScreen(openUrl: openUrl),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('the support button reads "Support on Ko-fi" in the theme',
      (tester) async {
    await pump(tester, const Locale('en'));
    final button = find.widgetWithText(FilledButton, 'Support on Ko-fi');
    expect(button, findsOneWidget);
    // No style of its own: the colours are the theme's, not a brand's.
    expect(tester.widget<FilledButton>(button).style, isNull);
    expect(find.textContaining('Liberapay'), findsNothing);
  });

  testWidgets('and "Soutenir sur Ko-fi" in French', (tester) async {
    await pump(tester, const Locale('fr'));
    expect(find.widgetWithText(FilledButton, 'Soutenir sur Ko-fi'),
        findsOneWidget);
  });

  testWidgets('under it, what the money pays for', (tester) async {
    await pump(tester, const Locale('en'));
    final note = find.byKey(const Key('supportNote'));
    expect(tester.widget<Text>(note).data,
        'Support pays for test devices, infrastructure and Claude. Mostly, it '
        'buys a good coffee and keeps the motivation going for the next projects.');
    expect(tester.getTopLeft(note).dy,
        greaterThan(tester.getBottomLeft(find.widgetWithText(FilledButton, 'Support on Ko-fi')).dy));
  });

  testWidgets('and in French', (tester) async {
    await pump(tester, const Locale('fr'));
    expect(tester.widget<Text>(find.byKey(const Key('supportNote'))).data,
        "Le soutien paie les appareils de test, l'infrastructure et Claude. Surtout, "
        'il offre un bon café et entretient la motivation pour les prochains projets.');
  });

  testWidgets('a tap on it opens Ko-fi', (tester) async {
    final opened = <Uri>[];
    await pump(tester, const Locale('en'), openUrl: opened.add);
    await tester.tap(find.widgetWithText(FilledButton, 'Support on Ko-fi'));
    expect(opened, [Uri.parse('https://ko-fi.com/missingfoss')]);
  });
}
