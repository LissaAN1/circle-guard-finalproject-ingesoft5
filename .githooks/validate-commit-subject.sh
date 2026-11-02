#!/usr/bin/env bash
set -euo pipefail

subject="${1:-}"
pattern='^(feat|fix|test|docs|chore)(\([a-z0-9][a-z0-9-]*\))?(!)?: [a-z][a-z0-9 ._:/()\-]*$'

if [[ ${#subject} -eq 0 || ${#subject} -gt 72 ]] ||
   [[ ! "$subject" =~ $pattern ]] ||
   [[ "$subject" != "${subject,,}" ]] ||
   [[ "$subject" == *. ]]; then
  printf 'Invalid Conventional Commit subject: %s\n' "$subject" >&2
  printf 'Required: feat|fix|test|docs|chore(scope): lowercase imperative text\n' >&2
  printf 'Maximum 72 characters; no trailing period.\n' >&2
  exit 1
fi
