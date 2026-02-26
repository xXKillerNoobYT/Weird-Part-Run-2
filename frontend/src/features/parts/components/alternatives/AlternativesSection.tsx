/**
 * AlternativesSection — collapsible section showing linked alternative parts.
 *
 * Two modes:
 * - Full edit (PartDetailPanel): add, edit, unlink alternatives
 * - Read-only (CatalogPage modal): just names + badges, link to full edit
 *
 * Bidirectional: a single DB row shows up for both parts.
 * The `viewingPartId` prop determines which "side" to display as the "other" part.
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  ChevronDown, ChevronRight, Plus, GitCompareArrows, Link2,
} from 'lucide-react';
import { AlternativeRow } from './AlternativeRow';
import { LinkAlternativeModal } from './LinkAlternativeModal';
import { Spinner } from '../../../../components/ui/Spinner';
import { Badge } from '../../../../components/ui/Badge';
import {
  listPartAlternatives,
  linkPartAlternative,
  updatePartAlternative,
  unlinkPartAlternative,
} from '../../../../api/parts';
import type { PartAlternative, AlternativeRelationship } from '../../../../lib/types';

interface AlternativesSectionProps {
  partId: number;
  readOnly?: boolean;
}

export function AlternativesSection({
  partId,
  readOnly = false,
}: AlternativesSectionProps) {
  const queryClient = useQueryClient();
  const [isExpanded, setIsExpanded] = useState(true);
  const [modalOpen, setModalOpen] = useState(false);
  const [editingLink, setEditingLink] = useState<PartAlternative | null>(null);

  // Fetch alternatives for this part
  const { data: alternatives = [], isLoading } = useQuery({
    queryKey: ['part-alternatives', partId],
    queryFn: () => listPartAlternatives(partId),
  });

  // Create link mutation
  const linkMutation = useMutation({
    mutationFn: (data: {
      alternative_part_id: number;
      relationship: AlternativeRelationship;
      preference: number;
      notes?: string;
    }) =>
      linkPartAlternative(partId, {
        alternative_part_id: data.alternative_part_id,
        relationship: data.relationship,
        preference: data.preference,
        notes: data.notes,
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['part-alternatives', partId] });
      setModalOpen(false);
    },
  });

  // Update link mutation
  const updateMutation = useMutation({
    mutationFn: ({
      linkId,
      data,
    }: {
      linkId: number;
      data: { relationship?: AlternativeRelationship; preference?: number; notes?: string };
    }) => updatePartAlternative(linkId, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['part-alternatives', partId] });
      setEditingLink(null);
      setModalOpen(false);
    },
  });

  // Unlink mutation
  const unlinkMutation = useMutation({
    mutationFn: unlinkPartAlternative,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['part-alternatives', partId] });
    },
  });

  const handleEdit = (alt: PartAlternative) => {
    setEditingLink(alt);
    setModalOpen(true);
  };

  const handleUnlink = (alt: PartAlternative) => {
    if (confirm(`Remove alternative link? This won't delete either part.`)) {
      unlinkMutation.mutate(alt.id);
    }
  };

  const handleSave = (data: {
    alternative_part_id?: number;
    relationship: AlternativeRelationship;
    preference: number;
    notes?: string;
  }) => {
    if (editingLink) {
      updateMutation.mutate({
        linkId: editingLink.id,
        data: {
          relationship: data.relationship,
          preference: data.preference,
          notes: data.notes,
        },
      });
    } else if (data.alternative_part_id) {
      linkMutation.mutate({
        alternative_part_id: data.alternative_part_id,
        relationship: data.relationship,
        preference: data.preference,
        notes: data.notes,
      });
    }
  };

  const handleOpenCreate = () => {
    setEditingLink(null);
    setModalOpen(true);
  };

  // Sort: preferred first, then alphabetically
  const sorted = [...alternatives].sort((a, b) => {
    if (a.preference !== b.preference) return b.preference - a.preference;
    const nameA = (a.part_id === partId ? a.alternative_name : a.part_name) ?? '';
    const nameB = (b.part_id === partId ? b.alternative_name : b.part_name) ?? '';
    return nameA.localeCompare(nameB);
  });

  // ── Read-only summary (for CatalogPage modal) ──────────────────
  if (readOnly) {
    if (isLoading) return null;
    if (alternatives.length === 0) return null;

    return (
      <div className="space-y-2">
        <h4 className="text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400 flex items-center gap-1">
          <GitCompareArrows className="h-3.5 w-3.5" />
          Alternatives
        </h4>
        <div className="space-y-1">
          {sorted.map((alt) => {
            const otherName = alt.part_id === partId
              ? alt.alternative_name
              : alt.part_name;
            return (
              <div key={alt.id} className="flex items-center gap-2 text-sm">
                {alt.preference > 0 && (
                  <span className="text-amber-500" title="Preferred">★</span>
                )}
                <span className="text-gray-700 dark:text-gray-300">
                  {otherName ?? 'Unknown'}
                </span>
                <Badge
                  variant={alt.relationship === 'upgrade' ? 'primary' : alt.relationship === 'compatible' ? 'success' : 'default'}
                >
                  {alt.relationship}
                </Badge>
              </div>
            );
          })}
        </div>
        <p className="text-xs text-gray-400 dark:text-gray-500 italic">
          Full edit in Categories →
        </p>
      </div>
    );
  }

  // ── Full editable section (for PartDetailPanel) ─────────────────
  return (
    <div className="space-y-3 border-t border-gray-200 dark:border-gray-700 pt-4">
      {/* Section header — collapsible */}
      <div className="flex items-center justify-between">
        <button
          onClick={() => setIsExpanded(!isExpanded)}
          className="flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wider text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300 transition-colors"
        >
          {isExpanded ? (
            <ChevronDown className="h-3.5 w-3.5" />
          ) : (
            <ChevronRight className="h-3.5 w-3.5" />
          )}
          <GitCompareArrows className="h-3.5 w-3.5" />
          Alternatives
          {alternatives.length > 0 && (
            <span className="text-gray-400 dark:text-gray-500 font-normal normal-case">
              ({alternatives.length})
            </span>
          )}
        </button>

        <button
          onClick={handleOpenCreate}
          className="text-xs text-primary-600 dark:text-primary-400 hover:underline flex items-center gap-1"
          title="Link alternative part"
        >
          <Plus className="h-3.5 w-3.5" />
          Link Part
        </button>
      </div>

      {/* Content (collapsed = hidden) */}
      {isExpanded && (
        <div>
          {isLoading ? (
            <div className="flex justify-center py-3">
              <Spinner size="sm" />
            </div>
          ) : sorted.length === 0 ? (
            <div className="text-center py-4">
              <Link2 className="h-8 w-8 text-gray-300 dark:text-gray-600 mx-auto mb-2" />
              <p className="text-sm text-gray-500 dark:text-gray-400">
                No alternatives linked.
              </p>
              <button
                onClick={handleOpenCreate}
                className="text-xs text-primary-600 dark:text-primary-400 hover:underline mt-1"
              >
                + Link a part
              </button>
            </div>
          ) : (
            <div className="space-y-1">
              {sorted.map((alt) => (
                <AlternativeRow
                  key={alt.id}
                  alt={alt}
                  viewingPartId={partId}
                  onEdit={handleEdit}
                  onUnlink={handleUnlink}
                />
              ))}
            </div>
          )}
        </div>
      )}

      {/* Link/Edit modal */}
      <LinkAlternativeModal
        isOpen={modalOpen}
        onClose={() => {
          setModalOpen(false);
          setEditingLink(null);
        }}
        partId={partId}
        editingLink={editingLink}
        onSave={handleSave}
        isLoading={linkMutation.isPending || updateMutation.isPending}
      />
    </div>
  );
}
