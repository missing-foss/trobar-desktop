# Third-Party Notices — Trobar desktop

Trobar desktop's own code is `GPL-3.0-or-later` (see `LICENSE`). The
release tarballs additionally redistribute the components below, each
under its own license.

## ffmpeg (Linux release tarballs only)

The Linux x64 tarball bundles a **static ffmpeg binary** (currently
7.0.2), built by John Van Sickle (https://johnvansickle.com/ffmpeg/) and
licensed under the **GNU General Public License version 3**. The tarball's
`licenses/` folder carries the license text (`ffmpeg-GPL-3.0.txt`) and the
build's own `ffmpeg-static-readme.txt` (exact library versions). Sources:
ffmpeg at https://ffmpeg.org/download.html, the static build's source
notes at the builder's page above; we will provide the corresponding
source for the bundled build on request (missing_foss@etik.com).

Builds from source use whatever ffmpeg is on your PATH instead — nothing
is bundled in that case.

**Windows and macOS release zips do not bundle ffmpeg either** — same
PATH-based fallback as a source build. This is a deliberate decision, not
an oversight: a redistributable static ffmpeg build exists for Linux
(above) with its licensing already sorted (GPLv3 notice + source offer),
but Windows and macOS builds are sourced from different providers with
their own licensing to verify and their own notice/source-offer text to
maintain per platform. Doing that properly for two more platforms was
scoped out of the initial Windows/macOS release automation
(missing-foss/trobar-desktop#2) to ship unsigned builds without also
taking on a second and third GPL redistribution obligation at the same
time. Revisit if users hit this often enough to be worth it.

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
