#!/usr/bin/env bash
set -uo pipefail

usage() {
  echo "usage: $0 <iphone|ipad>" >&2
  exit 64
}

[[ $# -eq 1 ]] || usage
case "$1" in
  iphone)
    gate_name="iPhone"
    device_key="iphone"
    device_type="com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro"
    ;;
  ipad)
    gate_name="iPad"
    device_key="ipad"
    device_type="com.apple.CoreSimulator.SimDeviceType.iPad-Air-13-inch-M2"
    ;;
  *) usage ;;
esac

expected_sha="${EXPECTED_SHA:-}"
if [[ -n "${GITHUB_WORKSPACE:-}" ]]; then
  workspace="$GITHUB_WORKSPACE"
else
  workspace="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "ERROR: cannot resolve the repository root" >&2
    exit 1
  }
fi
[[ -n "$workspace" && -d "$workspace" ]] || {
  echo "ERROR: repository root is not a directory: $workspace" >&2
  exit 1
}
runner_temp="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
runtime_version="${IOS_RUNTIME_VERSION:-26.5}"
runtime_id="com.apple.CoreSimulator.SimRuntime.iOS-${runtime_version//./-}"
minimum_free_gib="${MINIMUM_FREE_GIB:-60}"
simulator_boot_timeout_seconds="${SIMULATOR_BOOT_TIMEOUT_SECONDS:-900}"
xcode_phase_timeout_seconds="${XCODE_PHASE_TIMEOUT_SECONDS:-3000}"
artifact_dir="$workspace/artifacts/ios-beta-gate-$device_key"
metadata_file="$artifact_dir/metadata.txt"
derived_data=""
simulator_id=""

mkdir -p "$artifact_dir"

cleanup() {
  local status=$?
  if [[ -n "$simulator_id" ]]; then
    xcrun simctl shutdown "$simulator_id" >/dev/null 2>&1 || true
    xcrun simctl delete "$simulator_id" >/dev/null 2>&1 || true
  fi
  if [[ -n "$derived_data" && -d "$derived_data" ]]; then
    rm -rf "$derived_data"
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fail() {
  echo "ERROR: $*" | tee -a "$artifact_dir/gate.log" >&2
  exit 1
}

actual_sha="$(git -C "$workspace" rev-parse HEAD)" || fail "cannot resolve repository HEAD"
{
  echo "gate=$gate_name"
  echo "expected_sha=$expected_sha"
  echo "actual_sha=$actual_sha"
  echo "runner_name=${RUNNER_NAME:-local-manual}"
  echo "runner_os=${RUNNER_OS:-$(uname -s)}"
  echo "runner_arch=${RUNNER_ARCH:-$(uname -m)}"
  echo "runtime=$runtime_id"
  echo "device_type=$device_type"
  echo "minimum_free_gib=$minimum_free_gib"
  xcodebuild -version | tr '\n' ' '
  echo
} > "$metadata_file"

[[ -n "$expected_sha" ]] || fail "EXPECTED_SHA is required"
[[ "$actual_sha" == "$expected_sha" ]] || fail "checked out HEAD $actual_sha does not match expected PR head $expected_sha"
[[ "${RUNNER_OS:-macOS}" == "macOS" ]] || fail "gate requires a macOS runner"
[[ "$(uname -s)" == "Darwin" ]] || fail "gate requires Darwin"
command -v jq >/dev/null || fail "jq is required to validate xcresult evidence"
command -v xcodebuild >/dev/null || fail "xcodebuild is required"
command -v xcrun >/dev/null || fail "xcrun is required"
[[ -x /usr/bin/perl ]] || fail "/usr/bin/perl is required for bounded Xcode phases"

available_kib="$(df -Pk "$runner_temp" | awk 'NR == 2 {print $4}')"
[[ "$available_kib" =~ ^[0-9]+$ ]] || fail "could not determine free disk space for $runner_temp"
required_kib=$((minimum_free_gib * 1024 * 1024))
available_gib=$((available_kib / 1024 / 1024))
echo "available_free_gib=$available_gib" >> "$metadata_file"
(( available_kib >= required_kib )) || fail "runner has ${available_gib} GiB free; ${minimum_free_gib} GiB is required"

xcrun simctl list runtimes | grep -Fq "$runtime_id" || fail "required simulator runtime is unavailable: $runtime_id"
xcrun simctl list devicetypes | grep -Fq "$device_type" || fail "required simulator device type is unavailable: $device_type"

derived_data="$(mktemp -d "$runner_temp/wpr2-ios-beta-${1}.derived.XXXXXX")" || fail "cannot create temporary DerivedData directory"
simulator_name="WPR2-CI-${gate_name}-${GITHUB_RUN_ID:-manual}-${GITHUB_RUN_ATTEMPT:-1}"
simulator_id="$(xcrun simctl create "$simulator_name" "$device_type" "$runtime_id")" || fail "cannot create $gate_name simulator"
echo "simulator_id=$simulator_id" >> "$metadata_file"

/usr/bin/perl -e 'alarm shift; exec @ARGV' "$simulator_boot_timeout_seconds" \
  xcrun simctl boot "$simulator_id" \
  2>&1 | tee -a "$artifact_dir/gate.log"
boot_command_status=("${PIPESTATUS[@]}")
[[ "${boot_command_status[0]}" == "0" ]] || fail "cannot boot $gate_name simulator before the timeout"
[[ "${boot_command_status[1]}" == "0" ]] || fail "$gate_name simulator boot-command log could not be preserved"
/usr/bin/perl -e 'alarm shift; exec @ARGV' "$simulator_boot_timeout_seconds" \
  xcrun simctl bootstatus "$simulator_id" -b \
  2>&1 | tee -a "$artifact_dir/gate.log"
boot_pipeline_status=("${PIPESTATUS[@]}")
[[ "${boot_pipeline_status[0]}" == "0" ]] || fail "$gate_name simulator did not finish booting before the timeout"
[[ "${boot_pipeline_status[1]}" == "0" ]] || fail "$gate_name simulator boot log could not be preserved"

run_xcode_phase() {
  local phase="$1"
  local scheme="$2"
  local result_bundle="$3"
  local xcode_log="$4"
  shift 4

  /usr/bin/perl -e 'alarm shift; exec @ARGV' "$xcode_phase_timeout_seconds" xcodebuild test \
    -workspace "$workspace/Weird Parts.xcworkspace" \
    -scheme "$scheme" \
    -destination "platform=iOS Simulator,id=$simulator_id" \
    -derivedDataPath "$derived_data" \
    -resultBundlePath "$result_bundle" \
    -parallel-testing-enabled NO \
    "$@" \
    CODE_SIGNING_ALLOWED=NO \
    2>&1 | tee "$xcode_log"
  local pipeline_status=("${PIPESTATUS[@]}")
  echo "${pipeline_status[0]}" > "$artifact_dir/${phase}-xcode-status.txt"
  echo "${pipeline_status[1]}" > "$artifact_dir/${phase}-tee-status.txt"
}

unit_result="$artifact_dir/unit-regression-${gate_name}.xcresult"
unit_log="$artifact_dir/unit-regression-xcodebuild.log"
ui_result="$artifact_dir/ui-smokes-${gate_name}.xcresult"
ui_log="$artifact_dir/ui-smokes-xcodebuild.log"

# Run all app/core unit and regression tests while excluding the broad manual
# UI catalog. The second phase executes the repo's bounded deterministic UI
# smoke plan, including its viewport harness, on this same device class.
run_xcode_phase \
  "unit-regression" "WiredPart-iOS" "$unit_result" "$unit_log" \
  -skip-testing:"Weird PartsUITests"
run_xcode_phase \
  "ui-smokes" "WiredPart-iOS-Stage9-Smokes" "$ui_result" "$ui_log"

phase_failure=0
aggregate_total=0
aggregate_passed=0
aggregate_failed=0
aggregate_skipped=0

validate_phase() {
  local phase="$1"
  local result_bundle="$2"
  local status_file="$3"
  local tee_status_file="$4"
  local summary_json="$artifact_dir/${phase}-summary.json"
  local archive="$artifact_dir/${phase}-${gate_name}.xcresult.zip"
  local xcode_status
  local tee_status
  local result
  local total
  local passed
  local failed
  local skipped
  local summary_status=0

  [[ -f "$status_file" ]] || fail "missing Xcode status for $phase"
  [[ -f "$tee_status_file" ]] || fail "missing log-preservation status for $phase"
  xcode_status="$(<"$status_file")"
  tee_status="$(<"$tee_status_file")"
  if [[ ! -d "$result_bundle" ]]; then
    echo "ERROR: $phase produced no xcresult bundle" | tee -a "$artifact_dir/gate.log" >&2
    phase_failure=1
    return
  fi
  xcrun xcresulttool get test-results summary --path "$result_bundle" --compact > "$summary_json" || summary_status=$?
  ditto -c -k --sequesterRsrc --keepParent "$result_bundle" "$archive" || fail "$phase xcresult archive could not be created"
  rm -rf "$result_bundle"
  if (( summary_status != 0 )); then
    echo "ERROR: $phase xcresult summary could not be read; raw result was preserved in $archive" | tee -a "$artifact_dir/gate.log" >&2
    phase_failure=1
    return
  fi

  result="$(jq -r '.result // "unknown"' "$summary_json")" || fail "cannot read $phase result"
  total="$(jq -r '.totalTestCount // 0' "$summary_json")" || fail "cannot read $phase test count"
  passed="$(jq -r '.passedTests // 0' "$summary_json")" || fail "cannot read $phase pass count"
  failed="$(jq -r '.failedTests // 0' "$summary_json")" || fail "cannot read $phase failure count"
  skipped="$(jq -r '.skippedTests // 0' "$summary_json")" || fail "cannot read $phase skip count"

  {
    echo "${phase}_result=$result"
    echo "${phase}_total_tests=$total"
    echo "${phase}_passed_tests=$passed"
    echo "${phase}_failed_tests=$failed"
    echo "${phase}_skipped_tests=$skipped"
    echo "${phase}_xcode_status=$xcode_status"
    echo "${phase}_tee_status=$tee_status"
  } | tee -a "$metadata_file"

  aggregate_total=$((aggregate_total + total))
  aggregate_passed=$((aggregate_passed + passed))
  aggregate_failed=$((aggregate_failed + failed))
  aggregate_skipped=$((aggregate_skipped + skipped))

  [[ "$xcode_status" == "0" ]] || phase_failure=1
  [[ "$tee_status" == "0" ]] || phase_failure=1
  [[ "$result" == "Passed" ]] || phase_failure=1
  (( total > 0 )) || phase_failure=1
  (( failed == 0 )) || phase_failure=1
  (( skipped == 0 )) || phase_failure=1
}

validate_phase \
  "unit-regression" "$unit_result" \
  "$artifact_dir/unit-regression-xcode-status.txt" "$artifact_dir/unit-regression-tee-status.txt"
validate_phase \
  "ui-smokes" "$ui_result" \
  "$artifact_dir/ui-smokes-xcode-status.txt" "$artifact_dir/ui-smokes-tee-status.txt"

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "## iOS Beta Gate — $gate_name"
    echo
    echo "- PR head: \`$actual_sha\`"
    echo "- Tests: $aggregate_total total, $aggregate_passed passed, $aggregate_failed failed, $aggregate_skipped skipped"
    echo "- Simulator: $simulator_name ($runtime_version)"
  } >> "$GITHUB_STEP_SUMMARY"
fi

(( phase_failure == 0 )) || fail "one or more $gate_name test phases failed, skipped tests, or produced invalid evidence"

echo "iOS Beta Gate passed for $gate_name at $actual_sha"
