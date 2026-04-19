# iOS JPO Creation Page Design (Order Making)

> **Page:** Replaces `IOSUnifiedOrderPage.swift` (123 lines → full redesign)
> **Nav:** Accessed from JPO List [+] button, Clock Page, Job Detail
> **Status:** Design CONFIRMED (2026-03-22)

## Core Concept

A 3-panel order-building experience where field workers create parts lists for jobs. Smart search finds parts fast, the cart tracks what's been added with stock indicators, and a suggestions panel recommends related parts using companion rules + AI. Every interaction trains the companion rules system.

## Layout — 3 Panels

### Desktop/Tablet (side-by-side)
```
┌──────────────────┬────────────────────────┬──────────────────────────────┐
│  🔍 SEARCH       │  🛒 CART               │  💡 SUGGESTIONS              │
│  (left panel)    │  (center panel)        │  (right panel)               │
└──────────────────┴────────────────────────┴──────────────────────────────┘
```

### Mobile/iPhone (stacked vertically)
```
┌────────────────────────┐
│  🔍 Search + results   │
│  🛒 Cart               │
│  ▶ 💡 Suggestions (8)  │  ← collapsible
└────────────────────────┘
```

## Panel 1: Search (Left)

### Smart Search
- Text search: name, code, description, UPC
- [📷 Scan QR/Bar] button for barcode/QR scanning
- Recent searches shown below (last 5)

### AI-Powered Search Enhancement
- AI uses **cart contents + last 5 searches** as context
- Example: user searches "1/2 EMT" → picks 10ft pipe → searches "connectors" → AI sees 1/2 EMT pipe in cart → returns 1/2 EMT couplings at the top
- Understands natural language: "that flux stuff" = Copper Flux Paste
- ⚡ icon on the MOST LIKELY match for one-tap adding

### AI Data Sources for Search
- **Local (always):** Parts catalog, job history (which parts were used on similar jobs), JPO history, companion rules
- **Online (when available):** Can search online for part identification help, cross-referencing manufacturer part numbers
- **Toggle at top:** Internet help on/off for the AI search

### Search Result Row
```
┌────────────────────────────────┐
│ ⚡ ½" Copper Fitting           │
│   CF-050 · $2.14 · Shop: 45   │
│   [+ Add]  qty: [1] [-][+]    │
└────────────────────────────────┘
```

## Panel 2: Cart (Center)

### Cart Items
Each item shows:
- Part name + code
- Quantity with [-][+] stepper (easy to adjust)
- Unit price × qty = total
- Stock indicator:
  - 🟢 In stock (enough for order) → will auto-transfer
  - 🟡 Low stock (some available, not enough) → partial transfer + order rest
  - 🔴 Not in stock → needs full ordering
- [✕] Remove button

### Cart Summary
- Total parts count
- Estimated total cost
- Transfer vs ordering breakdown: "2 transfer · 2 ordering"

### Tapping a Cart Item
- Highlights that item
- Updates suggestions panel to show companions for THAT part
- Shows edit options (change qty inline)

### Cart Header
```
Job: Smith Residence (#412) ← auto from clock
[Change Job]
Priority: [Normal ▼]
Delivery: ◉ As available  ○ Wait for full
```

## Panel 3: Suggestions (Right)

### Suggestion Sources (in order)

**Top 5: Companion Rules (🔗 icon)**
- Based on: selected/highlighted cart item OR last added part
- If nothing selected: random top companions from parts in cart
- Sorted by points (highest first)
- Shows: confidence %, points count, suggested qty
- Pattern text: "Usually X per Y fittings"

**Bottom 3: AI Picks (🤖 icon)**
- Uses: cart contents + last 5 searches + job type + job history
- Fills gaps companion rules haven't learned yet
- Shows AI reasoning: "copper jobs usually need hangers"
- Can use online data if internet help is ON

### When a Part in Cart is Selected
- Top 5 update to companions for THAT specific part
- Bottom 3 update to AI picks related to THAT part
- If nothing selected → suggestions based on overall cart + last added

### Suggestion Row
```
┌───────────────────────────────────┐
│ 🔗 Copper Flux Paste              │
│    Usually 1 per 20 fittings      │
│    87 pts · 92% confidence        │
│    [+ Add qty: 1]                 │
├───────────────────────────────────┤
│ 🤖 Pipe Hanger (½")              │
│    AI: "copper jobs need hangers" │
│    [+ Add qty: 6]                 │
└───────────────────────────────────┘
```

### Already-in-Cart Indicator
If a suggested part is already in the cart → show ✅ "Already in cart" instead of [+ Add]

### Confirm Quantity Dialog
When user taps [+ Add qty: X]:
```
┌─ Add Copper Crimp Ring? ────────────────┐
│  🔗 Companion suggestion                │
│  "Usually 20 per 20 copper fittings"     │
│  Quantity:  [−]  [20]  [+]              │
│  Shop stock: 35  (🟢 In stock)          │
│  [Cancel]              [Add to Cart]     │
└──────────────────────────────────────────┘
```

## Feedback Loop — Training Companion Rules

Every user interaction feeds back into the companion rules system:

| Action | Effect on Companion Rules |
|--------|--------------------------|
| Part added from suggestion | +1 point to that combo |
| Suggested qty accepted as-is | Reinforces the ratio |
| Suggested qty adjusted UP | Ratio learns higher |
| Suggested qty adjusted DOWN | Ratio learns lower |
| Suggestion ignored (never added) | No change (neutral) |
| AI pick accepted by user | Creates a new candidate for companion rules (starts earning points) |

Over time, popular AI picks earn enough points to become full companion rules — the system evolves from AI suggestions into data-backed rules automatically.

## Submission Flow

1. User taps [Submit Order Request]
2. System creates a NEW JPO tied to the selected job
3. All cart items become JPO line items
4. Smart routing runs on each line (27B):
   - In stock → auto-transfer (no approval)
   - Not in stock → pending approval
5. JPO appears in JPO list for office/manager review
6. Companion rules get points from all accepted suggestions

## Auto-Fill from Clock

- If user is clocked in → job auto-filled, shown at top
- If at shop → asks to pick a job
- If at different job site → verify prompt: "You're clocked in at Job #412. Creating order for this job?"

## Issues in Current IOSUnifiedOrderPage (to be replaced)

1. Creates empty JPO (no parts in cart)
2. No search/scan for adding parts
3. No stock indicators
4. No suggestions
5. No delivery options
6. Platform guard
7. `loadError` never displayed
8. `print()` errors
9. Single-purpose — should be the FULL order-building experience

## Prompt Chain

| Prompt | What | Status |
|--------|------|--------|
| 30A | JPO Creation: 3-panel layout, job auto-fill, delivery options, cart with stock indicators | Done |
| 30B | JPO Creation: Smart search with AI context (cart + last 5 searches), QR scan, ⚡ best match | Done |
| 30C | JPO Creation: Suggestions panel — companion rules (5) + AI picks (3), context switching on selection | Done |
| 30D | JPO Creation: Feedback loop — qty confirm dialog, companion points, ratio learning, AI→rule promotion | Done |
| 30E | JPO Creation: Submit flow — create JPO + line items, smart routing, replace IOSUnifiedOrderPage | Done |
