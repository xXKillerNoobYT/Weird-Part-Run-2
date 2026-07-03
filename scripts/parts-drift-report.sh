#!/usr/bin/env bash
# parts-drift-report.sh — Mechanical first-pass for the parts-drift-detector
# subagent (GitHub #256). Speeds up the AUTO GO / hunt-fix "C1b — plan-vs-code
# drift" check for the Parts domain from ~10 min to ~2 min.
#
# What it does (grep-level, zero judgement):
#   1. PLANNED-BUT-NOT-CODED — pulls every `SomeFile.swift` filename mentioned
#      in the parts-domain plan files under docs/plans/ and reports which of
#      those files DO NOT exist anywhere in the repo. A missing file is a strong
#      signal the plan is ahead of the code.
#   2. CODED-BUT-NOT-PLANNED — lists every .swift file under the Parts iOS
#      feature dir and reports which filenames are NEVER mentioned in any
#      parts-domain plan. An unmentioned file is a candidate for "code ahead of
#      plan" (may be legitimately new, or a plan that needs an update).
#
# This script deliberately does NOT decide whether drift is acceptable — that
# is the subagent's job (.claude/agents/parts-drift-detector.md). It only
# surfaces the mechanical file-level anchors so the subagent can spend its
# reasoning budget on the semantic diff (method signatures, UI behavior,
# migration columns) instead of eyeballing filenames.
#
# Usage:
#   scripts/parts-drift-report.sh [--json] [--markdown] [--quiet]
#
# Flags:
#   --json       Emit machine-readable JSON (for the subagent to parse).
#   --markdown   Emit a Markdown report (default is plain text).
#   --quiet      Suppress the human header/footer; body only.
#   -h|--help    Show this help.
#
# Exit codes:
#   0  — Ran successfully. Drift MAY still be present; this is a report, not a
#        gate. Check the body. (Non-zero exit is reserved for tool failures so
#        the script can be safely chained in a pipeline without false CI fails.)
#   1  — Fatal error (missing repo layout, no plan files, bad args).
#
# Requirements: bash 3.2+ (macOS default), basename, find, grep, sed, sort.

set -euo pipefail

# --- Locate repo root (script lives in scripts/) ------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PLANS_DIR="$ROOT_DIR/docs/plans"
PARTS_IOS_DIR="$ROOT_DIR/Weird Parts IOS/Weird Parts IOS/Features/Parts"

# Parts-domain plan family (per docs/plans/parts-section-audit-fix-plan.md index).
# These are the plans the C1b Parts drift check reads.
PARTS_PLANS=(
  "parts-section-audit-fix-plan.md"
  "colors-parts-redesign.md"
  "forecasting-page-redesign.md"
  "inventory-intelligence-system.md"
  "ios-part-number-hierarchy.md"
  "ios-brands-suppliers-editing.md"
  "ios-supplier-system.md"
  "supplier-communication-bridge-plan.md"
)

# --- Arg parsing --------------------------------------------------------------
FORMAT="text"
QUIET=0

usage() {
  # Print the leading comment block (help text) up to the first blank line
  # after the shebang, minus the leading "# ".
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)     FORMAT="json" ;;
    --markdown) FORMAT="markdown" ;;
    --quiet)    QUIET=1 ;;
    -h|--help)  usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; echo "Try --help." >&2; exit 1 ;;
  esac
  shift
done

# --- Sanity checks ------------------------------------------------------------
if [[ ! -d "$PLANS_DIR" ]]; then
  echo "Fatal: plans dir not found: ${PLANS_DIR#"$ROOT_DIR"/}" >&2
  exit 1
fi
if [[ ! -d "$PARTS_IOS_DIR" ]]; then
  echo "Fatal: Parts iOS feature dir not found: ${PARTS_IOS_DIR#"$ROOT_DIR"/}" >&2
  exit 1
fi

# Keep only plan files that actually exist (plan family evolves over time).
EXISTING_PLANS=()
for p in "${PARTS_PLANS[@]}"; do
  [[ -f "$PLANS_DIR/$p" ]] && EXISTING_PLANS+=("$PLANS_DIR/$p")
done
if [[ ${#EXISTING_PLANS[@]} -eq 0 ]]; then
  echo "Fatal: none of the expected parts-domain plan files exist under ${PLANS_DIR#"$ROOT_DIR"/}" >&2
  exit 1
fi

# --- 1. Filenames mentioned in the plans (planned surface) --------------------
# Extract every token matching *.swift from every plan file, dedupe.
# grep -oE gives us just the filename tokens even inside table cells / prose.
mentioned_swift() {
  grep -hoE '[A-Za-z0-9_+.-]+\.swift' "${EXISTING_PLANS[@]}" 2>/dev/null \
    | sort -u
}

# --- 2. Actual Parts iOS .swift files (coded surface) -------------------------
coded_parts_swift() {
  find "$PARTS_IOS_DIR" -maxdepth 1 -type f -name '*.swift' -exec basename {} \; \
    | sort -u
}

# --- Compute PLANNED-BUT-NOT-CODED --------------------------------------------
# For each .swift mentioned in a plan, is there a file with that basename
# anywhere in the repo (iOS app OR core package)? If not → planned-but-not-coded.
PLANNED_MISSING=()
while IFS= read -r fname; do
  [[ -z "$fname" ]] && continue
  # Search the whole repo for a file with this basename (exclude VCS + build).
  if ! find "$ROOT_DIR" \
        -type d \( -name '.git' -o -name '.build' -o -name 'DerivedData' \) -prune -o \
        -type f -name "$fname" -print 2>/dev/null | grep -q .; then
    PLANNED_MISSING+=("$fname")
  fi
done < <(mentioned_swift)

# --- Compute CODED-BUT-NOT-PLANNED --------------------------------------------
# For each Parts iOS .swift file, is its basename mentioned in ANY plan? If not
# → coded-but-not-planned candidate.
MENTIONED_LIST="$(mentioned_swift)"
CODED_UNPLANNED=()
while IFS= read -r fname; do
  [[ -z "$fname" ]] && continue
  if ! grep -qxF "$fname" <<<"$MENTIONED_LIST"; then
    CODED_UNPLANNED+=("$fname")
  fi
done < <(coded_parts_swift)

# --- Rendering ----------------------------------------------------------------
n_plans=${#EXISTING_PLANS[@]}
n_planned_missing=${#PLANNED_MISSING[@]}
n_coded_unplanned=${#CODED_UNPLANNED[@]}

json_array() {
  # $@ = items → JSON string array, no external deps.
  local out="[" first=1 item
  for item in "$@"; do
    [[ $first -eq 0 ]] && out+=","
    # Escape backslashes and double quotes.
    item=${item//\\/\\\\}
    item=${item//\"/\\\"}
    out+="\"$item\""
    first=0
  done
  out+="]"
  printf '%s' "$out"
}

case "$FORMAT" in
  json)
    printf '{\n'
    printf '  "plans_scanned": %d,\n' "$n_plans"
    printf '  "planned_but_not_coded": %s,\n' "$(json_array "${PLANNED_MISSING[@]+"${PLANNED_MISSING[@]}"}")"
    printf '  "coded_but_not_planned": %s\n' "$(json_array "${CODED_UNPLANNED[@]+"${CODED_UNPLANNED[@]}"}")"
    printf '}\n'
    ;;
  markdown)
    [[ $QUIET -eq 0 ]] && {
      printf '# Parts drift — mechanical first-pass\n\n'
      printf 'Scanned **%d** parts-domain plan file(s) under `docs/plans/`.\n\n' "$n_plans"
      printf '> This is a file-level anchor report only. Semantic drift (method\n'
      printf '> signatures, UI behavior, migration columns) is judged by the\n'
      printf '> `parts-drift-detector` subagent, not this script.\n\n'
    }
    printf '## Planned but not coded (%d)\n\n' "$n_planned_missing"
    if [[ $n_planned_missing -eq 0 ]]; then
      printf '_None — every `.swift` named in the plans exists in the repo._\n\n'
    else
      printf 'Files named in a plan but not found anywhere in the repo:\n\n'
      for f in "${PLANNED_MISSING[@]}"; do printf -- '- `%s`\n' "$f"; done
      printf '\n'
    fi
    printf '## Coded but not planned (%d)\n\n' "$n_coded_unplanned"
    if [[ $n_coded_unplanned -eq 0 ]]; then
      printf '_None — every Parts iOS file is named in at least one plan._\n\n'
    else
      printf 'Parts iOS `.swift` files not mentioned in any parts-domain plan:\n\n'
      for f in "${CODED_UNPLANNED[@]}"; do printf -- '- `%s`\n' "$f"; done
      printf '\n'
    fi
    ;;
  text|*)
    [[ $QUIET -eq 0 ]] && {
      echo "parts-drift-report — mechanical first-pass ($n_plans plan file(s) scanned)"
      echo "NOTE: file-level anchors only; semantic drift is the subagent's job."
      echo
    }
    echo "PLANNED BUT NOT CODED ($n_planned_missing):"
    if [[ $n_planned_missing -eq 0 ]]; then
      echo "  (none)"
    else
      for f in "${PLANNED_MISSING[@]}"; do echo "  - $f"; done
    fi
    echo
    echo "CODED BUT NOT PLANNED ($n_coded_unplanned):"
    if [[ $n_coded_unplanned -eq 0 ]]; then
      echo "  (none)"
    else
      for f in "${CODED_UNPLANNED[@]}"; do echo "  - $f"; done
    fi
    ;;
esac

exit 0
