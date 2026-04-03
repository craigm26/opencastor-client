/**
 * FCM push notification triggers for robot status changes.
 *
 * onRobotOffline — Firestore trigger on robots/{rrn}:
 *   Fires when a robot transitions from online → offline and sends an FCM
 *   push notification to the robot owner's registered device(s).
 */

import * as admin from "firebase-admin";
import { firestore as firestoreTrigger } from "firebase-functions/v2";
import { RobotDoc } from "./types";

const db = () => admin.firestore();
const messaging = () => admin.messaging();

/**
 * Notify the robot owner when their robot goes offline.
 *
 * Guard: only fires on the online → offline transition, not on every write,
 * so rapid Firestore updates (e.g. telemetry) don't spam the owner.
 */
export const onRobotOffline = firestoreTrigger.onDocumentUpdated(
  "robots/{rrn}",
  async (event) => {
    const before = event.data?.before.data() as RobotDoc | undefined;
    const after = event.data?.after.data() as RobotDoc | undefined;

    if (!before || !after) return;

    // Only fire on the online → offline transition
    if (before.status?.online !== true || after.status?.online !== false) return;

    const ownerUid: string = after.firebase_uid;
    const tokenDoc = await db().collection("_fcm_tokens").doc(ownerUid).get();
    if (!tokenDoc.exists) return;

    const token: string = tokenDoc.data()!.token;
    await messaging().send({
      token,
      notification: {
        title: `${after.name} went offline`,
        body: `Your robot ${after.name} lost connection`,
      },
      data: {
        type: "robot_offline",
        rrn: event.params.rrn,
        name: after.name ?? "",
        last_seen: after.status?.last_seen ?? "",
      },
    });
  }
);
