/**
 * MyOrdersPage — unified personal orders workspace.
 *
 * Aggregates the current user's JPOs (requests), recent returns, and
 * pending actions into a single dashboard-style view.
 *
 * Field workers see: their own requests + returns + quick actions.
 * Office staff see: everything + approval queue count.
 */

import { useMemo } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import {
  ShoppingCart, Plus, ArrowRight, Package, RotateCcw,
  Clock, CheckCircle, AlertCircle, FileText,
} from 'lucide-react';
import { PageSpinner } from '../../../components/ui/Spinner';
import { EmptyState } from '../../../components/ui/EmptyState';
import { Badge } from '../../../components/ui/Badge';
import { Button } from '../../../components/ui/Button';
import { Card } from '../../../components/ui/Card';
import { useAuthStore } from '../../../stores/auth-store';
import { PERMISSIONS } from '../../../lib/constants';
import { listJPOs, listReturns, countPendingApprovals } from '../../../api/orders';
import type { JPOListItem, ReturnListItem } from '../../../lib/types';


const STATUS_COLORS: Record<string, string> = {
  draft: 'neutral',
  pending_approval: 'warning',
  approved: 'success',
  in_progress: 'info',
  completed: 'success',
  cancelled: 'neutral',
  submitted: 'info',
  receiving: 'info',
};

function statusBadge(status: string) {
  const variant = (STATUS_COLORS[status] ?? 'neutral') as 'neutral' | 'warning' | 'success' | 'info';
  return (
    <Badge variant={variant} className="text-[10px]">
      {status.replace(/_/g, ' ')}
    </Badge>
  );
}


export function MyOrdersPage() {
  const navigate = useNavigate();
  const { user, hasPermission } = useAuthStore();
  const userId = user?.id;
  const canManageOrders = hasPermission(PERMISSIONS.MANAGE_ORDERS);

  // ── Data queries ──────────────────────────────────────────────
  const { data: myJPOs, isLoading: jpoLoading } = useQuery({
    queryKey: ['jpos', 'my-orders', userId],
    queryFn: () => listJPOs({ requested_by: userId! }),
    enabled: !!userId,
    staleTime: 30_000,
  });

  const { data: allReturns, isLoading: returnsLoading } = useQuery({
    queryKey: ['returns', 'recent'],
    queryFn: () => listReturns(),
    staleTime: 60_000,
  });

  const { data: approvalCounts } = useQuery({
    queryKey: ['pending-approval-counts'],
    queryFn: countPendingApprovals,
    enabled: canManageOrders,
    staleTime: 30_000,
  });

  // ── Computed data ─────────────────────────────────────────────
  const jposByStatus = useMemo(() => {
    if (!myJPOs) return { draft: 0, pending: 0, approved: 0, inProgress: 0, completed: 0 };
    return {
      draft: myJPOs.filter(j => j.status === 'draft').length,
      pending: myJPOs.filter(j => j.status === 'pending_approval').length,
      approved: myJPOs.filter(j => j.status === 'approved').length,
      inProgress: myJPOs.filter(j => j.status === 'in_progress').length,
      completed: myJPOs.filter(j => j.status === 'completed').length,
    };
  }, [myJPOs]);

  const activeJPOs = useMemo(
    () => (myJPOs ?? []).filter(j => j.status !== 'completed' && j.status !== 'cancelled'),
    [myJPOs],
  );

  const recentReturns = useMemo(
    () => (allReturns ?? []).slice(0, 5),
    [allReturns],
  );

  const isLoading = jpoLoading || returnsLoading;
  if (isLoading) return <PageSpinner />;

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div className="flex items-center gap-3">
          <ShoppingCart size={24} className="text-gray-600 dark:text-gray-400" />
          <div>
            <h1 className="text-xl font-bold text-gray-900 dark:text-white">
              My Orders
            </h1>
            <p className="text-sm text-gray-500 dark:text-gray-400">
              Your requests, returns, and pending actions
            </p>
          </div>
        </div>
        <Button size="sm" onClick={() => navigate('/orders/new-order')}>
          <Plus size={14} />
          <span className="hidden sm:inline ml-1">New Order</span>
        </Button>
      </div>

      {/* Summary cards */}
      <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
        <SummaryCard
          icon={<FileText size={16} className="text-gray-400" />}
          label="Drafts"
          count={jposByStatus.draft}
          onClick={() => navigate('/orders/all-requests')}
        />
        <SummaryCard
          icon={<Clock size={16} className="text-yellow-500" />}
          label="Pending"
          count={jposByStatus.pending}
          highlight={jposByStatus.pending > 0}
          onClick={() => navigate('/orders/all-requests')}
        />
        <SummaryCard
          icon={<CheckCircle size={16} className="text-green-500" />}
          label="Approved"
          count={jposByStatus.approved}
          onClick={() => navigate('/orders/all-requests')}
        />
        <SummaryCard
          icon={<Package size={16} className="text-blue-500" />}
          label="In Progress"
          count={jposByStatus.inProgress}
          onClick={() => navigate('/orders/all-requests')}
        />
        <SummaryCard
          icon={<CheckCircle size={16} className="text-gray-400" />}
          label="Completed"
          count={jposByStatus.completed}
          onClick={() => navigate('/orders/all-requests')}
        />
      </div>

      {/* Approval queue alert (office staff) */}
      {canManageOrders && approvalCounts && approvalCounts.total > 0 && (
        <Card className="p-4 border-l-4 border-l-yellow-400">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <AlertCircle size={20} className="text-yellow-500" />
              <div>
                <p className="font-medium text-gray-900 dark:text-white">
                  {approvalCounts.total} request{approvalCounts.total !== 1 ? 's' : ''} pending approval
                </p>
                <p className="text-sm text-gray-500 dark:text-gray-400">
                  Review and approve parts requests from the team
                </p>
              </div>
            </div>
            <Button
              size="sm"
              variant="secondary"
              onClick={() => navigate('/orders/approvals')}
            >
              Review
              <ArrowRight size={14} className="ml-1" />
            </Button>
          </div>
        </Card>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        {/* Active requests */}
        <Card className="p-4">
          <div className="flex items-center justify-between mb-3">
            <h2 className="font-semibold text-gray-900 dark:text-white">
              Active Requests
            </h2>
            <Link
              to="/orders/all-requests"
              className="text-xs text-blue-600 dark:text-blue-400 hover:underline"
            >
              View all
            </Link>
          </div>

          {activeJPOs.length === 0 ? (
            <div className="text-center py-6 text-sm text-gray-400 dark:text-gray-500">
              No active requests. Create a new order to get started.
            </div>
          ) : (
            <div className="space-y-2">
              {activeJPOs.slice(0, 8).map(jpo => (
                <Link
                  key={jpo.id}
                  to={`/orders/jpos/${jpo.id}`}
                  className="block p-2 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-800
                             border border-gray-100 dark:border-gray-800 transition-colors"
                >
                  <div className="flex items-center justify-between">
                    <div className="min-w-0">
                      <div className="flex items-center gap-2">
                        <span className="font-medium text-sm text-gray-900 dark:text-white truncate">
                          {jpo.order_number}
                        </span>
                        {statusBadge(jpo.status)}
                      </div>
                      {jpo.job_name && (
                        <p className="text-xs text-gray-500 dark:text-gray-400 truncate mt-0.5">
                          {jpo.job_name}
                        </p>
                      )}
                    </div>
                    <div className="text-xs text-gray-400 dark:text-gray-500 flex-shrink-0 ml-2">
                      {jpo.line_count} item{jpo.line_count !== 1 ? 's' : ''}
                    </div>
                  </div>
                </Link>
              ))}
              {activeJPOs.length > 8 && (
                <p className="text-xs text-gray-400 dark:text-gray-500 text-center pt-1">
                  +{activeJPOs.length - 8} more
                </p>
              )}
            </div>
          )}
        </Card>

        {/* Recent returns */}
        <Card className="p-4">
          <div className="flex items-center justify-between mb-3">
            <h2 className="font-semibold text-gray-900 dark:text-white">
              Recent Returns
            </h2>
            <Link
              to="/orders/returns"
              className="text-xs text-blue-600 dark:text-blue-400 hover:underline"
            >
              View all
            </Link>
          </div>

          {recentReturns.length === 0 ? (
            <div className="text-center py-6 text-sm text-gray-400 dark:text-gray-500">
              No recent returns.
            </div>
          ) : (
            <div className="space-y-2">
              {recentReturns.map(ret => (
                <Link
                  key={ret.id}
                  to={`/orders/returns/${ret.id}`}
                  className="block p-2 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-800
                             border border-gray-100 dark:border-gray-800 transition-colors"
                >
                  <div className="flex items-center justify-between">
                    <div className="min-w-0">
                      <div className="flex items-center gap-2">
                        <RotateCcw size={12} className="text-gray-400 flex-shrink-0" />
                        <span className="font-medium text-sm text-gray-900 dark:text-white truncate">
                          {ret.return_number}
                        </span>
                        {statusBadge(ret.status)}
                      </div>
                      <p className="text-xs text-gray-500 dark:text-gray-400 truncate mt-0.5 ml-5">
                        {ret.return_type === 'job_to_warehouse' ? 'Job → Warehouse' : 'Warehouse → Supplier'}
                        {ret.job_name ? ` · ${ret.job_name}` : ''}
                      </p>
                    </div>
                    <div className="text-xs text-gray-400 dark:text-gray-500 flex-shrink-0 ml-2">
                      {ret.line_count} item{ret.line_count !== 1 ? 's' : ''}
                    </div>
                  </div>
                </Link>
              ))}
            </div>
          )}
        </Card>
      </div>

      {/* Quick actions */}
      <Card className="p-4">
        <h2 className="font-semibold text-gray-900 dark:text-white mb-3">
          Quick Actions
        </h2>
        <div className="flex flex-wrap gap-2">
          <Button size="sm" variant="secondary" onClick={() => navigate('/orders/new-order')}>
            <Plus size={14} />
            <span className="ml-1">New Parts Request</span>
          </Button>
          <Button size="sm" variant="secondary" onClick={() => navigate('/orders/returns/new')}>
            <RotateCcw size={14} />
            <span className="ml-1">New Return</span>
          </Button>
          {canManageOrders && (
            <>
              <Button size="sm" variant="secondary" onClick={() => navigate('/orders/purchase-orders')}>
                <Package size={14} />
                <span className="ml-1">Purchase Orders</span>
              </Button>
              <Button size="sm" variant="secondary" onClick={() => navigate('/orders/procurement')}>
                <ShoppingCart size={14} />
                <span className="ml-1">Procurement</span>
              </Button>
            </>
          )}
        </div>
      </Card>
    </div>
  );
}


function SummaryCard({
  icon, label, count, highlight, onClick,
}: {
  icon: React.ReactNode;
  label: string;
  count: number;
  highlight?: boolean;
  onClick?: () => void;
}) {
  return (
    <button
      onClick={onClick}
      className={`
        p-3 rounded-lg border text-left transition-colors
        ${highlight
          ? 'border-yellow-300 bg-yellow-50 dark:border-yellow-700 dark:bg-yellow-900/20'
          : 'border-gray-200 bg-white dark:border-gray-700 dark:bg-gray-900'
        }
        hover:bg-gray-50 dark:hover:bg-gray-800
      `}
    >
      <div className="flex items-center gap-2 mb-1">
        {icon}
        <span className="text-xs text-gray-500 dark:text-gray-400">{label}</span>
      </div>
      <div className="text-xl font-bold text-gray-900 dark:text-white">
        {count}
      </div>
    </button>
  );
}
