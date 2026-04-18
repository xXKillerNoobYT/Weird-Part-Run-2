---
source: dev-improvement-scanner (2026-04-17 run 15)
severity: Medium
category: Apple HIG — Sheet Presentation
status: OPEN
github_issue: #248
---

# DIS-018: Add .presentationDetents to PageHelpSheet (highest-leverage fix)

## Problem
~170 sheet call sites app-wide have no `.presentationDetents`, defaulting to full-screen for
everything including informational overlays. `PageHelpSheet` alone covers ~80 call sites —
fixing it once propagates to all of them for free.

## Xcode AI Prompt

Paste into Xcode AI:

```
In the WiredPart iOS app, find the file: Weird Parts IOS/Shared/PageHelpSheet.swift

This is a reusable help sheet presented app-wide. Add `.presentationDetents([.medium, .large])`
and `.presentationDragIndicator(.visible)` to the root view returned by the sheet's body.

The goal: when presented as a sheet, it should default to medium height (showing help content
in a comfortable half-screen panel) while still allowing the user to drag it to full height.

Make only this change. Do not modify any call sites — the modifier should live inside
PageHelpSheet itself so all existing call sites automatically use the correct detents.
```

## Verification
- Open any page in the app that has a help button (the ? toolbar icon)
- Tap the help button
- Sheet should appear at medium height, not full-screen
- User should be able to drag it to full height
