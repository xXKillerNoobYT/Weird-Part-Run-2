#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fleet_file="$repo_root/Weird Parts IOS/Weird Parts IOS/Features/Fleet/IOSFleetDashboardPage.swift"
po_file="$repo_root/Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSPODetailPage.swift"
reports_file="$repo_root/Weird Parts IOS/Weird Parts IOS/Features/Reports/IOSReportsRouter.swift"
suppliers_file="$repo_root/Weird Parts IOS/Weird Parts IOS/Features/Parts/PartsSuppliersPage.swift"

grep -q 'IOSReportsRouter(tabId: "reports-hub", initialCategory: .fleet)' "$fleet_file"
grep -q 'var initialCategory: ReportCategory? = nil' "$reports_file"
grep -q 'PartsSuppliersPage(highlightSupplierId: po.supplierId)' "$po_file"
grep -q 'var highlightSupplierId: Int64? = nil' "$suppliers_file"

if perl -0ne 'exit 1 if /NavigationLink\s*\{\s*Text\("Fleet Reports"\)/' "$fleet_file"; then
  :
else
  echo "Fleet Reports still navigates to a Text placeholder" >&2
  exit 1
fi

if perl -0ne 'exit 1 if /NavigationLink\s*\{\s*Text\("Supplier Profile"\)/' "$po_file"; then
  :
else
  echo "Supplier Profile still navigates to a Text placeholder" >&2
  exit 1
fi

echo "iOS real navigation checks passed"
