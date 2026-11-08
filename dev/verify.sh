#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 missing-foss
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Pre-push verification gate for trobar-desktop. Run from the repo root:
#   dev/verify.sh
# Needs flutter on PATH.
#
# CI (.github/workflows/ci.yml) runs every step below except two, which run
# only here: the leak scan, whose pattern list is not public, and the
# toolchain-pin check.
set -uo pipefail
fail=0
step() { echo; echo "== $1 =="; }

step "brand colours (generated, WCAG AA)"
# lib/brand_tokens.dart is generated from brand/trobar-themes.json by
# tool/gen_brand_tokens.py. Fails when it is stale or any theme's derived
# scheme puts a text/background pair under WCAG AA.
python3 tool/gen_brand_tokens.py --check || fail=1

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
# A `-f` list has no comment syntax and no blank-line syntax: grep takes every
# line in the file as a pattern, including the ones a human wrote as structure.
# So anything not meant as a pattern is stripped before grep sees the list. If
# stripping leaves nothing the list is malformed, and that fails loudly rather
# than scanning against an empty pattern set and reporting "ok". The count is
# printed on success so a list that quietly shrinks is visible.
# The filtered list is fed to grep through process substitution and never
# written to disk. A 0600 file removed on EXIT is still a copy of a list whose
# one handling rule is that it is not copied, and EXIT does not run on SIGKILL,
# on a full disk, or when a CI container is torn down mid-step. This removes
# the cleanup path rather than managing it.
# ONE grep invocation, deliberately. `git ls-files | xargs grep` may run grep
# several times: a temp file is re-opened by each, but a process substitution
# is a pipe and is drained by the first, so later batches would scan against an
# empty pattern set and report clean -- no error, no change in exit status. The
# file list is passed as arguments instead, in an array so paths containing
# spaces survive. Should that list ever outgrow ARG_MAX, this fails loudly with
# E2BIG rather than quietly under-scanning.
if [ -n "${LEAK_PATTERNS:-}" ] && [ -s "${LEAK_PATTERNS}" ]; then
  mapfile -t leak_files < <(git ls-files)
  leak_n=$(grep -vcE '^[[:space:]]*(#|$)' "${LEAK_PATTERNS}")
  if [ "${#leak_files[@]}" -eq 0 ]; then
    # grep with no file operands reads stdin: it would hang rather than scan,
    # and a scan of zero files reporting "ok" would be vacuous either way.
    echo "FAIL: no tracked files to scan"; fail=1
  elif [ "${leak_n:-0}" -eq 0 ]; then
    echo "FAIL: pattern list has no usable patterns (comments and blanks only)"; fail=1
  else
    # grep exits 0 on match, 1 on no match, and 2 on error. An `if` reads 1 and
    # 2 alike, so a tracked file missing from the working tree -- an ordinary
    # mid-edit state -- turned a found leak into "ok": the match was printed and
    # the step still passed. Branch on the status so an incomplete scan fails
    # loudly instead of reporting a clean tree it never finished reading.
    grep -InE -f <(grep -vE '^[[:space:]]*(#|$)' "${LEAK_PATTERNS}") -- "${leak_files[@]}"
    leak_rc=$?
    case "$leak_rc" in
      0) echo "LEAK: forbidden term(s) above"; fail=1 ;;
      1) echo "ok ($leak_n patterns)" ;;
      *) echo "FAIL: leak scan errored (grep exit $leak_rc) -- scanned set incomplete"; fail=1 ;;
    esac
  fi
else
  echo "SKIP (no LEAK_PATTERNS configured)"
fi

step "gitleaks (secrets)"
if command -v gitleaks >/dev/null 2>&1; then
  _g=$(gitleaks git --no-banner . 2>&1); _rc=$?
  printf '%s\n' "$_g"
  # gitleaks reports how many commits it scanned; zero is a pass over nothing.
  _n=$(printf '%s' "$_g" | sed -n 's/.*[^0-9]\([0-9][0-9]*\) commits scanned.*/\1/p' | tail -1)
  if [ "$_rc" -ne 0 ]; then fail=1
  elif [ -z "$_n" ]; then
    echo "FAIL: gitleaks exited 0 but its commit count could not be read -- output format changed?"; fail=1
  elif [ "$_n" -eq 0 ]; then echo "FAIL: gitleaks scanned 0 commits"; fail=1
  else echo "ok ($_n commits scanned)"; fi
else
  echo "SKIP (gitleaks not installed) — CI still runs it"
fi

step "REUSE (per-file SPDX licensing, #30)"
# Every file must declare copyright + license (inline SPDX header, or via
# REUSE.toml for binaries / generated / Flutter-scaffolding). A new unlicensed
# file then fails here rather than shipping unattributed.
if command -v reuse >/dev/null 2>&1; then
  _r=$(reuse lint 2>&1); _rc=$?
  # reuse reports "Files with copyright information: N / M". A lint over zero
  # files is a pass over nothing, and is reported as such.
  _n=$(printf '%s' "$_r" | sed -n 's/.*Files with copyright information: \([0-9][0-9]*\) \/ [0-9][0-9]*.*/\1/p' | tail -1)
  _d=$(printf '%s' "$_r" | sed -n 's/.*Files with copyright information: [0-9][0-9]* \/ \([0-9][0-9]*\).*/\1/p' | tail -1)
  if [ "$_rc" -ne 0 ]; then printf '%s\n' "$_r" | tail -20; fail=1
  elif [ -z "$_n" ]; then
    echo "FAIL: reuse exited 0 but its file count could not be read -- output format changed?"; fail=1
  elif [ "$_n" -eq 0 ]; then echo "FAIL: reuse checked 0 files"; fail=1
  else echo "ok ($_n/$_d files)"; fi
else
  echo "FAIL: reuse is not installed (pipx install reuse) — the licensing check cannot run"; fail=1
fi

step "vendored guards match their declared versions"
# The guards below are copies of missing-foss/dev-guards. This recomputes each
# one's hash and compares it to the version this repository claims, so a guard
# edited in place -- or left behind when the canonical copy moved on -- is a red
# check rather than a silent fork. Six copies of one guard drifting, with
# nothing reporting it, is why the canonical repository exists.
dev/guards/verify-vendored.sh || fail=1

step "Tracker references in published prose"
# Public docs must stand alone: an issue number that outlives the tracker it
# points at is worse than no citation. Excludes fenced blocks, inline code, hex
# colours and heading anchors -- a guard that false-positives gets switched
# off, and then protects nothing.
if python3 dev/guards/check-tracker-refs.py; then
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
  # renovate.json's constraints.flutter is the Flutter Renovate regenerates
  # pubspec.lock with; it cannot read .tool-versions itself.
  tv_flutter=$(awk '/^flutter /{print $2}' .tool-versions)
  rn_flutter=$(python3 -c 'import json; print(json.load(open("renovate.json")).get("constraints", {}).get("flutter", ""))' 2>/dev/null)
  if [ -n "$tv_java" ] && [ -n "$ci_java" ] && [ "$tv_java" != "$ci_java" ]; then
    echo "PIN DRIFT: .tool-versions says java $tv_java, CI says $ci_java"; fail=1
  elif [ -f renovate.json ] && [ "$tv_flutter" != "$rn_flutter" ]; then
    echo "PIN DRIFT: .tool-versions says flutter $tv_flutter, renovate.json constraints say '${rn_flutter}'"; fail=1
  else
    echo "ok (flutter $tv_flutter in .tool-versions and renovate.json)"
  fi
else
  echo "SKIP (no .tool-versions in this repo)"
fi

echo
if [ "$fail" -eq 0 ]; then echo "VERIFY OK"; else echo "VERIFY FAILED"; fi
exit "$fail"
