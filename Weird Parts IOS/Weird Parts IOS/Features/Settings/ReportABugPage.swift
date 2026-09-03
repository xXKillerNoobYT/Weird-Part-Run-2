import SwiftUI
import WiredPartCore

/// In-app bug reporting for beta testers.
///
/// Gathers device model, iOS + app version, the page/module the user came
/// from, and recent in-app errors; lets the user edit a title and description;
/// then hands the report off via the iOS share sheet or a pre-filled GitHub
/// "new issue" URL. No tokens or secrets are embedded — the GitHub URL only
/// pre-fills the public issue form.
struct ReportABugPage: View {
    /// The page/module the user was on before opening the reporter, if known.
    /// Passed in by the entry point (e.g. the AI assistant) so testers do not
    /// have to describe where they were.
    var originModule: String?
    /// Exact startup error passed by the failure screen. This stays optional so
    /// ordinary in-app reports do not need startup state or database access.
    var launchError: String? = nil

    @ObservedObject private var errorLog = BugReportErrorLog.shared

    @State private var title = ""
    @State private var descriptionText = ""
    @State private var isShareSheetPresented = false
    @State private var urlBuildError: String?

    private var context: BugReportComposer.Context {
        BugReportContextBuilder.build(
            currentModule: originModule,
            launchError: launchError
        )
    }

    private var shareText: String {
        BugReportComposer.body(description: descriptionText, context: context)
    }

    private var githubURL: URL? {
        BugReportComposer.githubIssueURL(
            userTitle: title,
            description: descriptionText,
            context: context
        )
    }

    private var displayedLaunchError: String? {
        guard let launchError = context.launchError else { return nil }
        let trimmed = launchError.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        Form {
            if displayedLaunchError != nil {
                attachedDetailsSection
            }

            reportDescriptionSection

            if displayedLaunchError == nil {
                attachedDetailsSection
            }

            if !errorLog.entries.isEmpty {
                recentErrorsSection
            }

            actionsSection

            if let urlBuildError, githubURL == nil {
                Section {
                    Text(urlBuildError)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Report a Bug")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShareSheetPresented) {
            ReportShareSheet(items: [shareText])
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Sections

    private var reportDescriptionSection: some View {
        Section {
            TextField("Title", text: $title, prompt: Text("Short summary"))
                .accessibilityLabel("Bug report title")
            TextEditorWithPlaceholder(
                text: $descriptionText,
                placeholder: BugReportComposer.descriptionPlaceholder
            )
            .frame(minHeight: 120)
            .accessibilityLabel("Bug description")
            .accessibilityIdentifier("settings-bug-description-editor")
        } header: {
            Text("What happened")
        } footer: {
            Text("Describe the problem in your own words. Device and version details are attached automatically.")
        }
    }

    private var attachedDetailsSection: some View {
        Section("Attached details") {
            if let launchError = displayedLaunchError {
                LabeledContent("Startup error") {
                    Text(launchError)
                        .multilineTextAlignment(.trailing)
                }
                .accessibilityIdentifier("bug-report-startup-error-row")
                LabeledContent("Page", value: context.currentModule ?? "Unknown")
                    .accessibilityIdentifier("bug-report-page-row")
            }
            LabeledContent("Device", value: context.deviceModel)
                .accessibilityIdentifier("bug-report-device-row")
            LabeledContent("OS", value: context.systemVersion)
                .accessibilityIdentifier("bug-report-os-row")
            LabeledContent("iOS app on Mac", value: context.isIOSAppOnMac ? "Yes" : "No")
                .accessibilityIdentifier("bug-report-ios-on-mac-row")
            if displayedLaunchError == nil {
                LabeledContent("Page", value: context.currentModule ?? "Unknown")
                    .accessibilityIdentifier("bug-report-page-row")
            }
            LabeledContent("App version", value: displayVersion)
            LabeledContent("Core version", value: context.coreVersion)
        }
    }

    private var recentErrorsSection: some View {
        Section {
            ForEach(errorLog.entries.prefix(BugReportComposer.maxRenderedErrors)) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.message)
                        .font(.caption)
                    if let ctx = entry.context, !ctx.isEmpty {
                        Text(ctx)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Recent errors")
        } footer: {
            Text("These recent in-app errors are attached to help diagnose the problem.")
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                urlBuildError = nil
                isShareSheetPresented = true
            } label: {
                Label("Share report", systemImage: "square.and.arrow.up")
            }
            .frame(minHeight: 44)
            .accessibilityLabel("Share bug report")
            .accessibilityHint("Opens the share sheet with the full report attached.")
            .accessibilityIdentifier("settings-bug-share-report-button")

            if let githubURL {
                Link(destination: githubURL) {
                    Label("Open GitHub issue", systemImage: "ladybug")
                }
                .frame(minHeight: 44)
                .accessibilityLabel("Open a pre-filled GitHub issue")
                .accessibilityHint("Opens GitHub in the browser with the report pre-filled.")
                .accessibilityIdentifier("settings-bug-github-issue-button")
            } else {
                Button {
                    urlBuildError = "Could not build the GitHub issue link. Use Share report instead, or try shortening the description."
                } label: {
                    Label("Open GitHub issue", systemImage: "ladybug")
                }
                .frame(minHeight: 44)
                .accessibilityLabel("Open a pre-filled GitHub issue")
                .accessibilityHint("Opens GitHub in the browser with the report pre-filled.")
                .accessibilityIdentifier("settings-bug-github-issue-button")
            }
        } footer: {
            Text("Share sends the report to any app (Messages, Mail, Notes). GitHub opens a pre-filled issue you can submit while signed in.")
        }
    }

    private var displayVersion: String {
        let build = context.appBuild.trimmingCharacters(in: .whitespacesAndNewlines)
        return build.isEmpty ? context.appVersion : "\(context.appVersion) (\(build))"
    }
}

// MARK: - TextEditor with placeholder

/// A `TextEditor` that shows placeholder text when empty. SwiftUI's built-in
/// `TextEditor` has no prompt, so we overlay one.
private struct TextEditorWithPlaceholder: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                    .padding(.leading, 4)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            TextEditor(text: $text)
        }
    }
}

#Preview {
    NavigationStack {
        ReportABugPage(originModule: "Settings > About")
    }
}
