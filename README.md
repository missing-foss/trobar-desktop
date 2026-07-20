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

- The pairing token lives **on the card**: `.trobar/device.json` at the card
  root, written once from the device config file the web app offers at
  device creation. Any machine running this app recognises the card and
  syncs it as the right device; the app itself stores nothing per-device.
- Sync is the same server-driven diff the Android app uses: the server
  computes what the card is missing (`/api/device/changes`), files are
  written atomically (`.part` + rename), each track is acked with the real
  byte count written, deletions prune now-empty album/artist folders, and
  files the server expected but finds missing trigger the re-download /
  leave-deleted choice.
- **Transcoding is server-side**: if the device is set to an MP3 format in
  the web app, the server converts lossless sources (FLAC/WAV/AIFF) to MP3
  320/256/192/128 kbit/s on demand and streams the converted bytes — the
  client just downloads whatever it's served (no local ffmpeg). Changing the
  device's format re-syncs it under the new file names.
- On-device names come from the server and are already FAT/exFAT/Windows
  safe — the client never invents its own naming.
- Playlist selections arrive as .m3u8 files at the card root (same name,
  same order, local tracks only); files carrying the Trobar marker line are
  refreshed/removed as assignments change, hand-made playlists are never
  touched.
- Artist pictures (if enabled for the device) are written as `artist.jpg`
  into each artist folder.

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
