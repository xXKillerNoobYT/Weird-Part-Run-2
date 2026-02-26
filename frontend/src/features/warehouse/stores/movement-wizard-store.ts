/**
 * Movement Wizard Store — Zustand with localStorage persistence.
 *
 * Central state for the 7-step movement wizard. Handles:
 * - Step navigation with validation gates
 * - Part selection and quantity management
 * - Location from/to tracking
 * - Movement type inference from location pair
 * - Photo/notes/reason metadata
 * - localStorage backup for resume-on-reopen
 * - Pre-filling from dashboard quick actions
 */

import { create } from 'zustand';
import { persist } from 'zustand/middleware';
import type {
  LocationType,
  MovementLineItem,
  MovementPreview,
  MovementExecuteResponse,
  WizardPartSearchResult,
} from '../../../lib/types';

// ── Movement rules (mirrors backend MOVEMENT_RULES) ─────────────

const MOVEMENT_RULES: Record<
  string,
  { type: string; photo_required: boolean }
> = {
  'warehouse->pulled': { type: 'transfer', photo_required: false },
  'pulled->truck': { type: 'transfer', photo_required: false },
  'warehouse->truck': { type: 'transfer', photo_required: false },
  'truck->job': { type: 'consume', photo_required: true },
  'job->truck': { type: 'return', photo_required: true },
  'truck->warehouse': { type: 'return', photo_required: false },
  'pulled->warehouse': { type: 'return', photo_required: false },
};

// ── Types ────────────────────────────────────────────────────────

export interface WizardPart {
  part_id: number;
  part_name: string;
  part_code?: string | null;
  image_url?: string | null;
  category_name?: string | null;
  shelf_location?: string | null;
  available_qty: number;
  supplier_name?: string | null;
  supplier_id?: number | null;
  qty: number; // user-entered quantity for this movement
}

export type WizardStep = 1 | 2 | 3 | 4 | 5 | 6 | 7;

export interface WizardPresets {
  fromLocationType?: LocationType;
  fromLocationId?: number;
  toLocationType?: LocationType;
  toLocationId?: number;
  selectedParts?: WizardPart[];
  destinationType?: string;
  destinationId?: number;
  destinationLabel?: string;
}

interface MovementWizardState {
  // ── UI State ───────────────────────────────────────
  isOpen: boolean;
  currentStep: WizardStep;
  hasUnsavedState: boolean; // true if store has data from a previous incomplete session

  // ── Step 1: Locations ──────────────────────────────
  fromLocationType: LocationType | null;
  fromLocationId: number;
  toLocationType: LocationType | null;
  toLocationId: number;

  // ── Step 2 & 3: Parts + Quantities ─────────────────
  selectedParts: WizardPart[];

  // ── Step 4: Verification ───────────────────────────
  photoPath: string | null;
  scanConfirmed: boolean;
  qtyConfirmed: boolean;

  // ── Step 5: Notes & Reason ─────────────────────────
  reason: string | null;
  reasonDetail: string | null;
  notes: string | null;
  referenceNumber: string | null;

  // ── Step 6: Preview ────────────────────────────────
  preview: MovementPreview | null;

  // ── Step 7: Execute ────────────────────────────────
  isExecuting: boolean;
  executeResult: MovementExecuteResponse | null;
  executeError: string | null;

  // ── Staging destination hint ───────────────────────
  destinationType: string | null;
  destinationId: number | null;
  destinationLabel: string | null;

  // ── GPS ────────────────────────────────────────────
  gpsLat: number | null;
  gpsLng: number | null;

  // ── Actions ────────────────────────────────────────
  open: (presets?: WizardPresets) => void;
  close: () => void;
  discardAndClose: () => void;
  resumeSession: () => void;

  setStep: (step: WizardStep) => void;
  nextStep: () => void;
  prevStep: () => void;

  setFromLocation: (type: LocationType, id: number) => void;
  setToLocation: (type: LocationType, id: number) => void;

  addPart: (part: WizardPartSearchResult) => void;
  removePart: (partId: number) => void;
  updatePartQty: (partId: number, qty: number) => void;

  setPhoto: (path: string | null) => void;
  setScanConfirmed: (confirmed: boolean) => void;
  setQtyConfirmed: (confirmed: boolean) => void;

  setReason: (reason: string | null) => void;
  setReasonDetail: (detail: string | null) => void;
  setNotes: (notes: string | null) => void;
  setReferenceNumber: (ref: string | null) => void;

  setDestination: (
    type: string | null,
    id: number | null,
    label: string | null
  ) => void;
  setGps: (lat: number | null, lng: number | null) => void;

  setPreview: (preview: MovementPreview | null) => void;
  setExecuting: (executing: boolean) => void;
  setExecuteResult: (result: MovementExecuteResponse | null) => void;
  setExecuteError: (error: string | null) => void;

  // ── Derived / Computed ─────────────────────────────
  getMovementKey: () => string | null;
  getMovementType: () => string | null;
  isPhotoRequired: () => boolean;
  isVerificationRequired: () => boolean;
  canAdvanceFromStep: (step: WizardStep) => boolean;
  buildMovementRequest: () => MovementLineItem[];
  getTotalQty: () => number;
}

const INITIAL_STATE = {
  isOpen: false,
  currentStep: 1 as WizardStep,
  hasUnsavedState: false,
  fromLocationType: null as LocationType | null,
  fromLocationId: 1,
  toLocationType: null as LocationType | null,
  toLocationId: 1,
  selectedParts: [] as WizardPart[],
  photoPath: null as string | null,
  scanConfirmed: false,
  qtyConfirmed: false,
  reason: null as string | null,
  reasonDetail: null as string | null,
  notes: null as string | null,
  referenceNumber: null as string | null,
  preview: null as MovementPreview | null,
  isExecuting: false,
  executeResult: null as MovementExecuteResponse | null,
  executeError: null as string | null,
  destinationType: null as string | null,
  destinationId: null as number | null,
  destinationLabel: null as string | null,
  gpsLat: null as number | null,
  gpsLng: null as number | null,
};

export const useMovementWizardStore = create<MovementWizardState>()(
  persist(
    (set, get) => ({
      ...INITIAL_STATE,

      // ── Open / Close ─────────────────────────────────

      open: (presets?: WizardPresets) => {
        const state = get();

        // If there's unsaved state, don't overwrite — the UI should prompt to resume
        if (state.hasUnsavedState && state.selectedParts.length > 0) {
          set({ isOpen: true });
          return;
        }

        set({
          ...INITIAL_STATE,
          isOpen: true,
          hasUnsavedState: false,
          fromLocationType: presets?.fromLocationType ?? null,
          fromLocationId: presets?.fromLocationId ?? 1,
          toLocationType: presets?.toLocationType ?? null,
          toLocationId: presets?.toLocationId ?? 1,
          selectedParts: presets?.selectedParts ?? [],
          destinationType: presets?.destinationType ?? null,
          destinationId: presets?.destinationId ?? null,
          destinationLabel: presets?.destinationLabel ?? null,
        });
      },

      close: () => {
        const state = get();
        // If there are selected parts and we're mid-flow, mark as unsaved
        if (state.selectedParts.length > 0 && !state.executeResult) {
          set({ isOpen: false, hasUnsavedState: true });
        } else {
          set({ ...INITIAL_STATE });
        }
      },

      discardAndClose: () => {
        set({ ...INITIAL_STATE });
      },

      resumeSession: () => {
        set({ isOpen: true, hasUnsavedState: false });
      },

      // ── Navigation ───────────────────────────────────

      setStep: (step) => set({ currentStep: step }),

      nextStep: () => {
        const state = get();
        const next = state.currentStep + 1;
        if (next > 7) return;

        // Skip verification step if not required
        if (next === 4 && !state.isVerificationRequired()) {
          set({ currentStep: 5 as WizardStep });
          return;
        }

        set({ currentStep: next as WizardStep });
      },

      prevStep: () => {
        const state = get();
        const prev = state.currentStep - 1;
        if (prev < 1) return;

        // Skip verification step backwards too
        if (prev === 4 && !state.isVerificationRequired()) {
          set({ currentStep: 3 as WizardStep });
          return;
        }

        set({ currentStep: prev as WizardStep });
      },

      // ── Locations ────────────────────────────────────

      setFromLocation: (type, id) =>
        set({ fromLocationType: type, fromLocationId: id }),

      setToLocation: (type, id) =>
        set({ toLocationType: type, toLocationId: id }),

      // ── Parts ────────────────────────────────────────

      addPart: (part) => {
        const state = get();
        // Don't add duplicates
        if (state.selectedParts.some((p) => p.part_id === part.part_id)) return;
        // Max 20 parts per movement
        if (state.selectedParts.length >= 20) return;

        set({
          selectedParts: [
            ...state.selectedParts,
            {
              part_id: part.part_id,
              part_name: part.part_name,
              part_code: part.part_code,
              image_url: part.image_url,
              category_name: part.category_name,
              shelf_location: part.shelf_location,
              available_qty: part.available_qty,
              supplier_name: part.supplier_name,
              supplier_id: part.supplier_id,
              qty: 1, // default qty
            },
          ],
        });
      },

      removePart: (partId) => {
        const state = get();
        set({
          selectedParts: state.selectedParts.filter(
            (p) => p.part_id !== partId
          ),
        });
      },

      updatePartQty: (partId, qty) => {
        const state = get();
        set({
          selectedParts: state.selectedParts.map((p) =>
            p.part_id === partId ? { ...p, qty: Math.max(1, qty) } : p
          ),
        });
      },

      // ── Verification ─────────────────────────────────

      setPhoto: (path) => set({ photoPath: path }),
      setScanConfirmed: (confirmed) => set({ scanConfirmed: confirmed }),
      setQtyConfirmed: (confirmed) => set({ qtyConfirmed: confirmed }),

      // ── Notes & Reason ───────────────────────────────

      setReason: (reason) => set({ reason }),
      setReasonDetail: (detail) => set({ reasonDetail: detail }),
      setNotes: (notes) => set({ notes }),
      setReferenceNumber: (ref) => set({ referenceNumber: ref }),

      // ── Destination & GPS ────────────────────────────

      setDestination: (type, id, label) =>
        set({
          destinationType: type,
          destinationId: id,
          destinationLabel: label,
        }),

      setGps: (lat, lng) => set({ gpsLat: lat, gpsLng: lng }),

      // ── Preview & Execute ────────────────────────────

      setPreview: (preview) => set({ preview }),
      setExecuting: (executing) => set({ isExecuting: executing }),
      setExecuteResult: (result) => set({ executeResult: result }),
      setExecuteError: (error) => set({ executeError: error }),

      // ── Computed ─────────────────────────────────────

      getMovementKey: () => {
        const { fromLocationType, toLocationType } = get();
        if (!fromLocationType || !toLocationType) return null;
        return `${fromLocationType}->${toLocationType}`;
      },

      getMovementType: () => {
        const key = get().getMovementKey();
        if (!key) return null;
        return MOVEMENT_RULES[key]?.type ?? null;
      },

      isPhotoRequired: () => {
        const key = get().getMovementKey();
        if (!key) return false;
        return MOVEMENT_RULES[key]?.photo_required ?? false;
      },

      isVerificationRequired: () => {
        const key = get().getMovementKey();
        if (!key) return false;
        return MOVEMENT_RULES[key]?.photo_required ?? false;
      },

      canAdvanceFromStep: (step) => {
        const state = get();

        switch (step) {
          case 1: // Locations
            return (
              !!state.fromLocationType &&
              !!state.toLocationType &&
              state.fromLocationType !== state.toLocationType &&
              !!MOVEMENT_RULES[
                `${state.fromLocationType}->${state.toLocationType}`
              ]
            );

          case 2: // Parts selected
            return state.selectedParts.length > 0;

          case 3: // Quantities valid
            return state.selectedParts.every(
              (p) => p.qty > 0 && p.qty <= p.available_qty
            );

          case 4: // Verification (only if required)
            if (!state.isVerificationRequired()) return true;
            return !!state.photoPath && state.qtyConfirmed;

          case 5: // Notes/reason (always valid — reason is optional)
            return true;

          case 6: // Preview loaded
            return !!state.preview;

          case 7: // Execute complete
            return !!state.executeResult;

          default:
            return false;
        }
      },

      buildMovementRequest: () => {
        const state = get();
        return state.selectedParts.map((p) => ({
          part_id: p.part_id,
          qty: p.qty,
          supplier_id: p.supplier_id ?? undefined,
        }));
      },

      getTotalQty: () => {
        return get().selectedParts.reduce((sum, p) => sum + p.qty, 0);
      },
    }),
    {
      name: 'wiredpart-movement-wizard',
      partialize: (state) => ({
        // Only persist data fields, not UI state or results
        hasUnsavedState: state.hasUnsavedState,
        currentStep: state.currentStep,
        fromLocationType: state.fromLocationType,
        fromLocationId: state.fromLocationId,
        toLocationType: state.toLocationType,
        toLocationId: state.toLocationId,
        selectedParts: state.selectedParts,
        photoPath: state.photoPath,
        scanConfirmed: state.scanConfirmed,
        qtyConfirmed: state.qtyConfirmed,
        reason: state.reason,
        reasonDetail: state.reasonDetail,
        notes: state.notes,
        referenceNumber: state.referenceNumber,
        destinationType: state.destinationType,
        destinationId: state.destinationId,
        destinationLabel: state.destinationLabel,
        gpsLat: state.gpsLat,
        gpsLng: state.gpsLng,
      }),
    }
  )
);
