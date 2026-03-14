/**
 * Order Attachments API functions.
 */

import apiClient from '../client';
import type { ApiResponse } from '../../lib/types';
import { adaptedRequest } from '../adapter';


export interface OrderAttachment {
  id: number;
  entity_type: 'jpo' | 'po' | 'return';
  entity_id: number;
  file_path: string;
  file_name: string;
  file_type: string | null;
  file_size: number | null;
  description: string | null;
  uploaded_by: number | null;
  created_at: string;
}

/** List attachments for a JPO, PO, or return */
export async function listOrderAttachments(
  entityType: 'jpo' | 'po' | 'return',
  entityId: number,
): Promise<OrderAttachment[]> {
  return adaptedRequest(
    async () => {
      const { data } = await apiClient.get<ApiResponse<OrderAttachment[]>>(
    `/orders/attachments/${entityType}/${entityId}`,
  );
  return data.data ?? [];
    },
    async () => [] as unknown as OrderAttachment[],
  );
}

/** Upload a file attachment to a JPO, PO, or return */
export async function uploadOrderAttachment(
  entityType: 'jpo' | 'po' | 'return',
  entityId: number,
  file: File,
  description?: string,
): Promise<{ id: number; file_path: string }> {
  const formData = new FormData();
  formData.append('file', file);
  const { data } = await apiClient.post<ApiResponse<{ id: number; file_path: string }>>(
    `/orders/attachments/${entityType}/${entityId}`,
    formData,
    {
      headers: { 'Content-Type': 'multipart/form-data' },
      params: description ? { description } : undefined,
    },
  );
  return data.data!;
}

/** Delete an order attachment */
export async function deleteOrderAttachment(
  attachmentId: number,
): Promise<{ id: number }> {
  const { data } = await apiClient.delete<ApiResponse<{ id: number }>>(
    `/orders/attachments/${attachmentId}`,
  );
  return data.data!;
}
