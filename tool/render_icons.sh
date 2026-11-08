#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 missing-foss
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Renders the OS app icons from brand/trobar-mark-troubadour.svg (a copy of
# trobar-server's brand/svg/mark/): the macOS appiconset, the Windows .ico and
# the Linux hicolor icon. The OS icon is the Troubadour mark whatever theme the
# app is in.
#
#   tool/render_icons.sh
#
# Needs rsvg-convert and ImageMagick's convert. Without them, and with docker
# available, it runs itself in ubuntu:22.04 with both installed.
set -euo pipefail
cd "$(dirname "$0")/.."

src="brand/trobar-mark-troubadour.svg"
mac="macos/Runner/Assets.xcassets/AppIcon.appiconset"
ico="windows/runner/resources/app_icon.ico"
linux="packaging/icons/org.missing_foss.trobar_desktop.png"

if ! command -v rsvg-convert >/dev/null 2>&1 || ! command -v convert >/dev/null 2>&1; then
  if [ -n "${TROBAR_IN_RENDER_CONTAINER:-}" ] || ! command -v docker >/dev/null 2>&1; then
    echo "needs rsvg-convert and ImageMagick (or docker to run them in)" >&2
    exit 2
  fi
  tag="trobar-brand-render:local"
  printf 'FROM ubuntu:22.04\nRUN apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends librsvg2-bin imagemagick && rm -rf /var/lib/apt/lists/*\n' \
    | docker build -q -t "$tag" - >/dev/null
  # Renders into the container's own scratch directory and hands the files
  # back as a tar, so it never writes into the checkout itself.
  docker run --rm -e TROBAR_IN_RENDER_CONTAINER=1 -v "$PWD:/repo:ro" -w /repo "$tag" \
    sh -c 'mkdir -p /tmp/out && OUT=/tmp/out tool/render_icons.sh >&2 && tar -C /tmp/out -cf - .' \
    | tar -C . -xf -
  echo "rendered the app icons (in docker)"
  exit 0
fi

out="${OUT:-.}"
mkdir -p "$out/$mac" "$out/$(dirname "$ico")" "$out/$(dirname "$linux")"
# Rendered large and scaled down; -strip keeps timestamps out, so an
# unchanged mark renders byte-identical files.
big="$(mktemp --suffix=.png)"
rsvg-convert -w 2048 -h 2048 "$src" -o "$big"
for s in 16 32 64 128 256 512 1024; do
  convert "$big" -resize "${s}x${s}" -strip "PNG32:$out/$mac/app_icon_$s.png"
done
convert "$big" -define icon:auto-resize=256,128,64,48,32,24,16 -strip "$out/$ico"
convert "$big" -resize 512x512 -strip "PNG32:$out/$linux"
rm -f "$big"
echo "rendered $mac, $ico and $linux"
