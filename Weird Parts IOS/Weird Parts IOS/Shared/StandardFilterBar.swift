import SwiftUI

/// Reusable horizontal date filter bar with quick-pick buttons and custom date range picker.
///
/// Usage:
/// ```
/// @State private var dateRange: ReportDateRange = .thisWeek
/// @State private var customStart: Date = Date().addingTimeInterval(-7 * 86400)
/// @State private var customEnd: Date = Date()
///
/// StandardFilterBar(
///     selectedRange: $dateRange,
///     customStart: $customStart,
///     customEnd: $customEnd
/// )
/// ```
///
/// Read the effective dates via `effectiveStart` and `effectiveEnd`:
/// ```
/// var effectiveStart: Date {
///     dateRange.dateInterval?.start ?? customStart
/// }
/// var effectiveEnd: Date {
///     dateRange.dateInterval?.end ?? customEnd
/// }
/// ```
struct StandardFilterBar: View {
    @Binding var selectedRange: ReportDateRange
    @Binding var customStart: Date
    @Binding var customEnd: Date

    /// Which quick buttons to show. Defaults to the most common set.
    var quickOptions: [ReportDateRange] = [.thisWeek, .lastWeek, .thisPeriod, .lastPeriod, .thisMonth, .custom]

    init(
        selectedRange: Binding<ReportDateRange>,
        customStart: Binding<Date>,
        customEnd: Binding<Date>,
        quickOptions: [ReportDateRange] = [.thisWeek, .lastWeek, .thisPeriod, .lastPeriod, .thisMonth, .custom]
    ) {
        self._selectedRange = selectedRange
        self._customStart = customStart
        self._customEnd = customEnd
        self.quickOptions = quickOptions
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickOptions) { option in
                        Button {
                            selectedRange = option
                        } label: {
                            Text(option.rawValue)
                                .font(.caption)
                                .fontWeight(selectedRange == option ? .bold : .regular)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule().fill(selectedRange == option ? Color.accentColor : Color.secondary.opacity(0.15))
                                )
                                .foregroundStyle(selectedRange == option ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            // Custom date pickers — only show when Custom is selected
            if selectedRange == .custom {
                HStack(spacing: 12) {
                    DatePicker("From", selection: $customStart, displayedComponents: .date)
                        .labelsHidden()
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                    DatePicker("To", selection: $customEnd, displayedComponents: .date)
                        .labelsHidden()
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedRange)
    }

    /// Backward-compatible initializer for pages that only track start/end dates.
    /// Defaults to `.custom` so the date pickers are always visible.
    init(startDate: Binding<Date>, endDate: Binding<Date>) {
        self._selectedRange = .constant(.custom)
        self._customStart = startDate
        self._customEnd = endDate
    }
}
