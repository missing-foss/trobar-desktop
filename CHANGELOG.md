<!--
SPDX-FileCopyrightText: 2026 missing-foss

SPDX-License-Identifier: GPL-3.0-or-later
-->

# Changelog

What changed for someone using Trobar desktop, by version, in the
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) shape. A release's date
is its tag's. Versions before 0.11.0 are in the git log.

## [Unreleased]

## [0.12.0]

### Added

- Pair with a short enrollment code.
- Stop a sync, and leave during one without breaking it.
- A failed download is tried again, and an original resumes where it stopped.
- Playlists made on the card are sent to the server.
- Last sync says what became of the playlists and where unknown entries went.
- Automatic syncs say what they left undecided, and orphans can be picked one by
  one.
- A card's space is reported on Windows.
- A one-time thank-you card on Home, after 50 successful syncs.
- The Occitan rosette and five themes.

### Changed

- Cards are found when the system says a volume arrived, not by probing every
  8 seconds.
- An unattended sync decides nothing for you.
- A sync says up front when the downloads can't fit, and stops when the card fills.
- A stalled server times out instead of syncing forever, and a refused pairing
  says so and offers to pair again.
- Dates follow your language, with decimal commas and plurals that agree.
- AIFF counts as audio on the card, and `.alac` is dropped.
- macOS: the build you download isn't sandboxed any more, so it can still find
  your cards wherever macOS mounts them once it is signed.
- Support links go to Ko-fi, with a line saying what the money pays for.

### Fixed

- A playlist you made on the card is never offered for deletion.
- On Windows, no dialog for an empty drive, and only a removable drive root
  counts as removable.
- One scan runs at a time, each folder has a time limit, and the right user is
  used under sudo.
- Two volume arrivals close together both stay listed.

## [0.11.0]

### Added

- Local folder sync targets are discovered and remembered.
- A device manifest is uploaded right after a fresh pairing, and recovery keeps
  going across retries.

### Fixed

- The Material icons font is credited under its real licence, CC BY 4.0.
