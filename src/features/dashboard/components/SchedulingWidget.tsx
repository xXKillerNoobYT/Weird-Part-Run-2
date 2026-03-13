/**
 * SchedulingWidget — dashboard card showing today's dispatches,
 * upcoming time-off, and the current user's PTO balance.
 */

import { useQuery } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import {
  MapPin, Sun, Clock, Users, Wallet, ChevronRight,
} from 'lucide-react';
import { Card, CardHeader } from '../../../components/ui/Card';
import { Badge } from '../../../components/ui/Badge';
import { useAuthStore } from '../../../stores/auth-store';
import { PERMISSIONS } from '../../../lib/constants';
import { getCalendarData, getPtoBalance } from '../../../api/scheduling';

/** Get ISO date string for a Date */
function isoDate(d: Date) {
  return d.toISOString().slice(0, 10);
}

export function SchedulingWidget() {
  const navigate = useNavigate();
  const { user, hasPermission } = useAuthStore();
  const canViewSchedule = hasPermission(PERMISSIONS.VIEW_SCHEDULE);

  // Fetch this week's calendar data (today + 6 more days)
  const today = new Date();
  const weekEnd = new Date(today);
  weekEnd.setDate(weekEnd.getDate() + 6);

  const { data: calendar } = useQuery({
    queryKey: ['dashboard-calendar', isoDate(today), isoDate(weekEnd)],
    queryFn: () => getCalendarData(isoDate(today), isoDate(weekEnd)),
    enabled: canViewSchedule,
    staleTime: 60_000,
  });

  // Fetch PTO balance for the current user
  const { data: ptoBalance } = useQuery({
    queryKey: ['pto', 'balance', user?.id],
    queryFn: () => getPtoBalance(user!.id),
    enabled: !!user?.id,
    staleTime: 60_000,
  });

  if (!canViewSchedule) return null;

  // Split entries by type
  const allEntries = calendar?.entries ?? [];
  const todayStr = isoDate(today);
  const todayDispatches = allEntries.filter(
    e => e.entry_type === 'dispatch' && e.date === todayStr,
  );
  const upcomingTimeOff = allEntries.filter(
    e => e.entry_type === 'time_off',
  );

  return (
    <Card>
      <CardHeader
        title="Schedule Overview"
        subtitle="This week at a glance"
        action={
          <button
            onClick={() => navigate('/scheduling/calendar')}
            className="flex items-center gap-1 text-xs text-blue-600 dark:text-blue-400 hover:underline"
          >
            Full Calendar <ChevronRight size={12} />
          </button>
        }
      />

      <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
        {/* ── Today's Dispatches ─────────── */}
        <button
          onClick={() => navigate('/scheduling/calendar')}
          className="text-left p-3 rounded-lg border border-gray-200 dark:border-gray-700 hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors"
        >
          <div className="flex items-center gap-2 mb-2">
            <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-blue-50 dark:bg-blue-900/20">
              <MapPin size={16} className="text-blue-500" />
            </div>
            <div className="text-xs font-medium text-gray-500 dark:text-gray-400">
              Today's Dispatches
            </div>
          </div>
          <div className="text-2xl font-bold text-gray-900 dark:text-white">
            {todayDispatches.length}
          </div>
          {todayDispatches.length > 0 && (
            <div className="mt-1.5 space-y-1">
              {todayDispatches.slice(0, 3).map((d, i) => (
                <div key={i} className="flex items-center gap-1.5 text-xs text-gray-600 dark:text-gray-400 truncate">
                  <Users size={10} className="flex-shrink-0" />
                  <span className="truncate">{d.user_name ?? d.gc_name ?? 'Unassigned'}</span>
                  {d.job_name && (
                    <span className="text-gray-400 dark:text-gray-500 truncate">→ {d.job_name}</span>
                  )}
                </div>
              ))}
              {todayDispatches.length > 3 && (
                <div className="text-[10px] text-gray-400">+{todayDispatches.length - 3} more</div>
              )}
            </div>
          )}
        </button>

        {/* ── Upcoming Time Off ──────────── */}
        <button
          onClick={() => navigate('/scheduling/time-off')}
          className="text-left p-3 rounded-lg border border-gray-200 dark:border-gray-700 hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors"
        >
          <div className="flex items-center gap-2 mb-2">
            <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-amber-50 dark:bg-amber-900/20">
              <Sun size={16} className="text-amber-500" />
            </div>
            <div className="text-xs font-medium text-gray-500 dark:text-gray-400">
              Time Off This Week
            </div>
          </div>
          <div className="text-2xl font-bold text-gray-900 dark:text-white">
            {upcomingTimeOff.length}
          </div>
          {upcomingTimeOff.length > 0 && (
            <div className="mt-1.5 space-y-1">
              {upcomingTimeOff.slice(0, 3).map((t, i) => (
                <div key={i} className="flex items-center gap-1.5 text-xs text-gray-600 dark:text-gray-400 truncate">
                  <Clock size={10} className="flex-shrink-0" />
                  <span className="truncate">{t.user_name ?? 'Employee'}</span>
                  <Badge variant="neutral" className="text-[9px]">{t.date}</Badge>
                </div>
              ))}
              {upcomingTimeOff.length > 3 && (
                <div className="text-[10px] text-gray-400">+{upcomingTimeOff.length - 3} more</div>
              )}
            </div>
          )}
        </button>

        {/* ── PTO Balance ───────────────── */}
        <button
          onClick={() => navigate('/scheduling/time-off')}
          className="text-left p-3 rounded-lg border border-gray-200 dark:border-gray-700 hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors"
        >
          <div className="flex items-center gap-2 mb-2">
            <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-emerald-50 dark:bg-emerald-900/20">
              <Wallet size={16} className="text-emerald-500" />
            </div>
            <div className="text-xs font-medium text-gray-500 dark:text-gray-400">
              My PTO Balance
            </div>
          </div>
          <div className="text-2xl font-bold text-gray-900 dark:text-white">
            {ptoBalance ? `${ptoBalance.current_balance.toFixed(1)}` : '—'}
            <span className="text-sm font-normal text-gray-500 dark:text-gray-400 ml-1">hrs</span>
          </div>
          {ptoBalance?.policy && (
            <div className="mt-1.5 text-xs text-gray-500 dark:text-gray-400">
              {ptoBalance.policy.policy_name} · {ptoBalance.policy.accrual_rate} hrs/{ptoBalance.policy.accrual_period}
            </div>
          )}
          {ptoBalance && (
            <div className="flex items-center gap-3 mt-1">
              <span className="text-[10px] text-emerald-600 dark:text-emerald-400">
                +{ptoBalance.accrued_ytd.toFixed(1)} YTD
              </span>
              <span className="text-[10px] text-red-600 dark:text-red-400">
                -{ptoBalance.used_ytd.toFixed(1)} used
              </span>
            </div>
          )}
        </button>
      </div>
    </Card>
  );
}
