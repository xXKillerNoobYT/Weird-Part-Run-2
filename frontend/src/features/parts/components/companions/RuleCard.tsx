/**
 * RuleCard — displays a single companion rule with sources → targets.
 */

import { ArrowRight, Pencil, Trash2 } from 'lucide-react';
import { Card } from '../../../../components/ui/Card';
import { Badge } from '../../../../components/ui/Badge';
import { Button } from '../../../../components/ui/Button';
import type { CompanionRule } from '../../../../lib/types';

interface RuleCardProps {
  rule: CompanionRule;
  onEdit: (rule: CompanionRule) => void;
  onDelete: (rule: CompanionRule) => void;
}

export function RuleCard({ rule, onEdit, onDelete }: RuleCardProps) {
  const styleLabel = {
    auto: 'Auto-match style',
    any: 'Any style',
    explicit: 'Explicit style',
  }[rule.style_match];

  const qtyLabel = {
    sum: 'Sum qty',
    max: 'Max qty',
    ratio: `Ratio ${rule.qty_ratio}x`,
  }[rule.qty_mode];

  return (
    <Card className="p-4">
      {/* Header */}
      <div className="flex items-start justify-between gap-3 mb-3">
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2 flex-wrap">
            <h4 className="font-semibold text-gray-900 dark:text-gray-100">
              {rule.name}
            </h4>
            <Badge variant={rule.is_active ? 'success' : 'default'}>
              {rule.is_active ? 'Active' : 'Inactive'}
            </Badge>
          </div>
          {rule.description && (
            <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">
              {rule.description}
            </p>
          )}
        </div>
        <div className="flex items-center gap-1 shrink-0">
          <Button variant="ghost" size="sm" icon={<Pencil className="h-3.5 w-3.5" />} onClick={() => onEdit(rule)} />
          <Button variant="ghost" size="sm" icon={<Trash2 className="h-3.5 w-3.5 text-red-500" />} onClick={() => onDelete(rule)} />
        </div>
      </div>

      {/* Sources → Targets */}
      <div className="flex flex-col sm:flex-row items-start sm:items-center gap-2 mb-3">
        {/* Sources */}
        <div className="flex flex-wrap gap-1.5">
          {rule.sources.map((s) => (
            <Badge key={s.id} variant="primary">
              {s.category_name}
              {s.style_name && ` (${s.style_name})`}
            </Badge>
          ))}
        </div>

        <ArrowRight className="h-4 w-4 text-gray-400 dark:text-gray-500 shrink-0 rotate-90 sm:rotate-0" />

        {/* Targets */}
        <div className="flex flex-wrap gap-1.5">
          {rule.targets.map((t) => (
            <Badge key={t.id} variant="success">
              {t.category_name}
              {t.style_name && ` (${t.style_name})`}
            </Badge>
          ))}
        </div>
      </div>

      {/* Config badges */}
      <div className="flex flex-wrap gap-2 text-xs text-gray-500 dark:text-gray-400">
        <span className="px-2 py-0.5 rounded bg-gray-100 dark:bg-gray-700">
          {styleLabel}
        </span>
        <span className="px-2 py-0.5 rounded bg-gray-100 dark:bg-gray-700">
          {qtyLabel}
        </span>
      </div>
    </Card>
  );
}
