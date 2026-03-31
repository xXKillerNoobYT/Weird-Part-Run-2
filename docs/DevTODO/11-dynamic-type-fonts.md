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

## AI REPORT

Build succeeded. Here's the summary of all changes across 47 files (88 instances → 83 converted, 5 intentionally skipped):

Semantic text style replacements (38 instances across 24 files):
| Original | Replacement | Count |
|---|---|---|
| .font(.system(size: 7, weight: .bold)) | .font(.caption2).bold() | 1 |
| .font(.system(size: 7)) | .font(.caption2) | 2 |
| .font(.system(size: 8, weight: .bold)) | .font(.caption2).bold() | 1 |
| .font(.system(size: 8)) | .font(.caption2) | 6 |
| .font(.system(size: 9, weight: .bold)) | .font(.caption).bold() | 3 |
| .font(.system(size: 9)) | .font(.caption) | 11 |
| .font(.system(size: 9, design: .monospaced)) | .font(.system(.caption, design: .monospaced)) | 1 |
| .font(.system(size: 9, weight: dynamic)) | .font(.caption).font​Weight(...) | 1 |
| .font(.system(size: 10, weight: .bold)) | .font(.caption).bold() | 1 |
| .font(.system(size: 10)) | .font(.caption) | 1 |
| .font(.system(size: 11, weight: .bold)) | .font(.footnote).bold() | 1 |
| .font(.system(size: 11, weight: .semibold, design: .rounded)) | .font(.system(.footnote, design: .rounded, weight: .semibold)) | 1 |
| .font(.system(size: 14)) | .font(.subheadline) | 1 |
| .font(.system(size: 15, weight: .bold, design: .rounded)) | .font(.system(.body, design: .rounded, weight: .bold)) | 1 |
| .font(.system(size: 28)) | .font(.title) | 1 |
| .font(.system(size: 32)) | .font(.large​Title) | 4 |
| .font(.system(size: 36)) | .font(.large​Title) | 1 |
| .font(.system(size: 40)) | .font(.large​Title) | 3 |
| .font(.system(size: 48, weight: .bold, design: .rounded)) | .font(.system(.large​Title, design: .rounded)).bold() | 2 |

Decorative icons → @ScaledMetric via new .decorativeIconFont() modifier (45 instances across 31 files):
| Size | Count |
|---|---|
| 48pt | 28 |
| 56pt | 6 |
| 60pt | 1 |
| 64pt | 5 |
| 72pt | 4 |
| 80pt | 1 |

New utility added: Decorative​Icon​Font​Modifier in Typography.swift􀰓 — wraps @​Scaled​Metric(relative​To: .large​Title) internally so every decorative icon scales with Dynamic Type.

Intentionally skipped (5):
• Typography.swift comment + modifier implementation
• EmptyStateView/ErrorStateView — already use dynamic icon​Size parameter
• JobStageProgressBar — dynamic ternary compact ? 6 : 10