#!/usr/bin/env bash
set -euo pipefail

subject="${1:-}"
# Allow (#N) at end of subject: GitHub appends the PR number on squash merges.
pattern='^(feat|fix|test|docs|chore)(\([a-z0-9][a-z0-9-]*\))?(!)?: [a-z][a-z0-9 ._:/()\-]*(\(#[0-9]+\))?$'
# Strip trailing (#N) before the length check so GitHub-appended PR refs don't count.
subject_core="$(printf '%s' "$subject" | sed 's/ (#[0-9]\+)$//')"

if [[ ${#subject} -eq 0 || ${#subject_core} -gt 72 ]] ||
   [[ ! "$subject" =~ $pattern ]] ||
   [[ "$subject" != "${subject,,}" ]] ||
   [[ "$subject" == *. ]]; then
  printf 'Invalid Conventional Commit subject: %s\n' "$subject" >&2
  printf 'Required: feat|fix|test|docs|chore(scope): lowercase imperative text\n' >&2
  printf 'Maximum 72 characters; no trailing period.\n' >&2
  exit 1
fi
