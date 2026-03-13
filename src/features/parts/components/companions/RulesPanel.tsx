/**
 * RulesPanel — list all companion rules with CRUD operations.
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Plus, BookOpen } from 'lucide-react';
import { listCompanionRules, createCompanionRule, updateCompanionRule, deleteCompanionRule } from '../../../../api/parts';
import { RuleCard } from './RuleCard';
import { RuleFormModal } from './RuleFormModal';
import { Button } from '../../../../components/ui/Button';
import { Spinner } from '../../../../components/ui/Spinner';
import { EmptyState } from '../../../../components/ui/EmptyState';
import type { CompanionRule, CompanionRuleCreate, CompanionRuleUpdate } from '../../../../lib/types';

export function RulesPanel() {
  const queryClient = useQueryClient();
  const [modalOpen, setModalOpen] = useState(false);
  const [editingRule, setEditingRule] = useState<CompanionRule | null>(null);

  const { data: rules = [], isLoading } = useQuery({
    queryKey: ['companion-rules'],
    queryFn: listCompanionRules,
  });

  const createMutation = useMutation({
    mutationFn: createCompanionRule,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['companion-rules'] });
      queryClient.invalidateQueries({ queryKey: ['companion-stats'] });
      setModalOpen(false);
    },
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, data }: { id: number; data: CompanionRuleUpdate }) =>
      updateCompanionRule(id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['companion-rules'] });
      queryClient.invalidateQueries({ queryKey: ['companion-stats'] });
      setEditingRule(null);
      setModalOpen(false);
    },
  });

  const deleteMutation = useMutation({
    mutationFn: deleteCompanionRule,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['companion-rules'] });
      queryClient.invalidateQueries({ queryKey: ['companion-stats'] });
    },
  });

  const handleEdit = (rule: CompanionRule) => {
    setEditingRule(rule);
    setModalOpen(true);
  };

  const handleDelete = (rule: CompanionRule) => {
    if (confirm(`Delete rule "${rule.name}"? This cannot be undone.`)) {
      deleteMutation.mutate(rule.id);
    }
  };

  const handleSave = (data: CompanionRuleCreate | CompanionRuleUpdate) => {
    if (editingRule) {
      updateMutation.mutate({ id: editingRule.id, data: data as CompanionRuleUpdate });
    } else {
      createMutation.mutate(data as CompanionRuleCreate);
    }
  };

  const handleOpenCreate = () => {
    setEditingRule(null);
    setModalOpen(true);
  };

  if (isLoading) {
    return (
      <div className="flex justify-center py-12">
        <Spinner />
      </div>
    );
  }

  return (
    <div>
      {/* Header */}
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-sm font-semibold text-gray-700 dark:text-gray-300">
          {rules.length} rule{rules.length !== 1 ? 's' : ''} defined
        </h3>
        <Button
          variant="primary"
          size="sm"
          icon={<Plus className="h-4 w-4" />}
          onClick={handleOpenCreate}
        >
          New Rule
        </Button>
      </div>

      {/* Rules list */}
      {rules.length === 0 ? (
        <EmptyState
          icon={<BookOpen className="h-12 w-12" />}
          title="No companion rules"
          description="Create a rule to define which categories should be suggested together."
          action={
            <Button variant="primary" size="sm" icon={<Plus className="h-4 w-4" />} onClick={handleOpenCreate}>
              Create First Rule
            </Button>
          }
        />
      ) : (
        <div className="space-y-3">
          {rules.map((rule) => (
            <RuleCard
              key={rule.id}
              rule={rule}
              onEdit={handleEdit}
              onDelete={handleDelete}
            />
          ))}
        </div>
      )}

      {/* Create/Edit Modal */}
      <RuleFormModal
        isOpen={modalOpen}
        onClose={() => {
          setModalOpen(false);
          setEditingRule(null);
        }}
        onSave={handleSave}
        isLoading={createMutation.isPending || updateMutation.isPending}
        rule={editingRule}
      />
    </div>
  );
}
