// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// Trobar desktop — syncs library selections onto SD cards / local folders
// for network-less DAPs: pairing, server-driven diff sync, playlists,
// artist images. (Transcoding to MP3 is done server-side; the client just
// downloads whatever bytes the server serves.)

import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/gen/app_localizations.dart';

import 'about_screen.dart';
import 'api_client.dart';
import 'app_prefs.dart';
import 'card_store.dart';
import 'locale_notifier.dart';
import 'models.dart';
import 'settings_screen.dart';
import 'sync_engine.dart';

// Brand palette — mirrors android/.../Theme.kt and brand/README.md.
const brandBurgundy = Color(0xFFA83250);
const brandRose = Color(0xFFD76A83);
const brandCream = Color(0xFFF9EFDF);
const brandCanvas = Color(0xFF100E08);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load the app-wide language override before the first frame so the UI
  // opens in the chosen language (#17).
  final prefs = await AppPrefs.load();
  localeNotifier.value =
      prefs.language == 'system' ? null : Locale(prefs.language);
  runApp(const TrobarApp());
}

/// Brand-consistent ThemeData for a given brightness (#19). Dark keeps the
/// near-black brand canvas so dark mode is unchanged; light lets
/// ColorScheme.fromSeed pick a light surface. Both derive from the burgundy
/// seed, so the accent stays on-brand either way.
ThemeData _brandTheme(Brightness brightness) {
  final scheme = brightness == Brightness.dark
      ? ColorScheme.fromSeed(
          seedColor: brandBurgundy,
          secondary: brandRose,
          brightness: brightness,
          surface: brandCanvas,
        )
      : ColorScheme.fromSeed(
          seedColor: brandBurgundy,
          secondary: brandRose,
          brightness: brightness,
        );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    useMaterial3: true,
    // #22: Space Grotesk is the UI/body font everywhere (matches Android/web);
    // Fredoka is applied directly on the "Trobar" wordmark, not here.
    fontFamily: 'SpaceGrotesk',
  );
}

/// Primary "ink" for text/icons over the app canvas: the brand cream on the
/// dark theme (unchanged), the theme's onSurface on light — so the light
/// theme (#19) gets readable dark text instead of invisible cream.
Color brandInk(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? brandCream
        : Theme.of(context).colorScheme.onSurface;

class TrobarApp extends StatelessWidget {
  const TrobarApp({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Locale?>(
        valueListenable: localeNotifier,
        builder: (context, locale, _) => MaterialApp(
          title: 'Trobar',
          locale: locale, // null = follow the system locale (#17)
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: _brandTheme(Brightness.light),
          darkTheme: _brandTheme(Brightness.dark),
          themeMode: ThemeMode.system, // follow the OS light/dark setting (#19)
          home: const HomeScreen(),
        ),
      );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<(Directory, DeviceConfig)> _cards = [];
  bool _scanning = true;

  @override
  void initState() {
    super.initState();
    _rescan();
  }

  Future<void> _rescan() async {
    setState(() => _scanning = true);
    final cards = await discoverCards();
    if (!mounted) return;
    setState(() {
      _cards = cards;
      _scanning = false;
    });
  }

  Future<void> _openFolder() async {
    final path = await getDirectoryPath();
    if (path == null || !mounted) return;
    final root = Directory(path);
    final config = await readConfig(root);
    if (!mounted) return;
    if (config != null) {
      _openCard(root, config);
    } else {
      final saved = await Navigator.of(context).push<DeviceConfig>(
          MaterialPageRoute(builder: (_) => PairScreen(root: root)));
      if (saved != null && mounted) _openCard(root, saved);
    }
  }

  void _openCard(Directory root, DeviceConfig config) {
    Navigator.of(context)
        .push(MaterialPageRoute(
            builder: (_) => CardScreen(root: root, config: config)))
        .then((_) => _rescan());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Stack(children: [
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              tooltip: AppLocalizations.of(context).aboutTooltip,
              icon: Icon(Icons.info_outline,
                  color: brandInk(context).withValues(alpha: .6)),
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AboutScreen())),
            ),
          ),
          Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset('assets/logo_bard.png', width: 140),
                const SizedBox(height: 8),
                Text.rich(TextSpan(children: [
                  TextSpan(
                      text: 'Trob',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(
                              fontFamily: 'Fredoka', // #22: wordmark font
                              color: brandInk(context),
                              fontWeight: FontWeight.w600)),
                  TextSpan(
                      text: 'ar',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(
                              fontFamily: 'Fredoka', // #22: wordmark font
                              color: brandRose, fontWeight: FontWeight.w600)),
                ])),
                const SizedBox(height: 24),
                if (_scanning)
                  const CircularProgressIndicator()
                else if (_cards.isEmpty)
                  Text(AppLocalizations.of(context).noCardDetected,
                      style:
                          TextStyle(color: brandInk(context).withValues(alpha: .7)))
                else
                  ..._cards.map((c) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.sd_card),
                          title: Text(c.$1.path),
                          onTap: () => _openCard(c.$1, c.$2),
                        ),
                      )),
                const SizedBox(height: 24),
                Wrap(spacing: 12, children: [
                  OutlinedButton.icon(
                      onPressed: _rescan,
                      icon: const Icon(Icons.refresh),
                      label: Text(AppLocalizations.of(context).rescan)),
                  FilledButton.icon(
                      onPressed: _openFolder,
                      icon: const Icon(Icons.folder_open),
                      label: Text(AppLocalizations.of(context).openFolder)),
                ]),
              ],
            ),
          ),
          ),
        ]),
      );
}

class PairScreen extends StatefulWidget {
  final Directory root;
  const PairScreen({super.key, required this.root});

  @override
  State<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<PairScreen> {
  final _jsonController = TextEditingController();
  String? _error;

  DeviceConfig? _parse(String raw) {
    // ﻿: strip a UTF-8 BOM some editors/browsers prepend — jsonDecode
    // rejects it and the failure would be indistinguishable from a typo.
    final text = raw.replaceFirst('﻿', '').trim();
    try {
      final json = jsonDecode(text);
      if (json is! Map<String, dynamic> ||
          json['server_url'] is! String ||
          json['token'] is! String) {
        return null;
      }
      return DeviceConfig.fromJson(json);
    } on FormatException {
      return null;
    }
  }

  Future<void> _loadFile() async {
    final file = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: 'Device config', extensions: ['json'])
    ]);
    if (file == null) return;
    _jsonController.text = await file.readAsString();
    await _save();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final config = _parse(_jsonController.text);
    if (config == null) {
      setState(() => _error = l10n.pairInvalidConfig);
      return;
    }
    try {
      await writeConfig(widget.root, config);
    } on FileSystemException catch (e) {
      // The config was fine — the card wasn't. Say so explicitly.
      setState(() => _error = l10n.pairWriteFailed(
          widget.root.path, e.osError?.message ?? e.message));
      return;
    }
    if (mounted) Navigator.of(context).pop(config);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(AppLocalizations.of(context).pairTitle)),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(widget.root.path,
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 12),
                  Text(AppLocalizations.of(context).pairInstructions),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _jsonController,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: '{"server_url": "https://…", "token": "…"}',
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    ),
                  const SizedBox(height: 16),
                  Wrap(spacing: 12, children: [
                    OutlinedButton.icon(
                        onPressed: _loadFile,
                        icon: const Icon(Icons.file_open),
                        label: Text(AppLocalizations.of(context).loadConfigFile)),
                    FilledButton(
                        onPressed: _save,
                        child: Text(AppLocalizations.of(context).pairButton)),
                  ]),
                ],
              ),
            ),
          ),
        ),
      );
}

class CardScreen extends StatefulWidget {
  final Directory root;
  final DeviceConfig config;
  const CardScreen({super.key, required this.root, required this.config});

  @override
  State<CardScreen> createState() => _CardScreenState();
}

class _CardScreenState extends State<CardScreen> {
  // Mutable so the Settings screen can change the server URL: on change we
  // recreate the client against the new URL (token unchanged).
  late DeviceConfig _config = widget.config;
  late ApiClient _api = ApiClient(_config);

  DeviceInfo? _info;
  ({int free, int total})? _space;
  bool _syncing = false;
  SyncProgress? _progress;
  SyncResult? _lastResult;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final info = await _api.getInfo();
      final space = await volumeSpace(widget.root);
      if (!mounted) return;
      setState(() {
        _info = info;
        _space = space;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _sync() async {
    setState(() {
      _syncing = true;
      _error = null;
      _lastResult = null;
    });
    // Fresh device info per sync — the web UI can change the artist-image
    // setting while this screen is open.
    try {
      final info = await _api.getInfo();
      if (mounted) setState(() => _info = info);
    } catch (_) {
      // keep the last known info
    }
    final engine =
        SyncEngine(_api, widget.root, artistImages: _info?.artistImages);
    try {
      var changes = await _api.getChanges();

      // ask about files missing on the card before syncing — unless a
      // standing policy (#17) says to always re-download or always leave
      // them deleted, so unattended/repeat syncs don't prompt.
      final missing = await engine.findMissing(changes);
      if (missing.isNotEmpty && mounted) {
        final policy = AppPrefs.instance.missingPolicy;
        final bool? redownload = policy == 'redownload'
            ? true
            : policy == 'exclude'
                ? false
                : await _askMissing(missing.length);
        if (redownload == null) {
          setState(() => _syncing = false);
          return; // cancelled
        }
        await _api.resolveMissing(
          redownload: redownload ? [for (final t in missing) t.trackId] : [],
          exclude: redownload ? [] : [for (final t in missing) t.trackId],
        );
        changes = await _api.getChanges();
      }

      final result = await engine.run(changes,
          onProgress: (pr) => setState(() => _progress = pr));
      if (!mounted) return;
      setState(() => _lastResult = result);
      if (result.firstError != null) {
        setState(() => _error = result.firstError);
      }

      // leftovers no track claims (e.g. old-extension files
      // after a transcode-format change). Confirm-gated — the card may
      // hold files the user put there deliberately.
      final orphans = await engine.findOrphans(changes);
      if (orphans.isNotEmpty && mounted) {
        final delete = await _askOrphans(orphans);
        if (delete == true) {
          await engine.deleteOrphans(orphans);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) {
        setState(() {
          _syncing = false;
          _progress = null;
        });
        _load();
      }
    }
  }

  Future<bool?> _askOrphans(List<String> orphans) {
    final preview = orphans.take(5).join('\n');
    final more = orphans.length > 5
        ? '\n${AppLocalizations.of(context).orphansMore(orphans.length - 5)}'
        : '';
    return showDialog<bool>(
      context: context,
      builder: (context) {
        final l = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(l.orphansTitle(orphans.length)),
          content: Text(l.orphansBody('$preview$more')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l.keep)),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l.deleteThem)),
          ],
        );
      },
    );
  }

  /// true = re-download, false = leave deleted, null = cancel.
  Future<bool?> _askMissing(int count) => showDialog<bool>(
        context: context,
        builder: (context) {
          final l = AppLocalizations.of(context);
          return AlertDialog(
            title: Text(l.missingTitle(count)),
            content: Text(l.missingBody),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context), child: Text(l.cancel)),
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(l.leaveDeleted)),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(l.redownload)),
            ],
          );
        },
      );

  String _fmtGB(int bytes) => (bytes / 1e9).toStringAsFixed(1);

  Future<void> _openSettings() async {
    final newConfig = await Navigator.of(context).push<DeviceConfig>(
        MaterialPageRoute(
            builder: (_) => SettingsScreen(
                root: widget.root, config: _config, api: _api, info: _info)));
    if (!mounted || newConfig == null) return;
    if (newConfig.serverUrl != _config.serverUrl) {
      setState(() {
        _api.close();
        _config = newConfig;
        _api = ApiClient(_config);
      });
    }
    _load(); // pick up a storage-limit change (re-fetches device info)
  }

  @override
  Widget build(BuildContext context) {
    final space = _space;
    final result = _lastResult;
    return Scaffold(
      appBar: AppBar(
        title: Text(_info?.name ?? widget.root.path),
        actions: [
          IconButton(
            tooltip: AppLocalizations.of(context).settingsTooltip,
            icon: const Icon(Icons.settings_outlined),
            onPressed: _syncing ? null : _openSettings,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: Image.asset('assets/logo_bard.png', width: 96)),
                const SizedBox(height: 16),
                Text(widget.root.path,
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: brandInk(context).withValues(alpha: .6))),
                const SizedBox(height: 16),
                if (space != null) ...[
                  LinearProgressIndicator(
                      value: (space.total - space.free) / space.total),
                  const SizedBox(height: 4),
                  Text(
                      AppLocalizations.of(context)
                          .freeOfTotal(_fmtGB(space.free), _fmtGB(space.total)),
                      style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(height: 16),
                ],
                // #18: show the configured allocation and warn when it can't
                // physically fit on the card's free space.
                if (_info?.maxSizeBytes != null) ...[
                  Text(
                      AppLocalizations.of(context)
                          .storageAllocated(_fmtGB(_info!.maxSizeBytes!)),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall),
                  if (space != null && _info!.maxSizeBytes! > space.free)
                    Text(
                        AppLocalizations.of(context).storageLimitExceedsFree,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  const SizedBox(height: 16),
                ],
                if (_syncing && _progress != null)
                  Text(
                      '${_progress!.done}/${_progress!.total}  ${_progress!.currentPath}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall),
                if (result != null && !_syncing)
                  Text(
                      AppLocalizations.of(context).syncSummary(
                          result.downloadedCount, result.deletedCount),
                      textAlign: TextAlign.center),
                if (_error != null)
                  Row(children: [
                    Expanded(
                        child: Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error))),
                    IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () => setState(() => _error = null)),
                  ]),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _syncing ? null : _sync,
                  icon: _syncing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.sync),
                  label: Text(_syncing
                      ? AppLocalizations.of(context).syncing
                      : AppLocalizations.of(context).syncNow),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
