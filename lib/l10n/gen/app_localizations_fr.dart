// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get noCardDetected => 'Aucune carte associée détectée.';

  @override
  String get rescan => 'Réanalyser';

  @override
  String get openFolder => 'Ouvrir un dossier…';

  @override
  String get pairTitle => 'Associer ce dossier';

  @override
  String get pairInstructions =>
      'Dans l\'application web, créez un appareil (type : carte SD) et téléchargez son fichier de configuration — puis collez son contenu ici. L\'association est enregistrée sur la carte elle-même : tout ordinateur exécutant Trobar peut la synchroniser.';

  @override
  String get pairInvalidConfig =>
      'Configuration d\'appareil invalide (server_url + token attendus).';

  @override
  String pairWriteFailed(String path, String reason) {
    return 'Écriture impossible dans $path : $reason';
  }

  @override
  String get loadConfigFile => 'Charger trobar-device.json…';

  @override
  String get pairButton => 'Associer';

  @override
  String transcodeActive(String format) {
    return 'Les morceaux lossless sont convertis en $format kbit/s sur cette machine.';
  }

  @override
  String get transcodeNoFfmpeg =>
      'ffmpeg introuvable — les morceaux à convertir seront ignorés. Installez ffmpeg puis rouvrez cette carte.';

  @override
  String freeOfTotal(String free, String total) {
    return '$free Go libres sur $total Go';
  }

  @override
  String syncSummary(int downloaded, int transcoded, int removed) {
    return 'Synchronisé : $downloaded téléchargés, $transcoded convertis, $removed supprimés';
  }

  @override
  String syncSummarySkipped(int skipped) {
    return ', $skipped ignorés (ffmpeg absent)';
  }

  @override
  String missingTitle(int count) {
    return '$count morceau(x) introuvable(s) sur cette carte';
  }

  @override
  String get missingBody =>
      'Le serveur s\'attendait à trouver ces fichiers ici. Les retélécharger, ou les laisser supprimés (ils ne seront pas re-proposés) ?';

  @override
  String get cancel => 'Annuler';

  @override
  String get leaveDeleted => 'Laisser supprimés';

  @override
  String get redownload => 'Retélécharger';

  @override
  String orphansTitle(int count) {
    return '$count fichier(s) sur cette carte ne sont pas gérés par Trobar';
  }

  @override
  String orphansBody(String preview) {
    return 'Souvent des restes d\'un changement de format — mais vos propres fichiers copiés à la main apparaissent aussi. Les supprimer ?\n\n$preview';
  }

  @override
  String orphansMore(int count) {
    return '… et $count de plus';
  }

  @override
  String get keep => 'Garder';

  @override
  String get deleteThem => 'Les supprimer';

  @override
  String get syncNow => 'Synchroniser';

  @override
  String get syncing => 'Synchronisation…';

  @override
  String get aboutTooltip => 'À propos de Trobar';

  @override
  String get aboutTitle => 'À propos';

  @override
  String aboutVersion(String version) {
    return 'Version $version';
  }

  @override
  String get checkUpdates => 'Vérifier les mises à jour';

  @override
  String get updateChecking => 'Vérification…';

  @override
  String updateAvailable(String tag) {
    return 'Mise à jour disponible : $tag — voir les versions publiées.';
  }

  @override
  String updateUpToDate(String version) {
    return 'Vous utilisez la dernière version ($version).';
  }

  @override
  String updateCheckFailed(String error) {
    return 'Impossible de joindre GitHub ($error) — réessayez plus tard.';
  }

  @override
  String get donate => 'Faire un don';

  @override
  String get aboutLinks => 'Liens';

  @override
  String get aboutDocumentation => 'Documentation';

  @override
  String get aboutSourceCode => 'Code source';

  @override
  String get aboutReportIssue =>
      'Signaler un problème ou proposer une fonctionnalité';

  @override
  String get aboutReleases => 'Versions publiées';

  @override
  String get aboutLicenses => 'Licences';

  @override
  String get aboutLicenseSummary =>
      'Trobar desktop est un logiciel libre sous licence GNU GPL, version 3 ou ultérieure. Le ffmpeg intégré et chaque bibliothèque conservent leurs propres licences.';

  @override
  String get showLicense => 'Licence';

  @override
  String get showThirdParty => 'Composants tiers';

  @override
  String get close => 'Fermer';
}
