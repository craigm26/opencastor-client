/**
 * OpenCastor Hub — Phase 2 config/skill/harness sharing backend.
 *
 * Firestore schema:
 *   configs/{configId}
 *     id: string          — nanoid (10 chars)
 *     type: "preset" | "skill" | "harness"
 *     title: string
 *     description: string
 *     tags: string[]
 *     hardware: string    — e.g. "raspberry-pi-4", "so-arm101", "picar-x"
 *     rcan_version: string
 *     provider: string    — "google" | "anthropic" | "ollama" | "other"
 *     content: string     — raw YAML or SKILL.md (scrubbed of secrets)
 *     filename: string    — e.g. "arm.rcan.yaml"
 *     author_uid: string  — Firebase Auth UID
 *     author_name: string — display name
 *     created_at: Timestamp
 *     updated_at: Timestamp
 *     stars: number
 *     installs: number
 *     public: boolean
 *     robot_rrn?: string  — if shared from a specific robot
 */

import * as functions from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { CallableRequest } from "firebase-functions/v2/https";

const db = () => admin.firestore();

// Nano-ID for short readable config IDs
function nanoid(size = 10): string {
  const alphabet = "abcdefghijklmnopqrstuvwxyz0123456789";
  let id = "";
  for (let i = 0; i < size; i++) {
    id += alphabet[Math.floor(Math.random() * alphabet.length)];
  }
  return id;
}

// ── Secret scrubbing ─────────────────────────────────────────────────────────

const SECRET_PATTERNS = [
  /api[_-]?key\s*[:=]\s*['"]?[A-Za-z0-9_\-]{20,}['"]?/gi,
  /token\s*[:=]\s*['"]?[A-Za-z0-9_\-\.]{20,}['"]?/gi,
  /password\s*[:=]\s*['"]?.+['"]?/gi,
  /secret\s*[:=]\s*['"]?.+['"]?/gi,
  /credentials\s*[:=]\s*['"]?.+['"]?/gi,
  /private[_-]?key\s*[:=]\s*['"]?.+['"]?/gi,
  /service[_-]?account\s*[:=]\s*['"]?.+['"]?/gi,
  /sa[_-]?key\s*[:=]\s*['"]?.+['"]?/gi,
];

function scrubSecrets(content: string): string {
  let scrubbed = content;
  for (const pattern of SECRET_PATTERNS) {
    scrubbed = scrubbed.replace(pattern, "[REDACTED]");
  }
  return scrubbed;
}

// ── Input validation ─────────────────────────────────────────────────────────

interface UploadConfigRequest {
  type: "preset" | "skill" | "harness";
  title: string;
  description?: string;
  tags?: string[];
  hardware?: string;
  content: string;
  filename: string;
  robot_rrn?: string;
  public?: boolean;
}

function validateUploadRequest(data: unknown): UploadConfigRequest {
  const req = data as Record<string, unknown>;
  if (!req.type || !["preset", "skill", "harness"].includes(req.type as string)) {
    throw new functions.HttpsError("invalid-argument", "type must be preset, skill, or harness");
  }
  if (!req.title || typeof req.title !== "string" || req.title.length > 100) {
    throw new functions.HttpsError("invalid-argument", "title is required (max 100 chars)");
  }
  if (!req.content || typeof req.content !== "string") {
    throw new functions.HttpsError("invalid-argument", "content is required");
  }
  if (req.content.length > 50000) {
    throw new functions.HttpsError("invalid-argument", "content exceeds 50KB limit");
  }
  if (!req.filename || typeof req.filename !== "string") {
    throw new functions.HttpsError("invalid-argument", "filename is required");
  }
  return req as unknown as UploadConfigRequest;
}

// ── Extract metadata from YAML content ───────────────────────────────────────

function extractYamlMeta(content: string): { rcan_version: string; provider: string; hardware: string } {
  const rcanMatch = content.match(/rcan_version\s*:\s*['"]?([0-9.]+)['"]?/);
  const providerMatch = content.match(/provider\s*:\s*['"]?([a-z0-9_-]+)['"]?/);
  const typeMatch = content.match(/type\s*:\s*['"]?([a-z_-]+)['"]?/);
  return {
    rcan_version: rcanMatch ? rcanMatch[1] : "unknown",
    provider: providerMatch ? providerMatch[1] : "unknown",
    hardware: typeMatch ? typeMatch[1] : "unknown",
  };
}

// ── Cloud Functions ───────────────────────────────────────────────────────────

/**
 * uploadConfig — upload a config/skill/harness to the community hub.
 * Requires Firebase Auth. Content is scrubbed of secrets before storage.
 */
export const uploadConfig = functions.onCall(
  { cors: ["https://opencastor.com", "https://app.opencastor.com", "http://localhost:3000"] },
  async (request: CallableRequest<unknown>) => {
    if (!request.auth) {
      throw new functions.HttpsError("unauthenticated", "Authentication required to share configs");
    }

    const data = validateUploadRequest(request.data);
    const scrubbed = scrubSecrets(data.content);
    const meta = extractYamlMeta(scrubbed);
    const configId = nanoid(10);
    const now = admin.firestore.FieldValue.serverTimestamp();

    const doc = {
      id: configId,
      type: data.type,
      title: data.title.trim(),
      description: (data.description || "").trim().slice(0, 500),
      tags: (data.tags || []).slice(0, 10).map((t) => String(t).toLowerCase().trim()),
      hardware: data.hardware || meta.hardware,
      rcan_version: meta.rcan_version,
      provider: meta.provider,
      content: scrubbed,
      filename: data.filename,
      author_uid: request.auth.uid,
      author_name: request.auth.token.name || request.auth.token.email || "anonymous",
      created_at: now,
      updated_at: now,
      stars: 0,
      installs: 0,
      public: data.public !== false,
      robot_rrn: data.robot_rrn || null,
    };

    await db().collection("configs").doc(configId).set(doc);

    return {
      id: configId,
      url: `https://opencastor.com/config/${configId}`,
      install_cmd: `castor install opencastor.com/config/${configId}`,
    };
  }
);

/**
 * getConfig — fetch a single config by ID.
 * Public configs are accessible without auth.
 */
export const getConfig = functions.onCall(
  { cors: ["https://opencastor.com", "https://app.opencastor.com", "http://localhost:3000"] },
  async (request: CallableRequest<unknown>) => {
    const { id } = request.data as { id: string };
    if (!id || typeof id !== "string") {
      throw new functions.HttpsError("invalid-argument", "id is required");
    }

    const snap = await db().collection("configs").doc(id).get();
    if (!snap.exists) {
      throw new functions.HttpsError("not-found", `Config '${id}' not found`);
    }

    const data = snap.data()!;

    // Private configs only visible to owner
    if (!data.public && (!request.auth || request.auth.uid !== data.author_uid)) {
      throw new functions.HttpsError("permission-denied", "This config is private");
    }

    // Increment install count when content is fetched
    await snap.ref.update({ installs: admin.firestore.FieldValue.increment(1) });

    return data;
  }
);

/**
 * searchConfigs — search and filter community configs.
 * Returns paginated list of public configs.
 */
export const searchConfigs = functions.onCall(
  { cors: ["https://opencastor.com", "https://app.opencastor.com", "http://localhost:3000"] },
  async (request: CallableRequest<unknown>) => {
    const params = (request.data as Record<string, unknown>) || {};
    const type = params.type as string | undefined;
    const hardware = params.hardware as string | undefined;
    const provider = params.provider as string | undefined;
    const rcan_version = params.rcan_version as string | undefined;
    const limit = Math.min(Number(params.limit) || 20, 50);

    // Use a simple public==true query to avoid composite index requirements.
    // Filtering and sorting happen in memory — collection stays small (<500 docs).
    let query: admin.firestore.Query = db()
      .collection("configs")
      .where("public", "==", true)
      .limit(200); // over-fetch, filter in memory

    const snaps = await query.get();
    let docs = snaps.docs.map((doc) => doc.data());

    // Apply filters in memory
    if (type) docs = docs.filter((d) => d.type === type);
    if (hardware) docs = docs.filter((d) => d.hardware === hardware);
    if (provider) docs = docs.filter((d) => d.provider === provider);
    if (rcan_version) docs = docs.filter((d) => d.rcan_version === rcan_version);

    // Sort by stars desc, then installs desc (no created_at index needed)
    docs.sort((a, b) => {
      const starDiff = (b.stars || 0) - (a.stars || 0);
      if (starDiff !== 0) return starDiff;
      return (b.installs || 0) - (a.installs || 0);
    });

    const results = docs.slice(0, limit).map((d) => {
      const { content: _content, ...rest } = d as Record<string, unknown>;
      return { ...rest, has_content: true };
    });

    return { results, count: results.length };
  }
);

/**
 * starConfig — toggle a star on a config.
 */
export const starConfig = functions.onCall(
  { cors: ["https://opencastor.com", "https://app.opencastor.com", "http://localhost:3000"] },
  async (request: CallableRequest<unknown>) => {
    if (!request.auth) {
      throw new functions.HttpsError("unauthenticated", "Authentication required to star configs");
    }

    const { id } = request.data as { id: string };
    if (!id) throw new functions.HttpsError("invalid-argument", "id is required");

    const starRef = db().collection("stars").doc(`${request.auth.uid}_${id}`);
    const configRef = db().collection("configs").doc(id);

    const starSnap = await starRef.get();
    if (starSnap.exists) {
      // Unstar
      await starRef.delete();
      await configRef.update({ stars: admin.firestore.FieldValue.increment(-1) });
      return { starred: false };
    } else {
      // Star
      await starRef.set({ uid: request.auth.uid, config_id: id, created_at: admin.firestore.FieldValue.serverTimestamp() });
      await configRef.update({ stars: admin.firestore.FieldValue.increment(1) });
      return { starred: true };
    }
  }
);

/**
 * importCommunityConfig — server-side import of a config from config/community/ dir.
 * Called by the Ecosystem Monitor to seed the Firestore hub.
 * Admin-only (service account).
 */
export const importCommunityConfig = functions.onCall(
  { cors: ["https://app.opencastor.com"] },
  async (request: CallableRequest<unknown>) => {
    if (!request.auth) {
      throw new functions.HttpsError("unauthenticated", "Admin required");
    }

    // Verify caller is the ops service account
    const tokenEmail = request.auth.token.email || "";
    if (!tokenEmail.includes("firebase-adminsdk")) {
      throw new functions.HttpsError("permission-denied", "Admin service account required");
    }

    const configs = request.data as Array<{ filename: string; content: string; title: string; tags: string[] }>;
    const results: string[] = [];

    for (const cfg of configs) {
      const id = cfg.filename.replace(/[^a-z0-9-]/gi, "-").toLowerCase().replace(/\.rcan\.yaml$/, "").slice(0, 20);
      const meta = extractYamlMeta(cfg.content);
      await db().collection("configs").doc(id).set({
        id,
        type: "preset",
        title: cfg.title,
        description: "Community-contributed preset from the OpenCastor repository",
        tags: cfg.tags || [],
        hardware: meta.hardware,
        rcan_version: meta.rcan_version,
        provider: meta.provider,
        content: scrubSecrets(cfg.content),
        filename: cfg.filename,
        author_uid: "community",
        author_name: "OpenCastor Community",
        created_at: admin.firestore.FieldValue.serverTimestamp(),
        updated_at: admin.firestore.FieldValue.serverTimestamp(),
        stars: 0,
        installs: 0,
        public: true,
      }, { merge: true });
      results.push(id);
    }

    return { imported: results };
  }
);
