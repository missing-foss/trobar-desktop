#!/usr/bin/env bash
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

step "leak scan (household infra must never ship)"
if git ls-files | xargs grep -InE "mphp|soundsync|renoir|192\.168\.50|/nfs/" 2>/dev/null \
     | grep -viE "\.lock$|workflows/ci\.yml|dev/verify\.sh"; then
  echo "LEAK: forbidden term(s) above"; fail=1
else
  echo "ok"
fi

step "gitleaks (secrets)"
if command -v gitleaks >/dev/null 2>&1; then
  gitleaks git --no-banner . && echo ok || fail=1
else
  echo "SKIP (gitleaks not installed) — CI still runs it"
fi

echo
if [ "$fail" -eq 0 ]; then echo "VERIFY OK"; else echo "VERIFY FAILED"; fi
exit "$fail"
