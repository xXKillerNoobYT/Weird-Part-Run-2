#!/bin/bash
# Runs the same phone/tablet simulator classes selected by the WPR2 Xcode Cloud
# workflow. It deliberately never archives or uploads an IPA: this is a PR
# verification gate only.
set -euo pipefail

artifact_root="${WPR2_CI_ARTIFACT_ROOT:?WPR2_CI_ARTIFACT_ROOT is required}"
minimum_gib="${WPR2_MIN_FREE_GIB:-60}"
runtime="${WPR2_IOS_RUNTIME:-com.apple.CoreSimulator.SimRuntime.iOS-26-5}"
derived_data="$artifact_root/DerivedData"
summary="$artifact_root/summary.txt"
created_devices=""
overall_status=0

mkdir -p "$artifact_root"

cleanup() {
  local udid
  while IFS= read -r udid; do
    [ -z "$udid" ] || xcrun simctl delete "$udid" >/dev/null 2>&1 || true
  done <<EOF
$created_devices
EOF
  rm -rf "$derived_data"
}
trap cleanup EXIT

available_kib=$(df -k /System/Volumes/Data | awk 'NR == 2 { print $4 }')
required_kib=$((minimum_gib * 1024 * 1024))
if [ -z "$available_kib" ] || [ "$available_kib" -lt "$required_kib" ]; then
  printf 'FAIL: runner has %s KiB free on /System/Volumes/Data; need at least %s GiB.\n' \
    "${available_kib:-unknown}" "$minimum_gib" | tee "$summary"
  exit 1
fi

printf 'Runner free space: %s KiB (minimum: %s GiB)\n' "$available_kib" "$minimum_gib" | tee "$summary"
xcodebuild -version | tee -a "$summary"
xcrun simctl list runtimes | grep -F "$runtime" >/dev/null || {
  printf 'FAIL: required simulator runtime is unavailable: %s\n' "$runtime" | tee -a "$summary"
  exit 1
}

# Format: stable artifact slug | exact Xcode Cloud display name | simulator type ID
matrix=(
  'ipad-air-13-m2|iPad Air 13-inch (M2)|com.apple.CoreSimulator.SimDeviceType.iPad-Air-13-inch-M2'
  'iphone-16-pro-max|iPhone 16 Pro Max|com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max'
  'ipad-pro-13-m4-16gb|iPad Pro 13-inch (M4) (16GB)|com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M4-16GB'
  'ipad-mini-6|iPad mini (6th generation)|com.apple.CoreSimulator.SimDeviceType.iPad-mini-6th-generation'
  'iphone-16-pro|iPhone 16 Pro|com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro'
  'ipad-10|iPad (10th generation)|com.apple.CoreSimulator.SimDeviceType.iPad-10th-generation'
  'iphone-16|iPhone 16|com.apple.CoreSimulator.SimDeviceType.iPhone-16'
  'iphone-se-3|iPhone SE (3rd generation)|com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation'
)

for entry in "${matrix[@]}"; do
  IFS='|' read -r slug display_name device_type <<< "$entry"
  device_name="WPR2-CI-${slug}-${GITHUB_RUN_ID:-manual}-${RANDOM}"
  log="$artifact_root/${slug}.log"
  result="$artifact_root/${slug}.xcresult"

  if ! udid=$(xcrun simctl create "$device_name" "$device_type" "$runtime"); then
    printf 'FAIL: %s simulator could not be created.\n' "$display_name" | tee -a "$summary"
    overall_status=1
    continue
  fi
  created_devices="${created_devices}${udid}"$'\n'

  if ! xcrun simctl boot "$udid"; then
    printf 'FAIL: %s simulator could not boot.\n' "$display_name" | tee -a "$summary"
    overall_status=1
    continue
  fi
  xcrun simctl bootstatus "$udid" -b

  printf '\n=== %s ===\n' "$display_name" | tee -a "$summary"
  if xcodebuild test \
    -workspace 'Weird Parts.xcworkspace' \
    -scheme 'WiredPart-iOS' \
    -destination "id=$udid" \
    -parallel-testing-enabled NO \
    -derivedDataPath "$derived_data" \
    -resultBundlePath "$result" \
    >"$log" 2>&1; then
    printf 'PASS: %s\n' "$display_name" | tee -a "$summary"
  else
    printf 'FAIL: %s (see %s)\n' "$display_name" "$(basename "$log")" | tee -a "$summary"
    tail -n 120 "$log" || true
    overall_status=1
  fi
done

exit "$overall_status"
