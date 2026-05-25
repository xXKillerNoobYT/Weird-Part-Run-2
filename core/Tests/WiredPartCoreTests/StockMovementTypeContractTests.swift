import Testing
@testable import WiredPartCore

@Suite("Stock Movement Type Contract Tests")
struct StockMovementTypeContractTests {

    @Test("UI movement filters use the canonical stock movement type contract")
    func uiMovementFiltersUseCanonicalContract() {
        let filterTypes = StockMovement.MovementType.primaryUIFilterTypes

        #expect(filterTypes == [.transfer, .receive, .consume, .returnToSupplier, .adjustment])
        #expect(filterTypes.map(\.rawValue) == ["transfer", "receive", "consume", "return_to_supplier", "adjustment"])
        #expect(filterTypes.map(\.displayName) == ["Transfer", "Received", "Consumed", "Returned", "Adjustment"])
        #expect(filterTypes.map(\.systemImageName) == ["arrow.left.arrow.right", "arrow.down.circle", "flame", "arrow.uturn.left", "plus.forwardslash.minus"])
    }

    @Test("Primary UI filters include every raw movement value rendered with the same label")
    func primaryUIFiltersIncludeGroupedRawValues() {
        #expect(StockMovement.MovementType.transfer.primaryUIFilterRawValues == Set(["transfer"]))
        #expect(StockMovement.MovementType.receive.primaryUIFilterRawValues == Set(["receive", "receiving", "receipt"]))
        #expect(StockMovement.MovementType.consume.primaryUIFilterRawValues == Set(["consume", "pull", "usage", "job_pull"]))
        #expect(StockMovement.MovementType.returnToSupplier.primaryUIFilterRawValues == Set(["return", "return_to_supplier"]))
        #expect(StockMovement.MovementType.adjustment.primaryUIFilterRawValues == Set(["adjustment"]))
    }

    @Test("Movement type display fallback normalizes raw persisted values")
    func displayFallbackNormalizesRawPersistedValues() {
        #expect(StockMovement.MovementType.displayName(forRawValue: "return_to_supplier") == "Returned")
        #expect(StockMovement.MovementType.displayName(forRawValue: "receiving_staged") == "Receiving Staged")
        #expect(StockMovement.MovementType.displayName(forRawValue: "custom_type") == "Custom Type")
    }

    @Test("Wizard route derivation uses canonical movement types")
    func wizardRouteDerivationUsesCanonicalMovementTypes() {
        #expect(
            StockMovement.MovementType.from(sourceLocationType: "warehouse", destinationLocationType: "job") == .consume
        )
        #expect(
            StockMovement.MovementType.from(sourceLocationType: "job", destinationLocationType: "truck") == .returnToSupplier
        )
        #expect(
            StockMovement.MovementType.from(sourceLocationType: "warehouse", destinationLocationType: "truck") == .transfer
        )
    }
}
