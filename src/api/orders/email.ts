/**
 * Email Sending API functions for orders.
 */

import apiClient from '../client';
import type { ApiResponse } from '../../lib/types';


/** Check email configuration status (no secrets exposed) */
export async function getEmailConfig(): Promise<{
  enabled: boolean;
  configured: boolean;
  smtp_host: string;
  from_email: string;
  from_name: string;
}> {
  const { data } = await apiClient.get<ApiResponse<{
    enabled: boolean;
    configured: boolean;
    smtp_host: string;
    from_email: string;
    from_name: string;
  }>>('/orders/email/config');
  return data.data!;
}

/** Send a single PO via email (with optional PDF attachment) */
export async function sendPOEmail(
  poId: number,
  body: {
    to_email: string;
    to_name?: string | null;
    subject?: string | null;
    body_text?: string | null;
    cc?: string[] | null;
    attach_pdf?: boolean;
  },
): Promise<{ message: string; to_email: string; subject: string; pdf_attached: boolean }> {
  const { data } = await apiClient.post<ApiResponse<{
    message: string; to_email: string; subject: string; pdf_attached: boolean;
  }>>(`/orders/pos/${poId}/send-email`, body);
  return data.data!;
}

/** Send a PO group bundle via email */
export async function sendGroupEmail(
  groupId: number,
  body: {
    to_email: string;
    to_name?: string | null;
    subject?: string | null;
    body_text?: string | null;
    cc?: string[] | null;
  },
): Promise<{ message: string; to_email: string; subject: string; pdf_attached: boolean }> {
  const { data } = await apiClient.post<ApiResponse<{
    message: string; to_email: string; subject: string; pdf_attached: boolean;
  }>>(`/orders/pos/group/${groupId}/send-email`, body);
  return data.data!;
}
