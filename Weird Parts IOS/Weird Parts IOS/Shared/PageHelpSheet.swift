import SwiftUI

/// Reusable help sheet for any page.
struct PageHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Set only by the Ask AI action. Publishing from `onDisappear` gives the
    /// parent sheet a deterministic dismissal completion signal before the app
    /// shell presents the assistant.
    @State private var pendingAIHelpRequest: [AnyHashable: Any]?

    let title: String
    let sections: [(heading: String, body: String)]

    var body: some View {
        SheetDismissWrapper(title: title) {
            List {
                Section {
                    Button {
                        askAIAboutThisHelp()
                    } label: {
                        Label("Ask AI about this page", systemImage: "sparkles")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .accessibilityLabel("Ask AI about this help page")
                    .accessibilityIdentifier("askAIAboutHelpButton")
                } footer: {
                    Text("Opens the read-only assistant with this help content as context.")
                }

                ForEach(sections.indices, id: \.self) { i in
                    Section(sections[i].heading) {
                        Text(sections[i].body)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onDisappear {
            guard let pendingAIHelpRequest else { return }
            self.pendingAIHelpRequest = nil
            NotificationCenter.default.post(
                name: .askAIAboutHelp,
                object: nil,
                userInfo: pendingAIHelpRequest
            )
        }
    }

    private func askAIAboutThisHelp() {
        let helpBody = sections
            .map { "## \($0.heading)\n\($0.body)" }
            .joined(separator: "\n\n")
        let prompt = "Help me understand \(title). Use the visible help content for this page and explain the key actions I can take."

        var userInfo: [AnyHashable: Any] = [
            "title": title,
            "prompt": prompt,
            "helpBody": helpBody,
        ]
        if let pageId = HelpContentRegistry.pageId(matchingTitle: title) {
            userInfo["pageId"] = pageId
        }

        pendingAIHelpRequest = userInfo
        dismiss()
    }
}
