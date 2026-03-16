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
