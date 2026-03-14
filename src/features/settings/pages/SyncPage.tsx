/**
 * SyncPage — data synchronization settings and status.
 *
 * Shows sync status, device registry, device sync profiles with
 * editable policies, relay health dashboard, sync history,
 * and conflict log for admin users. Also provides shop URL
 * configuration for native (Tauri) devices.
 */

import { isNativeApp } from '../../../lib/environment';
import { ShopConnectionCard } from '../components/sync/ShopConnectionCard';
import { BluetoothSyncCard } from '../components/sync/BluetoothSyncCard';
import { DeviceRegistryCard } from '../components/sync/DeviceRegistryCard';
import { DeviceSyncProfilesCard } from '../components/sync/DeviceSyncProfilesCard';
import { MeshRelayHealthCard } from '../components/sync/MeshRelayHealthCard';
import { HardSyncRecoveryCard } from '../components/sync/HardSyncRecoveryCard';
import { SyncHistoryCard } from '../components/sync/SyncHistoryCard';
import { HardSyncHistoryCard } from '../components/sync/HardSyncHistoryCard';
import { ConflictLogCard } from '../components/sync/ConflictLogCard';

export function SyncPage() {
  return (
    <div className="space-y-6">
      <h2 className="text-xl font-bold text-gray-900 dark:text-gray-100">
        Sync & Devices
      </h2>

      {/* Shop Connection (native devices) */}
      {isNativeApp() && <ShopConnectionCard />}

      {/* Bluetooth Sync Status (Windows PCs) */}
      {!isNativeApp() && <BluetoothSyncCard />}

      {/* Registered Devices */}
      <DeviceRegistryCard />

      {/* Device Sync Profiles */}
      <DeviceSyncProfilesCard />

      {/* Mesh Relay Health */}
      <MeshRelayHealthCard />

      {/* Hard Sync Recovery */}
      <HardSyncRecoveryCard />

      {/* Sync History */}
      <SyncHistoryCard />

      {/* Hard Sync History */}
      <HardSyncHistoryCard />

      {/* Conflict Log */}
      <ConflictLogCard />
    </div>
  );
}
