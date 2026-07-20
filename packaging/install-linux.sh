#!/usr/bin/env bash
# XDG user-install for Trobar — no root needed. Run from the extracted tarball:
#
#   ./install.sh
#
# Installs the app under ~/.local/lib/trobar-desktop, drops an icon into the
# hicolor theme, and registers a menu launcher (Exec pointed at the installed
# binary). Uninstall: rm -rf the three paths echoed at the end.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
APPDIR="$HOME/.local/lib/trobar-desktop"
APPS_DIR="$DATA_HOME/applications"
HICOLOR="$DATA_HOME/icons/hicolor"
ICON_DIR="$HICOLOR/512x512/apps"
DESKTOP="$APPS_DIR/com.mfoss.trobar_desktop.desktop"
ICON="$ICON_DIR/com.mfoss.trobar_desktop.png"

mkdir -p "$APPDIR" "$APPS_DIR" "$ICON_DIR"

# App payload: everything in the tarball except the packaging helpers.
rm -rf "${APPDIR:?}"/*
for item in "$HERE"/*; do
  case "$(basename "$item")" in
    share|install.sh) continue ;;
    *) cp -r "$item" "$APPDIR/" ;;
  esac
done

install -m644 "$HERE/share/icons/hicolor/512x512/apps/com.mfoss.trobar_desktop.png" "$ICON"

# Register the launcher with Exec resolved to the installed binary.
sed "s|^Exec=.*|Exec=$APPDIR/trobar_desktop|" \
    "$HERE/share/applications/com.mfoss.trobar_desktop.desktop" > "$DESKTOP"
chmod 644 "$DESKTOP"

command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS_DIR" 2>/dev/null || true
command -v gtk-update-icon-cache  >/dev/null 2>&1 && gtk-update-icon-cache -f -t "$HICOLOR" 2>/dev/null || true

echo "Installed Trobar:"
echo "  app      $APPDIR"
echo "  launcher $DESKTOP"
echo "  icon     $ICON"
