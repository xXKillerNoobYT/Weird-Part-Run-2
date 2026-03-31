import SwiftUI

/// Reusable delivery timeline bar showing progress from order date to expected delivery.
///
/// Displays a colored progress bar and status text:
/// - Green: 7+ days remaining
/// - Yellow: 3-6 days remaining
/// - Orange: 1-2 days remaining or due today
/// - Red: overdue
/// - Green filled: received
///
/// Usage:
/// ```swift
/// DeliveryTimelineBar(
///     orderDateString: line.createdAt,
///     expectedDateString: po.expectedDelivery,
///     isReceived: line.lineStatus == "received"
/// )
/// ```
struct DeliveryTimelineBar: View {
    let orderDate: Date?
    let expectedDate: Date?
    let isReceived: Bool

    /// Convenience init accepting ISO-8601 date strings (common in the codebase).
    init(orderDateString: String?, expectedDateString: String?, isReceived: Bool = false) {
        self.orderDate = Self.parseDate(orderDateString)
        self.expectedDate = Self.parseDate(expectedDateString)
        self.isReceived = isReceived
    }

    /// Direct Date init.
    init(orderDate: Date?, expectedDate: Date?, isReceived: Bool = false) {
        self.orderDate = orderDate
        self.expectedDate = expectedDate
        self.isReceived = isReceived
    }

    // MARK: - Computed Properties

    /// Days remaining until expected delivery (negative = overdue).
    var daysRemaining: Int? {
        guard let expected = expectedDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: expected).day
    }

    /// Progress from 0.0 to 1.0 based on elapsed time vs total expected time.
    var progress: Double {
        guard let order = orderDate, let expected = expectedDate else { return 0 }
        let total = expected.timeIntervalSince(order)
        let elapsed = Date().timeIntervalSince(order)
        guard total > 0 else { return 1.0 }
        return min(max(elapsed / total, 0), 1.0)
    }

    /// Bar color based on delivery status.
    var color: Color {
        if isReceived { return .green }
        guard let days = daysRemaining else { return .secondary }
        if days < 0 { return .red }
        if days < 3 { return .orange }
        if days < 7 { return .yellow }
        return .green
    }

    /// Human-readable status label.
    var statusText: String {
        if isReceived { return "Received" }
        guard let days = daysRemaining else { return "No ETA" }
        if days < 0 { return "\(-days)d overdue" }
        if days == 0 { return "Due today" }
        return "\(days)d remaining"
    }

    /// Days elapsed since order date.
    var daysElapsed: Int {
        guard let order = orderDate else { return 0 }
        return max(0, Calendar.current.dateComponents([.day], from: order, to: Date()).day ?? 0)
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geo.size.width * (isReceived ? 1.0 : progress))
                }
            }
            .frame(height: 4)

            HStack {
                if !isReceived {
                    Text("Day \(daysElapsed)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(statusText)
                    .font(.caption)
                    .fontWeight(daysRemaining ?? 0 < 0 && !isReceived ? .bold : .regular)
                    .foregroundStyle(color)
            }
        }
    }

    // MARK: - Helpers

    /// Parse an ISO-8601 date string (first 10 characters) into a Date.
    private static func parseDate(_ str: String?) -> Date? {
        guard let str, !str.isEmpty else { return nil }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate]
        return fmt.date(from: String(str.prefix(10)))
    }
}
