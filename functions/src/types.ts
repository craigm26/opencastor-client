/**
 * Shared types for OpenCastor Cloud Functions.
 * Mirrors castor/cloud/firestore_models.py.
 */

export type CommandScope =
  | "discover"
  | "status"
  | "chat"
  | "control"
  | "safety"
  | "transparency";

export type CommandStatus =
  | "pending"
  | "processing"
  | "complete"
  | "failed"
  | "denied"
  | "expired"
  | "pending_consent";

export type ConsentStatus =
  | "pending"
  | "approved"
  | "denied"
  | "expired"
  | "revoked";

export interface CommandDoc {
  instruction: string;
  scope: CommandScope;
  issued_by_uid: string;
  issued_by_owner: string;
  issued_at: string;
  message_type: "command" | "consent_request" | "consent_grant" | "estop";
  status: CommandStatus;
  granted_scopes?: string[];
  consent_id?: string;
  result?: Record<string, unknown>;
  error?: string;
  ack_at?: string;
  completed_at?: string;
  source_rrn?: string;
  reason?: string;
}

export interface ConsentRequestDoc {
  from_rrn: string;
  from_owner: string;
  from_ruri: string;
  requested_scopes: string[];
  reason: string;
  duration_hours: number;
  status: ConsentStatus;
  created_at: string;
  resolved_at?: string;
  resolved_by_uid?: string;
  granted_scopes?: string[];
  consent_id?: string;
  expires_at?: string;
}

export interface RobotDoc {
  rrn: string;
  name: string;
  owner: string;
  firebase_uid: string;
  ruri: string;
  capabilities: string[];
  version: string;
  bridge_version: string;
  registered_at: string;
  status: {
    online: boolean;
    last_seen: string;
    error?: string;
  };
  telemetry?: Record<string, unknown>;
}

/** Payload for the sendCommand callable function. */
export interface SendCommandPayload {
  rrn: string;
  instruction: string;
  scope: CommandScope;
  reason?: string;
}

/** Payload for the resolveConsent callable function. */
export interface ResolveConsentPayload {
  rrn: string;
  consent_request_id: string;
  decision: "approve" | "deny";
  granted_scopes?: string[];
  duration_hours?: number;
}

/** Payload for the requestConsent callable function (robot-to-robot). */
export interface RequestConsentPayload {
  target_rrn: string;
  source_rrn: string;
  source_owner: string;
  source_ruri: string;
  requested_scopes: string[];
  reason: string;
  duration_hours?: number;
}
