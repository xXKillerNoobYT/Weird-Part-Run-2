# Devices → "Add MCP" — Agent Link (design)

> Owner request 2026-07-31 (chat, P2 after the pairing fix): *"On the Device
> Page I want an Add MCP tool to your system/Agent that will make it easy to
> Link the App to agents Like hermes and to you like Claude code and so on for
> managing the system"* — i.e. "MCP tool app integration and setup linking
> using the local system."
>
> Status: DECIDED 2026-08-01 — owner answered the decision list (log below);
> implementation is a go under the recorded decisions (design-first rule). References the
> master plan (`docs/implementation-plan.md`) and the current native-iOS
> architecture (CLAUDE.md). Related area: Devices page (Phase 16 Admin Hub
> territory). This v1 is separate from Multipeer/LAN sync.

## What this is

Let local AI agents on the same Mac — Claude Code, ChatGPT desktop, hermes,
and Paperclip agents — work with WiredPart data through the **Model Context
Protocol**. The Mac Catalyst app becomes an MCP *server*; agents are MCP
*clients*. The server accepts only loopback connections, so this is a
same-machine integration rather than device pairing or LAN discovery.

**Why app-as-server (not app-as-client):** the owner's phrasing is agents
"managing the system" — agents initiate, the app answers. This also matches
the security posture: the app never reaches out; it only answers
authenticated local callers.

## User story

The owner runs Claude Code / hermes on the Mac that runs WiredPart. In the Mac
Catalyst Devices page they tap **Add Agent Link**, name it ("Claude Code — shop
Mac"), choose the approved Read + notes scope, and get a one-time bearer token
plus a copyable JSON snippet. Pasting the snippet into the agent's MCP config
(`claude mcp add …` / hermes config) links it. The Devices page lists linked
agents with last-seen times and a revoke button. From then on, "ask WiredPart
how many 20A breakers are in stock" works locally and offline.

## Architecture

- **Transport:** MCP Streamable HTTP served strictly on loopback
  (`127.0.0.1:8471`). There is no LAN bind, device-IP configuration, Bonjour
  advertisement, or `NSBonjourServices` change in v1. The endpoint is
  `http://127.0.0.1:8471/mcp`.
- **Server location:** `WiredPartCore` service (`AgentLinkService`) reusing
  shared HTTP primitives where they do not carry LAN behavior. It runs only
  in the Mac Catalyst build, while enabled in Settings and with at least one
  link; iPhone and iPad do not expose this service in v1.
- **Auth:** per-agent bearer token minted at link time from at least 128 bits
  of CSPRNG-generated opaque bytes (256 bits preferred), base64url-encoded for
  the config snippet. This is deliberately separate from the 8-character
  human pairing-code format in `SyncCrypto`: never derive, normalize, or reuse
  a pairing code as a bearer credential. Store only a SHA-256 token digest and
  compare candidate digests in constant time. Every request must bear a valid
  token; unlinked = 401; revoked immediately.
- **Audit:** `agent_link_calls` table (soft-delete exempt, append-only):
  agent id, tool, argument digest, timestamp, result status. Surfaced on the
  Devices page per agent ("last seen", call count).

## Tool surface

**v1 — approved reads plus one append-only write:**
| Tool | Returns |
|---|---|
| `parts_search` | parts by name/number/category with stock levels |
| `stock_levels` | current stock for part/location filters |
| `jobs_list` | active jobs with stage, crew, schedule |
| `job_detail` | one job: materials, labor summary, notes |
| `orders_status` | open JPOs/POs and receiving state |
| `reports_summary` | pre-billing/labor/spending headline numbers |
| `system_health` | app version, DB schema version, sync status, device role |
| `job_note_append` | append-only job note attributed to the agent link; no edit/delete |

**Future scoped writes (each needs an owner decision):** create
wishlist/procurement request or create todo. Never in v1: deletes,
money-touching mutations, permission changes.

**Phase 3 — eventing:** MCP resource subscriptions for push ("notify the
agent when a PO is received").

## Devices page UX

New Mac-Catalyst-only section **Linked Agents**:
- `Add Agent Link` → sheet: name, approved Read + notes scope, generate →
  copyable config snippet + one-time display of the token (never shown again;
  matches Apple key UX).
- Config snippet shape (what the owner pastes on the Mac):
  ```json
  { "mcpServers": { "wiredpart-shop": {
      "type": "http", "url": "http://127.0.0.1:8471/mcp",
      "headers": { "Authorization": "Bearer <token>" } } } }
  ```
- Row per link: name, scope badge, last-seen, call count → detail with audit
  trail and **Revoke**.
- Empty/off states explain the Mac-only loopback constraint ("Agents must run
  on this Mac").

## Security posture (electricians-first = owner's data stays local)

Loopback-only; CSPRNG bearer per agent; SHA-256 digest at rest; constant-time
verification; revocation immediate;
approved append-only job notes; audit every call; rate-limit per token; server
off unless explicitly enabled; no cloud relay ever. Threat model note: another
local process holding the token has the granted scope, so the config snippet
is a secret and UX must say so ("treat this like a key").

## Acceptance criteria (Phase 1)

1. Devices page can create, list, and revoke agent links with scope badges.
2. A real `claude mcp add` against the snippet lists the 8 approved tools and
   answers `parts_search` correctly on local device data.
3. Requests without/with-revoked tokens: 401, audited.
4. Server rejects every non-loopback interface; it is unreachable from other
   LAN hosts.
5. All calls appear in the per-agent audit trail.
6. Unit tests prove a CSPRNG token has at least 128 bits of entropy, only its
   SHA-256 digest is stored, verification is constant-time, and revocation
   fails closed; also cover tool responses and the link-sheet UI smoke.
   Red-proof each guard (STEP 5.2 rule).

## Owner decisions — ANSWERED 2026-08-01 (chat)

1. **Scope** — *Read + append job note.* v1 ships the 7 read tools plus ONE
   write, `job_note_append` (append-only, attributed to the agent link, no
   edit/delete of anything).
2. **Port** — 8471 accepted (no objection raised).
3. **Which device runs it** — **Macs only**: *"Mac's Only this is meant to
   tie in with Claude or GPT on the desktop app."* The consumer is an AI
   desktop app (Claude Desktop / ChatGPT desktop) on the same Mac, so the
   server **binds to 127.0.0.1 only** — same-machine access, not LAN. v1 has
   no Bonjour advert, no `NSBonjourServices` change, and no LAN exposure. The Devices-page
   section renders only in the Mac (Catalyst) build. LAN serving, Bonjour
   discovery, and phone/iPad serving move to a future phase gated on a new
   owner decision.
4. **Tool list v1** — the 7 read tools accepted, plus `job_note_append` per
   decision 1.
5. **Naming** — **"Agent Link (MCP)"** (owner: "Agent Link/MCP").

### v1 architecture deltas from the decisions

- Bind strictly to loopback (`127.0.0.1:8471`); refuse other interfaces.
  The config snippet uses `http://127.0.0.1:8471/mcp`.
- Bearer tokens stay (they gate *other local processes*, not just LAN peers).
  Mint an independent CSPRNG opaque token (minimum 128 bits; 256 bits
  preferred), display it once, SHA-256-digest it at rest, compare digests in
  constant time, and revoke immediately. Do not reuse the human pairing-code
  family.
- Audit trail unchanged.
- Acceptance criterion 4 becomes: server unreachable from any non-loopback
  interface (and from other LAN hosts).

## AMENDED 2026-08-06 (chat) — identity model supersedes the scope *mechanism*

Verbatim:

> "for the MCP i think we should have it treadted like a AGENT user and then can
> pick the hat with permicions for the mcp like you for exsample by hat"

> "Agent users limited to 2 per a user and the users hats permission"

**The decision:** an MCP consumer is **not** a bespoke token with its own scope
vocabulary. It is a first-class **agent user** — a user record of type `agent` —
that **wears a hat**, exactly like a human user does. Its permissions *are* the
hat's permissions. There is no second permission system to design, maintain, or
get out of sync.

Rules that follow directly:

1. **Type.** `agent` joins the existing user types. It authenticates by token
   rather than by login, but it is a user everywhere else — People lists, audit
   trails, `created_by` / `updated_by` attribution.
2. **Permissions come from the hat.** Picking the hat *is* picking the scope.
   Changing the hat re-scopes the agent immediately; revoking the hat revokes
   the access.
3. **Cap: 2 agent users per human user.** Enforced at creation with a clear
   message, not a silent failure.
4. **Ceiling: the owning user's own hat permissions.** An agent user can never
   exceed the human who created it — if that human is later demoted, the agent
   is re-bounded too. An agent is a *delegation* of the creator's authority,
   never an escalation of it.
5. **Attribution stays honest.** Agent actions are written as the agent user,
   never laundered through the human's id. This is the existing hardcoded-user-id
   anti-pattern in a new costume; the real actor gets recorded.

### Exactly what this changes, and what it does not

| From 2026-08-01 | Status after 2026-08-06 |
|---|---|
| Decision 1 — *scope picker* ("Read-only \| Read + notes" as a sheet choice) | **SUPERSEDED.** There is no scope picker. The agent user wears a hat and the hat decides. |
| Decision 1/4 — the **8-tool surface** (7 reads + `job_note_append`) | **STANDS.** These are the tools that exist. Whether a given agent may call `job_note_append` is now a hat question, not a separate scope flag. |
| Decision 2 — port **8471** | **STANDS.** |
| Decision 3 — **Macs only, loopback `127.0.0.1`** | **STANDS.** |
| Decision 5 — naming **"Agent Link (MCP)"** | **STANDS.** |

The Devices-page sheet therefore replaces its scope picker with a **hat picker**,
and the "scope badge" on each row becomes the hat's name.

**Bearer tokens still exist** and are unchanged (CSPRNG, SHA-256 digest at rest,
constant-time compare, revoke immediately). The token answers *"which agent user
is calling?"*; the hat answers *"what may that user do?"*. Do not collapse the
two — authentication and authorization stay separate.

Design consequence worth flagging at build time: rule 4 needs a re-evaluation
hook. If the creator's hat changes, every agent user under them must be
re-bounded in the same transaction, or a demoted user leaves behind an agent
still holding the old authority.

**Status: MCP is a FUTURE feature** (owner 2026-08-06: *"MCP is future plan, add
as a feature GitHub issue"*). Tracked on #1573; no implementation is scheduled.


## Cross-references

- Token and audit implementation: new `AgentLinkService`; do not reuse
  `PeerDiscovery.swift`, LAN sync listeners, or `NSBonjourServices`.
- Related field bug informing UX copy: #1580 (transport truth in messaging)
- Paperclip/CI process: WEI-6655 (release-state duties; agent-facing systems
  get the same audit discipline)
