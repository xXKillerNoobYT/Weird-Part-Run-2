import SwiftUI

/// Reusable help sheet for any page.
struct PageHelpSheet: View {
    let title: String
    let sections: [(heading: String, body: String)]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections.indices, id: \.self) { i in
                    Section(sections[i].heading) {
                        Text(sections[i].body)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
