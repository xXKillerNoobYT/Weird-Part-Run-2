import SwiftUI
import WiredPartCore

/// Routes an office tab ID to the appropriate office page view.
///
/// Office is the hub for management operations: dashboard, approvals, pipeline,
/// teams, and report shortcuts. Report detail pages live in the Reports module.
/// HR/admin pages (employees, hats, permissions) are in the People module.
struct OfficeRouter: View {
    let tabId: String
    @EnvironmentObject private var appCore: AppCore

    var body: some View {
        routedView
    }

    @ViewBuilder
    private var routedView: some View {
        switch tabId {
        // Dashboard
        case "office-dashboard":
            IOSOfficeDashboardPage()

        // Approvals (unified: JPO, deletions, time-off, tool edits)
        case "office-approvals":
            IOSUnifiedApprovalsPage()

        // Operations (kept from original)
        case "office-manage-jobs":
            IOSManageJobsPage()
        case "office-warehouse-exec":
            IOSWarehouseExecPage()
        case "office-estimation-settings":
            IOSEstimationSettingsPage()

        // Pipeline (links to scheduling pages)
        case "office-pipeline":
            OfficePipelineView()

        // Teams
        case "office-teams":
            IOSTeamsPage()

        // Spending Dashboard (aggregate cost view)
        case "office-spending":
            IOSSpendingDashboardPage()

        // Reports (quick links into the Reports module)
        case "office-reports":
            OfficeReportsLinkView()

        default:
            ErrorStateView(message: "Unknown office page: \(tabId)") { }
        }
    }
}

// MARK: - Pipeline View

/// Office pipeline hub — links to scheduling pipeline and dispatch pages.
private struct OfficePipelineView: View {
    var body: some View {
        List {
            Section("Scheduling") {
                NavigationLink {
                    IOSShortTermPipelinePage()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "chart.bar.xaxis")
                            .foregroundStyle(.blue)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Short-Term Pipeline")
                                .font(.subheadline).fontWeight(.medium)
                            Text("Jobs ready to schedule")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                NavigationLink {
                    IOSLongTermPipelinePage()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundStyle(.purple)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Long-Term Pipeline")
                                .font(.subheadline).fontWeight(.medium)
                            Text("3-year timeline view")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Dispatch") {
                NavigationLink {
                    IOSDispatchPage()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.3.sequence.fill")
                            .foregroundStyle(.orange)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Dispatch Board")
                                .font(.subheadline).fontWeight(.medium)
                            Text("Assign crews to jobs")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Pipeline")
        .onAppear {
            postAIContext()
        }
        .onDisappear {
            NotificationCenter.default.post(name: .officePipelinePageInactive, object: nil)
        }
    }

    private func postAIContext() {
        let context = """
        Office Pipeline page. Visible entry points: Short-Term Pipeline, Long-Term Pipeline, Dispatch Board. Purpose: route office users to scheduling pipeline and dispatch workflows. Data state: hub page only; detailed counts load after choosing an entry point. Available read-only actions: explain which pipeline view to open, summarize available routing options, clarify that this page does not mutate schedules directly.
        """
        NotificationCenter.default.post(name: .officePipelinePageActive, object: nil, userInfo: ["context": context])
    }
}

// MARK: - Reports Quick Links

/// Quick links into the Reports module from Office.
private struct OfficeReportsLinkView: View {
    var body: some View {
        List {
            Section {
                NavigationLink {
                    ReportBuilderView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(.indigo)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Build Custom Report")
                                .font(.subheadline).fontWeight(.medium)
                            Text("Create a new report from scratch")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Quick Links") {
                NavigationLink {
                    IOSReportsRouter(tabId: "reports-hub")
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "chart.bar.fill")
                            .foregroundStyle(.blue)
                            .frame(width: 28)
                        Text("All Reports").font(.subheadline)
                    }
                }
            }

            Section {
                Text("Full reports available in the Reports module")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Reports")
    }
}
