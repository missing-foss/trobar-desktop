// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// desktop#45: GetDriveTypeW through dart:ffi, on a real Windows system.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trobar_desktop/card_store.dart';
import 'package:trobar_desktop/windows_volume.dart';

void main() {
  test(
    'the system drive is not removable, and nor is a folder on it',
    () {
      final system = '${Platform.environment['SystemDrive'] ?? 'C:'}\\';
      // 3 is DRIVE_FIXED.
      expect(windowsDriveType(system), 3);
      expect(isRemovable(Directory(system)), isFalse);
      expect(isRemovable(Directory.systemTemp), isFalse);
    },
    skip: Platform.isWindows ? false : 'GetDriveTypeW is Windows only',
  );
}
