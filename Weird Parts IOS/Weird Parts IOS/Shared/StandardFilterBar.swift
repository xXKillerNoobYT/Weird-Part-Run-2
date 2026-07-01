import SwiftUI

/// Reusable horizontal date filter bar with quick-pick buttons and custom date range picker.
///
/// Accessibility contract: quick chips keep at least a 44x44pt hit target,
/// expose stable identifiers, and report selected state to VoiceOver.
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
    static let minimumChipTapTarget: CGFloat = 44

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
                            if option == .custom {
                                normalizeCustomRange()
                            }
                        } label: {
                            Text(option.rawValue)
                                .font(.caption)
                                .fontWeight(selectedRange == option ? .bold : .regular)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .frame(minWidth: Self.minimumChipTapTarget, minHeight: Self.minimumChipTapTarget)
                                .background(
                                    Capsule().fill(selectedRange == option ? Color.accentColor : Color.secondary.opacity(0.15))
                                )
                                .foregroundStyle(selectedRange == option ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("dateRangeChip_\(option.accessibilityIdentifier)")
                        .accessibilityValue(selectedRange == option ? "Selected" : "Not selected")
                        .accessibilityAddTraits(selectedRange == option ? .isSelected : [])
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            // Custom date pickers — only show when Custom is selected
            if selectedRange == .custom {
                HStack(spacing: 12) {
                    DatePicker("From", selection: normalizedCustomStart, displayedComponents: .date)
                        .labelsHidden()
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                    DatePicker("To", selection: normalizedCustomEnd, displayedComponents: .date)
                        .labelsHidden()
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear(perform: normalizeCustomRange)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedRange)
    }

    private var normalizedCustomStart: Binding<Date> {
        Binding(
            get: { customStart },
            set: { newStart in
                customStart = newStart
                if customEnd < newStart {
                    customEnd = newStart
                }
            }
        )
    }

    private var normalizedCustomEnd: Binding<Date> {
        Binding(
            get: { customEnd },
            set: { newEnd in
                customEnd = max(newEnd, customStart)
            }
        )
    }

    private func normalizeCustomRange() {
        guard customStart > customEnd else { return }
        customEnd = customStart
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
    var accessibilityIdentifier: String {
        switch self {
        case .thisWeek: return "this_week"
        case .lastWeek: return "last_week"
        case .thisPeriod: return "this_period"
        case .lastPeriod: return "last_period"
        case .thisMonth: return "this_month"
        case .lastMonth: return "last_month"
        case .thisQuarter: return "this_quarter"
        case .thisYear: return "this_year"
        case .custom: return "custom"
        }
    }
}
