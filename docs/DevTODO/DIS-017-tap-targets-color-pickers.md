---
source: dev-improvement-scanner (2026-04-17 run 15)
severity: High
category: Apple HIG — Tap Target Accessibility
status: OPEN
github_issue: #246
---

# DIS-017: Sub-44pt Tap Targets in Color Pickers and Schedule Config

## Problem
Three locations have interactive buttons smaller than Apple's 44×44pt minimum tap target:

1. `CategoriesColorPicker.swift:114,123` — color swatch Button `.frame(width: 36, height: 36)`
2. `ThemesPage.swift:48` — theme color swatch `.frame(width: 36, height: 36)`
3. `IOSScheduleConfigPage.swift:160,648` — `.frame(width: 32, height: 32)` action buttons

## Xcode AI Prompt

Paste into Xcode AI:

```
In the WiredPart iOS app, fix sub-44pt tap targets in three files to meet Apple HIG accessibility requirements:

1. File: Weird Parts IOS/Features/Parts/CategoriesColorPicker.swift
   Around lines 114 and 123: color swatch Button labels have `.frame(width: 36, height: 36)`.
   Fix: Add `.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())` after the existing frame modifier.
   Do NOT change the visual Circle/square frame size — only grow the hit area.

2. File: Weird Parts IOS/Features/Settings/ThemesPage.swift
   Around line 48: theme color swatch button has `.frame(width: 36, height: 36)`.
   Same fix: add `.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())`.

3. File: Weird Parts IOS/Features/Scheduling/IOSScheduleConfigPage.swift
   Around lines 160 and 648: action buttons have `.frame(width: 32, height: 32)`.
   Same fix: add `.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())` after the existing frame.

Make only these specific changes. Do not refactor anything else.
```

## Verification
- Open each page in Xcode Simulator
- Use Accessibility Inspector to verify tap target is at least 44×44pt
- Visual appearance should be unchanged (only hit area grows)
