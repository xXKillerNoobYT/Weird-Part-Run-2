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
# A full gate run (workspace build + two test phases + xcresult bundles)
# consumes well under 20 GiB; 30 GiB keeps real headroom without failing
# closed on a Mac whose other tenants (Paperclip/hermes state and backups)
# legitimately hold large data sets. Was 60, which parked every PR whenever
# unrelated agents' storage grew (2026-07-28/30/31 incidents).
minimum_free_gib="${MINIMUM_FREE_GIB:-30}"
derived_data_stale_minutes="${DERIVED_DATA_STALE_MINUTES:-60}"
simulator_boot_command_timeout_seconds="${SIMULATOR_BOOT_COMMAND_TIMEOUT_SECONDS:-120}"
simulator_boot_timeout_seconds="${SIMULATOR_BOOT_TIMEOUT_SECONDS:-600}"
simulator_boot_recovery_timeout_seconds="${SIMULATOR_BOOT_RECOVERY_TIMEOUT_SECONDS:-600}"
xcode_phase_timeout_seconds="${XCODE_PHASE_TIMEOUT_SECONDS:-2400}"
ui_smoke_phase_timeout_seconds="${UI_SMOKE_PHASE_TIMEOUT_SECONDS:-900}"
job_timeout_seconds="${JOB_TIMEOUT_SECONDS:-7200}"
cleanup_upload_margin_seconds="${CLEANUP_UPLOAD_MARGIN_SECONDS:-1200}"
artifact_dir="$workspace/artifacts/ios-beta-gate-$device_key"
metadata_file="$artifact_dir/metadata.txt"
derived_data=""
simulator_id=""

# The self-hosted runner retains ignored artifacts between jobs. xcodebuild
# refuses an already-existing -resultBundlePath, so every gate attempt must
# begin with a clean device-scoped evidence directory.
prepare_artifact_dir() {
  rm -rf "$artifact_dir"
  mkdir -p "$artifact_dir"
}

prepare_artifact_dir

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

should_retry_core_location_migration() {
  local boot_status="$1"
  local boot_log="$2"

  # The bounded perl alarm used by bootstatus exits 142. Do not turn an
  # arbitrary simctl failure that happens to mention CoreLocation into a retry.
  [[ "$boot_status" == "142" ]] || return 1
  [[ -f "$boot_log" ]] || return 1
  grep -Fq "CoreLocationMigrator.migrator" "$boot_log"
}

should_retry_ui_smoke_bootstrap_failure() {
  local xcode_status="$1"
  local xcode_log="$2"

  # Retry only the known XCUITest-runner bootstrap termination once. Product
  # assertion failures, timeouts, and arbitrary Xcode failures remain red.
  [[ "$xcode_status" == "65" ]] || return 1
  [[ -f "$xcode_log" ]] || return 1
  grep -Fq "Early unexpected exit, operation never finished bootstrapping" "$xcode_log" &&
    grep -Eq "Test crashed with signal (term|abrt) while preparing to run tests\." "$xcode_log"
}

result_bundle_is_corrupt() {
  # A phase-timeout alarm (or runner starvation) can kill xcodebuild mid-write,
  # leaving an xcresult directory without its Info.plist — xcresulttool then
  # refuses the bundle and the gate fails with NO failing test. Observed 6x on
  # 2026-08-02 (e.g. runs 30725941573, 30730370453, 30759152155). A MISSING
  # bundle stays a hard fail; only the half-written state is retryable.
  local result_bundle="$1"
  [[ -d "$result_bundle" ]] || return 1
  [[ ! -f "$result_bundle/Info.plist" ]]
}

preserve_corrupt_phase_attempt() {
  # Same evidence discipline as the bootstrap retry: the corrupt attempt's raw
  # output is retained before the retry may overwrite the result path.
  local phase="$1"
  local result_bundle="$2"
  local xcode_log="$3"
  mv "$xcode_log" "$artifact_dir/${phase}-corrupt-attempt-1-xcodebuild.log" || fail "could not preserve corrupt-attempt log for $phase"
  mv "$artifact_dir/${phase}-xcode-status.txt" "$artifact_dir/${phase}-corrupt-attempt-1-xcode-status.txt" || fail "could not preserve corrupt-attempt Xcode status for $phase"
  mv "$artifact_dir/${phase}-tee-status.txt" "$artifact_dir/${phase}-corrupt-attempt-1-tee-status.txt" || fail "could not preserve corrupt-attempt tee status for $phase"
  mv "$result_bundle" "$artifact_dir/${phase}-corrupt-attempt-1-${gate_name}.xcresult" || fail "could not preserve corrupt-attempt xcresult for $phase"
}

retry_phase_if_bundle_corrupt() {
  # One bounded re-run per phase, ONLY for the half-written-bundle state.
  local phase="$1"
  local scheme="$2"
  local result_bundle="$3"
  local xcode_log="$4"
  local phase_timeout="$5"
  shift 5
  if result_bundle_is_corrupt "$result_bundle"; then
    echo "$gate_name $phase produced a corrupt xcresult (no Info.plist); preserving evidence and retrying the phase once" | tee -a "$artifact_dir/gate.log"
    preserve_corrupt_phase_attempt "$phase" "$result_bundle" "$xcode_log"
    run_xcode_phase "$phase" "$scheme" "$result_bundle" "$xcode_log" "$phase_timeout" "$@"
    echo "${phase}_corrupt_bundle_retry=1" >> "$metadata_file"
  else
    echo "${phase}_corrupt_bundle_retry=0" >> "$metadata_file"
  fi
}

preserve_failed_ui_smoke_attempt() {
  # A bootstrap retry can only be trusted if the failed attempt's raw result is
  # retained. Do this check before moving any other evidence and before a retry
  # is allowed to overwrite the result path.
  [[ -d "$ui_result" ]] || fail "first UI-smoke attempt produced no xcresult bundle; refusing bootstrap retry"
  [[ -f "$artifact_dir/ui-smokes-xcode-status.txt" ]] || fail "first UI-smoke attempt produced no Xcode status; refusing bootstrap retry"
  [[ -f "$artifact_dir/ui-smokes-tee-status.txt" ]] || fail "first UI-smoke attempt produced no tee status; refusing bootstrap retry"
  mv "$ui_log" "$artifact_dir/ui-smokes-attempt-1-xcodebuild.log" || fail "could not preserve first UI-smoke log"
  mv "$artifact_dir/ui-smokes-xcode-status.txt" "$artifact_dir/ui-smokes-attempt-1-xcode-status.txt" || fail "could not preserve first UI-smoke Xcode status"
  mv "$artifact_dir/ui-smokes-tee-status.txt" "$artifact_dir/ui-smokes-attempt-1-tee-status.txt" || fail "could not preserve first UI-smoke tee status"
  mv "$ui_result" "$artifact_dir/ui-smokes-attempt-1-${gate_name}.xcresult" || fail "could not preserve first UI-smoke xcresult bundle"
}

wait_for_xcode_destination() {
  local deadline=$((SECONDS + 120))
  local destinations

  # simctl bootstatus can finish before Xcode's destination registry observes a
  # newly created simulator. Do not start a test phase until the exact UUID is
  # visible to the same scheme that will run the UI smoke.
  while (( SECONDS < deadline )); do
    destinations="$(xcodebuild -showdestinations \
      -workspace "$workspace/Weird Parts.xcworkspace" \
      -scheme "WiredPart-iOS-Stage9-Smokes" 2>&1)"
    printf '%s\n' "$destinations" >> "$artifact_dir/destination-readiness.log"
    if grep -Fq "$simulator_id" <<< "$destinations"; then
      return 0
    fi
    sleep 5
  done
  return 1
}

# Pure listing filters shared with the self-test; these never call simctl.
shutdown_simulator_udids() {
  grep "(Shutdown)" \
    | grep -oE '\([A-Fa-f0-9-]{36}\)' | tr -d '()'
}

shutdown_run_owned_simulator_udids() {
  grep -F "WPR2-CI-" \
    | grep "(Shutdown)" \
    | grep -oE '\([A-Fa-f0-9-]{36}\)' | tr -d '()'
}

if [[ "${IOS_BETA_GATE_SELF_TEST:-}" == "1" ]]; then
  self_test_dir="$(mktemp -d)"
  trap 'rm -rf "$self_test_dir"' EXIT
  migration_log="$self_test_dir/migration.log"
  unrelated_log="$self_test_dir/unrelated.log"
  ui_bootstrap_log="$self_test_dir/ui-bootstrap.log"
  ui_bootstrap_abort_log="$self_test_dir/ui-bootstrap-abort.log"
  printf 'Waiting on Data Migration\nReason:Running plugin com.apple.locationd.migrator (CoreLocationMigrator.migrator)\n' > "$migration_log"
  printf 'Waiting on BackBoard\n' > "$unrelated_log"
  printf 'Early unexpected exit, operation never finished bootstrapping\nTest crashed with signal term while preparing to run tests.\n' > "$ui_bootstrap_log"
  printf 'Early unexpected exit, operation never finished bootstrapping\nTest crashed with signal abrt while preparing to run tests.\n' > "$ui_bootstrap_abort_log"

  should_retry_core_location_migration 142 "$migration_log" || exit 1
  ! should_retry_core_location_migration 0 "$migration_log" || exit 1
  ! should_retry_core_location_migration 1 "$migration_log" || exit 1
  ! should_retry_core_location_migration 142 "$unrelated_log" || exit 1
  should_retry_ui_smoke_bootstrap_failure 65 "$ui_bootstrap_log" || exit 1
  should_retry_ui_smoke_bootstrap_failure 65 "$ui_bootstrap_abort_log" || exit 1
  ! should_retry_ui_smoke_bootstrap_failure 0 "$ui_bootstrap_log" || exit 1
  ! should_retry_ui_smoke_bootstrap_failure 65 "$unrelated_log" || exit 1

  artifact_dir="$self_test_dir/artifacts"
  gate_name="iPhone"
  ui_log="$self_test_dir/ui-smokes.log"
  ui_result="$self_test_dir/ui-smokes.xcresult"
  workspace="$self_test_dir/workspace"
  simulator_id="self-test-simulator-id"
  mkdir -p "$workspace/Weird Parts.xcworkspace" "$artifact_dir"
  xcodebuild() {
    printf 'Available destinations: id:%s\n' "$simulator_id"
  }
  wait_for_xcode_destination || exit 1
  [[ -s "$artifact_dir/destination-readiness.log" ]] || exit 1
  unset -f xcodebuild

  mkdir -p "$artifact_dir/stale-ui-smokes-iPhone.xcresult"
  prepare_artifact_dir
  [[ ! -e "$artifact_dir/stale-ui-smokes-iPhone.xcresult" ]] || exit 1

  prepare_first_ui_smoke_attempt() {
    rm -rf "$artifact_dir" "$ui_result"
    mkdir -p "$artifact_dir" "$ui_result"
    printf 'raw first attempt\n' > "$ui_result/Info.plist"
    printf 'bootstrap failure log\n' > "$ui_log"
    printf '65\n' > "$artifact_dir/ui-smokes-xcode-status.txt"
    printf '1\n' > "$artifact_dir/ui-smokes-tee-status.txt"
  }

  # A qualifying status-65/bootstrap fingerprint still must not retry without
  # a first-attempt result bundle; the retry would otherwise overwrite missing
  # evidence and turn the gate green.
  mkdir -p "$artifact_dir"
  printf 'bootstrap failure log\n' > "$ui_log"
  ui_result="$self_test_dir/missing-first-attempt.xcresult"
  if (preserve_failed_ui_smoke_attempt); then
    echo "self-test expected missing first UI-smoke xcresult to reject retry" >&2
    exit 1
  fi
  [[ ! -e "$artifact_dir/ui-smokes-attempt-1-iPhone.xcresult" ]] || exit 1

  ui_result="$self_test_dir/ui-smokes.xcresult"
  prepare_first_ui_smoke_attempt
  rm "$artifact_dir/ui-smokes-xcode-status.txt"
  if (preserve_failed_ui_smoke_attempt); then
    echo "self-test expected missing first UI-smoke Xcode status to reject retry" >&2
    exit 1
  fi
  [[ -d "$ui_result" ]] || exit 1

  prepare_first_ui_smoke_attempt
  rm "$artifact_dir/ui-smokes-tee-status.txt"
  if (preserve_failed_ui_smoke_attempt); then
    echo "self-test expected missing first UI-smoke tee status to reject retry" >&2
    exit 1
  fi
  [[ -d "$ui_result" ]] || exit 1

  prepare_first_ui_smoke_attempt
  mv() {
    if [[ "$1" == "$artifact_dir/ui-smokes-xcode-status.txt" ]]; then
      return 1
    fi
    command mv "$@"
  }
  if (preserve_failed_ui_smoke_attempt); then
    echo "self-test expected failed first UI-smoke Xcode status preservation to reject retry" >&2
    exit 1
  fi
  unset -f mv
  [[ -d "$ui_result" ]] || exit 1

  prepare_first_ui_smoke_attempt
  preserve_failed_ui_smoke_attempt
  [[ -f "$artifact_dir/ui-smokes-attempt-1-xcode-status.txt" ]] || exit 1
  [[ -f "$artifact_dir/ui-smokes-attempt-1-tee-status.txt" ]] || exit 1
  [[ -d "$artifact_dir/ui-smokes-attempt-1-iPhone.xcresult" ]] || exit 1
  [[ ! -e "$artifact_dir/ui-smokes-xcode-status.txt" ]] || exit 1
  [[ ! -e "$artifact_dir/ui-smokes-tee-status.txt" ]] || exit 1
  [[ ! -e "$ui_result" ]] || exit 1
  # Corrupt-bundle detector: half-written (dir, no Info.plist) = corrupt;
  # healthy (Info.plist present) and missing (no dir) = not retryable here.
  corrupt_dir="$self_test_dir/corrupt.xcresult"
  healthy_dir="$self_test_dir/healthy.xcresult"
  mkdir -p "$corrupt_dir" "$healthy_dir"
  touch "$healthy_dir/Info.plist"
  result_bundle_is_corrupt "$corrupt_dir" || exit 1
  result_bundle_is_corrupt "$healthy_dir" && exit 1
  result_bundle_is_corrupt "$self_test_dir/absent.xcresult" && exit 1

  # Exercise the production filters with synthetic listings only. UUID spelling
  # must not change selection; Booted devices must survive both cleanup paths,
  # and the normal device set must additionally preserve non-WPR2 devices.
  upper_udid="ABCDEF12-3456-7890-ABCD-EF1234567890"
  lower_udid="abcdef12-3456-7890-abcd-ef1234567890"
  mixed_udid="AbCdEf12-3456-7890-aBcD-Ef1234567890"
  booted_udid="11111111-2222-3333-4444-555555555555"
  unrelated_udid="66666666-7777-8888-9999-AAAAAAAAAAAA"
  simulator_fixture="$(printf '%s\n' \
    "WPR2-CI-iPhone-upper ($upper_udid) (Shutdown)" \
    "WPR2-CI-iPad-lower ($lower_udid) (Shutdown)" \
    "WPR2-CI-iPhone-mixed ($mixed_udid) (Shutdown)" \
    "WPR2-CI-iPad-active ($booted_udid) (Booted)" \
    "Personal iPhone ($unrelated_udid) (Shutdown)")"
  expected_run_owned="$(printf '%s\n' "$upper_udid" "$lower_udid" "$mixed_udid")"
  expected_testing="$(printf '%s\n' "$upper_udid" "$lower_udid" "$mixed_udid" "$unrelated_udid")"
  [[ "$(printf '%s\n' "$simulator_fixture" | shutdown_run_owned_simulator_udids)" == "$expected_run_owned" ]] || exit 1
  [[ "$(printf '%s\n' "$simulator_fixture" | shutdown_simulator_udids)" == "$expected_testing" ]] || exit 1
  echo "iOS beta-gate simulator cleanup fixtures passed"

  echo "iOS beta-gate bounded recovery self-test passed"
  exit 0
fi

for timeout_value in \
  "$simulator_boot_command_timeout_seconds" \
  "$simulator_boot_timeout_seconds" \
  "$simulator_boot_recovery_timeout_seconds" \
  "$xcode_phase_timeout_seconds" \
  "$ui_smoke_phase_timeout_seconds" \
  "$job_timeout_seconds" \
  "$cleanup_upload_margin_seconds"; do
  [[ "$timeout_value" =~ ^[0-9]+$ ]] && (( timeout_value > 0 )) || \
    fail "all timeout budgets must be positive integer seconds"
done
[[ "$minimum_free_gib" =~ ^[0-9]+$ ]] && (( minimum_free_gib > 0 )) || \
  fail "minimum free disk budget must be a positive integer in GiB"
[[ "$derived_data_stale_minutes" =~ ^[0-9]+$ ]] && (( derived_data_stale_minutes > 0 )) || \
  fail "DerivedData stale cutoff must be a positive integer in minutes"
(( cleanup_upload_margin_seconds < job_timeout_seconds )) || \
  fail "cleanup/upload margin must be smaller than the job timeout"
internal_budget_seconds=$((
  simulator_boot_command_timeout_seconds +
  simulator_boot_timeout_seconds +
  simulator_boot_recovery_timeout_seconds +
  xcode_phase_timeout_seconds +
  (2 * ui_smoke_phase_timeout_seconds)
))
available_internal_budget_seconds=$((job_timeout_seconds - cleanup_upload_margin_seconds))
(( internal_budget_seconds <= available_internal_budget_seconds )) || \
  fail "internal timeout budget ${internal_budget_seconds}s exceeds ${available_internal_budget_seconds}s after reserving cleanup/upload margin"

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
  echo "derived_data_stale_minutes=$derived_data_stale_minutes"
  echo "simulator_boot_command_timeout_seconds=$simulator_boot_command_timeout_seconds"
  echo "simulator_boot_timeout_seconds=$simulator_boot_timeout_seconds"
  echo "simulator_boot_recovery_timeout_seconds=$simulator_boot_recovery_timeout_seconds"
  echo "xcode_phase_timeout_seconds=$xcode_phase_timeout_seconds"
  echo "ui_smoke_phase_timeout_seconds=$ui_smoke_phase_timeout_seconds"
  echo "job_timeout_seconds=$job_timeout_seconds"
  echo "cleanup_upload_margin_seconds=$cleanup_upload_margin_seconds"
  echo "internal_budget_seconds=$internal_budget_seconds"
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
if (( available_kib < required_kib )); then
  # Below the disk budget: reclaim stale shared DerivedData before failing.
  # Only top-level entries idle past the cutoff are deleted; anything newer
  # may belong to a concurrent build on the other Mac runner and must survive.
  derived_data_cache="$HOME/Library/Developer/Xcode/DerivedData"
  echo "runner has ${available_gib} GiB free; deleting DerivedData entries older than ${derived_data_stale_minutes} minutes before failing" | tee -a "$artifact_dir/gate.log"
  # Parallel-testing simulator clones (~/Library/Developer/XCTestDevices, the
  # `--set testing` device set) accumulate 2+ per UI-test run and nothing else
  # deletes them — 270 clones drove the 2026-07-31 disk incident. Shutdown
  # clones only; a Booted clone belongs to the sibling runner's live gate.
  xcrun simctl --set testing list devices 2>/dev/null \
    | shutdown_simulator_udids \
    | while read -r stale_clone; do
        xcrun simctl --set testing delete "$stale_clone" >/dev/null 2>&1 || true
      done
  # Interrupted gate runs can also leave the run-owned simulator in the normal
  # device set before the cleanup step sees metadata. Restrict this to shutdown
  # WPR2-CI devices so a sibling runner's active simulator is never deleted.
  xcrun simctl list devices 2>/dev/null \
    | shutdown_run_owned_simulator_udids \
    | while read -r stale_device; do
        xcrun simctl delete "$stale_device" >/dev/null 2>&1 || true
      done
  if [[ -d "$derived_data_cache" ]]; then
    find "$derived_data_cache" -mindepth 1 -maxdepth 1 -mmin "+${derived_data_stale_minutes}" -print -exec rm -rf {} + \
      2>&1 | tee -a "$artifact_dir/gate.log" || true
  fi
  available_kib="$(df -Pk "$runner_temp" | awk 'NR == 2 {print $4}')"
  [[ "$available_kib" =~ ^[0-9]+$ ]] || fail "could not determine free disk space for $runner_temp after DerivedData cleanup"
  cleanup_freed_gib=$((available_kib / 1024 / 1024 - available_gib))
  available_gib=$((available_kib / 1024 / 1024))
  {
    echo "derived_data_cleanup_freed_gib=$cleanup_freed_gib"
    echo "post_cleanup_free_gib=$available_gib"
  } >> "$metadata_file"
  echo "DerivedData cleanup freed ${cleanup_freed_gib} GiB; ${available_gib} GiB now free" | tee -a "$artifact_dir/gate.log"
fi
(( available_kib >= required_kib )) || fail "runner has ${available_gib} GiB free; ${minimum_free_gib} GiB is required"

xcrun simctl list runtimes | grep -Fq "$runtime_id" || fail "required simulator runtime is unavailable: $runtime_id"
xcrun simctl list devicetypes | grep -Fq "$device_type" || fail "required simulator device type is unavailable: $device_type"

derived_data="$(mktemp -d "$runner_temp/wpr2-ios-beta-${1}.derived.XXXXXX")" || fail "cannot create temporary DerivedData directory"
simulator_name="WPR2-CI-${gate_name}-${GITHUB_RUN_ID:-manual}-${GITHUB_RUN_ATTEMPT:-1}"

create_simulator() {
  simulator_id="$(xcrun simctl create "$simulator_name" "$device_type" "$runtime_id")" || return 1
  echo "simulator_id=$simulator_id" >> "$metadata_file"
}

capture_simulator_diagnostics() {
  local attempt="$1"
  local diagnostics_file="$artifact_dir/boot-attempt-${attempt}-diagnostics.log"
  {
    echo "simulator_id=$simulator_id"
    xcrun simctl list devices "$runtime_id"
    xcrun simctl diagnose "$simulator_id"
  } > "$diagnostics_file" 2>&1 || true
}

boot_simulator() {
  local attempt="$1"
  local readiness_timeout_seconds="$2"
  local boot_log="$artifact_dir/boot-attempt-${attempt}.log"
  local boot_command_status
  local boot_pipeline_status

  /usr/bin/perl -e 'alarm shift; exec @ARGV' "$simulator_boot_command_timeout_seconds" \
    xcrun simctl boot "$simulator_id" \
    2>&1 | tee -a "$boot_log" "$artifact_dir/gate.log"
  boot_command_status=("${PIPESTATUS[@]}")
  [[ "${boot_command_status[0]}" == "0" ]] || return 10
  [[ "${boot_command_status[1]}" == "0" ]] || return 11

  /usr/bin/perl -e 'alarm shift; exec @ARGV' "$readiness_timeout_seconds" \
    xcrun simctl bootstatus "$simulator_id" -b \
    2>&1 | tee -a "$boot_log" "$artifact_dir/gate.log"
  boot_pipeline_status=("${PIPESTATUS[@]}")
  [[ "${boot_pipeline_status[0]}" == "0" ]] || return "${boot_pipeline_status[0]}"
  [[ "${boot_pipeline_status[1]}" == "0" ]] || return 21
  return 0
}

create_simulator || fail "cannot create $gate_name simulator"
boot_simulator 1 "$simulator_boot_timeout_seconds"
first_boot_status=$?
if (( first_boot_status != 0 )); then
  capture_simulator_diagnostics 1
  if should_retry_core_location_migration "$first_boot_status" "$artifact_dir/boot-attempt-1.log"; then
    echo "$gate_name boot readiness timed out during CoreLocation migration; recreating the run-owned simulator for one bounded recovery attempt" | tee -a "$artifact_dir/gate.log"
    xcrun simctl shutdown "$simulator_id" >/dev/null 2>&1 || true
    xcrun simctl delete "$simulator_id" >/dev/null 2>&1 || true
    simulator_id=""
    create_simulator || fail "cannot recreate $gate_name simulator after CoreLocation migration timeout"
    boot_simulator 2 "$simulator_boot_recovery_timeout_seconds"
    second_boot_status=$?
    if (( second_boot_status != 0 )); then
      capture_simulator_diagnostics 2
      fail "$gate_name simulator did not finish booting after bounded CoreLocation migration recovery (status $second_boot_status)"
    fi
  else
    fail "$gate_name simulator did not finish booting before the timeout (status $first_boot_status)"
  fi
fi

if ! wait_for_xcode_destination; then
  capture_simulator_diagnostics "destination-readiness"
  fail "$gate_name simulator booted but Xcode did not expose its UUID within 120 seconds"
fi

run_xcode_phase() {
  local phase="$1"
  local scheme="$2"
  local result_bundle="$3"
  local xcode_log="$4"
  local phase_timeout_seconds="$5"
  shift 5

  /usr/bin/perl -e 'alarm shift; exec @ARGV' "$phase_timeout_seconds" xcodebuild test \
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
  "unit-regression" "WiredPart-iOS" "$unit_result" "$unit_log" "$xcode_phase_timeout_seconds" \
  -skip-testing:"Weird PartsUITests"
retry_phase_if_bundle_corrupt \
  "unit-regression" "WiredPart-iOS" "$unit_result" "$unit_log" "$xcode_phase_timeout_seconds" \
  -skip-testing:"Weird PartsUITests"
run_xcode_phase \
  "ui-smokes" "WiredPart-iOS-Stage9-Smokes" "$ui_result" "$ui_log" "$ui_smoke_phase_timeout_seconds"

ui_smoke_bootstrap_retry=0
[[ -f "$artifact_dir/ui-smokes-xcode-status.txt" ]] || fail "missing Xcode status for ui-smokes"
if should_retry_ui_smoke_bootstrap_failure "$(<"$artifact_dir/ui-smokes-xcode-status.txt")" "$ui_log"; then
  echo "$gate_name UI-smoke test runner terminated during bootstrap; preserving first-attempt evidence and retrying the same deterministic plan once" | tee -a "$artifact_dir/gate.log"
  preserve_failed_ui_smoke_attempt
  ui_smoke_bootstrap_retry=1
  run_xcode_phase \
    "ui-smokes" "WiredPart-iOS-Stage9-Smokes" "$ui_result" "$ui_log" "$ui_smoke_phase_timeout_seconds"
fi
echo "ui_smoke_bootstrap_retry=$ui_smoke_bootstrap_retry" >> "$metadata_file"
retry_phase_if_bundle_corrupt \
  "ui-smokes" "WiredPart-iOS-Stage9-Smokes" "$ui_result" "$ui_log" "$ui_smoke_phase_timeout_seconds"

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
