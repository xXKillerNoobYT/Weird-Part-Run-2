import SwiftUI

// MARK: - Quick Filter

/// Standard quick date filter options used across all date-relevant pages.
enum QuickDateFilter: String, CaseIterable, Sendable {
    case thisWeek = "This Week"
    case lastWeek = "Last Week"
    case thisPeriod = "This Period"
    case lastPeriod = "Last Period"
    case thisMonth = "This Month"
    case custom = "Custom"

    /// Compute the start date for this quick filter.
    var startDate: Date {
        let cal = Calendar.current
        switch self {
        case .thisWeek:
            return cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        case .lastWeek:
            let lastWeek = cal.date(byAdding: .weekOfYear, value: -1, to: Date()) ?? Date()
            return cal.dateInterval(of: .weekOfYear, for: lastWeek)?.start ?? lastWeek
        case .thisPeriod:
            return Self.payPeriodStart(offset: 0)
        case .lastPeriod:
            return Self.payPeriodStart(offset: -1)
        case .thisMonth:
            return cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
        case .custom:
            return Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        }
    }

    /// Compute the end date for this quick filter.
    var endDate: Date {
        let cal = Calendar.current
        switch self {
        case .lastWeek:
            let lastWeek = cal.date(byAdding: .weekOfYear, value: -1, to: Date()) ?? Date()
            return cal.dateInterval(of: .weekOfYear, for: lastWeek)?.end ?? Date()
        case .lastPeriod:
            return Self.payPeriodStart(offset: 0)
        default:
            return Date()
        }
    }

    // MARK: - Pay Period Helpers

    /// Bi-weekly pay period anchored to Jan 1, 2024.
    /// `offset` 0 = current period, -1 = last period, etc.
    private static func payPeriodStart(offset: Int) -> Date {
        let cal = Calendar.current
        let anchor = cal.date(from: DateComponents(year: 2024, month: 1, day: 1)) ?? Date()
        let daysSinceAnchor = cal.dateComponents([.day], from: anchor, to: Date()).day ?? 0
        let currentPeriodDay = daysSinceAnchor - (daysSinceAnchor % 14)
        let targetPeriodDay = currentPeriodDay + (offset * 14)
        return cal.date(byAdding: .day, value: targetPeriodDay, to: anchor) ?? Date()
    }
}

// MARK: - Standard Filter Bar

/// Reusable date filter bar with quick filters, optional custom date range, and
/// a slot for page-specific additional filters.
///
/// Usage:
///   StandardFilterBar(startDate: $startDate, endDate: $endDate)
///
///   StandardFilterBar(startDate: $startDate, endDate: $endDate) {
///       // Additional filter views (employee picker, job picker, etc.)
///   }
struct StandardFilterBar<AdditionalFilters: View>: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    @State private var selectedQuickFilter: QuickDateFilter = .thisWeek
    @State private var showCustomRange = false
    let additionalFilters: () -> AdditionalFilters

    init(
        startDate: Binding<Date>,
        endDate: Binding<Date>,
        @ViewBuilder additionalFilters: @escaping () -> AdditionalFilters
    ) {
        self._startDate = startDate
        self._endDate = endDate
        self.additionalFilters = additionalFilters
    }

    var body: some View {
        VStack(spacing: 8) {
            // Quick filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(QuickDateFilter.allCases, id: \.self) { filter in
                        FilterChip(
                            label: filter.rawValue,
                            isActive: selectedQuickFilter == filter
                        ) {
                            selectedQuickFilter = filter
                            if filter == .custom {
                                showCustomRange = true
                            } else {
                                applyQuickFilter(filter)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }

            // Custom date range (expandable)
            if showCustomRange {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("From").font(.caption2).foregroundStyle(.secondary)
                        DatePicker("", selection: $startDate, displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("To").font(.caption2).foregroundStyle(.secondary)
                        DatePicker("", selection: $endDate, displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                    }

                    Button {
                        showCustomRange = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
            }

            // Additional filters slot
            additionalFilters()
        }
        .padding(.vertical, 4)
    }

    private func applyQuickFilter(_ filter: QuickDateFilter) {
        startDate = filter.startDate
        endDate = filter.endDate
        showCustomRange = false
    }
}

// MARK: - Convenience Init (No Additional Filters)

extension StandardFilterBar where AdditionalFilters == EmptyView {
    init(startDate: Binding<Date>, endDate: Binding<Date>) {
        self._startDate = startDate
        self._endDate = endDate
        self.additionalFilters = { EmptyView() }
    }
}
