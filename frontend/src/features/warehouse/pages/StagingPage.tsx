/**
 * StagingPage — pulled parts staging area.
 *
 * Stub page. Will show parts pulled from bins awaiting truck loading or job allocation.
 */

import { PackageCheck } from 'lucide-react';
import { EmptyState } from '../../../components/ui/EmptyState';

export function StagingPage() {
  return (
    <EmptyState
      icon={<PackageCheck className="h-12 w-12" />}
      title="Pulled/Staging"
      description="View parts pulled from bins and staged for truck loading or job dispatch. Coming soon."
    />
  );
}
