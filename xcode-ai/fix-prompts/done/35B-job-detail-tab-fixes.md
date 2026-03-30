# 35B — Job Detail Tab View: Server-Side Filtering + Error Handling

> **Chain position:** **35B** (standalone)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Context

IOSJobDetailTabView has multiple issues:
1. **5 `print()` catch blocks** — errors invisible to user (team, parts, orders, Q&A, supplier channels)
2. **Client-side filtering** — fetches ALL JPOs then filters by jobId. Same for Q&A threads. Should use service methods that filter server-side.
3. **Dead code** — `placeholderTab` function defined but never called

## Files to Modify

- `Weird Parts IOS/Weird Parts IOS/Features/Jobs/IOSJobDetailTabView.swift`

## Task

### 1. Replace all 5 print() catches with actionError state
Add `@State private var tabError: String?` and display it.

### 2. Fix client-side filtering
Replace `service.listJPOs()` → filter by jobId with a service method that takes jobId parameter.
Replace `service.listQAThreads()` → filter by jobId with a service method that takes jobId parameter.

If the service methods don't exist with jobId parameters, add them.

### 3. Remove dead code
Delete the `placeholderTab` function.

## Success Criteria

- [ ] Zero print() catches — all errors visible
- [ ] JPO and Q&A queries filter server-side by jobId
- [ ] Dead code removed
- [ ] Project builds with no errors
