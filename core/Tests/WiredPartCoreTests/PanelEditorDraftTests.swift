import Testing
@testable import WiredPartCore

@Suite("Panel editor draft")
struct PanelEditorDraftTests {

    @Test("Kind switch resets to that kind's defaults")
    func kindSwitchResets() {
        var draft = PanelEditorDraft.defaults(kind: .full, anchorSpace: 5)
        draft.sections[0].name = "Kitchen"
        draft.switchKind(to: .tandem)
        #expect(draft.kind == .tandem)
        #expect(draft.sections.count == 2)
        #expect(draft.sections[0].name.isEmpty)
        draft.switchKind(to: .tandem) // no-op on same kind
        #expect(draft.sections.count == 2)
    }

    @Test("Quad mode switch resets sections to mode defaults")
    func quadModeSwitch() {
        var draft = PanelEditorDraft.defaults(kind: .quad, quadMode: .four, anchorSpace: 1)
        #expect(draft.sections.count == 4)
        draft.switchQuadMode(to: .center)
        #expect(draft.sections.count == 3)
        draft.switchQuadMode(to: .double)
        #expect(draft.sections.count == 2)
    }

    @Test("Presets set amps and clamp used load")
    func presets() {
        var draft = PanelEditorDraft.defaults(kind: .tandem, anchorSpace: 6)
        draft.sections[0].usedAmps = 14
        draft.sections[1].usedAmps = 25
        let preset = PanelBuildPreset.tandemPresets.first { $0.label == "15/20" }!
        draft.apply(preset: preset)
        #expect(draft.sections.map(\.amps) == [15, 20])
        #expect(draft.sections[0].usedAmps == 14)   // under new max: untouched
        #expect(draft.sections[1].usedAmps == 20)   // clamped to new max
    }

    @Test("Preset catalog routes by kind and quad mode")
    func presetCatalog() {
        #expect(PanelBuildPreset.presets(for: .full, quadMode: .four).isEmpty)
        #expect(PanelBuildPreset.presets(for: .tandem, quadMode: .four).count == 4)
        #expect(PanelBuildPreset.presets(for: .quad, quadMode: .center).contains { $0.label == "20·30·20" })
        #expect(PanelBuildPreset.presets(for: .quad, quadMode: .double).contains { $0.label == "30/50" })
    }

    @Test("Amp/type constraints follow the catalog per section")
    func constraints() {
        let full = PanelEditorDraft.defaults(kind: .full, anchorSpace: 1)
        #expect(full.ampChoices(forSection: 0) == DesignBreakerType.fullAmpChoices)
        #expect(full.typeChoices(forSection: 0).contains(.hacr))

        let tandem = PanelEditorDraft.defaults(kind: .tandem, anchorSpace: 1)
        #expect(tandem.ampChoices(forSection: 0) == [15, 20, 30])
        #expect(!tandem.typeChoices(forSection: 0).contains(.hacr))

        let center = PanelEditorDraft.defaults(kind: .quad, quadMode: .center, anchorSpace: 1)
        #expect(center.ampChoices(forSection: 1) == DesignBreakerType.quadTwoPoleAmpChoices)
        #expect(center.typeChoices(forSection: 1).contains(.hacr))
        #expect(center.ampChoices(forSection: 0) == [15, 20, 30])
    }

    @Test("Built entry round-trips every kind; all-spare builds nil")
    func builtEntryRoundTrip() {
        var full = PanelEditorDraft.defaults(kind: .full, anchorSpace: 1)
        full.poles = 2
        full.sections[0].name = "Dryer"
        if case .full(let poles, let circuit)? = full.builtEntry {
            #expect(poles == 2)
            #expect(circuit.name == "Dryer")
        } else { Issue.record("expected full entry") }

        let tandem = PanelEditorDraft.defaults(kind: .tandem, anchorSpace: 6)
        if case .tandem? = tandem.builtEntry {} else { Issue.record("expected tandem entry") }

        let quad = PanelEditorDraft.defaults(kind: .quad, quadMode: .double, anchorSpace: 8)
        if case .quad(let mode, let sections)? = quad.builtEntry {
            #expect(mode == .double)
            #expect(sections.count == 2)
        } else { Issue.record("expected quad entry") }

        var spare = PanelEditorDraft.defaults(kind: .full, anchorSpace: 2)
        spare.sections[0].type = .spare
        #expect(spare.builtEntry == nil)
    }

    @Test("Edit round-trip: from(entry:) preserves content")
    func editRoundTrip() {
        let source = DesignSpaceEntry.quad(mode: .center, sections: [
            .init(amps: 20, usedAmps: 10, name: "Outer A"),
            .init(amps: 30, type: .hacr, usedAmps: 20, name: "AC"),
            .init(amps: 20, usedAmps: 8, name: "Outer B"),
        ])
        let draft = PanelEditorDraft.from(entry: source, anchorSpace: 8)
        #expect(draft.kind == .quad)
        #expect(draft.quadMode == .center)
        #expect(draft.builtEntry == source)
    }

    @Test("Occupied spaces reflect the built entry and poles")
    func occupiedSpaces() {
        var full = PanelEditorDraft.defaults(kind: .full, anchorSpace: 1)
        full.poles = 3
        #expect(full.occupiedSpaces == [1, 3, 5])
        let quad = PanelEditorDraft.defaults(kind: .quad, quadMode: .four, anchorSpace: 8)
        #expect(quad.occupiedSpaces == [8, 10])
    }
}
