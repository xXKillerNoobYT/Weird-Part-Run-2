import SwiftUI
import Charts

/// Line chart showing daily mileage over the past 14 days.
///
/// Used on the Fleet dashboard and vehicle detail pages.
struct MileageChart: View {
    let data: [MileageDayData]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mileage (Past 14 Days)")
                .font(.headline)

            if data.isEmpty {
                Text("No mileage data available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                Chart(data) { day in
                    LineMark(
                        x: .value("Day", day.dayLabel),
                        y: .value("Miles", day.miles)
                    )
                    .foregroundStyle(Color.accentColor)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Day", day.dayLabel),
                        y: .value("Miles", day.miles)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.3), Color.accentColor.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Day", day.dayLabel),
                        y: .value("Miles", day.miles)
                    )
                    .foregroundStyle(Color.accentColor)
                    .symbolSize(20)
                }
                .chartYAxisLabel("Miles")
                .frame(height: 180)

                // Summary
                HStack(spacing: 20) {
                    VStack(spacing: 2) {
                        Text(String(format: "%.0f", data.reduce(0) { $0 + $1.miles }))
                            .font(.headline)
                        Text("Total Miles")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    VStack(spacing: 2) {
                        let avg = data.isEmpty ? 0.0 : data.reduce(0) { $0 + $1.miles } / Double(data.count)
                        Text(String(format: "%.0f", avg))
                            .font(.headline)
                        Text("Daily Avg")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .dsCard()
    }
}

struct MileageDayData: Identifiable, Sendable {
    let id = UUID()
    let dayLabel: String
    let date: String
    let miles: Double
}
