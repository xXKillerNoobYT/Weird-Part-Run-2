/**
 * MyClockPage — shows the user's current clock-in status.
 *
 * If clocked in: shows job details, running timer, and clock-out button.
 * If not clocked in: shows "Not clocked in" with a list of jobs to clock into.
 */

import { useEffect, useState, useMemo } from 'react';
import { useQuery } from '@tanstack/react-query';
import {
  Clock, Play, Square, MapPin, Navigation, Briefcase, Timer,
} from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { PageSpinner } from '../../../components/ui/Spinner';
import { Button } from '../../../components/ui/Button';
import { Card, CardHeader } from '../../../components/ui/Card';
import { EmptyState } from '../../../components/ui/EmptyState';
import { useClockStore } from '../../../stores/clock-store';
import { getActiveJobs } from '../../../api/jobs';
import type { JobListItem } from '../../../lib/types';

function formatElapsed(totalSeconds: number): string {
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;
  return `${hours.toString().padStart(2, '0')}:${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
}

function formatTime(isoString: string): string {
  const d = new Date(isoString);
  return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

export function MyClockPage() {
  const navigate = useNavigate();
  const {
    isClockedIn, activeEntry, isLoading: clockLoading,
    elapsedSeconds, fetchClockState, clockIn,
  } = useClockStore();

  const [clockingInJobId, setClockingInJobId] = useState<number | null>(null);

  // Fetch clock state on mount
  useEffect(() => {
    fetchClockState();
  }, [fetchClockState]);

  // Load active jobs for the "clock into" list
  const { data: jobs, isLoading: jobsLoading } = useQuery({
    queryKey: ['jobs-active-for-clock'],
    queryFn: () => getActiveJobs({ status: 'active' }),
    enabled: !isClockedIn,
    staleTime: 30_000,
  });

  const handleClockIn = async (job: JobListItem) => {
    setClockingInJobId(job.id);
    try {
      // Request GPS
      let lat: number | undefined;
      let lng: number | undefined;
      if (navigator.geolocation) {
        try {
          const pos = await new Promise<GeolocationPosition>((resolve, reject) => {
            navigator.geolocation.getCurrentPosition(resolve, reject, {
              enableHighAccuracy: true,
              timeout: 10000,
            });
          });
          lat = pos.coords.latitude;
          lng = pos.coords.longitude;
        } catch {
          // GPS unavailable — proceed without
        }
      }
      await clockIn(job.id, lat, lng);
    } finally {
      setClockingInJobId(null);
    }
  };

  if (clockLoading) return <PageSpinner label="Checking clock status..." />;

  // ── CLOCKED IN VIEW ────────────────────────────────────────────

  if (isClockedIn && activeEntry) {
    return (
      <div className="max-w-lg mx-auto space-y-6">
        {/* Timer Display */}
        <div className="text-center py-8">
          <div className="inline-flex items-center justify-center w-16 h-16 rounded-full bg-green-100 dark:bg-green-900/30 mb-4">
            <Timer className="h-8 w-8 text-green-600 dark:text-green-400" />
          </div>
          <p className="text-xs text-green-600 dark:text-green-400 font-medium uppercase tracking-wider mb-1">
            Clocked In
          </p>
          <p className="text-5xl font-mono font-bold text-gray-900 dark:text-gray-100">
            {formatElapsed(elapsedSeconds)}
          </p>
          <p className="text-sm text-gray-500 dark:text-gray-400 mt-2">
            Since {formatTime(activeEntry.clock_in)}
          </p>
        </div>

        {/* Active Job Card */}
        <Card>
          <CardHeader title="Current Job" subtitle={`#${activeEntry.job_number}`} />
          <div className="px-4 pb-4 space-y-3">
            <div>
              <h3 className="text-lg font-semibold text-gray-900 dark:text-gray-100">
                {activeEntry.job_name}
              </h3>
            </div>

            {/* GPS info */}
            {activeEntry.clock_in_gps_lat && (
              <div className="flex items-center gap-2 text-xs text-gray-500 dark:text-gray-400">
                <MapPin className="h-3.5 w-3.5" />
                <span>
                  GPS: {activeEntry.clock_in_gps_lat.toFixed(4)}, {activeEntry.clock_in_gps_lng?.toFixed(4)}
                </span>
              </div>
            )}

            {/* Action Buttons */}
            <div className="flex gap-2 pt-2">
              <Button
                variant="secondary"
                size="sm"
                icon={<Briefcase className="h-4 w-4" />}
                onClick={() => navigate(`/jobs/${activeEntry.job_id}`)}
              >
                View Job
              </Button>
              <Button
                variant="danger"
                size="sm"
                icon={<Square className="h-4 w-4" />}
                onClick={() => navigate(`/jobs/${activeEntry.job_id}`, { state: { startClockOut: true } })}
                className="ml-auto"
              >
                Clock Out
              </Button>
            </div>
          </div>
        </Card>
      </div>
    );
  }

  // ── NOT CLOCKED IN VIEW ────────────────────────────────────────

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="text-center py-6">
        <div className="inline-flex items-center justify-center w-14 h-14 rounded-full bg-gray-100 dark:bg-gray-800 mb-3">
          <Clock className="h-7 w-7 text-gray-400 dark:text-gray-500" />
        </div>
        <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100">
          Not Clocked In
        </h2>
        <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">
          Select a job below to start your clock.
        </p>
      </div>

      {/* Job list for clocking in */}
      {jobsLoading ? (
        <PageSpinner label="Loading jobs..." />
      ) : !jobs || jobs.length === 0 ? (
        <EmptyState
          icon={<Briefcase className="h-12 w-12" />}
          title="No Active Jobs"
          description="There are no active jobs to clock into. Ask your supervisor to create one."
        />
      ) : (
        <div className="space-y-2">
          {jobs.map((job) => (
            <div
              key={job.id}
              className="flex items-center gap-3 p-3 bg-surface border border-border rounded-lg hover:border-green-300 dark:hover:border-green-600 transition-colors"
            >
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                  <span className="text-xs font-mono text-gray-500 dark:text-gray-400">
                    #{job.job_number}
                  </span>
                </div>
                <p className="text-sm font-medium text-gray-900 dark:text-gray-100 truncate">
                  {job.job_name}
                </p>
                <p className="text-xs text-gray-500 dark:text-gray-400 truncate">
                  {job.customer_name}
                  {job.city ? ` — ${job.city}` : ''}
                </p>
              </div>

              {/* Navigate button */}
              {(job.gps_lat || job.address_line1) && (
                <button
                  onClick={() => {
                    const dest = job.gps_lat
                      ? `${job.gps_lat},${job.gps_lng}`
                      : encodeURIComponent([job.address_line1, job.city, job.state].filter(Boolean).join(', '));
                    window.open(`https://www.google.com/maps/dir/?api=1&destination=${dest}`, '_blank');
                  }}
                  className="p-2 text-gray-400 hover:text-blue-500 transition-colors"
                  title="Navigate"
                >
                  <Navigation className="h-4 w-4" />
                </button>
              )}

              {/* Clock In button */}
              <Button
                size="sm"
                icon={<Play className="h-3.5 w-3.5" />}
                isLoading={clockingInJobId === job.id}
                onClick={() => handleClockIn(job)}
              >
                Clock In
              </Button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
