/**
 * LinkAlternativeModal — search for a part and link it as an alternative.
 *
 * Supports both creating new links and editing existing ones:
 * - Create: part search → select relationship → optional preference → confirm
 * - Edit: pre-populated fields, no part search (part already linked)
 *
 * Uses the catalog search API to find parts by name, code, or MPN.
 */

import { useState, useEffect, useCallback } from 'react';
import { Search, Star, Link2 } from 'lucide-react';
import { useQuery } from '@tanstack/react-query';
import { Modal } from '../../../../components/ui/Modal';
import { Input } from '../../../../components/ui/Input';
import { Button } from '../../../../components/ui/Button';
import { Badge } from '../../../../components/ui/Badge';
import { Spinner } from '../../../../components/ui/Spinner';
import { listParts } from '../../../../api/parts';
import type { PartAlternative, AlternativeRelationship } from '../../../../lib/types';

interface LinkAlternativeModalProps {
  isOpen: boolean;
  onClose: () => void;
  /** Current part we're linking FROM */
  partId: number;
  /** Existing alternative to edit (null = create new) */
  editingLink?: PartAlternative | null;
  onSave: (data: {
    alternative_part_id?: number;
    relationship: AlternativeRelationship;
    preference: number;
    notes?: string;
  }) => void;
  isLoading?: boolean;
}

const RELATIONSHIPS: { value: AlternativeRelationship; label: string; description: string }[] = [
  { value: 'substitute', label: 'Substitute', description: 'Does the same job' },
  { value: 'upgrade', label: 'Upgrade', description: 'Better/newer version' },
  { value: 'compatible', label: 'Compatible', description: 'Works alongside' },
];

export function LinkAlternativeModal({
  isOpen,
  onClose,
  partId,
  editingLink = null,
  onSave,
  isLoading = false,
}: LinkAlternativeModalProps) {
  const [searchTerm, setSearchTerm] = useState('');
  const [debouncedSearch, setDebouncedSearch] = useState('');
  const [selectedPartId, setSelectedPartId] = useState<number | null>(null);
  const [selectedPartName, setSelectedPartName] = useState<string>('');
  const [relationship, setRelationship] = useState<AlternativeRelationship>('substitute');
  const [isPreferred, setIsPreferred] = useState(false);
  const [notes, setNotes] = useState('');

  // Debounce search input
  useEffect(() => {
    const timer = setTimeout(() => setDebouncedSearch(searchTerm), 300);
    return () => clearTimeout(timer);
  }, [searchTerm]);

  // Populate fields when editing
  useEffect(() => {
    if (editingLink) {
      setRelationship(editingLink.relationship as AlternativeRelationship);
      setIsPreferred(editingLink.preference > 0);
      setNotes(editingLink.notes ?? '');
      // Set selected part info for display
      const otherName = editingLink.part_id === partId
        ? editingLink.alternative_name
        : editingLink.part_name;
      setSelectedPartName(otherName ?? 'Linked Part');
    } else {
      // Reset for new link
      setSearchTerm('');
      setDebouncedSearch('');
      setSelectedPartId(null);
      setSelectedPartName('');
      setRelationship('substitute');
      setIsPreferred(false);
      setNotes('');
    }
  }, [editingLink, partId, isOpen]);

  // Search catalog (only for new links)
  const { data: searchResults, isLoading: searching } = useQuery({
    queryKey: ['catalog-search-alt', debouncedSearch],
    queryFn: () =>
      listParts({
        search: debouncedSearch,
        page: 1,
        page_size: 10,
        sort_by: 'name',
        sort_dir: 'asc',
      }),
    enabled: !editingLink && debouncedSearch.length >= 2,
  });

  // Filter out the current part from results
  const filteredResults = (searchResults?.items ?? []).filter(
    (p) => p.id !== partId
  );

  const handleSelectPart = useCallback((id: number, name: string) => {
    setSelectedPartId(id);
    setSelectedPartName(name);
    setSearchTerm('');
    setDebouncedSearch('');
  }, []);

  const handleSubmit = () => {
    if (editingLink) {
      // Edit mode — just update relationship/preference/notes
      onSave({
        relationship,
        preference: isPreferred ? 1 : 0,
        notes: notes || undefined,
      });
    } else {
      // Create mode — need the selected part
      if (!selectedPartId) return;
      onSave({
        alternative_part_id: selectedPartId,
        relationship,
        preference: isPreferred ? 1 : 0,
        notes: notes || undefined,
      });
    }
  };

  const canSubmit = editingLink
    ? true
    : selectedPartId !== null;

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={editingLink ? 'Edit Alternative Link' : 'Link Alternative Part'}
      size="md"
    >
      <div className="space-y-4 max-h-[70vh] overflow-y-auto">
        {/* Part search (only for new links) */}
        {!editingLink ? (
          <div>
            {selectedPartId ? (
              /* Selected part display */
              <div className="flex items-center gap-2 p-3 rounded-lg bg-primary-50 dark:bg-primary-900/20 border border-primary-200 dark:border-primary-800">
                <Link2 className="h-4 w-4 text-primary-600 dark:text-primary-400" />
                <span className="text-sm font-medium text-primary-700 dark:text-primary-300">
                  {selectedPartName}
                </span>
                <button
                  className="ml-auto text-xs text-primary-500 hover:underline"
                  onClick={() => {
                    setSelectedPartId(null);
                    setSelectedPartName('');
                  }}
                >
                  Change
                </button>
              </div>
            ) : (
              /* Search input */
              <div className="relative">
                <Input
                  label="Search for a part"
                  value={searchTerm}
                  onChange={(e) => setSearchTerm(e.target.value)}
                  placeholder="Search by name, code, or MPN..."
                  icon={<Search className="h-4 w-4" />}
                />

                {/* Search results dropdown */}
                {debouncedSearch.length >= 2 && (
                  <div className="absolute z-10 left-0 right-0 top-full mt-1 bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-lg shadow-lg max-h-48 overflow-y-auto">
                    {searching ? (
                      <div className="flex justify-center py-3">
                        <Spinner size="sm" />
                      </div>
                    ) : filteredResults.length === 0 ? (
                      <p className="text-sm text-gray-500 dark:text-gray-400 p-3 text-center">
                        No parts found
                      </p>
                    ) : (
                      filteredResults.map((part) => (
                        <button
                          key={part.id}
                          className="w-full text-left px-3 py-2 hover:bg-gray-50 dark:hover:bg-gray-700/50 transition-colors border-b border-gray-100 dark:border-gray-700/50 last:border-b-0"
                          onClick={() => handleSelectPart(part.id, part.name)}
                        >
                          <div className="flex items-center justify-between">
                            <span className="text-sm font-medium text-gray-900 dark:text-gray-100">
                              {part.name}
                            </span>
                            {part.code && (
                              <span className="text-xs text-gray-500 font-mono">{part.code}</span>
                            )}
                          </div>
                          <div className="flex items-center gap-2 mt-0.5">
                            {part.brand_name && (
                              <span className="text-xs text-gray-500 dark:text-gray-400">
                                {part.brand_name}
                              </span>
                            )}
                            {part.category_name && (
                              <span className="text-xs text-gray-400 dark:text-gray-500">
                                {part.category_name}
                              </span>
                            )}
                          </div>
                        </button>
                      ))
                    )}
                  </div>
                )}
              </div>
            )}
          </div>
        ) : (
          /* Editing — show which part is linked */
          <div className="flex items-center gap-2 p-3 rounded-lg bg-gray-50 dark:bg-gray-800/50 border border-gray-200 dark:border-gray-700">
            <Link2 className="h-4 w-4 text-gray-500 dark:text-gray-400" />
            <span className="text-sm font-medium text-gray-700 dark:text-gray-300">
              {selectedPartName}
            </span>
            <Badge variant="default">Linked</Badge>
          </div>
        )}

        {/* Relationship selector */}
        <div className="space-y-2">
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">
            Relationship
          </label>
          <div className="grid grid-cols-3 gap-2">
            {RELATIONSHIPS.map((rel) => (
              <button
                key={rel.value}
                type="button"
                onClick={() => setRelationship(rel.value)}
                className={`
                  p-3 rounded-lg border text-center transition-colors
                  ${relationship === rel.value
                    ? 'border-primary-500 bg-primary-50 dark:bg-primary-900/20 text-primary-700 dark:text-primary-300'
                    : 'border-gray-200 dark:border-gray-700 hover:bg-gray-50 dark:hover:bg-gray-800 text-gray-700 dark:text-gray-300'
                  }
                `}
              >
                <div className="text-sm font-medium">{rel.label}</div>
                <div className="text-xs text-gray-500 dark:text-gray-400 mt-0.5">
                  {rel.description}
                </div>
              </button>
            ))}
          </div>
        </div>

        {/* Preference toggle */}
        <label className="flex items-center gap-2 cursor-pointer select-none">
          <input
            type="checkbox"
            checked={isPreferred}
            onChange={(e) => setIsPreferred(e.target.checked)}
            className="rounded border-gray-300 dark:border-gray-600 text-primary-600 focus:ring-primary-500"
          />
          <Star className={`h-4 w-4 ${isPreferred ? 'text-amber-500 fill-amber-500' : 'text-gray-400'}`} />
          <span className="text-sm text-gray-700 dark:text-gray-300">
            Mark as preferred alternative
          </span>
        </label>

        {/* Notes */}
        <div className="space-y-1.5">
          <label className="block text-sm font-medium text-gray-700 dark:text-gray-300">
            Notes
          </label>
          <textarea
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            className="w-full rounded-lg border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 px-3 py-2 text-sm min-h-[60px]"
            placeholder="e.g. Better quality, more customizable..."
          />
        </div>
      </div>

      {/* Footer */}
      <div className="flex justify-end gap-2 mt-4 pt-4 border-t border-gray-200 dark:border-gray-700">
        <Button variant="secondary" onClick={onClose}>
          Cancel
        </Button>
        <Button
          variant="primary"
          onClick={handleSubmit}
          disabled={!canSubmit}
          isLoading={isLoading}
        >
          {editingLink ? 'Update Link' : 'Link Part'}
        </Button>
      </div>
    </Modal>
  );
}
