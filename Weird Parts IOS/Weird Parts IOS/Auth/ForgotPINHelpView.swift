import SwiftUI
import WiredPartCore

/// Plain-English help screen shown when a user taps "Forgot PIN?" on the login screen.
///
/// Explains that PINs cannot be self-reset from the login screen, walks the user
/// through the recovery steps, and offers a CTA that opens the supervisor Q&A
/// escalation form so a supervisor can file a PIN-reset request on their behalf.
struct ForgotPINHelpView: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss
    @State private var showQAForm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Hero
                    VStack(spacing: 8) {
                        Image(systemName: "lock.rotation")
                            .font(.system(size: 52))
                            .foregroundStyle(Color.accentColor)
                            .accessibilityHidden(true)
                        Text("Forgot Your PIN?")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("No problem — a supervisor or admin can reset it for you.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                    Divider()

                    // Steps
                    VStack(alignment: .leading, spacing: 16) {
                        Text("How to Recover Access")
                            .font(.headline)

                        stepRow(
                            number: "1",
                            title: "Find a supervisor or admin",
                            body: "Look for someone who set up this app or manages your account — usually a lead, manager, or office contact."
                        )

                        stepRow(
                            number: "2",
                            title: "Ask them to open the Q&A system",
                            body: "Once they're logged in, they go to Chat → Q&A and can file a PIN reset request on your behalf."
                        )

                        stepRow(
                            number: "3",
                            title: "Your PIN gets reset",
                            body: "The admin will update your PIN in People → Employees. You'll get a new PIN to use the next time you sign in."
                        )
                    }

                    Divider()

                    // CTA
                    VStack(spacing: 12) {
                        Text("Have a supervisor nearby?")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("They can open the Q&A form right now to submit a PIN reset request for you.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Button {
                            showQAForm = true
                        } label: {
                            Label("Open Supervisor Q&A", systemImage: "bubble.left.and.bubble.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("forgotPINOpenQAButton")
                    }
                    .frame(maxWidth: .infinity)

                    // Tip
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 1)
                        Text("PINs are stored securely and cannot be viewed or recovered — they can only be reset by an admin.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .navigationTitle("PIN Recovery")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            // Wire CTA to existing supervisor chat escalation form
            .sheet(isPresented: $showQAForm) {
                IOSQAQuestionForm()
                    .environmentObject(appCore)
            }
        }
        .accessibilityIdentifier("forgotPINHelpView")
    }

    // MARK: - Helpers

    private func stepRow(number: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.accentColor)
                .clipShape(Circle())
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
