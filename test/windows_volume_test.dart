// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:trobar_desktop/windows_volume.dart';

void main() {
  group('utf16z', () {
    test('a drive root ends in one NUL', () {
      expect(utf16z(r'E:\'), [0x45, 0x3A, 0x5C, 0]);
    });

    test('a character outside the BMP is a surrogate pair', () {
      expect(utf16z('M:\\\u{1F3B5}'), [0x4D, 0x3A, 0x5C, 0xD83C, 0xDFB5, 0]);
    });

    test('an empty path is just the terminator', () {
      expect(utf16z(''), [0]);
    });
  });
}
