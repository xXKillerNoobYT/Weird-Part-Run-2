import SwiftUI
import WiredPartCore

/// PIN-based login screen.
///
/// Shows a grid of active users. Tapping a user reveals a 4-digit PIN pad.
/// On successful authentication the app transitions to MainView.
struct LoginView: View {
    @EnvironmentObject private var appCore: AppCore
    @State private var users: [User] = []
    @State private var selectedUser: User? = nil
    @State private var pin: String = ""
    @State private var errorMessage: String? = nil
    @State private var isAuthenticating: Bool = false

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            if let user = selectedUser {
                pinEntry(for: user)
            } else {
                userGrid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
        .task {
            loadUsers()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)
            Text("WiredPart")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Select your account to sign in")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 60)
        .padding(.bottom, 32)
    }

    // MARK: - User Grid

    private var userGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(users, id: \.id) { user in
                    userCard(user)
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }

    private func userCard(_ user: User) -> some View {
        Button {
            selectedUser = user
            pin = ""
            errorMessage = nil
        } label: {
            VStack(spacing: 12) {
                initialsCircle(for: user.displayName)
                Text(user.displayName)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.separatorColor), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func initialsCircle(for name: String) -> some View {
        let initials = name.split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
        return Text(initials.uppercased())
            .font(.title2)
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .background(Circle().fill(Color.accentColor))
    }

    // MARK: - PIN Entry

    private func pinEntry(for user: User) -> some View {
        VStack(spacing: 24) {
            // Back button + user name
            HStack {
                Button {
                    selectedUser = nil
                    pin = ""
                    errorMessage = nil
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 40)

            initialsCircle(for: user.displayName)
            Text(user.displayName)
                .font(.title3)
                .fontWeight(.semibold)

            // PIN dots
            HStack(spacing: 16) {
                ForEach(0..<4, id: \.self) { index in
                    Circle()
                        .fill(index < pin.count ? Color.accentColor : Color(.separatorColor))
                        .frame(width: 16, height: 16)
                }
            }
            .padding(.vertical, 8)

            // Error message
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Numeric keypad
            pinPad

            Spacer()
        }
        .padding(.top, 20)
    }

    private var pinPad: some View {
        let rows: [[String]] = [
            ["1", "2", "3"],
            ["4", "5", "6"],
            ["7", "8", "9"],
            ["", "0", "delete"],
        ]
        return VStack(spacing: 12) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(row, id: \.self) { key in
                        if key.isEmpty {
                            Color.clear.frame(width: 64, height: 48)
                        } else if key == "delete" {
                            Button {
                                if !pin.isEmpty { pin.removeLast() }
                                errorMessage = nil
                            } label: {
                                Image(systemName: "delete.left")
                                    .font(.title3)
                                    .frame(width: 64, height: 48)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button {
                                appendDigit(key)
                            } label: {
                                Text(key)
                                    .font(.title2)
                                    .fontWeight(.medium)
                                    .frame(width: 64, height: 48)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color(.controlBackgroundColor))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func appendDigit(_ digit: String) {
        guard pin.count < 4 else { return }
        pin += digit
        if pin.count == 4 {
            authenticate()
        }
    }

    private func authenticate() {
        guard let user = selectedUser, let userId = user.id else { return }
        isAuthenticating = true
        errorMessage = nil

        do {
            try appCore.login(userId: userId, pin: pin)
        } catch {
            errorMessage = error.localizedDescription
            pin = ""
        }
        isAuthenticating = false
    }

    private func loadUsers() {
        guard let authService = appCore.authService else { return }
        users = (try? authService.getActiveUsers()) ?? []
    }
}
