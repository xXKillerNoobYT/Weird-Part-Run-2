import Foundation

public enum ChatReferenceTriggerKind: String, Sendable {
    case part
    case purchaseOrder
    case job
}

public struct ChatReferenceTrigger: Sendable {
    public let kind: ChatReferenceTriggerKind
    public let range: Range<String.Index>

    public init(kind: ChatReferenceTriggerKind, range: Range<String.Index>) {
        self.kind = kind
        self.range = range
    }
}

public enum ChatReferenceTriggerParser {
    private static let supportedTriggers: [(token: String, kind: ChatReferenceTriggerKind)] = [
        ("@part:", .part),
        ("@po:", .purchaseOrder),
        ("@job:", .job)
    ]

    public static func firstTrigger(in text: String) -> ChatReferenceTrigger? {
        supportedTriggers
            .compactMap { token, kind -> ChatReferenceTrigger? in
                guard let range = text.range(of: token) else { return nil }
                return ChatReferenceTrigger(kind: kind, range: range)
            }
            .min { lhs, rhs in lhs.range.lowerBound < rhs.range.lowerBound }
    }

    public static func removingTrigger(_ trigger: ChatReferenceTrigger, from text: String) -> String {
        var cleaned = text
        cleaned.removeSubrange(trigger.range)
        return cleaned
    }
}
