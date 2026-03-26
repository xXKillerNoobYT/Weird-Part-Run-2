import SwiftUI
import WiredPartCore

// MARK: - Identifiable Conformances for .sheet(item:)

extension PartCategory: @retroactive Identifiable {}
extension PartStyle: @retroactive Identifiable {}
extension PartType: @retroactive Identifiable {}
extension PartColor: @retroactive Identifiable {}

// MARK: - Category Form Sheet

struct CategoryFormSheet: View {
    let category: PartCategory?
    let onSave: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var sortOrder = 0
    @State private var saveError: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Category Details") {
                    TextField("Name", text: $name)
                        .frame(minHeight: 44)
                    TextField("Description (optional)", text: $description)
                        .frame(minHeight: 44)
                    Stepper("Sort Order: \(sortOrder)", value: $sortOrder, in: 0...999)
                }

                if let error = saveError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle(category == nil ? "New Category" : "Edit Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await saveAndDismiss() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onAppear {
                if let c = category {
                    name = c.name
                    description = c.description ?? ""
                    sortOrder = c.sortOrder
                }
            }
        }
    }

    private func saveAndDismiss() async {
        isSaving = true
        saveError = nil
        do {
            try await save()
            await onSave()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }

    private func save() async throws {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            throw NSError(domain: "WiredPart", code: 0, userInfo: [NSLocalizedDescriptionKey: "Name cannot be empty"])
        }
        guard let service = appCore.partsService else {
            saveError = "Parts service not available"
            throw NSError(domain: "WiredPart", code: 0, userInfo: [NSLocalizedDescriptionKey: "Parts service not available"])
        }
        if let existing = category, let id = existing.id {
            try service.updateCategory(id: id, name: trimmedName, description: description.isEmpty ? nil : description, sortOrder: sortOrder)
        } else {
            try service.createCategory(name: trimmedName, description: description.isEmpty ? nil : description)
        }
    }
}

// MARK: - Style Form Sheet

struct StyleFormSheet: View {
    let style: PartStyle?
    let categoryId: Int64
    let onSave: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var sortOrder = 0
    @State private var saveError: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Style Details") {
                    TextField("Name", text: $name)
                        .frame(minHeight: 44)
                    TextField("Description (optional)", text: $description)
                        .frame(minHeight: 44)
                    Stepper("Sort Order: \(sortOrder)", value: $sortOrder, in: 0...999)
                }

                if let error = saveError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle(style == nil ? "New Style" : "Edit Style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await saveAndDismiss() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onAppear {
                if let s = style {
                    name = s.name
                    description = s.description ?? ""
                    sortOrder = s.sortOrder
                }
            }
        }
    }

    private func saveAndDismiss() async {
        isSaving = true
        saveError = nil
        do {
            try await save()
            await onSave()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }

    private func save() async throws {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            throw NSError(domain: "WiredPart", code: 0, userInfo: [NSLocalizedDescriptionKey: "Name cannot be empty"])
        }
        guard let service = appCore.partsService else {
            saveError = "Parts service not available"
            throw NSError(domain: "WiredPart", code: 0, userInfo: [NSLocalizedDescriptionKey: "Parts service not available"])
        }
        if let existing = style, let id = existing.id {
            try service.updateStyle(id: id, name: trimmedName, description: description.isEmpty ? nil : description, sortOrder: sortOrder)
        } else {
            try service.createStyle(categoryId: categoryId, name: trimmedName, description: description.isEmpty ? nil : description, sortOrder: sortOrder)
        }
    }
}

// MARK: - Type Form Sheet

struct TypeFormSheet: View {
    let type: PartType?
    let styleId: Int64
    let onSave: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var sortOrder = 0
    @State private var saveError: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Type Details") {
                    TextField("Name", text: $name)
                        .frame(minHeight: 44)
                    TextField("Description (optional)", text: $description)
                        .frame(minHeight: 44)
                    Stepper("Sort Order: \(sortOrder)", value: $sortOrder, in: 0...999)
                }

                if let error = saveError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle(type == nil ? "New Type" : "Edit Type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await saveAndDismiss() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onAppear {
                if let t = type {
                    name = t.name
                    description = t.description ?? ""
                    sortOrder = t.sortOrder
                }
            }
        }
    }

    private func saveAndDismiss() async {
        isSaving = true
        saveError = nil
        do {
            try await save()
            await onSave()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }

    private func save() async throws {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            throw NSError(domain: "WiredPart", code: 0, userInfo: [NSLocalizedDescriptionKey: "Name cannot be empty"])
        }
        guard let service = appCore.partsService else {
            saveError = "Parts service not available"
            throw NSError(domain: "WiredPart", code: 0, userInfo: [NSLocalizedDescriptionKey: "Parts service not available"])
        }
        if let existing = type, let id = existing.id {
            try service.updateType(id: id, name: trimmedName, description: description.isEmpty ? nil : description, sortOrder: sortOrder)
        } else {
            try service.createType(styleId: styleId, name: trimmedName, description: description.isEmpty ? nil : description, sortOrder: sortOrder)
        }
    }
}

// MARK: - Color Form Sheet

struct ColorFormSheet: View {
    let color: PartColor?
    let onSave: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var hasColor = false
    @State private var selectedColor: Color = .gray
    @State private var sortOrder = 0
    @State private var saveError: String?
    @State private var isSaving = false

    /// Common preset colors for quick selection
    private let presetColors: [(String, Color)] = [
        ("White", .white),
        ("Black", .black),
        ("Red", Color(.systemRed)),
        ("Blue", Color(.systemBlue)),
        ("Green", Color(.systemGreen)),
        ("Yellow", Color(.systemYellow)),
        ("Orange", Color(.systemOrange)),
        ("Purple", Color(.systemPurple)),
        ("Pink", Color(.systemPink)),
        ("Brown", Color(.systemBrown)),
        ("Gray", Color(.systemGray)),
        ("Teal", Color(.systemTeal)),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Color Name") {
                    TextField("e.g. Matte Black, Brushed Silver", text: $name)
                        .frame(minHeight: 44)
                }

                Section {
                    Toggle("Has a visible color", isOn: $hasColor.animation())
                } footer: {
                    if !hasColor {
                        Text("Use \"None\" for items that don't have color options — like raw materials, hardware, or unpainted parts.")
                    }
                }

                if hasColor {
                    Section("Pick a Color") {
                        // Preset grid
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 52), spacing: 8)
                        ], spacing: 8) {
                            ForEach(presetColors, id: \.0) { preset in
                                presetButton(name: preset.0, color: preset.1)
                            }
                        }
                        .padding(.vertical, 4)

                        // System color picker for custom colors
                        ColorPicker("Custom Color", selection: $selectedColor, supportsOpacity: false)
                            .frame(minHeight: 44)
                    }

                    Section("Preview") {
                        HStack {
                            Circle()
                                .fill(selectedColor)
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                                )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(name.isEmpty ? "Color Name" : name)
                                    .font(.headline)
                                    .foregroundStyle(name.isEmpty ? .secondary : .primary)
                                Text(hexStringFromColor(selectedColor))
                                    .font(.caption)
                                    .monospaced()
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                } else {
                    Section("Preview") {
                        HStack {
                            ZStack {
                                Circle()
                                    .fill(Color(.secondarySystemGroupedBackground))
                                    .frame(width: 40, height: 40)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                                    )
                                Image(systemName: "nosign")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(name.isEmpty ? "No Color" : name)
                                    .font(.headline)
                                    .foregroundStyle(name.isEmpty ? .secondary : .primary)
                                Text("No hex value")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    Stepper("Sort Order: \(sortOrder)", value: $sortOrder, in: 0...999)
                }

                if let error = saveError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle(color == nil ? "New Color" : "Edit Color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await saveAndDismiss() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onAppear {
                if let c = color {
                    name = c.name
                    sortOrder = c.sortOrder
                    if let hex = c.hexCode {
                        hasColor = true
                        selectedColor = Color(hex: hex) ?? .gray
                    } else {
                        hasColor = false
                    }
                }
            }
        }
    }

    // MARK: - Preset Button

    @ViewBuilder
    private func presetButton(name: String, color: Color) -> some View {
        let isSelected = hasColor && colorsMatch(selectedColor, color)
        Button {
            selectedColor = color
        } label: {
            VStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                    )
                    .overlay {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.caption.bold())
                                .foregroundStyle(color == .white || color == Color(.systemYellow) ? .black : .white)
                        }
                    }
                Text(name)
                    .font(.system(size: 9))
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    /// Convert a SwiftUI Color to a hex string like "#FF0000"
    private func hexStringFromColor(_ color: Color) -> String {
        let resolved = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }

    /// Rough comparison of two colors by hex output
    private func colorsMatch(_ a: Color, _ b: Color) -> Bool {
        hexStringFromColor(a) == hexStringFromColor(b)
    }

    // MARK: - Save

    private func saveAndDismiss() async {
        isSaving = true
        saveError = nil
        do {
            try await save()
            await onSave()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }

    private func save() async throws {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            throw NSError(domain: "WiredPart", code: 0, userInfo: [NSLocalizedDescriptionKey: "Name cannot be empty"])
        }
        guard let service = appCore.partsService else {
            saveError = "Parts service not available"
            throw NSError(domain: "WiredPart", code: 0, userInfo: [NSLocalizedDescriptionKey: "Parts service not available"])
        }
        let hex: String? = hasColor ? hexStringFromColor(selectedColor) : nil
        if let existing = color, let id = existing.id {
            try service.updateColor(id: id, name: trimmedName, hexCode: hex ?? "", sortOrder: sortOrder)
        } else {
            try service.createColor(name: trimmedName, hexCode: hex ?? "", sortOrder: sortOrder)
        }
    }
}
