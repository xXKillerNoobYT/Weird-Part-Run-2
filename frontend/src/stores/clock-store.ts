/**
 * Clock store — manages active clock-in state via Zustand.
 *
 * This store tracks:
 * - Whether the current user is clocked into a job
 * - The active labor entry (job name, clock-in time, elapsed time)
 * - GPS location state for clock-in/out
 * - Elapsed time timer (updates every second while clocked in)
 *
 * The store syncs with the backend on init and after clock-in/out.
 */

import { create } from 'zustand';
import type { ActiveClockResponse, LaborEntryResponse } from '../lib/types';
import { getMyClock, clockIn as apiClockIn, clockOut as apiClockOut } from '../api/jobs';
import type { ClockOutRequest } from '../lib/types';

interface ClockState {
  /** Whether the user is currently clocked in */
  isClockedIn: boolean;
  /** The active labor entry, if any */
  activeEntry: LaborEntryResponse | null;
  /** Loading state for clock operations */
  isLoading: boolean;
  /** Error message from last operation */
  error: string | null;
  /** Elapsed seconds since clock-in */
  elapsedSeconds: number;
  /** Timer interval ID */
  _timerId: ReturnType<typeof setInterval> | null;

  /** Fetch the current clock state from the backend */
  fetchClockState: () => Promise<void>;
  /** Clock in to a job */
  clockIn: (jobId: number, gpsLat?: number, gpsLng?: number) => Promise<LaborEntryResponse>;
  /** Clock out from the current job */
  clockOut: (request: ClockOutRequest) => Promise<LaborEntryResponse>;
  /** Start the elapsed-time ticker */
  _startTimer: () => void;
  /** Stop the elapsed-time ticker */
  _stopTimer: () => void;
  /** Calculate elapsed seconds from clock-in time */
  _calcElapsed: (clockInTime: string) => number;
}

export const useClockStore = create<ClockState>((set, get) => ({
  isClockedIn: false,
  activeEntry: null,
  isLoading: false,
  error: null,
  elapsedSeconds: 0,
  _timerId: null,

  fetchClockState: async () => {
    set({ isLoading: true, error: null });
    try {
      const result: ActiveClockResponse = await getMyClock();
      set({
        isClockedIn: result.is_clocked_in,
        activeEntry: result.entry ?? null,
        isLoading: false,
      });

      // Start the timer if clocked in
      if (result.is_clocked_in && result.entry) {
        get()._startTimer();
      } else {
        get()._stopTimer();
      }
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : 'Failed to fetch clock state';
      set({ isLoading: false, error: message });
    }
  },

  clockIn: async (jobId: number, gpsLat?: number, gpsLng?: number) => {
    set({ isLoading: true, error: null });
    try {
      const entry = await apiClockIn(jobId, {
        gps_lat: gpsLat,
        gps_lng: gpsLng,
      });
      set({
        isClockedIn: true,
        activeEntry: entry,
        isLoading: false,
      });
      get()._startTimer();
      return entry;
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : 'Failed to clock in';
      set({ isLoading: false, error: message });
      throw err;
    }
  },

  clockOut: async (request: ClockOutRequest) => {
    set({ isLoading: true, error: null });
    try {
      const entry = await apiClockOut(request);
      set({
        isClockedIn: false,
        activeEntry: null,
        isLoading: false,
        elapsedSeconds: 0,
      });
      get()._stopTimer();
      return entry;
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : 'Failed to clock out';
      set({ isLoading: false, error: message });
      throw err;
    }
  },

  _startTimer: () => {
    const state = get();
    // Clear any existing timer
    if (state._timerId) clearInterval(state._timerId);

    if (!state.activeEntry?.clock_in) return;

    // Calculate initial elapsed time
    const elapsed = state._calcElapsed(state.activeEntry.clock_in);
    set({ elapsedSeconds: elapsed });

    // Update every second
    const timerId = setInterval(() => {
      const { activeEntry } = get();
      if (!activeEntry?.clock_in) return;
      set({ elapsedSeconds: get()._calcElapsed(activeEntry.clock_in) });
    }, 1000);

    set({ _timerId: timerId });
  },

  _stopTimer: () => {
    const { _timerId } = get();
    if (_timerId) {
      clearInterval(_timerId);
      set({ _timerId: null });
    }
  },

  _calcElapsed: (clockInTime: string) => {
    const clockIn = new Date(clockInTime).getTime();
    const now = Date.now();
    return Math.max(0, Math.floor((now - clockIn) / 1000));
  },
}));
