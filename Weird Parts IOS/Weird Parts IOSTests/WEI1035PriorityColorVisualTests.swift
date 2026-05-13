import SwiftUI
import XCTest
@testable import Weird_Parts

@MainActor
final class WEI1035PriorityColorVisualTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testCapturePriorityColorEvidence() throws {
        let outputDirectory = try screenshotDirectory()
        let scenarios: [(name: String, size: CGSize, scheme: ColorScheme)] = [
            ("iphone-375x812-light", CGSize(width: 375, height: 812), .light),
            ("iphone-375x812-dark", CGSize(width: 375, height: 812), .dark),
            ("desktop-1280x800-light", CGSize(width: 1280, height: 800), .light),
            ("desktop-1280x800-dark", CGSize(width: 1280, height: 800), .dark)
        ]

        for scenario in scenarios {
            let view = WEI1035PriorityColorEvidenceView(now: now)
                .environment(\.colorScheme, scenario.scheme)
                .frame(width: scenario.size.width, height: scenario.size.height)

            let image = render(view, size: scenario.size)
            guard let pngData = image.pngData() else {
                XCTFail("Could not encode \(scenario.name)")
                continue
            }

            let url = outputDirectory.appendingPathComponent("WEI-1035-\(scenario.name).png")
            try pngData.write(to: url)

            let attachment = XCTAttachment(image: image)
            attachment.name = "WEI-1035-\(scenario.name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func screenshotDirectory() throws -> URL {
        let path = ProcessInfo.processInfo.environment["WEI1035_SCREENSHOT_DIR"]
            ?? NSTemporaryDirectory()
        let url = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func render<Content: View>(_ content: Content, size: CGSize) -> UIImage {
        let controller = UIHostingController(rootView: content)
        controller.view.bounds = CGRect(origin: .zero, size: size)
        controller.view.backgroundColor = .clear
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        return UIGraphicsImageRenderer(size: size).image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
    }
}

private struct WEI1035PriorityColorEvidenceView: View {
    let now: Date

    private var samples: [(title: String, priority: String, dueDate: Date?)] {
        [
            ("Overdue permit answer", "low", now.addingTimeInterval(-3_600)),
            ("Due today supplier callback", "low", now.addingTimeInterval(3_600)),
            ("Due in four-day window", "urgent", now.addingTimeInterval(72 * 3_600)),
            ("Safe future delivery", "urgent", now.addingTimeInterval(120 * 3_600)),
            ("No deadline parking lot", "urgent", nil)
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Priority Color Verification")
                    .font(.title2.weight(.semibold))
                Text("Time remaining controls color. Priority labels are intentionally mixed to prove labels do not drive color.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 260), spacing: 12, alignment: .top)],
                    spacing: 12
                ) {
                    ForEach(samples, id: \.title) { sample in
                        priorityCard(sample)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func priorityCard(_ sample: (title: String, priority: String, dueDate: Date?)) -> some View {
        let color = TimelinePriorityColor.color(priority: sample.priority, dueDate: sample.dueDate, now: now)
        let label = TimelinePriorityColor.urgencyLabel(for: sample.dueDate, now: now)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(color)
                    .frame(width: 14, height: 14)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(sample.title)
                        .font(.headline)
                    Text("Priority label: \(sample.priority.capitalized)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
            }

            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(color.opacity(0.16)))
                .foregroundStyle(color)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemGroupedBackground)))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.45), lineWidth: 1)
        )
    }
}
