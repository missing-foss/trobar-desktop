// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// Trobar desktop — syncs library selections onto SD cards / local folders
// for network-less DAPs: pairing, server-driven diff sync, playlists,
// artist images. (Transcoding to MP3 is done server-side; the client just
// downloads whatever bytes the server serves.)

import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show LicenseRegistry, LicenseEntryWithLineBreaks;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:local_notifier/local_notifier.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import 'l10n/gen/app_localizations.dart';

import 'about_screen.dart';
import 'api_client.dart';
import 'app_prefs.dart';
import 'brand_notifier.dart';
import 'brand_tokens.dart';
import 'card_store.dart';
import 'enrollment.dart';
import 'locale_notifier.dart';
import 'models.dart';
import 'notify.dart';
import 'orphans_dialog.dart';
import 'provenance.dart';
import 'settings_screen.dart';
import 'sync_engine.dart';
import 'formats.dart';
import 'sync_messages.dart';
import 'syncing_logo.dart';
import 'thanks_card.dart';
import 'volume_events.dart';
import 'windows_volume.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The card scan touches every drive letter, empty card readers included.
  if (Platform.isWindows) suppressDriveErrorDialogs();
  // So the About screen's "Third-party" licence viewer (Flutter's own
  // showLicensePage) lists this app's own GPL text alongside every bundled
  // package's, instead of a second, hand-rolled dialog for just this one.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
        const ['Trobar desktop'], await rootBundle.loadString('LICENSE'));
  });
  // #24: window focus queries + local notifications. Local only, no telemetry.
  await windowManager.ensureInitialized();
  // requireCreate (the default, made explicit): on Windows a toast needs an
  // AppUserModelID, which local_notifier supplies by creating a Start-menu
  // shortcut here — so toasts show from the packaged build. No-op on Linux;
  // macOS delivers via NSUserNotification. See packaging/PLATFORM-NOTES.md (#49).
  await localNotifier.setup(
      appName: 'Trobar', shortcutPolicy: ShortcutPolicy.requireCreate);
  // Load the app-wide language override before the first frame so the UI
  // opens in the chosen language (#17).
  final prefs = await AppPrefs.load();
  localeNotifier.value =
      prefs.language == 'system' ? null : Locale(prefs.language);
  brandNotifier.value = BrandTheme.of(prefs.brandTheme);
  runApp(const TrobarApp());
}

/// ThemeData for [brand] in [brightness]: its derived ColorScheme
/// (brand_tokens.dart, generated from brand/trobar-themes.json), its page
/// background, and the brand roles for the mark and wordmark.
ThemeData brandThemeData(BrandTheme brand, Brightness brightness) {
  final scheme = brandColorScheme(brand, brightness);
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: brandBackground(brand, brightness),
    useMaterial3: true,
    // #22: Space Grotesk is the UI/body font everywhere (matches Android/web);
    // Fredoka is applied directly on the "Trobar" wordmark, not here.
    fontFamily: 'SpaceGrotesk',
    extensions: [TrobarBrand(brand)],
  );
}

/// Primary "ink" for text/icons over the app canvas: the theme's onSurface,
/// which follows the brand theme and light/dark.
Color brandInk(BuildContext context) => Theme.of(context).colorScheme.onSurface;

class TrobarApp extends StatelessWidget {
  const TrobarApp({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<BrandTheme>(
        valueListenable: brandNotifier,
        builder: (context, brand, _) => ValueListenableBuilder<Locale?>(
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
            theme: brandThemeData(brand, Brightness.light),
            darkTheme: brandThemeData(brand, Brightness.dark),
            // Follow the OS light/dark setting (#19), except for the dark-only
            // brand themes (Nuèch, Contraste).
            themeMode: brand.darkOnly ? ThemeMode.dark : ThemeMode.system,
            home: const HomeScreen(volumeEvents: platformVolumeEvents),
          ),
        ),
      );
}

class HomeScreen extends StatefulWidget {
  /// Finds the paired cards and folders; tests pass a fake instead of the
  /// machine's real drives.
  final Future<List<(Directory, DeviceConfig)>> Function()? discover;

  /// Opens a link in the browser; tests pass a recorder instead.
  final void Function(Uri url)? openUrl;

  /// Volume arrivals and removals from the OS; without them (null, or a
  /// source that gives none, errors or ends) Home polls every
  /// [fallbackPoll] as before.
  final Stream<VolumeEvent>? Function()? volumeEvents;

  /// Finds the paired cards among [roots] only, after an arrival; tests
  /// pass a fake instead of the machine's real drives.
  final Future<List<(Directory, DeviceConfig)>> Function(List<Directory> roots)?
      discoverRoots;

  const HomeScreen(
      {super.key, this.discover, this.openUrl, this.volumeEvents, this.discoverRoots});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// The poll when the OS gives no volume events.
const fallbackPoll = Duration(seconds: 8);

/// How long after an arrival whose drive couldn't be read yet to look again.
const arrivalRetry = Duration(seconds: 2);

/// The safety poll beside volume events: a missed one (sleep and resume, a
/// broadcast before the window existed, a watch that died) is caught here.
const safetyPoll = Duration(seconds: 60);

class _HomeScreenState extends State<HomeScreen> {
  List<(Directory, DeviceConfig)> _cards = [];
  bool _scanning = true;
  // #23: card roots already seen, so auto-sync fires only for a card that
  // *appears* while the app is open (an insert), not ones present at launch.
  Set<String> _seenRoots = {};
  Timer? _poll;
  StreamSubscription<VolumeEvent>? _volumeSub;
  // #66: TargetKind per card path (drives the home-screen icon), probed once
  // and cached rather than on every rescan — a removable probe shells out to
  // platform tooling, and the auto-scan poll runs every 8s.
  final Map<String, TargetKind> _kinds = {};

  @override
  void initState() {
    super.initState();
    _rescan();
    // Keep the list live, and let a freshly-inserted card sync itself when
    // auto-sync-on-detect is on (#23): from the OS's volume events where
    // there are any, with a slow safety poll; otherwise from a poll.
    Stream<VolumeEvent>? events;
    try {
      events = widget.volumeEvents?.call();
    } catch (_) {
      events = null;
    }
    if (events == null) {
      _startPoll(fallbackPoll);
      return;
    }
    _startPoll(safetyPoll);
    _volumeSub = events.listen(_onVolumeEvent,
        onError: (Object _) => _fallBackToPolling(),
        onDone: _fallBackToPolling);
  }

  void _startPoll(Duration every) {
    _poll?.cancel();
    _poll = Timer.periodic(every, (_) => _autoScan());
  }

  void _fallBackToPolling() {
    _volumeSub?.cancel();
    _volumeSub = null;
    if (mounted) _startPoll(fallbackPoll);
  }

  /// A volume arrived or went. On Windows only the roots named are probed
  /// (an arrival) or dropped without any probe (a removal); a rescan event
  /// (macOS, Linux) scans as the poll does.
  Future<void> _onVolumeEvent(VolumeEvent event) async {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    final roots = event.roots;
    if (roots == null) return _autoScan();
    bool under(Directory dir) => roots.any(
        (r) => dir.path.toLowerCase().startsWith(r.path.toLowerCase()));
    // Built from the list as it is when applied, not when the event came:
    // two arrivals close together must not each start from the same list
    // and drop the other's card.
    List<(Directory, DeviceConfig)> kept() =>
        [for (final c in _cards) if (!under(c.$1)) c];
    if (!event.arrived) {
      await _applyFresh(kept);
      return;
    }
    final probe = widget.discoverRoots ?? (r) => discoverCards(only: r);
    var found = await probe(roots);
    if (found.isEmpty) {
      // Windows can announce a volume a moment before it can be read: one
      // more look at the same drives, still without touching any other.
      await Future<void>.delayed(arrivalRetry);
      if (!mounted) return;
      found = await probe(roots);
    }
    if (!mounted) return;
    await _applyFresh(() => [...kept(), ...found]);
  }

  /// [_apply] with a list [build] makes from the current one: built once to
  /// probe the new cards' kinds, then again just before it is shown, with no
  /// await in between, so an event applied meanwhile isn't lost.
  Future<void> _applyFresh(List<(Directory, DeviceConfig)> Function() build) async {
    await _refreshKinds(build());
    if (!mounted) return;
    await _apply(build(), kindsDone: true);
  }

  @override
  void dispose() {
    _poll?.cancel();
    _volumeSub?.cancel();
    super.dispose();
  }

  /// #66: removable-volume scan (unchanged) plus any manually-picked local
  /// folders remembered in AppPrefs — a path that no longer exists or lost
  /// its pairing file just isn't in the result, no error surfaced here.
  Future<List<(Directory, DeviceConfig)>> _discoverAll() async {
    if (widget.discover != null) return widget.discover!();
    final removable = await discoverCards();
    final local =
        await discoverLocalFolders(AppPrefs.instance.localFolders);
    return [...removable, ...local];
  }

  /// Probes only paths not already cached (see `_kinds`' own doc comment).
  /// Also drops cached entries for paths no longer present — #66 review: a
  /// removable volume unmounted and a *different* one later mounted at the
  /// same path (e.g. the same `/media/$USER/USB` reused) would otherwise
  /// keep showing the old kind until the app restarts.
  Future<void> _refreshKinds(List<(Directory, DeviceConfig)> cards) async {
    final present = {for (final c in cards) c.$1.path};
    _kinds.removeWhere((path, _) => !present.contains(path));
    for (final c in cards) {
      final path = c.$1.path;
      if (_kinds.containsKey(path)) continue;
      _kinds[path] = isRemovable(c.$1)
          ? await probeRemovableKind(c.$1)
          : TargetKind.local;
    }
  }

  /// The scan in progress, if any. The 8 s poll and a rescan (on launch,
  /// after a pairing, from the button) would otherwise run side by side,
  /// probing the same volumes twice and landing in either order; the later
  /// caller waits for the scan already running instead.
  Future<List<(Directory, DeviceConfig)>>? _scanInFlight;

  Future<List<(Directory, DeviceConfig)>> _scan() =>
      _scanInFlight ??= () async {
        try {
          final cards = await _discoverAll();
          await _refreshKinds(cards);
          return cards;
        } finally {
          _scanInFlight = null;
        }
      }();

  Future<void> _rescan() async {
    setState(() => _scanning = true);
    final cards = await _scan();
    if (!mounted) return;
    setState(() {
      _cards = cards;
      _seenRoots = {for (final c in cards) c.$1.path};
      _scanning = false;
    });
  }

  /// Background poll (#23): refresh the card list and, if a *new* card appeared
  /// and auto-sync-on-detect is on, open + sync it. No-op while a card/settings
  /// screen is on top (so it never scans or navigates under another route).
  Future<void> _autoScan() async {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    final cards = await _scan();
    if (!mounted) return;
    await _apply(cards, kindsDone: true);
  }

  /// A new card list, from a scan or an event: shown, and a card that just
  /// appeared is opened and synced when auto-sync-on-detect is on.
  Future<void> _apply(List<(Directory, DeviceConfig)> cards,
      {bool kindsDone = false}) async {
    if (!kindsDone) await _refreshKinds(cards);
    if (!mounted) return;
    final roots = {for (final c in cards) c.$1.path};
    final appeared = roots.difference(_seenRoots);
    setState(() {
      _cards = cards;
      _seenRoots = roots;
      _scanning = false;
    });
    if (AppPrefs.instance.autoSyncOnDetect && appeared.isNotEmpty) {
      // #42: if several cards appear in the same tick we auto-open+sync only
      // the first — you can only push one CardScreen at a time. Any others are
      // now in `_seenRoots`, so they stay in the list for manual open rather
      // than auto-syncing (an intentional limitation, not a queue).
      final root = appeared.first;
      final card = cards.firstWhere((c) => c.$1.path == root);
      _openCard(card.$1, card.$2, autoSync: true);
    }
  }

  /// #66: remembers a manually-picked *local* (non-removable) folder so it's
  /// rediscovered on the next launch — a removable one is always found fresh
  /// by discoverCards(), so there's nothing to persist for those.
  Future<void> _rememberIfLocal(Directory root) async {
    if (!isRemovable(root)) {
      await AppPrefs.instance.addLocalFolder(root.path);
    }
  }

  Future<void> _openFolder() async {
    final path = await getDirectoryPath();
    if (path == null || !mounted) return;
    final root = Directory(path);
    final config = await readConfig(root);
    if (!mounted) return;
    if (config != null) {
      await _rememberIfLocal(root);
      if (mounted) _openCard(root, config);
    } else {
      final saved = await Navigator.of(context).push<DeviceConfig>(
          MaterialPageRoute(builder: (_) => PairScreen(root: root)));
      if (saved != null && mounted) {
        await _rememberIfLocal(root);
        if (mounted) _openCard(root, saved);
      }
    }
  }

  /// #66: local → this machine's own OS icon (always correct, free); SD/USB
  /// → the specific glyph once the probe is conclusive; anything else
  /// (probe inconclusive, or not yet probed) → the generic removable-media
  /// icon this screen always showed before this feature existed.
  IconData _iconFor(String path) {
    switch (_kinds[path]) {
      case TargetKind.local:
        if (Platform.isWindows) return Icons.desktop_windows;
        if (Platform.isMacOS) return Icons.laptop_mac;
        return Icons.computer;
      case TargetKind.removableUsb:
        return Icons.usb;
      case TargetKind.removableSd:
        return Icons.sd_card;
      case TargetKind.removableUnknown:
      case null:
        // #66 review: this must stay visually distinct from removableSd
        // above — sharing Icons.sd_card here would bias "couldn't tell"
        // toward "it's an SD card", and would make the mmc/ID_DRIVE_FLASH_SD
        // detection in probeRemovableKind invisible (confirmed-SD and
        // gave-up would render identically).
        return Icons.storage;
    }
  }

  // Either of the thank-you card's buttons: it never shows again here.
  Future<void> _thanksDone() async {
    AppPrefs.instance.thanksCardDone = true;
    setState(() {});
    try {
      await AppPrefs.instance.save();
    } catch (_) {
      // shown again after a restart, which beats failing the tap
    }
  }

  void _openKofi() {
    final url = Uri.parse('https://ko-fi.com/missingfoss');
    final open = widget.openUrl;
    if (open != null) {
      open(url);
    } else {
      launchUrl(url);
    }
  }

  void _openCard(Directory root, DeviceConfig config, {bool autoSync = false}) {
    Navigator.of(context)
        .push(MaterialPageRoute(
            builder: (_) =>
                CardScreen(root: root, config: config, autoSync: autoSync)))
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
                const TrobarMark(size: 140),
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
                              color: Theme.of(context).colorScheme.secondary,
                              fontWeight: FontWeight.w600)),
                ])),
                const SizedBox(height: 24),
                if (showThanksCard(AppPrefs.instance)) ...[
                  ThanksCard(onDone: _thanksDone, onSupport: _openKofi),
                  const SizedBox(height: 24),
                ],
                if (_scanning)
                  const CircularProgressIndicator()
                else if (_cards.isEmpty)
                  Text(AppLocalizations.of(context).noCardDetected,
                      style:
                          TextStyle(color: brandInk(context).withValues(alpha: .7)))
                else
                  ..._cards.map((c) => Card(
                        child: ListTile(
                          leading: Icon(_iconFor(c.$1.path)),
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

  /// The HTTP client the code is redeemed with; tests pass a fake.
  final http.Client? client;
  const PairScreen({super.key, required this.root, this.client});

  @override
  State<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<PairScreen> {
  final _serverController = TextEditingController();
  final _codeController = TextEditingController();
  // A new device is named after the card's folder unless the user says
  // otherwise; a re-pair code ignores it and keeps the server's name.
  late final _nameController =
      TextEditingController(text: p.basename(widget.root.path));
  final _jsonController = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _serverController.dispose();
    _codeController.dispose();
    _nameController.dispose();
    _jsonController.dispose();
    super.dispose();
  }

  Future<void> _loadFile() async {
    final file = await openFile(acceptedTypeGroups: const [
      XTypeGroup(label: 'Device config', extensions: ['json'])
    ]);
    if (file == null) return;
    _jsonController.text = await file.readAsString();
    await _pairWithConfig();
  }

  /// The pasted or loaded text: a device config is written as it is; an
  /// enrollment payload (what the web app's QR code holds) is redeemed
  /// like a typed code.
  Future<void> _pairWithConfig() async {
    final l10n = AppLocalizations.of(context);
    final input = parsePairingInput(_jsonController.text);
    switch (input) {
      case null:
        setState(() => _error = l10n.pairInvalidConfig);
      case TokenInput(:final config):
        await _write(config);
      case EnrollInput(:final serverUrl, :final code):
        if (!isUsableServerUrl(serverUrl)) {
          setState(() => _error = l10n.pairBadServerUrl);
        } else {
          await _redeem(serverUrl, code);
        }
    }
  }

  Future<void> _pairWithCode() async {
    final l10n = AppLocalizations.of(context);
    final server = _serverController.text.trim();
    final code = normalizeEnrollCode(_codeController.text);
    if (server.isEmpty) {
      setState(() => _error = l10n.pairMissingServer);
    } else if (!isUsableServerUrl(server)) {
      setState(() => _error = l10n.pairBadServerUrl);
    } else if (code == null) {
      setState(() => _error = l10n.pairInvalidCode);
    } else {
      await _redeem(server, code);
    }
  }

  Future<void> _redeem(String serverUrl, String code) async {
    final l10n = AppLocalizations.of(context);
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = l10n.pairMissingName);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final (config, result) = await pairWithCode(widget.root,
          serverUrl: serverUrl,
          code: code,
          name: name,
          language: Localizations.localeOf(context).languageCode,
          client: widget.client);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.pairedAs(result.name))));
      Navigator.of(context).pop(config);
    } on EnrollException catch (e) {
      setState(() => _error = switch (e.kind) {
            EnrollFailure.invalidCode => l10n.pairCodeRejected,
            EnrollFailure.rateLimited => l10n.pairRateLimited,
            EnrollFailure.network => l10n.pairNetworkError(e.toString()),
            EnrollFailure.other => l10n.pairFailed(e.toString()),
          });
    } on FileSystemException catch (e) {
      // The code was redeemed, but the card couldn't be written: the
      // server now has a device this card doesn't know about. Say so; a
      // fresh code pairs it.
      setState(() => _error = l10n.pairWriteFailed(
          widget.root.path, e.osError?.message ?? e.message));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _write(DeviceConfig config) async {
    final l10n = AppLocalizations.of(context);
    try {
      await writeConfig(widget.root, config);
      // #84: recorded here, at pairing, rather than passed as an in-memory
      // flag to CardScreen — see manifestPendingFileName's own doc for why
      // persisting it on the card matters (survives a network failure and
      // a machine switch, checked on every open rather than only this one).
      await markManifestPending(widget.root);
    } on FileSystemException catch (e) {
      // The config was fine — the card wasn't. Say so explicitly.
      setState(() => _error = l10n.pairWriteFailed(
          widget.root.path, e.osError?.message ?? e.message));
      return;
    }
    if (mounted) Navigator.of(context).pop(config);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.pairTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.root.path,
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 12),
                Text(l10n.pairInstructions),
                const SizedBox(height: 12),
                TextField(
                  controller: _serverController,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: l10n.pairServerUrlLabel,
                    hintText: 'https://…',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  onSubmitted: (_) => _busy ? null : _pairWithCode(),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: l10n.pairCodeLabel,
                    hintText: 'ABCD2345',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: l10n.pairNameLabel,
                    helperText: l10n.pairNameHelp,
                    helperMaxLines: 2,
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
                FilledButton(
                    onPressed: _busy ? null : _pairWithCode,
                    child: Text(l10n.pairButton)),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 12),
                Text(l10n.pairConfigHeading,
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 12),
                TextField(
                  controller: _jsonController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '{"server_url": "https://…", "token": "…"}',
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(spacing: 12, children: [
                  OutlinedButton.icon(
                      onPressed: _busy ? null : _loadFile,
                      icon: const Icon(Icons.file_open),
                      label: Text(l10n.loadConfigFile)),
                  OutlinedButton(
                      onPressed: _busy ? null : _pairWithConfig,
                      child: Text(l10n.pairConfigButton)),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CardScreen extends StatefulWidget {
  final Directory root;
  final DeviceConfig config;

  /// #23: sync once, unprompted, right after opening (set when the card was
  /// auto-opened on detection).
  final bool autoSync;

  /// The HTTP client the card's API calls use; tests pass a fake.
  final http.Client? client;

  /// How a link opens: the browser (url_launcher) by default. A test passes
  /// its own to see where it would go.
  final void Function(Uri url)? openUrl;

  const CardScreen({
    super.key,
    required this.root,
    required this.config,
    this.autoSync = false,
    this.client,
    this.openUrl,
  });

  @override
  State<CardScreen> createState() => _CardScreenState();
}

class _CardScreenState extends State<CardScreen> {
  // Mutable so the Settings screen can change the server URL: on change we
  // recreate the client against the new URL (token unchanged).
  late DeviceConfig _config = widget.config;
  late ApiClient _api = ApiClient(_config, httpClient: widget.client);

  DeviceInfo? _info;
  ({int free, int total})? _space;
  bool _syncing = false;
  SyncProgress? _progress;
  // Last sync's outcome, persisted on the card (#20) — survives reopen/offline.
  SyncOutcome? _outcome;
  // Tracks an unattended sync found missing and, with policy "ask", left
  // undecided: said in a banner until a manual sync decides. 0: none.
  int _missingUndecided = 0;
  // Transient, in-session only: a failure to reach the server *now* (e.g. the
  // initial device-info load). Distinct from a persisted sync error.
  String? _error;
  // The server refused this card's token: offer to pair it again.
  bool _revoked = false;
  // Asked to stop the running sync (the Stop button, or leaving the screen).
  bool _stopRequested = false;
  // Completes when the running sync has wound down, so leaving can wait for
  // it instead of closing the client under it.
  Completer<void>? _syncDone;
  // #23: periodic re-sync while this card is open (null = interval off).
  Timer? _interval;

  @override
  void initState() {
    super.initState();
    _load().then((_) async {
      // #82/#84: before anything else gets a chance to sync/prune, tell the
      // server what this card already holds — checked on every open (the
      // marker persists on the card), not just a fresh pairing, so a
      // failed attempt keeps retrying instead of permanently forfeiting
      // the re-download-avoidance win.
      await _recoverIfPending();
      // Auto-sync on open (a detected-card insert), once the first load settled.
      if (widget.autoSync && mounted && !_syncing) _sync(unattended: true);
    });
    _restartInterval();
  }

  /// #82/#84: a device id the server has no manifest record for yet — set
  /// pending at pairing (see [markManifestPending]), most commonly relevant
  /// after `.trobar/` was lost (metadata corruption, a cleared hidden
  /// folder) while the music itself survived, forcing re-enrollment under a
  /// brand-new device id. Tell the server what's already here before the
  /// first sync, so whatever selections end up assigned to this device —
  /// now or later — don't trigger a needless re-download of files already
  /// on the card.
  ///
  /// source_of_truth='device' is set FIRST: it's what stops the very next
  /// recompute from pruning the 'downloaded' rows the manifest is about to
  /// write, for a device that hasn't been assigned matching selections yet.
  /// A blank card (nothing found) skips both calls — there's nothing to
  /// protect, and no reason to flip this device to `device` source-of-truth
  /// — but the marker still clears, same as a successful handshake: there's
  /// nothing left pending either way.
  ///
  /// Only a genuine failure (network, server) leaves the marker in place,
  /// so the next card open retries — same property Android's
  /// `Prefs.recoveryPending`/`SyncEngine.recoverIfPending` has.
  Future<void> _recoverIfPending() async {
    if (!await manifestPending(widget.root)) return;
    try {
      final engine = SyncEngine(_api, widget.root);
      final held = await engine.collectManifestPaths();
      if (held.isNotEmpty) {
        await _api.setSourceOfTruth('device');
        await _api.postManifest(held);
      }
      await clearManifestPending(widget.root);
    } catch (e) {
      // The marker stays set, so this retries next open; said once here,
      // rather than nothing at all, so a card that keeps failing it shows why.
      if (!mounted) return;
      final l = AppLocalizations.of(context);
      setState(() {
        _error ??= l.recoveryFailed(errorText(e, l));
        _revoked = _revoked || isRevoked(e);
      });
    }
  }

  /// Pair this card again (its token was refused): the pairing screen
  /// writes the new config onto the card, and the card screen carries on
  /// with it.
  Future<void> _pairAgain() async {
    final saved = await Navigator.of(context).push<DeviceConfig>(
        MaterialPageRoute(
            builder: (_) => PairScreen(root: widget.root, client: widget.client)));
    if (!mounted || saved == null) return;
    setState(() {
      _api.close();
      _config = saved;
      _api = ApiClient(_config, httpClient: widget.client);
      _error = null;
      _revoked = false;
    });
    _load();
  }

  /// (Re)start the while-open interval timer from the current pref (#23) —
  /// called on open and after Settings, so a changed interval takes effect
  /// without reopening the card.
  void _restartInterval() {
    _interval?.cancel();
    final mins = AppPrefs.instance.autoSyncIntervalMinutes;
    _interval = mins > 0
        ? Timer.periodic(Duration(minutes: mins), (_) {
            if (mounted && !_syncing) _sync(unattended: true);
          })
        : null;
  }

  @override
  void dispose() {
    _interval?.cancel();
    _api.close();
    super.dispose();
  }

  /// [_load], for a test standing in for what reloads the card (Settings,
  /// pairing again).
  @visibleForTesting
  Future<void> reloadForTest() => _load();

  Future<void> _load() async {
    // Card-local, no server — so the last-sync outcome shows even when the
    // server is unreachable.
    final outcome = await readSyncOutcome(widget.root);
    if (mounted) setState(() => _outcome = outcome);
    try {
      final info = await _api.getInfo();
      final space = await volumeSpace(widget.root);
      if (!mounted) return;
      setState(() {
        _info = info;
        _space = space;
        // The token works again (a refusal by a proxy, say, has passed):
        // the refusal and its offer no longer hold.
        if (_revoked) {
          _revoked = false;
          _error = null;
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorText(e, AppLocalizations.of(context));
          _revoked = isRevoked(e);
        });
      }
    }
  }

  /// [unattended] = triggered by auto-sync (on-detect / interval, #23) rather
  /// than the Sync button, so it must not block on a prompt (#43).
  Future<void> _sync({bool unattended = false}) async {
    // Captured before the awaits so it's safe to use in the finally for the
    // completion notification (#24), regardless of later widget lifecycle.
    final l = AppLocalizations.of(context);
    setState(() {
      _syncing = true;
      _stopRequested = false;
      _error = null;
    });
    _syncDone = Completer<void>();
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
    SyncResult? result;
    String? syncError;
    var cancelled = false;
    try {
      var changes = await _api.getChanges();
      // A stop asked for while the server was answering ends the sync
      // here, before anything is asked or downloaded. A request already
      // under way is waited out, not aborted: at most one, within its
      // timeout.
      if (_stopRequested) {
        syncError = l.syncStopped(0);
        return;
      }

      // ask about files missing on the card before syncing — unless a
      // standing policy (#17) says to always re-download or always leave
      // them deleted, so unattended/repeat syncs don't prompt.
      final missing = await engine.findMissing(changes);
      final policy = AppPrefs.instance.missingPolicy;
      // #43: an unattended auto-sync stays hands-off and never pops the
      // modal. With policy 'ask' it also decides nothing: "leave them
      // deleted" excludes the tracks on the server, which a card whose files
      // are only briefly missing (a half-mounted folder, say) must not get
      // without someone choosing it. The next manual sync asks.
      if (mounted) {
        setState(() => _missingUndecided =
            unattended && policy == 'ask' ? missing.length : 0);
      }
      if (missing.isNotEmpty && mounted && !(unattended && policy == 'ask')) {
        final bool? redownload = policy == 'redownload'
            ? true
            : policy == 'exclude'
                ? false
                : await _askMissing(missing.length);
        if (redownload == null) {
          cancelled = true;
          return; // cancelled — record nothing
        }
        await _api.resolveMissing(
          redownload: redownload ? [for (final t in missing) t.trackId] : [],
          exclude: redownload ? [] : [for (final t in missing) t.trackId],
        );
        changes = await _api.getChanges();
        if (_stopRequested) {
          syncError = l.syncStopped(0);
          return;
        }
      }

      result = await engine.run(changes,
          onProgress: (pr) {
            if (mounted) setState(() => _progress = pr);
          },
          isCancelled: () => _stopRequested);
      syncError = syncErrorText(result, l);

      // A stopped sync stops here: nothing more is sent, nothing is asked.
      if (!result.cancelled) {
        // #77/#80: best-effort — a provenance hiccup must never fail the
        // sync itself, matching how writeSyncOutcome below treats a
        // read-only/removed card.
        try {
          await syncProvenance(_api, widget.root);
        } catch (_) {
          // try again next sync
        }

        // leftovers no track claims (e.g. old-extension files
        // after a transcode-format change). Confirm-gated — the card may
        // hold files the user put there deliberately.
        // Never asked during an unattended sync, which stays hands-off (#43).
        // A standing "keep them" (the dialog's own box, or Settings) asks
        // nothing either.
        final orphans = unattended || AppPrefs.instance.orphanPolicy == 'keep'
            ? const <String>[]
            : await engine.findOrphans(changes);
        if (orphans.isNotEmpty && mounted) {
          final choice = await showDialog<OrphansChoice>(
              context: context, builder: (_) => OrphansDialog(orphans: orphans));
          if (choice != null && choice.delete.isNotEmpty) {
            await engine.deleteOrphans(choice.delete);
          }
          if (choice != null && choice.alwaysKeep) {
            AppPrefs.instance.orphanPolicy = 'keep';
            await AppPrefs.instance.save();
          }
        }
      }
    } catch (e) {
      // A refused token also refuses the reload in `finally` below, which
      // is what raises the offer to pair again.
      syncError = errorText(e, l);
    } finally {
      // Persist the outcome onto the card (#20) so it survives reopen — skipped
      // if the user cancelled before anything ran.
      if (!cancelled) {
        final outcome = SyncOutcome(
          syncedAt: DateTime.now(),
          downloaded: result?.downloadedCount ?? 0,
          deleted: result?.deletedCount ?? 0,
          playlists: result?.playlistCount ?? 0,
          devicePlaylists: result?.devicePlaylistCount ?? 0,
          unknownEntries: result?.deviceUnknownEntries ?? 0,
          error: syncError,
        );
        try {
          await writeSyncOutcome(widget.root, outcome);
        } catch (_) {
          // a read-only/removed card mustn't crash the sync UI
        }
        if (mounted) setState(() => _outcome = outcome);
        if (outcome.error == null) {
          await recordSuccessfulSync(AppPrefs.instance, _api);
        }
        // #24: signal completion via an OS notification when the window isn't
        // focused — but only when something actually happened, so an unattended
        // interval sync (#23) that finds nothing doesn't ping every time.
        if (outcome.error != null) {
          notifyIfUnfocused(l.notifySyncFailed, outcome.error!);
        } else {
          final body = syncCompleteBody(outcome, l);
          if (body != null) notifyIfUnfocused(l.notifySyncComplete, body);
        }
      }
      if (mounted) {
        setState(() {
          _syncing = false;
          _progress = null;
        });
        _load();
      }
      _syncDone?.complete();
    }
  }

  String _fmtSyncTime(DateTime dt) =>
      syncTimeText(dt, Localizations.localeOf(context).toString());

  Future<void> _copyError(String error) async {
    await Clipboard.setData(ClipboardData(text: error));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context).errorCopied)));
    }
  }

  Future<void> _clearError() async {
    final outcome = _outcome;
    if (outcome == null) return;
    final cleared = outcome.withoutError();
    try {
      await writeSyncOutcome(widget.root, cleared);
    } catch (_) {
      // best-effort; still drop it from the view
    }
    if (mounted) setState(() => _outcome = cleared);
  }

  /// Back while a sync runs: confirm, then stop the sync and leave once it
  /// has wound down, so the client is never closed under a download.
  Future<void> _leaveDuringSync() async {
    final stop = await showDialog<bool>(
      context: context,
      builder: (context) {
        final l = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(l.leaveDuringSyncTitle),
          content: Text(l.leaveDuringSyncBody),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l.keepSyncing)),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l.stopAndLeave)),
          ],
        );
      },
    );
    if (stop != true || !mounted) return;
    setState(() => _stopRequested = true);
    await _syncDone?.future;
    if (mounted) Navigator.of(context).pop();
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
        _api = ApiClient(_config, httpClient: widget.client);
      });
    }
    _restartInterval(); // #23: the auto-sync interval may have changed
    _load(); // pick up a storage-limit change (re-fetches device info)
  }

  @override
  Widget build(BuildContext context) {
    final space = _space;
    final l = AppLocalizations.of(context);
    final outcome = _outcome;
    return PopScope(
      canPop: !_syncing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leaveDuringSync();
      },
      child: Scaffold(
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
                Center(
                  // #25: notes rise from the lute while syncing; tap to sync.
                  child: SyncingLogo(
                    syncing: _syncing,
                    size: 96,
                    onTap: _syncing ? null : _sync,
                  ),
                ),
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
                // What an unattended sync left for the person to decide.
                if (_missingUndecided > 0 && !_syncing) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Icon(Icons.help_outline,
                                  color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 12),
                              Expanded(child: Text(l.missingUndecided(_missingUndecided))),
                            ]),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(onPressed: _sync, child: Text(l.decide)),
                            ),
                          ]),
                    ),
                  ),
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
                if (_syncing)
                  TextButton.icon(
                      icon: const Icon(Icons.stop_circle_outlined, size: 16),
                      label: Text(_stopRequested ? l.syncStopping : l.syncStop),
                      onPressed: _stopRequested
                          ? null
                          : () => setState(() => _stopRequested = true)),
                // Persisted last-sync outcome (#20): summary + timestamp, both
                // read from the card so they survive reopening it.
                if (outcome != null && !_syncing) ...[
                  Text(l.syncSummary(outcome.downloaded, outcome.deleted),
                      textAlign: TextAlign.center),
                  // desktop#25: whether the playlists made on the card were
                  // understood, and where the entries that weren't went.
                  if (syncPlaylistsLine(outcome, l) case final line?)
                    Text(line, textAlign: TextAlign.center),
                  const SizedBox(height: 2),
                  Text(l.lastSync(_fmtSyncTime(outcome.syncedAt)),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: brandInk(context).withValues(alpha: .6))),
                  if (outcome.unknownEntries > 0)
                    Center(
                      child: TextButton(
                          onPressed: () {
                            // The Devices tab, where the card's unknown
                            // entries are reviewed on its device card.
                            final url = Uri.parse(
                                '${widget.config.serverUrl.replaceAll(RegExp(r'/+$'), '')}/#/devices');
                            (widget.openUrl ?? (u) => launchUrl(u))(url);
                          },
                          child: Text(l.reviewUnknownEntries)),
                    ),
                ],
                // Persisted sync error — copyable (for a bug report) and
                // clearable; survives reopen until cleared (#20).
                if (outcome?.error != null && !_syncing)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(children: [
                      Expanded(
                          child: Text(outcome!.error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error))),
                      IconButton(
                          tooltip: l.copyError,
                          icon: const Icon(Icons.copy, size: 16),
                          onPressed: () => _copyError(outcome.error!)),
                      IconButton(
                          tooltip: l.clearError,
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: _clearError),
                    ]),
                  ),
                // Transient connection error (this session only, e.g. couldn't
                // reach the server to load device info) — not persisted.
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
                if (_revoked)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                        icon: const Icon(Icons.link, size: 16),
                        label: Text(l.pairAgain),
                        onPressed: _syncing ? null : _pairAgain),
                  ),
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
    ));
  }
}
