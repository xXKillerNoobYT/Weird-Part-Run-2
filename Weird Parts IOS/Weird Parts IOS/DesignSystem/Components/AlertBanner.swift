import SwiftUI

/// Inline alert banner for warnings, errors, and info callouts.
///
/// Extracted from the overdue delivery banner pattern in DashboardView.
/// Uses `dsAlertCard()` styling with a colored icon and message.
///
/// Usage:
///   DSAlertBanner(
///       severity: .error,
///       icon: "exclamationmark.triangle.fill",
///       title: "3 overdue deliveries",
///       message: "Immediate attention required"
///   )
struct DSAlertBanner: View {
    let severity: DSAlertSeverity
    var icon: String? = nil
    let title: String
    var message: String? = nil

    var body: some View {
        HStack(spacing: DS.Space.md) {
            if let icon {
                Image(systemName: icon)
                    .foregroundStyle(severity.color)
            }

            VStack(alignment: .leading, spacing: DS.Space.xxxs) {
                Text(title)
                    .dsStyle(.detail)
                    .fontWeight(.medium)
                    .foregroundStyle(severity.color)

                if let message {
                    Text(message)
                        .dsStyle(.caption)
                        .foregroundStyle(severity.color.opacity(0.7))
                }
            }

            Spacer()
        }
        .padding(DS.Space.md)
        .dsAlertCard(severity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(message ?? "")")
    }
}

#Preview {
    VStack(spacing: DS.Space.lg) {
        DSAlertBanner(
            severity: .error,
            icon: "exclamationmark.triangle.fill",
            title: "3 overdue deliveries",
            message: "Immediate attention required"
        )
        DSAlertBanner(
            severity: .warning,
            icon: "exclamationmark.shield.fill",
            title: "2 certifications expiring soon"
        )
        DSAlertBanner(
            severity: .info,
            icon: "info.circle.fill",
            title: "Sync completed",
            message: "All devices are up to date"
        )
    }
    .padding()
}
