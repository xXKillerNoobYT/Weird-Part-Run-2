# Fix Prompt PE-001: Tool Page Naming — "Tool Registry" → "All Tools", "Tool Admin" → "Management"

> **BEFORE DOING ANYTHING:** Read `xcode-ai/xcode.md` and follow every instruction in it.

---

## The Problem (User Perspective)

Two tool pages have names that don't match the rest of the app's naming conventions:

- **"Tool Registry"** is called a "Registry" but every other list page uses plain English ("All Tools" would match "All Parts", "All Jobs", etc.)
- **"Tool Admin"** uses the word "Admin" but every other management/configuration page uses "Management" (e.g., "Warehouse Management", "People Management")

These names were left from early development. This fix brings them in line with the rest of the app.

**PE Tracker:** PE-001

---

## Files To Fix

### 1. `Weird Parts IOS/Weird Parts IOS/Features/Tools/IOSToolRegistryPage.swift`

Change all user-visible references from "Tool Registry" to "All Tools":

| Line | Find | Replace |
|------|------|---------|
| `.navigationTitle("Tool Registry")` | `"Tool Registry"` | `"All Tools"` |
| `title: "Tool Registry Help"` | `"Tool Registry Help"` | `"All Tools Help"` |
| Any help body text that says "The Tool Registry is..." | `"The Tool Registry is"` | `"All Tools is"` |
| AI context string: `"Tool Registry: \(tools.count) tools..."` | `"Tool Registry:"` | `"All Tools:"` |

**Do NOT rename the Swift struct `IOSToolRegistryPage` — only change displayed text strings.**

### 2. `Weird Parts IOS/Weird Parts IOS/Features/Tools/IOSToolAdminPage.swift`

Change all user-visible references from "Tool Admin" to "Management":

| Line | Find | Replace |
|------|------|---------|
| `.navigationTitle("Tool Admin")` | `"Tool Admin"` | `"Management"` |
| `title: "Tool Admin Help"` | `"Tool Admin Help"` | `"Management Help"` |
| Any help body text that says "Tool Admin is..." | `"Tool Admin is"` | `"Management is"` |

**Do NOT rename the Swift struct `IOSToolAdminPage` — only change displayed text strings.**

### 3. `Weird Parts IOS/Weird Parts IOS/Features/Tools/IOSToolCheckoutsPage.swift`

Update the inline help text that mentions "Tool Registry" by name:

| Find | Replace |
|------|---------|
| `"jump to the Tool Registry to see"` | `"jump to All Tools to see"` |

### 4. `Weird Parts IOS/Weird Parts IOS/Shared/HelpContentRegistry.swift`

Update the help entry registered under the tools-registry key:

| Find | Replace |
|------|---------|
| `title: "Tool Registry Help"` | `title: "All Tools Help"` |
| `"The Tool Registry is the master inventory"` | `"All Tools is the master inventory"` |

---

## What NOT to Change

- Do NOT rename Swift struct names: `IOSToolRegistryPage`, `IOSToolAdminPage`
- Do NOT change route strings: `"tools-registry"`, `"tools-admin"` (these are navigation identifiers used in router code)
- Do NOT change file names
- Do NOT change any functionality — this is purely a text/display rename

---

## After Making Changes

Verify the app builds cleanly (`swift build`). No logic changes were made so no tests need updating.

---

## Context

This aligns with PE-001 in `docs/dev-pipeline.md` (plan-enforcer finding: naming drift between tool pages and the rest of the app). The rename is cosmetic only.
