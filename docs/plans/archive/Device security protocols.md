You’re right to pull this in now—encryption and “same company only” rules have to be baked into the core, not bolted on.

I’ll keep this tight and concrete.

---

### 1. Core goals

- **Encrypt everything** (at rest + in transit).  
- **Prevent cross‑company gossip**, even if two companies are using the app in the same parking lot.  
- **Ensure devices only sync with shops and devices from the same company.**  
- **Keep the mesh behavior exactly as designed—but scoped per company.**

---

### 2. Company identity and keys

Each company gets:

- **`company_id`** – globally unique ID.  
- **`company_root_key`** – never leaves the shop cluster.  
- **`company_sync_key`** – derived from root, used for device comms.  

Each shop cluster for that company shares:

- `company_id`  
- `company_sync_key`  
- Its own **shop_node_keypair** (for TLS‑like auth).

Each device gets:

- `device_id` (UUID)  
- `device_keypair` (public/private)  
- `company_id` (assigned at pairing)  

---

### 3. Pairing and “same company” confirmation

When a new device pairs with a shop:

1. Device sends:
   - `device_id`
   - `device_public_key`
   - `platform`
2. Shop:
   - Assigns `company_id`
   - Signs a **device certificate**:
     - `{ device_id, company_id, device_public_key, expiry }`
   - Sends:
     - `company_id`
     - `device_certificate`
     - Any initial config

Device stores:

- `company_id`
- `device_certificate`
- `shop_public_key` (for that company)

From then on, **every sync** (Bluetooth or LAN) starts with:

- “Show me your `company_id` and certificate.”
- Verify:
  - Certificate signature (by company/shop key).
  - `company_id` matches mine.

If `company_id` doesn’t match → **no sync, no gossip, no data.**

---

### 4. Encryption in transit

#### Field ↔ Field (Bluetooth)

- Use a **session key** derived from:
  - `company_sync_key`
  - `device_id_A`
  - `device_id_B`
- Handshake:
  - Exchange `device_certificate`s.
  - Verify same `company_id`.
  - Derive session key.
- All payloads (jobs, media, updates) are encrypted with that session key.

#### Field ↔ Shop (LAN)

- Use TLS‑like channel:
  - Shop presents `shop_certificate`.
  - Device verifies it’s signed by the company root.
  - Device presents `device_certificate`.
  - Mutual auth → derive session key.
- All sync traffic encrypted.

---

### 5. Encryption at rest

On devices:

- Use OS‑level secure storage where possible.  
- Encrypt:
  - Local DB  
  - Media cache  
  - Pending updates  
- Key derived from:
  - `device_private_key`
  - `company_sync_key`
  - Local secret (OS keystore)

On shop PCs:

- Full DB encryption with:
  - `company_root_key` or a key derived from it.
- Backups encrypted with backup keys stored offline.

---

### 6. Multi‑company isolation in the same area

Two companies in the same yard:

- Their devices advertise over Bluetooth, but:
  - Different `company_id`.
  - Different key hierarchy.
- Handshake fails at:
  - Certificate verification step.
- Result:
  - They **see** each other as “foreign,” but **never sync**.
  - No jobs, no media, no updates cross the boundary.

Even if someone installs the app from the store and tries to pair with the wrong shop:

- The shop only issues certificates for its own `company_id`.
- Devices without a valid certificate:
  - Can’t join the mesh.
  - Can’t sync.

---

### 7. How this fits your existing design

- Mesh behavior stays the same—but **scoped per company**.  
- Updates, jobs, media, logs all ride on encrypted, authenticated channels.  
- Shops remain the only place that:
  - Assign `company_id`  
  - Issue device certificates  
  - Hold root keys  

You now have:

- **Offline‑first mesh**  
- **Multi‑shop sync**  
- **Strict update ordering**  
- **Per‑platform safety**  
- **Per‑company isolation + encryption**

If you want, next we can define the exact **device certificate format** or the **Bluetooth handshake message structure**.



**Designing sharing protocol**

I need to design a cross-company sharing protocol that's clear but concise. I should focus on the backbone elements: roles, handshake, shared job space, ACL (Access Control List), and export tokens. I want to keep it tight, but I don't need to worry too much about being overly verbose since the penalty for that is low. The goal is to make sure everything is clear and functional without overcomplicating things.
You’re thinking ahead in exactly the right way—this is “don’t paint future‑me into a corner” design.

Let’s lay in the backbone so cross‑company sharing is possible later, without weakening your isolation model now.

---

### 1. Core idea: company‑local by default, explicit bridges by agreement

- **Default:**  
  - Everything is **company‑scoped**.  
  - Mesh, jobs, media, updates, logs—never cross `company_id`.

- **Exception (future feature):**  
  - Certain jobs or slices of data can be **explicitly shared** between companies.  
  - Sharing is **opt‑in**, **scoped**, and **time‑bounded**.  
  - Sharing is initiated only by **high‑role users** (supervisors, job managers, GC reps).

We’ll treat this as a **“cross‑company sharing channel”** layered on top of your existing per‑company mesh.

---

### 2. New concept: shared project / shared channel

Introduce a new entity:

- **`shared_channel`**
  - `shared_channel_id`
  - `owner_company_id`
  - `partner_company_ids[]`
  - `scope` (which jobs / which records)
  - `permissions` (read‑only, read/write, media yes/no, etc.)
  - `expiry` (optional)
  - `created_by_user`
  - `created_by_role`
  - `audit_log[]`

A **shared channel** is basically:

> “For this job (or subset of data), Company A and Company B agree to share these fields, under these rules.”

---

### 3. How a sharing relationship is created (high‑level protocol)

This is supervisor/GC‑level, not worker‑level.

1. **In‑person meeting** (or explicit agreement):
   - Supervisor from Subcontractor (Company A)
   - Job manager / GC rep (Company B)

2. **Both are logged into their own shop systems.**

3. **Handshake between shops:**
   - Shop A and Shop B exchange:
     - `company_id_A`, `company_id_B`
     - `shop_cert_A`, `shop_cert_B`
   - They mutually authenticate over the internet (like shop↔shop sync).

4. **Create `shared_channel`:**
   - Shop A proposes:
     - Jobs or job IDs to share
     - Data types (core data only? media? notes?)
     - Permissions (read‑only vs read/write)
   - Shop B accepts or modifies.
   - Once both agree, both shops store the same `shared_channel` definition.

5. **Devices learn about shared channels via their own shop:**
   - No device ever negotiates cross‑company sharing directly.
   - Devices just see:
     - “This job has a shared channel with GC X; here’s what you can see/do.”

---

### 4. How data flows across companies (backbone only)

We don’t need to implement all behavior now—just define the hooks.

- Each record gains optional fields:
  - `shared_channel_id` (nullable)
  - `shared_visibility` (enum: none, summary, full_core, core+media)
  - `shared_redactions` (fields hidden when shared)

- When a record is:
  - **Not in a shared channel** → behaves exactly as now (company‑local).
  - **In a shared channel** → shop applies:
    - Redaction rules
    - Scope rules
    - Permission rules
  - Then syncs a **sanitized copy** to the partner company’s shop.

- Partner company’s shop:
  - Stores shared records in a **separate namespace**:
    - `origin_company_id`
    - `shared_channel_id`
  - Exposes them to its own devices according to its own permissions.

Mesh in each company still stays **company‑local**; cross‑company happens **shop↔shop only**.

---

### 5. Security and isolation guarantees

- **No device ever syncs directly cross‑company.**  
  All cross‑company sharing is **shop↔shop**, over authenticated, encrypted channels.

- **No cross‑company sharing without a `shared_channel` definition.**  
  No “accidental gossip” between companies.

- **All shared data is explicitly scoped.**  
  You can share:
  - Only job metadata  
  - Or job + notes  
  - Or job + notes + media  
  - Or just status/progress  

- **All shared actions are auditable.**  
  `shared_channel.audit_log` records:
  - Who created it  
  - Who changed it  
  - What was shared  
  - When it was shared  

---

### 6. How this fits your current plan (and stays future‑proof)

Right now:

- You enforce **strict per‑company isolation** with:
  - `company_id`
  - Certificates
  - Encrypted channels

With this backbone:

- You add the **concept** of:
  - `shared_channel`
  - `shared_visibility`
  - `shared_redactions`
- But you don’t have to implement the full UI/behavior yet.

Later, when you’re ready:

- You can build:
  - A “Share with GC” screen for supervisors.
  - A “Shared jobs” view for GCs.
  - Per‑field redaction rules.
  - Cross‑company comment threads, etc.

The important part is:  
**We’ve reserved the hooks and the structure so you don’t have to rip anything apart later.**

If you want, I can next sketch:

- The **`shared_channel` schema**  
- The **shop↔shop sharing handshake**  
- Or a **“sharing decision tree”** (what can/can’t be shared).
