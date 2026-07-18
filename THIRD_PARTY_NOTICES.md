# Third-Party Notices — Trobar desktop

Trobar desktop's own code is `GPL-3.0-or-later` (see `LICENSE`). The
release tarballs additionally redistribute the components below, each
under its own license.

(Transcoding to MP3 is now done server-side, so no ffmpeg is bundled on any
platform — #15.)

## Flutter

The application embeds the Flutter engine (BSD-3-Clause, Copyright 2014
The Flutter Authors) and its Dart package dependencies. The complete,
auto-generated license collection for all of them ships inside every build
at `data/flutter_assets/NOTICES.Z` and is viewable programmatically via
Flutter's LicenseRegistry.

## Fonts and artwork

The bard artwork (`assets/logo_bard.png`) is original work, licensed with
the repository. No fonts are bundled beyond Flutter's Material icons
(Apache-2.0, part of the Flutter distribution above).
