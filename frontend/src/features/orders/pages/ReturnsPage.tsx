/**
 * ReturnsPage — manage part returns and RMAs.
 *
 * Stub page. Will track return authorizations, credit tracking, and restocking.
 */

import { RotateCcw } from 'lucide-react';
import { EmptyState } from '../../../components/ui/EmptyState';

export function ReturnsPage() {
  return (
    <EmptyState
      icon={<RotateCcw className="h-12 w-12" />}
      title="Returns"
      description="Process part returns, track RMA status, and manage supplier credits. Coming soon."
    />
  );
}
