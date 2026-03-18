/**
 * Phase 4 social layer Cloud Functions.
 *
 * forkConfig      — copy a config to personal namespace, returns new id
 * addComment      — add a comment to a config
 * getComments     — list comments for a config (paginated)
 * deleteComment   — delete own comment
 * getMyStars      — list configs starred by the current user
 */

import * as functions from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { CallableRequest } from "firebase-functions/v2/https";

const db = () => admin.firestore();

function nanoid(size = 10): string {
  const alphabet = "abcdefghijklmnopqrstuvwxyz0123456789";
  let id = "";
  for (let i = 0; i < size; i++) id += alphabet[Math.floor(Math.random() * alphabet.length)];
  return id;
}

const CORS = ["https://opencastor.com", "https://app.opencastor.com", "http://localhost:3000"];

// ── Fork ──────────────────────────────────────────────────────────────────────

export const forkConfig = functions.onCall({ cors: CORS }, async (request: CallableRequest<unknown>) => {
  if (!request.auth) throw new functions.HttpsError("unauthenticated", "Login required");

  const { id, title, tags } = request.data as { id: string; title?: string; tags?: string[] };
  if (!id) throw new functions.HttpsError("invalid-argument", "id required");

  const original = await db().collection("configs").doc(id).get();
  if (!original.exists) throw new functions.HttpsError("not-found", `Config '${id}' not found`);

  const src = original.data()!;
  if (!src.public && src.author_uid !== request.auth.uid) {
    throw new functions.HttpsError("permission-denied", "Cannot fork private config");
  }

  const forkId = nanoid(10);
  const now = admin.firestore.FieldValue.serverTimestamp();
  const forkedTitle = title || `${src.title} (fork)`;

  await db().collection("configs").doc(forkId).set({
    ...src,
    id: forkId,
    title: forkedTitle,
    tags: tags || [...(src.tags || []), "fork"],
    author_uid: request.auth.uid,
    author_name: request.auth.token.name || request.auth.token.email || "anonymous",
    forked_from: id,
    forked_from_title: src.title,
    created_at: now,
    updated_at: now,
    stars: 0,
    installs: 0,
    public: false, // forks are private by default until published
  });

  await db().collection("configs").doc(id).update({
    forks: admin.firestore.FieldValue.increment(1),
  });

  return {
    id: forkId,
    url: `https://opencastor.com/config/${forkId}`,
    install_cmd: `castor install opencastor.com/config/${forkId}`,
  };
});

// ── Comments ─────────────────────────────────────────────────────────────────

export const addComment = functions.onCall({ cors: CORS }, async (request: CallableRequest<unknown>) => {
  if (!request.auth) throw new functions.HttpsError("unauthenticated", "Login required");

  const { config_id, text } = request.data as { config_id: string; text: string };
  if (!config_id || !text?.trim()) {
    throw new functions.HttpsError("invalid-argument", "config_id and text required");
  }
  if (text.length > 1000) {
    throw new functions.HttpsError("invalid-argument", "Comment too long (max 1000 chars)");
  }

  const commentId = nanoid(12);
  const now = admin.firestore.FieldValue.serverTimestamp();

  await db().collection("configs").doc(config_id)
    .collection("comments").doc(commentId).set({
      id: commentId,
      config_id,
      text: text.trim(),
      author_uid: request.auth.uid,
      author_name: request.auth.token.name || request.auth.token.email || "anonymous",
      created_at: now,
      edited: false,
    });

  await db().collection("configs").doc(config_id).update({
    comment_count: admin.firestore.FieldValue.increment(1),
  });

  return { id: commentId };
});

export const getComments = functions.onCall({ cors: CORS }, async (request: CallableRequest<unknown>) => {
  const { config_id, limit: rawLimit } = request.data as { config_id: string; limit?: number };
  if (!config_id) throw new functions.HttpsError("invalid-argument", "config_id required");

  const limit = Math.min(rawLimit ?? 20, 50);
  const snaps = await db().collection("configs").doc(config_id)
    .collection("comments")
    .orderBy("created_at", "desc")
    .limit(limit)
    .get();

  return { comments: snaps.docs.map(d => d.data()) };
});

export const deleteComment = functions.onCall({ cors: CORS }, async (request: CallableRequest<unknown>) => {
  if (!request.auth) throw new functions.HttpsError("unauthenticated", "Login required");

  const { config_id, comment_id } = request.data as { config_id: string; comment_id: string };
  if (!config_id || !comment_id) {
    throw new functions.HttpsError("invalid-argument", "config_id and comment_id required");
  }

  const ref = db().collection("configs").doc(config_id).collection("comments").doc(comment_id);
  const snap = await ref.get();
  if (!snap.exists) throw new functions.HttpsError("not-found", "Comment not found");
  if (snap.data()!.author_uid !== request.auth.uid) {
    throw new functions.HttpsError("permission-denied", "Can only delete own comments");
  }

  await ref.delete();
  await db().collection("configs").doc(config_id).update({
    comment_count: admin.firestore.FieldValue.increment(-1),
  });

  return { deleted: true };
});

// ── My Stars ─────────────────────────────────────────────────────────────────

export const getMyStars = functions.onCall({ cors: CORS }, async (request: CallableRequest<unknown>) => {
  if (!request.auth) throw new functions.HttpsError("unauthenticated", "Login required");

  // No orderBy — avoids composite index requirement; sort in memory instead
  const snaps = await db().collection("stars")
    .where("uid", "==", request.auth.uid)
    .limit(50)
    .get();

  const configIds = snaps.docs.map(d => d.data().config_id as string);
  if (configIds.length === 0) return { configs: [] };

  // Batch fetch configs (Firestore in-queries limited to 10)
  const chunks: string[][] = [];
  for (let i = 0; i < configIds.length; i += 10) chunks.push(configIds.slice(i, i + 10));

  const configs: admin.firestore.DocumentData[] = [];
  for (const chunk of chunks) {
    const results = await Promise.all(chunk.map(id => db().collection("configs").doc(id).get()));
    for (const snap of results) {
      if (snap.exists) {
        const { content: _, ...rest } = snap.data()!;
        configs.push(rest);
      }
    }
  }

  // Sort by stars desc in memory
  configs.sort((a, b) => (b.stars || 0) - (a.stars || 0));
  return { configs };
});

// ── My Configs (uploaded by current user) ────────────────────────────────────

export const getMyConfigs = functions.onCall({ cors: CORS }, async (request: CallableRequest<unknown>) => {
  if (!request.auth) throw new functions.HttpsError("unauthenticated", "Login required");

  // No orderBy — avoids composite index requirement; sort in memory instead
  const snaps = await db().collection("configs")
    .where("author_uid", "==", request.auth.uid)
    .limit(50)
    .get();

  const configs = snaps.docs.map(d => {
    const { content: _, ...rest } = d.data();
    return rest;
  });

  // Sort by installs desc in memory (newest uploads tend to have fewer installs)
  configs.sort((a, b) => (b.installs || 0) - (a.installs || 0));
  return { configs };
});

// ── Publish fork (make public) ────────────────────────────────────────────────

export const publishFork = functions.onCall({ cors: CORS }, async (request: CallableRequest<unknown>) => {
  if (!request.auth) throw new functions.HttpsError("unauthenticated", "Login required");

  const { id } = request.data as { id: string };
  if (!id) throw new functions.HttpsError("invalid-argument", "id required");

  const ref = db().collection("configs").doc(id);
  const snap = await ref.get();
  if (!snap.exists) throw new functions.HttpsError("not-found", "Config not found");
  if (snap.data()!.author_uid !== request.auth.uid) {
    throw new functions.HttpsError("permission-denied", "Can only publish own configs");
  }

  await ref.update({ public: true, updated_at: admin.firestore.FieldValue.serverTimestamp() });
  return { published: true, url: `https://opencastor.com/config/${id}` };
});
