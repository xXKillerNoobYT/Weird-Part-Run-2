import SwiftUI
import Testing
import UIKit
@testable import Weird_Parts

@Suite("TimelinePriorityColor")
@MainActor
struct TimelinePriorityColorTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func overdueDueDateUsesErrorToken() {
        let dueDate = now.addingTimeInterval(-3_600)

        #expect(colorsMatch(
            TimelinePriorityColor.color(forDueDate: dueDate, now: now),
            DS.SemanticColor.error
        ))
    }

    @Test func dueWithin24HoursUsesWarningToken() {
        let dueDate = now.addingTimeInterval(3_600)

        #expect(colorsMatch(
            TimelinePriorityColor.color(forDueDate: dueDate, now: now),
            DS.SemanticColor.warning
        ))
    }

    @Test func exactly24HoursUsesCautionToken() {
        let dueDate = now.addingTimeInterval(24 * 3_600)

        #expect(colorsMatch(
            TimelinePriorityColor.color(forDueDate: dueDate, now: now),
            DS.SemanticColor.caution
        ))
    }

    @Test func exactly96HoursUsesSuccessToken() {
        let dueDate = now.addingTimeInterval(96 * 3_600)

        #expect(colorsMatch(
            TimelinePriorityColor.color(forDueDate: dueDate, now: now),
            DS.SemanticColor.success
        ))
    }

    @Test func completedAndNilDueDatesUseNeutralTokens() {
        #expect(colorsMatch(
            TimelinePriorityColor.color(forDueDate: now.addingTimeInterval(-3_600), now: now, isCompleted: true),
            .gray
        ))
        #expect(colorsMatch(
            TimelinePriorityColor.color(forDueDate: nil as Date?, now: now),
            .secondary
        ))
    }

    @Test func priorityLabelDoesNotAffectTimeBasedColor() {
        let dueDate = now.addingTimeInterval(3_600)

        #expect(colorsMatch(
            TimelinePriorityColor.color(priority: "low", dueDate: dueDate, now: now),
            DS.SemanticColor.warning
        ))
    }

    @Test func urgencyLabelUsesInjectedClock() {
        #expect(TimelinePriorityColor.urgencyLabel(for: now.addingTimeInterval(-1), now: now) == "Overdue")
        #expect(TimelinePriorityColor.urgencyLabel(for: now.addingTimeInterval(3_600), now: now) == "Due today")
        #expect(TimelinePriorityColor.urgencyLabel(for: now.addingTimeInterval(72 * 3_600), now: now) == "Due in 3d")
        #expect(TimelinePriorityColor.urgencyLabel(for: nil as Date?, now: now) == "No deadline")
        #expect(TimelinePriorityColor.urgencyLabel(for: now, now: now, isCompleted: true) == "Completed")
    }
}

private func colorsMatch(_ actual: Color, _ expected: Color) -> Bool {
    let actualColor = UIColor(actual).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
    let expectedColor = UIColor(expected).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))

    var actualRed: CGFloat = 0
    var actualGreen: CGFloat = 0
    var actualBlue: CGFloat = 0
    var actualAlpha: CGFloat = 0
    var expectedRed: CGFloat = 0
    var expectedGreen: CGFloat = 0
    var expectedBlue: CGFloat = 0
    var expectedAlpha: CGFloat = 0

    guard actualColor.getRed(&actualRed, green: &actualGreen, blue: &actualBlue, alpha: &actualAlpha),
          expectedColor.getRed(&expectedRed, green: &expectedGreen, blue: &expectedBlue, alpha: &expectedAlpha) else {
        return false
    }

    return abs(actualRed - expectedRed) < 0.001
        && abs(actualGreen - expectedGreen) < 0.001
        && abs(actualBlue - expectedBlue) < 0.001
        && abs(actualAlpha - expectedAlpha) < 0.001
}
