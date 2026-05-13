import Foundation
import Testing
@testable import WiredPartCore

@Suite("Chat reference trigger parser")
struct ChatReferenceTriggerParserTests {
    @Test("Detects supported reference triggers")
    func detectsSupportedTriggers() {
        #expect(ChatReferenceTriggerParser.firstTrigger(in: "@part:")?.kind == .part)
        #expect(ChatReferenceTriggerParser.firstTrigger(in: "Need @po: for this")?.kind == .purchaseOrder)
        #expect(ChatReferenceTriggerParser.firstTrigger(in: "Link @job:")?.kind == .job)
    }

    @Test("Ignores normal at-sign text")
    func ignoresNormalAtText() {
        #expect(ChatReferenceTriggerParser.firstTrigger(in: "Talk to @maria") == nil)
        #expect(ChatReferenceTriggerParser.firstTrigger(in: "email@example.com") == nil)
        #expect(ChatReferenceTriggerParser.firstTrigger(in: "@parts: is not a trigger") == nil)
    }

    @Test("Uses the first repeated trigger and can remove it cleanly")
    func repeatedTriggersRemoveOneAtATime() {
        let text = "Need @job: before @part:"
        let trigger = ChatReferenceTriggerParser.firstTrigger(in: text)

        #expect(trigger?.kind == .job)

        let cleaned = trigger.map { ChatReferenceTriggerParser.removingTrigger($0, from: text) }
        #expect(cleaned == "Need  before @part:")
    }
}
