# Prompt 14G — Categories: First-Use Guidance + Help Bubble

> Read `xcode-ai/xcode.md` first for project conventions.

## Goal

Add onboarding guidance for the Categories hierarchy system:

1. **First-time empty state** — when no categories exist, show a step-by-step explanation of the hierarchy concept
2. **Help bubble button** — always visible in the header, shows the hierarchy explanation in a popover/sheet. Especially useful when a new user is added to an existing database with data already present

## Files to Modify

1. `Weird Parts IOS/Weird Parts IOS/Features/Parts/CategoriesTreeView.swift`

## Step 1: Add Help Content

Add a new struct at the bottom of the file (or as a private view within `CategoriesTreeView`):

```swift
// MARK: - Hierarchy Help View

struct HierarchyHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    // Overview
                    Text("How the Parts Hierarchy Works")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Parts are organized in a 5-level tree. Each level adds specificity:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    // Level explanations
                    hierarchyLevel(
                        number: 1,
                        name: "Category",
                        icon: "folder.fill",
                        color: .accentColor,
                        example: "e.g. Electrical, Plumbing, Framing",
                        description: "The broadest grouping. Start here."
                    )

                    hierarchyLevel(
                        number: 2,
                        name: "Style",
                        icon: "paintbrush.fill",
                        color: .purple,
                        example: "e.g. Residential, Commercial, Industrial",
                        description: "A variation within a category. Different styles may use different types of parts."
                    )

                    hierarchyLevel(
                        number: 3,
                        name: "Type",
                        icon: "wrench.and.screwdriver.fill",
                        color: .teal,
                        example: "e.g. 12/2 Wire, 14/2 Wire, THHN",
                        description: "The specific kind of part. This is where you link brands and colors."
                    )

                    hierarchyLevel(
                        number: 4,
                        name: "Brand",
                        icon: "tag.fill",
                        color: .orange,
                        example: "e.g. Southwire, Cerro, General",
                        description: "Which manufacturer makes this type. 'General' means no specific brand."
                    )

                    hierarchyLevel(
                        number: 5,
                        name: "Color",
                        icon: "circle.fill",
                        color: .pink,
                        example: "e.g. White, Black, Red, None",
                        description: "The color variant. Selecting a color under a brand creates a catalog entry you can order and stock."
                    )

                    Divider()

                    // Quick start
                    VStack(alignment: .leading, spacing: DS.Space.sm) {
                        Text("Quick Start")
                            .font(.headline)

                        stepRow(step: 1, text: "Tap the **+** button to create a Category")
                        stepRow(step: 2, text: "Tap into the category and add a **Style**")
                        stepRow(step: 3, text: "Add a **Type** under the style")
                        stepRow(step: 4, text: "Link **Brands** to the type using checkboxes")
                        stepRow(step: 5, text: "Pick **Colors** under each brand to create catalog entries")
                    }

                    Divider()

                    Text("Each catalog entry (Type + Brand + Color) becomes a part you can order, stock, and track.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(DS.Space.lg)
            }
            .navigationTitle("Hierarchy Guide")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func hierarchyLevel(number: Int, name: String, icon: String, color: Color, example: String, description: String) -> some View {
        HStack(alignment: .top, spacing: DS.Space.md) {
            // Level indicator
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 36, height: 36)
                Text("\(number)")
                    .font(.system(.subheadline, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                        .font(.subheadline)
                    Text(name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(example)
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary.opacity(0.8))
            }
        }
        // Indent each level slightly more
        .padding(.leading, CGFloat(number - 1) * 8)
    }

    @ViewBuilder
    private func stepRow(step: Int, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: DS.Space.sm) {
            Text("\(step).")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(.accentColor)
                .frame(width: 20, alignment: .trailing)
            Text(text)
                .font(.subheadline)
        }
    }
}
```

## Step 2: Add Help Button to Tree Header

In `CategoriesTreeView`, find the header `HStack` that contains "Parts Hierarchy" and the `+` menu. Add a help button between the title and the `+` button:

```swift
@State private var showHelp = false
```

In the header HStack:

```swift
HStack {
    Text("Parts Hierarchy")
        .font(.headline)

    // Help bubble button
    Button {
        showHelp = true
    } label: {
        Image(systemName: "questionmark.circle")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
    .buttonStyle(.plain)

    Spacer()

    Menu {
        // ... existing + menu
    } label: {
        Image(systemName: "plus.circle.fill")
            .font(.title3)
    }
}
```

Add the sheet for help:

```swift
.sheet(isPresented: $showHelp) {
    HierarchyHelpView()
}
```

**Important:** This is a second `.sheet` modifier. To avoid the multiple-sheet conflict, integrate it into the existing `ActiveSheet` enum instead:

Add to `ActiveSheet`:
```swift
case help
```

With id:
```swift
case .help: return "help"
```

And in the `.sheet(item:)` switch:
```swift
case .help:
    HierarchyHelpView()
```

Then the help button becomes:
```swift
Button {
    activeSheet = .help
} label: {
    Image(systemName: "questionmark.circle")
        .font(.subheadline)
        .foregroundStyle(.secondary)
}
```

## Step 3: Enhanced Empty State with Guidance

Update the empty state in `CategoriesTreeView` (when `hierarchy.categories.isEmpty`). Replace the current `EmptyStateView` with a more helpful first-use guide:

```swift
if hierarchy.categories.isEmpty {
    VStack(spacing: DS.Space.lg) {
        Spacer()

        Image(systemName: "folder.badge.questionmark")
            .font(.system(size: 48))
            .foregroundStyle(.secondary)

        Text("No Categories Yet")
            .font(.title3)
            .fontWeight(.semibold)

        Text("The parts hierarchy organizes your inventory into 5 levels:\nCategory > Style > Type > Brand > Color")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, DS.Space.xl)

        VStack(spacing: DS.Space.sm) {
            Button {
                activeSheet = .addCategory
            } label: {
                Label("Create First Category", systemImage: "plus.circle.fill")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .frame(maxWidth: 240)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)

            Button {
                activeSheet = .help
            } label: {
                Label("Learn How It Works", systemImage: "questionmark.circle")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
        }

        Spacer()
    }
    .frame(maxWidth: .infinity)
}
```

## Success Criteria

- [ ] Build succeeds with no errors
- [ ] Help button (?) visible in the tree header, next to "Parts Hierarchy" title
- [ ] Tapping help button opens HierarchyHelpView sheet
- [ ] Help view explains all 5 levels with icons, descriptions, and examples
- [ ] Help view includes "Quick Start" steps
- [ ] Empty state (no categories) shows hierarchy overview + "Create First Category" button + "Learn How It Works" link
- [ ] Help button uses the `ActiveSheet` enum (no second `.sheet` modifier)
- [ ] Works for new users added to existing databases (help button always available)

## Next

When all criteria are met, the Categories page improvements are complete. Return to `xcode-ai/fix-prompts/00-fix-order.md` for the next page to review.
