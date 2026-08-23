#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 missing-foss
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Pre-push verification gate for trobar-desktop. Run from the repo root:
#   dev/verify.sh
# Needs flutter on PATH.
#
# CI (.github/workflows/ci.yml) runs a SUBSET of what follows: analyze,
# tests, translations, gitleaks and REUSE. The hardcoded-UI-string check,
# the leak scan, the tracker-reference check and the toolchain-pin check
# run only here, so this script is the only place they happen at all.
set -uo pipefail
fail=0
step() { echo; echo "== $1 =="; }

step "flutter analyze"
flutter analyze && echo ok || fail=1

step "flutter test"
flutter test && echo ok || fail=1

step "translations (FR ARB complete, #32)"
# gen-l10n validates placeholder/ICU parity (it errors on a mismatch) and writes
# every untranslated key to the untranslated-messages-file set in l10n.yaml. The
# file is "{}" when complete and "{\"fr\": [...]}" when a key lacks its FR value,
# so a "[" means a gap — a new string then fails the build instead of shipping an
# English fallback in French.
if flutter gen-l10n; then
  if grep -q "\[" lib/l10n/untranslated.txt 2>/dev/null; then
    echo "UNTRANSLATED FR messages:"; cat lib/l10n/untranslated.txt; fail=1
  else
    echo ok
  fi
else
  echo "flutter gen-l10n failed (placeholder/ICU mismatch?)"; fail=1
fi

step "no hardcoded UI strings (must go through AppLocalizations) (#13)"
# A Text() built from a string literal bypasses l10n and renders in English
# regardless of locale (the sync dialogs did this). Native language names in
# the Settings language picker are the one legitimate exception.
if grep -rnE "Text\(\s*(const\s+)?['\"]" lib/ --include='*.dart' \
     | grep -v 'l10n/gen' \
     | grep -vE "Text\((const )?'(English|Français)'\)"; then
  echo "HARDCODED: localize the Text() string(s) above via AppLocalizations"; fail=1
else
  echo "ok"
fi

step "leak scan (strings that must never ship)"
# The pattern list is NOT in this repository. A denylist that ships the terms
# it exists to exclude publishes exactly what it is protecting -- which is what
# used to happen here. Supply one via LEAK_PATTERNS to run it; with no
# list configured this reports that it did not run rather than passing.
if [ -n "${LEAK_PATTERNS:-}" ] && [ -s "${LEAK_PATTERNS}" ]; then
  if git ls-files | xargs grep -InE -f "${LEAK_PATTERNS}" 2>/dev/null; then
    echo "LEAK: forbidden term(s) above"; fail=1
  else
    echo "ok"
  fi
else
  echo "SKIP (no LEAK_PATTERNS configured)"
fi

step "gitleaks (secrets)"
if command -v gitleaks >/dev/null 2>&1; then
  gitleaks git --no-banner . && echo ok || fail=1
else
  echo "SKIP (gitleaks not installed) — CI still runs it"
fi

step "REUSE (per-file SPDX licensing, #30)"
# Every file must declare copyright + license (inline SPDX header, or via
# REUSE.toml for binaries / generated / Flutter-scaffolding). A new unlicensed
# file then fails here rather than shipping unattributed.
if command -v reuse >/dev/null 2>&1; then
  if reuse lint >/dev/null 2>&1; then echo ok; else reuse lint | tail -20; fail=1; fi
else
  echo "FAIL: reuse is not installed (pipx install reuse) — the licensing check cannot run"; fail=1
fi

step "Tracker references in published prose"
# Public docs must stand alone: an issue number that outlives the tracker it
# points at is worse than no citation. Excludes fenced blocks, inline code, hex
# colours and heading anchors -- a guard that false-positives gets switched
# off, and then protects nothing.
if python3 dev/check-tracker-refs.py docs README.md SECURITY.md CONTRIBUTING.md; then
  echo ok
else
  fail=1
fi

echo
step "Toolchain pin agrees with CI"
# .tool-versions is the source of truth; CI must not drift from it. Deliberately
# a consistency check rather than making CI read the exact string: setup-java's
# acceptance of a "17.0.20+8" style version is not something this repo can test,
# and a check that both agree catches the drift either way.
if [ -f .tool-versions ]; then
  tv_java=$(awk '/^java /{print $2}' .tool-versions | sed 's/^temurin-//; s/\..*//')
  ci_java=$(grep -hoE 'java-version: *"?[0-9]+' .github/workflows/*.yml 2>/dev/null | grep -oE '[0-9]+' | sort -u)
  if [ -n "$tv_java" ] && [ -n "$ci_java" ] && [ "$tv_java" != "$ci_java" ]; then
    echo "PIN DRIFT: .tool-versions says java $tv_java, CI says $ci_java"; fail=1
  else
    echo ok
  fi
else
  echo "SKIP (no .tool-versions in this repo)"
fi

echo
if [ "$fail" -eq 0 ]; then echo "VERIFY OK"; else echo "VERIFY FAILED"; fi
exit "$fail"
