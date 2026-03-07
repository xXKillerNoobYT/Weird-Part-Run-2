# Sideloading Guide — Wired-Part Mobile App

> **Last updated:** 2026-03-06
> **Platforms:** iOS (iPhone + iPad) and Android
> **Method:** Free sideloading — Sideloadly + AltServer for iOS, direct APK for Android
> **Architecture:** Each device runs the full frontend with a lean field-worker backend and its own local SQLite database. Works offline. Syncs with the shop over Wi-Fi when available.
> **Prerequisites:** Capacitor mobile project built (see `deployment-master-plan.md`)
> **Production cost:** $0

---

## Quick Summary

| Platform | Method | Cost | Install From | Update Process | Notes |
|----------|--------|------|--------------|----------------|-------|
| **iOS** | Sideloadly + AltServer | **Free** | Mac or Windows via USB | Rebuild IPA → re-sideload | 7-day signing, auto-refreshed by AltServer |
| **Android** | APK sideload | **Free** | Any OS via USB/email/download | Share new APK file | No expiry, no developer account |
| **iPad** | Same as iOS | **Free** | Same | Same | Universal app — works on both |

### How the Free iOS Method Works

Apple allows installing apps outside the App Store using a **free Apple ID** for code signing. The caveat: the signing expires every **7 days**. But **AltServer** (a free tool running on the shop computer) auto-refreshes the signing over Wi-Fi — workers never notice.

| Step | What | Who | When |
|------|------|-----|------|
| 1. Build IPA | Compile the app | You (on a Mac) | First build + updates only |
| 2. Install via USB | Push IPA to each device | You (Mac or Windows) | First install + updates |
| 3. Auto-refresh | AltServer re-signs over Wi-Fi | Shop computer (automatic) | Every 7 days, no action needed |

---

## Part 1: iOS Installation (Free — Sideloadly + AltServer)

### What You Need

| Tool | Where to Get It | Platform | Purpose |
|------|-----------------|----------|---------|
| **Xcode** | Mac App Store (free) | Mac only | Build the iOS binary |
| **Sideloadly** | [sideloadly.io](https://sideloadly.io) | Mac + Windows | Sign & install IPA on device via USB |
| **AltServer** | [altstore.io](https://altstore.io) | Mac + Windows | Auto-refresh 7-day signing over Wi-Fi |
| **Free Apple ID** | [appleid.apple.com](https://appleid.apple.com) | — | Code signing identity |
| **USB cable** | — | — | Connect device to computer |
| **Node.js 20+** | [nodejs.org](https://nodejs.org) | Mac | Build the frontend |

You do **NOT** need an Apple Developer Account ($99/year). A free Apple ID is all that's required.

### Step-by-Step: Building the IPA (Mac Required)

You only need a Mac for this step — building the IPA. After that, you can install from either Mac or Windows.

#### 1. Build the Frontend + Sync to iOS

Open Terminal on the Mac:

```bash
cd /path/to/Weird-Part-Run-2/frontend

# Install dependencies (first time only)
npm install

# Build the web app
npm run build

# Sync to iOS project
npx cap sync ios

# Open in Xcode
npx cap open ios
```

#### 2. Configure Xcode Signing (First Time Only)

Xcode opens with the iOS project:

1. Click the **App** project in the left sidebar (top-level, blue icon)
2. Select the **App** target
3. Click the **Signing & Capabilities** tab
4. Check **"Automatically manage signing"**
5. Set **Team** to your **free Apple ID**
   - If your Apple ID isn't listed: Xcode → Settings → Accounts → **+ (Add)** → Apple ID → sign in
6. Set **Bundle Identifier** to `com.wiredpart.app`
7. Under **Deployment Info**: set Minimum iOS version to **16.0**

If Xcode shows a signing error, click "Try Again" — it usually resolves itself.

#### 3. Set App Display Name (First Time Only)

1. In the project navigator, open `App/Info.plist`
2. Set `CFBundleDisplayName` to `Wired-Part`
3. Set `CFBundleName` to `Wired-Part`

#### 4. Build and Export the IPA

1. In the Xcode menu bar: **Product → Destination → Any iOS Device (arm64)**
2. **Product → Archive** (takes 2-5 minutes)
3. When done, the **Organizer** window opens showing your archive
4. Click **Distribute App**
5. Select **Development** → **Next**
6. Check "Automatically manage signing" → **Next**
7. Click **Export** → save the `.ipa` file somewhere easy to find (Desktop is fine)

You now have a `WiredPart.ipa` file. This is what gets installed on devices.

> **Tip:** Copy this IPA to a shared folder or USB drive if you'll install from a different computer (e.g., a Windows PC at the shop).

### Step-by-Step: Installing on Each Device (Mac or Windows)

This is the step you repeat per device. You can do it from **Mac or Windows** — you don't need the Mac from the build step.

#### 5. Install Sideloadly

- Download from [sideloadly.io](https://sideloadly.io)
- **Mac:** Drag to Applications
- **Windows:** Run the installer

#### 6. Sideload the App

1. **Connect** the iPhone or iPad to the computer via **USB cable**
2. If the device asks "Trust This Computer?" → tap **Trust** and enter the device passcode
3. Open **Sideloadly**
4. Drag the `WiredPart.ipa` file into the Sideloadly window (or click the file icon to browse)
5. Make sure your device appears in the device dropdown
6. Enter your **free Apple ID** email in the Apple ID field
7. Click **Start**
8. Enter your Apple ID password when prompted (and 2FA code if enabled)
9. Sideloadly signs the app and pushes it to the device — takes about 1-2 minutes

#### 7. Trust the App on the Device

After Sideloadly finishes, do this **once per Apple ID** on each device:

1. On the device: **Settings → General → VPN & Device Management**
2. Under "Developer App", tap your **Apple ID email**
3. Tap **"Trust [your email]"** → confirm

This only needs to be done once. Future re-installs with the same Apple ID don't require it again.

#### 8. Launch and Set Up Sync

1. Tap the **Wired-Part** icon on the home screen
2. The app opens — **works immediately** with a local database (fully offline-capable from first launch)
3. Connect to **shop Wi-Fi**
4. Scan QR code from shop computer (at `http://<shop-ip>:8000/setup`) or enter shop IP manually in app settings
5. Initial sync pulls all existing data from the shop to the device
6. Log in with their **PIN**
7. Done! ✅ Device works independently — syncs automatically when on shop Wi-Fi

**Repeat steps 6-8 for each iPhone/iPad.** Takes about 3-5 minutes per device.

### Setting Up AltServer (Auto-Refresh — Do This Once)

Free-signed iOS apps expire after **7 days**. AltServer solves this by automatically re-signing the app over Wi-Fi. Set it up once on the shop computer and forget about it.

#### On Mac:

1. Download **AltServer** from [altstore.io](https://altstore.io)
2. Drag `AltServer.app` to the **Applications** folder
3. Open AltServer — it appears as an icon in the **menu bar** (top-right of screen)
4. Click the AltServer icon → **Sign in with Apple ID** (same free Apple ID you used in Sideloadly)
5. That's it — AltServer runs in the background

**To auto-start:** System Settings → General → Login Items → add AltServer

#### On Windows:

1. Download **AltServer for Windows** from [altstore.io](https://altstore.io)
2. Run the installer
3. AltServer appears in the **system tray** (bottom-right, may be hidden — click the ^ arrow)
4. Right-click the AltServer tray icon → **Sign in with Apple ID**
5. AltServer runs in the background

**To auto-start:** AltServer adds itself to startup by default. Verify in Task Manager → Startup tab.

#### How Auto-Refresh Works:

- AltServer runs quietly on the shop computer
- When a worker's iPhone/iPad connects to the **same Wi-Fi network**, AltServer detects it
- AltServer refreshes the app signing **automatically** — no action from the worker
- As long as workers connect to shop Wi-Fi at least once every 7 days, the app never expires

### Updating the iOS App

When you build a new version of Wired-Part:

```bash
# On the Mac:
cd frontend
npm run build
npx cap sync ios
npx cap open ios
```

In Xcode:
1. **Bump the version number** in the project settings (e.g., 1.0.1 → 1.0.2)
2. Product → Archive → Export (Development) → save new IPA
3. Re-sideload the new IPA to each device using Sideloadly (same process as step 6)

Workers' local database and all data is **preserved** — new migrations run automatically on first launch.

### iOS Tips

- **7-day signing is invisible** as long as AltServer is running on the shop computer. Workers never need to think about it.
- If a worker is away from the shop for 8+ days, the app stops launching. **Data is NOT lost.** Connect to shop Wi-Fi → AltServer refreshes → app works again with all data intact.
- If a worker gets a new phone: sideload the IPA again → sync from shop restores all their data.
- You can use up to **3 apps** with a single free Apple ID for sideloading. Wired-Part counts as 1.

---

## Part 2: Android Sideloading via APK

### What You Need

1. **Android Studio** installed (free — [developer.android.com/studio](https://developer.android.com/studio))
   - Works on Windows, Mac, or Linux
2. **Node.js 20+** installed
3. **The Wired-Part source code**

### Step-by-Step: First Build

#### 1. Build the Frontend + Sync to Android

```bash
cd /path/to/Weird-Part-Run-2/frontend

# Install dependencies (first time only)
npm install

# Build the web app
npm run build

# Sync to Android project
npx cap sync android

# Open in Android Studio
npx cap open android
```

#### 2. Generate a Signing Key (First Time Only)

In Android Studio:
1. **Build → Generate Signed Bundle / APK**
2. Select **APK**
3. Click **Create new...** for the key store
   - Key store path: choose a safe location (e.g., `~/keys/wiredpart.jks`)
   - Password: choose a strong password (write it down!)
   - Key alias: `wiredpart`
   - Key password: same or different
   - Fill in at least one field (Name, Organization, etc.)
4. Click **OK**

**⚠️ KEEP THIS KEY SAFE.** You need the same key for every update. If you lose it, workers have to uninstall and reinstall.

#### 3. Build the APK

1. **Build → Generate Signed Bundle / APK → APK**
2. Select your key store, enter passwords
3. Build variant: **release**
4. Click **Create**
5. Output file: `frontend/android/app/build/outputs/apk/release/app-release.apk`

#### 4. Share the APK with Workers

Choose one or more methods:

**Method A: Host on the shop server** (recommended)
- Copy `app-release.apk` to `frontend/public/downloads/wiredpart.apk`
- Rebuild frontend: `npm run build`
- Workers download from: `http://<shop-ip>:8000/downloads/wiredpart.apk`

**Method B: Share directly**
- Email the APK to each worker
- Put it on Google Drive and share the link
- Transfer via USB cable
- AirDrop equivalent (Android Nearby Share)

#### 5. Workers Install the APK

Each worker does this on their Android phone/tablet:

1. **Download the APK** (from email, Drive link, or shop server URL)
2. Android may warn "Install from Unknown Sources" — tap **Settings**
3. Enable **"Allow from this source"** for your browser or file manager
4. Tap the APK file → **Install**
5. Open **Wired-Part** — **works immediately** with a local database (fully offline-capable)
6. Connect to shop Wi-Fi → scan QR code or enter shop IP for sync setup
7. Initial sync pulls all existing data from shop → device is populated
8. Log in with their PIN
9. Done! ✅ Device works offline from here — syncs automatically on shop Wi-Fi

### Updating the Android App

```bash
# Build new version
cd frontend
npm run build
npx cap sync android
npx cap open android
```

In Android Studio:
1. Open `frontend/android/app/build.gradle`
2. Bump `versionCode` by 1 and update `versionName`
3. Build → Generate Signed APK (same key!)
4. Share the new APK — workers install it over the old version (data preserved)

### Android Tips

- Workers only need to enable "Unknown Sources" once per source (browser, file manager, etc.)
- Installing a new APK over an old one **preserves app data and local database** (as long as same signing key). New migrations run automatically on first launch.
- Android 12+ requires "Install unknown apps" permission per-app, not a global setting
- Android APKs **do not expire** — no refreshing needed, ever
- If a worker factory-resets their phone, reinstall APK → initial sync from shop restores all data

---

## Part 3: iPad Setup

iPads use the **exact same process as iPhones** (Part 1 above). Sideloadly and AltServer work identically for iPad.

The Capacitor project produces a **universal iOS app** that runs on both iPhone and iPad.

**iPad-specific notes:**
- The app uses responsive design — iPad gets the tablet layout automatically
- Sidebar is always visible on iPad (landscape), drawer on iPhone
- All 44×44px touch targets are maintained
- Split-view / Slide Over multitasking works with the responsive layout

---

## Part 4: Troubleshooting

### iOS Issues

| Problem | Solution |
|---------|----------|
| Build fails in Xcode | Clean build: Product → Clean Build Folder, then Archive again |
| "No profiles found" in Xcode | Xcode → Settings → Accounts → Download Manual Profiles |
| Sideloadly says "provision.cpp:… Your account requires…" | Apple may require app-specific password for 2FA accounts. Generate one at [appleid.apple.com](https://appleid.apple.com) → Sign-In and Security → App-Specific Passwords |
| Sideloadly says "Max 3 apps reached" | Free Apple IDs can only sign 3 apps. Remove one from Sideloadly or use a second free Apple ID. |
| "Untrusted Developer" on device | Settings → General → VPN & Device Management → tap your Apple ID → Trust |
| App stops launching after 7 days | AltServer didn't refresh. Ensure AltServer is running on shop computer + device is on same Wi-Fi. The app and data are fine — it'll work again once refreshed. |
| AltServer not refreshing | Make sure AltServer is signed in with the same Apple ID used for sideloading. Check that both the shop computer and device are on the same Wi-Fi network. |
| App crashes on launch | Connect device to Mac → Xcode → Window → Devices and Simulators → View Device Logs for crash info |

### Android Issues

| Problem | Solution |
|---------|----------|
| "App not installed" | Already installed from a different signing key — uninstall first, then install |
| "Parse error" | APK may be corrupted — re-download or re-build |
| "Blocked by Play Protect" | Tap "More details" → "Install anyway". This is normal for sideloaded apps |
| "Install from Unknown Sources" not showing | On Android 12+, it's per-app: Settings → Apps → your browser → Install unknown apps |

### Sync / Connection Issues

| Problem | Solution |
|---------|----------|
| Sync status shows "Shop unreachable" | Check that phone is on same Wi-Fi as shop computer. The **app still works offline** — data will sync when connection is restored. |
| Sync fails with CORS error | Verify CORS_ORIGINS in `.env` includes `capacitor://localhost` (iOS) and `https://localhost` (Android) |
| Data not appearing after sync | Check sync detail panel (tap sync icon in header) — look for conflict resolutions or errors |
| Works on Wi-Fi, not on cellular | Expected for sync — the shop is only reachable on the local network. **All other features work on cellular/offline.** |
| Shop IP address changed | Assign a static IP to the shop computer in router settings. Update shop URL in app settings |
| App works but shows "3 changes pending" | Normal — means you have local changes not yet synced. They'll sync automatically when shop is reachable |

---

## Part 5: Quick Reference

### Cost Comparison

| Method | Cost | Signing Duration | Install Method | Update Method |
|--------|------|------------------|----------------|---------------|
| **Free sideloading** (this guide) | $0 | 7 days (auto-refreshed) | USB + Sideloadly | Re-sideload IPA |
| Android sideloading | $0 | No expiry | Share APK | Share new APK |

### Build Commands (from project root)

```bash
# Frontend
cd frontend && npm run build && cd ..

# iOS
cd frontend && npx cap sync ios && npx cap open ios

# Android  
cd frontend && npx cap sync android && npx cap open android
```

### Common Capacitor Commands

```bash
npx cap sync          # Copy web assets + sync native plugins (both platforms)
npx cap sync ios      # iOS only
npx cap sync android  # Android only
npx cap open ios      # Open Xcode
npx cap open android  # Open Android Studio
npx cap run ios       # Build + run on connected iOS device
npx cap run android   # Build + run on connected Android device
```

### Version Bumping

- **iOS**: Xcode → project settings → General → Version + Build
- **Android**: `frontend/android/app/build.gradle` → `versionCode` + `versionName`
- **Frontend**: `frontend/package.json` → `version`
- **Backend**: `backend/app/config.py` → `APP_VERSION`
