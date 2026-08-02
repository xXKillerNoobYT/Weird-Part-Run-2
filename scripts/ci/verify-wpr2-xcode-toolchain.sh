#!/usr/bin/env bash
# Select and prove the exact, repo-declared Xcode before any simulator or build work.
# Bash 3.2 compatible; this script never modifies xcode-select or project metadata.
set -euo pipefail

usage() {
  echo "usage: $0 [--self-test]" >&2
  exit 64
}

self_test=0
case "${1:-}" in
  "") ;;
  --self-test) self_test=1 ;;
  *) usage ;;
esac

repo_root="${GITHUB_WORKSPACE:-}"
if [[ -z "$repo_root" ]]; then
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "ERROR: cannot resolve repository root" >&2
    exit 1
  }
fi
contract="$repo_root/.github/wpr2-main-build/toolchain.env"
[[ -f "$contract" ]] || {
  echo "ERROR: missing public WPR2 toolchain contract: $contract" >&2
  exit 1
}

# shellcheck disable=SC1090
. "$contract"
for required in WPR2_XCODE_VERSION WPR2_XCODE_BUILD WPR2_XCODE_DEVELOPER_DIR; do
  eval "value=\${$required:-}"
  [[ -n "$value" ]] || {
    echo "ERROR: toolchain contract omits $required" >&2
    exit 1
  }
done

verify_version_output() {
  local output="$1"
  local expected_version="$2"
  local expected_build="$3"
  local actual_version
  local actual_build

  actual_version="$(printf '%s\n' "$output" | awk -F' ' '/^Xcode / { print $2; exit }')"
  actual_build="$(printf '%s\n' "$output" | awk -F' ' '/^Build version / { print $3; exit }')"
  [[ "$actual_version" == "$expected_version" ]] || return 1
  [[ "$actual_build" == "$expected_build" ]] || return 1
}

if (( self_test )); then
  verify_version_output $'Xcode 26.3\nBuild version 17C529' '26.3' '17C529'
  ! verify_version_output $'Xcode 26.6\nBuild version 17F113' '26.3' '17C529'
  ! verify_version_output $'Xcode 26.3\nBuild version 17C528' '26.3' '17C529'
  echo "WPR2 Xcode toolchain verifier self-test passed"
  exit 0
fi

[[ -d "$WPR2_XCODE_DEVELOPER_DIR" ]] || {
  echo "::error::Xcode ${WPR2_XCODE_VERSION} (${WPR2_XCODE_BUILD}) is unavailable at the declared developer directory: $WPR2_XCODE_DEVELOPER_DIR" >&2
  exit 1
}

export DEVELOPER_DIR="$WPR2_XCODE_DEVELOPER_DIR"
version_output="$(xcodebuild -version 2>&1)" || {
  echo "::error::Unable to query declared Xcode at $DEVELOPER_DIR" >&2
  exit 1
}
if ! verify_version_output "$version_output" "$WPR2_XCODE_VERSION" "$WPR2_XCODE_BUILD"; then
  echo "::error::Xcode toolchain mismatch. Expected Xcode $WPR2_XCODE_VERSION build $WPR2_XCODE_BUILD at $WPR2_XCODE_DEVELOPER_DIR; discovered: $(printf '%s' "$version_output" | tr '\n' ' ')" >&2
  exit 1
fi

metadata_dir="${WPR2_TOOLCHAIN_METADATA_DIR:-$repo_root/artifacts/ios-beta-gate-toolchain}"
mkdir -p "$metadata_dir"
{
  echo "xcode_version=$WPR2_XCODE_VERSION"
  echo "xcode_build=$WPR2_XCODE_BUILD"
  echo "developer_dir=$WPR2_XCODE_DEVELOPER_DIR"
  printf 'xcodebuild_version='
  printf '%s' "$version_output" | tr '\n' ' '
  echo
} > "$metadata_dir/toolchain.txt"

if [[ -n "${GITHUB_ENV:-}" ]]; then
  {
    echo "DEVELOPER_DIR=$DEVELOPER_DIR"
    echo "WPR2_TOOLCHAIN_VERIFIED=1"
  } >> "$GITHUB_ENV"
fi

echo "Verified Xcode $WPR2_XCODE_VERSION ($WPR2_XCODE_BUILD) at $DEVELOPER_DIR"
