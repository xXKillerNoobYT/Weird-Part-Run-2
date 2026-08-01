import Foundation
import Testing
@testable import WiredPartCore

@Suite("Panel print document assembly")
struct PanelPrintDocumentTests {

    private func samplePanel() throws -> DesignPanelState {
        var panel = DesignPanelState(setup: DesignPanelSetup(
            voltageSystem: .v120_240Single3Wire, totalSpaces: 12, mainAmps: 200
        ))
        try panel.save(.full(poles: 2, circuit: .init(amps: 30, usedAmps: 24, name: "Dryer", note: "#10 THHN, 30ft")), atAnchor: 2)
        try panel.save(.tandem(
            upper: .init(amps: 15, usedAmps: 10, name: "Hall"),
            lower: .init(amps: 20, usedAmps: 8, name: "Bath")
        ), atAnchor: 5)
        try panel.save(.quad(mode: .double, sections: [
            .init(amps: 30, usedAmps: 24, name: "Dryer 2"),
            .init(amps: 50, usedAmps: 40, name: "Range"),
        ]), atAnchor: 7)
        return panel
    }

    @Test("Rows carry spec slot labels, breaker text, and phases")
    func rowLabels() throws {
        let doc = PanelPrintDocument.assemble(
            panelName: "Panel A", panel: try samplePanel(), config: PanelPrintConfig()
        )
        let slots = doc.rows.map(\.slot)
        #expect(slots.contains("2–4"))       // 2P full spans 2,4
        #expect(slots.contains("5a") && slots.contains("5b"))
        #expect(slots.contains("7–9↑") && slots.contains("7–9↓"))
        let dryer = doc.rows.first { $0.slot == "2–4" }!
        #expect(dryer.breaker == "30A/2P")
        #expect(dryer.phases == "A·B")
        let hall = doc.rows.first { $0.slot == "5a" }!
        #expect(hall.phases == "A")          // space 5 → row 3 → leg A (2-leg)
    }

    @Test("VA column follows the toggle and the math")
    func vaColumn() throws {
        let panel = try samplePanel()
        let with = PanelPrintDocument.assemble(panelName: "P", panel: panel, config: PanelPrintConfig(showVAColumn: true))
        let without = PanelPrintDocument.assemble(panelName: "P", panel: panel, config: PanelPrintConfig(showVAColumn: false))
        #expect(with.rows.first { $0.slot == "2–4" }?.va == 5760)   // 24A @240
        #expect(without.rows.allSatisfy { $0.va == nil })
    }

    @Test("Wire column appears only when enabled and follows the table")
    func wireColumn() throws {
        let doc = PanelPrintDocument.assemble(
            panelName: "P", panel: try samplePanel(),
            config: PanelPrintConfig(showWireColumn: true)
        )
        #expect(doc.rows.first { $0.slot == "5b" }?.wire == "#12 Cu")   // 20A
        #expect(doc.rows.first { $0.slot == "7–9↓" }?.wire == "#8 Cu")  // 50A
    }

    @Test("Empty spaces render as open rows only when enabled, in order")
    func emptyRows() throws {
        let panel = try samplePanel()
        let doc = PanelPrintDocument.assemble(
            panelName: "P", panel: panel,
            config: PanelPrintConfig(showEmptySpaces: true)
        )
        let openRows = doc.rows.filter(\.isEmpty)
        // 12 spaces; occupied: 2,4 (full) + 5 (tandem) + 7,9 (quad) = 5 → 7 open.
        #expect(openRows.count == 7)
        #expect(doc.rows.first?.slot == "1")  // sorted numerically
        let off = PanelPrintDocument.assemble(panelName: "P", panel: panel, config: PanelPrintConfig())
        #expect(off.rows.allSatisfy { !$0.isEmpty })
    }

    @Test("Load summary: legs, imbalance, demand, min service")
    func summary() throws {
        var panel = DesignPanelState(setup: DesignPanelSetup(
            voltageSystem: .v120_240Single3Wire, totalSpaces: 8, mainAmps: 100
        ))
        try panel.save(.full(poles: 1, circuit: .init(amps: 20, usedAmps: 20)), atAnchor: 1) // A: 2400 VA
        try panel.save(.full(poles: 1, circuit: .init(amps: 20, usedAmps: 10)), atAnchor: 3) // B: 1200 VA
        let doc = PanelPrintDocument.assemble(
            panelName: "P", panel: panel,
            config: PanelPrintConfig(demandFactorPercent: 125, showDemandCalc: true)
        )
        #expect(doc.summary.perLegVA == [2400, 1200])
        #expect(doc.summary.perLegAmps == [20, 10])
        #expect(doc.summary.perLegPercent == [20, 10])
        #expect(doc.summary.totalConnectedVA == 3600)
        #expect(doc.summary.serviceAmps == 15)
        #expect(doc.summary.imbalancePercent == 50)   // (20-10)/20
        #expect(doc.summary.demandVA == 4500)         // 125% of 3600
        #expect(doc.summary.demandAmps == 19)         // 4500/240 rounded
        #expect(doc.summary.minServiceAmps == 60)     // next standard ≥ 18.75
    }

    @Test("Notes assemble from section notes with slot prefixes; toggle honored")
    func notes() throws {
        let panel = try samplePanel()
        let with = PanelPrintDocument.assemble(panelName: "P", panel: panel, config: PanelPrintConfig(showNotes: true))
        #expect(with.notes.contains { $0.hasPrefix("#2–4 Dryer:") && $0.contains("#10 THHN") })
        let without = PanelPrintDocument.assemble(panelName: "P", panel: panel, config: PanelPrintConfig(showNotes: false))
        #expect(without.notes.isEmpty)
    }

    @Test("Title block carries the 12 spec fields; footer always has the disclaimer")
    func titleBlockAndFooter() throws {
        let doc = PanelPrintDocument.assemble(
            panelName: "Shop Panel", panel: try samplePanel(),
            config: PanelPrintConfig(project: "Barn", jobNumber: "J-42", paper: .a4)
        )
        #expect(doc.titleBlock.count == 12)
        #expect(doc.titleBlock.first { $0.label == "Project" }?.value == "Barn")
        #expect(doc.titleBlock.first { $0.label == "Spaces" }?.value == "12 · 7 free")
        #expect(doc.footer.hasPrefix("A4 · "))
        #expect(doc.footer.contains("verify against NEC"))
        #expect(doc.titleRight == ["PANEL SCHEDULE", "Shop Panel", doc.titleRight[2]])
    }

    @Test("Demand factor clamps to 25...150 and paper sizes are correct")
    func configClamps() {
        #expect(PanelPrintConfig(demandFactorPercent: 10).demandFactorPercent == 25)
        #expect(PanelPrintConfig(demandFactorPercent: 400).demandFactorPercent == 150)
        #expect(PanelPrintConfig.Paper.letter.pointSize.width == 612)
        #expect(PanelPrintConfig.Paper.a4.pointSize.height == 842)
    }
}
