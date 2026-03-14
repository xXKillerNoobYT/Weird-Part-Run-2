/**
 * MileageTab — daily mileage log table with expandable trip legs.
 */

import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Gauge, Home } from 'lucide-react';
import { PageSpinner } from '../../../../components/ui/Spinner';
import { EmptyState } from '../../../../components/ui/EmptyState';
import { Badge } from '../../../../components/ui/Badge';
import { getMileageLogs } from '../../../../api/vehicles';
import type { MileageLog } from '../../../../lib/types';


export function MileageTab({ vehicleId }: { vehicleId: number }) {
  const { data: logs, isLoading } = useQuery({
    queryKey: ['vehicle-mileage', vehicleId],
    queryFn: () => getMileageLogs(vehicleId, { limit: 30 }),
    staleTime: 15_000,
  });

  if (isLoading) return <PageSpinner label="Loading mileage..." />;

  if (!logs || logs.length === 0) {
    return (
      <EmptyState
        icon={<Gauge className="h-12 w-12" />}
        title="No Mileage Logs"
        description="Daily mileage readings will appear here once logged."
      />
    );
  }

  return (
    <div className="space-y-3">
      <p className="text-xs text-gray-500 dark:text-gray-400">
        Showing last {logs.length} entries
      </p>

      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-border text-left text-xs text-gray-500 dark:text-gray-400">
              <th className="pb-2 font-medium">Date</th>
              <th className="pb-2 font-medium">Driver</th>
              <th className="pb-2 font-medium text-right">Start</th>
              <th className="pb-2 font-medium text-right">End</th>
              <th className="pb-2 font-medium text-right">Total</th>
              <th className="pb-2 font-medium text-center">Take-Home</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-border">
            {logs.map((log) => (
              <MileageLogRow key={log.id} log={log} />
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}


function MileageLogRow({ log }: { log: MileageLog }) {
  const [expanded, setExpanded] = useState(false);

  return (
    <>
      <tr
        className="cursor-pointer hover:bg-gray-50 dark:hover:bg-gray-800/50 transition-colors"
        onClick={() => setExpanded(!expanded)}
      >
        <td className="py-2 text-gray-900 dark:text-gray-100">{log.log_date}</td>
        <td className="py-2 text-gray-500 dark:text-gray-400">{log.driver_name ?? '—'}</td>
        <td className="py-2 text-right font-mono">{log.odometer_start?.toLocaleString() ?? '—'}</td>
        <td className="py-2 text-right font-mono">{log.odometer_end?.toLocaleString() ?? '—'}</td>
        <td className="py-2 text-right font-mono font-medium">
          {log.total_miles?.toLocaleString() ?? '—'} mi
        </td>
        <td className="py-2 text-center">
          {log.is_take_home_day ? (
            <Home className="h-3.5 w-3.5 text-blue-500 inline" />
          ) : (
            <span className="text-gray-300 dark:text-gray-600">—</span>
          )}
        </td>
      </tr>
      {expanded && log.trip_legs && log.trip_legs.length > 0 && (
        <tr>
          <td colSpan={6} className="pb-3 pt-0">
            <div className="ml-4 pl-3 border-l-2 border-blue-200 dark:border-blue-800 space-y-1">
              {log.trip_legs.map((leg, i) => (
                <div key={leg.id ?? i} className="flex items-center gap-3 text-xs text-gray-500 dark:text-gray-400">
                  <span className="capitalize font-medium min-w-[100px]">
                    {leg.leg_type.replace(/_/g, ' ')}
                  </span>
                  <span>{leg.from_label ?? '?'} → {leg.to_label ?? '?'}</span>
                  <span className="font-mono">{leg.actual_miles ?? leg.estimated_miles ?? '—'} mi</span>
                  {leg.is_billable && (
                    <Badge variant="success">billable</Badge>
                  )}
                </div>
              ))}
            </div>
          </td>
        </tr>
      )}
      {expanded && (!log.trip_legs || log.trip_legs.length === 0) && (
        <tr>
          <td colSpan={6} className="pb-2 pt-0">
            <p className="text-xs text-gray-400 dark:text-gray-500 ml-4 italic">
              No trip legs recorded{log.notes ? ` — ${log.notes}` : ''}
            </p>
          </td>
        </tr>
      )}
    </>
  );
}
