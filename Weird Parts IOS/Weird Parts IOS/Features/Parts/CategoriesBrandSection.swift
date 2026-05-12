import SwiftUI
import WiredPartCore

/// Brand editing section for a selected Type.
/// Shows checkboxes for all brands (linked vs unlinked), with
/// manufacturer part number fields for named brands and
/// supplier part numbers for each brand's suppliers.
///
/// "General" is always available as a pseudo-brand — when checked,
/// no part number is needed and no warnings appear.
struct CategoriesBrandSection: View {
    let typeId: Int64
    /// If a specific brand is focused, highlight it and scroll to it.
    var focusedBrandId: Int64?

    @EnvironmentObject private var appCore: AppCore
    @State private var allBrands: [Brand] = []
    @State private var linkedBrandIds: Set<Int64> = []
    @State private var brandLinkIds: [Int64: Int64] = [:] // brandId -> linkRowId
    @State private var mfrPartNumbers: [Int64: String] = [:] // brandId -> mfr part number
    @State private var suppliersByBrand: [Int64: [Supplier]] = [:] // brandId -> suppliers
    @State private var supplierPartNumbers: [String: String] = [:] // "brandId-supplierId" -> supplier part number
    @State private var isGeneralLinked = false
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var pendingBrandRemoval: BrandRemovalConfirmation?

    /// Key constant for the "General" pseudo-brand
    private static let generalBrandName = "General"

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text("Brands")
                .font(.headline)
                .padding(.bottom, DS.Space.xxs)

            if let error = loadError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                // General brand option (always first)
                generalBrandRow

                Divider()

                // Named brands
                ForEach(allBrands, id: \.id) { brand in
                    namedBrandRow(brand)
                }

                if allBrands.isEmpty {
                    Text("No brands in the system yet. Add brands from the Brands tab.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, DS.Space.sm)
                }
            }
        }
        .refreshable { await loadBrandData() }
        .task { await loadBrandData() }
        .confirmationDialog(
            "Remove Brand?",
            isPresented: Binding(
                get: { pendingBrandRemoval != nil },
                set: { if !$0 { pendingBrandRemoval = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingBrandRemoval
        ) { removal in
            Button("Remove", role: .destructive) {
                Task { await removeBrand(removal) }
            }
            Button("Cancel", role: .cancel) {
                pendingBrandRemoval = nil
            }
        } message: { removal in
            Text(removal.message)
        }
    }

    // MARK: - General Brand Row

    @ViewBuilder
    private var generalBrandRow: some View {
        HStack(spacing: DS.Space.md) {
            Image(systemName: isGeneralLinked ? "checkmark.square.fill" : "square")
                .foregroundStyle(isGeneralLinked ? Color.accentColor : Color.secondary)
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("General")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("No specific brand — part number not required")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isGeneralLinked ? .isSelected : [])
        .onTapGesture {
            isGeneralLinked.toggle()
        }
    }

    // MARK: - Named Brand Row

    @ViewBuilder
    private func namedBrandRow(_ brand: Brand) -> some View {
        let brandId = brand.id ?? 0
        let isLinked = linkedBrandIds.contains(brandId)
        let isFocused = focusedBrandId == brandId

        VStack(alignment: .leading, spacing: DS.Space.sm) {
            // Checkbox row
            HStack(spacing: DS.Space.md) {
                Image(systemName: isLinked ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isLinked ? Color.accentColor : Color.secondary)
                    .font(.title3)
                    .accessibilityHidden(true)
                Text(brand.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()

                // Warning if linked but no manufacturer part number
                if isLinked {
                    let mfrPn = mfrPartNumbers[brandId] ?? ""
                    if mfrPn.trimmingCharacters(in: .whitespaces).isEmpty {
                        HStack(spacing: DS.Space.xxs) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                                .accessibilityHidden(true)
                            Text("Part # recommended")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(isLinked ? .isSelected : [])
            .onTapGesture {
                if isLinked {
                    pendingBrandRemoval = BrandRemovalConfirmation(brandId: brandId, brandName: brand.name)
                } else {
                    Task { await addBrand(brandId: brandId) }
                }
            }

            // Expanded details when linked
            if isLinked {
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    // Manufacturer part number
                    HStack(spacing: DS.Space.sm) {
                        Text("Mfr Part #:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .trailing)
                        TextField("Manufacturer part number", text: Binding(
                            get: { mfrPartNumbers[brandId] ?? "" },
                            set: { mfrPartNumbers[brandId] = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.subheadline)
                    }
                    .padding(.leading, DS.Space.xxxl)

                    // Supplier part numbers
                    let suppliers = suppliersByBrand[brandId] ?? []
                    if !suppliers.isEmpty {
                        DisclosureGroup("Supplier Part Numbers (\(suppliers.count))") {
                            ForEach(suppliers, id: \.id) { supplier in
                                let key = "\(brandId)-\(supplier.id ?? 0)"
                                HStack(spacing: DS.Space.sm) {
                                    Text(supplier.name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 100, alignment: .trailing)
                                        .lineLimit(1)
                                    TextField("Supplier part #", text: Binding(
                                        get: { supplierPartNumbers[key] ?? "" },
                                        set: { supplierPartNumbers[key] = $0 }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .font(.subheadline)
                                }
                            }
                        }
                        .font(.caption)
                        .padding(.leading, DS.Space.xxxl)
                    }
                }
            }

            Divider()
        }
        .background(isFocused ? Color.accentColor.opacity(0.06) : Color.clear)
    }

    // MARK: - Data Loading

    private func loadBrandData() async {
        guard let service = appCore.partsService else {
            loadError = "Parts service not available"
            isLoading = false
            return
        }
        do {
            let brands = try service.listBrands()
            let allBrandsList = brands.map(\.brand)

            // Get type-brand links for this type from the hierarchy
            let hierarchy = try service.getHierarchy()
            var linkedIds = Set<Int64>()

            // Find the type node in the hierarchy to get its linked brands
            for catNode in hierarchy.categories {
                for styleNode in catNode.styles {
                    for typeNode in styleNode.types {
                        if typeNode.type.id == typeId {
                            for brand in typeNode.brands {
                                if let bid = brand.id {
                                    linkedIds.insert(bid)
                                }
                            }
                        }
                    }
                }
            }

            // Load brand-supplier links for each brand
            var supplierMap: [Int64: [Supplier]] = [:]
            for brand in allBrandsList {
                guard let brandId = brand.id else { continue }
                let suppliers = try service.getBrandSuppliers(brandId: brandId)
                if !suppliers.isEmpty {
                    supplierMap[brandId] = suppliers
                }
            }

            await MainActor.run {
                allBrands = allBrandsList
                linkedBrandIds = linkedIds
                suppliersByBrand = supplierMap
                isGeneralLinked = TypeBrandSelectionDefaults.isGeneralSelectedOnLoad
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = userFriendlyError(error, context: "load category brands")
                isLoading = false
            }
        }
    }

    // MARK: - Toggle Brand Link

    private func addBrand(brandId: Int64) async {
        guard let service = appCore.partsService else {
            loadError = "Service not available"
            return
        }
        do {
            try service.linkTypeToBrand(typeId: typeId, brandId: brandId)
            linkedBrandIds.insert(brandId)
        } catch {
            loadError = userFriendlyError(error, context: "load brands")
        }
    }

    private func removeBrand(_ removal: BrandRemovalConfirmation) async {
        guard let service = appCore.partsService else {
            loadError = "Service not available"
            return
        }
        do {
            let linkId = try service.getTypeBrandLinkId(typeId: typeId, brandId: removal.brandId)
            if let linkId {
                try service.unlinkTypeBrand(linkId: linkId)
            }
            linkedBrandIds.remove(removal.brandId)
            pendingBrandRemoval = nil
        } catch {
            loadError = userFriendlyError(error, context: "load brands")
        }
    }
}
