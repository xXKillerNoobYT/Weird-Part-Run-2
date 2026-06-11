# Wired-Part — Dependency Reference

> Last updated: 2026-03-10
> Purpose: Reliable dependency map for backend/frontend and deployment prep.
> Paperclip staging update: Treat this as historical dependency context until a promoted stage requires dependency changes. Current execution order lives in `docs/plans/staged-paperclip-goals.md`.

---

## Backend Python Dependencies (`backend/requirements.txt`)

### Runtime — Web Framework
- fastapi (>=0.115.0)
- uvicorn[standard] (>=0.34.0)

### Runtime — Data & Validation
- pydantic (>=2.10.0)
- pydantic-settings (>=2.7.0)
- aiosqlite (>=0.20.0)

### Runtime — Authentication & Security
- python-jose[cryptography] (>=3.3.0) — JWT tokens
- bcrypt (>=4.0.0) — password hashing
- cryptography (>=44.0.0) — Ed25519 device security keys

### Runtime — Scheduling & Utilities
- apscheduler (>=3.10.0)
- python-dotenv (>=1.0.0)
- python-multipart (>=0.0.20) — file uploads

### Runtime — PDF & Export
- fpdf2 (>=2.7.0) — PO PDF generation (`backend/app/services/pdf_service.py`)

### Test-only
- pytest (>=8.3.0)
- pytest-asyncio (>=0.24.0)
- httpx (>=0.28.0) — also used at runtime by `ai_service.py` for LM Studio API calls

### Notes
- `fpdf2` is used for PO PDF generation. If missing, PDF generation falls back to plain text output.
- `httpx` is listed under test-only in requirements.txt but is also imported at runtime by `ai_service.py`. It works because it's always installed, but note the dual usage.
- `cryptography` is a transitive dependency of `python-jose[cryptography]` but is also directly imported by `device_security_service.py` for Ed25519 operations, so it's explicitly listed.

---

## Frontend npm Dependencies (`package.json`)

### Runtime — React Core
- react (^19.2.0)
- react-dom (^19.2.0)
- react-router-dom (^7.13.0)
- @tanstack/react-query (^5.90.21)
- zustand (^5.0.11)

### Runtime — HTTP & Data
- axios (^1.13.5)

### Runtime — UI & Styling
- lucide-react (^0.575.0) — icon library
- clsx (^2.1.1) — className utility
- tailwind-merge (^3.5.0) — Tailwind class deduplication

### Runtime — QR/Barcode
- qrcode (^1.5.4)
- html5-qrcode (^2.3.8)
- jsbarcode (^3.12.3)
- @types/qrcode (^1.5.6)
- @types/jsbarcode (^3.11.4)

### Runtime — Drag & Drop
- @dnd-kit/core (^6.3.1)
- @dnd-kit/sortable (^10.0.0)
- @dnd-kit/utilities (^3.2.2)

### Runtime — Capacitor (Mobile)
- @capacitor/core (^6.0.0)
- @capacitor/ios (^6.2.1)
- @capacitor/app (^6.0.0)
- @capacitor/camera (^6.0.0)
- @capacitor/geolocation (^6.0.0)
- @capacitor/haptics (^6.0.0)
- @capacitor/network (^6.0.0)
- @capacitor/preferences (^6.0.0)
- @capacitor/splash-screen (^6.0.0)
- @capacitor/status-bar (^6.0.0)
- @capacitor-community/sqlite (^6.0.0)

### Dev/Build
- vite (^7.3.1)
- typescript (~5.9.3)
- @vitejs/plugin-react (^5.1.1)
- tailwindcss (^4.2.0)
- @tailwindcss/vite (^4.2.0)
- @capacitor/cli (^6.0.0)
- @types/node, @types/react, @types/react-dom
- eslint + eslint-plugin-react-hooks + eslint-plugin-react-refresh + typescript-eslint + globals

### Custom (No External Package)
- Toast system: `src/lib/toast.ts` — pure DOM implementation, zero dependencies

---

## Install Commands

```bash
# Backend
cd backend
pip install -r requirements.txt

# Frontend
cd frontend
npm install
```

---

## Deployment Dependency Checklist

- [x] Backend requirements.txt includes all runtime dependencies (including fpdf2) — verified 2026-03-10
- [x] Frontend `npm install` resolves without lock or peer errors — verified 2026-03-10
- [x] Dev/build commands run on Windows (verified); Mac requires physical test
- [x] Any newly introduced package is documented in this file and in the relevant plan section — verified 2026-03-10
