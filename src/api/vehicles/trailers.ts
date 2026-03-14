/**
 * Job trailer CRUD, inventory, location tracking, and stock templates.
 */

import apiClient from '../client';
import type {
  ApiResponse,
  StatusMessage,
  JobTrailerCreate,
  JobTrailerUpdate,
  JobTrailer,
  TrailerLocationEventCreate,
  TrailerLocationEvent,
  TrailerInventoryItem,
  TrailerStockTemplate,
  TrailerStockTemplateCreate,
  TrailerRestockGuidance,
} from '../../lib/types';
import { adaptedRequest } from '../adapter';


// =================================================================
// JOB TRAILERS -- CRUD
// =================================================================

/** List active job trailers with optional search. */
export async function listTrailers(params?: {
  search?: string;
}): Promise<JobTrailer[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<JobTrailer[]>>(
    '/trucks/trailers',
    { params },
  );
  return data.data ?? [];
    },
    async () => [] as unknown as JobTrailer[],
  );
}

/** Create a new job trailer. */
export async function createTrailer(
  trailer: JobTrailerCreate,
): Promise<JobTrailer> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<JobTrailer>>(
    '/trucks/trailers',
    trailer,
  );
  return data.data!;
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}

/** Update a job trailer. */
export async function updateTrailer(
  trailerId: number,
  update: JobTrailerUpdate,
): Promise<JobTrailer> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<JobTrailer>>(
    `/trucks/trailers/${trailerId}`,
    update,
  );
  return data.data!;
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}

/** Deactivate (soft delete) a job trailer. */
export async function deactivateTrailer(
  trailerId: number,
): Promise<StatusMessage> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.delete<ApiResponse<StatusMessage>>(
    `/trucks/trailers/${trailerId}`,
  );
  return data.data!;
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}


// =================================================================
// JOB TRAILERS -- INVENTORY
// =================================================================

/** Get inventory currently loaded on a trailer. */
export async function getTrailerInventory(
  trailerId: number,
  params?: { search?: string },
): Promise<TrailerInventoryItem[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<TrailerInventoryItem[]>>(
    `/trucks/trailers/${trailerId}/inventory`,
    { params },
  );
  return data.data ?? [];
    },
    async () => [] as unknown as TrailerInventoryItem[],
  );
}

/** Preload stock onto a trailer (warehouse/pulled -> trailer). */
export async function preloadTrailerInventory(
  trailerId: number,
  params: {
    part_id: number;
    qty: number;
    from_location_type?: string;
    from_location_id?: number;
    notes?: string;
  },
): Promise<{ part_id: number; qty: number; trailer_id: number }> {
  const { data } = await apiClient.post<
    ApiResponse<{ part_id: number; qty: number; trailer_id: number }>
  >(`/trucks/trailers/${trailerId}/inventory/preload`, null, { params });
  return data.data!;
}

/** Consume stock from trailer to a job (the billing boundary). */
export async function consumeTrailerToJob(
  trailerId: number,
  params: {
    part_id: number;
    qty: number;
    job_id: number;
    notes?: string;
    photo_path?: string;
    scan_confirmed?: boolean;
  },
): Promise<{ part_id: number; qty: number; job_id: number }> {
  const { data } = await apiClient.post<
    ApiResponse<{ part_id: number; qty: number; job_id: number }>
  >(`/trucks/trailers/${trailerId}/inventory/consume`, null, { params });
  return data.data!;
}

/** Return stock from trailer to a destination (default: warehouse). */
export async function returnTrailerInventory(
  trailerId: number,
  params: {
    part_id: number;
    qty: number;
    to_location_type?: string;
    to_location_id?: number;
    notes?: string;
  },
): Promise<{ part_id: number; qty: number }> {
  const { data } = await apiClient.post<
    ApiResponse<{ part_id: number; qty: number }>
  >(`/trucks/trailers/${trailerId}/inventory/return`, null, { params });
  return data.data!;
}


// =================================================================
// JOB TRAILERS -- LOCATION TRACKING
// =================================================================

/** Get latest known location for a trailer. */
export async function getTrailerLocation(
  trailerId: number,
): Promise<TrailerLocationEvent | null> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<TrailerLocationEvent | null>>(
    `/trucks/trailers/${trailerId}/location`,
  );
  return data.data ?? null;
    },
    async () => ({}) as unknown as TrailerLocationEvent | null,
  );
}

/** List location event history for a trailer (newest first). */
export async function listTrailerLocationEvents(
  trailerId: number,
  params?: { limit?: number },
): Promise<TrailerLocationEvent[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<TrailerLocationEvent[]>>(
    `/trucks/trailers/${trailerId}/location-events`,
    { params },
  );
  return data.data ?? [];
    },
    async () => [] as unknown as TrailerLocationEvent[],
  );
}

/** Record a new location event / check-in for a trailer. */
export async function createTrailerLocationEvent(
  trailerId: number,
  event: TrailerLocationEventCreate,
): Promise<TrailerLocationEvent> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<TrailerLocationEvent>>(
    `/trucks/trailers/${trailerId}/location-events`,
    event,
  );
  return data.data!;
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}


// =================================================================
// TRAILER STOCK TEMPLATES
// =================================================================

/** List trailer stock templates (global + trailer-specific). */
export async function listTrailerTemplates(params?: {
  trailer_id?: number;
  include_global?: boolean;
}): Promise<TrailerStockTemplate[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<TrailerStockTemplate[]>>(
    '/trucks/trailer-templates',
    { params },
  );
  return data.data ?? [];
    },
    async () => [] as unknown as TrailerStockTemplate[],
  );
}

/** Get a single template with its lines. */
export async function getTrailerTemplate(
  templateId: number,
): Promise<TrailerStockTemplate> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<TrailerStockTemplate>>(
    `/trucks/trailer-templates/${templateId}`,
  );
  return data.data!;
    },
    async () => ({}) as unknown as TrailerStockTemplate,
  );
}

/** Create a new trailer stock template. */
export async function createTrailerTemplate(
  template: TrailerStockTemplateCreate,
): Promise<TrailerStockTemplate> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<TrailerStockTemplate>>(
    '/trucks/trailer-templates',
    template,
  );
  return data.data!;
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}

/** Update a trailer stock template. */
export async function updateTrailerTemplate(
  templateId: number,
  update: Partial<TrailerStockTemplateCreate>,
): Promise<TrailerStockTemplate> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<TrailerStockTemplate>>(
    `/trucks/trailer-templates/${templateId}`,
    update,
  );
  return data.data!;
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}

/** Delete a trailer stock template. */
export async function deleteTrailerTemplate(
  templateId: number,
): Promise<StatusMessage> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.delete<ApiResponse<StatusMessage>>(
    `/trucks/trailer-templates/${templateId}`,
  );
  return data.data!;
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}

/** Get restock guidance for a trailer vs its default template. */
export async function getTrailerRestockGuidance(
  trailerId: number,
): Promise<TrailerRestockGuidance> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<TrailerRestockGuidance>>(
    `/trucks/trailers/${trailerId}/restock-guidance`,
  );
  return data.data!;
    },
    async () => ({}) as unknown as TrailerRestockGuidance,
  );
}
