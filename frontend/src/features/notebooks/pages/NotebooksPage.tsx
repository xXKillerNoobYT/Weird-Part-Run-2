/**
 * NotebooksPage — list of all notebooks with filter tabs (All / Job / General).
 *
 * Shows NotebookCards in a responsive grid. Supports search and filter.
 * "New Notebook" button creates general notebooks.
 */

import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Plus, Search, BookOpen } from 'lucide-react';
import { useNavigate, useLocation } from 'react-router-dom';
import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { listNotebooks, createNotebook } from '../../../api/notebooks';
import { NotebookCard } from '../components/NotebookCard';
import { CreateNotebookModal } from '../components/CreateNotebookModal';
import type { NotebookCreate, NotebookListItem } from '../../../lib/types';

type FilterTab = 'all' | 'job' | 'general';

const TABS: { id: FilterTab; label: string; path: string }[] = [
  { id: 'all', label: 'All', path: '/notebooks/all' },
  { id: 'job', label: 'Job Notebooks', path: '/notebooks/job-notebooks' },
  { id: 'general', label: 'General', path: '/notebooks/general' },
];

/** Derive filter tab from the current URL path */
function tabFromPath(pathname: string): FilterTab {
  if (pathname.includes('job-notebooks')) return 'job';
  if (pathname.includes('general')) return 'general';
  return 'all';
}

export function NotebooksPage() {
  const navigate = useNavigate();
  const location = useLocation();
  const queryClient = useQueryClient();
  const activeTab = tabFromPath(location.pathname);
  const [search, setSearch] = useState('');
  const [showCreate, setShowCreate] = useState(false);

  const { data: notebooks = [], isLoading } = useQuery({
    queryKey: ['notebooks', activeTab, search],
    queryFn: () => listNotebooks({ filter: activeTab, search: search || undefined }),
  });

  const createMutation = useMutation({
    mutationFn: (data: NotebookCreate) => createNotebook(data),
    onSuccess: (nb) => {
      queryClient.invalidateQueries({ queryKey: ['notebooks'] });
      setShowCreate(false);
      navigate(`/notebooks/${nb.id}`);
    },
  });

  // Client-side search is already handled by the API, but we
  // can also filter locally for instant feedback
  const filtered = notebooks;

  if (isLoading) return <PageSpinner />;

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between">
        <h1 className="text-lg font-bold text-gray-900 dark:text-gray-100">
          Notebooks
        </h1>
        <button
          onClick={() => setShowCreate(true)}
          className="flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium text-white bg-blue-500 hover:bg-blue-600 rounded-lg transition-colors"
        >
          <Plus className="h-4 w-4" />
          New Notebook
        </button>
      </div>

      {/* Filter tabs + search */}
      <div className="flex flex-col sm:flex-row items-start sm:items-center gap-3">
        {/* Tabs */}
        <div className="flex gap-1 p-1 bg-surface-secondary rounded-lg">
          {TABS.map((tab) => (
            <button
              key={tab.id}
              onClick={() => navigate(tab.path, { replace: true })}
              className={`px-3 py-1.5 text-xs font-medium rounded-md transition-colors ${
                activeTab === tab.id
                  ? 'bg-surface text-gray-900 dark:text-gray-100 shadow-sm'
                  : 'text-gray-500 dark:text-gray-400 hover:text-gray-700 dark:hover:text-gray-300'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>

        {/* Search */}
        <div className="relative flex-1 max-w-xs">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-400" />
          <input
            type="text"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search notebooks..."
            className="w-full pl-9 pr-3 py-1.5 rounded-lg border border-border bg-surface text-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
          />
        </div>
      </div>

      {/* Notebook grid */}
      {filtered.length === 0 ? (
        <EmptyState
          icon={<BookOpen className="h-10 w-10 text-gray-300 dark:text-gray-600" />}
          title="No notebooks found"
          description={
            search
              ? 'Try adjusting your search'
              : activeTab === 'general'
                ? 'Create a general notebook to get started'
                : 'Notebooks are created automatically when you open a job'
          }
        />
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
          {filtered.map((nb: NotebookListItem) => (
            <NotebookCard
              key={nb.id}
              notebook={nb}
              onClick={() => navigate(`/notebooks/${nb.id}`)}
            />
          ))}
        </div>
      )}

      {/* Create modal */}
      {showCreate && (
        <CreateNotebookModal
          onSubmit={(data) => createMutation.mutate(data)}
          onClose={() => setShowCreate(false)}
          loading={createMutation.isPending}
        />
      )}
    </div>
  );
}
