// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// App-wide (NOT per-card) preferences — the language override and the
// missing-file sync policy (#17). Persisted as a small JSON file in the OS
// config dir. Hand-rolled to match card_store's platform-path style and keep
// the app plugin-free (no shared_preferences/path_provider), and so it's
// trivially unit-testable with an injected file.

import 'brand_tokens.dart';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Language override: 'system' follows the OS locale; 'en'/'fr' force it.
const languageValues = ['system', 'en', 'fr'];

/// What to do about tracks the server expected but the card is missing:
/// 'ask' prompts every sync (the default); the others apply a standing choice
/// so repeat/unattended syncs don't nag.
const missingPolicyValues = ['ask', 'redownload', 'exclude'];

/// What to do about files on the card no track claims: 'ask' after every
/// manual sync (the default), or 'keep' them without asking, for a card that
/// holds music copied there by hand.
const orphanPolicyValues = ['ask', 'keep'];

/// In-app auto-sync interval while a card is open, in minutes (#23). 0 = off.
/// Desktop has no background daemon, so this only ticks while the app is open.
const autoSyncIntervalValues = [0, 15, 30, 60, 360];

class AppPrefs {
  String language;

  /// The brand theme's key (BrandTheme.key): troubadour unless chosen.
  String brandTheme;
  String missingPolicy;
  String orphanPolicy;

  /// #23: when the app is open and a paired card appears, sync it unprompted.
  bool autoSyncOnDetect;

  /// #23: re-sync every N minutes while a card is open (0 = off).
  int autoSyncIntervalMinutes;

  /// #66: manually-picked local folders (not under a removable-volume mount
  /// root), so they're rediscovered on the next launch instead of having to
  /// be re-picked by hand every time. Just a "look here" hint, same category
  /// as a recent-locations list — the actual pairing still lives in
  /// .trobar/device.json on the folder itself. A path that no longer exists
  /// or no longer carries a config is dropped at discovery time, not here.
  List<String> localFolders;

  /// Syncs this install has finished with no error, for the one-time
  /// thank-you card on Home (shown from [thanksCardSyncs] on).
  int syncsCompleted;

  /// Either of the thank-you card's buttons was pressed: it never shows
  /// again on this install.
  bool thanksCardDone;

  final File _file;

  AppPrefs._(this._file, {
    required this.language,
    required this.brandTheme,
    required this.missingPolicy,
    required this.orphanPolicy,
    required this.autoSyncOnDetect,
    required this.autoSyncIntervalMinutes,
    required this.localFolders,
    required this.syncsCompleted,
    required this.thanksCardDone,
  });

  static AppPrefs? _instance;

  /// The process-wide instance. [load] must have run first (in main()).
  static AppPrefs get instance => _instance!;

  /// Read prefs from [file] (defaults to the OS config path), falling back to
  /// defaults for a missing or corrupt file. Sets the singleton.
  static Future<AppPrefs> load({File? file}) async {
    final f = file ?? await _defaultFile();
    var language = 'system';
    var brandTheme = BrandTheme.fallback.key;
    var missingPolicy = 'ask';
    var orphanPolicy = 'ask';
    var autoSyncOnDetect = false;
    var autoSyncIntervalMinutes = 0;
    var localFolders = <String>[];
    var syncsCompleted = 0;
    var thanksCardDone = false;
    try {
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        language = _oneOf(j['language'], languageValues, language);
        brandTheme = _oneOf(j['brand_theme'],
            [for (final t in BrandTheme.values) t.key], brandTheme);
        missingPolicy =
            _oneOf(j['missing_policy'], missingPolicyValues, missingPolicy);
        orphanPolicy =
            _oneOf(j['orphan_policy'], orphanPolicyValues, orphanPolicy);
        autoSyncOnDetect = j['auto_sync_on_detect'] == true;
        autoSyncIntervalMinutes = _oneOfInt(
            j['auto_sync_interval_minutes'], autoSyncIntervalValues, 0);
        final rawFolders = j['local_folders'];
        if (rawFolders is List) {
          localFolders = rawFolders.whereType<String>().toList();
        }
        final rawSyncs = j['syncs_completed'];
        if (rawSyncs is int && rawSyncs >= 0) syncsCompleted = rawSyncs;
        thanksCardDone = j['thanks_card_done'] == true;
      }
    } catch (_) {
      // corrupt / unreadable — use defaults
    }
    return _instance = AppPrefs._(f,
        language: language,
        brandTheme: brandTheme,
        missingPolicy: missingPolicy,
        orphanPolicy: orphanPolicy,
        autoSyncOnDetect: autoSyncOnDetect,
        autoSyncIntervalMinutes: autoSyncIntervalMinutes,
        localFolders: localFolders,
        syncsCompleted: syncsCompleted,
        thanksCardDone: thanksCardDone);
  }

  Future<void> save() async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(
        '${jsonEncode({
          'language': language,
          'brand_theme': brandTheme,
          'missing_policy': missingPolicy,
          'orphan_policy': orphanPolicy,
          'auto_sync_on_detect': autoSyncOnDetect,
          'auto_sync_interval_minutes': autoSyncIntervalMinutes,
          'local_folders': localFolders,
          'syncs_completed': syncsCompleted,
          'thanks_card_done': thanksCardDone,
        })}\n',
        flush: true);
  }

  /// Remembers [path] for next launch (#66) — a no-op if it's already there.
  Future<void> addLocalFolder(String path) async {
    if (localFolders.contains(path)) return;
    localFolders = [...localFolders, path];
    await save();
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
