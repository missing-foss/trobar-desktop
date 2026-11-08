// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// The one-time thank-you card on Home: once this install has finished
// [thanksCardSyncs] syncs with no error, until either of its buttons is
// pressed. Each such sync is also reported to the server, which counts them
// for its own card (shown to administrators in the web UI).

import 'package:flutter/material.dart';

import 'api_client.dart';
import 'app_prefs.dart';
import 'l10n/gen/app_localizations.dart';
import 'main.dart' show brandInk;

/// Successful syncs on this install before the card shows.
const thanksCardSyncs = 50;

/// Whether Home shows the card now.
bool showThanksCard(AppPrefs prefs) =>
    !prefs.thanksCardDone && prefs.syncsCompleted >= thanksCardSyncs;

/// Counts one sync that finished with no error, and tells the server.
/// The report is best-effort: an older server answers 404, and neither that
/// nor being offline may fail a sync that already succeeded.
Future<void> recordSuccessfulSync(AppPrefs prefs, ApiClient api) async {
  prefs.syncsCompleted++;
  try {
    await prefs.save();
  } catch (_) {
    // an unwritable prefs file loses one count, nothing more
  }
  try {
    await api.reportSyncCompleted();
  } catch (_) {
    // older server, or offline
  }
}

class ThanksCard extends StatelessWidget {
  /// Either button: the caller records it and hides the card.
  final VoidCallback onDone;

  /// Opens Ko-fi (the About screen's link, in the browser).
  final VoidCallback onSupport;

  const ThanksCard({super.key, required this.onDone, required this.onSupport});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    // Two sentences, each on its own line.
    final lines = [l.thanksCardSynced(thanksCardSyncs), l.thanksCardCoffee].join('\n');
    final heading = Theme.of(context).textTheme.titleLarge?.copyWith(
        fontFamily: 'Fredoka',
        fontWeight: FontWeight.w600,
        color: brandInk(context));
    return Card(
      key: const Key('thanksCard'),
      child: Stack(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${l.thanksCardThank} '),
                    TextSpan(
                        text: l.thanksCardYou,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.secondary)),
                  ]),
                  key: const Key('thanksCardHeading'),
                  textAlign: TextAlign.center,
                  style: heading,
                ),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Text(lines, key: const Key('thanksCardText')),
              const SizedBox(height: 14),
              Center(
                child: FilledButton(
                  onPressed: () {
                    onSupport();
                    onDone();
                  },
                  child: Text(l.supportOnKofi),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: IconButton(
            tooltip: l.dismiss,
            icon: const Icon(Icons.close),
            onPressed: onDone,
          ),
        ),
      ]),
    );
  }
}
