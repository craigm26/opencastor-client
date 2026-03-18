/**
 * OpenCastor Cloud Functions — entry point.
 * Exports all callable functions and Firestore triggers.
 */

import * as admin from "firebase-admin";

// Initialize Firebase Admin (once)
admin.initializeApp();

// Command relay
export { sendCommand, getCommandStatus, registerFcmToken } from "./relay";

// R2RAM consent handshake
export { requestConsent, resolveConsent, revokeConsent, onConsentResolved } from "./consent";

// Community hub — Phase 2 config/skill/harness sharing
export { uploadConfig, getConfig, searchConfigs, starConfig, importCommunityConfig } from "./hub";

// Phase 4 social layer
export { forkConfig, addComment, getComments, deleteComment, getMyStars, getMyConfigs, publishFork } from "./social";

// Fleet registration limit (MAX_ROBOTS = 2 per user, free tier)
export { registerRobot, enforceRobotLimit } from "./registration";
