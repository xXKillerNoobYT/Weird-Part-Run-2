/**
 * BillingPaySettingsPage — configure billing cycles, pay periods,
 * and payroll export columns.
 *
 * Three sections:
 * 1. Billing Cycle — how jobs are billed (monthly, weekly, etc.)
 * 2. Pay Period — how employees are paid (weekly, biweekly, etc.)
 * 3. Payroll Columns — which columns appear in payroll CSV exports
 *
 * All three affect report generation, exports, and period filtering.
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Calendar, Clock, Columns3, Check, AlertCircle, RotateCcw,
  Plus, X, GripVertical,
} from 'lucide-react';
import {
  getBillingCycle,
  updateBillingCycle,
  getPayPeriod,
  updatePayPeriod,
  getPayrollColumns,
  updatePayrollColumns,
} from '../../../api/settings';
import type {
  BillingCycleSettings,
  PayPeriodSettings,
  PayrollColumnConfig,
} from '../../../api/settings';

// ── Constants ──────────────────────────────────────────────

const BILLING_CYCLE_OPTIONS = [
  { value: 'weekly', label: 'Weekly' },
  { value: 'biweekly', label: 'Bi-Weekly (Every 2 Weeks)' },
  { value: 'semi_monthly', label: 'Semi-Monthly (1st & 16th)' },
  { value: 'monthly', label: 'Monthly' },
  { value: 'quarterly', label: 'Quarterly' },
  { value: 'yearly', label: 'Yearly' },
];

const PAY_PERIOD_OPTIONS = [
  { value: 'weekly', label: 'Weekly' },
  { value: 'biweekly', label: 'Bi-Weekly (Every 2 Weeks)' },
  { value: 'semi_monthly', label: 'Semi-Monthly (1st & 16th)' },
  { value: 'monthly', label: 'Monthly' },
];

const WEEKDAY_OPTIONS = [
  { value: 1, label: 'Monday' },
  { value: 2, label: 'Tuesday' },
  { value: 3, label: 'Wednesday' },
  { value: 4, label: 'Thursday' },
  { value: 5, label: 'Friday' },
  { value: 6, label: 'Saturday' },
  { value: 7, label: 'Sunday' },
];

const DAY_OF_MONTH_OPTIONS = Array.from({ length: 28 }, (_, i) => ({
  value: i + 1,
  label: `${i + 1}${i === 0 ? 'st' : i === 1 ? 'nd' : i === 2 ? 'rd' : 'th'}`,
}));

const AVAILABLE_PAYROLL_COLUMNS = [
  'Employee ID',
  'Employee Name',
  'Period Start',
  'Period End',
  'Regular Hours',
  'Overtime Hours',
  'Total Hours',
  'Pay Rate',
  'Gross Pay',
  'Job Name',
  'Job Number',
  'Bill Rate Type',
];

const DEFAULT_BILLING: BillingCycleSettings = { cycle_type: 'monthly', start_day: 1 };
const DEFAULT_PAY: PayPeriodSettings = { period_type: 'weekly', start_day: 1 };
const DEFAULT_COLUMNS: PayrollColumnConfig = {
  columns: ['Employee ID', 'Employee Name', 'Period Start', 'Period End', 'Regular Hours', 'Overtime Hours', 'Total Hours', 'Pay Rate'],
};


// ── Main Component ─────────────────────────────────────────

export function BillingPaySettingsPage() {
  const queryClient = useQueryClient();
  const [saveSuccess, setSaveSuccess] = useState<string | null>(null);

  // ── Queries ──────────────────────────────────────────

  const billingQ = useQuery({
    queryKey: ['billing-cycle'],
    queryFn: getBillingCycle,
  });

  const payQ = useQuery({
    queryKey: ['pay-period'],
    queryFn: getPayPeriod,
  });

  const columnsQ = useQuery({
    queryKey: ['payroll-columns'],
    queryFn: getPayrollColumns,
  });

  // ── Local Form State ─────────────────────────────────

  const [billingForm, setBillingForm] = useState<BillingCycleSettings | null>(null);
  const [payForm, setPayForm] = useState<PayPeriodSettings | null>(null);
  const [columnsForm, setColumnsForm] = useState<PayrollColumnConfig | null>(null);
  const [newCol, setNewCol] = useState('');

  // Initialize form from server data
  const billing = billingForm ?? billingQ.data ?? DEFAULT_BILLING;
  if (!billingForm && billingQ.data) setBillingForm(billingQ.data);

  const pay = payForm ?? payQ.data ?? DEFAULT_PAY;
  if (!payForm && payQ.data) setPayForm(payQ.data);

  const columns = columnsForm ?? columnsQ.data ?? DEFAULT_COLUMNS;
  if (!columnsForm && columnsQ.data) setColumnsForm(columnsQ.data);

  // ── Mutations ────────────────────────────────────────

  const billingMut = useMutation({
    mutationFn: updateBillingCycle,
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: ['billing-cycle'] });
      setBillingForm(data);
      showSuccess('Billing cycle updated');
    },
  });

  const payMut = useMutation({
    mutationFn: updatePayPeriod,
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: ['pay-period'] });
      setPayForm(data);
      showSuccess('Pay period updated');
    },
  });

  const columnsMut = useMutation({
    mutationFn: updatePayrollColumns,
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: ['payroll-columns'] });
      setColumnsForm(data);
      showSuccess('Payroll columns updated');
    },
  });

  function showSuccess(msg: string) {
    setSaveSuccess(msg);
    setTimeout(() => setSaveSuccess(null), 3000);
  }

  // ── Helpers ──────────────────────────────────────────

  const isWeekBased = (type: string) => type === 'weekly' || type === 'biweekly';

  function addColumn() {
    if (!newCol || columns.columns.includes(newCol)) return;
    setColumnsForm({ columns: [...columns.columns, newCol] });
    setNewCol('');
  }

  function removeColumn(col: string) {
    setColumnsForm({ columns: columns.columns.filter((c) => c !== col) });
  }

  function moveColumn(idx: number, dir: -1 | 1) {
    const newCols = [...columns.columns];
    const target = idx + dir;
    if (target < 0 || target >= newCols.length) return;
    [newCols[idx], newCols[target]] = [newCols[target], newCols[idx]];
    setColumnsForm({ columns: newCols });
  }

  const billingDirty = billingForm && JSON.stringify(billingForm) !== JSON.stringify(billingQ.data);
  const payDirty = payForm && JSON.stringify(payForm) !== JSON.stringify(payQ.data);
  const columnsDirty = columnsForm && JSON.stringify(columnsForm) !== JSON.stringify(columnsQ.data);

  // ── Loading ──────────────────────────────────────────

  if (billingQ.isLoading || payQ.isLoading || columnsQ.isLoading) {
    return (
      <div className="flex items-center justify-center py-12">
        <div className="animate-spin w-6 h-6 border-2 border-blue-500 border-t-transparent rounded-full" />
      </div>
    );
  }

  // ── Render ───────────────────────────────────────────

  return (
    <div className="space-y-6 max-w-3xl">
      {/* Header */}
      <div>
        <h1 className="text-xl font-semibold text-gray-900 dark:text-gray-100">
          Billing & Payroll
        </h1>
        <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">
          Configure billing cycles, pay periods, and payroll export columns. These settings affect
          report generation, timesheet grouping, and bookkeeper exports.
        </p>
      </div>

      {/* Success Banner */}
      {saveSuccess && (
        <div className="flex items-center gap-2 p-3 bg-green-50 dark:bg-green-900/20 border border-green-200 dark:border-green-800 rounded-lg text-green-700 dark:text-green-300 text-sm">
          <Check className="w-4 h-4 shrink-0" />
          {saveSuccess}
        </div>
      )}

      {/* Error Banners */}
      {(billingMut.isError || payMut.isError || columnsMut.isError) && (
        <div className="flex items-center gap-2 p-3 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg text-red-700 dark:text-red-300 text-sm">
          <AlertCircle className="w-4 h-4 shrink-0" />
          Failed to save settings. Please try again.
        </div>
      )}

      {/* ══ Section 1: Billing Cycle ═══════════════════════ */}
      <div className="bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-xl p-5">
        <div className="flex items-center gap-2 mb-4">
          <Calendar className="w-5 h-5 text-blue-500" />
          <h2 className="text-base font-medium text-gray-900 dark:text-gray-100">
            Billing Cycle
          </h2>
        </div>
        <p className="text-sm text-gray-500 dark:text-gray-400 mb-4">
          How billing periods are computed for job cost rollups, profitability reports, 
          and bookkeeper exports. E.g., &quot;Monthly starting on the 1st.&quot;
        </p>

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          {/* Cycle Type */}
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              Cycle Type
            </label>
            <select
              value={billing.cycle_type}
              onChange={(e) => setBillingForm({ ...billing, cycle_type: e.target.value })}
              className="w-full px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100"
            >
              {BILLING_CYCLE_OPTIONS.map((opt) => (
                <option key={opt.value} value={opt.value}>{opt.label}</option>
              ))}
            </select>
          </div>

          {/* Start Day */}
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              {isWeekBased(billing.cycle_type) ? 'Start Day of Week' : 'Start Day of Month'}
            </label>
            <select
              value={billing.start_day}
              onChange={(e) => setBillingForm({ ...billing, start_day: parseInt(e.target.value) })}
              className="w-full px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100"
            >
              {(isWeekBased(billing.cycle_type) ? WEEKDAY_OPTIONS : DAY_OF_MONTH_OPTIONS).map((opt) => (
                <option key={opt.value} value={opt.value}>{opt.label}</option>
              ))}
            </select>
          </div>
        </div>

        <div className="flex flex-wrap items-center gap-3 mt-4">
          <button
            onClick={() => billingMut.mutate(billing)}
            disabled={billingMut.isPending || !billingDirty}
            className="inline-flex items-center gap-2 px-4 py-2 text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 rounded-lg disabled:opacity-50 disabled:cursor-not-allowed"
          >
            <Check className="w-4 h-4" />
            {billingMut.isPending ? 'Saving...' : 'Save Billing Cycle'}
          </button>
          <button
            onClick={() => setBillingForm(DEFAULT_BILLING)}
            className="inline-flex items-center gap-2 px-4 py-2 text-sm font-medium border border-gray-300 dark:border-gray-600 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-700"
          >
            <RotateCcw className="w-4 h-4" />
            Reset
          </button>
        </div>
      </div>

      {/* ══ Section 2: Pay Period ══════════════════════════ */}
      <div className="bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-xl p-5">
        <div className="flex items-center gap-2 mb-4">
          <Clock className="w-5 h-5 text-green-500" />
          <h2 className="text-base font-medium text-gray-900 dark:text-gray-100">
            Pay Period
          </h2>
        </div>
        <p className="text-sm text-gray-500 dark:text-gray-400 mb-4">
          How pay periods are computed for timesheets, labor reports, and payroll exports. 
          E.g., &quot;Bi-weekly starting on Monday.&quot;
        </p>

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              Period Type
            </label>
            <select
              value={pay.period_type}
              onChange={(e) => setPayForm({ ...pay, period_type: e.target.value })}
              className="w-full px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100"
            >
              {PAY_PERIOD_OPTIONS.map((opt) => (
                <option key={opt.value} value={opt.value}>{opt.label}</option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-1">
              {isWeekBased(pay.period_type) ? 'Start Day of Week' : 'Start Day of Month'}
            </label>
            <select
              value={pay.start_day}
              onChange={(e) => setPayForm({ ...pay, start_day: parseInt(e.target.value) })}
              className="w-full px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100"
            >
              {(isWeekBased(pay.period_type) ? WEEKDAY_OPTIONS : DAY_OF_MONTH_OPTIONS).map((opt) => (
                <option key={opt.value} value={opt.value}>{opt.label}</option>
              ))}
            </select>
          </div>
        </div>

        <div className="flex flex-wrap items-center gap-3 mt-4">
          <button
            onClick={() => payMut.mutate(pay)}
            disabled={payMut.isPending || !payDirty}
            className="inline-flex items-center gap-2 px-4 py-2 text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 rounded-lg disabled:opacity-50 disabled:cursor-not-allowed"
          >
            <Check className="w-4 h-4" />
            {payMut.isPending ? 'Saving...' : 'Save Pay Period'}
          </button>
          <button
            onClick={() => setPayForm(DEFAULT_PAY)}
            className="inline-flex items-center gap-2 px-4 py-2 text-sm font-medium border border-gray-300 dark:border-gray-600 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-700"
          >
            <RotateCcw className="w-4 h-4" />
            Reset
          </button>
        </div>
      </div>

      {/* ══ Section 3: Payroll Columns ════════════════════ */}
      <div className="bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-xl p-5">
        <div className="flex items-center gap-2 mb-4">
          <Columns3 className="w-5 h-5 text-purple-500" />
          <h2 className="text-base font-medium text-gray-900 dark:text-gray-100">
            Payroll Export Columns
          </h2>
        </div>
        <p className="text-sm text-gray-500 dark:text-gray-400 mb-4">
          Choose which columns appear in payroll CSV exports. Drag to reorder, click × to remove.
          Match your payroll provider&apos;s import format (ADP, Gusto, etc.).
        </p>

        {/* Current columns list */}
        <div className="space-y-2 mb-4">
          {columns.columns.map((col, idx) => (
            <div
              key={col}
              className="flex items-center gap-2 px-3 py-2 bg-gray-50 dark:bg-gray-700 rounded-lg border border-gray-200 dark:border-gray-600"
            >
              <GripVertical className="w-4 h-4 text-gray-400 shrink-0" />
              <span className="flex-1 text-sm text-gray-900 dark:text-gray-100">{col}</span>
              <div className="flex items-center gap-1">
                <button
                  onClick={() => moveColumn(idx, -1)}
                  disabled={idx === 0}
                  className="p-1 text-gray-400 hover:text-gray-600 dark:hover:text-gray-300 disabled:opacity-30"
                  title="Move up"
                >
                  ↑
                </button>
                <button
                  onClick={() => moveColumn(idx, 1)}
                  disabled={idx === columns.columns.length - 1}
                  className="p-1 text-gray-400 hover:text-gray-600 dark:hover:text-gray-300 disabled:opacity-30"
                  title="Move down"
                >
                  ↓
                </button>
                <button
                  onClick={() => removeColumn(col)}
                  className="p-1 text-red-400 hover:text-red-600"
                  title="Remove column"
                >
                  <X className="w-4 h-4" />
                </button>
              </div>
            </div>
          ))}
        </div>

        {/* Add column */}
        <div className="flex items-center gap-2">
          <select
            value={newCol}
            onChange={(e) => setNewCol(e.target.value)}
            className="flex-1 px-3 py-2 text-sm border border-gray-300 dark:border-gray-600 rounded-lg bg-white dark:bg-gray-700 text-gray-900 dark:text-gray-100"
          >
            <option value="">Add a column...</option>
            {AVAILABLE_PAYROLL_COLUMNS.filter((c) => !columns.columns.includes(c)).map((c) => (
              <option key={c} value={c}>{c}</option>
            ))}
          </select>
          <button
            onClick={addColumn}
            disabled={!newCol}
            className="inline-flex items-center gap-1 px-3 py-2 text-sm font-medium text-white bg-purple-600 hover:bg-purple-700 rounded-lg disabled:opacity-50"
          >
            <Plus className="w-4 h-4" />
            Add
          </button>
        </div>

        <div className="flex flex-wrap items-center gap-3 mt-4">
          <button
            onClick={() => columnsMut.mutate(columns)}
            disabled={columnsMut.isPending || !columnsDirty}
            className="inline-flex items-center gap-2 px-4 py-2 text-sm font-medium text-white bg-blue-600 hover:bg-blue-700 rounded-lg disabled:opacity-50 disabled:cursor-not-allowed"
          >
            <Check className="w-4 h-4" />
            {columnsMut.isPending ? 'Saving...' : 'Save Columns'}
          </button>
          <button
            onClick={() => setColumnsForm(DEFAULT_COLUMNS)}
            className="inline-flex items-center gap-2 px-4 py-2 text-sm font-medium border border-gray-300 dark:border-gray-600 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-700"
          >
            <RotateCcw className="w-4 h-4" />
            Reset to Defaults
          </button>
        </div>
      </div>
    </div>
  );
}
