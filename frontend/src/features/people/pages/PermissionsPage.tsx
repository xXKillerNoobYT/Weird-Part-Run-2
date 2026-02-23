/**
 * PermissionsPage — fine-grained access control management.
 *
 * Stub page. Will manage permissions per role and per user overrides.
 */

import { Shield } from 'lucide-react';
import { EmptyState } from '../../../components/ui/EmptyState';

export function PermissionsPage() {
  return (
    <EmptyState
      icon={<Shield className="h-12 w-12" />}
      title="Permissions"
      description="Configure fine-grained access control for roles and individual users. Coming soon."
    />
  );
}
