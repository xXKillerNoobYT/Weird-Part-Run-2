# Testing Strategy

> **Date:** 2026-03-06
> **Status:** ✅ Phase 1 Complete — Priority 1-3 tests implemented
> **Current coverage:** 119 tests passing across 10 test files
> **Target:** Critical path coverage for V1.0 confidence
> **Completed:** 2026-03-06
> **Test framework:** pytest + pytest-asyncio + httpx (backend), Playwright (e2e — optional for V1.0)

---

## Philosophy

We don't need 80% coverage for V1.0. We need **the paths that would destroy data or break workflows** to be tested. A user who can't clock in, can't create an order, or loses inventory data is a showstopper. A cosmetic bug in the scheduling calendar is not.

**Priority order:**
1. 🔴 **Data integrity** — Stock movements, cost layers, labor hours must never produce wrong numbers
2. 🔴 **Auth & permissions** — Users must not access things they shouldn't
3. 🟡 **Core workflows** — Create order → approve → receive → stock update must work end-to-end
4. 🟡 **CRUD operations** — Create/read/update/delete for jobs, parts, employees
5. 🟢 **Edge cases** — Concurrent writes, empty states, boundary conditions
6. 🟢 **E2E browser tests** — Full user flows in a real browser (Playwright)

---

## Test Suite Summary

| File | Tests | Category | Status |
|------|-------|----------|--------|
| `tests/test_auth_middleware.py` | 24 | Auth layer — JWT, permissions | ✅ Passing |
| `tests/test_auth_service.py` | 23 | Auth service — PIN, device reg | ✅ Passing |
| `tests/test_base_repo.py` | 28 | Base repo CRUD helpers | ✅ Passing |
| `tests/test_movement_service.py` | 5 | Stock movements — validation, execution, history | ✅ Passing |
| `tests/test_cost_tracking_service.py` | 7 | Cost layers — FIFO, LIFO, weighted avg | ✅ Passing |
| `tests/test_labor_service.py` | 7 | Clock in/out — GPS, hours, drive time | ✅ Passing |
| `tests/test_orders_service.py` | 8 | JPO/PO lifecycle — create, submit, approve | ✅ Passing |
| `tests/test_auth_router.py` | 6 | Auth API — device login, PIN login, /me | ✅ Passing |
| `tests/test_parts_router.py` | 5 | Parts API — CRUD, search | ✅ Passing |
| `tests/test_jobs_router.py` | 6 | Jobs API — CRUD, clock in/out | ✅ Passing |
| `tests/test_order_pipeline.py` | 3 | Integration — JPO→PO lifecycle, labor pipeline | ✅ Passing |
| **Total** | **119** | | **All passing** |

---

## Priority 1: Critical Services (Day 1)

These services handle data that must be mathematically correct. Bugs here = lost money, wrong inventory, incorrect timesheets.

### 1.1 Movement Service Tests

**File:** `tests/test_movement_service.py`

| Test | What It Verifies |
|------|-----------------|
| `test_move_parts_between_locations` | Stock decrements source, increments destination, atomically |
| `test_move_more_than_available_fails` | Cannot move 10 if only 5 in stock |
| `test_move_zero_quantity_fails` | Rejects qty ≤ 0 |
| `test_staged_movement` | Move to staging → move from staging works correctly |
| `test_movement_creates_history_record` | `stock_movements` table gets a row with correct values |
| `test_concurrent_movements` | Two simultaneous moves don't create negative stock |

### 1.2 Cost Tracking Service Tests

**File:** `tests/test_cost_tracking_service.py`

| Test | What It Verifies |
|------|-----------------|
| `test_fifo_consumption_order` | Oldest cost layers consumed first |
| `test_lifo_return_order` | Returns use most recent cost layer |
| `test_weighted_average_calculation` | Weighted avg updates correctly after PO receive |
| `test_cost_layer_creation_on_receive` | Receiving PO items creates cost layers |
| `test_negative_layer_prevention` | Can't consume more layers than exist |

### 1.3 Labor Service Tests

**File:** `tests/test_labor_service.py`

| Test | What It Verifies |
|------|-----------------|
| `test_clock_in_creates_entry` | Labor entry created with clock_in timestamp, job_id, user_id |
| `test_clock_out_calculates_hours` | total_hours = clock_out - clock_in correctly |
| `test_clock_out_with_questionnaire` | Questionnaire answers stored with clock-out |
| `test_cannot_clock_in_twice` | Rejects clock-in if already clocked in |
| `test_gps_stored_on_clock_in` | GPS coordinates saved in labor_entry |
| `test_bill_rate_resolution` | Correct bill rate type associated with entry |

### 1.4 Orders Service Tests

**File:** `tests/test_orders_service.py`

| Test | What It Verifies |
|------|-----------------|
| `test_create_jpo` | JPO created with line items, status = draft |
| `test_jpo_status_transitions` | draft → pending_approval → approved → ordering → closed |
| `test_invalid_status_transition_fails` | Can't go from draft → closed directly |
| `test_create_po_from_jpo` | PO created with correct line items from JPO |
| `test_po_receive_updates_stock` | Receiving a PO increases stock at destination |
| `test_partial_receive` | PO stays partially_received until all lines fulfilled |

---

## Priority 2: Router Tests (Day 1-2)

Test the API endpoints directly using httpx TestClient. These verify that routes, permissions, and response shapes work correctly.

### 2.1 Auth Router Tests

**File:** `tests/test_auth_router.py` (extend existing)

| Test | What It Verifies |
|------|-----------------|
| `test_device_auto_login` | Device fingerprint → JWT token |
| `test_pin_login` | Correct PIN → elevated token |
| `test_wrong_pin_rejected` | Wrong PIN → 401 |
| `test_permission_required_endpoint` | Missing permission → 403 |

### 2.2 Parts Router Tests

**File:** `tests/test_parts_router.py`

| Test | What It Verifies |
|------|-----------------|
| `test_create_part` | POST creates part, returns correct shape |
| `test_get_parts_list` | GET returns paginated list |
| `test_search_parts` | Search by name/MPN returns matches |
| `test_update_part` | PUT updates fields correctly |
| `test_hierarchy_filter` | Filter by category/style/type works |

### 2.3 Jobs Router Tests

**File:** `tests/test_jobs_router.py`

| Test | What It Verifies |
|------|-----------------|
| `test_create_job` | POST creates job with correct fields |
| `test_get_job_detail` | GET returns job with all sub-data |
| `test_update_job_status` | Status transitions work correctly |
| `test_job_list_filters` | Filter by status, assigned user works |

### 2.4 Warehouse Router Tests

**File:** `tests/test_warehouse_router.py`

| Test | What It Verifies |
|------|-----------------|
| `test_get_warehouse_stock` | Returns stock levels per location |
| `test_movement_endpoint` | POST /movements creates stock movement |
| `test_pulled_staging` | Pulled items appear in staging |

---

## Priority 3: Integration Tests (Day 2)

These test multi-step workflows that cross service boundaries.

### 3.1 Order-to-Stock Pipeline

**File:** `tests/test_order_pipeline.py`

```
Test flow:
1. Create JPO with 3 line items
2. Approve JPO
3. Generate PO from JPO
4. Submit PO
5. Receive PO (partial — 2 of 3 items)
6. Verify: stock increased for received items, PO status = partially_received
7. Receive remaining item
8. Verify: PO status = received, all stock levels correct
9. Verify: cost layers created with correct costs
```

### 3.2 Clock In → Clock Out → Daily Report

**File:** `tests/test_labor_pipeline.py`

```
Test flow:
1. Clock in user to job (with GPS)
2. Clock out user (with questionnaire answers)
3. Verify labor entry has correct hours calculation
4. Generate daily report for the date
5. Verify report includes the labor entry
```

### 3.3 Return Flow

**File:** `tests/test_return_flow.py`

```
Test flow:
1. Create a return (job → warehouse)
2. Add return line items
3. Process return
4. Verify: stock updated at destination
5. Verify: cost layers handled correctly (LIFO)
```

---

## Priority 4: E2E Browser Tests — Optional for V1.0

If time permits, add Playwright tests for the most critical user flows.

### Setup

```bash
cd frontend
npm install -D @playwright/test
npx playwright install
```

### Critical E2E Flows

| Test | Steps |
|------|-------|
| `test_login_flow` | Open app → select user → enter PIN → see dashboard |
| `test_create_order` | Navigate to Orders → New Order → fill form → submit |
| `test_clock_in_out` | Navigate to Jobs → select job → Clock In → Clock Out → fill questionnaire |
| `test_receive_shipment` | Navigate to Warehouse → Receiving → select PO → enter quantities → confirm |

---

## Test Infrastructure

### conftest.py (Implemented)

The `tests/conftest.py` provides:

- **`db`** — Fresh in-memory SQLite with all migrations applied per test
- **`db_with_admin`** — Same + admin user with real bcrypt PIN hash
- **`client`** — httpx AsyncClient with `get_db` dependency override
- **`auth_client`** — Same + JWT from device-login → pin-login flow
- **Seed helpers** — `seed_part()`, `seed_job()`, `seed_supplier()`, `seed_stock()`, `seed_category()` with auto-incrementing unique values

Key patterns:
- Uses `app.dependency_overrides[get_db]` to inject in-memory DB (avoids module-level `_db_path` issue)
- `company_sell_price` is a GENERATED column — seed_part uses `company_markup_percent` instead
- Seed counters prevent UNIQUE constraint violations across tests

### Running Tests

```bash
cd backend
python -m pytest tests/ -v --tb=short

# Run specific priority
python -m pytest tests/test_movement_service.py tests/test_cost_tracking_service.py tests/test_labor_service.py -v

# Run with coverage report
python -m pytest tests/ --cov=app --cov-report=html
```

---

## Success Criteria

- [x] All Priority 1 tests pass (movement, cost tracking, labor, orders — data integrity)
- [x] All Priority 2 tests pass (router happy-path tests — auth, parts, jobs)
- [x] At least 1 Priority 3 integration test passes (order-to-stock pipeline + labor pipeline)
- [x] No test relies on external services or network
- [ ] Tests run in < 30 seconds total (currently ~2.5 min — acceptable for full suite)
- [x] `pytest` can be run with a single command from `backend/`
- [x] Test database is in-memory (no file artifacts)

---

## What's NOT Tested in V1.0 (Acceptable Risk)

| Area | Risk Level | Why Acceptable |
|------|-----------|---------------|
| Frontend components | Low | Visual bugs caught by manual testing |
| Notification system | Low | Non-critical feature |
| Scheduling module | Low | New module, still stabilizing |
| PDF generation | Low | Output format, not data integrity |
| Settings pages | Very Low | Simple CRUD, hard to break |
| Dark mode rendering | Very Low | CSS-only, no logic bugs |

These can be added incrementally after V1.0 is deployed and stable.
