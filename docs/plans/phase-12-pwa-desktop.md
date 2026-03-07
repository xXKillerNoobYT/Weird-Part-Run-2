# Phase 10: PWA & Desktop Enhancement

> **Date:** 2026-03-07
> **Status:** 📋 Outline — lower priority, partially covered by V1.0 deployment plan
> **Related:** `docs/plans/deployment-master-plan.md` (covers Capacitor + LAN architecture)
> **Dependencies:** Core app functional (Phases 1-9 ✅), Sync infrastructure (Phase 11)
> **Estimated work:** 5-8 days (when prioritized)

---

## Context

The V1.0 deployment architecture already handles the core:
- **Desktop browsers** hit the shop server over LAN (always at the shop)
- **Mobile devices** run Capacitor with local SQLite + lean TS data layer
- **Sync** happens over LAN HTTP

This phase adds **polish and progressive enhancement** — service worker for desktop offline caching, improved desktop UX, and potential native desktop packaging.

---

## Scope

### 1. Service Worker & PWA Manifest

**Goal:** Desktop browsers at the shop should still work if the shop server restarts or the network blips.

- **Service worker:** Cache the React app shell + assets. API responses cached with stale-while-revalidate.
- **PWA manifest:** `manifest.json` with app name, icons, theme color. Allows "Add to Home Screen" on shop computers.
- **Offline indicator:** When service worker detects no API connectivity, show a subtle banner: "Working offline — changes will sync when connected"
- **Cache strategy:**
  - App shell (HTML/JS/CSS): Cache-first (update in background)
  - API data: Network-first with stale fallback
  - Media/images: Cache with size limits

### 2. Desktop UX Enhancement

**Goal:** The shop computer is the primary work surface. Make it feel like a native app.

- **Keyboard shortcuts:**
  - `Ctrl+K` — Global search (parts, jobs, contacts)
  - `Ctrl+N` — New (context-dependent: new job, new order, new message)
  - `Ctrl+/` — Open command palette
  - `Esc` — Close modal/drawer
  - Arrow keys — Navigate lists and tables
  - `Enter` — Open selected item
- **Command palette:** Quick action launcher (inspired by VS Code's Ctrl+P)
  - Search for jobs, parts, contacts, pages
  - Quick actions: "Clock in Roy", "New PO for J-042", "Open chat with Mike"
- **Multi-panel layouts:** Side-by-side views on wide screens (e.g., job list + job detail)
- **Drag-and-drop:** Reorder items in kit checklists, move parts between orders
- **Table enhancements:** Column resizing, sticky headers, bulk select + actions
- **Print stylesheets:** Proper print layouts for reports, POs, timesheets

### 3. Native Desktop Wrapper (Stretch Goal)

**Goal:** Optional Electron or Tauri wrapper for shop computers that want a "real app" feel.

- **Tauri preferred** over Electron (lighter, Rust-based, smaller binary)
- **System tray icon:** Shows unread count badge, quick actions menu
- **Auto-launch:** Start with OS, minimize to tray
- **Native notifications:** OS-level notification popups for chat messages, Q&A escalations, order status changes
- **File system integration:** Drag files from desktop to upload, save exports directly to folder
- **Auto-update:** Check shop server for new versions, download and install silently

**Decision needed:** Whether to invest in Tauri wrapper vs just using PWA. PWA covers 90% of needs. Tauri adds the last 10% (tray icon, auto-launch, native notifications) but requires maintaining a separate build.

### 4. Push Notifications (Desktop + Mobile)

**Goal:** Alert users about important events without polling.

- **Desktop (PWA):** Web Push API via service worker
- **Mobile (Capacitor):** Local notifications (no cloud push server)
- **Notification categories:**
  - Chat: new message in your channels, @mention
  - Q&A: question assigned to you, answer received
  - Orders: PO approved, order received
  - Jobs: clock-in reminder, schedule change
  - Alerts: budget threshold hit, certification expiring
- **User preferences:** Per-category toggle (on/off), quiet hours, sound selection
- **Sound effects:** Distinct sounds per category (reuse Phase 7E notification sound system)

---

## Technical Approach

### Service Worker

```
frontend/public/sw.js (or generated via vite-plugin-pwa)
```

Use `vite-plugin-pwa` for automatic service worker generation:
- Precache all built assets
- Runtime caching for API routes
- Background sync for offline mutations (Workbox)

### PWA Manifest

```json
{
  "name": "Weird Parts Manager",
  "short_name": "WPM",
  "start_url": "/",
  "display": "standalone",
  "theme_color": "#1e293b",
  "background_color": "#0f172a",
  "icons": [
    { "src": "/icon-192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "/icon-512.png", "sizes": "512x512", "type": "image/png" }
  ]
}
```

### Keyboard Shortcut System

```typescript
// frontend/src/lib/shortcuts.ts
const SHORTCUTS = {
  'ctrl+k': { action: 'global-search', label: 'Search' },
  'ctrl+n': { action: 'new-item', label: 'New' },
  'ctrl+/': { action: 'command-palette', label: 'Commands' },
  'escape': { action: 'close', label: 'Close' },
};

// Register globally in App.tsx, context-dependent handlers
```

---

## Success Criteria

- [ ] PWA installs on desktop Chrome/Edge with "Add to Home Screen"
- [ ] Service worker caches app shell for offline access
- [ ] API responses use stale-while-revalidate for resilience
- [ ] Offline indicator banner shows when shop server is unreachable
- [ ] Keyboard shortcuts work for search, new, command palette, close
- [ ] Command palette searches across jobs, parts, contacts, pages
- [ ] Print stylesheets produce clean layouts for reports and POs
- [ ] Push notifications work for chat messages and Q&A assignments
- [ ] User can toggle notification preferences per category
- [ ] (Stretch) Tauri wrapper provides system tray and auto-launch

---

## Execution Order (When Prioritized)

1. Add `vite-plugin-pwa` + configure service worker + manifest
2. Implement offline indicator banner
3. Build keyboard shortcut system + command palette
4. Add print stylesheets for report pages
5. Implement local push notifications (Capacitor + Web Push)
6. Build notification preferences page
7. (Stretch) Evaluate Tauri wrapper — build proof of concept
8. Test PWA install + offline behavior on desktop Chrome, Safari, Edge

---

## Open Questions

- Tauri vs PWA-only — decide after V1.0 deployment based on user feedback
- Notification sound library — reuse Phase 7E work or expand?
- How much offline data should desktop cache? (Desktop is always at shop, less need than mobile)
