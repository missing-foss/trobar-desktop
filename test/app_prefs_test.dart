// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// #17: the hand-rolled app-wide prefs store — defaults, round-trip, and
// robustness against a corrupt / out-of-range file.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:trobar_desktop/app_prefs.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('trobar-prefs-');
  });
  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  File prefsFile() => File(p.join(tmp.path, 'prefs.json'));

  test('defaults when no file exists', () async {
    final prefs = await AppPrefs.load(file: prefsFile());
    expect(prefs.language, 'system');
    expect(prefs.missingPolicy, 'ask');
    // #23: auto-sync is opt-in / off by default.
    expect(prefs.autoSyncOnDetect, isFalse);
    expect(prefs.autoSyncIntervalMinutes, 0);
  });

  test('save then load round-trips the values', () async {
    final prefs = await AppPrefs.load(file: prefsFile());
    prefs
      ..language = 'fr'
      ..missingPolicy = 'redownload'
      ..autoSyncOnDetect = true
      ..autoSyncIntervalMinutes = 60;
    await prefs.save();

    final reloaded = await AppPrefs.load(file: prefsFile());
    expect(reloaded.language, 'fr');
    expect(reloaded.missingPolicy, 'redownload');
    expect(reloaded.autoSyncOnDetect, isTrue);
    expect(reloaded.autoSyncIntervalMinutes, 60);
  });

  test('an out-of-range auto-sync interval falls back to off (#23)', () async {
    await prefsFile().writeAsString(
        '{"auto_sync_on_detect":"yes","auto_sync_interval_minutes":7}');
    final prefs = await AppPrefs.load(file: prefsFile());
    // non-bool -> false; 7 isn't an allowed step -> 0.
    expect(prefs.autoSyncOnDetect, isFalse);
    expect(prefs.autoSyncIntervalMinutes, 0);
  });

  test('save creates the parent directory', () async {
    final nested = File(p.join(tmp.path, 'trobar-desktop', 'prefs.json'));
    final prefs = await AppPrefs.load(file: nested);
    prefs.language = 'en';
    await prefs.save();
    expect(nested.existsSync(), isTrue);
  });

  test('a corrupt file falls back to defaults', () async {
    await prefsFile().writeAsString('{ this is not json');
    final prefs = await AppPrefs.load(file: prefsFile());
    expect(prefs.language, 'system');
    expect(prefs.missingPolicy, 'ask');
  });

  test('out-of-range values fall back to defaults', () async {
    await prefsFile()
        .writeAsString('{"language":"de","missing_policy":"nuke"}');
    final prefs = await AppPrefs.load(file: prefsFile());
    expect(prefs.language, 'system');
    expect(prefs.missingPolicy, 'ask');
  });

  test('load sets the process-wide singleton', () async {
    await prefsFile()
        .writeAsString('{"language":"en","missing_policy":"exclude"}');
    await AppPrefs.load(file: prefsFile());
    expect(AppPrefs.instance.language, 'en');
    expect(AppPrefs.instance.missingPolicy, 'exclude');
  });
}
