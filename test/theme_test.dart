// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// The brand themes: each one's derived scheme, light or dark; the dark-only
// themes (Nuèch, Contraste) stay dark under a light system; brandInk follows
// the theme; and an unknown stored key reads as Troubadour.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trobar_desktop/brand_tokens.dart';
import 'package:trobar_desktop/main.dart' show brandInk, brandThemeData;

void main() {
  Future<Color> inkUnder(WidgetTester tester, BrandTheme brand, Brightness brightness) async {
    late Color ink;
    // A fresh tree each time: MaterialApp animates a theme change, so the
    // first frame after a re-pump would still show the previous theme.
    await tester.pumpWidget(MaterialApp(
      key: UniqueKey(),
      theme: brandThemeData(brand, brightness),
      home: Builder(builder: (context) {
        ink = brandInk(context);
        return const SizedBox();
      }),
    ));
    return ink;
  }

  testWidgets('brandInk is light on a dark theme and dark on a light one', (tester) async {
    for (final t in BrandTheme.values) {
      final dark = await inkUnder(tester, t, Brightness.dark);
      expect(dark.computeLuminance() > 0.5, isTrue, reason: '$t dark');
      if (!t.darkOnly) {
        final light = await inkUnder(tester, t, Brightness.light);
        expect(light.computeLuminance() < 0.5, isTrue, reason: '$t light');
      }
    }
  });

  test('a dark-only theme is dark whatever the brightness asked for', () {
    for (final t in [BrandTheme.nuech, BrandTheme.contraste]) {
      expect(brandColorScheme(t, Brightness.light).brightness, Brightness.dark);
      expect(brandBackground(t, Brightness.light), brandBackground(t, Brightness.dark));
    }
    expect(brandColorScheme(BrandTheme.garriga, Brightness.light).brightness, Brightness.light);
  });

  test('Troubadour keeps the burgundy it had', () {
    expect(brandColorScheme(BrandTheme.troubadour, Brightness.light).primary, const Color(0xFFA83250));
    expect(brandBackground(BrandTheme.troubadour, Brightness.dark), const Color(0xFF100E08));
  });

  test('an unknown stored key is Troubadour', () {
    expect(BrandTheme.of('bard'), BrandTheme.troubadour);
    expect(BrandTheme.of(null), BrandTheme.troubadour);
    expect(BrandTheme.of('peira'), BrandTheme.peira);
  });
}
