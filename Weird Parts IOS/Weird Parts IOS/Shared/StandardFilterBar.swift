import SwiftUI

enum StandardFilterBarLayout {
    static let minimumTapTarget: CGFloat = 44
}

struct StandardFilterBarCustomRange: Equatable {
    let start: Date
    let end: Date

    static func normalized(start: Date, end: Date) -> StandardFilterBarCustomRange {
        guard start <= end else {
            return StandardFilterBarCustomRange(start: start, end: start)
        }
        return StandardFilterBarCustomRange(start: start, end: end)
    }
}

enum StandardFilterBarDateFilter {
    static func contains(
        _ isoDateString: String?,
        selectedRange: ReportDateRange,
        customStart: Date,
        customEnd: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard let date = date(from: isoDateString, calendar: calendar) else { return false }
        let interval = selectedRange.dateInterval(containing: Date(), calendar: calendar)
        let start = calendar.startOfDay(for: interval?.start ?? customStart)
        let end = calendar.startOfDay(for: interval?.end ?? customEnd)
        let itemDate = calendar.startOfDay(for: date)

        return itemDate >= min(start, end) && itemDate <= max(start, end)
    }

    private static func date(from isoDateString: String?, calendar: Calendar) -> Date? {
        guard let raw = isoDateString?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }

        let dateOnly = String(raw.prefix(10))
        let components = dateOnly.split(separator: "-")
        guard components.count == 3,
              let year = Int(components[0]),
              let month = Int(components[1]),
              let day = Int(components[2]) else {
            return nil
        }

        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}

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
                                .frame(minWidth: StandardFilterBarLayout.minimumTapTarget, minHeight: StandardFilterBarLayout.minimumTapTarget)
                                .background(
                                    Capsule().fill(selectedRange == option ? Color.accentColor : Color.secondary.opacity(0.15))
                                )
                                .foregroundStyle(selectedRange == option ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Capsule())
                        .accessibilityIdentifier("dateRangeChip_\(option.accessibilityKey)")
                        .accessibilityLabel(option.rawValue)
                        .accessibilityValue(selectedRange == option ? "Selected" : "Not selected")
                        .accessibilityAddTraits(selectedRange == option ? .isSelected : [])
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            // Custom date pickers — only show when Custom is selected
            if selectedRange == .custom {
                ViewThatFits(in: .horizontal) {
                    customRangeControls(axis: .horizontal)
                    customRangeControls(axis: .vertical)
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedRange)
        .onAppear(perform: normalizeCustomRange)
        .onChange(of: customStart) { _, _ in normalizeCustomRange() }
        .onChange(of: customEnd) { _, _ in normalizeCustomRange() }
    }

    private var validatedCustomStart: Binding<Date> {
        Binding(
            get: { customStart },
            set: { customStart = min($0, customEnd) }
        )
    }

    private var validatedCustomEnd: Binding<Date> {
        Binding(
            get: { customEnd },
            set: { customEnd = max($0, customStart) }
        )
    }

    @ViewBuilder
    private func customRangeControls(axis: Axis) -> some View {
        if axis == .horizontal {
            HStack(spacing: 12) {
                customStartPicker
                rangeSeparator
                customEndPicker
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                customStartPicker
                customEndPicker
            }
        }
    }

    private var customStartPicker: some View {
        DatePicker("From", selection: validatedCustomStart, in: ...customEnd, displayedComponents: .date)
            .labelsHidden()
            .frame(minHeight: StandardFilterBarLayout.minimumTapTarget)
            .accessibilityIdentifier("dateRangeCustomStart")
    }

    private var customEndPicker: some View {
        DatePicker("To", selection: validatedCustomEnd, in: customStart..., displayedComponents: .date)
            .labelsHidden()
            .frame(minHeight: StandardFilterBarLayout.minimumTapTarget)
            .accessibilityIdentifier("dateRangeCustomEnd")
    }

    private var rangeSeparator: some View {
        Image(systemName: "arrow.right")
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }

    private func normalizeCustomRange() {
        let normalized = StandardFilterBarCustomRange.normalized(start: customStart, end: customEnd)
        guard customStart != normalized.start || customEnd != normalized.end else { return }
        customStart = normalized.start
        customEnd = normalized.end
    }

    /// Backward-compatible initializer for pages that only track start/end dates.
    /// Defaults to `.custom` so the date pickers are always visible.
    init(startDate: Binding<Date>, endDate: Binding<Date>) {
        self._selectedRange = .constant(.custom)
        self._customStart = startDate
        self._customEnd = endDate
    }
}

private extension ReportDateRange {
    var accessibilityKey: String {
        rawValue
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
    }
}
