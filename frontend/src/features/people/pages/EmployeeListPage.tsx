/**
 * EmployeeListPage — directory of all employees and contractors.
 *
 * Stub page. Will show employee profiles, contact info, and role assignments.
 */

import { Users } from 'lucide-react';
import { EmptyState } from '../../../components/ui/EmptyState';

export function EmployeeListPage() {
  return (
    <EmptyState
      icon={<Users className="h-12 w-12" />}
      title="Employee List"
      description="View and manage employee profiles, contact info, and team assignments. Coming soon."
    />
  );
}
