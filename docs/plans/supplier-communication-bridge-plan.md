# Supplier Communication Bridge Plan

> **Date:** 2026-03-07
> **Status:** 🟡 Started (Phase S0 implemented)
> **Source idea:** `docs/plans/The supplier's rep welcome too Idea.md`
> **Scope:** Supplier-facing communication layer that bridges contractor↔supplier workflows without replacing supplier ERP systems.

---

## Why this exists

Suppliers need:
- Their own mode/login context
- Multi-customer support
- Robust pairing/recovery when network conditions change
- Fast communication tools for PO/RFI and part recommendations

Contractors need:
- Clear, contextual incoming supplier information
- Easy import of supplier-suggested parts into internal catalog
- Optional (not mandatory) API integrations for richer supplier data

---

## Design principles

1. **Communication-first, not ERP replacement**
2. **Price sharing off by default**
3. **Attachment-first clarity** (PDFs/photos/videos/docs/links)
4. **Optional integrations via stable connector contracts**
5. **Resilient shop identity + pairing recovery for remote sync**

---

## Phased roadmap

### Phase S0 (Implemented now)
- Add in-app planning/control surface in Settings:
  - Route: `/settings/supplier-bridge`
  - Tab: `Supplier Bridge`
  - Page: phased roadmap, guardrails, and implementation checklist

### Phase S1 — Communication Bridge Core
- Supplier-side app mode with role-scoped UI
- Contractor↔supplier partner channels for PO/RFI threads
- Rich attachment messaging with structured context
- Link + supplier part reference payload support

### Phase S2 — Supplier Suggest Catalog (Backup)
- Rep-level lightweight suggest catalog
- Fast “send suggestion” actions
- Contractor one-click import to internal catalog
- Auto-mapping to supplier source metadata (supplier ID + supplier part ID)

### Phase S3 — Optional Supplier API Connectors
- Connector abstraction (`connector_type`, `auth_strategy`, `capabilities`)
- Optional catalog/availability/pricing sync endpoints
- Schema/version compatibility layer to prevent breaking integrations

### Phase S4 — Remote Pairing + Recovery
- Permanent shop identity model
- Known-partner table with last-known endpoint
- One-sided IP auto-recovery path
- Two-sided guided manual recovery wizard + PIN verification

---

## Implementation notes (S0)

- `frontend/src/features/settings/pages/SupplierBridgePage.tsx` added.
- Settings navigation + app route registered.
- This is intentionally a safe first slice: no DB migrations yet, no protocol changes yet.

---

## Next implementation target

Recommended next concrete build step:
- **S1.1** Supplier message payload extension in existing chat/RFI flow
  - Add typed attachment bundles + external supplier reference block
  - Keep access behind permissions and feature flags

