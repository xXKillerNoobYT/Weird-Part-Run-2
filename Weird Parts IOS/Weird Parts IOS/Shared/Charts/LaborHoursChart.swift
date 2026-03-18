import SwiftUI
import Charts

/// Bar chart showing labor hours by day for the past 7 days.
///
/// Displays regular vs overtime hours stacked per day. Uses the
/// labor_entries table aggregated by date.
struct LaborHoursChart: View {
    let data: [LaborDayData]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Labor Hours (Past 7 Days)")
                .font(.headline)

            if data.isEmpty {
                Text("No labor data available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Chart(data) { day in
                    BarMark(
                        x: .value("Day", day.dayLabel),
                        y: .value("Hours", day.regularHours)
                    )
                    .foregroundStyle(Color.accentColor)

                    if day.overtimeHours > 0 {
                        BarMark(
                            x: .value("Day", day.dayLabel),
                            y: .value("Hours", day.overtimeHours)
                        )
                        .foregroundStyle(.orange)
                    }
                }
                .chartYAxisLabel("Hours")
                .frame(height: 200)

                // Legend
                HStack(spacing: 16) {
                    Label("Regular", systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                    Label("Overtime", systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding()
        .dsCard()
    }
}

struct LaborDayData: Identifiable, Sendable {
    let id = UUID()
    let dayLabel: String   // e.g. "Mon", "Tue"
    let date: String       // ISO date string
    let regularHours: Double
    let overtimeHours: Double
}
