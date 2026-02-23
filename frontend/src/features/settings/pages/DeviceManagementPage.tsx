/**
 * DeviceManagementPage — manage registered devices and sessions.
 *
 * Stub page. Will show connected devices, session management, and remote wipe.
 */

import { Monitor } from 'lucide-react';
import { EmptyState } from '../../../components/ui/EmptyState';

export function DeviceManagementPage() {
  return (
    <EmptyState
      icon={<Monitor className="h-12 w-12" />}
      title="Device Management"
      description="View registered devices, manage active sessions, and configure device policies. Coming soon."
    />
  );
}
