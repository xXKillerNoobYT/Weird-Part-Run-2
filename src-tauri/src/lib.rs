/// WiredPart Tauri Application
///
/// This is the Rust entry point for the Tauri native shell.
/// The app uses a React frontend with a local SQLite database
/// (via tauri-plugin-sql) for fully offline operation.
///
/// Plugins registered here:
/// - tauri-plugin-sql: SQLite database (local-first data layer)
/// - tauri-plugin-log: Debug logging (dev builds only)
/// - tauri-plugin-fs: File system access (read/write files)
/// - tauri-plugin-dialog: Native open/save dialogs
/// - tauri-plugin-notification: OS-level notifications
/// - tauri-plugin-autostart: Launch on login (shop computer, desktop-only)
/// - tauri-plugin-updater: Auto-update for desktop builds (desktop-only)
///
/// Phase 4 additions:
/// - P2P sync server (axum HTTP on random port)
/// - mDNS/Bonjour discovery (_wiredpart._tcp.local.)
/// - IPC commands for TS ↔ Rust sync bridge
///
/// Phase 5 additions:
/// - Apple Multipeer Connectivity (macOS/iOS) for BT P2P sync
/// - ObjC bridge compiled via `cc` crate (see build.rs)
///
/// Phase 6 additions:
/// - Native file export (save dialog + fs write)
/// - OS notifications (sync reminders, shift starts)
/// - Auto-start on boot (shop computer role)
/// - TS-side scheduled task runner (replaces Python APScheduler)

mod commands;
mod crypto;
mod discovery;
mod multipeer;
mod sync_server;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    // Create managed state for the sync server + discovery
    let sync_state = commands::create_sync_state();
    let discovery_state = commands::create_discovery_state();

    let mut builder = tauri::Builder::default()
        // ── SQLite database plugin ──
        // The frontend connects via `Database.load('sqlite:wiredpart.db')`
        .plugin(tauri_plugin_sql::Builder::default().build())
        // ── Phase 6: Native capability plugins ──
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_notification::init());

    // Desktop-only plugins — these reference APIs that don't exist on iOS/Android.
    #[cfg(desktop)]
    {
        // Auto-start on boot (shop computer role)
        builder = builder.plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            Some(vec!["--autostarted"]),
        ));
        // Auto-update — checks endpoint for new versions, downloads + installs
        builder = builder.plugin(tauri_plugin_updater::Builder::new().build());
    }

    builder
        // ── Managed state for P2P sync ──
        .manage(sync_state)
        .manage(discovery_state)
        // ── IPC commands for sync ──
        .invoke_handler(tauri::generate_handler![
            // Phase 4: LAN sync
            commands::start_p2p_sync,
            commands::get_discovered_peers,
            commands::get_sync_inbox,
            commands::clear_sync_inbox,
            commands::set_sync_outbox,
            commands::get_sync_port,
            commands::get_sync_server_status,
            commands::update_sync_timestamp,
            commands::push_to_sync_inbox,
            // Phase 5: Security + Multipeer Connectivity (BT + Wi-Fi P2P)
            commands::set_company_public_key,
            multipeer::start_multipeer,
            multipeer::stop_multipeer,
            multipeer::get_multipeer_peers,
            multipeer::multipeer_send,
            multipeer::multipeer_pop_received,
            multipeer::multipeer_receive_count,
            multipeer::multipeer_is_running,
        ])
        .setup(|app| {
            // Dev-only: enable logging plugin
            if cfg!(debug_assertions) {
                app.handle().plugin(
                    tauri_plugin_log::Builder::default()
                        .level(log::LevelFilter::Info)
                        .build(),
                )?;
            }
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
