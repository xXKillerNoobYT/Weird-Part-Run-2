#!/usr/bin/env python3
"""Host-side source policy checks for the Panel Quality PR.

These checks intentionally run from GitHub Actions against the checkout rather
than from an iOS XCTest bundle: simulator and Xcode Cloud test runners do not
have a source checkout to read at runtime (#1492).
"""

from __future__ import annotations

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]


def source(relative_path: str) -> str:
    path = ROOT / relative_path
    if not path.is_file():
        raise AssertionError(f"Missing required source file: {relative_path}")
    return path.read_text(encoding="utf-8")


def require(text: str, needle: str, description: str) -> None:
    if needle not in text:
        raise AssertionError(description)


def require_count(text: str, needle: str, minimum: int, description: str) -> None:
    if text.count(needle) < minimum:
        raise AssertionError(description)


def main() -> int:
    craft_kit = source("Weird Parts IOS/Weird Parts IOS/DesignSystem/Components/CraftKit.swift")
    panel_builder = source("Weird Parts IOS/Weird Parts IOS/Features/Notebooks/PanelScheduleBuilder.swift")
    review_page = source("Weird Parts IOS/Weird Parts IOS/Sync/SyncConflictReviewPage.swift")
    conflict_choices = source("Weird Parts IOS/Weird Parts IOS/Sync/AIConflictResolutionView.swift")
    app_core = source("Weird Parts IOS/Weird Parts IOS/App/AppCore.swift")
    screenshot_tests = source("Weird Parts IOS/Weird Parts IOSUITests/ConflictScreenshotCaptureUITests.swift")

    require(craft_kit, "struct PanelQualityInstructionBanner", "Shared instruction banner is missing")
    require(craft_kit, ".dsMinTapTarget()", "Banner must retain the shared 44pt target floor")
    require(craft_kit, "accessibilityIdentifier: String", "Banner needs a stable accessibility identifier")
    require(craft_kit, ".accessibilityIdentifier(accessibilityIdentifier)", "Banner must expose its stable identifier")
    require(craft_kit, ".accessibilityLabel(message)", "Banner must expose its guidance to VoiceOver")
    require(craft_kit, ".fixedSize(horizontal: false, vertical: true)", "Banner text must wrap vertically")
    if craft_kit.index(".layoutPriority(1)") > craft_kit.index(".padding(.horizontal, DS.Space.sm)"):
        raise AssertionError("Banner must constrain wrapping text before outer padding")

    require(panel_builder, "PanelQualityInstructionBanner(", "Panel move mode must use the shared banner")
    require(panel_builder, "panelScheduleMoveModeBanner", "Panel move-mode banner needs a stable identifier")
    require(review_page, "PanelQualityInstructionBanner(", "Conflict review must show review guidance")
    require(review_page, "syncConflictReviewInstructionBanner", "Conflict review banner needs a stable identifier")
    require(review_page, "requestCriticalResolution(conflict, keepLocal: true)", "Critical local choice must remain actionable")
    require(review_page, "requestCriticalResolution(conflict, keepLocal: false)", "Critical remote choice must remain actionable")
    require(review_page, "resolveText(conflict, selectedValue: selectedValue)", "Hard-conflict choice must retain its selected value")
    require(review_page, "@State private var activeAlert", "Review page must own the critical confirmation presenter")
    require(review_page, "case critical(PendingCriticalResolution)", "Critical confirmation state is missing")

    require(conflict_choices, "syncConflictUseLocalValue", "Local critical-choice identifier is missing")
    require(conflict_choices, "syncConflictUseRemoteValue", "Remote critical-choice identifier is missing")
    require_count(conflict_choices, ".dsMinTapTarget()", 2, "Both critical choices need 44pt targets")
    require_count(conflict_choices, "#if targetEnvironment(macCatalyst)", 2, "Catalyst overlays must remain platform-scoped")
    require_count(conflict_choices, ".accessibilityAction", 2, "Both critical choices need default VoiceOver actions")

    require(app_core, "case fixturePartMissing(String)", "UI fixture failure must remain explicit")
    require(app_core, "throw UITestBootstrapError.fixturePartMissing(\"UITEST-QA-CONDUIT\")", "Fixture lookup must fail safely")
    require(app_core, "code = 'UITEST-QA-CONDUIT' AND is_active = 1 AND deleted_at IS NULL", "Fixture lookup must reject inactive or deleted parts")
    require(screenshot_tests, "identifier == %@ OR label == %@", "Critical confirmation buttons need identifier-or-label discovery")

    print("panel-quality source policy: PASS")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, OSError) as error:
        print(f"panel-quality source policy: FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
