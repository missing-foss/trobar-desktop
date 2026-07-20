#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 missing-foss
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Package the Linux x64 release tarball: the Flutter bundle, the license files,
# and XDG desktop integration (#21 — menu launcher + hicolor icon + install.sh,
# since macOS/Windows ship icons in their runners but Linux had none).
# Transcoding is done server-side now, so nothing else is bundled — no ffmpeg,
# no GPL redistributable to maintain (#15). Run from desktop/:
#
#   packaging/package-linux.sh <version>
#
# e.g. packaging/package-linux.sh 0.6.2
# The user then extracts and runs ./install.sh (XDG user-install, no root).
set -euo pipefail

VERSION="${1:?usage: package-linux.sh <version>}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE="$HERE/build/linux/x64/release/bundle"
OUT="trobar-desktop-$VERSION-linux-x64"

(cd "$HERE" && flutter build linux --release)

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -r "$BUNDLE"/. "$STAGE/"
mkdir -p "$STAGE/licenses"
cp "$HERE/THIRD_PARTY_NOTICES.md" "$STAGE/licenses/"
cp "$HERE/LICENSE" "$STAGE/licenses/LICENSE"

# XDG desktop integration (#21): staged under share/ in the standard hicolor
# layout; install.sh wires them into the user's ~/.local at install time.
mkdir -p "$STAGE/share/applications" "$STAGE/share/icons/hicolor/512x512/apps"
cp "$HERE/packaging/com.mfoss.trobar_desktop.desktop" "$STAGE/share/applications/"
cp "$HERE/assets/logo_bard.png" "$STAGE/share/icons/hicolor/512x512/apps/com.mfoss.trobar_desktop.png"
cp "$HERE/packaging/install-linux.sh" "$STAGE/install.sh"
chmod +x "$STAGE/install.sh"

tar czf "$OUT.tar.gz" -C "$STAGE" .
echo "wrote $OUT.tar.gz"
