import SwiftUI
import GRDB
import WiredPartCore

// MARK: - Identifiable Conformances for .sheet(item:)

extension PartCategory: @retroactive Identifiable {}
extension PartStyle: @retroactive Identifiable {}
extension PartType: @retroactive Identifiable {}

// MARK: - Category Form Sheet

struct CategoryFormSheet: View {
    let category: PartCategory?
    let onSave: () async -> Void
    @EnvironmentObject private var appCore: AppCore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var sortOrder = 0

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
            }
            .navigationTitle(category == nil ? "New Category" : "Edit Category")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await save()
                            await onSave()
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
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

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        do {
            guard let service = appCore.partsService else { return }
            if let existing = category, let id = existing.id {
                try service.updateCategory(id: id, name: trimmedName, description: description.isEmpty ? nil : description, sortOrder: sortOrder)
            } else {
                try service.createCategory(name: trimmedName, description: description.isEmpty ? nil : description)
            }
        } catch {
            print("[CategoryFormSheet] Save error: \(error)")
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
            }
            .navigationTitle(style == nil ? "New Style" : "Edit Style")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await save()
                            await onSave()
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
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

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        do {
            guard let service = appCore.partsService else { return }
            if let existing = style, let id = existing.id {
                try service.updateStyle(id: id, name: trimmedName, description: description.isEmpty ? nil : description, sortOrder: sortOrder)
            } else {
                try service.createStyle(categoryId: categoryId, name: trimmedName, description: description.isEmpty ? nil : description, sortOrder: sortOrder)
            }
        } catch {
            print("[StyleFormSheet] Save error: \(error)")
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
            }
            .navigationTitle(type == nil ? "New Type" : "Edit Type")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await save()
                            await onSave()
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
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

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        do {
            guard let service = appCore.partsService else { return }
            if let existing = type, let id = existing.id {
                try service.updateType(id: id, name: trimmedName, description: description.isEmpty ? nil : description, sortOrder: sortOrder)
            } else {
                try service.createType(styleId: styleId, name: trimmedName, description: description.isEmpty ? nil : description, sortOrder: sortOrder)
            }
        } catch {
            print("[TypeFormSheet] Save error: \(error)")
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
    @State private var hexCode = "#888888"
    @State private var sortOrder = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Color Details") {
                    TextField("Name", text: $name)
                        .frame(minHeight: 44)
                    TextField("Hex Code (e.g. #FF0000)", text: $hexCode)
                        .frame(minHeight: 44)
                        .monospaced()
                    HStack {
                        Text("Preview")
                        Spacer()
                        Circle()
                            .fill(Color(hex: hexCode) ?? .gray)
                            .frame(width: 32, height: 32)
                    }
                    Stepper("Sort Order: \(sortOrder)", value: $sortOrder, in: 0...999)
                }
            }
            .navigationTitle(color == nil ? "New Color" : "Edit Color")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await save()
                            await onSave()
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let c = color {
                    name = c.name
                    hexCode = c.hexCode ?? "#888888"
                    sortOrder = c.sortOrder
                }
            }
        }
    }

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        do {
            guard let service = appCore.partsService else { return }
            if let existing = color, let id = existing.id {
                try service.updateColor(id: id, name: trimmedName, hexCode: hexCode, sortOrder: sortOrder)
            } else {
                try service.createColor(name: trimmedName, hexCode: hexCode, sortOrder: sortOrder)
            }
        } catch {
            print("[ColorFormSheet] Save error: \(error)")
        }
    }
}
