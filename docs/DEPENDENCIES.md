# Wired-Part — Dependency Reference

> Last updated: 2026-03-06
> Purpose: Reliable dependency map for backend/frontend and deployment prep.

---

## Backend Python Dependencies (`backend/requirements.txt`)

## Runtime
- fastapi
- uvicorn[standard]
- pydantic
- pydantic-settings
- aiosqlite
- python-jose[cryptography]
- bcrypt
- apscheduler
- python-dotenv
- python-multipart

## PDF and export-related
- fpdf2 (required by `backend/app/services/pdf_service.py`)

## Test-only
- pytest
- pytest-asyncio
- httpx

### Notes
- `fpdf2` is used for PO PDF generation and should be present in `backend/requirements.txt`.
- If `fpdf2` is missing, PDF generation falls back to plain text output.

---

## Frontend npm Dependencies (`frontend/package.json`)

## Runtime
- react
- react-dom
- react-router-dom
- @tanstack/react-query
- axios
- zustand
- lucide-react
- clsx
- tailwind-merge
- qrcode
- html5-qrcode

## Type/runtime support
- @types/qrcode

## Dev/build
- vite
- typescript
- @vitejs/plugin-react
- tailwindcss
- @tailwindcss/vite
- eslint ecosystem packages

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

- [ ] Backend requirements.txt includes all runtime dependencies (including fpdf2)
- [ ] Frontend `npm install` resolves without lock or peer errors
- [ ] Dev/build commands run on Windows and Mac
- [ ] Any newly introduced package is documented in this file and in the relevant plan section
