/**
 * Mission Thread Cloud Functions — R2R2H multi-robot, multi-human group chat.
 *
 * createMission(title, robot_rrns, invite_emails?)  → missionId
 * sendMissionMessage(missionId, content)            → msgId, fanout to robot commands
 * listMissions()                                    → missions where caller is participant
 * inviteToMission(missionId, email_or_uid, role)    → adds human participant + invite doc
 * joinMission(missionId)                            → accept pending invite, join mission
 */

import * as admin from "firebase-admin";
import { https } from "firebase-functions/v2";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import * as uuid from "uuid";

const db = () => admin.firestore();
const auth = () => admin.auth();

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type HumanRole = "owner" | "operator" | "observer";

interface MissionParticipant {
  type: "human" | "robot";
  uid?: string;        // human
  rrn?: string;        // robot
  name: string;
  role?: HumanRole;    // human only; robots don't have roles
  joined?: boolean;    // false until joinMission() is called for invitees
}

interface Mission {
  id: string;
  title: string;
  created_by: string;      // firebase uid of owner
  created_at: string;
  participants: MissionParticipant[];
  participant_uids: string[];  // flat uid list for efficient Firestore array-contains queries
  status: "active" | "paused" | "completed";
  last_message_at: string;
}

interface MissionMessage {
  id: string;
  from_type: "human" | "robot";
  from_uid?: string;
  from_rrn?: string;
  from_name: string;
  from_role?: HumanRole;   // sender's role when from_type == "human"
  content: string;
  mentions: string[];      // mentioned participant names/RRNs
  timestamp: string;
  scope: "chat";
  status: "delivered" | "processing" | "responded";
}

// ---------------------------------------------------------------------------
// Scope enforcement per role  (§2.8.5)
// ---------------------------------------------------------------------------

/** Scopes a human role is allowed to send. Observer cannot send. */
const ROLE_ALLOWED_SCOPES: Record<HumanRole, string[]> = {
  owner: ["chat", "control", "status", "system"],
  operator: ["chat", "control", "status"],
  observer: [],  // read-only
};

function roleCanSend(role: HumanRole): boolean {
  return ROLE_ALLOWED_SCOPES[role].length > 0;
}

// ---------------------------------------------------------------------------
// @Mention extraction
// ---------------------------------------------------------------------------

/**
 * Extract @mentioned names/RRNs from content.
 * Matches @Bob, @RRN-000000000001, @Alice etc. against all participant names and RRNs.
 */
function extractMentions(content: string, participants: MissionParticipant[]): string[] {
  const mentioned: string[] = [];
  // Build a set of mentionable tokens (robot RRNs and all participant names)
  const tokens: string[] = [];
  for (const p of participants) {
    tokens.push(p.name);
    if (p.rrn) tokens.push(p.rrn);
  }
  for (const token of tokens) {
    if (content.includes(`@${token}`)) {
      mentioned.push(token);
    }
  }
  return [...new Set(mentioned)];  // deduplicate
}

// ---------------------------------------------------------------------------
// createMission
// ---------------------------------------------------------------------------

export const createMission = https.onCall(
  {
    cors: ["https://app.opencastor.com", "https://opencastor-client.pages.dev", "http://localhost"],
    invoker: "public",
  },
  async (request) => {
    const authCtx = request.auth;
    if (!authCtx) {
      throw new https.HttpsError("unauthenticated", "Must be authenticated");
    }

    const data = request.data as {
      title?: string;
      robot_rrns?: string[];
      invite_emails?: string[];  // optional: invite other humans at creation
    };

    if (!data.title || !data.robot_rrns || data.robot_rrns.length === 0) {
      throw new https.HttpsError(
        "invalid-argument",
        "title and robot_rrns (non-empty array) are required"
      );
    }

    // Verify all robots exist and belong to the caller
    const robotRefs = await Promise.all(
      data.robot_rrns.map((rrn) => db().collection("robots").doc(rrn).get())
    );

    const participants: MissionParticipant[] = [];
    const participantUids: string[] = [authCtx.uid];

    // Add human creator as owner
    participants.push({
      type: "human",
      uid: authCtx.uid,
      name: authCtx.token.name || authCtx.token.email || "Owner",
      role: "owner",
      joined: true,
    });

    // Add robot participants (validate ownership)
    for (let i = 0; i < robotRefs.length; i++) {
      const robotDoc = robotRefs[i];
      if (!robotDoc.exists) {
        throw new https.HttpsError("not-found", `Robot ${data.robot_rrns[i]} not found`);
      }
      const robot = robotDoc.data()!;
      if (robot.firebase_uid !== authCtx.uid) {
        throw new https.HttpsError(
          "permission-denied",
          `Robot ${data.robot_rrns[i]} does not belong to your account`
        );
      }
      participants.push({
        type: "robot",
        rrn: data.robot_rrns[i],
        name: robot.name || data.robot_rrns[i],
      });
    }

    const missionId = `mission-${uuid.v4().replace(/-/g, "").slice(0, 12)}`;
    const now = new Date().toISOString();

    const mission: Mission = {
      id: missionId,
      title: data.title,
      created_by: authCtx.uid,
      created_at: now,
      participants,
      participant_uids: participantUids,
      status: "active",
      last_message_at: now,
    };

    await db().collection("missions").doc(missionId).set(mission);

    // Process initial email invites if provided
    const inviteResults: Array<{ email: string; status: string }> = [];
    if (data.invite_emails && data.invite_emails.length > 0) {
      for (const email of data.invite_emails) {
        try {
          const inviteeRecord = await auth().getUserByEmail(email);
          await _addInviteToMission(missionId, data.title, inviteeRecord.uid,
            inviteeRecord.displayName || email, "operator", authCtx.uid,
            authCtx.token.name || authCtx.token.email || "Owner");
          inviteResults.push({ email, status: "invited" });
        } catch {
          inviteResults.push({ email, status: "not_found" });
        }
      }
    }

    return { missionId, mission, inviteResults };
  }
);

// ---------------------------------------------------------------------------
// inviteToMission
// ---------------------------------------------------------------------------

/**
 * Internal helper — adds invite record and updates mission participants.
 */
async function _addInviteToMission(
  missionId: string,
  missionTitle: string,
  inviteeUid: string,
  inviteeName: string,
  role: HumanRole,
  inviterUid: string,
  inviterName: string,
): Promise<void> {
  const now = new Date().toISOString();
  const missionRef = db().collection("missions").doc(missionId);

  // Add to participants array with joined=false
  await missionRef.update({
    participants: admin.firestore.FieldValue.arrayUnion({
      type: "human",
      uid: inviteeUid,
      name: inviteeName,
      role,
      joined: false,
    }),
    participant_uids: admin.firestore.FieldValue.arrayUnion(inviteeUid),
  });

  // Create invite notification doc at mission_invites/{inviteeUid}/invites/{missionId}
  await db()
    .collection("mission_invites")
    .doc(inviteeUid)
    .collection("invites")
    .doc(missionId)
    .set({
      mission_id: missionId,
      mission_title: missionTitle,
      invited_by_uid: inviterUid,
      invited_by_name: inviterName,
      role,
      invited_at: now,
      status: "pending",  // pending | accepted | declined
    });
}

export const inviteToMission = https.onCall(
  {
    cors: ["https://app.opencastor.com", "https://opencastor-client.pages.dev", "http://localhost"],
    invoker: "public",
  },
  async (request) => {
    const authCtx = request.auth;
    if (!authCtx) throw new https.HttpsError("unauthenticated", "Must be authenticated");

    const data = request.data as {
      missionId?: string;
      email_or_uid?: string;
      role?: HumanRole;
    };

    if (!data.missionId || !data.email_or_uid) {
      throw new https.HttpsError("invalid-argument", "missionId and email_or_uid are required");
    }

    const role: HumanRole = data.role ?? "operator";
    if (!["owner", "operator", "observer"].includes(role)) {
      throw new https.HttpsError("invalid-argument", `Invalid role: ${role}`);
    }

    // Load mission, verify caller has owner or operator role
    const missionRef = db().collection("missions").doc(data.missionId);
    const missionDoc = await missionRef.get();
    if (!missionDoc.exists) {
      throw new https.HttpsError("not-found", `Mission ${data.missionId} not found`);
    }
    const mission = missionDoc.data() as Mission;

    const callerParticipant = mission.participants.find(
      (p) => p.type === "human" && p.uid === authCtx.uid
    );
    if (!callerParticipant) {
      throw new https.HttpsError("permission-denied", "You are not a participant in this mission");
    }
    const callerRole = callerParticipant.role ?? "observer";

    // Observers cannot invite; operators can invite observers only; owners can do anything
    if (callerRole === "observer") {
      throw new https.HttpsError("permission-denied", "Observers cannot invite participants");
    }
    if (callerRole === "operator" && role === "owner") {
      throw new https.HttpsError("permission-denied", "Operators cannot grant owner role");
    }

    // Resolve invitee — email or uid
    let inviteeUid: string;
    let inviteeName: string;

    const input = data.email_or_uid;
    if (input.includes("@")) {
      // Email lookup
      try {
        const userRecord = await auth().getUserByEmail(input);
        inviteeUid = userRecord.uid;
        inviteeName = userRecord.displayName || input;
      } catch {
        throw new https.HttpsError("not-found", `No user found with email: ${input}`);
      }
    } else {
      // Assume uid directly
      try {
        const userRecord = await auth().getUser(input);
        inviteeUid = userRecord.uid;
        inviteeName = userRecord.displayName || input;
      } catch {
        throw new https.HttpsError("not-found", `No user found with uid: ${input}`);
      }
    }

    // Check not already a participant
    const alreadyIn = mission.participants.some(
      (p) => p.type === "human" && p.uid === inviteeUid
    );
    if (alreadyIn) {
      throw new https.HttpsError("already-exists", `${inviteeName} is already in this mission`);
    }

    const callerName = authCtx.token.name || authCtx.token.email || "Someone";
    await _addInviteToMission(
      data.missionId, mission.title, inviteeUid, inviteeName,
      role, authCtx.uid, callerName
    );

    return { invited: true, inviteeName, role };
  }
);

// ---------------------------------------------------------------------------
// joinMission
// ---------------------------------------------------------------------------

export const joinMission = https.onCall(
  {
    cors: ["https://app.opencastor.com", "https://opencastor-client.pages.dev", "http://localhost"],
    invoker: "public",
  },
  async (request) => {
    const authCtx = request.auth;
    if (!authCtx) throw new https.HttpsError("unauthenticated", "Must be authenticated");

    const data = request.data as { missionId?: string; accept?: boolean };
    if (!data.missionId) {
      throw new https.HttpsError("invalid-argument", "missionId is required");
    }

    const accept = data.accept !== false; // default true

    // Verify invite exists
    const inviteRef = db()
      .collection("mission_invites")
      .doc(authCtx.uid)
      .collection("invites")
      .doc(data.missionId);
    const inviteDoc = await inviteRef.get();
    if (!inviteDoc.exists) {
      throw new https.HttpsError("not-found", "No pending invite for this mission");
    }
    const invite = inviteDoc.data()!;
    if (invite.status !== "pending") {
      throw new https.HttpsError("failed-precondition", `Invite already ${invite.status}`);
    }

    if (!accept) {
      // Decline — mark invite, remove from participants
      await inviteRef.update({ status: "declined" });
      await db().collection("missions").doc(data.missionId).update({
        participants: admin.firestore.FieldValue.arrayRemove({
          type: "human",
          uid: authCtx.uid,
          name: invite.inviteeName || authCtx.uid,
          role: invite.role,
          joined: false,
        }),
        participant_uids: admin.firestore.FieldValue.arrayRemove(authCtx.uid),
      });
      return { joined: false, status: "declined" };
    }

    // Accept — mark joined on the participants entry
    // Firestore doesn't support updating a single array element in place,
    // so we read-modify-write the participants array.
    const missionRef = db().collection("missions").doc(data.missionId);
    await db().runTransaction(async (tx) => {
      const mDoc = await tx.get(missionRef);
      if (!mDoc.exists) throw new https.HttpsError("not-found", "Mission not found");
      const mData = mDoc.data() as Mission;

      const updatedParticipants = mData.participants.map((p) => {
        if (p.type === "human" && p.uid === authCtx.uid) {
          return { ...p, joined: true };
        }
        return p;
      });
      tx.update(missionRef, { participants: updatedParticipants });
    });

    await inviteRef.update({ status: "accepted" });
    return { joined: true, status: "accepted", role: invite.role };
  }
);

// ---------------------------------------------------------------------------
// sendMissionMessage
// ---------------------------------------------------------------------------

export const sendMissionMessage = https.onCall(
  {
    cors: ["https://app.opencastor.com", "https://opencastor-client.pages.dev", "http://localhost"],
    invoker: "public",
  },
  async (request) => {
    const authCtx = request.auth;
    if (!authCtx) throw new https.HttpsError("unauthenticated", "Must be authenticated");

    const data = request.data as { missionId?: string; content?: string };
    if (!data.missionId || !data.content) {
      throw new https.HttpsError("invalid-argument", "missionId and content are required");
    }

    const missionRef = db().collection("missions").doc(data.missionId);
    const missionDoc = await missionRef.get();
    if (!missionDoc.exists) {
      throw new https.HttpsError("not-found", `Mission ${data.missionId} not found`);
    }
    const mission = missionDoc.data() as Mission;

    if (mission.status !== "active") {
      throw new https.HttpsError(
        "failed-precondition",
        `Mission is ${mission.status} — cannot send messages`
      );
    }

    // Find sender in participants
    const senderParticipant = mission.participants.find(
      (p) => p.type === "human" && p.uid === authCtx.uid
    );
    if (!senderParticipant) {
      throw new https.HttpsError("permission-denied", "You are not a participant in this mission");
    }

    const senderRole: HumanRole = senderParticipant.role ?? "observer";

    // §2.8.5: Enforce role — observers cannot send
    if (!roleCanSend(senderRole)) {
      throw new https.HttpsError(
        "permission-denied",
        `Your role (${senderRole}) is read-only — observers cannot send messages`
      );
    }

    // Extract @mentions against all participants (robots by RRN, humans by name)
    const mentions = extractMentions(data.content, mission.participants);

    // Robot participants for fanout
    const robotParticipants = mission.participants.filter(
      (p): p is MissionParticipant & { rrn: string } =>
        p.type === "robot" && typeof p.rrn === "string"
    );
    const robotRrns = robotParticipants.map((p) => p.rrn);

    const msgId = `msg-${uuid.v4().replace(/-/g, "").slice(0, 12)}`;
    const now = new Date().toISOString();
    const senderName = senderParticipant.name ||
      authCtx.token.name || authCtx.token.email || "Human";

    const message: MissionMessage = {
      id: msgId,
      from_type: "human",
      from_uid: authCtx.uid,
      from_name: senderName,
      from_role: senderRole,
      content: data.content,
      mentions,
      timestamp: now,
      scope: "chat",
      status: "delivered",
    };

    // Write human message to mission thread (§2.8.6: retained for audit)
    await missionRef.collection("messages").doc(msgId).set(message);
    await missionRef.update({ last_message_at: now });

    // Fanout to each robot command queue concurrently (Promise.all)
    const fanoutPromises = robotParticipants.map((robot) => {
      const cmdId = `mc-${uuid.v4().replace(/-/g, "").slice(0, 12)}`;
      return db()
        .collection("robots")
        .doc(robot.rrn)
        .collection("commands")
        .doc(cmdId)
        .set({
          id: cmdId,
          instruction: data.content,
          scope: "chat",
          mission_id: data.missionId,
          mission_msg_id: msgId,
          participants: robotRrns,
          context: "mission_thread",
          issued_by_uid: authCtx.uid,
          issued_by_owner: authCtx.uid,
          issued_by_role: senderRole,
          issued_at: now,
          message_type: "command",
          status: "pending",
          sender_type: "cloud_function",
          mentions,
        });
    });

    await Promise.all(fanoutPromises);

    return { msgId, robotsFannedOut: robotParticipants.length, mentions, senderRole };
  }
);

// ---------------------------------------------------------------------------
// listMissions
// ---------------------------------------------------------------------------

export const listMissions = https.onCall(
  {
    cors: ["https://app.opencastor.com", "https://opencastor-client.pages.dev", "http://localhost"],
    invoker: "public",
  },
  async (request) => {
    const authCtx = request.auth;
    if (!authCtx) throw new https.HttpsError("unauthenticated", "Must be authenticated");

    // Query by participant_uids array-contains — catches both owned + invited missions
    const snapshot = await db()
      .collection("missions")
      .where("participant_uids", "array-contains", authCtx.uid)
      .orderBy("last_message_at", "desc")
      .limit(50)
      .get();

    const missions = snapshot.docs.map((doc) => doc.data() as Mission);
    return { missions };
  }
);

// ---------------------------------------------------------------------------
// deleteMissionMessage
// ---------------------------------------------------------------------------

export const deleteMissionMessage = onCall(
  {
    region: "us-central1",
    cors: ["https://app.opencastor.com", "https://opencastor-client.pages.dev", "http://localhost"],
    invoker: "public",
  },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Login required");
    const { missionId, msgId } = request.data as { missionId: string; msgId: string };
    if (!missionId || !msgId) throw new HttpsError("invalid-argument", "missionId and msgId required");

    const firestore = admin.firestore();
    const missionRef = firestore.collection("missions").doc(missionId);
    const msgRef = missionRef.collection("messages").doc(msgId);

    const [missionDoc, msgDoc] = await Promise.all([missionRef.get(), msgRef.get()]);
    if (!missionDoc.exists || !msgDoc.exists) throw new HttpsError("not-found", "Not found");

    const mission = missionDoc.data()!;
    const msg = msgDoc.data()!;
    const uid = request.auth.uid;

    const isOwner = mission.created_by === uid;
    const isSender = msg.from_uid === uid;
    if (!isOwner && !isSender) throw new HttpsError("permission-denied", "Cannot delete this message");

    await msgRef.update({ deleted: true, content: "" });
    return { ok: true };
  }
);

// ---------------------------------------------------------------------------
// hideMission
// ---------------------------------------------------------------------------

export const hideMission = onCall(
  {
    region: "us-central1",
    cors: ["https://app.opencastor.com", "https://opencastor-client.pages.dev", "http://localhost"],
    invoker: "public",
  },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Login required");
    const { missionId, hidden } = request.data as { missionId: string; hidden: boolean };
    if (!missionId) throw new HttpsError("invalid-argument", "missionId required");

    const firestore = admin.firestore();
    const ref = firestore.collection("missions").doc(missionId);
    const doc = await ref.get();
    if (!doc.exists) throw new HttpsError("not-found", "Mission not found");

    const data = doc.data()!;
    if (!data.participant_uids?.includes(request.auth.uid)) {
      throw new HttpsError("permission-denied", "Not a participant");
    }

    const uid = request.auth.uid;
    if (hidden) {
      await ref.update({ hidden_by: admin.firestore.FieldValue.arrayUnion(uid) });
    } else {
      await ref.update({ hidden_by: admin.firestore.FieldValue.arrayRemove(uid) });
    }
    return { ok: true };
  }
);
