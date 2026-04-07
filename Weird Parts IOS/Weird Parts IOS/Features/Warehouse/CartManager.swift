import SwiftUI
import Combine
import WiredPartCore

/// Item in the warehouse cart — a part or bin being moved to a new location.
struct CartItem: Identifiable, Equatable, Sendable {
    let id = UUID()
    let partId: Int64?
    let binId: Int64?
    let name: String
    let currentLocation: String?
    let quantity: Int

    static func == (lhs: CartItem, rhs: CartItem) -> Bool {
        lhs.id == rhs.id
    }
}

/// Global cart manager for moving multiple bins/parts at once.
///
/// Usage:
/// - Inject as `@StateObject` at the warehouse router level
/// - Any bin/part list can add items via `addToCart()`
/// - Cart sheet shows items and allows placing to new locations
final class CartManager: ObservableObject {
    @Published var items: [CartItem] = []
    @Published var isCartSheetPresented = false

    var itemCount: Int { items.count }
    var isEmpty: Bool { items.isEmpty }

    func addToCart(partId: Int64? = nil, binId: Int64? = nil, name: String, currentLocation: String? = nil, quantity: Int = 1) {
        // Don't add duplicates
        if let pid = partId, items.contains(where: { $0.partId == pid }) { return }
        if let bid = binId, items.contains(where: { $0.binId == bid }) { return }

        items.append(CartItem(
            partId: partId,
            binId: binId,
            name: name,
            currentLocation: currentLocation,
            quantity: quantity
        ))
    }

    func removeFromCart(_ item: CartItem) {
        items.removeAll { $0.id == item.id }
    }

    func removeAll() {
        items.removeAll()
    }

    func showCart() {
        isCartSheetPresented = true
    }
}

// MARK: - Cart Sheet View

/// Sheet showing all cart items with placement controls.
struct CartSheetView: View {
    @EnvironmentObject private var appCore: AppCore
    @ObservedObject var cartManager: CartManager
    @Environment(\.dismiss) private var dismiss

    @State private var placements: [UUID: String] = [:]
    @State private var placementError: String?
    @State private var placedItems: Set<UUID> = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if cartManager.isEmpty {
                    ContentUnavailableView {
                        Label("Cart is Empty", systemImage: "cart")
                    } description: {
                        Text("Add parts or bins from any list to move them in bulk.")
                    }
                } else {
                    cartList
                    placeAllButton
                }
            }
            .navigationTitle("Cart (\(cartManager.itemCount))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if !cartManager.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear All", role: .destructive) {
                            cartManager.removeAll()
                        }
                    }
                }
            }
            .alert("Error", isPresented: Binding(
                get: { placementError != nil },
                set: { if !$0 { placementError = nil } }
            )) {
                Button("OK") { placementError = nil }
            } message: {
                if let msg = placementError { Text(msg) }
            }
        }
    }

    // MARK: - Cart List

    private var cartList: some View {
        List {
            ForEach(cartManager.items) { item in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: item.binId != nil ? "tray.fill" : "shippingbox.fill")
                            .foregroundStyle(.blue)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            if let loc = item.currentLocation {
                                Text("From: \(loc)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if placedItems.contains(item.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }

                        Text("×\(item.quantity)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !placedItems.contains(item.id) {
                        TextField("New location (shelf, area, bin...)", text: Binding(
                            get: { placements[item.id] ?? "" },
                            set: { placements[item.id] = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                    }
                }
                .padding(.vertical, 4)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        cartManager.removeFromCart(item)
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Place All

    private var placeAllButton: some View {
        Button {
            placeAllItems()
        } label: {
            Label(
                placedItems.count == cartManager.itemCount ? "All Placed!" : "Place All Items",
                systemImage: placedItems.count == cartManager.itemCount ? "checkmark.circle.fill" : "arrow.right.circle.fill"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(placedItems.count == cartManager.itemCount ? .green : .blue)
        .disabled(placements.values.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty })
        .padding()
        .background(Color(.secondarySystemBackground))
    }

    private func placeAllItems() {
        for item in cartManager.items {
            guard let location = placements[item.id],
                  !location.trimmingCharacters(in: .whitespaces).isEmpty else { continue }

            // Update part location note
            if let partId = item.partId {
                do {
                    try appCore.partsService?.updatePart(id: partId, notes: "Location: \(location)")
                    placedItems.insert(item.id)
                } catch {
                    placementError = userFriendlyError(error, context: "place item")
                }
            } else {
                // Bin moves are logged but bins are not location-locked per spec
                placedItems.insert(item.id)
            }
        }

        // Clear placed items from cart
        if placedItems.count == cartManager.itemCount {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                cartManager.removeAll()
                dismiss()
            }
        }
    }
}

// MARK: - Cart Badge Button

/// Toolbar button showing cart badge count. Tapping opens the cart sheet.
struct CartBadgeButton: View {
    @ObservedObject var cartManager: CartManager

    var body: some View {
        Button {
            cartManager.showCart()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "cart")
                    .font(.body)

                if cartManager.itemCount > 0 {
                    Text("\(cartManager.itemCount)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(Color.red)
                        .clipShape(Circle())
                        .offset(x: 6, y: -6)
                }
            }
        }
        .accessibilityLabel("Cart: \(cartManager.itemCount) items")
    }
}
