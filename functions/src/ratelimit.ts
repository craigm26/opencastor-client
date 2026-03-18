/**
 * Per-UID rate limiting for OpenCastor Cloud Functions.
 *
 * Uses Firestore to track call counts in a rolling window.
 * Limits:
 *   - chat/status: 60 calls/minute per UID
 *   - control:     10 calls/minute per UID
 *   - safety:      unlimited (ESTOP must never be rate-limited)
 */

import * as admin from "firebase-admin";
import { CommandScope } from "./types";

const LIMITS: Record<CommandScope, number | null> = {
  discover: 60,
  status: 60,
  chat: 60,
  control: 10,
  safety: null,       // never rate-limit ESTOP
  transparency: 60,
  system: 5,          // low limit — upgrade/reboot are infrequent ops
};

const WINDOW_MS = 60_000; // 1 minute rolling window

/**
 * Check rate limit for a UID + scope combination.
 * Returns { allowed: true } or { allowed: false, retryAfterMs: number }.
 */
export async function checkRateLimit(
  uid: string,
  scope: CommandScope
): Promise<{ allowed: boolean; retryAfterMs?: number }> {
  const limit = LIMITS[scope];
  if (limit === null) {
    return { allowed: true }; // safety — always allow
  }

  const db = admin.firestore();
  const now = Date.now();
  const windowStart = now - WINDOW_MS;

  const ref = db
    .collection("_rate_limits")
    .doc(`${uid}:${scope}`);

  return db.runTransaction(async (tx) => {
    const doc = await tx.get(ref);
    const data = doc.exists ? (doc.data() as { calls: number[]; }) : { calls: [] };

    // Drop calls outside the rolling window
    const recent = (data.calls || []).filter((ts: number) => ts > windowStart);

    if (recent.length >= limit) {
      const oldest = Math.min(...recent);
      const retryAfterMs = WINDOW_MS - (now - oldest);
      return { allowed: false, retryAfterMs };
    }

    recent.push(now);
    tx.set(ref, { calls: recent }, { merge: false });
    return { allowed: true };
  });
}
