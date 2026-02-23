# Wired-Part

Field service management app for an electrical contracting company. Manages parts inventory, warehouse operations, truck inventories, job tracking, labor hours, procurement, and pre-billing exports.

---

## Quick Start

### Prerequisites

- **Python 3.12+** (tested on 3.14)
- **Node.js 18+** with npm
- **Git**

### 1. Clone & Install

```bash
git clone https://github.com/xXKillerNoobYT/Weird-Part-Run-2.git
cd Weird-Part-Run-2

# Backend
cd backend
pip install -r requirements.txt
cd ..

# Frontend
cd frontend
npm install
cd ..
```

### 2. Start the Servers

**Backend** (API on port 8000):
```bash
cd backend
python -m uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload
```

**Frontend** (UI on port 5173):
```bash
cd frontend
npm run dev
```

### 3. Open the App

Navigate to **http://localhost:5173** in your browser.

---

## Default Login Credentials

| Field | Value |
|-------|-------|
| **User** | Admin |
| **PIN** | `1234` |

On first launch, the app creates a default Admin user with PIN **1234**. Select "Admin" from the user picker, then enter the PIN to sign in.

> **Change the default PIN** in a production environment. The PIN is set via the `DEFAULT_ADMIN_PIN` environment variable in `.env`.

---

## Environment Variables

All configuration is in the `.env` file at the project root:

| Variable | Default | Description |
|----------|---------|-------------|
| `APP_NAME` | `Wired-Part` | Application display name |
| `APP_VERSION` | `0.1.0` | Current version |
| `DATABASE_PATH` | `./wiredpart.db` | SQLite database file path (relative to `backend/`) |
| `SECRET_KEY` | `dev-secret-change-...` | JWT signing key (**change in production**) |
| `PIN_HASH_ROUNDS` | `12` | bcrypt hash rounds for PIN hashing |
| `DEFAULT_ADMIN_PIN` | `1234` | Default admin PIN on first launch |
| `ACCESS_TOKEN_EXPIRE_SECONDS` | `86400` | JWT access token lifetime (24 hours) |
| `PIN_TOKEN_EXPIRE_SECONDS` | `300` | PIN verification token lifetime (5 minutes) |
| `CORS_ORIGINS` | `["http://localhost:5173"]` | Allowed CORS origins (JSON array) |
| `BACKEND_HOST` | `0.0.0.0` | Backend bind address |
| `BACKEND_PORT` | `8000` | Backend port |

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| **Backend** | Python 3.12+ / FastAPI / SQLite (aiosqlite) / Pydantic v2 |
| **Frontend** | React 19 / TypeScript / Vite / Tailwind CSS v4 |
| **State** | Zustand (UI state) / TanStack React Query (server state) |
| **Auth** | Device fingerprint auto-login + PIN-based login + JWT |
| **Icons** | Lucide React |

---

## Project Structure

```
Weird-Part-Run-2/
├── backend/
│   ├── app/
│   │   ├── main.py              # FastAPI entry point
│   │   ├── config.py            # Settings from .env
│   │   ├── database.py          # SQLite connection + migrations
│   │   ├── models/              # Pydantic request/response models
│   │   ├── routers/             # API route modules
│   │   ├── repositories/        # Data access layer
│   │   ├── services/            # Business logic (auth, movements)
│   │   ├── middleware/          # JWT auth + permission dependencies
│   │   └── migrations/          # Numbered SQL migration files
│   ├── tests/
│   └── requirements.txt
├── frontend/
│   ├── src/
│   │   ├── App.tsx              # Root component with all routes
│   │   ├── api/                 # Axios client + endpoint modules
│   │   ├── components/
│   │   │   ├── auth/            # AuthGate, UserPicker, PinLoginForm
│   │   │   ├── layout/          # AppShell, Sidebar, TopBar, TabBar
│   │   │   └── ui/              # Button, Card, Input, Badge, Modal, etc.
│   │   ├── features/            # One folder per module (dashboard, parts, etc.)
│   │   ├── stores/              # Zustand stores (auth, theme, sidebar)
│   │   └── lib/                 # Types, navigation config, utils, constants
│   ├── package.json
│   └── vite.config.ts
├── docs/
│   └── implementation-plan.md   # Full implementation plan
├── .env                         # Environment configuration
├── .gitignore
├── CLAUDE.md                    # AI agent instructions
├── ThePlan.md                   # Full product specification
└── README.md                    # This file
```

---

## Authentication Flow

1. **Device auto-login**: The app generates a browser fingerprint and checks if this device is registered to a user. If so, you're logged in automatically.
2. **User picker**: On new or public devices, a grid of active users is shown. Tap your name.
3. **PIN entry**: Enter your 4-6 digit PIN. Auto-submits at 4 digits.
4. **Sensitive actions**: Some operations (editing pricing, managing permissions) require a secondary PIN verification that issues a short-lived token.

---

## Modules

| Module | Description | Route |
|--------|-------------|-------|
| Dashboard | KPI cards + quick actions | `/dashboard` |
| Parts | Catalog, brands, pricing, forecasting, import/export | `/parts/*` |
| Warehouse | Dashboard, inventory grid, staging, audit, movement log | `/warehouse/*` |
| Trucks | My truck, all trucks, tools, maintenance, mileage | `/trucks/*` |
| Jobs | Active jobs, templates | `/jobs/*` |
| Orders | Draft POs, pending, incoming, returns, procurement | `/orders/*` |
| People | Employees, roles/hats, permissions | `/people/*` |
| Reports | Pre-billing, timesheets, labor overview, exports | `/reports/*` |
| Settings | App config, themes, sync, AI config, devices | `/settings/*` |

---

## API Documentation

With the backend running, visit **http://localhost:8000/docs** for the interactive Swagger UI, or **http://localhost:8000/redoc** for ReDoc.

### Key Endpoints

| Method | Endpoint | Description | Auth Required |
|--------|----------|-------------|---------------|
| `POST` | `/api/auth/device-login` | Auto-login by device fingerprint | No |
| `POST` | `/api/auth/pin-login` | Login with user ID + PIN | No |
| `GET` | `/api/auth/me` | Current user profile + permissions | Yes |
| `GET` | `/api/auth/users` | User picker list | No |
| `POST` | `/api/auth/verify-pin` | PIN verification for sensitive actions | Yes |
| `GET` | `/api/settings/theme` | Get theme settings | Yes |
| `PUT` | `/api/settings/theme` | Update theme settings | Yes |
| `GET` | `/api/health` | Health check | No |

---

## Roles & Permissions

The app uses a **hat-based** permission system. Users wear one or more "hats" (roles), and their permissions are the **union** of all hat permissions.

### Built-in Hats (Roles)

| Hat | Level | Description |
|-----|-------|-------------|
| Admin | 0 | Full access to everything |
| Office Manager | 1 | Manages orders, people, reports, settings |
| Foreman | 2 | Manages jobs, labor, warehouse operations |
| Lead Technician | 3 | Job management, truck/parts operations |
| Technician | 4 | View jobs, clock in/out, consume parts |
| Apprentice | 5 | Limited view access, clock in/out |
| Grunt | 6 | Minimal access (view own truck only) |

There are **30 permission keys** controlling access to every feature. See `backend/app/migrations/001_foundation.sql` for the full list.

---

## Development Notes

- **Database**: SQLite with WAL mode. The `.db` file is created automatically on first run in the `backend/` directory.
- **Migrations**: SQL files in `backend/app/migrations/` run automatically on startup. Track applied migrations in a `_migrations` table.
- **Dark mode**: Toggle in the top bar. Persists to the backend settings store.
- **Responsive**: Sidebar collapses on mobile, tab bar adapts to screen size.

---

## License

Private repository. All rights reserved.
