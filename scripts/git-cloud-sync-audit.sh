#!/usr/bin/env bash
set -euo pipefail

remote="${1:-origin}"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "error: run from inside the Git worktree" >&2
  exit 1
fi

branch="$(git branch --show-current)"
head_sha="$(git rev-parse HEAD)"

echo "Git cloud sync audit"
echo "remote: ${remote}"
echo "branch: ${branch:-detached}"
echo "head: ${head_sha}"
echo

echo "Remote URLs"
git remote -v | awk -v remote="$remote" '$1 == remote { print }'
echo

echo "Fetching remote refs and tags..."
git fetch --prune --tags "$remote" >/dev/null
echo

echo "Worktree status"
if git diff --quiet && git diff --cached --quiet && [ -z "$(git status --porcelain --untracked-files=all)" ]; then
  echo "clean"
else
  git status --short --untracked-files=all
fi
echo

echo "Current branch tracking"
if [ -n "$branch" ] && upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)"; then
  read -r behind ahead < <(git rev-list --left-right --count "$upstream...HEAD")
  echo "${branch} tracks ${upstream}: ahead ${ahead}, behind ${behind}"
else
  echo "${branch:-detached HEAD} has no upstream"
fi
echo

echo "Local branches with tracking divergence or no upstream"
while read -r refname shortname upstream; do
  if [ -z "$upstream" ]; then
    echo "${shortname}: no upstream"
    continue
  fi

  if ! git rev-parse --verify --quiet "$upstream" >/dev/null; then
    echo "${shortname}: upstream ${upstream} is gone"
    continue
  fi

  read -r behind ahead < <(git rev-list --left-right --count "$upstream...$refname")
  if [ "$ahead" != "0" ] || [ "$behind" != "0" ]; then
    echo "${shortname}: tracks ${upstream}, ahead ${ahead}, behind ${behind}"
  fi
done < <(git for-each-ref --format='%(refname) %(refname:short) %(upstream:short)' refs/heads)
echo

echo "Tag sync"
local_tags="$(git tag --list | wc -l | tr -d ' ')"
remote_tags="$(git ls-remote --refs --tags "$remote" | wc -l | tr -d ' ')"
echo "local tags: ${local_tags}; remote tags: ${remote_tags}"
