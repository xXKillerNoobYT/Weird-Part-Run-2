A **manual hard‑sync** is absolutely essential in a system like yours.  
You already have a resilient mesh, ordered updates, shop authority, and multi‑shop sync — but every real‑world deployment needs a “break glass” option when a device is:

- Missing data  
- Out of sync  
- Stuck in a partial state  
- Hasn’t seen the shop in months  
- Has corrupted local caches  
- Has mismatched update chains  
- Has incomplete job/media bundles  

Let’s design a **safe, deterministic, audit‑friendly hard‑sync protocol** that fits perfectly into your architecture.

---

# 🔧 **1. What a Hard Sync Actually Means in Your System**

A hard sync is **not** a blind overwrite.  
It is a **guided, authoritative, shop‑controlled resynchronization** that guarantees:

- No data loss  
- No duplication  
- No corruption  
- No out‑of‑order updates  
- No cross‑company contamination  
- No breaking the mesh rules  

A hard sync is basically:

> “Reset this device’s local state to match the shop’s authoritative state, but keep its identity, certificates, and pending outbound data.”

---

# 🧱 **2. When a Hard Sync Should Be Used**

You want this option available when:

- Device is missing jobs it should have  
- Device has jobs it shouldn’t have  
- Device has partial media bundles  
- Device update chain is stuck  
- Device hasn’t synced in months  
- Device has corrupted local storage  
- Device is newly paired but didn’t receive everything  
- Device was offline during a major update rollout  
- Device is switching between shop locations  
- Device is switching between contractor/supplier modes  

This is the “fix it now” button.

---

# 🔄 **3. Hard Sync Protocol (Step‑By‑Step)**

Here’s the clean, safe sequence.

---

## **Step 1 — Device Requests Hard Sync**
User taps:

> **Settings → Advanced → Hard Sync (Reset & Resync)**

Device sends to shop:

- `device_id`  
- `company_id`  
- `device_certificate`  
- `current_version`  
- `pending_outbound_data` hashes  
- `reason_code` (optional)  

---

## **Step 2 — Shop Validates Identity**
Shop checks:

- Certificate signature  
- Company match  
- Device role (field, supplier, contractor)  
- Device platform  
- Device version chain  

If anything fails → shop refuses hard sync.

---

## **Step 3 — Shop Prepares a “Hard Sync Package”**
This is the authoritative snapshot for that device:

- Required jobs  
- Required job metadata  
- Required media metadata  
- Required update packages  
- Required user permissions  
- Required device preferences  
- Required shared channels (if any)  
- Required supplier/GC links (if any)  
- Required Q&A threads  
- Required RFI threads  
- Required logs  
- Required schema version  

This is **not** the full DB — only what the device is supposed to have.

---

## **Step 4 — Device Purges Local State (Safely)**
Device:

- Keeps:
  - `device_id`
  - `device_certificate`
  - `company_id`
  - `platform`
  - `device_keypair`
  - `pending_outbound_data` (temporarily)
- Purges:
  - Local DB  
  - Local media cache  
  - Local job list  
  - Local Q&A  
  - Local RFIs  
  - Local update cache  
  - Local logs (except crash logs)  

This is a **clean slate**, not a factory reset.

---

## **Step 5 — Device Installs Hard Sync Package**
Device receives:

- Jobs  
- Media metadata  
- Update chain  
- Permissions  
- Shared channels  
- Supplier/GC links  
- Q&A threads  
- RFIs  
- Logs  

Device installs:

- Updates in strict order  
- Schema migrations  
- Job bundles  
- Media metadata  
- Permissions  

---

## **Step 6 — Device Replays Pending Outbound Data**
If the device had:

- Unsent photos  
- Unsent job updates  
- Unsent Q&A messages  
- Unsent RFIs  
- Unsent logs  

It now sends them to the shop.

Shop:

- Deduplicates  
- Validates  
- Inserts  
- Logs  

---

## **Step 7 — Device rejoins the mesh**
Once hard sync is complete:

- Device is fully aligned with shop  
- Device can sync with other devices  
- Device can relay updates  
- Device can relay jobs  
- Device can relay media  

---

# 🛡️ **4. Safety Rules for Hard Sync**

### ✔ Hard sync never overwrites shop data  
Shop is always authoritative.

### ✔ Hard sync never deletes outbound data  
Device keeps unsent data until shop confirms receipt.

### ✔ Hard sync never bypasses update ordering  
Device still installs updates in strict chain order.

### ✔ Hard sync never bypasses company isolation  
Device must present valid certificate.

### ✔ Hard sync never bypasses shared‑channel rules  
Cross‑company data is still controlled by shop↔shop sync.

### ✔ Hard sync never bypasses supplier/GC permissions  
Supplier devices only receive supplier‑scoped data.

---

# 🧠 **5. Hard Sync UI (Simple & Safe)**

### **Settings → Advanced → Hard Sync**
Shows:

- Device ID  
- Current version  
- Last successful sync  
- Missing data indicators  
- “Hard Sync will reset local data and resync from shop. No job data will be lost.”  

Button:

> **Perform Hard Sync**

Confirmation:

> “Are you sure? This will reset local data and resync from the shop. Your unsent data will be preserved.”

---

# 🎯 **6. Why This Fits Perfectly Into Your Architecture**

Because your system already has:

- Shop authority  
- Strict version chains  
- Mesh sync  
- Update ordering  
- Multi‑shop sync  
- Multi‑company isolation  
- Supplier/GC channels  
- Device certificates  
- Encrypted channels  

A hard sync is simply:

> A controlled, shop‑authorized, safe re‑alignment of a device with the authoritative state.

It doesn’t break anything.  
It doesn’t bypass anything.  
It doesn’t weaken anything.  
It just gives you a **reliable recovery tool**.

---

If you want, I can now design:

- The **Hard Sync Package schema**  
- The **Hard Sync UI flow**  
- The **Hard Sync safety checklist**  
- The **Hard Sync error handling rules**

Just tell me which direction you want to go.
