// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get noCardDetected => 'No paired card detected.';

  @override
  String get rescan => 'Rescan';

  @override
  String get openFolder => 'Open folder…';

  @override
  String get pairTitle => 'Pair this folder';

  @override
  String get pairInstructions =>
      'In the web app, get a pairing code for this device (for one that already exists: Devices → Re-pair in app), then enter the server URL and the 8-character code below. The pairing is stored on the card itself, so any computer running Trobar can sync it.';

  @override
  String get pairInvalidConfig =>
      'Not a valid device config (expected server_url with token or enroll_code).';

  @override
  String pairWriteFailed(String path, String reason) {
    return 'Could not write to $path: $reason';
  }

  @override
  String get loadConfigFile => 'Load trobar-device.json…';

  @override
  String get pairButton => 'Pair';

  @override
  String get pairServerUrlLabel => 'Server URL';

  @override
  String get pairCodeLabel => 'Pairing code';

  @override
  String get pairNameLabel => 'Device name';

  @override
  String get pairNameHelp =>
      'Used for a new device. Re-pairing keeps the name the device already has.';

  @override
  String get pairConfigHeading => 'Or paste a device config, or load its file';

  @override
  String get pairConfigButton => 'Pair with config';

  @override
  String get pairMissingServer => 'Enter the server URL.';

  @override
  String get pairBadServerUrl =>
      'The server URL must start with https:// or http://.';

  @override
  String get pairMissingName => 'Enter a device name.';

  @override
  String get pairInvalidCode =>
      'That isn\'t a pairing code: it\'s 8 letters and digits.';

  @override
  String get pairCodeRejected =>
      'Invalid or expired code. Get a fresh one in the web app.';

  @override
  String get pairRateLimited =>
      'Too many attempts. Wait a few minutes and try again.';

  @override
  String pairNetworkError(String reason) {
    return 'Couldn\'t reach the server: $reason';
  }

  @override
  String pairFailed(String reason) {
    return 'Pairing failed: $reason';
  }

  @override
  String pairedAs(String name) {
    return 'Paired as $name';
  }

  @override
  String freeOfTotal(String free, String total) {
    return '$free GB free of $total GB';
  }

  @override
  String missingTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tracks missing on this card',
      one: '$count track missing on this card',
    );
    return '$_temp0';
  }

  @override
  String get missingBody =>
      'The server expected these files to be here. Re-download them, or leave them deleted (they will not be re-queued)?';

  @override
  String get cancel => 'Cancel';

  @override
  String get leaveDeleted => 'Leave deleted';

  @override
  String get redownload => 'Re-download';

  @override
  String orphansTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files on this card are not managed by Trobar',
      one: '$count file on this card is not managed by Trobar',
    );
    return '$_temp0';
  }

  @override
  String get keep => 'Keep';

  @override
  String get syncNow => 'Sync now';

  @override
  String get syncing => 'Syncing…';

  @override
  String get aboutTooltip => 'About Trobar';

  @override
  String get aboutTitle => 'About';

  @override
  String aboutVersion(String version) {
    return 'Version $version';
  }

  @override
  String get checkUpdates => 'Check for updates';

  @override
  String get updateChecking => 'Checking…';

  @override
  String updateAvailable(String tag) {
    return 'Update available: $tag — see Releases.';
  }

  @override
  String updateUpToDate(String version) {
    return 'You are running the latest release ($version).';
  }

  @override
  String updateCheckFailed(String error) {
    return 'Could not reach GitHub ($error) — try again later.';
  }

  @override
  String get supportOnKofi => 'Support on Ko-fi';

  @override
  String get supportNote =>
      'Support pays for test devices, infrastructure and Claude. Mostly, it buys a good coffee and keeps the motivation going for the next projects.';

  @override
  String get thanksCardThank => 'Thank';

  @override
  String get thanksCardYou => 'you';

  @override
  String thanksCardSynced(int count) {
    return 'Trobar has synced $count times for you.';
  }

  @override
  String get thanksCardCoffee => 'If it\'s useful, a coffee helps.';

  @override
  String get dismiss => 'Dismiss';

  @override
  String get aboutLinks => 'Links';

  @override
  String get aboutDocumentation => 'Documentation';

  @override
  String get aboutSourceCode => 'Source code';

  @override
  String get aboutReportIssue => 'Report an issue or request a feature';

  @override
  String get aboutReleases => 'Releases';

  @override
  String get aboutLicenses => 'Licenses';

  @override
  String get aboutLicenseSummary =>
      'Trobar desktop is free software under the GNU GPL, version 3 or later. Every bundled library keeps its own license.';

  @override
  String get showThirdParty => 'Show licenses';

  @override
  String get close => 'Close';

  @override
  String get save => 'Save';

  @override
  String syncSummary(int downloaded, int removed) {
    return 'Synced: $downloaded downloaded, $removed removed';
  }

  @override
  String get settingsTooltip => 'Settings';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsServerUrl => 'Server URL';

  @override
  String get settingsServerUrlHelp =>
      'The Trobar server this card syncs with. The pairing token is kept.';

  @override
  String get settingsInvalidUrl => 'Enter a valid http(s) server URL.';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageSystem => 'System';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get brandThemeTroubadour => 'Default · cream';

  @override
  String get brandThemeNuech => 'Night · dark only';

  @override
  String get brandThemeGarriga => 'Sage · olive';

  @override
  String get brandThemePeira => 'Stone · terracotta';

  @override
  String get brandThemeContraste => 'High contrast · dark only';

  @override
  String get settingsMissingPolicy => 'When files are missing on the card';

  @override
  String get settingsMissingAsk => 'Ask each time';

  @override
  String get settingsMissingRedownload => 'Always re-download';

  @override
  String get settingsMissingExclude => 'Always leave deleted';

  @override
  String get settingsStorageLimit => 'Storage limit (GB)';

  @override
  String get settingsStorageLimitHelp => 'Leave empty for no limit.';

  @override
  String get settingsInvalidLimit =>
      'Enter a whole number of GB, or leave empty.';

  @override
  String storageAllocated(String limit) {
    return 'Allocated: $limit GB';
  }

  @override
  String get storageLimitExceedsFree =>
      'This limit exceeds the actual free space!';

  @override
  String lastSync(String when) {
    return 'Last sync: $when';
  }

  @override
  String get copyError => 'Copy error';

  @override
  String get clearError => 'Clear';

  @override
  String get errorCopied => 'Error copied to clipboard';

  @override
  String get settingsAutoSyncOnDetect =>
      'Sync automatically when a card is inserted';

  @override
  String get settingsAutoSyncOnDetectHelp =>
      'While this app is open and a paired card appears, sync it without asking.';

  @override
  String get settingsAutoSyncInterval => 'Auto-sync while a card is open';

  @override
  String get autoSyncOff => 'Off';

  @override
  String autoSyncEveryMinutes(int minutes) {
    return 'Every $minutes min';
  }

  @override
  String autoSyncEveryHours(int hours) {
    return 'Every $hours h';
  }

  @override
  String get notifySyncComplete => 'Sync complete';

  @override
  String get notifySyncFailed => 'Sync failed';

  @override
  String get syncStop => 'Stop sync';

  @override
  String get syncStopping => 'Stopping…';

  @override
  String syncStopped(int downloaded) {
    return 'Sync stopped: $downloaded downloaded before it stopped. The rest comes with the next sync.';
  }

  @override
  String get leaveDuringSyncTitle => 'A sync is running';

  @override
  String get leaveDuringSyncBody =>
      'Stop it and leave? What\'s already downloaded stays on the card; the rest comes with the next sync.';

  @override
  String get keepSyncing => 'Keep syncing';

  @override
  String get stopAndLeave => 'Stop and leave';

  @override
  String get pairingRevoked =>
      'The server no longer accepts this card\'s pairing: the device was removed or paired again elsewhere. Pair this card again to keep syncing it.';

  @override
  String get pairAgain => 'Pair this card again';

  @override
  String recoveryFailed(String reason) {
    return 'Couldn\'t tell the server what this card already holds; this is tried again the next time the card is opened. ($reason)';
  }

  @override
  String syncNotEnoughSpace(String needed, String free) {
    return 'Not enough space on the card: these downloads need at least $needed GB, and $free GB is free. Nothing was downloaded; free some space, or lower what is selected for this device.';
  }

  @override
  String get syncCardFull =>
      'The card filled up during the sync. What fit is on it; free some space, or lower what is selected for this device, and sync again.';

  @override
  String get duelTitle => 'Duel the bard';

  @override
  String get duelYourTurn => 'Your turn';

  @override
  String get duelBardThinking => 'The bard is thinking…';

  @override
  String get duelYouWin => 'You beat the bard!';

  @override
  String get duelBardWins => 'The bard wins!';

  @override
  String get duelDraw => 'A draw!';

  @override
  String get duelPlayAgain => 'Play again';

  @override
  String get duelHint => 'Click a column or press 1–7 to drop';

  @override
  String syncPlaylists(int written, int read) {
    String _temp0 = intl.Intl.pluralLogic(
      written,
      locale: localeName,
      other: '$written playlists written',
      one: '$written playlist written',
    );
    return '$_temp0 · $read of yours read';
  }

  @override
  String syncUnknownEntries(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '($count entries unknown)',
      one: '($count entry unknown)',
    );
    return '$_temp0';
  }

  @override
  String get reviewUnknownEntries => 'Review them in the web app';

  @override
  String missingUndecided(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count tracks the server expects are missing on this card. An automatic sync leaves that for you to decide.',
      one:
          '$count track the server expects is missing on this card. An automatic sync leaves that for you to decide.',
    );
    return '$_temp0';
  }

  @override
  String get decide => 'Decide';

  @override
  String get orphansIntro =>
      'Usually leftovers from a format change, but files you copied here yourself show up too. Tick the ones to delete; the rest stay.';

  @override
  String get orphansSelectAll => 'Select all';

  @override
  String orphansDeleteSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Delete $count files',
      one: 'Delete $count file',
    );
    return '$_temp0';
  }

  @override
  String get orphansAlwaysKeep =>
      'Always keep files Trobar didn\'t put here, and stop asking';

  @override
  String get settingsOrphanPolicy =>
      'When the card has files Trobar didn\'t put there';

  @override
  String get settingsOrphanAsk => 'Ask each time';

  @override
  String get settingsOrphanKeep => 'Always keep them';
}
