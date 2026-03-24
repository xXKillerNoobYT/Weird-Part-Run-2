# 30B — JPO Creation: AI-Powered Smart Search

> **Chain position:** 30A → **30B** → 30C → 30D → 30E
> **Prerequisite:** 30A complete (3-panel layout with search panel placeholder)
> **Plan:** `docs/plans/ios-jpo-creation-page.md` — Search Panel section

## Instructions

Read 30A results and the plan. When done, wait for user confirmation.

## Context

The search panel needs AI enhancement: it uses cart contents + last 5 searches as context to return smarter results. Example: user searches "1/2 EMT" → picks pipe → searches "connectors" → AI sees EMT pipe in cart → returns 1/2 EMT couplings at top. The ⚡ icon marks the MOST LIKELY match for one-tap adding. Internet help toggle at top for online part identification.

**Files to modify:**
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSJPOCreationPage.swift` — enhance search panel

## Task

### Step 1: Track recent searches

```swift
@State private var recentSearches: [String] = []  // last 5
// On search: if searchText not in recent, insert at 0, trim to 5
```

### Step 2: Build AI search context

When searching, pass context to the AI service:

```swift
private func buildSearchContext() -> String {
    var context = "User is building a parts order. "
    if !cartItems.isEmpty {
        let cartNames = cartItems.map(\.partName).joined(separator: ", ")
        context += "Cart contains: \(cartNames). "
    }
    if !recentSearches.isEmpty {
        context += "Recent searches: \(recentSearches.joined(separator: ", ")). "
    }
    if let jobName = selectedJobName {
        context += "Job: \(jobName). "
    }
    return context
}
```

### Step 3: Enhanced search with AI ranking

```swift
@State private var internetHelpEnabled = false

private func searchParts() {
    guard let service = appCore.partsService, searchText.count >= 2 else {
        searchResults = []
        return
    }

    // Standard search
    let results = (try? service.searchParts(query: searchText, limit: 20)) ?? []
    searchResults = results

    // AI re-ranking (if available)
    let aiService = FoundationModelsService()
    if aiService.checkAvailability() == .available {
        Task {
            let context = buildSearchContext()
            let prompt = """
                Given this search context: \(context)
                The user searched for: "\(searchText)"
                Which of these parts is most likely what they want?
                Return ONLY the part name of the best match.
                Parts: \(results.prefix(10).map(\.name).joined(separator: ", "))
                """
            let result = await aiService.generate(
                instructions: "You rank parts search results. Return only the best match part name.",
                prompt: prompt
            )
            if let bestMatch = result.text {
                await MainActor.run {
                    // Move the AI-picked best match to top with ⚡ indicator
                    bestMatchName = bestMatch.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
    }

    // Track recent search
    if !recentSearches.contains(searchText) {
        recentSearches.insert(searchText, at: 0)
        if recentSearches.count > 5 { recentSearches.removeLast() }
    }
}
```

### Step 4: Search result row with ⚡ indicator

```swift
@State private var bestMatchName: String?

private func searchResultRow(_ part: Part) -> some View {
    HStack(spacing: 8) {
        // AI best match indicator
        if let best = bestMatchName, part.name.lowercased().contains(best.lowercased()) {
            Image(systemName: "bolt.fill")
                .foregroundStyle(.yellow)
                .font(.caption)
        }

        VStack(alignment: .leading, spacing: 2) {
            Text(part.name)
                .font(.subheadline)
                .fontWeight(.medium)
            HStack(spacing: 8) {
                if let code = part.code {
                    Text(code).font(.caption2).monospaced().foregroundStyle(.secondary)
                }
                if let price = part.companySellPrice ?? part.companyCostPrice {
                    Text(String(format: "$%.2f", price)).font(.caption2).foregroundStyle(.secondary)
                }
                Text("Shop: \(getShopStock(partId: part.id ?? 0))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }

        Spacer()

        // Quick add with qty stepper
        HStack(spacing: 4) {
            Button { addToCart(part: part) } label: {
                Text("+ Add")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }
    .padding(.vertical, 4)
}
```

### Step 5: QR/Barcode scan integration

Wire the scan button to `QRScanSheet`:

```swift
@State private var showScanner = false

Button { showScanner = true } label: {
    Label("Scan QR/Barcode", systemImage: "qrcode.viewfinder")
        .font(.caption)
}

// In sheet routing:
.sheet(isPresented: $showScanner) {
    QRScanSheet(expectedType: nil) { result in  // nil = accept any type
        if let partId = result.entityId, result.isFound {
            if let part = try? appCore.partsService?.getPart(id: partId) {
                addToCart(part: part)
            }
        }
        showScanner = false
    }
    .environmentObject(appCore)
}
```

### Step 6: Internet help toggle

```swift
// At top of search panel:
Toggle(isOn: $internetHelpEnabled) {
    Label("Internet Help", systemImage: "globe")
        .font(.caption)
}
.toggleStyle(.switch)
.controlSize(.mini)
```

When enabled, AI search can reference online sources for part identification (e.g., looking up manufacturer part numbers). This is a future enhancement — for now, just show the toggle and pass `internetHelpEnabled` as context.

### Step 7: Recent searches display

```swift
if searchText.isEmpty && !recentSearches.isEmpty {
    VStack(alignment: .leading, spacing: 4) {
        Text("Recent").font(.caption2).foregroundStyle(.tertiary)
        ForEach(recentSearches, id: \.self) { query in
            Button {
                searchText = query
                searchParts()
            } label: {
                HStack {
                    Image(systemName: "clock").font(.caption2)
                    Text(query).font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
    }
}
```

## Success Criteria

- [ ] Search uses cart + last 5 searches as AI context
- [ ] ⚡ best match indicator on AI-picked result
- [ ] Recent searches tracked (last 5) with tap-to-reuse
- [ ] QR/barcode scan adds part to cart
- [ ] Internet help toggle (UI present, functional in future)
- [ ] AI gracefully degrades when unavailable (standard search still works)
- [ ] Project builds with no errors

**Wait for user confirmation before proceeding to prompt 30C.**
