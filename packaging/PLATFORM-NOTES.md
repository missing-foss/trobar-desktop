<!--
SPDX-FileCopyrightText: 2026 missing-foss

SPDX-License-Identifier: GPL-3.0-or-later
-->

# Platform packaging notes

Per-platform setup that isn't obvious from the Dart code, for whoever cuts a
release. Currently this is all about the **completion notification** (#24) —
`notifyIfUnfocused` posts a local OS notification when a sync finishes and the
window isn't focused. It swallows failures, so a misconfigured platform fails
*silently* (no toast) rather than crashing — which is why each platform needs a
real-device check.

## Linux

- **Runtime dependency: `libnotify`** (`libnotify.so.4`). It's linked at load
  time, so the app **won't start** without it — `install.sh` warns if it's
  missing, and the README documents it (Debian/Ubuntu `libnotify4`, Fedora
  `libnotify`). See #48.
- Delivery works out of the box on any desktop with a notification daemon
  (GNOME/KDE/etc.) — verified on the build host.

## macOS

- `local_notifier` 0.1.6 delivers via the legacy **`NSUserNotification`** API.
  That path **does not prompt for permission** and needs no notification-specific
  entitlement — only a valid bundle identifier (`com.mfoss.trobarDesktop`, set)
  and the app-sandbox entitlement (present). So no first-run permission dialog is
  expected.
- **Still needs a real-Mac check:** `NSUserNotification` is deprecated; confirm a
  toast actually appears on a current macOS (12+) from the packaged `.app` with
  the window unfocused. If Apple has made it a no-op on the target OS, the fix
  is to move the plugin (or a fork) to `UNUserNotificationCenter` +
  `requestAuthorization`.
- **Network entitlement (#52):** `com.apple.security.network.client` is set in
  both `Debug`/`Release.entitlements` — the App Sandbox requires it for the
  outbound HTTP the sync uses. It's inert on the current **unsigned** builds
  (the sandbox isn't enforced) but load-bearing once the app is code-signed.
  **Still to confirm at signing time:** that a signed build actually completes a
  sync (the sandbox can only be exercised once signed).

## Windows

- **Runtime dependency: the Visual C++ Redistributable** (`msvcp140.dll`,
  `vcruntime140.dll`, `vcruntime140_1.dll`) — linked at load time by every
  Flutter Windows release build, same failure shape as Linux's `libnotify`
  above (app won't start without it). Not part of a base Windows install.
  `.github/workflows/release.yml`'s `build-windows` job now copies these
  app-local into the Release folder before zipping, so the published zip
  is self-contained (#63) — see `THIRD_PARTY_NOTICES.md`.
- Toasts use WinToast, which needs an **AppUserModelID**. `localNotifier.setup`
  is called with **`ShortcutPolicy.requireCreate`** (explicit in `main.dart`),
  which creates a Start-menu shortcut carrying that identity — so toasts work
  from the **packaged** build.
- **Still needs a real-Windows check:** toast identity differs between
  `flutter run` and a packaged build, so confirm on the **zip artifact** (not a
  dev run), window unfocused, that the toast shows. First run may need the
  shortcut to register; a second launch is a fair test if the first is silent.

## Status

| Platform | Notification delivery |
|----------|-----------------------|
| Linux    | ✅ verified on the build host |
| macOS    | ⏳ needs a real-Mac check (config prepared; no prompt expected) |
| Windows  | ⏳ needs a real-Windows check on the packaged build (shortcut auto-created) |
