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
echo

echo "Branch hygiene snapshot"
remote_main_ref="refs/remotes/${remote}/main"
if ! git show-ref --verify --quiet "$remote_main_ref"; then
  remote_main_ref="refs/remotes/${remote}/master"
fi

mapfile -t remote_branch_short_names < <(
  git for-each-ref --format='%(refname:short)' "refs/remotes/${remote}" \
    | sed -e "s#^${remote}/##" \
    | grep -Ev '^(HEAD|main|master)$' \
    | sort -u
)

echo "remote branches (excluding ${remote}/HEAD, main, master): ${#remote_branch_short_names[@]}"

if git show-ref --verify --quiet "$remote_main_ref"; then
  merged_remote_count="$(
    git branch -r --merged "${remote_main_ref#refs/remotes/}" \
      | sed 's/^[[:space:]]*//' \
      | grep "^${remote}/" \
      | sed -e "s#^${remote}/##" \
      | grep -Ev '^(HEAD|main|master)$' \
      | wc -l \
      | tr -d ' '
  )"
  echo "remote branches already merged into ${remote_main_ref#refs/remotes/}: ${merged_remote_count}"
else
  echo "remote branches already merged into ${remote}/main: unavailable (missing ${remote}/main and ${remote}/master refs)"
fi

if command -v gh >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  repo_from_remote="$(git remote get-url "$remote" 2>/dev/null | sed -nE 's#(git@github.com:|https://github.com/)([^/]+/[^/.]+)(\.git)?#\2#p')"
  if [[ -n "$repo_from_remote" ]]; then
    open_pr_json="$(gh pr list --repo "$repo_from_remote" --state open --limit 200 --json headRefName 2>/dev/null || true)"
    if [[ -n "$open_pr_json" ]]; then
      open_pr_count="$(jq 'length' <<<"$open_pr_json" 2>/dev/null || echo 0)"
      if [[ "$open_pr_count" =~ ^[0-9]+$ ]]; then
        echo "open PRs: ${open_pr_count}"
        if [[ ${#remote_branch_short_names[@]} -gt 0 ]]; then
          declare -A open_pr_heads=()
          while IFS= read -r head_ref; do
            [[ -n "$head_ref" ]] && open_pr_heads["$head_ref"]=1
          done < <(jq -r '.[].headRefName // empty' <<<"$open_pr_json")

          no_pr_count=0
          for remote_branch in "${remote_branch_short_names[@]}"; do
            if [[ -z "${open_pr_heads[$remote_branch]+x}" ]]; then
              ((no_pr_count += 1))
            fi
          done
          echo "remote branches without open PR: ${no_pr_count}"
        fi
      fi
    fi
  fi
fi
