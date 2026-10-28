# Glass Monitor — agent rules

Canonical rules for every AI tool in this repo. Codex and Cursor read this file directly;
`CLAUDE.md` only imports it for Claude Code. Edit this file, never a copy.

## What this is

A macOS menu-bar system monitor in SwiftUI + AppKit with an animated mascot. A Swift
Package with no Xcode project; macOS 14+, Apple Silicon and Intel. Solo project, released
as an ad-hoc-signed DMG on GitHub Releases.

## Layout

- `Sources/GlassMonitor/`
  - `App.swift` — entry point; the UI lives in `AppDelegate`'s panel.
  - `AppDelegate.swift` — status item, right-click menu, slide-in panel, drone icon.
  - `Monitor.swift` — main `ObservableObject`, refreshes every 1.5 s.
  - `Sensors.swift` — IOKit / CoreWLAN / IOBluetooth reads, private IOHID for CPU temperature on Apple
   Silicon, read-only AppleSMC on Intel.
  - `ClaudeUsage.swift` — OAuth token from the Keychain → undocumented Anthropic usage endpoint.
  - `AirAlerts.swift` — siren.pp.ua alerts, alerts.in.ua threat report, local region matching, map.
  - `Updater.swift` — GitHub Releases latest → optional menu-bar Update, replaces this `.app` from the DMG.
  - `Eyes.swift` (mascot), `Notifier.swift` (limit notifications).
  - `Views/` — `ContentView.swift` (main panel and page switching), one file per page
    (`NetworkPage`, `ClaudePage`, `MemoryPage`, `AlertsPage` with the main-panel alert card),
    `Components.swift` (`Card`, `Title`, `Subtitle`, `ActionLink`, `formatSpeed`) and
    `Icons.swift` (hand-drawn icons). Helpers used by one file stay `private` there.
- `Assets/` — copied into the app's `Contents/Resources` by the build scripts. Code reads them
  through `Bundle.main`, so they only resolve inside a `.app`.
- `Tests/GlassMonitorTests/` — Swift Testing, `@testable import GlassMonitor`.

## Commands

| Command | What it does |
|---|---|
| `swift build` | compile check (debug) |
| `swift test` | unit tests |
| `./dev.sh` / `./dev.sh lldb` | debug `.app` (`dev.local.glassmonitor.dev`) that runs beside the installed release; logs in the terminal |
| `./dev.sh cmd <show\|hide\|hot-cpu\|low-battery\|alert-yellow\|alert-red\|alert-off\|claude-NN\|update-on\|update-off\|update>` | drive the running dev build's Debug menu without clicking |
| `GM_LOG=/tmp/gm.log ./dev.sh` | app output to a file (an agent shell has no terminal, so output is lost otherwise) |
| `./build.sh` | release universal app, installs to `~/Applications` |
| `./make_dmg.sh` | release build + `dist/GlassMonitor.dmg` |

- SwiftPM starts its own sandbox, so `swift build` / `swift test` fail inside an agent
  sandbox with `sandbox_apply: Operation not permitted`. Run them unsandboxed.
- Do not judge behaviour with `swift run`: a bare binary has no assets, and macOS attributes
  Location / Bluetooth / Keychain prompts to the terminal instead of the app.
- In a debug build, right-click the menu-bar icon → **Debug** to simulate an air-raid alert,
  a Claude session percentage, low battery, a hot CPU or an available update.
- To check behaviour without clicking: `GM_LOG=… ./dev.sh`, then `./dev.sh cmd …`, and a temporary
  `print` read from the log. Remove the prints afterwards. `screencapture` needs Screen Recording
  permission for the agent's app; without it, ask the user to look.
- A scripted `show` panel can close by itself (it never becomes key), and the mascot then sleeps.
  When a log looks odd, check for that before suspecting the code.

## Code conventions

- Match the surrounding style: compact Swift, short local names, `// MARK:` sections.
- Models are `@MainActor` `ObservableObject`s. Blocking work goes in `Task.detached`, results
  come back via `MainActor.run`; timers and observers capture `[weak self]`.
- Keep parsing and decision logic in `static` functions (`nonisolated` on a `@MainActor` type)
  so tests can call them: `Notifier.decide`, `AirAlertMonitor.threats`, `ClaudeUsage.window`.
- Debug-only code sits under `#if DEBUG` and must not change release behaviour. Code under
  `#if !DEBUG` is compiled only by `swift build -c release`.
- A comment answers "what breaks if you change this". No narration, no banner separators.
- Search for prior art before writing a helper, and name what you found. Known twin:
  ISO-8601 parsing in `ClaudeUsage.parse` and `AirAlertMonitor.parseDate`.
- No third-party dependencies without asking first.
- UI copy is English; region names and threat text stay in Ukrainian as the APIs serve them.
- Repository files are in English, whatever language the chat uses.

## Privacy and security baseline

- The Claude OAuth token is read from the Keychain via `/usr/bin/security`, sent only to
  `api.anthropic.com`, and never logged, persisted, or shown.
- The location never leaves the Mac: regions are matched locally, and the alert APIs only
  get generic GETs.
- `Process` gets a fixed executable path and an argument array — never a shell string.
- Network calls use HTTPS with a timeout and keep the last good state on failure. Respect the
  backoff: Claude usage ≥ 5 min and doubling on failure; alerts.in.ua at most once a minute
  and only while an alert is active; GitHub Releases at launch and at most once a day.
  The updater only downloads `GlassMonitor.dmg` from `github.com/kio00o/glass-monitor` and
  only replaces this `.app` after the mounted bundle id matches `dev.local.glassmonitor`.
- Treat every network response as untrusted: `Decodable` or optional casts, no force-unwraps.
- The air-alert feature is not an official warning system; never word it as authoritative.

## Done means verified

1. `swift build` and `swift test` pass.
2. Behaviour change: run `./dev.sh` and exercise it, using the Debug menu where it helps.
   UI change: attach a screenshot.
3. Code under `#if !DEBUG` or in `build.sh`: `swift build -c release` passes.
4. The report says what was run and what was not.

## Git

- Work on a branch from `main`: `feat/`, `fix/`, `refactor/`, `test/`, `docs/`, `chore/`.
  A hook blocks file edits while the repo is on `main`
  (`.claude/hooks/check-branch-before-write.sh`).
- On `main` with no branch yet: propose a branch name and create it once the user agrees.
- Uncommitted changes this session did not make belong to someone else: ask before
  building on them or committing them.
- Commit, push, open or merge a PR, tag or release only when the user asks. Stage files by
  path, never `git add -A` or `git add .`. Never force-push `main`.
- Branch names, commit messages, PRs and the release steps: `.claude/skills/git-conventions/SKILL.md`.

## Agents and skills

- Skills (`.claude/skills/`, Codex reads them via the `.agents/skills` symlink):
  `brainstorming` before a new feature or architectural change; `git-conventions` for git.
- Agents (`.claude/agents/`, Codex adapters in `.codex/agents/`): `implementor`,
  `code-reviewer` and `security-reviewer`. The reviewers are read-only.
- A small fix: just do it and verify. A feature: brainstorming → implement → `code-reviewer`,
  plus `security-reviewer` when the diff touches the Keychain, network, `Process`, location,
  notifications or private APIs.
- When the user corrects a miss that could recur, fix it and update this file, a skill or an
  agent on the same branch.
