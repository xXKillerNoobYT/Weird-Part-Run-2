import SwiftUI

/// One selectable filter chip rendered with the shared SmartFilterCard style.
struct FilterChipItem: Identifiable {
    let id: String
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    init(
        id: String,
        title: String,
        count: Int,
        isSelected: Bool,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.count = count
        self.isSelected = isSelected
        self.action = action
    }
}

/// Horizontal single-select chip row for page-specific status/type filters.
struct FilterChipRow: View {
    let items: [FilterChipItem]

    init(items: [FilterChipItem]) {
        self.items = items
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    SmartFilterCard(
                        title: item.title,
                        count: item.count,
                        isSelected: item.isSelected,
                        action: item.action
                    )
                    .accessibilityLabel("\(item.title), \(item.count) items")
                    .accessibilityValue(item.isSelected ? "Selected" : "Not selected")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}

/// Canonical filter-region composer for iOS list pages.
///
/// The list/grid and native `.searchable` modifier stay owned by each page.
/// `FilterStack` only owns the shared filter region ordering:
/// onboarding, skipped-module hint, header KPI, primary chips, date bar,
/// secondary filters, then summary KPI.
struct FilterStack<HeaderKPI: View, PrimaryChips: View, SecondaryChips: View, SummaryKPI: View>: View {
    let onboardingPageId: String?
    let skippedModuleId: String?
    let dateRange: Binding<ReportDateRange>?
    let customStart: Binding<Date>?
    let customEnd: Binding<Date>?
    let quickOptions: [ReportDateRange]?
    private let headerKPI: () -> HeaderKPI
    private let primaryChips: () -> PrimaryChips
    private let secondaryChips: () -> SecondaryChips
    private let summaryKPI: () -> SummaryKPI

    init(
        onboardingPageId: String? = nil,
        skippedModuleId: String? = nil,
        dateRange: Binding<ReportDateRange>? = nil,
        customStart: Binding<Date>? = nil,
        customEnd: Binding<Date>? = nil,
        quickOptions: [ReportDateRange]? = nil,
        @ViewBuilder headerKPI: @escaping () -> HeaderKPI,
        @ViewBuilder primaryChips: @escaping () -> PrimaryChips,
        @ViewBuilder secondaryChips: @escaping () -> SecondaryChips,
        @ViewBuilder summaryKPI: @escaping () -> SummaryKPI
    ) {
        self.onboardingPageId = onboardingPageId
        self.skippedModuleId = skippedModuleId
        self.dateRange = dateRange
        self.customStart = customStart
        self.customEnd = customEnd
        self.quickOptions = quickOptions
        self.headerKPI = headerKPI
        self.primaryChips = primaryChips
        self.secondaryChips = secondaryChips
        self.summaryKPI = summaryKPI
    }

    var body: some View {
        VStack(spacing: 0) {
            if let onboardingPageId {
                OnboardingBanner(pageId: onboardingPageId)
            }

            if let skippedModuleId {
                SkippedModuleHint(moduleId: skippedModuleId)
            }

            headerKPI()
            primaryChips()
            dateBar
            secondaryChips()
            summaryKPI()
        }
    }

    @ViewBuilder
    private var dateBar: some View {
        if let dateRange, let customStart, let customEnd {
            StandardFilterBar(
                selectedRange: dateRange,
                customStart: customStart,
                customEnd: customEnd,
                quickOptions: quickOptions ?? [.thisWeek, .lastWeek, .thisPeriod, .lastPeriod, .thisMonth, .custom]
            )
        }
    }
}

extension FilterStack where HeaderKPI == EmptyView, PrimaryChips == EmptyView, SecondaryChips == EmptyView, SummaryKPI == EmptyView {
    init(
        onboardingPageId: String? = nil,
        skippedModuleId: String? = nil,
        dateRange: Binding<ReportDateRange>? = nil,
        customStart: Binding<Date>? = nil,
        customEnd: Binding<Date>? = nil,
        quickOptions: [ReportDateRange]? = nil
    ) {
        self.init(
            onboardingPageId: onboardingPageId,
            skippedModuleId: skippedModuleId,
            dateRange: dateRange,
            customStart: customStart,
            customEnd: customEnd,
            quickOptions: quickOptions,
            headerKPI: { EmptyView() },
            primaryChips: { EmptyView() },
            secondaryChips: { EmptyView() },
            summaryKPI: { EmptyView() }
        )
    }
}

extension FilterStack where HeaderKPI == EmptyView, SecondaryChips == EmptyView, SummaryKPI == EmptyView {
    init(
        onboardingPageId: String? = nil,
        skippedModuleId: String? = nil,
        dateRange: Binding<ReportDateRange>? = nil,
        customStart: Binding<Date>? = nil,
        customEnd: Binding<Date>? = nil,
        quickOptions: [ReportDateRange]? = nil,
        @ViewBuilder primaryChips: @escaping () -> PrimaryChips
    ) {
        self.init(
            onboardingPageId: onboardingPageId,
            skippedModuleId: skippedModuleId,
            dateRange: dateRange,
            customStart: customStart,
            customEnd: customEnd,
            quickOptions: quickOptions,
            headerKPI: { EmptyView() },
            primaryChips: primaryChips,
            secondaryChips: { EmptyView() },
            summaryKPI: { EmptyView() }
        )
    }
}

extension FilterStack where HeaderKPI == EmptyView, SecondaryChips == EmptyView {
    init(
        onboardingPageId: String? = nil,
        skippedModuleId: String? = nil,
        dateRange: Binding<ReportDateRange>? = nil,
        customStart: Binding<Date>? = nil,
        customEnd: Binding<Date>? = nil,
        quickOptions: [ReportDateRange]? = nil,
        @ViewBuilder primaryChips: @escaping () -> PrimaryChips,
        @ViewBuilder summaryKPI: @escaping () -> SummaryKPI
    ) {
        self.init(
            onboardingPageId: onboardingPageId,
            skippedModuleId: skippedModuleId,
            dateRange: dateRange,
            customStart: customStart,
            customEnd: customEnd,
            quickOptions: quickOptions,
            headerKPI: { EmptyView() },
            primaryChips: primaryChips,
            secondaryChips: { EmptyView() },
            summaryKPI: summaryKPI
        )
    }
}

/// Counts each chip key against an already search/date/secondary-filtered base set.
///
/// The "all" key always returns `base.count`; all other keys are counted with
/// `matches`. Duplicate keys are evaluated once in their first-seen order.
nonisolated func filterCounts<T>(
    base: [T],
    keys: [String],
    matches: (T, String) -> Bool
) -> [String: Int] {
    var counts: [String: Int] = [:]

    for key in keys where counts[key] == nil {
        if key == "all" {
            counts[key] = base.count
        } else {
            var count = 0
            for item in base {
                if matches(item, key) {
                    count += 1
                }
            }
            counts[key] = count
        }
    }

    return counts
}
