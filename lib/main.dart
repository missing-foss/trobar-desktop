// SPDX-License-Identifier: GPL-3.0-or-later
// Trobar desktop — syncs library selections onto SD cards / local folders
// for network-less DAPs (gitea#2): pairing, server-driven diff sync,
// client-side MP3 transcoding, playlists, artist images.

import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/gen/app_localizations.dart';

import 'about_screen.dart';
import 'api_client.dart';
import 'card_store.dart';
import 'models.dart';
import 'sync_engine.dart';
import 'transcoder.dart';

// Brand palette — mirrors android/.../Theme.kt and brand/README.md.
const brandBurgundy = Color(0xFFA83250);
const brandRose = Color(0xFFD76A83);
const brandCream = Color(0xFFF9EFDF);
const brandCanvas = Color(0xFF100E08);

void main() {
  // The Linux release tarball bundles a static ffmpeg (GPL-3.0) — surface
  // its license in Flutter's own third-party page (gitea#71/#137).
  LicenseRegistry.addLicense(() async* {
    final text =
        await rootBundle.loadString('packaging/licenses/ffmpeg-GPL-3.0.txt');
    yield LicenseEntryWithLineBreaks(const ['ffmpeg (bundled static build)'], text);
  });
  runApp(const TrobarApp());
}

class TrobarApp extends StatelessWidget {
  const TrobarApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Trobar',
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: brandBurgundy,
            secondary: brandRose,
            brightness: Brightness.dark,
            surface: brandCanvas,
          ),
          scaffoldBackgroundColor: brandCanvas,
          useMaterial3: true,
        ),
        home: const HomeScreen(),
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
                  color: brandCream.withValues(alpha: .6)),
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
                              color: brandCream, fontWeight: FontWeight.w600)),
                  TextSpan(
                      text: 'ar',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(
                              color: brandRose, fontWeight: FontWeight.w600)),
                ])),
                const SizedBox(height: 24),
                if (_scanning)
                  const CircularProgressIndicator()
                else if (_cards.isEmpty)
                  Text(AppLocalizations.of(context).noCardDetected,
                      style: TextStyle(color: brandCream.withValues(alpha: .7)))
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
  late final ApiClient _api = ApiClient(widget.config);
  Transcoder? _transcoder;
  bool _transcoderChecked = false;

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
      final transcoder = _transcoderChecked
          ? _transcoder
          : await FfmpegTranscoder.locate();
      final info = await _api.getInfo();
      final space = await volumeSpace(widget.root);
      if (!mounted) return;
      setState(() {
        _transcoder = transcoder;
        _transcoderChecked = true;
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
    // Fresh device info per sync — the web UI can change the transcode
    // format or artist-image setting while this screen is open.
    try {
      final info = await _api.getInfo();
      if (mounted) setState(() => _info = info);
    } catch (_) {
      // keep the last known info; /changes still carries the format
    }
    final engine = SyncEngine(_api, widget.root,
        transcoder: _transcoder,
        transcodeFormat: _info?.transcodeFormat,
        artistImages: _info?.artistImages);
    try {
      var changes = await _api.getChanges();

      // gitea#49: ask about files missing on the card before syncing.
      final missing = await engine.findMissing(changes);
      if (missing.isNotEmpty && mounted) {
        final redownload = await _askMissing(missing.length);
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

      // gitea#2 M4: leftovers no track claims (e.g. old-extension files
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
    final more = orphans.length > 5 ? '\n… and ${orphans.length - 5} more' : '';
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${orphans.length} file(s) on this card are not managed '
            'by Trobar'),
        content: Text(
            'Usually leftovers from a format change — but files you copied '
            'here yourself also show up. Delete them?\n\n$preview$more'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete them')),
        ],
      ),
    );
  }

  /// true = re-download, false = leave deleted, null = cancel.
  Future<bool?> _askMissing(int count) => showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('$count track(s) missing on this card'),
          content: const Text(
              'The server expected these files to be here. Re-download them, '
              'or leave them deleted (they will not be re-queued)?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Leave deleted')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Re-download')),
          ],
        ),
      );

  String _fmtGB(int bytes) => (bytes / 1e9).toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final space = _space;
    final result = _lastResult;
    return Scaffold(
      appBar: AppBar(title: Text(_info?.name ?? widget.root.path)),
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
                    style: TextStyle(color: brandCream.withValues(alpha: .6))),
                if (_info?.transcodeFormat != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _transcoder != null
                        ? Text(
                            AppLocalizations.of(context).transcodeActive(
                                (_info!.transcodeFormat ?? '')
                                    .replaceFirst('mp3_', 'MP3 ')),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: brandCream.withValues(alpha: .6)))
                        : Text(AppLocalizations.of(context).transcodeNoFfmpeg,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                  ),
                const SizedBox(height: 16),
                if (space != null) ...[
                  LinearProgressIndicator(
                      value: (space.total - space.free) / space.total),
                  const SizedBox(height: 4),
                  Text(
                      '${_fmtGB(space.free)} GB free of ${_fmtGB(space.total)} GB',
                      style: Theme.of(context).textTheme.labelSmall),
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
                      'Synced: ${result.downloadedCount} downloaded, '
                      '${result.transcodedCount} transcoded, '
                      '${result.deletedCount} removed'
                      '${result.skippedTranscode > 0 ? ', ${result.skippedTranscode} skipped (no ffmpeg)' : ''}',
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
