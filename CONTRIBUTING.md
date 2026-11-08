<!--
SPDX-FileCopyrightText: 2026 missing-foss

SPDX-License-Identifier: GPL-3.0-or-later
-->

# Contributing

This is the desktop client of Trobar — the contribution guidelines,
issue tracker conventions, and dev-environment notes live in the main
server repository's `CONTRIBUTING.md` and `docs/`. Short version: open an
issue before large PRs, AI-assisted patches are fine if you say so in the PR,
`dev/verify.sh` must pass, contributions are `GPL-3.0-or-later` like the
client itself.

`dev/verify.sh` runs `flutter analyze`, `flutter test` and the repository's
other checks (translations, brand colours, licensing headers, secrets). CI runs
them too, so running it before you push saves a round trip. It needs `flutter`,
`python3` and `reuse` (`pipx install reuse`) and fails without them. Without
`gitleaks` it reports SKIP for the secret scan, which CI still runs.

Public issues and PRs live here on GitHub.

Pull requests opened here are reviewed and then shipped by the maintainers
rather than merged in place, so your commits may arrive under a release
commit rather than your own. Your pull request is closed with a note
crediting you when the change lands. Keep changes focused — a small pull
request with a clear rationale is much easier to take than a large one.

Contributing a translation? See [Translating Trobar](https://missing-foss.github.io/trobar-server/project/translations/).

Security issues: not in the public tracker — missing_foss@etik.com.
