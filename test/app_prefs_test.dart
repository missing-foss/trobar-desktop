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
  });

  test('save then load round-trips the values', () async {
    final prefs = await AppPrefs.load(file: prefsFile());
    prefs
      ..language = 'fr'
      ..missingPolicy = 'redownload';
    await prefs.save();

    final reloaded = await AppPrefs.load(file: prefsFile());
    expect(reloaded.language, 'fr');
    expect(reloaded.missingPolicy, 'redownload');
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
