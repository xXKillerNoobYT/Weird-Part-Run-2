import SwiftUI
import WiredPartCore


/// "Agent Link (MCP)" section of Device Management — Mac only (plan
/// `docs/plans/devices-add-mcp-agent-link.md`, owner decisions 2026-08-01).
/// Lets the owner serve the app's data to AI desktop apps (Claude Desktop /
/// ChatGPT) on THIS Mac over loopback, manage per-agent links, and revoke
/// them. The bearer key is shown exactly once at creation.
struct AgentLinkSection: View {
    @EnvironmentObject private var appCore: AppCore
    @AppStorage("agentLinkEnabled") private var serverEnabled = false
    @State private var links: [AgentLinkService.AgentLink] = []
    @State private var showCreateSheet = false
    @State private var revokeTarget: AgentLinkService.AgentLink?
    @State private var loadError: String?

    var body: some View {
        Section {
            Toggle(isOn: $serverEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Serve Agent Link")
                    Text(serverEnabled
                         ? "AI apps on this Mac can connect at 127.0.0.1:\(AgentLinkServer.defaultPort)"
                         : "Off — no agent can connect")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: serverEnabled) { _, enabled in
                appCore.setAgentLinkEnabled(enabled)
            }
            .accessibilityIdentifier("settings-agent-link-toggle")

            ForEach(links) { link in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(link.name)
                            .fontWeight(.medium)
                            .strikethrough(link.isRevoked)
                        Text(link.scope == .readNotes ? "Read + notes" : "Read-only")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                        if link.isRevoked {
                            Text("Revoked")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                    Text(auditLine(for: link))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if !link.isRevoked {
                        Button("Revoke", role: .destructive) { revokeTarget = link }
                    }
                }
                .rowAccessibility(
                    label: "\(link.name), \(link.scope == .readNotes ? "read and notes" : "read-only")\(link.isRevoked ? ", revoked" : "")",
                    value: auditLine(for: link),
                    id: "settings-agent-link-row-\(link.id)"
                )
            }

            Button {
                showCreateSheet = true
            } label: {
                Label("Add Agent Link", systemImage: "link.badge.plus")
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("settings-agent-link-add-button")

            if let loadError {
                Text(loadError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Agent Link (MCP)")
        } footer: {
            Text("Connects AI apps running on this Mac — Claude Desktop, ChatGPT — to your WiredPart data. Same-machine only; nothing is served to the network. Each agent gets its own key you can revoke any time.")
        }
        .onAppear(perform: reload)
        .sheet(isPresented: $showCreateSheet, onDismiss: reload) {
            AgentLinkCreateSheet()
                .environmentObject(appCore)
        }
        .confirmationDialog(
            "Revoke \(revokeTarget?.name ?? "link")?",
            isPresented: Binding(get: { revokeTarget != nil }, set: { if !$0 { revokeTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("Revoke Access", role: .destructive) {
                if let target = revokeTarget {
                    do {
                        try appCore.agentLinkService?.revoke(linkId: target.id)
                        loadError = nil
                    } catch {
                        // A silent revoke failure would leave the owner
                        // believing access was cut (Copilot review 2026-08-02).
                        loadError = userFriendlyError(error, context: "revoke agent link")
                    }
                    reload()
                }
                revokeTarget = nil
            }
        } message: {
            Text("The agent loses access on its next request. This cannot be undone.")
        }
    }

    private func auditLine(for link: AgentLinkService.AgentLink) -> String {
        var parts: [String] = ["\(link.callCount) calls"]
        if let seen = link.lastSeenAt {
            parts.append("last seen \(seen) UTC")
        } else {
            parts.append("never used")
        }
        return parts.joined(separator: " · ")
    }

    private func reload() {
        do {
            links = try appCore.agentLinkService?.listLinks() ?? []
            loadError = nil
        } catch {
            loadError = userFriendlyError(error, context: "load agent links")
        }
    }
}

// MARK: - Create sheet

/// Two-step create flow: name + scope, then the one-time key + config
/// snippet. The key is never shown again — the sheet says so loudly.
private struct AgentLinkCreateSheet: View {
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var scope: AgentLinkService.Scope = .read
    @State private var created: (link: AgentLinkService.AgentLink, token: String)?
    @State private var createError: String?

    var body: some View {
        NavigationStack {
            Form {
                if let created {
                    resultSections(created)
                } else {
                    formSections
                }
            }
            .navigationTitle(created == nil ? "Add Agent Link" : "Key Created")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Always-visible dismiss — Mac Catalyst has no
                    // swipe-to-dismiss (dismiss-trap audit #1388).
                    Button(created == nil ? "Cancel" : "Done") { dismiss() }
                        .accessibilityIdentifier("settings-agent-link-create-close")
                }
                if created == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") { create() }
                            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("settings-agent-link-create-confirm")
                    }
                }
            }
            .interactiveDismissDisabled(created != nil)
        }
    }

    @ViewBuilder
    private var formSections: some View {
        Section("Agent") {
            TextField("Name (e.g. Claude Desktop)", text: $name)
                .accessibilityIdentifier("settings-agent-link-name-field")
            Picker("Access", selection: $scope) {
                Text("Read-only").tag(AgentLinkService.Scope.read)
                Text("Read + job notes").tag(AgentLinkService.Scope.readNotes)
                    .selectionDisabled(appCore.currentUser?.id == nil)
            }
        }
        Section {
            EmptyView()
        } footer: {
            Text(appCore.currentUser?.id == nil
                 ? "Read-only allows lookups (parts, stock, jobs, orders, reports). Sign in to create a link that can append job notes — notes must be attributed to a real user."
                 : "Read-only allows lookups (parts, stock, jobs, orders, reports). Read + job notes additionally lets the agent append notes to job notebooks, attributed to you.")
        }
        if let createError {
            Section {
                Text(createError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func resultSections(_ created: (link: AgentLinkService.AgentLink, token: String)) -> some View {
        Section {
            Text(created.token)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .accessibilityIdentifier("settings-agent-link-token-text")
            Button {
                UIPasteboard.general.string = created.token
            } label: {
                Label("Copy Key", systemImage: "doc.on.doc")
            }
        } header: {
            Text("Agent Key — shown once")
        } footer: {
            Text("Treat this like a password. It is NOT stored in the app and cannot be shown again — only revoked.")
        }
        Section {
            Text(configSnippet(created.token))
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(nil)
            Button {
                UIPasteboard.general.string = configSnippet(created.token)
            } label: {
                Label("Copy Config", systemImage: "doc.on.doc")
            }
            .accessibilityIdentifier("settings-agent-link-copy-config")
        } header: {
            Text("MCP config for the AI app")
        } footer: {
            Text("Paste into the AI app's MCP settings (Claude Desktop: Settings → Developer → Edit Config). Turn on Serve Agent Link, then restart the AI app.")
        }
    }

    private func configSnippet(_ token: String) -> String {
        """
        {
          "mcpServers": {
            "wiredpart": {
              "type": "http",
              "url": "http://127.0.0.1:\(AgentLinkServer.defaultPort)/mcp",
              "headers": { "Authorization": "Bearer \(token)" }
            }
          }
        }
        """
    }

    private func create() {
        createError = nil
        do {
            guard let service = appCore.agentLinkService else {
                createError = "Service not available"
                return
            }
            created = try service.createLink(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                scope: scope,
                createdBy: appCore.currentUser?.id
            )
            appCore.restartAgentLinkIfRunning()
        } catch {
            createError = userFriendlyError(error, context: "create agent link")
        }
    }
}
