import SwiftUI

// MARK: - Destructive Confirmation (Panel-Quality Craft Kit)
//
// Shared count-aware destructive confirmation, modeled on the Panel Schedule
// Builder's hidden-circuit prune alert (docs/plans/panel-quality-uplift.md,
// rubric criterion 8): Cancel (.cancel) + action (.destructive) roles, and a
// message that states the EXACT number of affected records with pluralization
// — "Saving will permanently remove 3 hidden circuits…" — instead of a
// generic "Are you sure?".
//
// Two shapes:
//   .confirmDestruction(of: "wishlist item", count: selected.count, …)
//       → "Delete 3 wishlist items?" / "This deletes 3 wishlist items. …"
//   .confirmDestruction(ofRecordNamed: notebook.title, noun: "notebook", …)
//       → "Delete 'Kitchen remodel'?" / names the record, never a bare noun.

/// Copy builders live outside the view modifier so tests can pin the
/// pluralization and message contract behaviorally (no source scans).
/// `nonisolated`: pure string logic, callable from nonisolated test methods
/// under the app target's default MainActor isolation.
nonisolated enum DestructiveConfirmationCopy {
    /// "3 wishlist items" / "1 wishlist item" — irregular plurals via `plural`.
    static func countPhrase(count: Int, noun: String, plural: String? = nil) -> String {
        let resolvedPlural = plural ?? "\(noun)s"
        return "\(count) \(count == 1 ? noun : resolvedPlural)"
    }

    /// "Delete 3 wishlist items?"
    static func title(actionLabel: String, countPhrase: String) -> String {
        "\(actionLabel) \(countPhrase)?"
    }

    /// Quotes a record name defensively: single quotes normally, double quotes
    /// when the name contains an apostrophe ("Bob's"), and no wrapping in the
    /// degenerate case where the name contains both quote styles.
    static func quoted(_ name: String) -> String {
        if !name.contains("'") { return "'\(name)'" }
        if !name.contains("\"") { return "\"\(name)\"" }
        return name
    }

    /// "Delete 'Kitchen remodel'?" — blank/whitespace names fall back to
    /// "Delete this <noun>?" so the title never renders as "Delete ''?".
    static func recordTitle(actionLabel: String, recordName: String, noun: String) -> String {
        let trimmed = recordName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "\(actionLabel) this \(noun)?" }
        return "\(actionLabel) \(quoted(trimmed))?"
    }

    /// Default body when the call site doesn't supply one. `suffix` carries
    /// site-specific consequences ("Items already ordered are unaffected.").
    static func defaultMessage(actionVerb: String, countPhrase: String, suffix: String? = nil) -> String {
        let base = "This \(actionVerb) \(countPhrase). This can't be undone from this screen."
        guard let suffix, !suffix.isEmpty else { return base }
        return "\(base) \(suffix)"
    }

    /// Default body for the named-record shape; blank names read as
    /// "this <noun>" instead of an empty quoted string.
    static func defaultRecordMessage(actionVerb: String, noun: String, recordName: String, suffix: String? = nil) -> String {
        let trimmed = recordName.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = trimmed.isEmpty ? "this \(noun)" : "the \(noun) \(quoted(trimmed))"
        let base = "This \(actionVerb) \(subject). This can't be undone from this screen."
        guard let suffix, !suffix.isEmpty else { return base }
        return "\(base) \(suffix)"
    }
}

extension View {
    /// Count-based destructive confirmation: exact count + pluralization in
    /// both title and message, Cancel/.destructive roles.
    ///
    /// - Parameters:
    ///   - noun: singular record noun ("wishlist item").
    ///   - plural: irregular plural override; defaults to noun + "s".
    ///   - count: exact number of records the action destroys.
    ///   - actionLabel: the destructive button's verb, also used in the title
    ///     ("Delete", "Remove", "Clear").
    ///   - actionVerb: present-tense verb for the message body; defaults to a
    ///     lowercased actionLabel + "s" ("deletes").
    ///   - messageSuffix: optional site-specific consequence sentence.
    func confirmDestruction(
        of noun: String,
        plural: String? = nil,
        count: Int,
        actionLabel: String = "Delete",
        actionVerb: String? = nil,
        isPresented: Binding<Bool>,
        messageSuffix: String? = nil,
        onConfirm: @escaping () -> Void
    ) -> some View {
        let phrase = DestructiveConfirmationCopy.countPhrase(count: count, noun: noun, plural: plural)
        let verb = actionVerb ?? "\(actionLabel.lowercased())s"
        return alert(
            DestructiveConfirmationCopy.title(actionLabel: actionLabel, countPhrase: phrase),
            isPresented: isPresented
        ) {
            Button("Cancel", role: .cancel) {}
            Button(actionLabel, role: .destructive) { onConfirm() }
        } message: {
            Text(DestructiveConfirmationCopy.defaultMessage(actionVerb: verb, countPhrase: phrase, suffix: messageSuffix))
        }
    }

    /// Single-record destructive confirmation that names the record —
    /// "Delete 'Kitchen remodel'?" — never a generic "Are you sure?".
    func confirmDestruction(
        ofRecordNamed recordName: String,
        noun: String,
        actionLabel: String = "Delete",
        actionVerb: String? = nil,
        isPresented: Binding<Bool>,
        messageSuffix: String? = nil,
        onConfirm: @escaping () -> Void
    ) -> some View {
        let verb = actionVerb ?? "\(actionLabel.lowercased())s"
        return alert(
            DestructiveConfirmationCopy.recordTitle(actionLabel: actionLabel, recordName: recordName, noun: noun),
            isPresented: isPresented
        ) {
            Button("Cancel", role: .cancel) {}
            Button(actionLabel, role: .destructive) { onConfirm() }
        } message: {
            Text(DestructiveConfirmationCopy.defaultRecordMessage(actionVerb: verb, noun: noun, recordName: recordName, suffix: messageSuffix))
        }
    }
}
