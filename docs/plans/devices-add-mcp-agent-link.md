# Devices → "Add MCP" — Agent Link (design)

> Owner request 2026-07-31 (chat, P2 after the pairing fix): *"On the Device
> Page I want an Add MCP tool to your system/Agent that will make it easy to
> Link the App to agents Like hermes and to you like Claude code and so on for
> managing the system"* — i.e. "MCP tool app integration and setup linking
> using the local system."
>
> Status: DESIGN — awaiting owner answers on the decision list below before
> implementation prompts are written (design-first rule). References the
> master plan (`docs/implementation-plan.md`) and the current native-iOS
> architecture (CLAUDE.md). Related area: Devices page (Phase 16 Admin Hub
> territory), Multipeer/LAN sync plumbing (`core/Sources/WiredPartCore/Sync/`).

## What this is

Let local AI agents on the shop network — Claude Code, hermes, Paperclip
agents — connect to a WiredPart device and work with its data through the
**Model Context Protocol**. The app becomes an MCP *server*; agents are MCP
*clients*. Linking is a first-class flow on the Devices page, as easy as the
existing device pairing: generate a link, hand it to the agent, done.

**Why app-as-server (not app-as-client):** the owner's phrasing is agents
"managing the system" — agents initiate, the app answers. This also matches
the security posture: the app never reaches out; it only answers
authenticated local callers.

## User story

The owner runs Claude Code / hermes on the shop Mac. On the shop device's
Devices page they tap **Add Agent Link**, name it ("Claude Code — shop Mac"),
pick a scope, and get (a) a QR code and (b) a copyable JSON snippet. Pasting
the snippet into the agent's MCP config (`claude mcp add …` / hermes config)
links it. The Devices page lists linked agents with last-seen times and a
revoke button. From then on, "ask WiredPart how many 20A breakers are in
stock" just works, locally, offline.

## Architecture

- **Transport:** MCP Streamable HTTP served by the app on the local network
  only (bind to LAN interface; never cellular/public). Port: fixed default
  (proposal: 8471) with per-device override in Settings. Advertised via
  Bonjour `_wiredpart-mcp._tcp` (add to `NSBonjourServices` — same pattern as
  `_wiredpart._tcp` LAN sync; keep the Info.plist comment in sync).
- **Server location:** `WiredPartCore` service (`AgentLinkService`) reusing
  the existing LAN-sync HTTP server plumbing rather than a second stack —
  extend, don't duplicate (systems shrink). Runs only while enabled in
  Settings and at least one link exists.
- **Auth:** per-agent bearer token minted at link time via the existing
  pairing-code UX (`SyncCrypto.normalizedPairingCode` family). Token stored
  hashed (FNV-1a is NOT acceptable for secrets — use SHA-256 here; the
  `String.hashValue` ban applies doubly). Every request must bear a valid
  token; unlinked = 401; revoked immediately.
- **Audit:** `agent_link_calls` table (soft-delete exempt, append-only):
  agent id, tool, argument digest, timestamp, result status. Surfaced on the
  Devices page per agent ("last seen", call count).

## Tool surface

**Phase 1 — read-only (ships first):**
| Tool | Returns |
|---|---|
| `parts_search` | parts by name/number/category with stock levels |
| `stock_levels` | current stock for part/location filters |
| `jobs_list` | active jobs with stage, crew, schedule |
| `job_detail` | one job: materials, labor summary, notes |
| `orders_status` | open JPOs/POs and receiving state |
| `reports_summary` | pre-billing/labor/spending headline numbers |
| `system_health` | app version, DB schema version, sync status, device role |

**Phase 2 — scoped writes (each its own owner decision):** append job note,
create wishlist/procurement request, create todo. Never in v1: deletes,
money-touching mutations, permission changes.

**Phase 3 — eventing:** MCP resource subscriptions for push ("notify the
agent when a PO is received").

## Devices page UX

New section **Linked Agents** (below existing device pairing):
- `Add Agent Link` → sheet: name, scope picker (Read-only | Read + notes),
  generate → QR + copyable config snippet + one-time display of the token
  (never shown again; matches Apple key UX).
- Config snippet shape (what the owner pastes on the Mac):
  ```json
  { "mcpServers": { "wiredpart-shop": {
      "type": "http", "url": "http://<device-ip>:8471/mcp",
      "headers": { "Authorization": "Bearer <token>" } } } }
  ```
- Row per link: name, scope badge, last-seen, call count → detail with audit
  trail and **Revoke**.
- Empty/off states honest about LAN-only ("Agents must be on this network").

## Security posture (electricians-first = owner's data stays local)

LAN-bind only; Bearer per agent; hashed at rest; revocation immediate;
read-only default; audit every call; rate-limit per token; server off unless
explicitly enabled; no cloud relay ever. Threat model note: anyone with the
token on the LAN has the granted scope — the QR/snippet is a secret; UX must
say so ("treat this like a key").

## Acceptance criteria (Phase 1)

1. Devices page can create, list, and revoke agent links with scope badges.
2. A real `claude mcp add` against the snippet lists the 7 tools and answers
   `parts_search` correctly on device data.
3. Requests without/with-revoked tokens: 401, audited.
4. Server unreachable from a non-LAN interface.
5. All calls appear in the per-agent audit trail.
6. Bonjour advert visible only while enabled.
7. Unit tests for token mint/verify/revoke + tool responses; UI smoke for the
   link sheet. Red-proof each guard (STEP 5.2 rule).

## Owner decisions needed before build

1. **Scope default** — Read-only only in v1, or include "append job note"?
2. **Port 8471** OK, or prefer another?
3. **Which device runs it** — shop device only, or any device with the toggle?
4. **Tool list v1** — the 7 above right? Anything missing you'd ask first?
5. **Naming** — "Agent Link" vs "MCP Link" vs "AI Access" on the page?

## Cross-references

- Pairing/trust plumbing: `IOSSyncManager.pairWithShop`, `SyncCrypto`
- LAN server + Bonjour: `PeerDiscovery.swift` (`_wiredpart._tcp`), Info.plist
  `NSBonjourServices`
- Related field bug informing UX copy: #1580 (transport truth in messaging)
- Paperclip/CI process: WEI-6655 (release-state duties; agent-facing systems
  get the same audit discipline)
