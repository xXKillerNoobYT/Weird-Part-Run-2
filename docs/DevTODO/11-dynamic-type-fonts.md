# Replace Hardcoded Font Sizes with Dynamic Type
**GitHub Issue:** #11
**Priority:** High
**Estimated effort:** Medium (20-30 min across 24 files)

## What's Wrong
55 instances of `.font(.system(size: N))` across 24 files bypass Dynamic Type. Users who increase text size in Settings → Accessibility get no benefit. 21 instances use sizes under 10pt which are too small even at default.

## Files to Change (worst offenders first)
- `IOSChannelsPage.swift:280` — 7pt → `.font(.caption2)`
- `IOSChannelsPage.swift:300` — 9pt → `.font(.caption)`
- `IOSJobDetailTabView.swift:1125` — 8pt → `.font(.caption2)`
- `PartsCatalogPage.swift:473` — 8pt → `.font(.caption2)`
- `WarehouseLocationsPage.swift:248,273,276` — 7-9pt → `.font(.caption2)` / `.font(.caption)`
- `IOSPODetailPage.swift:1558,1560,1662,1686` — 9pt → `.font(.caption)`
- `IOSOrganizationAuditPage.swift:244,247` — 7-10pt → `.font(.caption2)` / `.font(.caption)`
- `IOSAuditPage.swift:626` — 9pt → `.font(.caption)`
- `CategoriesFormSheets.swift:495` — 9pt → `.font(.caption)`
- `TypeBrandColorSection.swift:124` — 10pt → `.font(.caption)`
- `PartsPricingPage.swift:438,518,522,1035,1039` — 8-9pt → `.font(.caption2)` / `.font(.caption)`
- Large decorative sizes (48pt, 64pt for icons) → use `@ScaledMetric` wrapper

## AI Prompt
```
Search this file for all instances of .font(.system(size: followed by a number. Replace each one with the appropriate semantic text style:

Size mapping:
- 7-8pt → .font(.caption2)
- 9-10pt → .font(.caption)
- 11-12pt → .font(.footnote)
- 13-14pt → .font(.subheadline)
- 15-16pt → .font(.body)
- 17-20pt → .font(.headline) or .font(.title3)
- 22-28pt → .font(.title2) or .font(.title)
- 32-48pt → .font(.largeTitle)
- 48-64pt (decorative icons) → keep .system(size:) but wrap in @ScaledMetric

For bold variants, chain .bold() after the text style.
Do NOT change .font(.system(size:).weight(.semibold)) patterns — convert to .font(.headline) or appropriate weighted style.
```

## How to Verify
1. Build and run the app
2. Go to Settings → Accessibility → Display & Text Size → Larger Text
3. Set text to maximum size
4. Navigate through the app — all text should scale up proportionally
5. No text should be clipped or overlapping
