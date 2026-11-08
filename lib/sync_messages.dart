// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// The sentence a finished sync shows, from its SyncResult: kept out of the
// widget so the choice is testable without driving a whole sync.

import 'api_client.dart';
import 'l10n/gen/app_localizations.dart';
import 'models.dart';
import 'sync_engine.dart';

/// Gigabytes to one decimal, rounded the way that keeps "needs at least X,
/// Y free" true: what's needed up, what's free down. A plain rounding could
/// read "needs at least 1.0 GB, and 1.0 GB is free".
String gbUp(int bytes) => ((bytes / 1e8).ceil() / 10).toStringAsFixed(1);
String gbDown(int bytes) => ((bytes / 1e8).floor() / 10).toStringAsFixed(1);

/// The error a sync reports, or null when it went through: the card being
/// too small or filling up, worded here, before any other first error.
String? syncErrorText(SyncResult result, AppLocalizations l) {
  if (result.cancelled) return l.syncStopped(result.downloadedCount);
  final short = result.notEnoughSpace;
  if (short != null) {
    return l.syncNotEnoughSpace(gbUp(short.needed), gbDown(short.free));
  }
  if (result.diskFull) return l.syncCardFull;
  return result.firstError;
}

/// desktop#25: what became of the playlists, or null when the sync wrote
/// none and read none of the card's own.
String? syncPlaylistsLine(SyncOutcome o, AppLocalizations l) {
  if (o.playlists == 0 && o.devicePlaylists == 0) return null;
  return [
    l.syncPlaylists(o.playlists, o.devicePlaylists),
    if (o.unknownEntries > 0) l.syncUnknownEntries(o.unknownEntries),
  ].join(' ');
}

/// The body of the notification a finished sync sends, or null when nothing
/// worth one happened. Entries of the card's playlists that matched nothing
/// count: they wait for the person. Playlists written don't on their own;
/// every sync writes them again.
String? syncCompleteBody(SyncOutcome o, AppLocalizations l) {
  if (o.downloaded == 0 && o.deleted == 0 && o.unknownEntries == 0) return null;
  final playlists = syncPlaylistsLine(o, l);
  return [l.syncSummary(o.downloaded, o.deleted), ?playlists].join('\n');
}

/// How a failed request reads on screen: a revoked pairing as what it is and
/// what to do about it, anything else as it was reported.
String errorText(Object e, AppLocalizations l) =>
    e is ApiException && e.isRevoked ? l.pairingRevoked : '$e';

/// Whether [e] means the card has to be paired again.
bool isRevoked(Object e) => e is ApiException && e.isRevoked;
