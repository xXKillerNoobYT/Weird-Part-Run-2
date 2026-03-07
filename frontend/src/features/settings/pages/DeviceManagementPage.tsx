/**
 * DeviceManagementPage — manage registered devices and sessions.
 *
 * Planned for v2.0: Device registration, per-device PGP keys,
 * session management, and sync status monitoring.
 */

import { Monitor } from 'lucide-react';
import { EmptyState } from '../../../components/ui/EmptyState';

export function DeviceManagementPage() {
  return (
    <EmptyState
      icon={<Monitor className="h-12 w-12" />}
      title="Device Management"
      description="Device registration, session management, and sync monitoring are planned for v2.0 when mobile device support is added."
    />
  );
}
