// SPDX-FileCopyrightText: 2026 missing-foss
// SPDX-License-Identifier: GPL-3.0-or-later
// #24: a local OS notification on sync completion when the app window isn't
// focused — so a long sync that finishes while the user is in another app
// still signals. Local only: nothing is phoned home (the no-telemetry stance).
// The plugin surface (local_notifier + window_manager) is confined to this file.

import 'package:local_notifier/local_notifier.dart';
import 'package:window_manager/window_manager.dart';

/// Show a desktop notification, but only when the window isn't focused — if the
/// user is looking at the app, the in-app summary already told them. Failures
/// (unsupported platform, missing libnotify) are swallowed: a notification is a
/// nicety, never a reason to break a sync.
Future<void> notifyIfUnfocused(String title, String body) async {
  try {
    if (await windowManager.isFocused()) return;
    await LocalNotification(title: title, body: body).show();
  } catch (_) {
    // best-effort only
  }
}
