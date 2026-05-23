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

    @Test("Movement type display fallback normalizes raw persisted values")
    func displayFallbackNormalizesRawPersistedValues() {
        #expect(StockMovement.MovementType.displayName(forRawValue: "return_to_supplier") == "Returned")
        #expect(StockMovement.MovementType.displayName(forRawValue: "receiving_staged") == "Receiving Staged")
        #expect(StockMovement.MovementType.displayName(forRawValue: "custom_type") == "Custom Type")
    }
}
