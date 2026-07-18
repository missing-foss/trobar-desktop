#!/usr/bin/env bash
# Package the Linux x64 release tarball: the Flutter bundle plus the license
# files. Transcoding is done server-side now, so nothing else is bundled — no
# ffmpeg, no GPL redistributable to maintain (#15). Run from desktop/:
#
#   packaging/package-linux.sh <version>
#
# e.g. packaging/package-linux.sh 0.6.2
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

tar czf "$OUT.tar.gz" -C "$STAGE" .
echo "wrote $OUT.tar.gz"
