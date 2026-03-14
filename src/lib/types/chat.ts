/**
 * Chat & Messaging types — channels, messages, mentions, Q&A threads, RFIs,
 * alerts (job lead elevations, cert alerts, vehicle expiry alerts),
 * email sending, supplier portal.
 */

// ══════════════════════════════════════════════════════════════════
// JOB LEAD ELEVATIONS
// ══════════════════════════════════════════════════════════════════

export interface JobLeadElevationResponse {
  id: number;
  user_id: number;
  user_name?: string;
  job_id: number;
  job_name?: string;
  permission_key: string;
  granted_by: number;
  granted_by_name?: string;
  granted_at: string | null;
}

export interface JobLeadElevationCreate {
  job_id: number;
  permission_key: string;
}


// ══════════════════════════════════════════════════════════════════
// CERT ALERTS
// ══════════════════════════════════════════════════════════════════

export interface CertAlertItem {
  user_id: number;
  user_name: string;
  cert_name: string;
  expiry_date: string;
  days_until_expiry: number;
}


// ══════════════════════════════════════════════════════════════════
// VEHICLE EXPIRY ALERTS
// ══════════════════════════════════════════════════════════════════

export interface VehicleExpiryAlert {
  vehicle_id: number;
  vehicle_name: string;
  vehicle_number: string;
  alert_type: 'insurance' | 'registration';
  expiry_date: string;
  days_until_expiry: number;
}


// ══════════════════════════════════════════════════════════════════
// CHAT & MESSAGING
// ══════════════════════════════════════════════════════════════════

export type ChannelType = 'job' | 'dm' | 'general';
export type MessageType = 'text' | 'photo' | 'voice' | 'file' | 'system' | 'qa_question' | 'qa_answer' | 'qa_escalation';
export type QALevel = 'worker' | 'lead' | 'foreman' | 'supervisor' | 'office';
export type QAStatus = 'open' | 'escalated' | 'answered' | 'closed' | 'sent_to_gc';
export type QAPriority = 'normal' | 'urgent';
export type RFIStatus = 'draft' | 'sent_text' | 'sent_email' | 'sent_app' | 'responded' | 'closed';

// ── Channels ──────────────────────────────────────────────────────

export interface ChatChannelResponse {
  id: number;
  channel_type: ChannelType;
  job_id: number | null;
  name: string | null;
  created_by: number | null;
  created_at: string | null;
  updated_at: string | null;
  member_count: number;
  unread_count: number;
  last_message: ChatMessagePreview | null;
  job_name: string | null;
  job_number: string | null;
  members: ChatChannelMember[] | null;
}

export interface ChatChannelMember {
  id: number;
  channel_id: number;
  user_id: number;
  role: string;
  muted_until: string | null;
  joined_at: string | null;
  display_name: string | null;
  username: string | null;
}

export interface ChatChannelDetailResponse {
  channel: ChatChannelResponse;
  messages: ChatMessageResponse[];
  members: ChatChannelMember[];
  pinned_messages: ChatMessageResponse[];
  has_more: boolean;
}

export interface ChatInboxResponse {
  channels: ChatChannelResponse[];
  total_unread: number;
  unread_mentions: number;
}

// ── Messages ──────────────────────────────────────────────────────

export interface ChatMessageResponse {
  id: number;
  channel_id: number;
  sender_id: number;
  message_type: MessageType;
  content: string | null;
  media_path: string | null;
  media_mime_type: string | null;
  media_size_bytes: number | null;
  reply_to_id: number | null;
  pinned_at: string | null;
  pinned_by: number | null;
  edited_at: string | null;
  deleted_at: string | null;
  created_at: string | null;
  qa_thread_id: number | null;
  qa_level: string | null;
  // Joined
  sender_name: string | null;
  sender_username: string | null;
  reply_preview: string | null;
  reply_sender_name: string | null;
}

export interface ChatMessagePreview {
  id: number;
  content: string | null;
  message_type: MessageType;
  sender_name: string | null;
  created_at: string | null;
}

export interface SendMessageRequest {
  content?: string | null;
  message_type?: MessageType;
  media_path?: string | null;
  media_mime_type?: string | null;
  media_size_bytes?: number | null;
  reply_to_id?: number | null;
  mention_ids?: number[];
}

export interface EditMessageRequest {
  content: string;
}

export interface MarkReadRequest {
  last_read_message_id: number;
}

// ── Mentions ──────────────────────────────────────────────────────

export interface ChatMentionResponse {
  id: number;
  message_id: number;
  mentioned_user_id: number;
  acknowledged_at: string | null;
  channel_id: number | null;
  channel_name: string | null;
  job_id: number | null;
  sender_name: string | null;
  content: string | null;
  created_at: string | null;
}

export interface ChatBadgeResponse {
  total_unread: number;
  unread_mentions: number;
}

// ── Q&A Threads ───────────────────────────────────────────────────

export interface QAThreadResponse {
  id: number;
  channel_id: number;
  job_id: number | null;
  asked_by: number;
  subject: string;
  current_level: QALevel;
  assigned_to: number | null;
  status: QAStatus;
  priority: QAPriority;
  answered_by: number | null;
  answered_at: string | null;
  closed_at: string | null;
  created_at: string | null;
  updated_at: string | null;
  // Joined
  asker_name: string | null;
  assigned_name: string | null;
  answerer_name: string | null;
  job_name: string | null;
  job_number: string | null;
  message_count: number;
}

export interface QAThreadDetailResponse {
  thread: QAThreadResponse;
  messages: ChatMessageResponse[];
  timeline: EscalationStep[];
  rfi?: RFIResponse | null;
}

export interface EscalationStep {
  level: QALevel;
  action: 'asked' | 'escalated' | 'answered' | 'sent_to_gc' | 'closed';
  user_name: string | null;
  user_id: number | null;
  timestamp: string | null;
  comment: string | null;
}

export interface AskQuestionRequest {
  job_id: number;
  subject: string;
  body: string;
  priority?: QAPriority;
  media_path?: string | null;
}

export interface EscalateRequest {
  comment?: string | null;
}

export interface AnswerRequest {
  answer: string;
}

// ── RFIs ──────────────────────────────────────────────────────────

export interface RFIResponse {
  id: number;
  qa_thread_id: number;
  job_id: number;
  gc_contact_id: number | null;
  subject: string;
  body: string;
  status: RFIStatus;
  sent_via: string | null;
  sent_at: string | null;
  response_text: string | null;
  responded_at: string | null;
  created_by: number;
  created_at: string | null;
  updated_at: string | null;
  // Joined
  gc_name: string | null;
  gc_phone: string | null;
  gc_email: string | null;
  job_name: string | null;
  job_number: string | null;
  thread_subject: string | null;
}

export interface SendToGCRequest {
  gc_contact_id: number;
  via: 'sms' | 'email';
}

export interface UpdateRFIRequest {
  status?: RFIStatus;
  response_text?: string | null;
  sent_via?: string | null;
}


// ═══════════════════════════════════════════════════════════════════
// Email Sending (Office Gap Closure)
// ═══════════════════════════════════════════════════════════════════

/** Current email configuration status (safe — no password exposed) */
export interface EmailConfigStatus {
  enabled: boolean;
  configured: boolean;
  smtp_host: string;
  from_email: string;
  from_name: string;
}

/** Request to send a PO via email */
export interface SendPOEmailRequest {
  to_email: string;
  to_name?: string | null;
  subject?: string | null;
  body_text?: string | null;
  cc?: string[] | null;
  attach_pdf?: boolean;
}

/** Request to send a PO group bundle via email */
export interface SendGroupEmailRequest {
  to_email: string;
  to_name?: string | null;
  subject?: string | null;
  body_text?: string | null;
  cc?: string[] | null;
}

/** Response after successfully sending an email */
export interface EmailSendResult {
  message: string;
  to_email: string;
  subject: string;
  pdf_attached: boolean;
}


// ═══════════════════════════════════════════════════════════════════
// Supplier Portal (Office Gap Closure)
// ═══════════════════════════════════════════════════════════════════

/** Create a supplier portal access token */
export interface SupplierPortalTokenCreate {
  supplier_id: number;
  expires_in_days?: number;
  note?: string | null;
}

/** Supplier portal token in API responses */
export interface SupplierPortalToken {
  id: number;
  supplier_id: number;
  supplier_name?: string | null;
  token: string;
  is_active: boolean;
  expires_at: string | null;
  last_used_at: string | null;
  note: string | null;
  created_by: number | null;
  created_at: string | null;
}

/** Public portal info returned when validating a token */
export interface SupplierPortalInfo {
  supplier_id: number;
  supplier_name: string;
  company?: string | null;
  token_expires_at: string | null;
}

/** A PO visible in the supplier portal */
export interface SupplierPortalPO {
  po_id: number;
  po_number: string;
  status: string;
  total_cost: number;
  line_count: number;
  expected_delivery: string | null;
  created_at: string | null;
  acknowledged: boolean;
  acknowledged_at: string | null;
}

/** Full PO detail for supplier portal view */
export interface SupplierPortalPODetail {
  po_id: number;
  po_number: string;
  status: string;
  total_cost: number;
  expected_delivery: string | null;
  created_at: string | null;
  notes: string | null;
  lines: {
    part_number: string | null;
    part_description: string | null;
    qty_ordered: number;
    unit_cost: number;
    line_total: number;
  }[];
  acknowledgment: {
    acknowledged_at: string;
    estimated_delivery: string | null;
    supplier_notes: string | null;
  } | null;
}

/** Acknowledge a PO in the supplier portal */
export interface SupplierPortalAcknowledge {
  po_id: number;
  estimated_delivery?: string | null;
  supplier_notes?: string | null;
}
