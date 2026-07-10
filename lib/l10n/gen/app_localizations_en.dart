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
  String transcodeActive(String format) {
    return 'Lossless tracks are transcoded to $format kbit/s on this machine.';
  }

  @override
  String get transcodeNoFfmpeg =>
      'ffmpeg not found — transcoded tracks will be skipped. Install ffmpeg and reopen this card.';

  @override
  String freeOfTotal(String free, String total) {
    return '$free GB free of $total GB';
  }

  @override
  String syncSummary(int downloaded, int transcoded, int removed) {
    return 'Synced: $downloaded downloaded, $transcoded transcoded, $removed removed';
  }

  @override
  String syncSummarySkipped(int skipped) {
    return ', $skipped skipped (no ffmpeg)';
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
      'Trobar desktop is free software under the GNU GPL, version 3 or later. The bundled ffmpeg and every library keep their own licenses.';

  @override
  String get showLicense => 'License';

  @override
  String get showThirdParty => 'Third-party';

  @override
  String get close => 'Close';
}
