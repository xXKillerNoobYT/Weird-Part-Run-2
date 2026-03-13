/**
 * NotebooksPage — list of all notebooks with search and filter.
 *
 * Filter tabs (All / Job / General) are provided by the navigation
 * TabBar — they drive the URL which we read to determine the filter.
 * This page just renders the header + search + notebook grid.
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

  if (isLoading) return <PageSpinner />;

  return (
    <div className="space-y-4">
      {/* Header row: search + action button */}
      <div className="flex items-center gap-3">
        {/* Search */}
        <div className="relative flex-1 max-w-sm">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-400" />
          <input
            type="text"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search notebooks..."
            className="w-full pl-9 pr-3 py-1.5 rounded-lg border border-border bg-surface text-sm focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
          />
        </div>

        <button
          onClick={() => setShowCreate(true)}
          className="flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium text-white bg-blue-500 hover:bg-blue-600 rounded-lg transition-colors flex-shrink-0"
        >
          <Plus className="h-4 w-4" />
          New Notebook
        </button>
      </div>

      {/* Notebook grid */}
      {notebooks.length === 0 ? (
        <EmptyState
          icon={<BookOpen className="h-10 w-10 text-gray-300 dark:text-gray-600" />}
          title="No notebooks found"
          description={
            search
              ? 'Try adjusting your search'
              : activeTab === 'general'
                ? 'Create a general notebook to get started'
                : activeTab === 'job'
                  ? 'Job notebooks are created automatically when you open a job'
                  : 'No notebooks yet — open a job or create a general notebook'
          }
          action={
            activeTab !== 'job' ? (
              <button
                onClick={() => setShowCreate(true)}
                className="text-sm text-primary hover:underline"
              >
                + Create a notebook
              </button>
            ) : undefined
          }
        />
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
          {notebooks.map((nb: NotebookListItem) => (
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
