# Wired-Part — Customer Setup Guide

Everything you need to get Wired-Part running at your shop.

---

## What You Need

| Item | Purpose | Notes |
|------|---------|-------|
| **Shop computer** | Runs the server (Windows 10/11 or Mac) | Any desktop/laptop at the shop |
| **Wi-Fi router** | Connects all devices on same network | Any standard home/office router |
| **Web browser** | Access from shop desktops | Chrome, Edge, or Safari |
| **Mobile devices** (optional) | iPads, iPhones, Android phones for field workers | Requires Capacitor app install |

---

## Step 1: Install on the Shop Computer

### Prerequisites

1. **Python 3.12+** — Download from [python.org](https://www.python.org/downloads/)
   - During install, check "Add Python to PATH"
2. **Node.js 18+** — Download from [nodejs.org](https://nodejs.org/)

### Installation

1. Copy the `Weird-Part-Run-2` folder to your shop computer (e.g., `C:\WiredPart`)
2. Open **Terminal** (Mac) or **PowerShell** (Windows)
3. Run the startup script:

**Windows:**
```powershell
cd C:\WiredPart
powershell -ExecutionPolicy Bypass -File scripts\start-server.ps1
```

**Mac:**
```bash
cd ~/WiredPart
bash scripts/start-server.sh
```

The script will:
- Create a Python virtual environment
- Install backend dependencies
- Build the frontend
- Detect your LAN IP address
- Start the server

You'll see output like:
```
  Server starting at:
    Local:   http://localhost:8000
    Network: http://192.168.1.100:8000

  Field devices connect to: http://192.168.1.100:8000
```

**Write down the Network URL** — you'll need it for Step 3.

---

## Step 2: Access from Shop Computers

On any computer connected to the same Wi-Fi:

1. Open a web browser (Chrome, Edge, or Safari)
2. Go to `http://<shop-ip>:8000` (the Network URL from Step 1)
3. The first time, you'll see the login screen

### First Login

1. Select the admin user ("Admin")
2. Enter the admin PIN created during setup
3. You're in! Go to **Settings → People** to create employee accounts

### Create Employee Accounts

1. Go to **People → Employees**
2. Click **Add Employee**
3. Set their name, email, phone, and a 4-6 digit PIN
4. Assign their **hats** (roles) — this controls what they can see and do
5. A default Mon-Fri schedule is automatically created

---

## Step 3: Connect Mobile Devices (Optional)

### For iPads/iPhones

1. Install the Wired-Part app via sideloading (see `docs/plans/sideloading-guide.md`)
2. Open the app
3. Go to **Settings → Sync**
4. Enter the shop server URL: `http://<shop-ip>:8000`
5. Tap **Test** to verify connection
6. Tap **Sync Now** for initial data load

### For Android

1. Install the APK (transfer via USB or file share)
2. Same setup as iOS above

### How Sync Works

- Mobile devices work **fully offline** — no Wi-Fi needed for daily tasks
- When on the shop Wi-Fi, changes sync automatically every 5 minutes
- You can also tap the sync icon in the header to sync manually
- The shop server is the "truth" — if two people edit the same thing, the last edit wins

---

## Step 4: Daily Operations

### For Field Workers (Mobile)

- **Clock in/out** — Tap a job, then Clock In. Clock Out prompts questionnaire.
- **Move parts** — Use the warehouse movement wizard to pull/transfer parts
- **Create orders** — Submit parts requests from job sites
- **Check tools** — View assigned tools, do kit verification
- **Write notes** — Job notebooks for daily updates

### For Office Staff (Desktop)

- **Dashboard** — KPI overview, quick actions
- **Manage orders** — Review parts requests, create purchase orders
- **Approve time-off** — Review and approve/deny requests
- **Dispatch** — Assign workers to jobs for the day
- **Reports** — Pre-billing, timesheets, labor overview, profitability
- **Cost tracking** — FIFO/LIFO cost analysis, budget monitoring

---

## Step 5: Auto-Start on Boot

### Windows

1. Press `Win+R`, type `taskschd.msc`, press Enter
2. Click **Create Basic Task**
3. Name: "Wired-Part Server"
4. Trigger: "When the computer starts"
5. Action: "Start a program"
6. Program: `powershell.exe`
7. Arguments: `-ExecutionPolicy Bypass -File C:\WiredPart\scripts\start-server.ps1`
8. Finish

### Mac

Create `~/Library/LaunchAgents/com.wiredpart.server.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.wiredpart.server</string>
    <key>ProgramArguments</key>
    <array>
        <string>bash</string>
        <string>/Users/YOU/WiredPart/scripts/start-server.sh</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
</dict>
</plist>
```

Then run: `launchctl load ~/Library/LaunchAgents/com.wiredpart.server.plist`

---

## Backups

### Automatic Backups

Set up a daily backup using the backup script:

**Windows** (Task Scheduler):
- Program: `powershell.exe`
- Arguments: `-File C:\WiredPart\scripts\backup-db.ps1`
- Schedule: Daily at midnight

**Mac** (cron):
```bash
crontab -e
# Add this line:
0 0 * * * bash /Users/YOU/WiredPart/scripts/backup-db.sh
```

Backups are saved to `backups/` and the last 30 are kept automatically.

### Restore from Backup

If something goes wrong, restore from a backup:

**Windows:**
```powershell
powershell -File scripts\restore-db.ps1
```

**Mac:**
```bash
bash scripts/restore-db.sh
```

The script will show available backups and let you choose one. A safety backup of your current database is created before restoring.

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Server won't start | Check Python is installed: `python --version` |
| Can't access from other computers | Ensure all devices are on the same Wi-Fi network |
| Mobile app can't connect | Check the shop URL in Settings → Sync. Must include `http://` and port |
| "Invalid PIN" | Ask your admin to reset your PIN |
| Slow performance | The database grows over time. Regular backups + cleanup help |
| Data not syncing | Tap the sync icon in the header. Check if shop is reachable |

---

## Getting Help

- Check the **API docs** at `http://<shop-ip>:8000/docs`
- Review logs at `backend/logs/wiredpart.log`
- Database is at `backend/wiredpart.db` (SQLite — can browse with DB Browser)
