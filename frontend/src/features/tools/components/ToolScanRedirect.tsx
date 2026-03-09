/**
 * ToolScanRedirect — resolves a QR-scanned tool number to the correct page.
 *
 * Route: /tools/scan/:toolNumber
 *
 * When a user scans a tool's QR code (or types the tool number into a scan
 * field), this component:
 *   1. Extracts the toolNumber from the URL
 *   2. Calls the backend /api/tools/scan/:toolNumber endpoint
 *   3. Based on the tool's current location_type, redirects to:
 *      - warehouse → /warehouse/tools?tool={id}
 *      - truck     → /trucks/tools?tool={id}
 *      - job       → /jobs/{jobId}?tab=tools&tool={id}
 *
 * If the tool doesn't exist or the lookup fails, shows a friendly error
 * with a manual search option.
 */

import { useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { QrCode, AlertTriangle, ArrowLeft } from 'lucide-react';
import { scanTool } from '../../../api/tools';
import { PageSpinner } from '../../../components/ui/Spinner';
import { Button } from '../../../components/ui/Button';

export function ToolScanRedirect() {
  const { toolNumber } = useParams<{ toolNumber: string }>();
  const navigate = useNavigate();

  const { data: tool, isLoading, error } = useQuery({
    queryKey: ['tool-scan', toolNumber],
    queryFn: () => scanTool(toolNumber!),
    enabled: !!toolNumber,
    retry: false,          // Don't retry — the tool number is either valid or not
    staleTime: Infinity,   // No need to refetch; this is a one-shot lookup
  });

  // Redirect once we have the tool data
  useEffect(() => {
    if (!tool) return;

    switch (tool.location_type) {
      case 'truck':
        navigate(`/trucks/tools?tool=${tool.id}`, { replace: true });
        break;
      case 'job':
        navigate(`/jobs/${tool.location_id}?tab=tools&tool=${tool.id}`, { replace: true });
        break;
      case 'warehouse':
      default:
        navigate(`/warehouse/tools?tool=${tool.id}`, { replace: true });
        break;
    }
  }, [tool, navigate]);

  // ── Loading ──
  if (isLoading) {
    return (
      <div className="flex flex-col items-center justify-center py-24 gap-4">
        <QrCode className="h-10 w-10 text-primary-500 animate-pulse" />
        <p className="text-sm text-gray-500 dark:text-gray-400">
          Looking up tool <span className="font-mono font-medium text-gray-700 dark:text-gray-300">{toolNumber}</span>...
        </p>
      </div>
    );
  }

  // ── Error / Not found ──
  if (error || !tool) {
    return (
      <div className="flex flex-col items-center justify-center py-24 gap-4 max-w-sm mx-auto text-center">
        <AlertTriangle className="h-10 w-10 text-amber-500" />
        <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100">
          Tool Not Found
        </h2>
        <p className="text-sm text-gray-500 dark:text-gray-400">
          No tool with number{' '}
          <span className="font-mono font-medium text-gray-700 dark:text-gray-300">{toolNumber}</span>{' '}
          was found. It may have been retired or the QR code may be outdated.
        </p>
        <div className="flex gap-3 mt-2">
          <Button variant="secondary" size="sm" onClick={() => navigate(-1)}>
            <ArrowLeft className="h-4 w-4 mr-1" /> Go Back
          </Button>
          <Button size="sm" onClick={() => navigate('/warehouse/tools')}>
            Search All Tools
          </Button>
        </div>
      </div>
    );
  }

  // If we reach here, we're about to redirect (useEffect should fire)
  return <PageSpinner label="Redirecting..." />;
}
