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
      'In the web app, create a device (type: SD card) and download its config file — then paste its contents here. The pairing is stored on the card itself, so any computer running Trobar can sync it.';

  @override
  String get pairInvalidConfig =>
      'Not a valid device config (expected server_url + token).';

  @override
  String pairWriteFailed(String path, String reason) {
    return 'Could not write to $path: $reason';
  }

  @override
  String get loadConfigFile => 'Load trobar-device.json…';

  @override
  String get pairButton => 'Pair';

  @override
  String freeOfTotal(String free, String total) {
    return '$free GB free of $total GB';
  }

  @override
  String missingTitle(int count) {
    return '$count track(s) missing on this card';
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
    return '$count file(s) on this card are not managed by Trobar';
  }

  @override
  String orphansBody(String preview) {
    return 'Usually leftovers from a format change — but files you copied here yourself also show up. Delete them?\n\n$preview';
  }

  @override
  String orphansMore(int count) {
    return '… and $count more';
  }

  @override
  String get keep => 'Keep';

  @override
  String get deleteThem => 'Delete them';

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
  String get donate => 'Donate';

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
  String get showLicense => 'License';

  @override
  String get showThirdParty => 'Third-party';

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
}
