// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// App-wide (NOT per-card) preferences — the language override and the
// missing-file sync policy (#17). Persisted as a small JSON file in the OS
// config dir. Hand-rolled to match card_store's platform-path style and keep
// the app plugin-free (no shared_preferences/path_provider), and so it's
// trivially unit-testable with an injected file.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Language override: 'system' follows the OS locale; 'en'/'fr' force it.
const languageValues = ['system', 'en', 'fr'];

/// What to do about tracks the server expected but the card is missing:
/// 'ask' prompts every sync (the default); the others apply a standing choice
/// so repeat/unattended syncs don't nag.
const missingPolicyValues = ['ask', 'redownload', 'exclude'];

/// In-app auto-sync interval while a card is open, in minutes (#23). 0 = off.
/// Desktop has no background daemon, so this only ticks while the app is open.
const autoSyncIntervalValues = [0, 15, 30, 60, 360];

class AppPrefs {
  String language;
  String missingPolicy;

  /// #23: when the app is open and a paired card appears, sync it unprompted.
  bool autoSyncOnDetect;

  /// #23: re-sync every N minutes while a card is open (0 = off).
  int autoSyncIntervalMinutes;

  final File _file;

  AppPrefs._(this._file, {
    required this.language,
    required this.missingPolicy,
    required this.autoSyncOnDetect,
    required this.autoSyncIntervalMinutes,
  });

  static AppPrefs? _instance;

  /// The process-wide instance. [load] must have run first (in main()).
  static AppPrefs get instance => _instance!;

  /// Read prefs from [file] (defaults to the OS config path), falling back to
  /// defaults for a missing or corrupt file. Sets the singleton.
  static Future<AppPrefs> load({File? file}) async {
    final f = file ?? await _defaultFile();
    var language = 'system';
    var missingPolicy = 'ask';
    var autoSyncOnDetect = false;
    var autoSyncIntervalMinutes = 0;
    try {
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        language = _oneOf(j['language'], languageValues, language);
        missingPolicy =
            _oneOf(j['missing_policy'], missingPolicyValues, missingPolicy);
        autoSyncOnDetect = j['auto_sync_on_detect'] == true;
        autoSyncIntervalMinutes = _oneOfInt(
            j['auto_sync_interval_minutes'], autoSyncIntervalValues, 0);
      }
    } catch (_) {
      // corrupt / unreadable — use defaults
    }
    return _instance = AppPrefs._(f,
        language: language,
        missingPolicy: missingPolicy,
        autoSyncOnDetect: autoSyncOnDetect,
        autoSyncIntervalMinutes: autoSyncIntervalMinutes);
  }

  Future<void> save() async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(
        '${jsonEncode({
          'language': language,
          'missing_policy': missingPolicy,
          'auto_sync_on_detect': autoSyncOnDetect,
          'auto_sync_interval_minutes': autoSyncIntervalMinutes,
        })}\n',
        flush: true);
  }

  static String _oneOf(Object? v, List<String> allowed, String fallback) =>
      (v is String && allowed.contains(v)) ? v : fallback;

  static int _oneOfInt(Object? v, List<int> allowed, int fallback) =>
      (v is int && allowed.contains(v)) ? v : fallback;

  static Future<File> _defaultFile() async =>
      File(p.join(_configDir().path, 'trobar-desktop', 'prefs.json'));

  static Directory _configDir() {
    final env = Platform.environment;
    if (Platform.isWindows) {
      return Directory(env['APPDATA'] ??
          p.join(env['USERPROFILE'] ?? '.', 'AppData', 'Roaming'));
    }
    if (Platform.isMacOS) {
      return Directory(
          p.join(env['HOME'] ?? '.', 'Library', 'Application Support'));
    }
    final xdg = env['XDG_CONFIG_HOME'];
    if (xdg != null && xdg.isNotEmpty) return Directory(xdg);
    return Directory(p.join(env['HOME'] ?? '.', '.config'));
  }
}
