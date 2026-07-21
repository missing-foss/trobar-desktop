<!--
SPDX-FileCopyrightText: 2026 missing-foss

SPDX-License-Identifier: GPL-3.0-or-later
-->

# Trobar desktop

[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/missing-foss/trobar-desktop/badge)](https://securityscorecards.dev/viewer/?uri=github.com/missing-foss/trobar-desktop)

Flutter app (Linux / macOS / Windows) that syncs
[Trobar](https://github.com/missing-foss/trobar-server) library selections
onto SD cards, USB drives, and local folders — the client for network-less
DAPs that only ever see a card.

## Install

Grab the build for your OS from Releases (tags `desktop-vX.Y.Z`):

- **Linux x64**: tarball — untar and run `./trobar_desktop` (glibc 2.39+).
  Requires **`libnotify`** at runtime (for completion notifications) —
  Debian/Ubuntu `libnotify4`, Fedora `libnotify`. It's present on virtually
  every desktop Linux (GNOME/KDE pull it in); on a minimal system without it
  the app won't start, so install it first. `./install.sh` checks for it.
- **Windows / macOS**: zip — unzip and run. No external dependencies
  (transcoding is handled by the server, so ffmpeg is no longer needed on
  any platform). These builds are **unsigned**: Windows SmartScreen will
  warn ("Windows protected your PC" → More info → Run anyway), and macOS
  Gatekeeper will refuse to open it until you right-click → Open (or allow
  it under System Settings → Privacy & Security). No code-signing
  cert / Apple notarization yet — both are paid, out of scope for now.

On older Linux distributions, or if you'd rather build it yourself, see
Build below.

## How it works

The pairing lives **on the card** (`.trobar/device.json`), so any machine
running this app recognises it and syncs it as the right device — the app
stores nothing per-device. Sync is the same server-driven diff the Android app
uses (the server computes what the card is missing; files are written
atomically and acked with the real byte count), and **transcoding is
server-side** — the client just downloads whatever it's served. The full model
(sync protocol, on-device naming, playlists, artist pictures) is in the
[Desktop client guide](https://missing-foss.github.io/trobar-server/clients/desktop/).

> **Security:** the pairing token is stored in plaintext on the card so it
> travels with it — treat a lost or stolen card as a credential to revoke
> (regenerate it under *Profile → Devices* in the web app). See
> [SECURITY.md](SECURITY.md).

## Develop

```
flutter pub get
flutter test
flutter run -d linux    # or macos / windows
```

## Build

```
flutter build linux     # bundle in build/linux/x64/release/bundle/
flutter build macos
flutter build windows
```

The UI is available in English and French (follows the system locale).

## License

Licensed `GPL-3.0-or-later` (see [LICENSE](LICENSE)), same as the Android
client. Bundled third-party components (the Flutter engine and Dart
packages) keep their own licenses — see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
