/**
 * Harness safety gate — validateAndSaveHarness callable.
 *
 * Validates harness layers + flow graph edges before any Firestore write.
 * This is the authoritative server-side gate; even API callers cannot bypass it.
 *
 * Returns: { ok: true, docId: string, warnings: ValidationIssueCF[] }
 * Throws:  HttpsError('failed-precondition') with { issues } detail if BLOCK-level issues found.
 */

import * as functions from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

// ─── Types ────────────────────────────────────────────────────────────────────

export interface FlowEdgeCF {
  fromId: string;
  toId: string;
  isLoop?: boolean;
}

export interface HarnessLayerCF {
  id: string;
  label: string;
  enabled: boolean;
  type?: string;
  config?: Record<string, unknown>;
  canDisable?: boolean;
}

export interface ValidationIssueCF {
  severity: "block" | "warn";
  code: string;
  message: string;
}

// ─── Constants ────────────────────────────────────────────────────────────────

const FORBIDDEN_KEYS = new Set([
  "safety",
  "auth",
  "p66",
  "estop",
  "motor",
  "motor_params",
  "hardware",
  "emergency_stop",
  "pin",
  "secret",
  "api_key",
  "token",
  "password",
  "private_key",
]);

const ALWAYS_ON_IDS = new Set(["trajectory-logger", "p66"]);

// ─── Core validator ───────────────────────────────────────────────────────────

export function validateHarness(
  layers: HarnessLayerCF[],
  edges: FlowEdgeCF[],
): ValidationIssueCF[] {
  const issues: ValidationIssueCF[] = [];

  // ── Check 1: Always-on layers present and enabled ─────────────────────────
  for (const id of ALWAYS_ON_IDS) {
    const layer = layers.find((l) => l.id === id);
    if (!layer) {
      issues.push({
        severity: "block",
        code: "ALWAYS_ON_MISSING",
        message: `Required layer "${id}" is missing.`,
      });
    } else if (!layer.enabled) {
      issues.push({
        severity: "block",
        code: "ALWAYS_ON_DISABLED",
        message: `Layer "${id}" must always be enabled.`,
      });
    }
  }

  // ── Check 2: Forbidden keys in layer configs ──────────────────────────────
  for (const layer of layers) {
    for (const key of Object.keys(layer.config ?? {})) {
      if (FORBIDDEN_KEYS.has(key.toLowerCase())) {
        issues.push({
          severity: "block",
          code: "FORBIDDEN_KEY",
          message: `Layer "${layer.label}" contains forbidden key "${key}".`,
        });
      }
    }
  }

  // ── Check 3: Duplicate layer IDs ─────────────────────────────────────────
  const seen = new Set<string>();
  for (const layer of layers) {
    if (seen.has(layer.id)) {
      issues.push({
        severity: "block",
        code: "DUPLICATE_LAYER_ID",
        message: `Duplicate layer id "${layer.id}".`,
      });
    }
    seen.add(layer.id);
  }

  // ── Check 4: Cycle detection (DFS) ────────────────────────────────────────
  if (edges.length > 0) {
    const adj = new Map<string, string[]>();
    for (const e of edges) {
      if (!adj.has(e.fromId)) adj.set(e.fromId, []);
      adj.get(e.fromId)!.push(e.toId);
    }
    const allNodes = [
      ...new Set([...edges.map((e) => e.fromId), ...edges.map((e) => e.toId)]),
    ];
    const visited = new Set<string>();
    const inStack = new Set<string>();

    function hasCycle(node: string): boolean {
      if (inStack.has(node)) return true;
      if (visited.has(node)) return false;
      visited.add(node);
      inStack.add(node);
      for (const next of adj.get(node) ?? []) {
        if (hasCycle(next)) return true;
      }
      inStack.delete(node);
      return false;
    }

    let cycleFound = false;
    for (const node of allNodes) {
      if (!visited.has(node) && hasCycle(node)) {
        cycleFound = true;
        break;
      }
    }

    if (cycleFound) {
      // Check if any loop edge has an exit to a non-loop destination
      const loopEdges = edges.filter((e) => e.isLoop);
      const hasExitEdge = loopEdges.some((loopEdge) =>
        edges.some(
          (e) =>
            !e.isLoop &&
            e.fromId === loopEdge.toId &&
            e.toId !== loopEdge.fromId,
        ),
      );
      issues.push({
        severity: hasExitEdge ? "warn" : "block",
        code: hasExitEdge ? "LOOP_WITH_EXIT" : "INFINITE_LOOP",
        message: hasExitEdge
          ? "Flow graph contains a loop — verify the exit condition is reachable."
          : "Flow graph contains an unescapable loop. Add an exit edge or timeout node.",
      });
    }
  }

  return issues;
}

// ─── Cloud Function ───────────────────────────────────────────────────────────

export const validateAndSaveHarness = functions.onCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth) {
      throw new functions.HttpsError("unauthenticated", "Login required");
    }

    const { configId, layers, edges, content, title, tags } =
      request.data as {
        configId?: string;
        layers: HarnessLayerCF[];
        edges: FlowEdgeCF[];
        content: string;
        title: string;
        tags: string[];
      };

    if (!layers || !Array.isArray(layers)) {
      throw new functions.HttpsError(
        "invalid-argument",
        "layers is required and must be an array",
      );
    }
    if (!content || typeof content !== "string") {
      throw new functions.HttpsError(
        "invalid-argument",
        "content is required",
      );
    }
    if (!title || typeof title !== "string") {
      throw new functions.HttpsError(
        "invalid-argument",
        "title is required",
      );
    }

    // ── Server-side safety validation ─────────────────────────────────────
    const issues = validateHarness(layers, edges ?? []);
    const blocked = issues.some((i) => i.severity === "block");
    if (blocked) {
      throw new functions.HttpsError(
        "failed-precondition",
        "Harness failed safety validation",
        { issues: issues.filter((i) => i.severity === "block") },
      );
    }

    // ── Persist to Firestore ──────────────────────────────────────────────
    const db = admin.firestore();
    const uid = request.auth.uid;
    const docId =
      configId ??
      `harness-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;

    const userDoc = await db.collection("users").doc(uid).get();
    const authorName =
      (userDoc.data()?.display_name as string | undefined) ?? "Unknown";

    await db
      .collection("configs")
      .doc(docId)
      .set(
        {
          id: docId,
          type: "harness",
          title,
          content,
          tags: [...new Set([...(tags ?? []), "rcan-1.6"])],
          author_id: uid,
          author_name: authorName,
          public: false,
          rcan_version: "1.6.1",
          validation_warnings: issues
            .filter((i) => i.severity === "warn")
            .map((i) => i.message),
          updated_at: new Date().toISOString(),
        },
        { merge: true },
      );

    return {
      ok: true,
      docId,
      warnings: issues.filter((i) => i.severity === "warn"),
    };
  },
);
