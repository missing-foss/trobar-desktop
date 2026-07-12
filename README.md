# Trobar desktop

Flutter app (Linux / macOS / Windows) that syncs
[Trobar](https://github.com/missing-foss/trobar-server) library selections
onto SD cards, USB drives, and local folders — the client for network-less
DAPs that only ever see a card, and the only client that transcodes.

## Install

Grab the build for your OS from Releases (tags `desktop-vX.Y.Z`):

- **Linux x64**: tarball, ffmpeg bundled — untar and run `./trobar_desktop`
  (glibc 2.39+).
- **Windows / macOS**: zip, ffmpeg **not** bundled — install ffmpeg
  yourself (`winget install ffmpeg` / `brew install ffmpeg`) and make sure
  it's on your `PATH`; transcoding is skipped otherwise. Bundling a
  redistributable, correctly-licensed static ffmpeg is only sorted out for
  Linux today (see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)) — it's
  a deliberate scope cut, not an oversight, revisit if it becomes annoying.
  These builds are also **unsigned**: Windows SmartScreen will warn
  ("Windows protected your PC" → More info → Run anyway), and macOS
  Gatekeeper will refuse to open it until you right-click → Open (or allow
  it under System Settings → Privacy & Security). No code-signing
  cert / Apple notarization yet — both are paid, out of scope for now.

On older Linux distributions, or if you'd rather build it yourself, see
Build below; the app always falls back to ffmpeg on `PATH` when none is
bundled.

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
- **Transcoding**: if the device is set to an MP3 format in the web app,
  lossless sources (FLAC/WAV/AIFF) are converted on this machine at sync
  time — MP3 320/256/192/128 kbit/s, tags and embedded cover art carried
  over. The server always sends originals and stores nothing transcoded.
  Changing the device's format re-syncs it under the new file names.
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
client. Bundled third-party components (the static ffmpeg in release
tarballs, Flutter engine, Dart packages) keep their own licenses — see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
