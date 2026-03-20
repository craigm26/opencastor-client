/**
 * robotApiGet — Proxy GET requests to a robot's local API.
 *
 * The Flutter client calls this to fetch robot hardware profiles, status,
 * and other read-only data from robots that are behind NAT/firewalls.
 *
 * Flow:
 *   1. Verify Firebase Auth
 *   2. Verify caller owns the robot
 *   3. Look up robot's bridge URL from Firestore
 *   4. Forward GET request to robot's API endpoint
 *   5. Return response body
 */

import * as admin from "firebase-admin";
import { https } from "firebase-functions/v2";

const db = () => admin.firestore();

interface RobotApiGetPayload {
  rrn: string;
  path: string;
}

export const robotApiGet = https.onCall(
  {
    cors: [
      "https://app.opencastor.com",
      "https://opencastor-client.pages.dev",
      "http://localhost",
    ],
    invoker: "public",
  },
  async (request) => {
    const auth = request.auth;
    if (!auth) {
      throw new https.HttpsError("unauthenticated", "Must be authenticated");
    }

    const data = request.data as RobotApiGetPayload;
    if (!data.rrn || !data.path) {
      throw new https.HttpsError(
        "invalid-argument",
        "rrn and path are required"
      );
    }

    // Sanitize path — must start with /api/
    const path = data.path.startsWith("/") ? data.path : `/${data.path}`;
    if (!path.startsWith("/api/")) {
      throw new https.HttpsError(
        "invalid-argument",
        "path must start with /api/"
      );
    }

    // Verify ownership
    const robotRef = db().collection("robots").doc(data.rrn);
    const robotDoc = await robotRef.get();
    if (!robotDoc.exists) {
      throw new https.HttpsError("not-found", `Robot ${data.rrn} not found`);
    }

    const robotData = robotDoc.data();
    if (!robotData) {
      throw new https.HttpsError("not-found", "Robot data missing");
    }

    // Check ownership
    if (robotData.owner_uid !== auth.uid) {
      // Check if user has consent/sharing access
      const consentSnap = await db()
        .collection("robots")
        .doc(data.rrn)
        .collection("consents")
        .where("grantee_uid", "==", auth.uid)
        .where("status", "==", "active")
        .limit(1)
        .get();

      if (consentSnap.empty) {
        throw new https.HttpsError(
          "permission-denied",
          "You don't have access to this robot"
        );
      }
    }

    // Get robot's bridge URL from telemetry
    const bridgeUrl = robotData.bridge_url || robotData.gateway_url;
    const apiToken = robotData.api_token;

    if (!bridgeUrl) {
      // Robot doesn't have a bridge URL — return data from Firestore telemetry instead
      return _getFallbackData(robotData, path);
    }

    // Forward request to robot's bridge
    try {
      const url = `${bridgeUrl.replace(/\/$/, "")}${path}`;
      const headers: Record<string, string> = {
        "Content-Type": "application/json",
      };
      if (apiToken) {
        headers["Authorization"] = `Bearer ${apiToken}`;
      }

      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 8000);

      const response = await fetch(url, {
        method: "GET",
        headers,
        signal: controller.signal,
      });

      clearTimeout(timeout);

      if (!response.ok) {
        return _getFallbackData(robotData, path);
      }

      const body = await response.json();
      return { body, source: "bridge" };
    } catch (err) {
      // Bridge unreachable — fall back to Firestore data
      return _getFallbackData(robotData, path);
    }
  }
);

/**
 * When the bridge is unreachable, return what we have from Firestore telemetry.
 */
function _getFallbackData(
  robotData: admin.firestore.DocumentData,
  path: string
): Record<string, unknown> {
  if (path === "/api/hardware" || path.startsWith("/api/hardware")) {
    // Return hardware profile from telemetry if available
    const telemetry = robotData.telemetry || {};
    const hardware = telemetry.hardware || {};
    return {
      body: {
        hostname: robotData.hostname || hardware.hostname || "unknown",
        arch: hardware.arch || "unknown",
        platform: hardware.platform || "unknown",
        cpu_model: hardware.cpu_model || "unknown",
        cpu_cores: hardware.cpu_cores || 0,
        ram_gb: hardware.ram_gb || 0,
        ram_available_gb: hardware.ram_available_gb || 0,
        storage_free_gb: hardware.storage_free_gb || 0,
        accelerators: hardware.accelerators || [],
        accessories: hardware.accessories || [],
        hardware_tier: hardware.hardware_tier || "unknown",
        ollama_models: hardware.ollama_models || [],
        rcan_hardware: hardware.rcan_hardware || {},
      },
      source: "firestore-fallback",
    };
  }

  if (path === "/api/status" || path.startsWith("/api/status")) {
    return {
      body: {
        version: robotData.version || robotData.telemetry?.version || "unknown",
        status: robotData.status || "unknown",
        uptime: robotData.telemetry?.uptime || 0,
      },
      source: "firestore-fallback",
    };
  }

  return { body: {}, source: "firestore-fallback" };
}
