#!/usr/bin/env bash
# PreToolUse (Edit|Write|MultiEdit) guard: block file edits while the target file's repo is on
# `main` (AGENTS.md "Git"). Claude Code runs it from .claude/settings.json, and Cursor runs the
# same entry as a third-party hook.
#
# The branch comes from the target file's own repo, walking up to the nearest existing
# directory (a new file's dir may not exist yet) — never from $PWD, which may be another
# checkout or worktree. Fails open on anything ambiguous so it never breaks a legitimate edit.
set -uo pipefail

input=$(cat 2>/dev/null || true)
command -v jq >/dev/null 2>&1 || exit 0
f=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null || true)
[ -z "$f" ] && exit 0

d=$(dirname "$f")
while [ -n "$d" ] && [ "$d" != "/" ] && [ ! -d "$d" ]; do d=$(dirname "$d"); done
[ -d "$d" ] || exit 0

b=$(git -C "$d" branch --show-current 2>/dev/null) || exit 0
if [ "$b" = "main" ]; then
  cat >&2 <<MSG
BLOCKED: the repo of $f is on 'main'. Edits belong on a branch from main
(feat/, fix/, refactor/, test/, docs/, chore/). Propose a name to the user, then:
  git -C "$d" checkout -b <prefix>/<name>
MSG
  exit 2
fi
exit 0
