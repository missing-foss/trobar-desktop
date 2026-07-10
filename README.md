# Trobar desktop

Flutter app (Linux / macOS / Windows) that syncs Trobar library selections
onto SD cards and local folders — the client for network-less DAPs that
only ever see a card.

Status: gitea#2 **M2 skeleton** — pairing + plain-copy sync. Transcoding
(`transcode_format` devices) is detected but skipped until M3 brings ffmpeg.

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
  leave-deleted choice (gitea#49).
- On-device names come from the server and are already FAT/exFAT/Windows
  safe — the client never invents its own naming.
- Playlist selections arrive as .m3u8 files at the card root (same name,
  same order, local tracks only); files carrying the Trobar marker line are
  refreshed/removed as assignments change, hand-made playlists are never
  touched.

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

Licensed GPL-3.0-or-later (see LICENSE), same as the Android client.
