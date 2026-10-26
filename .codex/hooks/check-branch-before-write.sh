#!/usr/bin/env bash
# Codex PreToolUse (Edit/Write/apply_patch) guard, same rule as
# .claude/hooks/check-branch-before-write.sh: no file edits while the file's repo is on `main`.
# Codex sends apply_patch input as tool_input.command, so every affected file is extracted and
# checked against its own worktree's branch. Fails open when no file path can be found.
set -uo pipefail

input=$(cat 2>/dev/null || true)
command -v jq >/dev/null 2>&1 || exit 0

tool=$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null || true)
cwd=$(printf '%s' "$input" | jq -r '.cwd // "."' 2>/dev/null || true)
[ -n "$cwd" ] || cwd="."

if [ "$tool" = "apply_patch" ]; then
  files=$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null \
    | sed -nE 's/^\*\*\* (Add|Update|Delete) File: (.+)$/\2/p')
else
  files=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null || true)
fi

while IFS= read -r file; do
  [ -n "$file" ] || continue
  case "$file" in
    /*) target="$file" ;;
    *) target="$cwd/$file" ;;
  esac

  dir=$(dirname "$target")
  while [ -n "$dir" ] && [ "$dir" != "/" ] && [ ! -d "$dir" ]; do
    dir=$(dirname "$dir")
  done
  [ -d "$dir" ] || continue

  branch=$(git -C "$dir" branch --show-current 2>/dev/null || true)
  if [ "$branch" = "main" ]; then
    cat >&2 <<MSG
BLOCKED: the repo of $file is on 'main'. Edits belong on a branch from main
(feat/, fix/, refactor/, test/, docs/, chore/). Propose a name to the user, then:
  git -C "$dir" checkout -b <prefix>/<name>
MSG
    exit 2
  fi
done <<EOF
$files
EOF
exit 0
