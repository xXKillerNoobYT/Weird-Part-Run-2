/**
 * ToolLinksPanel — self-contained tool linking for notebook task entries.
 *
 * Handles its own queries and mutations so parent components don't need
 * to thread callbacks. Just drop `<ToolLinksPanel entryId={...} />` into
 * any task entry card.
 *
 * Features:
 * - Lists tools linked to the entry as compact chips
 * - "Add Tool" button opens an inline search picker
 * - Remove button per link
 * - Shows tool number, name, status, and location
 */

import { useState, useEffect } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Wrench, Plus, X, Search, MapPin } from 'lucide-react';
import { getEntryTools, linkToolToEntry, unlinkToolFromEntry, getTools } from '../../../api/tools';
import type { EntryToolLink, Tool } from '../../../lib/types';
import { toast } from '../../../lib/toast';

interface ToolLinksPanelProps {
  entryId: number;
  /** Whether the user can add/remove links */
  canEdit?: boolean;
}

export function ToolLinksPanel({ entryId, canEdit }: ToolLinksPanelProps) {
  const queryClient = useQueryClient();
  const [showPicker, setShowPicker] = useState(false);
  const [search, setSearch] = useState('');
  const [debouncedSearch, setDebouncedSearch] = useState('');

  // Debounce search input
  useEffect(() => {
    const timer = setTimeout(() => setDebouncedSearch(search), 300);
    return () => clearTimeout(timer);
  }, [search]);

  // ── Linked tools query ──────────────────────────────────────────
  const { data: links = [] } = useQuery({
    queryKey: ['entry-tools', entryId],
    queryFn: () => getEntryTools(entryId),
  });

  // ── Tool search query (for picker) ─────────────────────────────
  const { data: searchResults } = useQuery({
    queryKey: ['tools-search-picker', debouncedSearch],
    queryFn: () => getTools({ search: debouncedSearch || undefined, page: 1, page_size: 8 }),
    enabled: showPicker && debouncedSearch.length >= 1,
    staleTime: 10_000,
  });

  const invalidate = () => {
    queryClient.invalidateQueries({ queryKey: ['entry-tools', entryId] });
  };

  // ── Mutations ───────────────────────────────────────────────────
  const linkMut = useMutation({
    mutationFn: (toolId: number) => linkToolToEntry(entryId, { tool_id: toolId }),
    onSuccess: () => {
      invalidate();
      setShowPicker(false);
      setSearch('');
      toast.success('Tool linked');
    },
    onError: () => toast.error('Failed to link tool'),
  });

  const unlinkMut = useMutation({
    mutationFn: (toolId: number) => unlinkToolFromEntry(entryId, toolId),
    onSuccess: () => {
      invalidate();
      toast.success('Tool unlinked');
    },
    onError: () => toast.error('Failed to unlink tool'),
  });

  // Already-linked tool IDs for filtering search results
  const linkedIds = new Set(links.map((l: EntryToolLink) => l.tool_id));

  // Filter out already-linked tools from search results
  const availableTools = (searchResults?.items ?? []).filter(
    (t: Tool) => !linkedIds.has(t.id),
  );

  // Don't render anything if no links and no edit ability
  if (links.length === 0 && !canEdit) return null;

  return (
    <div className="mt-2">
      {/* Linked tools chips */}
      {links.length > 0 && (
        <div className="flex items-start gap-1.5 flex-wrap mb-1.5">
          <Wrench className="h-3.5 w-3.5 text-indigo-500 mt-0.5 shrink-0" />
          {links.map((link: EntryToolLink) => (
            <span
              key={link.id}
              className="inline-flex items-center gap-1 px-2 py-0.5 bg-indigo-50 dark:bg-indigo-900/20 border border-indigo-200 dark:border-indigo-800 rounded-md text-xs text-indigo-700 dark:text-indigo-300"
            >
              <span className="font-mono text-[10px]">{link.tool_number}</span>
              <span className="truncate max-w-[120px]">{link.tool_name}</span>
              {link.tool_location_name && (
                <span className="hidden sm:inline-flex items-center gap-0.5 text-[10px] text-indigo-400 dark:text-indigo-500">
                  <MapPin className="h-2.5 w-2.5" />
                  {link.tool_location_name}
                </span>
              )}
              {canEdit && (
                <button
                  onClick={() => unlinkMut.mutate(link.tool_id)}
                  className="ml-0.5 p-0.5 rounded hover:bg-indigo-200 dark:hover:bg-indigo-800 transition-colors"
                  title="Remove tool"
                  disabled={unlinkMut.isPending}
                >
                  <X className="h-3 w-3" />
                </button>
              )}
            </span>
          ))}
        </div>
      )}

      {/* Add tool button */}
      {canEdit && !showPicker && (
        <button
          onClick={() => setShowPicker(true)}
          className="inline-flex items-center gap-1 px-2 py-1 text-xs text-indigo-600 dark:text-indigo-400 hover:bg-indigo-50 dark:hover:bg-indigo-900/20 rounded-md transition-colors min-h-[32px]"
        >
          <Plus className="h-3.5 w-3.5" />
          Add Tool
        </button>
      )}

      {/* Inline tool picker */}
      {canEdit && showPicker && (
        <div className="mt-1 p-2 border border-indigo-200 dark:border-indigo-800 bg-indigo-50/50 dark:bg-indigo-900/10 rounded-lg space-y-2">
          <div className="flex items-center gap-2">
            <div className="flex-1 relative">
              <Search className="absolute left-2 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-gray-400" />
              <input
                type="text"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="Search tools by name or number..."
                className="w-full pl-7 pr-3 py-1.5 text-xs rounded-md border border-gray-300 dark:border-gray-600 bg-white dark:bg-gray-800 text-gray-900 dark:text-gray-100 focus:ring-1 focus:ring-indigo-500 min-h-[36px]"
                autoFocus
              />
            </div>
            <button
              onClick={() => { setShowPicker(false); setSearch(''); }}
              className="p-1.5 rounded text-gray-400 hover:text-gray-600 dark:hover:text-gray-300 hover:bg-gray-200 dark:hover:bg-gray-700 transition-colors min-h-[36px] min-w-[36px] flex items-center justify-center"
              title="Close"
            >
              <X className="h-4 w-4" />
            </button>
          </div>

          {/* Search results */}
          {debouncedSearch.length >= 1 && (
            <div className="max-h-40 overflow-y-auto space-y-1">
              {availableTools.length === 0 ? (
                <p className="text-xs text-gray-400 dark:text-gray-500 py-2 text-center">
                  {debouncedSearch ? 'No matching tools found' : 'Type to search...'}
                </p>
              ) : (
                availableTools.map((tool: Tool) => (
                  <button
                    key={tool.id}
                    onClick={() => linkMut.mutate(tool.id)}
                    disabled={linkMut.isPending}
                    className="w-full flex items-center gap-2 px-2 py-1.5 text-left text-xs rounded-md hover:bg-indigo-100 dark:hover:bg-indigo-900/30 transition-colors min-h-[36px]"
                  >
                    <Wrench className="h-3.5 w-3.5 text-gray-400 shrink-0" />
                    <span className="font-mono text-[10px] text-gray-500 dark:text-gray-400 shrink-0">
                      {tool.tool_number}
                    </span>
                    <span className="truncate text-gray-900 dark:text-gray-100">
                      {tool.name}
                    </span>
                    <span className={`ml-auto shrink-0 px-1.5 py-0.5 rounded text-[10px] ${tool.status === 'available'
                        ? 'bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-400'
                        : 'bg-gray-100 dark:bg-gray-700 text-gray-600 dark:text-gray-400'
                      }`}>
                      {tool.status.replace('_', ' ')}
                    </span>
                  </button>
                ))
              )}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
