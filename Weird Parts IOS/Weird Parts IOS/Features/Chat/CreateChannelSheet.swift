import SwiftUI
import WiredPartCore

/// Sheet for creating a new chat channel or DM.
struct CreateChannelSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss

    let channelType: String
    var onSave: () -> Void

    @State private var channelName = ""
    @State private var description = ""
    @State private var isSaving = false
    @State private var saveError: String?

    private var isDM: Bool { channelType == "dm" }

    var body: some View {
        NavigationStack {
            Form {
                Section(isDM ? "Conversation Name" : "Channel Name") {
                    TextField(isDM ? "e.g. John & Jane" : "e.g. general-chat", text: $channelName)
                }

                if !isDM {
                    Section("Description (Optional)") {
                        TextEditor(text: $description)
                            .frame(minHeight: 60)
                    }
                }

                if let error = saveError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(isDM ? "New Message" : "New Channel")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { saveChannel() }
                        .disabled(channelName.isEmpty || isSaving)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func saveChannel() {
        guard let service = appCore.chatService,
              let userId = appCore.currentUser?.id else { return }
        isSaving = true
        saveError = nil
        do {
            _ = try service.createChannel(
                name: channelName,
                channelType: channelType,
                createdBy: userId
            )
            onSave()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }
}
