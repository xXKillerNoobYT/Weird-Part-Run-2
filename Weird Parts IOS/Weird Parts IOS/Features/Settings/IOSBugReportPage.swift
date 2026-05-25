import SwiftUI
import WiredPartCore

/// Settings page for submitting in-app bug reports, feature requests, and general feedback.
///
/// Collects a report type, title, and description from the user, then opens the
/// GitHub issue-creation page pre-filled with that information so no GitHub token
/// needs to be stored inside the app.  Device and app-version details are included
/// automatically (opt-out toggle) so the development team has enough context to
/// reproduce the problem.
struct IOSBugReportPage: View {

    @EnvironmentObject private var appCore: AppCore

    // MARK: - Report Type

    enum ReportType: String, CaseIterable, Identifiable {
        case bug            = "bug"
        case featureRequest = "feature_request"
        case other          = "other"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .bug:            return "Bug Report"
            case .featureRequest: return "Feature Request"
            case .other:          return "General Feedback"
            }
        }

        var icon: String {
            switch self {
            case .bug:            return "ant.fill"
            case .featureRequest: return "lightbulb.fill"
            case .other:          return "bubble.left.fill"
            }
        }

        var githubLabel: String {
            switch self {
            case .bug:            return "bug"
            case .featureRequest: return "enhancement"
            case .other:          return "question"
            }
        }
    }

    // MARK: - State

    @State private var reportType: ReportType = .bug
    @State private var title = ""
    @State private var description = ""
    @State private var stepsToReproduce = ""
    @State private var includeDeviceInfo = true
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: Identifiable {
        case help
        var id: String { "help" }
    }

    // MARK: - Validation

    private var isFormValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !description.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Device / App Info

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build   = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private var deviceInfoBlock: String {
        let device = UIDevice.current
        return """
        **Device:** \(device.model)
        **iOS:** \(device.systemName) \(device.systemVersion)
        **App Version:** \(appVersion)
        **Core Version:** \(WiredPartCore.version)
        """
    }

    // MARK: - GitHub URL

    private var githubIssueURL: URL? {
        let repo = "xXKillerNoobYT/Weird-Part-Run-2"
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let trimmedDesc  = description.trimmingCharacters(in: .whitespaces)
        let trimmedSteps = stepsToReproduce.trimmingCharacters(in: .whitespaces)

        var body = trimmedDesc
        if reportType == .bug && !trimmedSteps.isEmpty {
            body += "\n\n**Steps to Reproduce:**\n\(trimmedSteps)"
        }
        if includeDeviceInfo {
            body += "\n\n---\n\(deviceInfoBlock)"
        }

        var components = URLComponents(string: "https://github.com/\(repo)/issues/new")
        components?.queryItems = [
            URLQueryItem(name: "title",  value: trimmedTitle),
            URLQueryItem(name: "body",   value: body),
            URLQueryItem(name: "labels", value: reportType.githubLabel),
        ]
        return components?.url
    }

    // MARK: - Body

    var body: some View {
        Form {
            reportTypeSection
            titleSection
            descriptionSection
            if reportType == .bug {
                stepsSection
            }
            deviceInfoSection
            submitSection
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Submit Feedback")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { activeSheet = .help } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help")
            }
        }
        .sheet(item: $activeSheet) { _ in
            PageHelpSheet(title: "Submit Feedback Help", sections: [
                ("What This Page Does",
                 "Lets you submit bug reports, feature requests, and general feedback directly to the development team on GitHub. No account is required to fill in the form — you only need a GitHub account when you actually post the issue."),
                ("How to Use It",
                 "Choose the report type, fill in a title and description, then tap 'Open GitHub to Submit'. Your default browser opens GitHub with the form pre-filled. Sign in to GitHub to post the issue."),
                ("Device Info",
                 "When enabled, your device model, iOS version, and app version are attached automatically so the team has everything needed to reproduce the problem. Disable the toggle if you prefer not to include this information."),
            ])
        }
    }

    // MARK: - Sections

    private var reportTypeSection: some View {
        Section("Report Type") {
            Picker("Type", selection: $reportType) {
                ForEach(ReportType.allCases) { type in
                    Label(type.label, systemImage: type.icon).tag(type)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var titleSection: some View {
        Section("Title") {
            TextField(titlePlaceholder, text: $title)
                .autocorrectionDisabled()
        }
    }

    private var titlePlaceholder: String {
        switch reportType {
        case .bug:            return "Short description of the bug"
        case .featureRequest: return "What feature would you like?"
        case .other:          return "Subject"
        }
    }

    private var descriptionSection: some View {
        Section {
            TextField(descriptionPlaceholder, text: $description, axis: .vertical)
                .lineLimit(4...10)
        } header: {
            Text("Description")
        } footer: {
            Text("Be as specific as possible to help the team understand the issue.")
        }
    }

    private var descriptionPlaceholder: String {
        switch reportType {
        case .bug:            return "What went wrong? What did you expect to happen?"
        case .featureRequest: return "Describe the feature and how it would help you."
        case .other:          return "Your feedback…"
        }
    }

    private var stepsSection: some View {
        Section {
            TextField("1. Open the app\n2. Go to…\n3. Tap…", text: $stepsToReproduce, axis: .vertical)
                .lineLimit(3...8)
        } header: {
            Text("Steps to Reproduce")
        } footer: {
            Text("Optional but very helpful — include the exact taps needed to trigger the bug.")
        }
    }

    private var deviceInfoSection: some View {
        Section {
            Toggle("Include Device Info", isOn: $includeDeviceInfo)
            if includeDeviceInfo {
                Text(deviceInfoBlock)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Device Information")
        } footer: {
            Text("Attaches your device model, iOS version, and app version to the report.")
        }
    }

    private var submitSection: some View {
        Section {
            Button {
                submitReport()
            } label: {
                HStack {
                    Spacer()
                    Label("Open GitHub to Submit", systemImage: "arrow.up.right.square")
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isFormValid)
        } footer: {
            Text("Opens github.com in your browser with the report pre-filled. A GitHub account is required to post the issue.")
                .font(.caption)
        }
    }

    // MARK: - Actions

    private func submitReport() {
        guard let url = githubIssueURL else { return }
        UIApplication.shared.open(url)
    }
}
