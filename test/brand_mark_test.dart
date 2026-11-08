// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// The rosette: its three layers take the active theme's colours, and while
// syncing only the star layer turns, not when the platform asks for reduced
// motion.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trobar_desktop/brand_tokens.dart';
import 'package:trobar_desktop/main.dart' show brandThemeData;
import 'package:trobar_desktop/syncing_logo.dart';

void main() {
  late String source;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    source = await rootBundle.loadString('assets/brand/trobar-mark-themable.svg');
  });

  String hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  test('each layer is filled in the theme\'s own colours', () {
    for (final t in BrandTheme.values) {
      final layers = markLayers(source, t);
      List<String> fills(String svg) =>
          RegExp(r'fill="(#[0-9a-f]{6})"').allMatches(svg).map((m) => m[1]!).toList();
      expect(fills(layers[0]), [hex(t.disc), hex(t.star)], reason: '$t disc + pommels');
      expect(fills(layers[1]), [hex(t.star), hex(t.star)], reason: '$t star');
      expect(fills(layers[2]), [hex(t.disc), hex(t.dot)], reason: '$t hub + dot');
    }
  });

  Future<double> starTurnAfter(WidgetTester tester, {required bool syncing, bool reduceMotion = false}) async {
    await tester.pumpWidget(MaterialApp(
      theme: brandThemeData(BrandTheme.garriga, Brightness.light),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Center(child: TrobarMark(size: 96, syncing: syncing)),
      ),
    ));
    // Let the asset load resolve, then advance the animation clock.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final star = tester.widget<RotationTransition>(find.byKey(const ValueKey('mark-star')));
    return star.turns.value;
  }

  testWidgets('the star turns while syncing', (tester) async {
    expect(await starTurnAfter(tester, syncing: true), greaterThan(0));
  });

  testWidgets('the star holds still when not syncing', (tester) async {
    expect(await starTurnAfter(tester, syncing: false), 0);
  });

  testWidgets('the star holds still under reduced motion', (tester) async {
    expect(await starTurnAfter(tester, syncing: true, reduceMotion: true), 0);
  });
}
