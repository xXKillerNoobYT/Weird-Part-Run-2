/**
 * Mileage reimbursement operations.
 */

import apiClient from '../client';
import type {
  ApiResponse,
  ReimbursementCreate,
  MileageReimbursement,
  ReimbursementApproval,
} from '../../lib/types';
import { adaptedRequest } from '../adapter';


/** List reimbursements (optionally by user or status). */
export async function listReimbursements(params?: {
  user_id?: number;
  status?: string;
}): Promise<MileageReimbursement[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<MileageReimbursement[]>>(
    '/trucks/reimbursements',
    { params },
  );
  return data.data ?? [];
    },
    async () => [] as unknown as MileageReimbursement[],
  );
}

/** Get pending reimbursements count. */
export async function getPendingReimbursements(): Promise<
  MileageReimbursement[]
> {
  const { data } = await apiClient.get<ApiResponse<MileageReimbursement[]>>(
    '/trucks/reimbursements/pending',
  );
  return data.data ?? [];
}

/** Create a reimbursement request. */
export async function createReimbursement(
  reimbursement: ReimbursementCreate,
): Promise<MileageReimbursement> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.post<ApiResponse<MileageReimbursement>>(
    '/trucks/reimbursements',
    reimbursement,
  );
  return data.data!;
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}

/** Approve or reject a reimbursement. */
export async function approveReimbursement(
  reimbursementId: number,
  approval: ReimbursementApproval,
): Promise<MileageReimbursement> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.put<ApiResponse<MileageReimbursement>>(
    `/trucks/reimbursements/${reimbursementId}/approve`,
    approval,
  );
  return data.data!;
    },
    async () => { throw new Error('Fleet Management requires the shop server.'); },
  );
}
