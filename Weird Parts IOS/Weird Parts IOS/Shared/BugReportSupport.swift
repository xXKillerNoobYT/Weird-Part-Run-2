import SwiftUI
import UIKit

/// Shared helpers for filing app feedback into the project tracker.
///
/// The app cannot silently create GitHub issues from a user's device without
/// storing credentials, so every entry point builds a pre-filled GitHub issue
/// draft and asks the user to review/submit it in the browser.
enum BugReportSupport {
    static let repositoryNewIssueURL = URL(string: "https://github.com/xXKillerNoobYT/Weird-Part-Run-2/issues/new")!

    static func githubIssueURL(
        title: String,
        description: String,
        category: BugReportCategory,
        source: BugReportSource,
        context: String,
        user: String?
    ) -> URL {
        var components = URLComponents(url: repositoryNewIssueURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "title", value: "[In-App] \(title)"),
            URLQueryItem(name: "body", value: issueBody(
                title: title,
                description: description,
                category: category,
                source: source,
                context: context,
                user: user
            )),
            URLQueryItem(name: "labels", value: "bug,from-app")
        ]
        return components.url ?? repositoryNewIssueURL
    }

    static func issueBody(
        title: String,
        description: String,
        category: BugReportCategory,
        source: BugReportSource,
        context: String,
        user: String?
    ) -> String {
        """
        ## Reported from Weird Parts iOS

        **Category:** \(category.label)
        **Source:** \(source.label)
        **Reporter:** \(user?.isEmpty == false ? user! : "Not provided")
        **App context:** \(context.isEmpty ? "Not provided" : context)

        ## What happened
        \(description)

        ## Expected behavior
        _Please describe what you expected to happen._

        ## Steps to reproduce
        1. _Add the steps you took before this happened._
        2. _Add screenshots or logs if useful._

        ## Device / build
        - App: Weird Parts iOS
        - Device: \(UIDevice.current.model)
        - System: \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)
        """
    }
}

enum BugReportCategory: String, CaseIterable, Identifiable {
    case bug
    case featureRequest
    case appCrashed
    case dataProblem
    case usability

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bug: return "Bug"
        case .featureRequest: return "Feature request"
        case .appCrashed: return "App crashed or failed to load"
        case .dataProblem: return "Data problem"
        case .usability: return "Usability problem"
        }
    }
}

enum BugReportSource: String {
    case settings
    case assistant
    case launchError

    var label: String {
        switch self {
        case .settings: return "Settings > Report a Bug"
        case .assistant: return "AI Assistant"
        case .launchError: return "Launch error screen"
        }
    }
}

struct BugReportComposerView: View {
    @Environment(\.dismiss) private var dismiss

    let source: BugReportSource
    let initialContext: String
    let initialTitle: String
    let initialDescription: String
    let reporterName: String?

    @State private var category: BugReportCategory
    @State private var title: String
    @State private var description: String
    @State private var context: String
    @State private var openError: String?

    init(
        source: BugReportSource,
        initialContext: String = "",
        initialTitle: String = "",
        initialDescription: String = "",
        reporterName: String? = nil,
        category: BugReportCategory = .bug
    ) {
        self.source = source
        self.initialContext = initialContext
        self.initialTitle = initialTitle
        self.initialDescription = initialDescription
        self.reporterName = reporterName
        _category = State(initialValue: category)
        _title = State(initialValue: initialTitle)
        _description = State(initialValue: initialDescription)
        _context = State(initialValue: initialContext)
    }

    private var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $category) {
                        ForEach(BugReportCategory.allCases) { category in
                            Text(category.label).tag(category)
                        }
                    }

                    TextField("Short summary", text: $title, axis: .vertical)
                        .textInputAutocapitalization(.sentences)

                    TextField("What happened?", text: $description, axis: .vertical)
                        .lineLimit(5...10)
                        .textInputAutocapitalization(.sentences)
                } header: {
                    Text("Report")
                } footer: {
                    Text("Opens a pre-filled GitHub issue for review. Nothing is submitted until you send it from GitHub.")
                }

                Section("Context") {
                    TextField("Page, workflow, or error context", text: $context, axis: .vertical)
                        .lineLimit(3...8)
                }

                if let openError {
                    Section {
                        Text(openError)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Report a Bug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open GitHub") { openGitHubDraft() }
                        .disabled(!canSubmit)
                }
            }
        }
    }

    private func openGitHubDraft() {
        let url = BugReportSupport.githubIssueURL(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            source: source,
            context: context.trimmingCharacters(in: .whitespacesAndNewlines),
            user: reporterName
        )

        UIApplication.shared.open(url) { success in
            if success {
                dismiss()
            } else {
                openError = "GitHub could not be opened on this device. Copy the details and report them when you have browser access."
            }
        }
    }
}
