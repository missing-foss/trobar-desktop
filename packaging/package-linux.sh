#!/usr/bin/env bash
# Package the Linux x64 release tarball: Flutter bundle + static
# ffmpeg + the license files GPL distribution requires. Run from desktop/:
#
#   packaging/package-linux.sh <version> <path-to-static-ffmpeg>
#
# e.g. packaging/package-linux.sh 0.6.2 ~/ffmpeg-7.0.2-amd64-static/ffmpeg
#
# If the bundled ffmpeg build ever changes, refresh BOTH files in
# packaging/licenses/ from the new build's archive (GPLv3.txt and its
# readme.txt) and the version note in THIRD_PARTY_NOTICES.md.
set -euo pipefail

VERSION="${1:?usage: package-linux.sh <version> <ffmpeg-binary>}"
FFMPEG="${2:?usage: package-linux.sh <version> <ffmpeg-binary>}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE="$HERE/build/linux/x64/release/bundle"
OUT="trobar-desktop-$VERSION-linux-x64"

[ -x "$FFMPEG" ] || { echo "not an executable: $FFMPEG" >&2; exit 1; }
(cd "$HERE" && flutter build linux --release)

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -r "$BUNDLE"/. "$STAGE/"
install -m 0755 "$FFMPEG" "$STAGE/ffmpeg"
mkdir -p "$STAGE/licenses"
cp "$HERE/packaging/licenses/"* "$STAGE/licenses/"
cp "$HERE/THIRD_PARTY_NOTICES.md" "$STAGE/licenses/"
cp "$HERE/LICENSE" "$STAGE/licenses/LICENSE"

tar czf "$OUT.tar.gz" -C "$STAGE" .
echo "wrote $OUT.tar.gz"
