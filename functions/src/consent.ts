/**
 * R2RAM consent handshake Cloud Functions.
 *
 * Handles the three-way consent flow:
 *   requestConsent  — robot A asks robot B's owner for authorization
 *   resolveConsent  — robot B's owner approves or denies
 *   revokeConsent   — either owner revokes an existing consent record
 */

import * as admin from "firebase-admin";
import { https, firestore as firestoreTrigger } from "firebase-functions/v2";
import { RequestConsentPayload, ResolveConsentPayload } from "./types";
import * as uuid from "uuid";

const db = () => admin.firestore();
const messaging = () => admin.messaging();

// ---------------------------------------------------------------------------
// requestConsent — called by robot A's bridge (or via Flutter app)
// ---------------------------------------------------------------------------

export const requestConsent = https.onCall({ cors: ["https://app.opencastor.com", "https://opencastor-client.pages.dev", "http://localhost"] }, async (request) => {
  const auth = request.auth;
  if (!auth) throw new https.HttpsError("unauthenticated", "Must be authenticated");

  const data = request.data as RequestConsentPayload;
  if (!data.target_rrn || !data.requested_scopes?.length) {
    throw new https.HttpsError("invalid-argument", "target_rrn and requested_scopes required");
  }

  // Look up target robot to find its owner's Firebase UID
  const robotRef = db().collection("robots").doc(data.target_rrn);
  const robotDoc = await robotRef.get();
  if (!robotDoc.exists) {
    throw new https.HttpsError("not-found", `Robot ${data.target_rrn} not found in registry`);
  }

  const robot = robotDoc.data()!;
  const targetOwnerUid: string = robot.firebase_uid;

  const consentId = uuid.v4();
  const requestId = uuid.v4();
  const now = new Date().toISOString();

  const consentRequestDoc = {
    from_rrn: data.source_rrn,
    from_owner: data.source_owner,
    from_ruri: data.source_ruri,
    requested_scopes: data.requested_scopes,
    reason: data.reason || "",
    duration_hours: data.duration_hours || 24,
    status: "pending",
    created_at: now,
    consent_id: consentId,
  };

  // Write to target robot's consent_requests subcollection
  await robotRef
    .collection("consent_requests")
    .doc(requestId)
    .set(consentRequestDoc);

  // Also write as a command (pending_consent) so the bridge picks it up
  await robotRef.collection("commands").doc(requestId).set({
    ...consentRequestDoc,
    message_type: "consent_request",
    instruction: `Consent request from ${data.source_owner}: ${data.requested_scopes.join(", ")}`,
    scope: "discover",
    issued_by_uid: auth.uid,
    issued_by_owner: data.source_owner,
    issued_at: now,
    status: "pending",
  });

  // Push FCM notification to target owner
  const ownerTokenRef = db().collection("_fcm_tokens").doc(targetOwnerUid);
  const tokenDoc = await ownerTokenRef.get();
  if (tokenDoc.exists) {
    const token: string = tokenDoc.data()!.token;
    await messaging().send({
      token,
      notification: {
        title: "Robot access request",
        body: `${data.source_owner} wants ${data.requested_scopes.join(", ")} access to your robot ${robot.name}`,
      },
      data: {
        type: "consent_request",
        request_id: requestId,
        target_rrn: data.target_rrn,
        from_owner: data.source_owner,
        scopes: data.requested_scopes.join(","),
      },
    });
  }

  return { request_id: requestId, consent_id: consentId };
});

// ---------------------------------------------------------------------------
// resolveConsent — owner approves or denies (callable from Flutter app)
// ---------------------------------------------------------------------------

export const resolveConsent = https.onCall({ cors: ["https://app.opencastor.com", "https://opencastor-client.pages.dev", "http://localhost"] }, async (request) => {
  const auth = request.auth;
  if (!auth) throw new https.HttpsError("unauthenticated", "Must be authenticated");

  const data = request.data as ResolveConsentPayload;
  if (!data.rrn || !data.consent_request_id || !data.decision) {
    throw new https.HttpsError("invalid-argument", "rrn, consent_request_id, decision required");
  }
  if (!["approve", "deny"].includes(data.decision)) {
    throw new https.HttpsError("invalid-argument", "decision must be approve or deny");
  }

  // Verify caller owns this robot
  const robotRef = db().collection("robots").doc(data.rrn);
  const robotDoc = await robotRef.get();
  if (!robotDoc.exists) {
    throw new https.HttpsError("not-found", `Robot ${data.rrn} not found`);
  }
  if (robotDoc.data()!.firebase_uid !== auth.uid) {
    throw new https.HttpsError("permission-denied", "You do not own this robot");
  }

  const reqRef = robotRef.collection("consent_requests").doc(data.consent_request_id);
  const reqDoc = await reqRef.get();
  if (!reqDoc.exists) {
    throw new https.HttpsError("not-found", "Consent request not found");
  }

  const reqData = reqDoc.data()!;
  const now = new Date().toISOString();

  if (data.decision === "approve") {
    const durationHours = data.duration_hours || reqData.duration_hours || 24;
    const expiresAt = new Date(Date.now() + durationHours * 3_600_000).toISOString();
    const grantedScopes = data.granted_scopes || reqData.requested_scopes;
    const consentId = reqData.consent_id || uuid.v4();

    await reqRef.update({
      status: "approved",
      resolved_at: now,
      resolved_by_uid: auth.uid,
      granted_scopes: grantedScopes,
      expires_at: expiresAt,
      consent_id: consentId,
    });

    // Write consent peer record so bridge's ConsentManager can find it
    const peerId = reqData.from_owner.replace("rrn://", "").replace(/\//g, "_");
    await robotRef.collection("consent_peers").doc(peerId).set({
      peer_rrn: reqData.from_rrn,
      peer_owner: reqData.from_owner,
      peer_ruri: reqData.from_ruri,
      granted_scopes: grantedScopes,
      established_at: now,
      expires_at: expiresAt,
      consent_id: consentId,
      direction: "inbound",
      status: "approved",
    });

    // Write CONSENT_GRANT command so bridge publishes it back to requester
    await robotRef.collection("commands").doc(uuid.v4()).set({
      message_type: "consent_grant",
      instruction: "consent_grant",
      scope: "discover",
      issued_by_uid: auth.uid,
      issued_by_owner: robotDoc.data()!.owner,
      issued_at: now,
      status: "pending",
      // Payload for the bridge to forward as a RCAN CONSENT_GRANT message
      target_rrn: reqData.from_rrn,
      granted_scopes: grantedScopes,
      consent_id: consentId,
      expires_at: expiresAt,
    });

    return { status: "approved", consent_id: consentId, expires_at: expiresAt };
  } else {
    // deny
    await reqRef.update({
      status: "denied",
      resolved_at: now,
      resolved_by_uid: auth.uid,
    });

    return { status: "denied" };
  }
});

// ---------------------------------------------------------------------------
// revokeConsent — owner revokes an existing peer consent
// ---------------------------------------------------------------------------

export const revokeConsent = https.onCall({ cors: ["https://app.opencastor.com", "https://opencastor-client.pages.dev", "http://localhost"] }, async (request) => {
  const auth = request.auth;
  if (!auth) throw new https.HttpsError("unauthenticated", "Must be authenticated");

  const { rrn, peer_owner } = request.data as { rrn: string; peer_owner: string };
  if (!rrn || !peer_owner) {
    throw new https.HttpsError("invalid-argument", "rrn and peer_owner required");
  }

  const robotRef = db().collection("robots").doc(rrn);
  const robotDoc = await robotRef.get();
  if (!robotDoc.exists || robotDoc.data()!.firebase_uid !== auth.uid) {
    throw new https.HttpsError("permission-denied", "You do not own this robot");
  }

  const peerId = peer_owner.replace("rrn://", "").replace(/\//g, "_");
  await robotRef.collection("consent_peers").doc(peerId).update({
    status: "revoked",
    revoked_at: new Date().toISOString(),
    revoked_by_uid: auth.uid,
  });

  return { status: "revoked" };
});

// ---------------------------------------------------------------------------
// Firestore trigger: notify requester when consent is resolved
// ---------------------------------------------------------------------------

export const onConsentResolved = firestoreTrigger.onDocumentUpdated(
  "robots/{rrn}/consent_requests/{reqId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();

    if (!before || !after) return;
    if (before.status === after.status) return; // no change
    if (!["approved", "denied"].includes(after.status)) return;

    // Find the requester robot's owner FCM token and notify
    const fromRrn: string = after.from_rrn;
    const fromRobotRef = db().collection("robots").doc(fromRrn);
    const fromRobotDoc = await fromRobotRef.get();
    if (!fromRobotDoc.exists) return;

    const fromOwnerUid: string = fromRobotDoc.data()!.firebase_uid;
    const tokenDoc = await db().collection("_fcm_tokens").doc(fromOwnerUid).get();
    if (!tokenDoc.exists) return;

    const token: string = tokenDoc.data()!.token;
    const targetRrn = event.params.rrn;

    await messaging().send({
      token,
      notification: {
        title: after.status === "approved" ? "Consent approved" : "Consent denied",
        body:
          after.status === "approved"
            ? `Access to ${targetRrn} granted: ${after.granted_scopes?.join(", ")}`
            : `Access to ${targetRrn} was denied`,
      },
      data: {
        type: "consent_resolved",
        status: after.status,
        target_rrn: targetRrn,
        granted_scopes: (after.granted_scopes || []).join(","),
      },
    });
  }
);
