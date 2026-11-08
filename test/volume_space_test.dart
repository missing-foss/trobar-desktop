// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// The card's space comes from df on Linux and macOS and from kernel32 on
// Windows; each platform must take its own path, since the other's fails
// quietly into "no space shown".

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trobar_desktop/card_store.dart';

void main() {
  test('volumeSpace reads a real volume here', () async {
    final space = await volumeSpace(Directory.systemTemp);
    expect(space, isNotNull);
    expect(space!.free, greaterThan(0));
    expect(space.total, greaterThanOrEqualTo(space.free));
  }, skip: Platform.isWindows ? 'df is the Linux and macOS path' : false);

  test('main() sets the Windows error mode only on Windows', () {
    // Nothing runs main() in tests, and kernel32 doesn't exist elsewhere.
    final source = File('lib/main.dart').readAsStringSync();
    expect('if (Platform.isWindows) suppressDriveErrorDialogs();'.allMatches(source).length, 1);
    expect('suppressDriveErrorDialogs()'.allMatches(source).length, 1);
  });
}
