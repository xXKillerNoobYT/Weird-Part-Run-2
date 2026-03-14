/// mDNS Service Discovery
///
/// Advertises this WiredPart instance on the LAN so other devices can
/// find it, and discovers other WiredPart instances.
///
/// Service type: `_wiredpart._tcp.local.`
///
/// TXT records published:
///   - device_id: UUID of this device
///   - device_name: human-readable name (e.g., "Shop Computer")
///   - company_id: company identifier (devices only sync within same company)
///   - version: app version
///
/// The mdns-sd crate runs its own background thread for multicast
/// I/O, so this works with both sync and async code.

use mdns_sd::{ServiceDaemon, ServiceEvent, ServiceInfo};
use serde::Serialize;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};

const SERVICE_TYPE: &str = "_wiredpart._tcp.local.";

/// A discovered peer device on the LAN
#[derive(Debug, Clone, Serialize)]
pub struct DiscoveredPeer {
    pub device_id: String,
    pub device_name: String,
    pub company_id: String,
    pub host: String,
    pub port: u16,
    pub version: String,
    pub discovered_at: String,
}

/// Manages mDNS advertisement and discovery
pub struct DiscoveryManager {
    daemon: ServiceDaemon,
    peers: Arc<Mutex<HashMap<String, DiscoveredPeer>>>,
    my_device_id: String,
    my_company_id: String,
}

impl DiscoveryManager {
    /// Create a new discovery manager and start the mDNS daemon
    pub fn new(device_id: String, company_id: String) -> Result<Self, String> {
        let daemon = ServiceDaemon::new().map_err(|e| format!("mDNS daemon error: {}", e))?;
        Ok(Self {
            daemon,
            peers: Arc::new(Mutex::new(HashMap::new())),
            my_device_id: device_id,
            my_company_id: company_id,
        })
    }

    /// Advertise this device on the LAN with the given sync server port
    pub fn advertise(
        &self,
        port: u16,
        device_name: &str,
    ) -> Result<(), String> {
        // Build instance name: "WiredPart-<short_id>"
        let short_id = &self.my_device_id[..8.min(self.my_device_id.len())];
        let instance_name = format!("WiredPart-{}", short_id);

        // Get the local hostname
        let hostname = hostname::get()
            .map(|h| h.to_string_lossy().to_string())
            .unwrap_or_else(|_| "unknown".to_string());
        let mdns_hostname = format!("{}.local.", hostname);

        // TXT record properties
        let properties = [
            ("device_id", self.my_device_id.as_str()),
            ("device_name", device_name),
            ("company_id", self.my_company_id.as_str()),
            ("version", env!("CARGO_PKG_VERSION")),
        ];

        let service = ServiceInfo::new(
            SERVICE_TYPE,
            &instance_name,
            &mdns_hostname,
            "",  // Let mdns-sd resolve IP
            port,
            &properties[..],
        )
        .map_err(|e| format!("ServiceInfo error: {}", e))?;

        self.daemon
            .register(service)
            .map_err(|e| format!("Registration error: {}", e))?;

        log::info!(
            "[discovery] Advertising as '{}' on port {}",
            instance_name,
            port
        );

        Ok(())
    }

    /// Start browsing for other WiredPart devices on the LAN.
    /// Runs in a background thread — discovered peers are stored internally.
    pub fn start_browsing(&self) -> Result<(), String> {
        let receiver = self
            .daemon
            .browse(SERVICE_TYPE)
            .map_err(|e| format!("Browse error: {}", e))?;

        let peers = Arc::clone(&self.peers);
        let my_device_id = self.my_device_id.clone();
        let my_company_id = self.my_company_id.clone();

        std::thread::spawn(move || {
            loop {
                match receiver.recv() {
                    Ok(event) => match event {
                        ServiceEvent::ServiceResolved(info) => {
                            let device_id = info
                                .get_property_val_str("device_id")
                                .unwrap_or_default()
                                .to_string();
                            let company_id = info
                                .get_property_val_str("company_id")
                                .unwrap_or_default()
                                .to_string();

                            // Skip ourselves and devices from other companies
                            if device_id == my_device_id || company_id != my_company_id {
                                continue;
                            }

                            let device_name = info
                                .get_property_val_str("device_name")
                                .unwrap_or_default()
                                .to_string();
                            let version = info
                                .get_property_val_str("version")
                                .unwrap_or_default()
                                .to_string();

                            // Get the first IPv4 address
                            let host = info
                                .get_addresses()
                                .iter()
                                .find(|a| a.is_ipv4())
                                .map(|a| a.to_string())
                                .unwrap_or_default();

                            if host.is_empty() {
                                continue;
                            }

                            let peer = DiscoveredPeer {
                                device_id: device_id.clone(),
                                device_name,
                                company_id,
                                host,
                                port: info.get_port(),
                                version,
                                discovered_at: chrono_now(),
                            };

                            log::info!(
                                "[discovery] Found peer: {} at {}:{}",
                                peer.device_name,
                                peer.host,
                                peer.port
                            );

                            if let Ok(mut map) = peers.lock() {
                                map.insert(device_id, peer);
                            }
                        }
                        ServiceEvent::ServiceRemoved(_, fullname) => {
                            // Extract device_id from the removed service
                            // The fullname looks like "WiredPart-abcd1234._wiredpart._tcp.local."
                            log::info!("[discovery] Peer removed: {}", fullname);
                            if let Ok(mut map) = peers.lock() {
                                map.retain(|_, p| {
                                    !fullname.contains(&p.device_id[..8.min(p.device_id.len())])
                                });
                            }
                        }
                        _ => {} // SearchStarted, SearchStopped — informational
                    },
                    Err(_) => break, // Channel closed
                }
            }
        });

        log::info!("[discovery] Browsing for peers on LAN");
        Ok(())
    }

    /// Get all currently discovered peers (same company only)
    pub fn get_peers(&self) -> Vec<DiscoveredPeer> {
        self.peers
            .lock()
            .map(|map| map.values().cloned().collect())
            .unwrap_or_default()
    }

    /// Shut down the mDNS daemon
    #[allow(dead_code)]
    pub fn shutdown(&self) {
        let _ = self.daemon.shutdown();
    }
}

/// Simple ISO 8601 timestamp without pulling in chrono
pub fn chrono_now_utc() -> String {
    chrono_now()
}

fn chrono_now() -> String {
    // Use std::time for a basic UTC timestamp
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();

    // Convert seconds to a basic ISO date string
    // (good enough for discovery timestamps — not used for conflict resolution)
    let secs_per_day = 86400u64;
    let days = now / secs_per_day;
    let time_of_day = now % secs_per_day;
    let hours = time_of_day / 3600;
    let minutes = (time_of_day % 3600) / 60;
    let seconds = time_of_day % 60;

    // Calculate year/month/day from days since epoch (1970-01-01)
    let (year, month, day) = days_to_date(days);

    format!(
        "{:04}-{:02}-{:02}T{:02}:{:02}:{:02}Z",
        year, month, day, hours, minutes, seconds
    )
}

/// Convert days since Unix epoch to (year, month, day)
fn days_to_date(days: u64) -> (u64, u64, u64) {
    // Simplified — accurate for 2000-2100
    let mut y = 1970;
    let mut remaining = days;
    loop {
        let days_in_year = if y % 4 == 0 && (y % 100 != 0 || y % 400 == 0) {
            366
        } else {
            365
        };
        if remaining < days_in_year {
            break;
        }
        remaining -= days_in_year;
        y += 1;
    }
    let leap = y % 4 == 0 && (y % 100 != 0 || y % 400 == 0);
    let days_in_months: [u64; 12] = [
        31,
        if leap { 29 } else { 28 },
        31, 30, 31, 30, 31, 31, 30, 31, 30, 31,
    ];
    let mut m = 0;
    for &dim in &days_in_months {
        if remaining < dim {
            break;
        }
        remaining -= dim;
        m += 1;
    }
    (y, m + 1, remaining + 1)
}
