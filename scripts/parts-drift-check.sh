#!/usr/bin/env bash
# parts-drift-check.sh — Quick plan-vs-code drift scan for Parts area.
# Used by AUTO GO C1b check. Runs deterministic grep-based checks and
# outputs a YAML-ish report to stdout (or file if --out is given).
#
# Usage:
#   scripts/parts-drift-check.sh            # print to stdout
#   scripts/parts-drift-check.sh --out .tmp/drift-report.yaml

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

OUT="/dev/stdout"
if [[ "${1:-}" == "--out" && -n "${2:-}" ]]; then
  mkdir -p "$(dirname "$2")"
  OUT="$2"
fi

# ── plan files ──────────────────────────────────────────────
PLAN_AUDIT="docs/plans/parts-section-audit-fix-plan.md"
PLAN_COLORS="docs/plans/colors-parts-redesign.md"
PLAN_FORECAST="docs/plans/forecasting-page-redesign.md"
PLAN_INVENTORY="docs/plans/inventory-intelligence-system.md"

# ── code locations ──────────────────────────────────────────
PARTS_SERVICE="core/Sources/WiredPartCore/Services/PartsService.swift"
WISHLIST_SERVICE="core/Sources/WiredPartCore/Services/WishlistService.swift"
ORDERS_SERVICE="core/Sources/WiredPartCore/Services/OrdersService.swift"
MIGRATIONS="core/Sources/WiredPartCore/Database/AppDatabase+Migrations.swift"
PARTS_UI="Weird Parts IOS/Weird Parts IOS/Features/Parts"

# ── helpers ─────────────────────────────────────────────────
has_func() {
  # $1 = file, $2 = function name (partial match OK)
  grep -q "func $2" "$1" 2>/dev/null
}

has_table() {
  # $1 = table name
  grep -q "\"$1\"" "$MIGRATIONS" 2>/dev/null || grep -q "'$1'" "$MIGRATIONS" 2>/dev/null
}

has_column() {
  # $1 = column name in migrations
  grep -q "$1" "$MIGRATIONS" 2>/dev/null
}

has_file() {
  # $1 = filename (basename)
  find "$PARTS_UI" -name "$1" -type f 2>/dev/null | grep -q .
}

report_missing() {
  # $1=item, $2=plan, $3=expected_location, $4=severity
  echo "    - item: \"$1\""
  echo "      plan_file: \"$2\""
  echo "      expected_location: \"$3\""
  echo "      severity: \"$4\""
}

# ── begin report ────────────────────────────────────────────
{
echo "drift_report:"
echo "  generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "  plan_files_checked:"
echo "    - $PLAN_AUDIT"
echo "    - $PLAN_COLORS"
echo "    - $PLAN_FORECAST"
echo "    - $PLAN_INVENTORY"
echo ""

MISSING=0
FOUND=0

echo "  planned_but_not_coded:"

# ── colors-parts-redesign.md Phase 2 items (#237-#240) ─────
# These are known-pending Phase 2 UI items

if ! has_table "color_brand_skus"; then
  report_missing "color_brand_skus table" "$PLAN_COLORS" "$MIGRATIONS" "high"
  ((MISSING++))
else
  ((FOUND++))
fi

if ! has_table "variant_substitutes"; then
  report_missing "variant_substitutes table" "$PLAN_COLORS" "$MIGRATIONS" "medium"
  ((MISSING++))
else
  ((FOUND++))
fi

if ! has_func "$PARTS_SERVICE" "searchParts"; then
  report_missing "searchParts() — 3-layer union search" "$PLAN_COLORS" "$PARTS_SERVICE" "high"
  ((MISSING++))
else
  ((FOUND++))
fi

if ! has_func "$ORDERS_SERVICE" "resolveGeneralLineItem"; then
  report_missing "resolveGeneralLineItem() — auto-resolve brand for general mode" "$PLAN_COLORS" "$ORDERS_SERVICE" "medium"
  ((MISSING++))
else
  ((FOUND++))
fi

if ! has_column "brand_selection_mode"; then
  report_missing "brand_selection_mode column on jpo/po line items" "$PLAN_COLORS" "$MIGRATIONS" "medium"
  ((MISSING++))
else
  ((FOUND++))
fi

# ── forecasting items ──────────────────────────────────────
for func in listForecastDataWithStock recalculateForecastsPerLocation \
            getForecastSettings saveForecastSettings \
            getFreeSpaceRating setFreeSpaceRating \
            generateDailyRecommendation approveRecommendation dismissRecommendation \
            listPendingRecommendations pendingRecommendationCount; do
  if ! has_func "$PARTS_SERVICE" "$func"; then
    report_missing "$func()" "$PLAN_FORECAST" "$PARTS_SERVICE" "high"
    ((MISSING++))
  else
    ((FOUND++))
  fi
done

if ! has_file "ForecastSettingsSheet.swift"; then
  report_missing "ForecastSettingsSheet.swift" "$PLAN_FORECAST" "$PARTS_UI" "high"
  ((MISSING++))
else
  ((FOUND++))
fi

# ── inventory-intelligence items ───────────────────────────
if ! has_table "location_stock_targets"; then
  report_missing "location_stock_targets table" "$PLAN_INVENTORY" "$MIGRATIONS" "high"
  ((MISSING++))
else
  ((FOUND++))
fi

if ! has_table "forecast_settings"; then
  report_missing "forecast_settings table" "$PLAN_INVENTORY" "$MIGRATIONS" "high"
  ((MISSING++))
else
  ((FOUND++))
fi

if ! has_table "location_free_space"; then
  report_missing "location_free_space table" "$PLAN_INVENTORY" "$MIGRATIONS" "medium"
  ((MISSING++))
else
  ((FOUND++))
fi

if ! has_table "target_recommendations"; then
  report_missing "target_recommendations table" "$PLAN_INVENTORY" "$MIGRATIONS" "high"
  ((MISSING++))
else
  ((FOUND++))
fi

if ! has_table "wishlist_items"; then
  report_missing "wishlist_items table" "$PLAN_INVENTORY" "$MIGRATIONS" "high"
  ((MISSING++))
else
  ((FOUND++))
fi

# Wishlist service methods
for func in listItems getItem approveItem dismissItem sendToProcurement \
            reopenItem getSectionedItems; do
  if ! has_func "$WISHLIST_SERVICE" "$func"; then
    report_missing "WishlistService.$func()" "$PLAN_INVENTORY" "$WISHLIST_SERVICE" "high"
    ((MISSING++))
  else
    ((FOUND++))
  fi
done

# UI pages
for page in IOSWishlistPage.swift IOSInventoryGridPage.swift; do
  if ! find "Weird Parts IOS" -name "$page" -type f 2>/dev/null | grep -q .; then
    report_missing "$page" "$PLAN_INVENTORY" "Weird Parts IOS/" "high"
    ((MISSING++))
  else
    ((FOUND++))
  fi
done

# ── parts-audit items ──────────────────────────────────────
for func in listLocationStockTargets getLocationStockTarget setLocationStockTarget; do
  if ! has_func "$PARTS_SERVICE" "$func"; then
    report_missing "$func()" "$PLAN_AUDIT" "$PARTS_SERVICE" "high"
    ((MISSING++))
  else
    ((FOUND++))
  fi
done

# Check for PricingOverrideFlow wiring in CategoriesTreeView
if ! grep -q "PricingOverrideFlow" "$PARTS_UI/CategoriesTreeView.swift" 2>/dev/null; then
  report_missing "PricingOverrideFlow entry point in CategoriesTreeView" "$PLAN_AUDIT" "$PARTS_UI/CategoriesTreeView.swift" "medium"
  ((MISSING++))
else
  ((FOUND++))
fi

if [[ $MISSING -eq 0 ]]; then
  echo "    [] # no drift detected"
fi

echo ""

# ── coded but not planned (heuristic) ──────────────────────
echo "  coded_but_not_planned:"

UNPLANNED=0

# Baseline: CRUD + domains from completed earlier phases — exclude from drift noise
# Hierarchy CRUD (Phase 2), Pricing (Phase 5/7D), Companions (Phase 3.5),
# Import/Export (Phase 2), Supplier scoring (Phase 5), Cost layers (Phase 7D),
# Traceability (Phase 7D), Polls (Phase 3.5), Scheduled deletions (Phase 3.5)
BASELINE_RE="^(list|create|update|delete|get|link|unlink|upsert|find|set|remove|add|log|check|schedule|approve|cancel|calculate|recalculate|cast|close|admin|run|record|export|import|build|trace|purge|reset|mark)(Categor|Style|Type|Color|Brand|Supplier|Part[^s]|TypeBrand|TypeColor|Cost|Price|Pricing|Companion|Rule|Poll|Vote|Import|Export|Catalog|Inventory|Co.?Occur|Sandbox|Feedback|Contact|WeeklyPoll|SKU|Stock|Shelf|Training|ActiveUser|JobPart|NextLevel)"

while IFS= read -r line; do
  func_name=$(echo "$line" | sed 's/.*func \([a-zA-Z_]*\).*/\1/')

  # Skip baseline CRUD — these are foundational and predate the plans
  if echo "$func_name" | grep -qE "$BASELINE_RE"; then
    continue
  fi

  # Check if mentioned in any plan file
  mentioned=false
  for plan in "$PLAN_AUDIT" "$PLAN_COLORS" "$PLAN_FORECAST" "$PLAN_INVENTORY"; do
    if grep -qi "$func_name" "$plan" 2>/dev/null; then
      mentioned=true
      break
    fi
  done
  if ! $mentioned; then
    line_num=$(grep -n "func $func_name" "$PARTS_SERVICE" 2>/dev/null | head -1 | cut -d: -f1)
    echo "    - item: \"$func_name\""
    echo "      location: \"$PARTS_SERVICE:${line_num:-?}\""
    ((UNPLANNED++))
  fi
done < <(grep "public func " "$PARTS_SERVICE" 2>/dev/null)

if [[ $UNPLANNED -eq 0 ]]; then
  echo "    [] # all public methods have plan references"
fi

echo ""
echo "  summary:"
echo "    total_checked: $((FOUND + MISSING))"
echo "    implemented: $FOUND"
echo "    missing: $MISSING"
echo "    unplanned_code_samples: $UNPLANNED"
echo "    drift_percentage: $(( MISSING * 100 / (FOUND + MISSING + 1) ))%"

} > "$OUT"

if [[ "$OUT" != "/dev/stdout" ]]; then
  echo "Drift report written to $OUT"
  echo "Missing: $MISSING | Implemented: $FOUND | Unplanned samples: $UNPLANNED"
fi
