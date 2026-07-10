import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fr'),
  ];

  /// No description provided for @noCardDetected.
  ///
  /// In en, this message translates to:
  /// **'No paired card detected.'**
  String get noCardDetected;

  /// No description provided for @rescan.
  ///
  /// In en, this message translates to:
  /// **'Rescan'**
  String get rescan;

  /// No description provided for @openFolder.
  ///
  /// In en, this message translates to:
  /// **'Open folder…'**
  String get openFolder;

  /// No description provided for @pairTitle.
  ///
  /// In en, this message translates to:
  /// **'Pair this folder'**
  String get pairTitle;

  /// No description provided for @pairInstructions.
  ///
  /// In en, this message translates to:
  /// **'In the web app, create a device (type: SD card) and download its config file — then paste its contents here. The pairing is stored on the card itself, so any computer running Trobar can sync it.'**
  String get pairInstructions;

  /// No description provided for @pairInvalidConfig.
  ///
  /// In en, this message translates to:
  /// **'Not a valid device config (expected server_url + token).'**
  String get pairInvalidConfig;

  /// No description provided for @pairWriteFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not write to {path}: {reason}'**
  String pairWriteFailed(String path, String reason);

  /// No description provided for @loadConfigFile.
  ///
  /// In en, this message translates to:
  /// **'Load trobar-device.json…'**
  String get loadConfigFile;

  /// No description provided for @pairButton.
  ///
  /// In en, this message translates to:
  /// **'Pair'**
  String get pairButton;

  /// No description provided for @transcodeActive.
  ///
  /// In en, this message translates to:
  /// **'Lossless tracks are transcoded to {format} kbit/s on this machine.'**
  String transcodeActive(String format);

  /// No description provided for @transcodeNoFfmpeg.
  ///
  /// In en, this message translates to:
  /// **'ffmpeg not found — transcoded tracks will be skipped. Install ffmpeg and reopen this card.'**
  String get transcodeNoFfmpeg;

  /// No description provided for @freeOfTotal.
  ///
  /// In en, this message translates to:
  /// **'{free} GB free of {total} GB'**
  String freeOfTotal(String free, String total);

  /// No description provided for @syncSummary.
  ///
  /// In en, this message translates to:
  /// **'Synced: {downloaded} downloaded, {transcoded} transcoded, {removed} removed'**
  String syncSummary(int downloaded, int transcoded, int removed);

  /// No description provided for @syncSummarySkipped.
  ///
  /// In en, this message translates to:
  /// **', {skipped} skipped (no ffmpeg)'**
  String syncSummarySkipped(int skipped);

  /// No description provided for @missingTitle.
  ///
  /// In en, this message translates to:
  /// **'{count} track(s) missing on this card'**
  String missingTitle(int count);

  /// No description provided for @missingBody.
  ///
  /// In en, this message translates to:
  /// **'The server expected these files to be here. Re-download them, or leave them deleted (they will not be re-queued)?'**
  String get missingBody;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @leaveDeleted.
  ///
  /// In en, this message translates to:
  /// **'Leave deleted'**
  String get leaveDeleted;

  /// No description provided for @redownload.
  ///
  /// In en, this message translates to:
  /// **'Re-download'**
  String get redownload;

  /// No description provided for @orphansTitle.
  ///
  /// In en, this message translates to:
  /// **'{count} file(s) on this card are not managed by Trobar'**
  String orphansTitle(int count);

  /// No description provided for @orphansBody.
  ///
  /// In en, this message translates to:
  /// **'Usually leftovers from a format change — but files you copied here yourself also show up. Delete them?\n\n{preview}'**
  String orphansBody(String preview);

  /// No description provided for @orphansMore.
  ///
  /// In en, this message translates to:
  /// **'… and {count} more'**
  String orphansMore(int count);

  /// No description provided for @keep.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get keep;

  /// No description provided for @deleteThem.
  ///
  /// In en, this message translates to:
  /// **'Delete them'**
  String get deleteThem;

  /// No description provided for @syncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get syncNow;

  /// No description provided for @syncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing…'**
  String get syncing;

  /// No description provided for @aboutTooltip.
  ///
  /// In en, this message translates to:
  /// **'About Trobar'**
  String get aboutTooltip;

  /// No description provided for @aboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutTitle;

  /// No description provided for @aboutVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String aboutVersion(String version);

  /// No description provided for @checkUpdates.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get checkUpdates;

  /// No description provided for @updateChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get updateChecking;

  /// No description provided for @updateAvailable.
  ///
  /// In en, this message translates to:
  /// **'Update available: {tag} — see Releases.'**
  String updateAvailable(String tag);

  /// No description provided for @updateUpToDate.
  ///
  /// In en, this message translates to:
  /// **'You are running the latest release ({version}).'**
  String updateUpToDate(String version);

  /// No description provided for @updateCheckFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not reach GitHub ({error}) — try again later.'**
  String updateCheckFailed(String error);

  /// No description provided for @donate.
  ///
  /// In en, this message translates to:
  /// **'Donate'**
  String get donate;

  /// No description provided for @aboutLinks.
  ///
  /// In en, this message translates to:
  /// **'Links'**
  String get aboutLinks;

  /// No description provided for @aboutDocumentation.
  ///
  /// In en, this message translates to:
  /// **'Documentation'**
  String get aboutDocumentation;

  /// No description provided for @aboutSourceCode.
  ///
  /// In en, this message translates to:
  /// **'Source code'**
  String get aboutSourceCode;

  /// No description provided for @aboutReportIssue.
  ///
  /// In en, this message translates to:
  /// **'Report an issue or request a feature'**
  String get aboutReportIssue;

  /// No description provided for @aboutReleases.
  ///
  /// In en, this message translates to:
  /// **'Releases'**
  String get aboutReleases;

  /// No description provided for @aboutLicenses.
  ///
  /// In en, this message translates to:
  /// **'Licenses'**
  String get aboutLicenses;

  /// No description provided for @aboutLicenseSummary.
  ///
  /// In en, this message translates to:
  /// **'Trobar desktop is free software under the GNU GPL, version 3 or later. The bundled ffmpeg and every library keep their own licenses.'**
  String get aboutLicenseSummary;

  /// No description provided for @showLicense.
  ///
  /// In en, this message translates to:
  /// **'License'**
  String get showLicense;

  /// No description provided for @showThirdParty.
  ///
  /// In en, this message translates to:
  /// **'Third-party'**
  String get showThirdParty;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
