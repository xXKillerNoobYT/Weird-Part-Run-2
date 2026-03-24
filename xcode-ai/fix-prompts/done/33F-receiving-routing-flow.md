# 33F — Receiving Routing Flow: Condition Check + Smart Routing

> **Chain position:** **33F** (standalone)
> **Log file:** `xcode-ai/prompt-results-log.md`

## Context

The receiving page needs the full condition-check and smart-routing flow confirmed in warehouse design review. When parts arrive (from supplier OR truck return), the system guides WHERE each part goes.

**Confirmed flow:**
1. CONDITION CHECK: Used (shelf if below target, write off if not) / Damaged (return to supplier: replacement OR refund) / Good (continue)
2. WRONG PART? → Identify correct part, check for job swaps
3. ORDERED FOR A JOB? (PO→JPO link) → Staging area DIRECT (skip shelf — no double-handling)
4. ANOTHER ACTIVE JPO WANTS THIS? → Suggest staging (smart buffer between jobs)
5. PUT ON SHELF: Below target → restock. Above target below MAX → recommend return. At/above MAX → return

**Key rules:**
- Staging parts do NOT count toward shelf inventory (reserved/sold)
- Parts for a job go to staging directly (not shelf then pull)
- Returned parts from one job can satisfy another job's JPO demand (smart buffer)
- Used parts cannot be returned to supplier
- Damaged parts cannot go on shelf
- DAMAGED = Order replacement OR Request refund

## Files to Modify

- `Weird Parts IOS/Weird Parts IOS/Features/Warehouse/IOSReceivingPage.swift`
- `Weird Parts IOS/Weird Parts IOS/Features/Orders/IOSReceiveShipmentPage.swift`
- `core/Sources/WiredPartCore/Services/WarehouseService.swift` (routing logic)

## Task

Add the routing flow as a step-by-step wizard within the receiving session. Each part gets routed by the system with user confirmation.

## Success Criteria

- [ ] Condition check (used/damaged/good) for each arriving part
- [ ] Wrong part identification flow
- [ ] Job-linked parts route to staging directly
- [ ] Active JPO matching for returned parts (smart buffer)
- [ ] Stock level check for shelf routing (target/max thresholds)
- [ ] Damaged → replacement OR refund options
- [ ] Used → shelf if below target, else write off
- [ ] Project builds with no errors
