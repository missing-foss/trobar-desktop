// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// #239/#77/#80: walks and replays this device's local provenance cache
// (.trobar/provenance.json on the card — see card_store.dart). Clients
// never compute fingerprints; this only stores and forwards what the
// server itself already computed.
//
// Card-side, not app-side: everything about the existing pairing design
// (card_store.dart's own header) points there — "plug the card into any
// machine running this app and it syncs as the right device. The app
// itself keeps no per-device state." Provenance (fingerprint + on-device
// path per synced track) is per-device state in exactly the same sense
// the pairing and last_sync.json already are. App-side storage would be
// invisible the moment the card moves to another machine, defeating the
// server-DB-loss recovery case this whole feature exists for.

import 'dart:io';

import 'api_client.dart';
import 'card_store.dart';
import 'models.dart';

/// #77: walks every page of this device's server-computed fingerprints
/// (oldest track_id first) and merges them into the card's
/// provenance.json — only rewriting the file if something actually
/// changed. The endpoint has no "since" filter (only a cursor position),
/// so every sync re-walks the whole thing; a routine no-op refetch is the
/// common case, and an SD card doesn't need a whole-file rewrite for
/// nothing.
///
/// A changed fingerprint/path for an already-pushed row resets `pushed`
/// back to false, so [_pushPendingProvenance] replays it — a re-tag/
/// re-encode changes identity server-side without the client hearing
/// about it any other way.
Future<void> _fetchProvenance(ApiClient api, Directory root) async {
  final merged = await readProvenance(root);
  var changed = false;
  var after = 0;
  while (true) {
    final page = await api.getFingerprintsPage(after);
    for (final entry in page.entries) {
      final existing = merged[entry.trackId];
      final unchanged = existing != null &&
          existing.fingerprint == entry.fingerprint &&
          existing.path == entry.path;
      if (unchanged) continue;
      merged[entry.trackId] = ProvenanceRecord(
        trackId: entry.trackId,
        fingerprint: entry.fingerprint,
        path: entry.path,
      );
      changed = true;
    }
    final next = page.nextAfter;
    if (next == null) break;
    after = next;
  }
  if (changed) await writeProvenance(root, merged);
}

/// #80: replays this device's not-yet-acknowledged provenance rows,
/// paged at [provenancePushMax]. Driven by the locally-stored `pushed`
/// flag, not the response's `pending` count — that count also includes
/// rows still awaiting the server's own async rematch job, which this
/// loop has no reason to wait on.
///
/// Run every sync, right after the fetch — not gated behind an explicit
/// "re-link this device" action or a server-reported-unknown-tracks
/// signal (the other two candidates #80 raised): with `pushed` already
/// tracking what's been sent, a call here is a no-op once caught up, so
/// this is the cheap "replay anything outstanding" default the issue
/// asked for, not a wasteful whole-DB replay every sync.
Future<void> _pushPendingProvenance(ApiClient api, Directory root) async {
  final stored = await readProvenance(root);
  final pending = stored.values.where((e) => !e.pushed).toList();
  if (pending.isEmpty) return;
  final merged = Map<int, ProvenanceRecord>.from(stored);
  for (var i = 0; i < pending.length; i += provenancePushMax) {
    final end = i + provenancePushMax < pending.length
        ? i + provenancePushMax
        : pending.length;
    final page = pending.sublist(i, end);
    await api.pushProvenance(page);
    for (final e in page) {
      merged[e.trackId] = e.copyWith(pushed: true);
    }
  }
  await writeProvenance(root, merged);
}

/// #77/#80 combined: fetch, then push whatever's now outstanding. The
/// one entry point _sync() in main.dart calls, as a best-effort step —
/// a provenance hiccup must never fail the sync itself.
Future<void> syncProvenance(ApiClient api, Directory root) async {
  await _fetchProvenance(api, root);
  await _pushPendingProvenance(api, root);
}
