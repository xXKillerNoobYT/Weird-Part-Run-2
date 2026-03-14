/**
 * AssignmentsTab — lists driver assignments with assign/unassign controls.
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Users, Plus, Trash2, Home } from 'lucide-react';
import { PageSpinner } from '../../../../components/ui/Spinner';
import { EmptyState } from '../../../../components/ui/EmptyState';
import { Button } from '../../../../components/ui/Button';
import { useAuthStore } from '../../../../stores/auth-store';
import { PERMISSIONS } from '../../../../lib/constants';
import { listAssignments, unassignDriver } from '../../../../api/vehicles';
import { AssignDriverModal } from '../AssignDriverModal';
import type { VehicleAssignment } from '../../../../lib/types';


export function AssignmentsTab({ vehicleId, vehicleName }: { vehicleId: number; vehicleName: string }) {
  const { hasPermission } = useAuthStore();
  const canManage = hasPermission(PERMISSIONS.MANAGE_FLEET);
  const queryClient = useQueryClient();

  const [showAssign, setShowAssign] = useState(false);

  const { data: assignments, isLoading } = useQuery({
    queryKey: ['vehicle-assignments', vehicleId],
    queryFn: () => listAssignments(vehicleId),
    staleTime: 15_000,
  });

  const unassignMut = useMutation({
    mutationFn: (userId: number) => unassignDriver(vehicleId, userId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['vehicle-assignments', vehicleId] });
      queryClient.invalidateQueries({ queryKey: ['vehicle', vehicleId] });
      queryClient.invalidateQueries({ queryKey: ['vehicles'] });
    },
  });

  if (isLoading) return <PageSpinner label="Loading assignments..." />;

  const existingDriverIds = (assignments ?? []).map((a) => a.user_id);

  return (
    <div className="space-y-3">
      {canManage && (
        <div className="flex justify-end">
          <Button size="sm" icon={<Plus className="h-4 w-4" />} onClick={() => setShowAssign(true)}>
            <span className="hidden sm:inline">Assign Driver</span>
          </Button>
        </div>
      )}

      {!assignments || assignments.length === 0 ? (
        <EmptyState
          icon={<Users className="h-12 w-12" />}
          title="No Drivers Assigned"
          description="Assign drivers to this vehicle to track who drives it."
          action={
            canManage ? (
              <Button icon={<Plus className="h-4 w-4" />} onClick={() => setShowAssign(true)}>
                Assign Driver
              </Button>
            ) : undefined
          }
        />
      ) : (
        <div className="space-y-2">
          {assignments.map((a) => (
            <AssignmentRow
              key={a.id}
              assignment={a}
              canManage={canManage}
              onUnassign={() => {
                if (window.confirm(`Remove ${a.user_name} from this vehicle?`)) {
                  unassignMut.mutate(a.user_id);
                }
              }}
            />
          ))}
        </div>
      )}

      <AssignDriverModal
        isOpen={showAssign}
        onClose={() => setShowAssign(false)}
        vehicleId={vehicleId}
        vehicleName={vehicleName}
        existingDriverIds={existingDriverIds}
      />
    </div>
  );
}


function AssignmentRow({
  assignment: a,
  canManage,
  onUnassign,
}: {
  assignment: VehicleAssignment;
  canManage: boolean;
  onUnassign: () => void;
}) {
  const typeColors: Record<string, string> = {
    primary: 'bg-blue-100 dark:bg-blue-900/30 text-blue-700 dark:text-blue-300',
    authorized: 'bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-300',
    temporary: 'bg-amber-100 dark:bg-amber-900/30 text-amber-700 dark:text-amber-300',
  };

  return (
    <div className="flex items-center gap-3 p-3 bg-surface border border-border rounded-lg">
      <div className="flex items-center justify-center h-9 w-9 rounded-full bg-gray-100 dark:bg-gray-800 text-gray-500 dark:text-gray-400 shrink-0">
        <Users className="h-4 w-4" />
      </div>
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2 flex-wrap">
          <span className="text-sm font-medium text-gray-900 dark:text-gray-100">
            {a.user_name ?? `User #${a.user_id}`}
          </span>
          <span className={`px-2 py-0.5 text-[10px] font-medium rounded-full ${typeColors[a.assignment_type] ?? 'bg-gray-100 dark:bg-gray-800 text-gray-600 dark:text-gray-400'}`}>
            {a.assignment_type}
          </span>
          {a.is_take_home && (
            <span className="flex items-center gap-1 text-[10px] text-blue-500 dark:text-blue-400">
              <Home className="h-3 w-3" /> Take-Home
            </span>
          )}
        </div>
        <div className="flex items-center gap-3 text-xs text-gray-500 dark:text-gray-400 mt-0.5">
          {a.home_to_shop_miles != null && (
            <span>{a.home_to_shop_miles} mi commute</span>
          )}
          {a.start_date && <span>Since {a.start_date}</span>}
          {a.notes && <span className="truncate max-w-[150px]">{a.notes}</span>}
        </div>
      </div>
      {canManage && (
        <button
          onClick={onUnassign}
          className="p-2 text-gray-400 hover:text-red-500 transition-colors shrink-0"
          title="Remove assignment"
        >
          <Trash2 className="h-4 w-4" />
        </button>
      )}
    </div>
  );
}
