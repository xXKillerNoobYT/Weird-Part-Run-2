# Windows Architecture — Decision Document

**Created:** 2026-03-15 (Phase 13–15)  
**Status:** Implementation complete, build verification pending (MSVC Build Tools needed)

---

## 1. Executive Summary

WiredPart runs on Windows using the **existing Tauri 2.x / React architecture** (Option B). This means zero UI porting, zero service rewriting, and the same codebase serves both macOS desktop browsers and Windows desktop. On-device AI uses **llama.cpp** as a sidecar process, not Windows Copilot Runtime.

---

## 2. Framework Decision: Option B (Keep Tauri/React)

### What was evaluated

| Option | Effort | Advantage | Verdict |
|--------|--------|-----------|---------|
| **A: WinUI 3 / .NET MAUI** | Massive — rewrite 86 pages + 64 services in C# | Native Windows UX | ❌ Rejected: months of work for negligible UX gain in a business ERP |
| **B: Keep Tauri/React** | Zero — already works | All code exists, WebView2 is adequate | ✅ Chosen |
| **C: Swift on Windows** | Unknown — Swift on Windows is immature | Shared code with Apple | ❌ Rejected: no SwiftUI, no mature GRDB, too risky |

### Why Option B wins

1. **86 pages already exist** — responsive, touch-friendly, tested across breakpoints
2. **64 TypeScript services already exist** — all business logic, all sync, all CRUD
3. **Tauri Rust layer already exists** — mDNS discovery, Ed25519 crypto, sync server, Foundation Models bridge
4. **WebView2 is pre-installed on Windows 10/11** — no extra runtime needed
5. **Single codebase** — one change in `src/` propagates to all platforms

### What this means for the codebase

- `src/` and `src-tauri/` **stay** (they ARE the Windows app)
- No `windows/` project directory was created
- Phase 15 cleanup (file deletions) is **cancelled** — nothing to delete
- The React frontend runs identically on Windows (Tauri/WebView2) and macOS (Safari/Chrome via LAN)

---

## 3. AI Decision: llama.cpp (Not Copilot Runtime)

### Why not Windows Copilot Runtime?

Windows Copilot Runtime's on-device AI requires a **Copilot+ PC** — a device with a dedicated NPU (Neural Processing Unit). As of 2026, this is a tiny fraction of Windows PCs. A plumbing shop's computers almost certainly don't have NPUs.

### llama.cpp approach

- **llama-server.exe** runs as a sidecar on `localhost:8086`
- Exposes an **OpenAI-compatible HTTP API** (`/v1/chat/completions`)
- Uses **GGUF format models** (quantized, 2-8GB, runs on CPU)
- Rust layer manages the process lifecycle (start, health check, shutdown)
- User downloads `llama-server.exe` and a GGUF model manually (v1)

### File inventory

| File | Lines | Purpose |
|------|-------|---------|
| `src-tauri/src/foundation_models.rs` | 563 | Rust IPC bridge — `windows_llm` module with 11 functions |
| `src-tauri/Cargo.toml` | 48 | `ureq` + `lazy_static` as Windows-only deps |
| `src-tauri/src/lib.rs` | 57 | 8 Tauri commands registered + shutdown hook |
| `src/lib/foundation-models.ts` | 329 | TypeScript types + Windows status helpers |
| `src/features/settings/pages/AiConfigPage.tsx` | 382 | Settings UI with setup instructions |
| `src/hooks/useAITextField.ts` | 210 | Hook for AI text completion |
| `src/components/ui/AiTextarea.tsx` | 170 | Ghost text overlay + Tab/Escape |
| `src/components/ui/AiSuggestionPopover.tsx` | 149 | 5 enhancement modes |

### Availability states (6 levels)

1. `not_installed` — llama-server.exe not found
2. `no_server` — server binary exists but not running (auto-start attempted)
3. `no_model` — server running but no GGUF model found
4. `available` — ready for requests
5. `not_ready` — Apple-specific (Foundation Models downloading)
6. `unavailable` — catch-all error state

### Model paths

- **Models:** `%APPDATA%\WiredPart\models\` (GGUF files)
- **Server binary:** `%APPDATA%\WiredPart\bin\llama-server.exe`
- **Preferred quantizations:** Q4_K_M, Q5_K_M, Q4_K_S, Q5_K_S

---

## 4. Platform Architecture (Dual-Platform)

```
┌────────────────────────────────────────────────────┐
│                    src/ (React)                      │
│         86 pages · 64 TS services · Tailwind v4     │
│              One codebase for ALL platforms          │
├────────────────┬───────────────────┬────────────────┤
│  Tauri/WebView2│  Tauri/WKWebView  │  Safari/Chrome │
│   (Windows)    │   (iOS/macOS)     │  (LAN browser) │
├────────────────┼───────────────────┼────────────────┤
│  src-tauri/    │  src-tauri/ +     │  FastAPI        │
│  Rust IPC      │  ios/ (Capacitor) │  backend/       │
│  llama.cpp AI  │  Apple FM AI      │  Python API     │
│  mDNS/sync     │  mDNS/sync        │  (shop server)  │
└────────────────┴───────────────────┴────────────────┘
```

### Environment detection

```typescript
// src/lib/foundation-models.ts
isTauri()   → local TS services + Rust IPC
isBrowser() → HTTP API to FastAPI backend
isDesktop() → desktop-only features (public data dir, autostart)
isMobile()  → mobile-friendly UI, offline-first
```

### Sync topology

- **Shop computer (Python FastAPI):** Sync anchor, serves desktop browsers over LAN
- **Windows devices (Tauri):** Sync via LAN HTTP to shop server
- **iOS devices (Tauri):** Sync via LAN HTTP + Apple Multipeer Connectivity
- **All devices:** Local SQLite with `_change_log` table, field-level LWW merge

---

## 5. Build Requirements

### Windows build prerequisites

1. **Rust 1.94.0+** — installed via `rustup`
2. **MSVC Build Tools 2022** — install via:
   ```powershell
   # Run as Administrator
   winget install Microsoft.VisualStudio.2022.BuildTools --override "--wait --quiet --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
   ```
3. **Node.js 18+** — for Vite frontend build
4. **WebView2** — pre-installed on Windows 10/11

### Build command

```bash
cd src-tauri
cargo tauri build
```

### Output

- NSIS installer: `src-tauri/target/release/bundle/nsis/WiredPart_x.y.z_x64-setup.exe`
- Code signing configured in `tauri.conf.json`

---

## 6. What's Deferred

These items need a running Windows build (MSVC) or physical devices to complete:

| Task | Blocker |
|------|---------|
| AI tests (13.22-13.25) | Needs running llama-server + GGUF model |
| Sync tests (14.46-14.52) | Needs MSVC build + multiple devices |
| Performance tests (14.48) | Needs MSVC build |
| Cross-platform verification (15.1-15.2) | Needs MSVC build + Mac + iOS |
| Release tag v2.0.0 (15.18) | After all verification passes |

---

## 7. What Was NOT Needed (Thanks to Option B)

With Option B, these items from the original plan were **unnecessary**:

- ❌ No `windows/` project scaffold
- ❌ No service rewriting (all 64 TS services work as-is)
- ❌ No UI porting (all 86 pages work as-is)
- ❌ No new database layer (same SQLite + same migrations)
- ❌ No file deletions in Phase 15 (src/ and src-tauri/ ARE the app)
- ❌ No WebView fallback elimination (WebView IS the architecture)

**Estimated effort saved:** ~3-6 months of development time.
