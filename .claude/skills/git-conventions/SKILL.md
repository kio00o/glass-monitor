---
name: git-conventions
description: Glass Monitor git conventions — branch names, commit messages, pull requests, and the release steps (version bump, DMG, tag, GitHub Release). Use when creating a branch, writing a commit or PR, or cutting a release.
---

# Git Conventions

Flow: a branch from `main` → PR → `main`. Every git write (commit, push, PR, merge, tag,
release) happens only when the user asks for it.

## Branch names

`<prefix>/<kebab-case-description>`, short:

| Prefix | Use for | Example |
|---|---|---|
| `feat/` | new functionality | `feat/alert-history` |
| `fix/` | bug fix | `fix/battery-minutes-overflow` |
| `refactor/` | no behaviour change | `refactor/split-views` |
| `test/` | tests only | `test/region-matching` |
| `docs/` | README / docs | `docs/development-section` |
| `chore/` | tooling, scripts, agent setup | `chore/agent-setup` |

## Commit messages

Follow the existing history (`git log --oneline`):

- English, one line, capitalised, no trailing period.
- Describe what the user gets, in plain words; join several changes with commas.
- A release commit ends with `, version X.Y.Z`.

```
Air-raid alert map page with hover details, angry lowered eyes in the menu bar, version 1.5.1
Fix battery minutes while macOS is still calculating
```

Stage files by path. Do not amend a commit that was pushed.

## Pull requests

- Title: same style as a commit message.
- Body: **Summary** (bullets of what changed and why) and **Testing** (the commands run —
  `swift build`, `swift test`, `swift build -c release` — and what was checked in `./dev.sh`,
  with a screenshot for UI changes).
- Update the branch from `origin/main` before opening the PR.

## Release

Semver: patch for fixes, minor for features, major for breaking changes (for example a
higher minimum macOS).

1. Bump `VERSION` in `build.sh`.
2. `./make_dmg.sh` → `dist/GlassMonitor.dmg`; install that build and check it.
3. Commit (`…, version X.Y.Z`), then PR → `main` and merge.
4. On `main`: `git tag vX.Y.Z && git push origin vX.Y.Z`.
5. `gh release create vX.Y.Z dist/GlassMonitor.dmg --title "Glass Monitor X.Y.Z" --notes "<what changed>"`.
   Keep the asset name `GlassMonitor.dmg` (in-app update fetches it). `make_dmg.sh` must keep `Install.command` in the image.
