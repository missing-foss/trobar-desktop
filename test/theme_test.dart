// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// #19: the app follows the OS light/dark theme. brandInk() must adapt so the
// light theme gets readable dark text instead of the (invisible) brand cream.
// Pure build-time reads — no async, so this is reliable in flutter_test.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trobar_desktop/main.dart' show brandCream, brandInk;

void main() {
  Future<Color> inkUnder(WidgetTester tester, Brightness brightness) async {
    late Color ink;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Builder(builder: (context) {
        ink = brandInk(context);
        return const SizedBox();
      }),
    ));
    return ink;
  }

  testWidgets('brandInk is the brand cream on the dark theme', (tester) async {
    expect(await inkUnder(tester, Brightness.dark), brandCream);
  });

  testWidgets('brandInk is a dark, readable colour on the light theme',
      (tester) async {
    final ink = await inkUnder(tester, Brightness.light);
    expect(ink, isNot(brandCream)); // not the invisible cream
    expect(ink.computeLuminance() < 0.5, isTrue); // dark ink on a light surface
  });
}
