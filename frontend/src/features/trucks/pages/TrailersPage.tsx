/**
 * TrailersPage — list of all job trailers with search, status filters, and create action.
 *
 * Shows TrailerCards in a responsive grid. Managers can create new trailers
 * and access fleet-wide management. Follows the AllTrucksPage pattern.
 */

import { useState, useEffect, useCallback } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Plus, Search, Filter, Container, X } from 'lucide-react';
import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { Button } from '../../../components/ui/Button';
import { Input } from '../../../components/ui/Input';
import { useAuthStore } from '../../../stores/auth-store';
import { PERMISSIONS } from '../../../lib/constants';
import { listTrailers } from '../../../api/vehicles';
import { TrailerCard } from '../components/TrailerCard';
import { CreateTrailerModal } from '../components/CreateTrailerModal';
import type { TrailerStatus } from '../../../lib/types';

const STATUS_OPTIONS: { label: string; value: TrailerStatus | 'all' }[] = [
    { label: 'All', value: 'all' },
    { label: 'Active', value: 'active' },
    { label: 'In Transit', value: 'in_transit' },
    { label: 'Maintenance', value: 'maintenance' },
    { label: 'Inactive', value: 'inactive' },
];

export function TrailersPage() {
    const { hasPermission } = useAuthStore();
    const canManageFleet = hasPermission(PERMISSIONS.MANAGE_FLEET);

    // ── Filters ──
    const [search, setSearch] = useState('');
    const [debouncedSearch, setDebouncedSearch] = useState('');
    const [statusFilter, setStatusFilter] = useState<string>('all');
    const [showFilters, setShowFilters] = useState(false);
    const [showCreate, setShowCreate] = useState(false);

    // Debounce search
    useEffect(() => {
        const timer = setTimeout(() => setDebouncedSearch(search), 300);
        return () => clearTimeout(timer);
    }, [search]);

    const { data: trailers, isLoading, error } = useQuery({
        queryKey: ['trailers', debouncedSearch],
        queryFn: () => listTrailers({ search: debouncedSearch || undefined }),
        staleTime: 15_000,
    });

    // Client-side status filter (backend search covers name/code)
    const filtered = trailers?.filter(
        (t) => statusFilter === 'all' || t.status === statusFilter,
    );

    const hasActiveFilters = statusFilter !== 'all';

    const clearFilters = useCallback(() => {
        setStatusFilter('all');
    }, []);

    if (isLoading) return <PageSpinner label="Loading trailers..." />;

    if (error) {
        return (
            <div className="text-center py-16">
                <p className="text-red-500">Failed to load trailers. Please try again.</p>
            </div>
        );
    }

    return (
        <div className="space-y-4">
            {/* Header — search + filter + create */}
            <div className="flex items-center gap-3 flex-wrap">
                <div className="flex-1 min-w-[200px]">
                    <Input
                        placeholder="Search trailers..."
                        value={search}
                        onChange={(e) => setSearch(e.target.value)}
                        icon={<Search className="h-4 w-4" />}
                        iconRight={
                            search ? (
                                <button onClick={() => setSearch('')} className="text-gray-400 hover:text-gray-600">
                                    <X className="h-4 w-4" />
                                </button>
                            ) : undefined
                        }
                    />
                </div>

                <Button
                    variant={hasActiveFilters ? 'primary' : 'secondary'}
                    size="sm"
                    icon={<Filter className="h-4 w-4" />}
                    onClick={() => setShowFilters(!showFilters)}
                >
                    <span className="hidden sm:inline">Filter</span>
                </Button>

                {canManageFleet && (
                    <Button
                        size="sm"
                        icon={<Plus className="h-4 w-4" />}
                        onClick={() => setShowCreate(true)}
                    >
                        <span className="hidden sm:inline">New Trailer</span>
                    </Button>
                )}
            </div>

            {/* Filter panel */}
            {showFilters && (
                <div className="flex flex-wrap gap-4 p-3 bg-surface-secondary rounded-lg border border-border">
                    {/* Status chips */}
                    <div className="flex items-center gap-2 flex-wrap">
                        <span className="text-xs font-medium text-gray-500 dark:text-gray-400">Status:</span>
                        <div className="flex gap-1 flex-wrap">
                            {STATUS_OPTIONS.map((opt) => (
                                <button
                                    key={opt.value}
                                    onClick={() => setStatusFilter(opt.value)}
                                    className={`px-3 py-1.5 text-xs rounded-full transition-colors min-h-[36px] ${statusFilter === opt.value
                                            ? 'bg-blue-100 dark:bg-blue-900/40 text-blue-700 dark:text-blue-300'
                                            : 'bg-gray-100 dark:bg-gray-800 text-gray-600 dark:text-gray-400 hover:bg-gray-200 dark:hover:bg-gray-700'
                                        }`}
                                >
                                    {opt.label}
                                </button>
                            ))}
                        </div>
                    </div>

                    {hasActiveFilters && (
                        <button
                            onClick={clearFilters}
                            className="text-xs text-blue-500 hover:text-blue-700 dark:hover:text-blue-300"
                        >
                            Clear filters
                        </button>
                    )}
                </div>
            )}

            {/* Summary chip */}
            {filtered && filtered.length > 0 && (
                <p className="text-xs text-gray-500 dark:text-gray-400">
                    {filtered.length} trailer{filtered.length !== 1 ? 's' : ''}
                    {debouncedSearch ? ` matching "${debouncedSearch}"` : ''}
                </p>
            )}

            {/* Trailer grid */}
            {!filtered || filtered.length === 0 ? (
                <EmptyState
                    icon={<Container className="h-12 w-12" />}
                    title={
                        debouncedSearch || hasActiveFilters
                            ? 'No trailers match filters'
                            : 'No Trailers'
                    }
                    description={
                        debouncedSearch || hasActiveFilters
                            ? 'Try adjusting your search or filters.'
                            : 'Add your first trailer to start tracking mobile inventory.'
                    }
                    action={
                        canManageFleet && !debouncedSearch && !hasActiveFilters ? (
                            <Button icon={<Plus className="h-4 w-4" />} onClick={() => setShowCreate(true)}>
                                Add Trailer
                            </Button>
                        ) : undefined
                    }
                />
            ) : (
                <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-3">
                    {filtered.map((t) => (
                        <TrailerCard key={t.id} trailer={t} />
                    ))}
                </div>
            )}

            {/* Create modal */}
            <CreateTrailerModal
                isOpen={showCreate}
                onClose={() => setShowCreate(false)}
            />
        </div>
    );
}
