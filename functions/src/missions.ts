/**
 * Mission Thread Cloud Functions — R2R2H multi-robot group chat.
 *
 * createMission(title, robot_rrns)   → missionId
 * sendMissionMessage(missionId, content) → msgId, fanout to robot commands
 * listMissions()                     → missions created_by the caller
 */

import * as admin from "firebase-admin";
import { https } from "firebase-functions/v2";
import * as uuid from "uuid";

const db = () => admin.firestore();

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface MissionParticipant {
  type: "human" | "robot";
  uid?: string;   // human
  rrn?: string;   // robot
  name: string;
}

interface Mission {
  id: string;
  title: string;
  created_by: string;  // firebase uid
  created_at: string;
  participants: MissionParticipant[];
  status: "active" | "paused" | "completed";
  last_message_at: string;
}

interface MissionMessage {
  id: string;
  from_type: "human" | "robot";
  from_uid?: string;
  from_rrn?: string;
  from_name: string;
  content: string;
  mentions: string[];   // mentioned robot RRNs
  timestamp: string;
  scope: "chat";
  status: "delivered" | "processing" | "responded";
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Extract @mentioned robot RRNs from message content. */
function extractMentions(content: string, robotRrns: string[]): string[] {
  const mentioned: string[] = [];
  for (const rrn of robotRrns) {
    // Match @RRN-XXXX style or partial name matches embedded in message
    if (content.includes(`@${rrn}`)) {
      mentioned.push(rrn);
    }
  }
  return mentioned;
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
    const auth = request.auth;
    if (!auth) {
      throw new https.HttpsError("unauthenticated", "Must be authenticated");
    }

    const data = request.data as { title?: string; robot_rrns?: string[] };
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

    // Add human creator first
    participants.push({
      type: "human",
      uid: auth.uid,
      name: auth.token.name || auth.token.email || "Human",
    });

    // Add robot participants (validate each exists)
    for (let i = 0; i < robotRefs.length; i++) {
      const robotDoc = robotRefs[i];
      if (!robotDoc.exists) {
        throw new https.HttpsError(
          "not-found",
          `Robot ${data.robot_rrns[i]} not found`
        );
      }
      const robot = robotDoc.data()!;
      // Ownership check — only allow robots owned by the caller
      if (robot.firebase_uid !== auth.uid) {
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
      created_by: auth.uid,
      created_at: now,
      participants,
      status: "active",
      last_message_at: now,
    };

    await db().collection("missions").doc(missionId).set(mission);

    return { missionId, mission };
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
    const auth = request.auth;
    if (!auth) {
      throw new https.HttpsError("unauthenticated", "Must be authenticated");
    }

    const data = request.data as { missionId?: string; content?: string };
    if (!data.missionId || !data.content) {
      throw new https.HttpsError(
        "invalid-argument",
        "missionId and content are required"
      );
    }

    // Load mission
    const missionRef = db().collection("missions").doc(data.missionId);
    const missionDoc = await missionRef.get();
    if (!missionDoc.exists) {
      throw new https.HttpsError("not-found", `Mission ${data.missionId} not found`);
    }

    const mission = missionDoc.data() as Mission;

    // Caller must be a human participant
    const isParticipant = mission.participants.some(
      (p) => p.type === "human" && p.uid === auth.uid
    );
    if (!isParticipant) {
      throw new https.HttpsError(
        "permission-denied",
        "You are not a participant in this mission"
      );
    }

    if (mission.status !== "active") {
      throw new https.HttpsError(
        "failed-precondition",
        `Mission is ${mission.status} — cannot send messages`
      );
    }

    // Find robot participants
    const robotParticipants = mission.participants.filter(
      (p): p is MissionParticipant & { rrn: string } =>
        p.type === "robot" && typeof p.rrn === "string"
    );
    const robotRrns = robotParticipants.map((p) => p.rrn);

    // Extract @mentions from content
    const mentions = extractMentions(data.content, robotRrns);

    const msgId = `msg-${uuid.v4().replace(/-/g, "").slice(0, 12)}`;
    const now = new Date().toISOString();
    const senderName = auth.token.name || auth.token.email || "Human";

    const message: MissionMessage = {
      id: msgId,
      from_type: "human",
      from_uid: auth.uid,
      from_name: senderName,
      content: data.content,
      mentions,
      timestamp: now,
      scope: "chat",
      status: "delivered",
    };

    // Write human message to mission thread
    await missionRef.collection("messages").doc(msgId).set(message);

    // Update last_message_at on the mission doc
    await missionRef.update({ last_message_at: now });

    // Fanout: write command to each robot's commands queue concurrently
    const fanoutPromises = robotParticipants.map((robot) => {
      const cmdId = `mc-${uuid.v4().replace(/-/g, "").slice(0, 12)}`;
      const cmdDoc = {
        id: cmdId,
        instruction: data.content,
        scope: "chat",
        mission_id: data.missionId,
        mission_msg_id: msgId,
        participants: robotRrns,
        context: "mission_thread",
        issued_by_uid: auth.uid,
        issued_by_owner: auth.uid,
        issued_at: now,
        message_type: "command",
        status: "pending",
        sender_type: "cloud_function",
        mentions,
      };
      return db()
        .collection("robots")
        .doc(robot.rrn)
        .collection("commands")
        .doc(cmdId)
        .set(cmdDoc);
    });

    await Promise.all(fanoutPromises);

    return {
      msgId,
      robotsFannedOut: robotParticipants.length,
      mentions,
    };
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
    const auth = request.auth;
    if (!auth) {
      throw new https.HttpsError("unauthenticated", "Must be authenticated");
    }

    const snapshot = await db()
      .collection("missions")
      .where("created_by", "==", auth.uid)
      .orderBy("last_message_at", "desc")
      .limit(50)
      .get();

    const missions = snapshot.docs.map((doc) => doc.data() as Mission);
    return { missions };
  }
);
