/**
 * HatsPage — manage roles ("hats") employees can wear.
 *
 * Stub page. Will define role types, permissions bundles, and hat assignments.
 */

import { Crown } from 'lucide-react';
import { EmptyState } from '../../../components/ui/EmptyState';

export function HatsPage() {
  return (
    <EmptyState
      icon={<Crown className="h-12 w-12" />}
      title="Roles & Hats"
      description="Define organizational roles, assign hats to employees, and manage team structure. Coming soon."
    />
  );
}
