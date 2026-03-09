/**
 * ScheduleCalendarPage — unified week view showing dispatches, time off,
 * and subcontractor schedules on a single calendar grid.
 *
 * Rows = dates in selected week, entries = color-coded cards.
 * Navigation: prev/next week arrows + "Today" button.
 * Mobile: stacked daily list view.
 */

import { useState, useMemo } from 'react';
import { useQuery } from '@tanstack/react-query';
import {
  CalendarDays, ChevronLeft, ChevronRight, Briefcase,
  HardHat, Sun, Filter,
} from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { PageSpinner } from '../../../components/ui/Spinner';
import { Badge } from '../../../components/ui/Badge';
import { Button } from '../../../components/ui/Button';
import { getCalendarData } from '../../../api/scheduling';
import type { CalendarEntry, CalendarEntryType } from '../../../lib/types';


// ── Date helpers ──────────────────────────────────────────────────

/** Get Monday of the week containing `date` */
function getMonday(date: Date): Date {
  const d = new Date(date);
  const day = d.getDay(); // 0=Sun
  const diff = day === 0 ? -6 : 1 - day;
  d.setDate(d.getDate() + diff);
  d.setHours(0, 0, 0, 0);
  return d;
}

function addDays(date: Date, n: number): Date {
  const d = new Date(date);
  d.setDate(d.getDate() + n);
  return d;
}

function isoDate(d: Date): string {
  return d.toISOString().slice(0, 10);
}

function isToday(d: Date): boolean {
  const today = new Date();
  return isoDate(d) === isoDate(today);
}

const DAY_NAMES = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const DAY_NAMES_FULL = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];


// ── Entry type styling ────────────────────────────────────────────

const ENTRY_TYPE_CONFIG: Record<CalendarEntryType, {
  bg: string;
  text: string;
  icon: typeof Briefcase;
  label: string;
}> = {
  dispatch: {
    bg: 'bg-blue-100 dark:bg-blue-900/30 border-blue-300 dark:border-blue-700',
    text: 'text-blue-700 dark:text-blue-300',
    icon: Briefcase,
    label: 'Dispatch',
  },
  time_off: {
    bg: 'bg-amber-100 dark:bg-amber-900/30 border-amber-300 dark:border-amber-700',
    text: 'text-amber-700 dark:text-amber-300',
    icon: Sun,
    label: 'Time Off',
  },
  sub_schedule: {
    bg: 'bg-purple-100 dark:bg-purple-900/30 border-purple-300 dark:border-purple-700',
    text: 'text-purple-700 dark:text-purple-300',
    icon: HardHat,
    label: 'Subcontractor',
  },
};

const STATUS_BADGE: Record<string, 'success' | 'warning' | 'danger' | 'info' | 'neutral'> = {
  completed: 'success',
  on_site: 'info',
  confirmed: 'info',
  scheduled: 'neutral',
  cancelled: 'danger',
  no_show: 'danger',
  approved: 'success',
  pending: 'warning',
  // time off specific
  vacation: 'info',
  sick: 'warning',
  time_off: 'neutral',
};


// ── Calendar Entry Card ───────────────────────────────────────────

// Role-specific overrides for dispatch entries (supervisor = amber, lead = indigo)
const ROLE_OVERRIDES: Record<string, { bg: string; text: string }> = {
  supervisor: {
    bg: 'bg-amber-100 dark:bg-amber-900/30 border-amber-300 dark:border-amber-700',
    text: 'text-amber-700 dark:text-amber-300',
  },
  lead: {
    bg: 'bg-indigo-100 dark:bg-indigo-900/30 border-indigo-300 dark:border-indigo-700',
    text: 'text-indigo-700 dark:text-indigo-300',
  },
};

function EntryCard({ entry }: { entry: CalendarEntry }) {
  const navigate = useNavigate();
  const baseConfig = ENTRY_TYPE_CONFIG[entry.entry_type];
  const Icon = baseConfig.icon;

  // Use role-specific colors for dispatch entries with special roles
  const roleOverride = entry.entry_type === 'dispatch' && entry.role_on_job
    ? ROLE_OVERRIDES[entry.role_on_job]
    : undefined;
  const bg = roleOverride?.bg ?? baseConfig.bg;
  const text = roleOverride?.text ?? baseConfig.text;

  function handleClick() {
    if (entry.entry_type === 'dispatch' && entry.job_id) {
      navigate(`/jobs/${entry.job_id}`);
    }
  }

  return (
    <button
      onClick={handleClick}
      disabled={entry.entry_type !== 'dispatch'}
      className={`
        w-full text-left p-2 rounded-lg border text-xs
        ${bg}
        ${entry.entry_type === 'dispatch' ? 'cursor-pointer hover:shadow-sm' : 'cursor-default'}
        transition-shadow
      `}
    >
      <div className="flex items-center gap-1.5 mb-0.5">
        <Icon size={12} className={text} />
        <span className={`font-medium truncate ${text}`}>
          {entry.label}
        </span>
        {/* Role badge for non-worker dispatch entries */}
        {entry.entry_type === 'dispatch' && entry.role_on_job && entry.role_on_job !== 'worker' && (
          <span className={`text-[10px] px-1 py-0.5 rounded font-medium flex-shrink-0 ${text} opacity-75`}>
            {entry.role_on_job}
          </span>
        )}
      </div>

      {/* Person or GC name */}
      {entry.user_name && (
        <div className="text-gray-600 dark:text-gray-400 truncate">
          {entry.user_name}
        </div>
      )}
      {entry.gc_name && (
        <div className="text-gray-600 dark:text-gray-400 truncate">
          {entry.gc_name}
        </div>
      )}

      {/* Status badge */}
      {entry.status && (
        <Badge
          variant={STATUS_BADGE[entry.status] ?? 'neutral'}
          className="mt-1 text-[10px]"
        >
          {entry.status.replace(/_/g, ' ')}
        </Badge>
      )}
    </button>
  );
}


// ═══════════════════════════════════════════════════════════════════
// MAIN PAGE
// ═══════════════════════════════════════════════════════════════════

export function ScheduleCalendarPage() {
  // ── State ────────────────────────────────────────────────────────
  const [weekStart, setWeekStart] = useState(() => getMonday(new Date()));
  const [typeFilter, setTypeFilter] = useState<CalendarEntryType | 'all'>('all');

  // 3-week span: 21 days total
  const spanEnd = addDays(weekStart, 20);

  // Memoize weekDates so the reference is stable (changes only when weekStart changes)
  const weekDates = useMemo(
    () => Array.from({ length: 21 }, (_, i) => addDays(weekStart, i)),
    [weekStart],
  );

  // Split into 3 groups of 7 for the desktop grid
  const weeks = useMemo(() => [
    weekDates.slice(0, 7),
    weekDates.slice(7, 14),
    weekDates.slice(14, 21),
  ], [weekDates]);

  // ── Data ─────────────────────────────────────────────────────────
  const { data: calendar, isLoading } = useQuery({
    queryKey: ['calendar', isoDate(weekStart), isoDate(spanEnd)],
    queryFn: () => getCalendarData(isoDate(weekStart), isoDate(spanEnd)),
    staleTime: 30_000,
  });

  // Group entries by date
  const entriesByDate = useMemo(() => {
    const map = new Map<string, CalendarEntry[]>();
    weekDates.forEach(d => map.set(isoDate(d), []));
    if (calendar?.entries) {
      for (const entry of calendar.entries) {
        if (typeFilter !== 'all' && entry.entry_type !== typeFilter) continue;
        const bucket = map.get(entry.date);
        if (bucket) bucket.push(entry);
      }
    }
    return map;
  }, [calendar, weekDates, typeFilter]);

  // ── Week nav ─────────────────────────────────────────────────────
  function prevWeek() { setWeekStart(addDays(weekStart, -7)); }
  function nextWeek() { setWeekStart(addDays(weekStart, 7)); }
  function goToday() { setWeekStart(getMonday(new Date())); }

  // ── Loading ──────────────────────────────────────────────────────
  if (isLoading) return <PageSpinner />;

  const totalEntries = calendar?.entries?.length ?? 0;
  const weekLabel = `${weekStart.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })} – ${spanEnd.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })} (3 weeks)`;

  return (
    <div className="space-y-4">
      {/* ── Header ──────────────────────────────────────────────── */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div className="flex items-center gap-3">
          <CalendarDays size={24} className="text-blue-600 dark:text-blue-400" />
          <div>
            <h1 className="text-xl font-bold text-gray-900 dark:text-white">
              Schedule Calendar
            </h1>
            <p className="text-sm text-gray-500 dark:text-gray-400">
              {weekLabel} &middot; {totalEntries} entries
            </p>
          </div>
        </div>

        {/* Week navigation */}
        <div className="flex items-center gap-2">
          <Button size="sm" variant="secondary" onClick={prevWeek}>
            <ChevronLeft size={16} />
          </Button>
          <Button size="sm" variant="secondary" onClick={goToday}>
            Today
          </Button>
          <Button size="sm" variant="secondary" onClick={nextWeek}>
            <ChevronRight size={16} />
          </Button>
        </div>
      </div>

      {/* ── Type filter pills ────────────────────────────────────── */}
      <div className="flex items-center gap-2 overflow-x-auto pb-1">
        <Filter size={14} className="text-gray-400 dark:text-gray-500 flex-shrink-0" />
        {(['all', 'dispatch', 'time_off', 'sub_schedule'] as const).map(t => (
          <button
            key={t}
            onClick={() => setTypeFilter(t)}
            className={`
              px-3 py-1 rounded-full text-xs font-medium whitespace-nowrap transition-colors
              ${typeFilter === t
                ? 'bg-blue-600 text-white'
                : 'bg-gray-100 dark:bg-gray-800 text-gray-600 dark:text-gray-400 hover:bg-gray-200 dark:hover:bg-gray-700'
              }
            `}
          >
            {t === 'all' ? 'All' : ENTRY_TYPE_CONFIG[t].label}
          </button>
        ))}
      </div>

      {/* ── Desktop: 3-week stacked grid ──────────────────────── */}
      <div className="hidden md:flex flex-col gap-2">
        {weeks.map((weekGroup, weekIdx) => (
          <div key={weekIdx} className="rounded-lg overflow-hidden border border-gray-200 dark:border-gray-700">
            {/* Week label bar */}
            <div className="px-3 py-1.5 bg-gray-50 dark:bg-gray-800 border-b border-gray-200 dark:border-gray-700">
              <span className="text-xs font-semibold text-gray-500 dark:text-gray-400 uppercase tracking-wide">
                Week {weekIdx + 1} &middot; {weekGroup[0].toLocaleDateString('en-US', { month: 'short', day: 'numeric' })} – {weekGroup[6].toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}
              </span>
            </div>
            <div className="grid grid-cols-7 gap-px bg-gray-200 dark:bg-gray-700">
              {weekGroup.map((d, i) => {
                const dateStr = isoDate(d);
                const entries = entriesByDate.get(dateStr) ?? [];
                const today = isToday(d);

                return (
                  <div
                    key={dateStr}
                    className={`
                      bg-white dark:bg-gray-900 min-h-[150px] p-2 flex flex-col
                      ${today ? 'ring-2 ring-inset ring-blue-500' : ''}
                    `}
                  >
                    {/* Day header */}
                    <div className="flex items-center justify-between mb-2">
                      <span className="text-xs font-medium text-gray-500 dark:text-gray-400">
                        {DAY_NAMES[i]}
                      </span>
                      <span className={`
                        text-sm font-semibold
                        ${today
                          ? 'bg-blue-600 text-white w-7 h-7 rounded-full flex items-center justify-center'
                          : 'text-gray-700 dark:text-gray-300'
                        }
                      `}>
                        {d.getDate()}
                      </span>
                    </div>

                    {/* Entries */}
                    <div className="flex-1 space-y-1 overflow-y-auto max-h-[200px]">
                      {entries.length === 0 && (
                        <div className="text-[10px] text-gray-400 dark:text-gray-600 text-center pt-4">
                          No entries
                        </div>
                      )}
                      {entries.map((entry, j) => (
                        <EntryCard key={`${entry.entry_type}-${entry.user_id ?? entry.gc_id}-${j}`} entry={entry} />
                      ))}
                    </div>
                  </div>
                );
              })}
            </div>
          </div>
        ))}
      </div>

      {/* ── Mobile: daily list ─────────────────────────────────── */}
      <div className="md:hidden space-y-4">
        {weekDates.map((d, i) => {
          const isWeekStart = i % 7 === 0;
          const dateStr = isoDate(d);
          const entries = entriesByDate.get(dateStr) ?? [];
          const today = isToday(d);

          return (
            <div key={dateStr}>
              {/* Week separator on mobile */}
              {isWeekStart && (
                <div className="text-xs font-semibold text-gray-400 dark:text-gray-500 uppercase tracking-wide px-2 pb-1 pt-1 border-b border-gray-100 dark:border-gray-800 mb-2">
                  Week {Math.floor(i / 7) + 1}
                </div>
              )}
              <div className={`
                flex items-center gap-2 mb-2 px-2 py-1 rounded-lg
                ${today ? 'bg-blue-50 dark:bg-blue-900/20' : ''}
              `}>
                <span className={`
                  text-sm font-bold
                  ${today ? 'text-blue-600 dark:text-blue-400' : 'text-gray-700 dark:text-gray-300'}
                `}>
                  {DAY_NAMES_FULL[i]}
                </span>
                <span className="text-sm text-gray-500 dark:text-gray-400">
                  {d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}
                </span>
                {entries.length > 0 && (
                  <Badge variant="neutral" className="text-[10px]">
                    {entries.length}
                  </Badge>
                )}
              </div>

              {entries.length === 0 ? (
                <div className="text-xs text-gray-400 dark:text-gray-600 px-2 py-3 text-center border border-dashed border-gray-200 dark:border-gray-700 rounded-lg">
                  No entries
                </div>
              ) : (
                <div className="space-y-1.5 px-1">
                  {entries.map((entry, j) => (
                    <EntryCard key={`${entry.entry_type}-${entry.user_id ?? entry.gc_id}-${j}`} entry={entry} />
                  ))}
                </div>
              )}
            </div>
          );
        })}
      </div>

      {/* ── Legend ──────────────────────────────────────────────── */}
      <div className="flex items-center gap-4 text-xs text-gray-500 dark:text-gray-400 pt-2">
        {Object.entries(ENTRY_TYPE_CONFIG).map(([key, cfg]) => {
          const Icon = cfg.icon;
          return (
            <div key={key} className="flex items-center gap-1.5">
              <div className={`w-3 h-3 rounded border ${cfg.bg}`} />
              <Icon size={12} className={cfg.text} />
              <span>{cfg.label}</span>
            </div>
          );
        })}
      </div>
    </div>
  );
}
