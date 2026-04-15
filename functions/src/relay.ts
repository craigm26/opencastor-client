/**
 * Command relay Cloud Function.
 *
 * Validates auth + R2RAM scope, then writes to the target robot's Firestore
 * command queue. The robot's castor bridge picks it up and executes it.
 *
 * This function never connects directly to robots — all relay is via Firestore.
 */

import * as admin from "firebase-admin";
import { https } from "firebase-functions/v2";
import { SendCommandPayload, CommandDoc } from "./types";
import { checkRateLimit } from "./ratelimit";
import * as uuid from "uuid";

const db = () => admin.firestore();

// Scope hierarchy for cross-owner enforcement (matches ConsentManager in Python)
const SCOPE_LEVEL: Record<string, number> = {
  discover: 0,
  status: 1,
  chat: 2,
  control: 3,
  safety: 99,
  transparency: 0,
  system: 3,   // same level as control — requires admin role on the robot side
};

/**
 * sendCommand — Flutter app sends a command to a robot.
 *
 * Flow:
 *   1. Verify Firebase Auth
 *   2. Verify caller owns the robot OR has valid cross-owner consent
 *   3. Rate-limit check
 *   4. Write command to /robots/{rrn}/commands/{cmd_id}
 *   5. Return cmd_id for polling
 */
export const sendCommand = https.onCall({ cors: ["https://app.opencastor.com", "https://opencastor-client.pages.dev", "http://localhost"], invoker: "public" }, async (request) => {
  const auth = request.auth;
  if (!auth) throw new https.HttpsError("unauthenticated", "Must be authenticated");

  const data = request.data as SendCommandPayload;
  if (!data.rrn || !data.instruction || !data.scope) {
    throw new https.HttpsError(
      "invalid-argument",
      "rrn, instruction, and scope are required"
    );
  }

  // Validate scope string
  if (!(data.scope in SCOPE_LEVEL)) {
    throw new https.HttpsError("invalid-argument", `Unknown scope: ${data.scope}`);
  }

  const robotRef = db().collection("robots").doc(data.rrn);
  const robotDoc = await robotRef.get();
  if (!robotDoc.exists) {
    throw new https.HttpsError("not-found", `Robot ${data.rrn} not found`);
  }

  const robot = robotDoc.data()!;
  let isOwner: boolean = !!robot.firebase_uid && robot.firebase_uid === auth.uid;

  // Fallback ownership check for robots registered without firebase_uid in their
  // RCAN config (e.g. bridge.py started before firebase_uid was added to the yaml).
  // If the robot doc lacks firebase_uid but the authenticated user owns another
  // robot sharing the same `owner` string (RURI), treat them as the owner.
  if (!isOwner && !robot.firebase_uid && robot.owner) {
    const myRobotsSnap = await db()
      .collection("robots")
      .where("firebase_uid", "==", auth.uid)
      .limit(10)
      .get();
    const myOwnerStrings = new Set(myRobotsSnap.docs.map((d) => d.data().owner as string));
    if (myOwnerStrings.has(robot.owner as string)) {
      isOwner = true;
    }
  }

  // system scope is owner-only — no peer delegation for safety-critical ops
  if (!isOwner && data.scope === "system") {
    throw new https.HttpsError(
      "permission-denied",
      "system scope commands can only be sent by the robot owner — peer delegation is not permitted"
    );
  }

  // Cross-owner scope check
  if (!isOwner) {
    const authorized = await checkCrossOwnerScope(
      auth.uid,
      data.rrn,
      robot.owner,
      data.scope
    );
    if (!authorized) {
      throw new https.HttpsError(
        "permission-denied",
        `You do not have ${data.scope} access to this robot`
      );
    }
  }

  // Rate limiting (skip for safety scope — ESTOP must never be delayed)
  if (data.scope !== "safety") {
    const rl = await checkRateLimit(auth.uid, data.scope);
    if (!rl.allowed) {
      throw new https.HttpsError(
        "resource-exhausted",
        `Rate limit exceeded. Retry after ${Math.ceil((rl.retryAfterMs || 60000) / 1000)}s`
      );
    }
  }

  // ---------------------------------------------------------------------------
// Slash command mapping (mirrors SLASH_COMMAND_MAP in Flutter)
// ---------------------------------------------------------------------------

/**
 * Maps slash command strings to their canonical RCAN instruction text.
 * Used when instruction.startsWith('/') to normalize before queuing.
 * Unknown slash commands are passed through unchanged.
 */
const SLASH_COMMAND_MAP: Record<string, (args: string[]) => string> = {
  "/status": () => "STATUS",
  "/skills": () => "LIST_SKILLS",
  "/optimize": () => "OPTIMIZE",
  "/upgrade": (args) => (args[0] ? `UPGRADE: ${args[0]}` : "UPGRADE"),
  "/reboot": () => "REBOOT",
  "/reload-config": () => "RELOAD_CONFIG",
  "/share": () => "SHARE_CONFIG",
  "/install": (args) => `INSTALL: ${args[0] || ""}`,
};

  // Map slash commands to RCAN instructions
  let resolvedInstruction = data.instruction;
  if (data.instruction.startsWith("/")) {
    const [cmd, ...argParts] = data.instruction.split(" ");
    resolvedInstruction = SLASH_COMMAND_MAP[cmd]
      ? SLASH_COMMAND_MAP[cmd](argParts)
      : data.instruction; // pass through unknown slash commands
  }

  const cmdId = uuid.v4();
  const now = new Date().toISOString();

  const isEstop =
    data.scope === "safety" && data.instruction.toLowerCase().includes("estop");

  const cmd: CommandDoc = {
    instruction: resolvedInstruction,
    scope: data.scope,
    issued_by_uid: auth.uid,
    issued_by_owner: `uid:${auth.uid}`, // resolved to rrn:// if owner robot
    issued_at: now,
    message_type: isEstop ? "estop" : "command",
    status: "pending",
    reason: data.reason,
  };

  // Remove undefined fields
  const clean = Object.fromEntries(
    Object.entries(cmd).filter(([_, v]) => v !== undefined)
  );

  await robotRef.collection("commands").doc(cmdId).set(clean);

  return { cmd_id: cmdId, queued_at: now };
});

/**
 * getCommandStatus — poll for command result.
 */
export const getCommandStatus = https.onCall({ cors: ["https://app.opencastor.com", "https://opencastor-client.pages.dev", "http://localhost"], invoker: "public" }, async (request) => {
  const auth = request.auth;
  if (!auth) throw new https.HttpsError("unauthenticated", "Must be authenticated");

  const { rrn, cmd_id } = request.data as { rrn: string; cmd_id: string };
  if (!rrn || !cmd_id) {
    throw new https.HttpsError("invalid-argument", "rrn and cmd_id required");
  }

  // Verify ownership
  const robotDoc = await db().collection("robots").doc(rrn).get();
  if (!robotDoc.exists) throw new https.HttpsError("not-found", "Robot not found");

  const isOwner = robotDoc.data()!.firebase_uid === auth.uid;
  if (!isOwner) {
    // Cross-owner: may only read status of their own commands
    const cmdDoc = await db()
      .collection("robots")
      .doc(rrn)
      .collection("commands")
      .doc(cmd_id)
      .get();
    if (!cmdDoc.exists) throw new https.HttpsError("not-found", "Command not found");
    if (cmdDoc.data()!.issued_by_uid !== auth.uid) {
      throw new https.HttpsError("permission-denied", "Not your command");
    }
    return cmdDoc.data();
  }

  const cmdDoc = await db()
    .collection("robots")
    .doc(rrn)
    .collection("commands")
    .doc(cmd_id)
    .get();
  if (!cmdDoc.exists) throw new https.HttpsError("not-found", "Command not found");
  return cmdDoc.data();
});

/**
 * registerFcmToken — Flutter app registers its FCM token on login.
 */
export const registerFcmToken = https.onCall({ cors: ["https://app.opencastor.com", "https://opencastor-client.pages.dev", "http://localhost"], invoker: "public" }, async (request) => {
  const auth = request.auth;
  if (!auth) throw new https.HttpsError("unauthenticated", "Must be authenticated");

  const { token } = request.data as { token: string };
  if (!token) throw new https.HttpsError("invalid-argument", "token required");

  await db().collection("_fcm_tokens").doc(auth.uid).set(
    { token, updated_at: new Date().toISOString() },
    { merge: true }
  );

  return { registered: true };
});

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

async function checkCrossOwnerScope(
  requesterUid: string,
  targetRrn: string,
  targetOwner: string,
  requestedScope: string
): Promise<boolean> {
  // Find requester's RRN by looking up their robots
  const myRobots = await db()
    .collection("robots")
    .where("firebase_uid", "==", requesterUid)
    .limit(1)
    .get();

  if (myRobots.empty) return false;
  const myOwner: string = myRobots.docs[0].data().owner;

  // Check consent record on target robot
  const peerId = myOwner.replace("rrn://", "").replace(/\//g, "_");
  const peerRef = db()
    .collection("robots")
    .doc(targetRrn)
    .collection("consent_peers")
    .doc(peerId);

  const peerDoc = await peerRef.get();
  if (!peerDoc.exists) return false;

  const peer = peerDoc.data()!;
  if (peer.status !== "approved") return false;

  // Expiry check
  if (peer.expires_at) {
    if (new Date(peer.expires_at) < new Date()) return false;
  }

  // Scope check (additive hierarchy)
  const reqLevel = SCOPE_LEVEL[requestedScope] ?? 99;
  const grantedScopes: string[] = peer.granted_scopes || [];
  return grantedScopes.some(
    (g: string) => (SCOPE_LEVEL[g] ?? -1) >= reqLevel
  );
}
