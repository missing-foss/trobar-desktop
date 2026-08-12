#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 missing-foss
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Pre-push verification gate for trobar-desktop. Run from the repo root:
#   dev/verify.sh
# CI (.github/workflows/ci.yml) runs the same checks. Needs flutter on PATH.
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
# Patterns come from two files: dev/forbidden-terms.txt, committed and shared
# by every checkout, plus dev/forbidden-terms.local.txt, gitignored and
# optional, for terms that only make sense on one machine. Both are stripped of
# comments and blank lines before grep sees them — a `-f` list takes every line
# as a pattern, and an empty one matches every file in the repo.
# #404: `grep -f` on a missing terms file exits 2 (swallowed by 2>/dev/null
# below), the `if` is then false, and this printed "ok" having scanned
# nothing — fail-open, not fail-safe. `-s` catches missing AND empty in one
# test, skipping the grep entirely so this doesn't ALSO scan (and pass)
# against a pattern file with nothing in it.
_terms=$(mktemp)
cat dev/forbidden-terms.txt dev/forbidden-terms.local.txt 2>/dev/null \
  | grep -vE '^[[:space:]]*(#|$)' > "$_terms"
if [ ! -s dev/forbidden-terms.txt ]; then
  echo "LEAK: dev/forbidden-terms.txt missing or empty — scan did not run"; fail=1
elif [ ! -s "$_terms" ]; then
  echo "LEAK: no patterns left after stripping comments — scan did not run"; fail=1
elif git ls-files | xargs grep -InE -f "$_terms" 2>/dev/null \
     | grep -viE "\.lock$|^dev/forbidden-terms\.txt:"; then
  echo "LEAK: forbidden term(s) above"; fail=1
else
  echo "ok"
fi
rm -f "$_terms"

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
  echo "SKIP (reuse not installed — pipx install reuse) — CI still runs it"
fi

echo
if [ "$fail" -eq 0 ]; then echo "VERIFY OK"; else echo "VERIFY FAILED"; fi
exit "$fail"
