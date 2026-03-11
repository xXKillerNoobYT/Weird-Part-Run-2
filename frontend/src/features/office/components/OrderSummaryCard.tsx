/**
 * OrderSummaryCard — cross-job aggregate view of parts needed across all
 * approved orders.
 *
 * Shows a compact banner: "15 units of 8 parts needed across 3 jobs from 2 suppliers"
 * with an expandable table showing per-part breakdown.
 *
 * Phase 17 Gap 4: Cross-Job Aggregate Summary
 */

import { useState } from 'react';
import { ChevronDown, BarChart3, Building2, Briefcase } from 'lucide-react';
import type { OrderSummary } from '../../../lib/types';


interface Props {
  data: OrderSummary;
}

export function OrderSummaryCard({ data }: Props) {
  const [isExpanded, setIsExpanded] = useState(false);

  if (data.total_parts === 0) return null;

  return (
    <div className="rounded-xl border border-blue-200 dark:border-blue-800 bg-blue-50 dark:bg-blue-900/20 overflow-hidden">
      {/* Clickable summary banner */}
      <button
        onClick={() => setIsExpanded(!isExpanded)}
        className="w-full flex items-center justify-between gap-3 px-4 py-3 text-left hover:bg-blue-100 dark:hover:bg-blue-900/30 transition-colors"
      >
        <div className="flex items-center gap-3 min-w-0">
          <BarChart3 className="h-5 w-5 text-blue-600 dark:text-blue-400 flex-shrink-0" />
          <span className="text-sm font-medium text-blue-800 dark:text-blue-200 truncate">
            {data.summary_text}
          </span>
        </div>
        <ChevronDown
          className={`h-4 w-4 text-blue-500 flex-shrink-0 transition-transform ${
            isExpanded ? 'rotate-180' : ''
          }`}
        />
      </button>

      {/* Stat pills (visible even when collapsed on md+) */}
      <div className="flex flex-wrap gap-2 px-4 pb-3">
        <StatPill
          icon={<BarChart3 className="h-3.5 w-3.5" />}
          label={`${data.total_qty} unit${data.total_qty !== 1 ? 's' : ''}`}
        />
        <StatPill
          icon={<Briefcase className="h-3.5 w-3.5" />}
          label={`${data.total_jobs} job${data.total_jobs !== 1 ? 's' : ''}`}
        />
        <StatPill
          icon={<Building2 className="h-3.5 w-3.5" />}
          label={`${data.total_suppliers} supplier${data.total_suppliers !== 1 ? 's' : ''}`}
        />
      </div>

      {/* Expandable table */}
      {isExpanded && (
        <div className="border-t border-blue-200 dark:border-blue-800 overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-blue-100/60 dark:bg-blue-900/40 text-blue-700 dark:text-blue-300">
                <th className="text-left px-4 py-2 font-medium">Part</th>
                <th className="text-left px-4 py-2 font-medium hidden sm:table-cell">Category</th>
                <th className="text-right px-4 py-2 font-medium">Qty</th>
                <th className="text-right px-4 py-2 font-medium">Jobs</th>
                <th className="text-left px-4 py-2 font-medium hidden md:table-cell">Job Names</th>
                <th className="text-left px-4 py-2 font-medium hidden lg:table-cell">Supplier</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-blue-100 dark:divide-blue-800/50">
              {data.lines.map((line) => (
                <tr
                  key={line.part_id}
                  className="hover:bg-blue-100/40 dark:hover:bg-blue-900/30 transition-colors"
                >
                  <td className="px-4 py-2 text-gray-900 dark:text-gray-100 font-medium">
                    {line.part_name}
                  </td>
                  <td className="px-4 py-2 text-gray-500 dark:text-gray-400 hidden sm:table-cell">
                    {line.category_name || '—'}
                  </td>
                  <td className="px-4 py-2 text-right font-semibold text-gray-900 dark:text-gray-100">
                    {line.total_qty_needed}
                  </td>
                  <td className="px-4 py-2 text-right text-gray-600 dark:text-gray-300">
                    {line.job_count}
                  </td>
                  <td className="px-4 py-2 text-gray-500 dark:text-gray-400 hidden md:table-cell max-w-[200px] truncate">
                    {line.job_names?.join(', ') || '—'}
                  </td>
                  <td className="px-4 py-2 text-gray-600 dark:text-gray-300 hidden lg:table-cell">
                    {line.supplier_name || (
                      <span className="text-amber-500 dark:text-amber-400 text-xs">Unassigned</span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

function StatPill({ icon, label }: { icon: React.ReactNode; label: string }) {
  return (
    <span className="inline-flex items-center gap-1.5 rounded-full bg-blue-100 dark:bg-blue-900/40 px-2.5 py-1 text-xs font-medium text-blue-700 dark:text-blue-300">
      {icon}
      {label}
    </span>
  );
}
