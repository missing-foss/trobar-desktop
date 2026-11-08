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
      'Dans l\'application web, obtenez un code d\'association pour cet appareil (pour un appareil existant : Appareils → Réappairer dans l\'app), puis saisissez ci-dessous l\'URL du serveur et le code de 8 caractères. L\'association est enregistrée sur la carte elle-même : tout ordinateur exécutant Trobar peut la synchroniser.';

  @override
  String get pairInvalidConfig =>
      'Configuration d\'appareil invalide (server_url avec token ou enroll_code attendus).';

  @override
  String pairWriteFailed(String path, String reason) {
    return 'Écriture impossible dans $path : $reason';
  }

  @override
  String get loadConfigFile => 'Charger trobar-device.json…';

  @override
  String get pairButton => 'Associer';

  @override
  String get pairServerUrlLabel => 'URL du serveur';

  @override
  String get pairCodeLabel => 'Code d\'association';

  @override
  String get pairNameLabel => 'Nom de l\'appareil';

  @override
  String get pairNameHelp =>
      'Utilisé pour un nouvel appareil. Une réassociation garde le nom que l\'appareil a déjà.';

  @override
  String get pairConfigHeading =>
      'Ou collez une configuration d\'appareil, ou chargez son fichier';

  @override
  String get pairConfigButton => 'Associer avec la configuration';

  @override
  String get pairMissingServer => 'Saisissez l\'URL du serveur.';

  @override
  String get pairBadServerUrl =>
      'L\'URL du serveur doit commencer par https:// ou http://.';

  @override
  String get pairMissingName => 'Saisissez un nom d\'appareil.';

  @override
  String get pairInvalidCode =>
      'Ce n\'est pas un code d\'association : il fait 8 lettres et chiffres.';

  @override
  String get pairCodeRejected =>
      'Code invalide ou expiré. Obtenez-en un nouveau dans l\'application web.';

  @override
  String get pairRateLimited =>
      'Trop de tentatives. Attendez quelques minutes et réessayez.';

  @override
  String pairNetworkError(String reason) {
    return 'Impossible de joindre le serveur : $reason';
  }

  @override
  String pairFailed(String reason) {
    return 'Échec de l\'association : $reason';
  }

  @override
  String pairedAs(String name) {
    return 'Associé en tant que $name';
  }

  @override
  String freeOfTotal(String free, String total) {
    return '$free Go libres sur $total Go';
  }

  @override
  String missingTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count morceaux introuvables sur cette carte',
      one: '$count morceau introuvable sur cette carte',
    );
    return '$_temp0';
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
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fichiers sur cette carte ne sont pas gérés par Trobar',
      one: '$count fichier sur cette carte n\'est pas géré par Trobar',
    );
    return '$_temp0';
  }

  @override
  String get keep => 'Garder';

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
  String get supportOnKofi => 'Soutenir sur Ko-fi';

  @override
  String get supportNote =>
      'Le soutien paie les appareils de test, l\'infrastructure et Claude. Surtout, il offre un bon café et entretient la motivation pour les prochains projets.';

  @override
  String get thanksCardThank => 'Mer';

  @override
  String get thanksCardYou => 'ci';

  @override
  String thanksCardSynced(int count) {
    return 'Trobar a synchronisé $count fois pour vous.';
  }

  @override
  String get thanksCardCoffee => 'S\'il vous est utile, un café aide.';

  @override
  String get dismiss => 'Ignorer';

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
      'Trobar desktop est un logiciel libre sous licence GNU GPL, version 3 ou ultérieure. Chaque bibliothèque intégrée conserve sa propre licence.';

  @override
  String get showThirdParty => 'Afficher les licences';

  @override
  String get close => 'Fermer';

  @override
  String get save => 'Enregistrer';

  @override
  String syncSummary(int downloaded, int removed) {
    String _temp0 = intl.Intl.pluralLogic(
      downloaded,
      locale: localeName,
      other: '$downloaded téléchargés',
      one: '$downloaded téléchargé',
    );
    String _temp1 = intl.Intl.pluralLogic(
      removed,
      locale: localeName,
      other: '$removed supprimés',
      one: '$removed supprimé',
    );
    return 'Synchronisé : $_temp0, $_temp1';
  }

  @override
  String get settingsTooltip => 'Réglages';

  @override
  String get settingsTitle => 'Réglages';

  @override
  String get settingsServerUrl => 'URL du serveur';

  @override
  String get settingsServerUrlHelp =>
      'Le serveur Trobar avec lequel cette carte se synchronise. Le jeton d\'association est conservé.';

  @override
  String get settingsInvalidUrl =>
      'Saisissez une URL de serveur http(s) valide.';

  @override
  String get settingsLanguage => 'Langue';

  @override
  String get settingsLanguageSystem => 'Système';

  @override
  String get settingsTheme => 'Thème';

  @override
  String get brandThemeTroubadour => 'Par défaut · crème';

  @override
  String get brandThemeNuech => 'Nuit · sombre uniquement';

  @override
  String get brandThemeGarriga => 'Sauge · olive';

  @override
  String get brandThemePeira => 'Pierre · terre cuite';

  @override
  String get brandThemeContraste => 'Contraste élevé · sombre uniquement';

  @override
  String get settingsMissingPolicy =>
      'Quand des fichiers manquent sur la carte';

  @override
  String get settingsMissingAsk => 'Demander à chaque fois';

  @override
  String get settingsMissingRedownload => 'Toujours retélécharger';

  @override
  String get settingsMissingExclude => 'Toujours laisser supprimés';

  @override
  String get settingsStorageLimit => 'Limite de stockage (Go)';

  @override
  String get settingsStorageLimitHelp => 'Laisser vide pour aucune limite.';

  @override
  String get settingsInvalidLimit =>
      'Saisissez un nombre entier de Go, ou laissez vide.';

  @override
  String storageAllocated(String limit) {
    return 'Alloué : $limit Go';
  }

  @override
  String get storageLimitExceedsFree =>
      'Cette limite dépasse l\'espace réellement disponible !';

  @override
  String lastSync(String when) {
    return 'Dernière synchro : $when';
  }

  @override
  String get copyError => 'Copier l\'erreur';

  @override
  String get clearError => 'Effacer';

  @override
  String get errorCopied => 'Erreur copiée dans le presse-papiers';

  @override
  String get settingsAutoSyncOnDetect =>
      'Synchroniser automatiquement à l\'insertion d\'une carte';

  @override
  String get settingsAutoSyncOnDetectHelp =>
      'Quand l\'application est ouverte et qu\'une carte associée apparaît, la synchroniser sans demander.';

  @override
  String get settingsAutoSyncInterval =>
      'Synchro auto quand une carte est ouverte';

  @override
  String get autoSyncOff => 'Désactivé';

  @override
  String autoSyncEveryMinutes(int minutes) {
    return 'Toutes les $minutes min';
  }

  @override
  String autoSyncEveryHours(int hours) {
    return 'Toutes les $hours h';
  }

  @override
  String get notifySyncComplete => 'Synchronisation terminée';

  @override
  String get notifySyncFailed => 'Échec de la synchronisation';

  @override
  String get syncStop => 'Arrêter la synchro';

  @override
  String get syncStopping => 'Arrêt…';

  @override
  String syncStopped(int downloaded) {
    String _temp0 = intl.Intl.pluralLogic(
      downloaded,
      locale: localeName,
      other: '$downloaded téléchargés',
      one: '$downloaded téléchargé',
    );
    return 'Synchro arrêtée : $_temp0 avant l\'arrêt. Le reste viendra à la prochaine synchro.';
  }

  @override
  String get leaveDuringSyncTitle => 'Une synchro est en cours';

  @override
  String get leaveDuringSyncBody =>
      'L\'arrêter et quitter ? Ce qui est déjà téléchargé reste sur la carte ; le reste viendra à la prochaine synchro.';

  @override
  String get keepSyncing => 'Continuer la synchro';

  @override
  String get stopAndLeave => 'Arrêter et quitter';

  @override
  String get pairingRevoked =>
      'Le serveur n\'accepte plus l\'association de cette carte : l\'appareil a été supprimé ou associé à nouveau ailleurs. Associez cette carte à nouveau pour continuer à la synchroniser.';

  @override
  String get pairAgain => 'Associer cette carte à nouveau';

  @override
  String recoveryFailed(String reason) {
    return 'Impossible d\'indiquer au serveur ce que cette carte contient déjà ; ce sera retenté à la prochaine ouverture de la carte. ($reason)';
  }

  @override
  String syncNotEnoughSpace(String needed, String free) {
    return 'Pas assez de place sur la carte : ces téléchargements demandent au moins $needed Go, et $free Go sont libres. Rien n\'a été téléchargé ; libérez de la place, ou réduisez ce qui est sélectionné pour cet appareil.';
  }

  @override
  String get syncCardFull =>
      'La carte s\'est remplie pendant la synchronisation. Ce qui tenait y est ; libérez de la place, ou réduisez ce qui est sélectionné pour cet appareil, puis synchronisez à nouveau.';

  @override
  String get duelTitle => 'Défiez le barde';

  @override
  String get duelYourTurn => 'À vous de jouer';

  @override
  String get duelBardThinking => 'Le barde réfléchit…';

  @override
  String get duelYouWin => 'Vous avez battu le barde !';

  @override
  String get duelBardWins => 'Le barde gagne !';

  @override
  String get duelDraw => 'Match nul !';

  @override
  String get duelPlayAgain => 'Rejouer';

  @override
  String get duelHint => 'Cliquez une colonne ou appuyez sur 1–7 pour jouer';

  @override
  String syncPlaylists(int written, int read) {
    String _temp0 = intl.Intl.pluralLogic(
      written,
      locale: localeName,
      other: '$written playlists écrites',
      one: '$written playlist écrite',
    );
    String _temp1 = intl.Intl.pluralLogic(
      read,
      locale: localeName,
      other: '$read des vôtres lues',
      one: '$read des vôtres lue',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String syncUnknownEntries(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '($count entrées inconnues)',
      one: '($count entrée inconnue)',
    );
    return '$_temp0';
  }

  @override
  String get reviewUnknownEntries => 'Les voir dans l\'appli web';

  @override
  String missingUndecided(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count titres attendus par le serveur manquent sur cette carte. Une synchro automatique vous laisse décider.',
      one:
          '$count titre attendu par le serveur manque sur cette carte. Une synchro automatique vous laisse décider.',
    );
    return '$_temp0';
  }

  @override
  String get decide => 'Décider';

  @override
  String get orphansIntro =>
      'Ce sont souvent des restes d\'un changement de format, mais les fichiers que vous avez copiés vous-même apparaissent aussi. Cochez ceux à supprimer ; les autres restent.';

  @override
  String get orphansSelectAll => 'Tout sélectionner';

  @override
  String orphansDeleteSelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Supprimer $count fichiers',
      one: 'Supprimer $count fichier',
    );
    return '$_temp0';
  }

  @override
  String get orphansAlwaysKeep =>
      'Toujours garder les fichiers que Trobar n\'a pas mis ici, sans plus demander';

  @override
  String get settingsOrphanPolicy =>
      'Quand la carte contient des fichiers que Trobar n\'y a pas mis';

  @override
  String get settingsOrphanAsk => 'Demander à chaque fois';

  @override
  String get settingsOrphanKeep => 'Toujours les garder';
}
