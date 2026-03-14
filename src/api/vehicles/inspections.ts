/**
 * Vehicle inspection templates and records.
 */

import apiClient from '../client';
import type {
  ApiResponse,
  InspectionTemplateCreate,
  InspectionTemplateUpdate,
  InspectionTemplate,
  InspectionRecordCreate,
  InspectionRecord,
  InspectionItemSubmit,
} from '../../lib/types';
import { adaptedRequest } from '../adapter';


/** List all inspection templates. */
export async function listInspectionTemplates(
  params?: { vehicle_type?: string; inspection_type?: string },
): Promise<InspectionTemplate[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<InspectionTemplate[]>>(
    '/trucks/inspections/templates',
    { params },
  );
  return data.data!;
    },
    async () => [] as unknown as InspectionTemplate[],
  );
}

/** Create an inspection template. */
export async function createInspectionTemplate(
  body: InspectionTemplateCreate,
): Promise<InspectionTemplate> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<InspectionTemplate>>(
    '/trucks/inspections/templates',
    body,
  );
  return data.data!;
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}

/** Get an inspection template with items. */
export async function getInspectionTemplate(templateId: number): Promise<InspectionTemplate> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<InspectionTemplate>>(
    `/trucks/inspections/templates/${templateId}`,
  );
  return data.data!;
    },
    async () => ({}) as unknown as InspectionTemplate,
  );
}

/** Update an inspection template. */
export async function updateInspectionTemplate(
  templateId: number,
  body: InspectionTemplateUpdate,
): Promise<InspectionTemplate> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<InspectionTemplate>>(
    `/trucks/inspections/templates/${templateId}`,
    body,
  );
  return data.data!;
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}

/** Start a new inspection for a vehicle. */
export async function startInspection(
  vehicleId: number,
  body: InspectionRecordCreate,
): Promise<InspectionRecord> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<InspectionRecord>>(
    `/trucks/inspections/${vehicleId}/start`,
    body,
  );
  return data.data!;
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}

/** Submit pass/fail for a single inspection item. */
export async function submitInspectionItem(
  recordId: number,
  itemId: number,
  body: InspectionItemSubmit,
): Promise<InspectionRecord> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<InspectionRecord>>(
    `/trucks/inspections/records/${recordId}/items/${itemId}`,
    body,
  );
  return data.data!;
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}

/** Complete an inspection -- calculates overall result. */
export async function completeInspection(recordId: number): Promise<InspectionRecord> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<InspectionRecord>>(
    `/trucks/inspections/records/${recordId}/complete`,
  );
  return data.data!;
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}

/** Inspection history for a vehicle. */
export async function getVehicleInspections(
  vehicleId: number,
  params?: { limit?: number; offset?: number },
): Promise<InspectionRecord[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<InspectionRecord[]>>(
    `/trucks/inspections/${vehicleId}/history`,
    { params },
  );
  return data.data!;
    },
    async () => [] as unknown as InspectionRecord[],
  );
}

/** Fleet-wide incomplete inspections. */
export async function getPendingInspections(): Promise<InspectionRecord[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<InspectionRecord[]>>(
    '/trucks/fleet/inspections/pending',
  );
  return data.data!;
    },
    async () => [] as unknown as InspectionRecord[],
  );
}

/** Failed / needs-attention inspections for manager review. */
export async function getFailedInspections(): Promise<InspectionRecord[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<InspectionRecord[]>>(
    '/trucks/fleet/inspections/failed',
  );
  return data.data!;
    },
    async () => [] as unknown as InspectionRecord[],
  );
}
