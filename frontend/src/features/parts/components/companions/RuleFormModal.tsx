/**
 * RuleFormModal — create/edit companion rule with category/style pickers.
 *
 * Form fields: name, description, style_match, qty_mode, qty_ratio,
 * sources (category + optional style), targets (category + optional style).
 */

import { useState, useEffect } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Plus, Trash2 } from 'lucide-react';
import { Modal } from '../../../../components/ui/Modal';
import { Input } from '../../../../components/ui/Input';
import { Button } from '../../../../components/ui/Button';
import { getHierarchy } from '../../../../api/parts';
import type {
  CompanionRule,
  CompanionRuleCreate,
  CompanionRuleUpdate,
  CompanionRuleSourceCreate,
  CompanionRuleTargetCreate,
} from '../../../../lib/types';

interface RuleFormModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSave: (data: CompanionRuleCreate | CompanionRuleUpdate) => void;
  isLoading?: boolean;
  rule?: CompanionRule | null;  // null = create mode
}

interface SourceTargetEntry {
  category_id: number | '';
  style_id: number | '' | null;
}

export function RuleFormModal({ isOpen, onClose, onSave, isLoading, rule }: RuleFormModalProps) {
  const isEdit = !!rule;

  // Form state
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [styleMatch, setStyleMatch] = useState<'auto' | 'any' | 'explicit'>('auto');
  const [qtyMode, setQtyMode] = useState<'sum' | 'max' | 'ratio'>('sum');
  const [qtyRatio, setQtyRatio] = useState(1.0);
  const [isActive, setIsActive] = useState(true);
  const [sources, setSources] = useState<SourceTargetEntry[]>([{ category_id: '', style_id: null }]);
  const [targets, setTargets] = useState<SourceTargetEntry[]>([{ category_id: '', style_id: null }]);

  // Hierarchy for category/style pickers
  const { data: hierarchy } = useQuery({
    queryKey: ['hierarchy'],
    queryFn: getHierarchy,
    staleTime: 5 * 60 * 1000,
  });

  const categories = hierarchy?.categories ?? [];

  // Populate form when editing
  useEffect(() => {
    if (rule) {
      setName(rule.name);
      setDescription(rule.description ?? '');
      setStyleMatch(rule.style_match);
      setQtyMode(rule.qty_mode);
      setQtyRatio(rule.qty_ratio);
      setIsActive(rule.is_active);
      setSources(
        rule.sources.map((s) => ({
          category_id: s.category_id,
          style_id: s.style_id ?? null,
        }))
      );
      setTargets(
        rule.targets.map((t) => ({
          category_id: t.category_id,
          style_id: t.style_id ?? null,
        }))
      );
    } else {
      setName('');
      setDescription('');
      setStyleMatch('auto');
      setQtyMode('sum');
      setQtyRatio(1.0);
      setIsActive(true);
      setSources([{ category_id: '', style_id: null }]);
      setTargets([{ category_id: '', style_id: null }]);
    }
  }, [rule, isOpen]);

  // Get styles for a given category
  const getStylesForCategory = (categoryId: number | '') => {
    if (!categoryId || !hierarchy) return [];
    const cat = categories.find((c) => c.id === categoryId);
    return cat?.styles ?? [];
  };

  // Add/remove source/target rows
  const addRow = (list: SourceTargetEntry[], setter: typeof setSources) => {
    setter([...list, { category_id: '', style_id: null }]);
  };

  const removeRow = (list: SourceTargetEntry[], setter: typeof setSources, idx: number) => {
    if (list.length <= 1) return;
    setter(list.filter((_, i) => i !== idx));
  };

  const updateRow = (
    list: SourceTargetEntry[],
    setter: typeof setSources,
    idx: number,
    field: 'category_id' | 'style_id',
    value: number | '' | null,
  ) => {
    const updated = [...list];
    updated[idx] = { ...updated[idx], [field]: value };
    // Reset style if category changes
    if (field === 'category_id') {
      updated[idx].style_id = null;
    }
    setter(updated);
  };

  // Validate
  const validSources = sources.filter((s) => s.category_id !== '');
  const validTargets = targets.filter((t) => t.category_id !== '');
  const canSave = name.trim().length > 0 && validSources.length > 0 && validTargets.length > 0;

  const handleSave = () => {
    const sourcesPayload: CompanionRuleSourceCreate[] = validSources.map((s) => ({
      category_id: s.category_id as number,
      style_id: s.style_id || undefined,
    }));
    const targetsPayload: CompanionRuleTargetCreate[] = validTargets.map((t) => ({
      category_id: t.category_id as number,
      style_id: t.style_id || undefined,
    }));

    if (isEdit) {
      const update: CompanionRuleUpdate = {
        name,
        description: description || undefined,
        style_match: styleMatch,
        qty_mode: qtyMode,
        qty_ratio: qtyMode === 'ratio' ? qtyRatio : undefined,
        is_active: isActive,
        sources: sourcesPayload,
        targets: targetsPayload,
      };
      onSave(update);
    } else {
      const create: CompanionRuleCreate = {
        name,
        description: description || undefined,
        style_match: styleMatch,
        qty_mode: qtyMode,
        qty_ratio: qtyMode === 'ratio' ? qtyRatio : 1.0,
        is_active: isActive,
        sources: sourcesPayload,
        targets: targetsPayload,
      };
      onSave(create);
    }
  };

  // Render a source/target row
  const renderRow = (
    list: SourceTargetEntry[],
    setter: typeof setSources,
    idx: number,
    entry: SourceTargetEntry,
    label: string,
  ) => {
    const styles = getStylesForCategory(entry.category_id);

    return (
      <div key={idx} className="flex flex-col sm:flex-row gap-2 items-start sm:items-end">
        {/* Category picker */}
        <div className="flex-1 min-w-0 w-full sm:w-auto">
          {idx === 0 && (
            <label className="block text-xs font-medium text-gray-500 dark:text-gray-400 mb-1">
              {label} Category
            </label>
          )}
          <select
            value={entry.category_id}
            onChange={(e) =>
              updateRow(list, setter, idx, 'category_id', e.target.value ? Number(e.target.value) : '')
            }
            className="w-full h-9 px-2 text-sm rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 focus:outline-none focus:ring-2 focus:ring-primary-300"
          >
            <option value="">Select category...</option>
            {categories.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </select>
        </div>

        {/* Style picker (optional) */}
        <div className="flex-1 min-w-0 w-full sm:w-auto">
          {idx === 0 && (
            <label className="block text-xs font-medium text-gray-500 dark:text-gray-400 mb-1">
              Style (optional)
            </label>
          )}
          <select
            value={entry.style_id ?? ''}
            onChange={(e) =>
              updateRow(list, setter, idx, 'style_id', e.target.value ? Number(e.target.value) : null)
            }
            disabled={!entry.category_id || styles.length === 0}
            className="w-full h-9 px-2 text-sm rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 disabled:opacity-50 focus:outline-none focus:ring-2 focus:ring-primary-300"
          >
            <option value="">Any style</option>
            {styles.map((s) => (
              <option key={s.id} value={s.id}>
                {s.name}
              </option>
            ))}
          </select>
        </div>

        {/* Remove button */}
        <button
          onClick={() => removeRow(list, setter, idx)}
          disabled={list.length <= 1}
          className="p-2 text-gray-400 hover:text-red-500 disabled:opacity-30 transition-colors shrink-0"
        >
          <Trash2 className="h-4 w-4" />
        </button>
      </div>
    );
  };

  return (
    <Modal isOpen={isOpen} onClose={onClose} title={isEdit ? 'Edit Rule' : 'New Companion Rule'} size="lg">
      <div className="space-y-5 max-h-[70vh] overflow-y-auto">
        {/* Name */}
        <Input
          label="Rule Name"
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="e.g., Cover Plates for Devices"
        />

        {/* Description */}
        <div className="space-y-1.5">
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">
            Description
          </label>
          <textarea
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder="Optional description..."
            rows={2}
            className="block w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm text-gray-900 dark:text-gray-100 placeholder:text-gray-400 focus:outline-none focus:ring-2 focus:ring-primary-300"
          />
        </div>

        {/* Config row */}
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
          {/* Style match */}
          <div className="space-y-1.5">
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">
              Style Matching
            </label>
            <select
              value={styleMatch}
              onChange={(e) => setStyleMatch(e.target.value as typeof styleMatch)}
              className="w-full h-9 px-2 text-sm rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 focus:outline-none focus:ring-2 focus:ring-primary-300"
            >
              <option value="auto">Auto (match by name)</option>
              <option value="any">Any style</option>
              <option value="explicit">Explicit only</option>
            </select>
          </div>

          {/* Qty mode */}
          <div className="space-y-1.5">
            <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">
              Quantity Mode
            </label>
            <select
              value={qtyMode}
              onChange={(e) => setQtyMode(e.target.value as typeof qtyMode)}
              className="w-full h-9 px-2 text-sm rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 focus:outline-none focus:ring-2 focus:ring-primary-300"
            >
              <option value="sum">Sum of sources</option>
              <option value="max">Max of sources</option>
              <option value="ratio">Ratio</option>
            </select>
          </div>

          {/* Ratio (only visible if mode = ratio) */}
          {qtyMode === 'ratio' && (
            <div className="space-y-1.5">
              <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">
                Ratio
              </label>
              <input
                type="number"
                min={0.01}
                step={0.1}
                value={qtyRatio}
                onChange={(e) => setQtyRatio(parseFloat(e.target.value) || 1.0)}
                className="w-full h-9 px-2 text-sm rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 focus:outline-none focus:ring-2 focus:ring-primary-300"
              />
            </div>
          )}
        </div>

        {/* Active toggle */}
        <label className="flex items-center gap-2 cursor-pointer">
          <input
            type="checkbox"
            checked={isActive}
            onChange={(e) => setIsActive(e.target.checked)}
            className="rounded border-gray-300 dark:border-gray-600 text-primary-500 focus:ring-primary-300"
          />
          <span className="text-sm text-gray-700 dark:text-gray-300">Active</span>
        </label>

        {/* Sources */}
        <div>
          <div className="flex items-center justify-between mb-2">
            <h4 className="text-sm font-semibold text-gray-700 dark:text-gray-300">
              Source Categories (triggers)
            </h4>
            <button
              onClick={() => addRow(sources, setSources)}
              className="text-xs text-primary-600 dark:text-primary-400 hover:underline flex items-center gap-1"
            >
              <Plus className="h-3 w-3" /> Add
            </button>
          </div>
          <div className="space-y-2">
            {sources.map((entry, idx) => renderRow(sources, setSources, idx, entry, 'Source'))}
          </div>
        </div>

        {/* Targets */}
        <div>
          <div className="flex items-center justify-between mb-2">
            <h4 className="text-sm font-semibold text-gray-700 dark:text-gray-300">
              Target Categories (suggested)
            </h4>
            <button
              onClick={() => addRow(targets, setTargets)}
              className="text-xs text-primary-600 dark:text-primary-400 hover:underline flex items-center gap-1"
            >
              <Plus className="h-3 w-3" /> Add
            </button>
          </div>
          <div className="space-y-2">
            {targets.map((entry, idx) => renderRow(targets, setTargets, idx, entry, 'Target'))}
          </div>
        </div>
      </div>

      {/* Footer */}
      <div className="flex justify-end gap-3 mt-6 pt-4 border-t border-gray-200 dark:border-gray-700">
        <Button variant="secondary" onClick={onClose}>
          Cancel
        </Button>
        <Button
          variant="primary"
          onClick={handleSave}
          disabled={!canSave}
          isLoading={isLoading}
        >
          {isEdit ? 'Update Rule' : 'Create Rule'}
        </Button>
      </div>
    </Modal>
  );
}
