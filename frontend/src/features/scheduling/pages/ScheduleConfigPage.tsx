/**
 * ScheduleConfigPage — configure employee default weekly schedules.
 *
 * Select an employee → view/edit their 7-day default schedule grid.
 * Each day row has: working-day toggle, start time, end time, notes.
 * "Initialize" button sets Mon-Fri 07:00-15:30 as a starting template.
 */

import { useState, useEffect } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Settings, Clock, RotateCcw, Save, User, Check,
} from 'lucide-react';
import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { Badge } from '../../../components/ui/Badge';
import { Button } from '../../../components/ui/Button';
import { Input } from '../../../components/ui/Input';
import { Card } from '../../../components/ui/Card';
import { useAuthStore } from '../../../stores/auth-store';
import { PERMISSIONS } from '../../../lib/constants';
import {
  getDefaultSchedule,
  setDefaultSchedule,
  initDefaultSchedule,
  listShiftPatterns,
  applyShiftPatternToUser,
} from '../../../api/scheduling';
import { getEmployees } from '../../../api/people';
import { toast } from '../../../lib/toast';
import type {
  DefaultScheduleResponse, DefaultScheduleDay, EmployeeListItem,
  ShiftPatternResponse,
} from '../../../lib/types';


// ── Constants ─────────────────────────────────────────────────────

const DAY_NAMES = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const DAY_NAMES_SHORT = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];


// ── Build editable state from API response ────────────────────────

function buildDayState(response: DefaultScheduleResponse[]): DefaultScheduleDay[] {
  // Ensure we always have 7 days (0-6), filling gaps with defaults
  const map = new Map(response.map(d => [d.day_of_week, d]));
  return Array.from({ length: 7 }, (_, i) => {
    const existing = map.get(i);
    if (existing) {
      return {
        day_of_week: i,
        start_time: existing.start_time,
        end_time: existing.end_time,
        is_working_day: existing.is_working_day,
        notes: existing.notes,
      };
    }
    // Default: non-working
    return {
      day_of_week: i,
      start_time: '07:00',
      end_time: '15:30',
      is_working_day: false,
      notes: null,
    };
  });
}


// ═══════════════════════════════════════════════════════════════════
// MAIN PAGE
// ═══════════════════════════════════════════════════════════════════

export function ScheduleConfigPage() {
  const queryClient = useQueryClient();
  const { hasPermission } = useAuthStore();
  const canManage = hasPermission(PERMISSIONS.MANAGE_SCHEDULE);

  // ── Employee selector ────────────────────────────────────────────
  const [selectedUserId, setSelectedUserId] = useState<number | null>(null);
  const [search, setSearch] = useState('');

  const { data: employeesData } = useQuery({
    queryKey: ['employees', 'schedule-config', search],
    queryFn: () => getEmployees({ search, is_active: true, page: 1, page_size: 200 }),
    staleTime: 60_000,
  });

  const employees = employeesData?.items ?? [];

  // ── Schedule data ────────────────────────────────────────────────
  const { data: scheduleData, isLoading: scheduleLoading } = useQuery({
    queryKey: ['default-schedule', selectedUserId],
    queryFn: () => getDefaultSchedule(selectedUserId!),
    enabled: !!selectedUserId,
    staleTime: 30_000,
  });

  // ── Editable state ───────────────────────────────────────────────
  const [days, setDays] = useState<DefaultScheduleDay[]>([]);
  const [dirty, setDirty] = useState(false);

  // Sync when data loads
  useEffect(() => {
    if (scheduleData) {
      setDays(buildDayState(scheduleData));
      setDirty(false);
    }
  }, [scheduleData]);

  // ── Mutations ────────────────────────────────────────────────────
  const saveMut = useMutation({
    mutationFn: () => setDefaultSchedule(selectedUserId!, { days }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['default-schedule', selectedUserId] });
      setDirty(false);
    },
  });

  const initMut = useMutation({
    mutationFn: () => initDefaultSchedule(selectedUserId!),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['default-schedule', selectedUserId] });
    },
  });

  // ── Shift Patterns ────────────────────────────────────────────
  const { data: shiftPatterns } = useQuery({
    queryKey: ['shift-patterns'],
    queryFn: () => listShiftPatterns(),
    staleTime: 120_000,
  });

  const applyPatternMut = useMutation({
    mutationFn: (patternId: number) =>
      applyShiftPatternToUser(patternId, selectedUserId!),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['default-schedule', selectedUserId] });
      toast.success('Shift pattern applied');
    },
    onError: () => toast.error('Failed to apply shift pattern'),
  });

  // ── Day update helpers ───────────────────────────────────────────
  function updateDay(dayOfWeek: number, field: keyof DefaultScheduleDay, value: unknown) {
    setDays(prev => prev.map(d =>
      d.day_of_week === dayOfWeek ? { ...d, [field]: value } : d,
    ));
    setDirty(true);
  }

  const selectedEmployee = employees.find(e => e.id === selectedUserId);

  return (
    <div className="space-y-4">
      {/* ── Header ──────────────────────────────────────────────── */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div className="flex items-center gap-3">
          <Settings size={24} className="text-gray-600 dark:text-gray-400" />
          <div>
            <h1 className="text-xl font-bold text-gray-900 dark:text-white">
              Default Schedules
            </h1>
            <p className="text-sm text-gray-500 dark:text-gray-400">
              Configure weekly working hours for employees
            </p>
          </div>
        </div>

        {selectedUserId && canManage && (
          <div className="flex items-center gap-2">
            {/* Shift pattern quick-apply */}
            {shiftPatterns && shiftPatterns.length > 0 && (
              <select
                className="text-sm border border-gray-300 dark:border-gray-600 rounded-lg
                           bg-white dark:bg-gray-800 text-gray-700 dark:text-gray-300
                           px-2 py-1.5"
                value=""
                onChange={(e) => {
                  const id = Number(e.target.value);
                  if (id) applyPatternMut.mutate(id);
                }}
                disabled={applyPatternMut.isPending}
              >
                <option value="">Apply Pattern...</option>
                {shiftPatterns.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.name}
                  </option>
                ))}
              </select>
            )}
            <Button
              size="sm"
              variant="secondary"
              onClick={() => initMut.mutate()}
              disabled={initMut.isPending}
              title="Reset to Mon-Fri 07:00-15:30"
            >
              <RotateCcw size={14} />
              <span className="hidden sm:inline ml-1">Initialize</span>
            </Button>
            <Button
              size="sm"
              variant="primary"
              onClick={() => saveMut.mutate()}
              disabled={!dirty || saveMut.isPending}
            >
              <Save size={14} />
              <span className="hidden sm:inline ml-1">
                {saveMut.isPending ? 'Saving...' : 'Save Schedule'}
              </span>
            </Button>
          </div>
        )}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-4 gap-4">
        {/* ─── Employee list ──────────────────────────────────── */}
        <Card className="lg:col-span-1 p-4">
          <div className="mb-3">
            <Input
              placeholder="Search employees..."
              value={search}
              onChange={e => setSearch(e.target.value)}
              className="text-sm"
            />
          </div>

          <div className="space-y-1 max-h-[500px] overflow-y-auto">
            {employees.length === 0 ? (
              <div className="text-xs text-gray-400 dark:text-gray-500 text-center py-4">
                No employees found
              </div>
            ) : (
              employees.map(emp => (
                <button
                  key={emp.id}
                  onClick={() => setSelectedUserId(emp.id)}
                  className={`
                    w-full text-left p-2 rounded-lg text-sm transition-colors
                    ${selectedUserId === emp.id
                      ? 'bg-blue-50 dark:bg-blue-900/20 text-blue-700 dark:text-blue-300 font-medium'
                      : 'text-gray-700 dark:text-gray-300 hover:bg-gray-50 dark:hover:bg-gray-800'
                    }
                  `}
                >
                  <div className="flex items-center gap-2">
                    <User size={14} className="flex-shrink-0" />
                    <span className="truncate">{emp.display_name}</span>
                  </div>
                  {emp.hat_names?.[0] && (
                    <Badge variant="neutral" className="text-[10px] mt-0.5 ml-5">
                      {emp.hat_names[0]}
                    </Badge>
                  )}
                </button>
              ))
            )}
          </div>
        </Card>

        {/* ─── Schedule grid ─────────────────────────────────── */}
        <Card className="lg:col-span-3 p-4">
          {!selectedUserId ? (
            <EmptyState
              icon={User}
              title="Select an employee"
              description="Choose an employee from the list to view or edit their default schedule."
            />
          ) : scheduleLoading ? (
            <PageSpinner />
          ) : (
            <div>
              {/* Employee name */}
              <div className="flex items-center gap-2 mb-4">
                <h2 className="font-semibold text-gray-900 dark:text-white">
                  {selectedEmployee?.display_name ?? `Employee #${selectedUserId}`}
                </h2>
                {dirty && (
                  <Badge variant="warning" className="text-[10px]">Unsaved changes</Badge>
                )}
              </div>

              {/* Desktop: table layout */}
              <div className="hidden md:block">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b border-gray-200 dark:border-gray-700">
                      <th className="text-left py-2 px-2 text-gray-500 dark:text-gray-400 font-medium">Day</th>
                      <th className="text-center py-2 px-2 text-gray-500 dark:text-gray-400 font-medium w-20">Working</th>
                      <th className="text-left py-2 px-2 text-gray-500 dark:text-gray-400 font-medium w-32">Start</th>
                      <th className="text-left py-2 px-2 text-gray-500 dark:text-gray-400 font-medium w-32">End</th>
                      <th className="text-left py-2 px-2 text-gray-500 dark:text-gray-400 font-medium">Notes</th>
                    </tr>
                  </thead>
                  <tbody>
                    {days.map(day => (
                      <tr
                        key={day.day_of_week}
                        className={`
                          border-b border-gray-100 dark:border-gray-800
                          ${!day.is_working_day ? 'opacity-50' : ''}
                        `}
                      >
                        <td className="py-2 px-2 font-medium text-gray-900 dark:text-white">
                          {DAY_NAMES[day.day_of_week]}
                        </td>
                        <td className="py-2 px-2 text-center">
                          <button
                            onClick={() => updateDay(day.day_of_week, 'is_working_day', !day.is_working_day)}
                            disabled={!canManage}
                            className={`
                              w-8 h-5 rounded-full transition-colors relative
                              ${day.is_working_day
                                ? 'bg-blue-600'
                                : 'bg-gray-300 dark:bg-gray-600'
                              }
                            `}
                          >
                            <div className={`
                              absolute top-0.5 w-4 h-4 bg-white rounded-full shadow transition-transform
                              ${day.is_working_day ? 'translate-x-3.5' : 'translate-x-0.5'}
                            `} />
                          </button>
                        </td>
                        <td className="py-2 px-2">
                          <Input
                            type="time"
                            value={day.start_time}
                            onChange={e => updateDay(day.day_of_week, 'start_time', e.target.value)}
                            disabled={!day.is_working_day || !canManage}
                            className="text-sm !py-1"
                          />
                        </td>
                        <td className="py-2 px-2">
                          <Input
                            type="time"
                            value={day.end_time}
                            onChange={e => updateDay(day.day_of_week, 'end_time', e.target.value)}
                            disabled={!day.is_working_day || !canManage}
                            className="text-sm !py-1"
                          />
                        </td>
                        <td className="py-2 px-2">
                          <Input
                            value={day.notes ?? ''}
                            onChange={e => updateDay(day.day_of_week, 'notes', e.target.value || null)}
                            disabled={!canManage}
                            placeholder="—"
                            className="text-sm !py-1"
                          />
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>

              {/* Mobile: stacked cards */}
              <div className="md:hidden space-y-2">
                {days.map(day => (
                  <div
                    key={day.day_of_week}
                    className={`
                      border border-gray-200 dark:border-gray-700 rounded-lg p-3
                      ${!day.is_working_day ? 'opacity-50' : ''}
                    `}
                  >
                    <div className="flex items-center justify-between mb-2">
                      <span className="font-medium text-sm text-gray-900 dark:text-white">
                        {DAY_NAMES_SHORT[day.day_of_week]}
                      </span>
                      <button
                        onClick={() => updateDay(day.day_of_week, 'is_working_day', !day.is_working_day)}
                        disabled={!canManage}
                        className={`
                          w-10 h-6 rounded-full transition-colors relative
                          ${day.is_working_day
                            ? 'bg-blue-600'
                            : 'bg-gray-300 dark:bg-gray-600'
                          }
                        `}
                      >
                        <div className={`
                          absolute top-0.5 w-5 h-5 bg-white rounded-full shadow transition-transform
                          ${day.is_working_day ? 'translate-x-4.5' : 'translate-x-0.5'}
                        `} />
                      </button>
                    </div>

                    {day.is_working_day && (
                      <div className="grid grid-cols-2 gap-2">
                        <div>
                          <label className="text-[10px] text-gray-500 dark:text-gray-400">Start</label>
                          <Input
                            type="time"
                            value={day.start_time}
                            onChange={e => updateDay(day.day_of_week, 'start_time', e.target.value)}
                            disabled={!canManage}
                            className="text-sm !py-1"
                          />
                        </div>
                        <div>
                          <label className="text-[10px] text-gray-500 dark:text-gray-400">End</label>
                          <Input
                            type="time"
                            value={day.end_time}
                            onChange={e => updateDay(day.day_of_week, 'end_time', e.target.value)}
                            disabled={!canManage}
                            className="text-sm !py-1"
                          />
                        </div>
                      </div>
                    )}
                  </div>
                ))}
              </div>

              {/* Working hours summary */}
              <div className="mt-4 pt-3 border-t border-gray-200 dark:border-gray-700">
                <div className="flex items-center gap-2 text-sm text-gray-500 dark:text-gray-400">
                  <Clock size={14} />
                  <span>
                    {days.filter(d => d.is_working_day).length} working days/week
                  </span>
                  {days.filter(d => d.is_working_day).length > 0 && (
                    <>
                      <span className="text-gray-300 dark:text-gray-600">&middot;</span>
                      <span>
                        ~{(() => {
                          let totalMinutes = 0;
                          for (const d of days) {
                            if (!d.is_working_day) continue;
                            const [sh, sm] = d.start_time.split(':').map(Number);
                            const [eh, em] = d.end_time.split(':').map(Number);
                            totalMinutes += (eh * 60 + em) - (sh * 60 + sm);
                          }
                          return (totalMinutes / 60).toFixed(1);
                        })()} hours/week
                      </span>
                    </>
                  )}
                </div>
              </div>
            </div>
          )}
        </Card>
      </div>
    </div>
  );
}
