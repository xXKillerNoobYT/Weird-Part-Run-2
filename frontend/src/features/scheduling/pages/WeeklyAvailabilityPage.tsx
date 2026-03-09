/**
 * WeeklyAvailabilityPage — visual grid showing employee availability across a week.
 *
 * Rows = employees, columns = days of the selected week.
 * Each cell shows: available (green), dispatched (blue), time-off (orange), or
 * dispatched + time-off (red conflict).
 *
 * Week navigation: prev/next week arrows plus date picker.
 */

import { useState, useMemo } from 'react';
import { useQuery } from '@tanstack/react-query';
import {
  Calendar, ChevronLeft, ChevronRight, Users,
} from 'lucide-react';
import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { Button } from '../../../components/ui/Button';
import { Card } from '../../../components/ui/Card';
import { getWeeklyAvailability } from '../../../api/scheduling';



const DAY_SHORT = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

function getMonday(d: Date): Date {
  const day = d.getDay();
  const diff = d.getDate() - day + (day === 0 ? -6 : 1);
  return new Date(d.getFullYear(), d.getMonth(), diff);
}

function addDays(d: Date, n: number): Date {
  const r = new Date(d);
  r.setDate(r.getDate() + n);
  return r;
}

function fmt(d: Date): string {
  return d.toISOString().slice(0, 10);
}

function fmtShort(dateStr: string): string {
  const d = new Date(dateStr + 'T00:00:00');
  return `${d.getMonth() + 1}/${d.getDate()}`;
}


export function WeeklyAvailabilityPage() {
  const [weekStart, setWeekStart] = useState(() => getMonday(new Date()));

  const dateFrom = fmt(weekStart);
  const dateTo = fmt(addDays(weekStart, 6));

  const { data: availability, isLoading } = useQuery({
    queryKey: ['weekly-availability', dateFrom, dateTo],
    queryFn: () => getWeeklyAvailability(dateFrom, dateTo),
    staleTime: 30_000,
  });

  const dates = useMemo(() => {
    const result: string[] = [];
    for (let i = 0; i < 7; i++) {
      result.push(fmt(addDays(weekStart, i)));
    }
    return result;
  }, [weekStart]);

  // Summary stats
  const summary = useMemo(() => {
    if (!availability) return null;
    let totalAvailable = 0;
    let totalDispatched = 0;
    let totalOff = 0;
    for (const emp of availability) {
      for (const day of emp.days) {
        if (day.available) totalAvailable++;
        if (day.dispatches > 0) totalDispatched++;
        if (day.time_off) totalOff++;
      }
    }
    return { totalAvailable, totalDispatched, totalOff, employees: availability.length };
  }, [availability]);

  if (isLoading) return <PageSpinner />;

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div className="flex items-center gap-3">
          <Calendar size={24} className="text-gray-600 dark:text-gray-400" />
          <div>
            <h1 className="text-xl font-bold text-gray-900 dark:text-white">
              Weekly Availability
            </h1>
            <p className="text-sm text-gray-500 dark:text-gray-400">
              Employee dispatch and time-off overview
            </p>
          </div>
        </div>

        {/* Week navigation */}
        <div className="flex items-center gap-2">
          <Button
            size="sm"
            variant="ghost"
            onClick={() => setWeekStart(addDays(weekStart, -7))}
          >
            <ChevronLeft size={16} />
          </Button>
          <button
            onClick={() => setWeekStart(getMonday(new Date()))}
            className="text-sm font-medium text-gray-700 dark:text-gray-300
                       px-3 py-1 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-800"
          >
            This Week
          </button>
          <Button
            size="sm"
            variant="ghost"
            onClick={() => setWeekStart(addDays(weekStart, 7))}
          >
            <ChevronRight size={16} />
          </Button>
          <input
            type="date"
            value={dateFrom}
            onChange={(e) => {
              if (e.target.value) setWeekStart(getMonday(new Date(e.target.value + 'T00:00:00')));
            }}
            className="text-sm border border-gray-300 dark:border-gray-600 rounded-lg
                       bg-white dark:bg-gray-800 text-gray-700 dark:text-gray-300
                       px-2 py-1"
          />
        </div>
      </div>

      {/* Summary cards */}
      {summary && (
        <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
          <Card className="p-3 text-center">
            <div className="text-2xl font-bold text-gray-900 dark:text-white">
              {summary.employees}
            </div>
            <div className="text-xs text-gray-500 dark:text-gray-400">Employees</div>
          </Card>
          <Card className="p-3 text-center">
            <div className="text-2xl font-bold text-green-600">{summary.totalAvailable}</div>
            <div className="text-xs text-gray-500 dark:text-gray-400">Available Slots</div>
          </Card>
          <Card className="p-3 text-center">
            <div className="text-2xl font-bold text-blue-600">{summary.totalDispatched}</div>
            <div className="text-xs text-gray-500 dark:text-gray-400">Dispatched</div>
          </Card>
          <Card className="p-3 text-center">
            <div className="text-2xl font-bold text-orange-500">{summary.totalOff}</div>
            <div className="text-xs text-gray-500 dark:text-gray-400">Time Off</div>
          </Card>
        </div>
      )}

      {/* Legend */}
      <div className="flex items-center gap-4 text-xs text-gray-500 dark:text-gray-400">
        <div className="flex items-center gap-1">
          <div className="w-3 h-3 rounded bg-green-100 dark:bg-green-900/30 border border-green-300 dark:border-green-700" />
          Available
        </div>
        <div className="flex items-center gap-1">
          <div className="w-3 h-3 rounded bg-blue-100 dark:bg-blue-900/30 border border-blue-300 dark:border-blue-700" />
          Dispatched
        </div>
        <div className="flex items-center gap-1">
          <div className="w-3 h-3 rounded bg-orange-100 dark:bg-orange-900/30 border border-orange-300 dark:border-orange-700" />
          Time Off
        </div>
      </div>

      {/* Availability grid */}
      {!availability || availability.length === 0 ? (
        <EmptyState
          icon={<Users className="h-12 w-12" />}
          title="No employees"
          description="No active employees found for this period."
        />
      ) : (
        <Card className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-gray-200 dark:border-gray-700">
                <th className="text-left py-2 px-3 text-gray-500 dark:text-gray-400 font-medium
                               min-w-[150px] sticky left-0 bg-white dark:bg-gray-900 z-10">
                  Employee
                </th>
                {dates.map((d, _i) => (
                  <th
                    key={d}
                    className="text-center py-2 px-2 text-gray-500 dark:text-gray-400 font-medium min-w-[70px]"
                  >
                    <div>{DAY_SHORT[(new Date(d + 'T00:00:00')).getDay()]}</div>
                    <div className="text-[10px]">{fmtShort(d)}</div>
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {availability.map(emp => (
                <tr
                  key={emp.user_id}
                  className="border-b border-gray-100 dark:border-gray-800 hover:bg-gray-50 dark:hover:bg-gray-800/50"
                >
                  <td className="py-2 px-3 font-medium text-gray-900 dark:text-white truncate
                                 sticky left-0 bg-white dark:bg-gray-900 z-10">
                    {emp.user_name}
                  </td>
                  {emp.days.map(day => (
                    <td key={day.date} className="py-2 px-2 text-center">
                      <AvailabilityCell
                        dispatches={day.dispatches}
                        timeOff={day.time_off}
                        available={day.available}
                      />
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </Card>
      )}
    </div>
  );
}


function AvailabilityCell({
  dispatches, timeOff, available,
}: {
  dispatches: number;
  timeOff: boolean;
  available: boolean;
}) {
  if (timeOff) {
    return (
      <div className="inline-flex items-center justify-center w-8 h-8 rounded-lg
                      bg-orange-100 text-orange-700 dark:bg-orange-900/30 dark:text-orange-300
                      text-xs font-medium" title="Time off">
        OFF
      </div>
    );
  }
  if (dispatches > 0) {
    return (
      <div className="inline-flex items-center justify-center w-8 h-8 rounded-lg
                      bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-300
                      text-xs font-bold" title={`${dispatches} dispatch(es)`}>
        {dispatches}
      </div>
    );
  }
  if (available) {
    return (
      <div className="inline-flex items-center justify-center w-8 h-8 rounded-lg
                      bg-green-50 text-green-500 dark:bg-green-900/20 dark:text-green-400
                      text-xs" title="Available">
        ✓
      </div>
    );
  }
  return (
    <div className="inline-flex items-center justify-center w-8 h-8 rounded-lg
                    bg-gray-50 text-gray-300 dark:bg-gray-800 dark:text-gray-600
                    text-xs" title="Not working">
      —
    </div>
  );
}
