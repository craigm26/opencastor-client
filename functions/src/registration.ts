/**
 * Robot registration enforcement Cloud Functions.
 *
 * Limits each Firebase user account to MAX_ROBOTS registered robots.
 *
 * Two layers of enforcement:
 *   1. registerRobot — callable checked by the bridge before writing to Firestore
 *   2. enforceRobotLimit — Firestore onCreate trigger as a safety net
 */

import * as admin from "firebase-admin";
import { https, firestore as firestoreTrigger } from "firebase-functions/v2";
import { CallableRequest } from "firebase-functions/v2/https";

const db = () => admin.firestore();

/** Maximum robots allowed per user account. Change here when pricing launches. */
const MAX_ROBOTS = 2;

const CORS_ORIGINS = [
  "https://app.opencastor.com",
  "https://opencastor-client.pages.dev",
  "http://localhost",
];

/**
 * registerRobot — callable that the bridge (or Flutter) invokes before
 * creating a robot document. Checks the caller's robot count and either
 * approves the registration or throws resource-exhausted.
 *
 * Request body: { rrn: string }
 * Response:     { approved: true, rrn: string, remaining: number }
 */
export const registerRobot = https.onCall(
  { cors: CORS_ORIGINS, invoker: "public" },
  async (request: CallableRequest<unknown>) => {
    if (!request.auth) {
      throw new https.HttpsError("unauthenticated", "Auth required");
    }

    const uid = request.auth.uid;
    const data = request.data as { rrn?: string };

    if (!data?.rrn) {
      throw new https.HttpsError("invalid-argument", "rrn is required");
    }

    // Count existing robots owned by this user (all, not just online)
    const existingSnap = await db()
      .collection("robots")
      .where("firebase_uid", "==", uid)
      .count()
      .get();

    const existingCount = existingSnap.data().count;

    if (existingCount >= MAX_ROBOTS) {
      throw new https.HttpsError(
        "resource-exhausted",
        `Fleet limit reached: free accounts support up to ${MAX_ROBOTS} robots. Contact support to upgrade.`
      );
    }

    return {
      approved: true,
      rrn: data.rrn,
      remaining: MAX_ROBOTS - existingCount - 1,
    };
  }
);

/**
 * enforceRobotLimit — Firestore onCreate trigger.
 *
 * Safety net: fires whenever a new robot doc is created (e.g. directly by
 * bridge.py via Admin SDK, which bypasses Security Rules). If the owner now
 * exceeds MAX_ROBOTS, the newest doc is deleted. Existing robots are never
 * touched — only the newly created one is removed.
 */
export const enforceRobotLimit = firestoreTrigger.onDocumentCreated(
  "robots/{rrn}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const uid: string | undefined = snap.data()?.firebase_uid;
    if (!uid) return;

    // Fetch all robots for this user (including the one just created)
    const allRobotsSnap = await db()
      .collection("robots")
      .where("firebase_uid", "==", uid)
      .get();

    if (allRobotsSnap.size <= MAX_ROBOTS) {
      // Within limit — nothing to do
      return;
    }

    // Over limit: delete the newly created document only
    await snap.ref.delete();
    console.warn(
      `enforceRobotLimit: uid ${uid} exceeded MAX_ROBOTS (${MAX_ROBOTS}), ` +
        `deleted newly registered robot ${snap.id}. ` +
        `Existing count was ${allRobotsSnap.size}.`
    );
  }
);
