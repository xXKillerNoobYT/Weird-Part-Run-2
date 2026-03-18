import SwiftUI
import WiredPartCore

/// Public report view — displays a shared report via token.
///
/// Used when a report is shared externally via a URL with a token.
/// Renders a read-only summary without requiring authentication.
struct IOSPublicReportView: View {
    let reportToken: String

    @State private var isLoading = true
    @State private var reportTitle = ""
    @State private var reportContent = ""
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView("Loading report...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ErrorStateView(message: error) { loadReport() }
            } else {
                reportBody
            }
        }
        .navigationTitle(reportTitle.isEmpty ? "Report" : reportTitle)
        .task { loadReport() }
    }

    private var reportBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !reportTitle.isEmpty {
                    Text(reportTitle)
                        .font(.title2)
                        .fontWeight(.bold)
                }

                if !reportContent.isEmpty {
                    Text(reportContent)
                        .font(.body)
                } else {
                    EmptyStateView(
                        icon: "doc.text",
                        title: "Empty Report",
                        message: "This report has no content."
                    )
                }
            }
            .padding()
        }
    }

    private func loadReport() {
        // Public report loading via token — will be wired to ReportsService
        isLoading = false
        reportTitle = "Public Report"
        reportContent = "Report content will be loaded from the server using token: \(reportToken)"
    }
}
