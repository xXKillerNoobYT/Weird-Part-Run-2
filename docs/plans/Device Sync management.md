Absolutely — this is a **perfect clarification**, and it strengthens the architecture rather than complicating it. I’ll integrate your new constraints into the unified system spec and refine the rules so they match *exactly* what you want:

- **Devices sync with each other constantly**  
- **Any device can act as a relay**  
- **Core data is always stored on all devices**  
- **Media is selectively stored, but always carried until delivered**  
- **Primary user controls device preferences**  
- **Borrowed users do NOT change device storage behavior**  
- **Devices may only reach the shop every 1–2 months**  
- **But they still converge weekly through the mesh**  
- **3‑month device logs + 1‑year shop logs guarantee reconciliation**

Below is the updated, consolidated technical sheet with your new rules fully integrated.

---

# 📘 **TECHNICAL SPECIFICATION (Updated With Your Clarifications)**  
### *Offline‑First • Bluetooth Mesh • Guaranteed Delivery • Selective Storage • Any User, Any Device*

---

# 1. SYSTEM PRINCIPLES (Updated)

### **1.1 Prime Directive (unchanged but reinforced)**  
> **If data has not been confirmed as delivered to the shop, ANY device that encounters it MUST carry it and MUST sync it with every device within range until delivery is confirmed.**

This is the backbone of the entire system.

### **1.2 Weekly Convergence Without Shop Contact**  
Even if a device only reaches the shop every **1–2 months**, it still converges weekly because:

- It meets other devices  
- Those devices meet others  
- Eventually someone meets a device that *has* synced with the shop recently  

This creates a **rolling wave of updates** across the fleet.

### **1.3 Core Data Always Stored on All Devices**  
Because text is small, and because users may borrow devices:

- **All core data for all *active* jobs is stored on all devices**
- Completed or on‑hold jobs may be purged from devices  
- But remain on the shop server  

This ensures:
- Borrowed devices still function  
- Permissions still enforce correctly  
- Sync logic never breaks  
- No device becomes “blind” to job relationships  

### **1.4 Media Storage Is Selective, But Media Delivery Is Mandatory**  
- Devices may choose what media to **keep permanently**  
- But they may NOT refuse to **carry undelivered media temporarily**  

---

# 2. DEVICE OWNERSHIP & USER BEHAVIOR

### **2.1 Device Belongs to One Primary User**
- The device’s **storage preferences** belong to the primary user  
- Borrowed users do NOT change:
  - Storage preferences  
  - Sync behavior  
  - Data retention rules  

### **2.2 Borrowed Users**
- Can log in  
- Can access their job data  
- Can create updates  
- But cannot change:
  - Device profile  
  - Storage rules  
  - Media preferences  

This prevents:
- A borrowed user accidentally downloading huge media sets  
- A borrowed user blocking required data  
- A borrowed user altering the device’s long‑term behavior  

---

# 3. SYNC LOG RETENTION (Updated)

### **3.1 Device Sync Logs**
- Each device keeps **3 months** of:
  - What it synced  
  - Who it synced with  
  - What data it carried  
  - What data was delivered  
  - What data is still undelivered  

This allows:
- Late reconciliation  
- Conflict resolution  
- Delivery confirmation  
- Audit trails  

### **3.2 Shop Sync Logs**
- Shop keeps **1 year** of:
  - All device syncs  
  - All deliveries  
  - All conflict resolutions  
  - All media confirmations  
  - All job state changes  

This ensures:
- Even a device that returns after 6 months can still reconcile  
- No data is ever lost  
- All conflicts can be resolved  

---

# 4. JOB STORAGE RULES (Updated)

### **4.1 Active Jobs**
- All devices store **core data** for all active jobs  
- This includes:
  - Job metadata  
  - Parts lists  
  - Notes  
  - Checklists  
  - Assignments  
  - Q&A  
  - Hours reports (text portion)  

### **4.2 Completed or On‑Hold Jobs**
- Devices may purge core data for these jobs  
- Shop retains full records  
- Devices retain:
  - UUID  
  - Version  
  - Tombstone (if deleted)  
  - Minimal metadata  

This keeps devices light while maintaining sync integrity.

---

# 5. MEDIA STORAGE RULES (Updated)

### **5.1 Permanent Media Storage**
Controlled by primary user preferences:

- Media for all jobs  
- Media for assigned jobs only  
- No permanent media storage  
- Thumbnails only  
- Last N days  

### **5.2 Temporary Media Storage (Mandatory)**
Regardless of preferences:

> **If media has not been confirmed as delivered to the shop, the device MUST store it temporarily.**

This applies even if:
- The device has “no media storage” preference  
- The device is low on memory  
- The device is not assigned to that job  
- The device is not the intended recipient  

### **5.3 Purge Rules**
A device may purge media ONLY when:

- Shop confirms delivery  
- AND device preferences allow purging  

---

# 6. BLUETOOTH MESH BEHAVIOR (Updated)

### **6.1 Gossip Rule (Roy Rule)**
> **Any device that meets another device must exchange all undelivered data, regardless of job, role, or preferences.**

### **6.2 Supervisor Absence Handling**
If the supervisor is sick:

- Workers on Jobs A, B, C, D sync with each other  
- They exchange all undelivered data  
- If ANY of them reaches the shop:
  - ALL undelivered data from ALL jobs is delivered  

This is exactly what you want.

### **6.3 Weekly Convergence Guarantee**
Because devices meet each other regularly:

- Even if a device doesn’t reach the shop for 2 months  
- It still receives updates from devices that *have* reached the shop  
- And it still forwards undelivered data toward the shop  

---

# 7. SHOP SYNC BEHAVIOR (Updated)

### **7.1 Devices May Reach the Shop Rarely**
Some devices may only sync with the shop every:

- 1 month  
- 2 months  
- Or more  

This is fine because:

- The mesh keeps them updated  
- They carry undelivered data for others  
- They receive updates from others  
- The shop logs allow reconciliation  

### **7.2 Shop Is the Truth Anchor**
When a device finally reaches the shop:

- All undelivered data is uploaded  
- All conflicts are resolved  
- All media is confirmed  
- All purge‑eligible media is flagged  
- Device receives:
  - All missing updates  
  - All conflict resolutions  
  - All job state changes  

---

# 8. COMPLETE BEHAVIOR SUMMARY (Updated)

### ✔ Any device may act as a relay  
### ✔ Undelivered data overrides preferences  
### ✔ All devices gossip undelivered data  
### ✔ Shop is the truth anchor  
### ✔ No data is ever deleted  
### ✔ Media delivery is mandatory  
### ✔ Media storage is optional  
### ✔ Chain‑of‑command accelerates delivery  
### ✔ Workers sync with each other when supervisors are absent  
### ✔ Any worker reaching the shop delivers everyone’s data  
### ✔ Devices keep 3 months of logs  
### ✔ Shop keeps 1 year of logs  
### ✔ Devices may only reach the shop every 1–2 months  
### ✔ Borrowed users do NOT change device behavior  
### ✔ All core data for active jobs is stored on all devices  


You’ve just clarified two **critical architectural constraints**, and they fit beautifully into the system we’ve been building:

1. **The shop “supervisor” is not a single server — it’s a cluster of normal PCs/Macs on the same LAN.**  
   - Any of them may be running at any time.  
   - All of them must stay in sync.  
   - They collectively act as the “truth anchor.”

2. **Only *active* jobs must be stored on all devices.**  
   - Completed / On‑Hold jobs are optional on devices.  
   - Whether a user has permission to view them does NOT force storage.  
   - The shop always keeps the full history.

Let me integrate these into the architecture cleanly and show you how the system behaves with these rules in place.

---

# 🧱 Updated Architecture: Multi‑PC Shop Cluster (No True Server)

Your shop is essentially a **peer cluster** of PCs/Macs that all share the same role:

- They are **truth anchors**  
- They are **always on the same LAN**  
- They **sync with each other**  
- They **sync with field devices**  
- They **store the full database**  
- They **resolve conflicts**  
- They **confirm media delivery**

### How they behave together

- Any shop PC can act as the “shop” when a field device arrives.  
- If two shop PCs are running, they sync with each other automatically.  
- If only one is running, it becomes the temporary “primary.”  
- When others come online, they reconcile using the **1‑year shop sync log**.

This gives you **server‑like reliability without needing a server**.

---

# 📦 Updated Job Storage Rules (Your Clarification Applied)

### ✔ **Active Jobs**
- **All devices must store full core data**  
- Media follows preference + delivery rules  
- Required for:
  - Sync integrity  
  - Permissions  
  - Routing  
  - Conflict resolution  
  - Borrowed device behavior  

### ✔ **Completed Jobs**
- Optional on devices  
- Devices may purge full data  
- Devices keep:
  - UUID  
  - Version  
  - Minimal metadata  
- Shop keeps full history forever

### ✔ **On‑Hold Jobs**
- Same as completed jobs  
- Optional on devices  
- Shop retains full data

### ✔ **User permissions do NOT force storage**
A worker may have permission to view a completed job, but:

- The device does NOT need to store it  
- The device may fetch it on demand  
- The shop remains the authoritative source

This keeps devices light while maintaining full auditability.

---

# 🔄 How This Fits Into the Mesh

### Why active jobs must be on all devices
Because:

- Workers borrow devices  
- Devices act as relays  
- Devices must detect conflicts  
- Devices must enforce permissions  
- Devices must route undelivered data  
- Devices must know job relationships

### Why completed/on‑hold jobs can be optional
Because:

- They no longer generate new data  
- They no longer need to be routed  
- They no longer need conflict resolution  
- They no longer need to be part of the mesh  
- They are not needed for field operations

This dramatically reduces storage load.

---

# 🧠 Updated Storage Decision Tree (With Your Clarification)

```text
                         ┌───────────────────────────────┐
                         │ Incoming RECORD or MEDIA      │
                         └───────────────┬───────────────┘
                                         │
                                         ▼
                         ┌───────────────────────────────┐
                         │ Is this an ACTIVE job?        │
                         └───────────────┬───────────────┘
                                         │
                         Yes             │ No (Completed/On‑Hold)
                         │               ▼
                         ▼   ┌────────────────────────────┐
┌───────────────────────┐   │ Is this CORE DATA?         │
│ ALWAYS STORE FULL     │   └───────────────┬────────────┘
│ CORE DATA for ACTIVE  │                   │
│ JOBS on ALL devices   │                   │
└───────────────────────┘                   ▼
                                            ┌────────────────────────────┐
                                            │ Store only if user prefs   │
                                            │ allow (optional)           │
                                            └────────────────────────────┘
```

Media follows the same logic, but with the **Prime Directive**:

> **Undelivered media MUST be stored temporarily, even for completed/on‑hold jobs.**

---

# 🏢 Updated Shop Architecture Diagram (Multi‑PC Cluster)

```text
                ┌──────────────────────────────────────────┐
                │              SHOP CLUSTER                │
                │   (Multiple PCs/Macs on same LAN)        │
                │                                          │
                │  ┌──────────────┐   ┌──────────────┐    │
                │  │ Shop PC #1   │   │ Shop PC #2   │    │
                │  │ (running)    │   │ (running)    │    │
                │  └──────┬───────┘   └──────┬───────┘    │
                │         │ Sync LAN         │ Sync LAN    │
                │  ┌──────┴───────┐   ┌──────┴───────┐    │
                │  │ Shop PC #3   │   │ Shop PC #4   │    │
                │  │ (offline)    │   │ (offline)    │    │
                │  └──────────────┘   └──────────────┘    │
                └──────────────────────────────────────────┘

- Any running shop PC can sync with field devices.
- All running shop PCs sync with each other.
- Offline shop PCs reconcile when they come online.
- Shop cluster maintains 1‑year sync log.
```

---

# 🔄 Updated Sync Flow Diagram (Field → Shop Cluster)

```text
[Field Device]                          [Any Shop PC]
      │                                        │
      │ 1. Connect to LAN                      │
      │───────────────────────────────────────>│
      │                                        │
      │ 2. Send change summary                 │
      │───────────────────────────────────────>│
      │                                        │
      │ 3. Shop PC requests missing data       │
      │<───────────────────────────────────────│
      │                                        │
      │ 4. Upload all undelivered data         │
      │───────────────────────────────────────>│
      │                                        │
      │ 5. Shop PC resolves conflicts          │
      │    updates DB, logs sync               │
      │                                        │
      │ 6. Shop PC syncs with other shop PCs   │
      │    (LAN cluster)                       │
      │                                        │
      │ 7. Shop PC sends confirmations         │
      │<───────────────────────────────────────│
      │                                        │
      │ 8. Device purges eligible media        │
      │                                        │
      └────────────────────────────────────────┘
```

---

# 🔁 Updated Job Lifecycle Model (With Optional Storage)

```text
┌───────────────────────────┐
│        CREATED            │
└───────────────┬───────────┘
                ▼
┌───────────────────────────┐
│        ACTIVE             │
│ - Must be stored on all   │
│   devices (core data)     │
│ - Media follows prefs +   │
│   delivery rules          │
└───────────────┬───────────┘
        ┌───────┴───────────────┐
        ▼                       ▼
┌─────────────────────┐  ┌───────────────────────────┐
│   ON HOLD           │  │   COMPLETION REQUESTED    │
│ - Optional storage  │  │ - Optional storage        │
│ - Shop retains full │  │ - Shop confirms final     │
│   data              │  │   state                   │
└─────────────┬───────┘  └───────────────┬───────────┘
              ▼                          ▼
      ┌─────────────────────┐   ┌───────────────────────────┐
      │   ON HOLD (SHOP)    │   │       COMPLETED           │
      │ - Devices may purge │   │ - Devices may purge       │
      │   core data         │   │   core data               │
      │ - Keep metadata     │   │ - Keep metadata           │
      └─────────────┬───────┘   └───────────────┬───────────┘
                    ▼                           ▼
            ┌───────────────────────────┐
            │   ARCHIVED (SHOP ONLY)   │
            │ - Full history retained  │
            │ - Devices keep metadata  │
            └───────────────────────────┘
```

---

# ✔ Summary of Your Clarifications (Now Fully Integrated)

### ✔ Shop is a multi‑PC cluster, not a server  
### ✔ All shop PCs sync with each other  
### ✔ Any shop PC can sync with field devices  
### ✔ Devices may only reach the shop every 1–2 months  
### ✔ Mesh ensures weekly convergence anyway  
### ✔ Only active jobs must be stored on all devices  
### ✔ Completed/on‑hold jobs are optional on devices  
### ✔ User permissions do NOT force storage  
### ✔ Primary user controls device preferences  
### ✔ Borrowed users do NOT change device behavior  
### ✔ Undelivered data overrides preferences  
### ✔ All devices act as relays  

---

Things to consider, Please make full. Detailed documentation when making these areas.

- A **device behavior matrix**  
- A **shop cluster sync algorithm**  
- A **field device state machine**  
- A **media routing algorithm**  
- A **conflict resolution matrix**  

