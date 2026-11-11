# releases: repo rules

Signed, one-line installs for every Nomadware package, served from https://releases.nomadware.io.
This repo is the one publisher every package goes through. Overview and layout: [README.md](README.md).

This file adds only what is specific to releases. The cross-repo rules are the owner's global
agent rules (devbox `agents/AGENTS.md`). This repo is **public**: GitHub Actions is its CI.

## Routing

| Occasion | Doc | Guardrail |
|---|---|---|
| Find where something lives | [README.md § Layout](README.md#layout) | `<pkg>/<tag>/` is written once, never rewritten; only `<pkg>/install.sh` and `<pkg>/latest` are overwritten |
| Publish a release | [README.md § Publishing a release](README.md#publishing-a-release) | Pin `fum4/releases@<full commit sha>` (the step holds the signing key); the job runs on the tag push only, never on `pull_request` |
| Add a package (CLI, desktop or legacy) | [README.md § Adding a package](README.md#adding-a-package), [§ Desktop packages](README.md#desktop-packages) | One line in `packages`; a setup step is words of lowercase letters, digits and dashes, never shell |
| Change the installer or the index page | `templates/`, [ledger/backlog.md](ledger/backlog.md) § Top bar and terminal sync | Edit the template, never the rendered page; the top bar and terminal are copies of nomadware.io's, keep them in step |
| Touch a secret or a package repo's Actions secrets | [secrets/README.md](secrets/README.md) | Age-encrypted only; package repos get them via `mise run secrets:gh-push`, never typed by hand |
| Change the repo ruleset | `infra/github/` (`mise run tf:github -- plan`) | CI's `check` is the required check; renaming the job is a ruleset change in the same PR |
| Run the checks | [README.md § Checks](README.md#checks) | CI (`check`) is the gate; the box's `pre-push` / `pre-merge` are fast feedback |
| File a follow-up | [ledger/backlog.md](ledger/backlog.md) | `## <title> · <YYYY-MM-DD> · S\|M\|L`; owner asks are files in `ledger/asks/` |

## Asks and decisions

About to ask the owner anything, just chose between options, or just heard a decision → the
`cerebro-ledger` skill: it's a file in the repo (`ledger/asks/`, `docs/decisions/log/`), not a
chat message, even if the skill didn't fire.

## Merging

Agents may merge here (`[merge] by = "agents"` in [cerebro/repo.toml](cerebro/repo.toml)): PR,
then CI's `check` and `wt pre-merge` green, then `wt merge`. A PR touching an `approval_paths`
entry needs the owner's go.
