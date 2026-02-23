/**
 * SyncPage — data synchronization settings and status.
 *
 * Stub page. Will show sync status, conflict resolution, and offline data management.
 */

import { Cloud } from 'lucide-react';
import { EmptyState } from '../../../components/ui/EmptyState';

export function SyncPage() {
  return (
    <EmptyState
      icon={<Cloud className="h-12 w-12" />}
      title="Sync"
      description="Monitor data sync status, resolve conflicts, and manage offline storage. Coming soon."
    />
  );
}
