/**
 * Firestore security-rules tests for the robot command queue.
 *
 * What these pin down: a signed-in client cannot put a `system` scope command
 * into robots/{rrn}/commands, and cannot put an unattributed command there at
 * all. Those commands have to travel through the sendCommand callable, which is
 * where the owner-only check on system scope, the per-scope rate limit and the
 * issued_by_uid field live. Before this change the rules allowed any owner to
 * write the queue directly, so the first two tests below would have passed the
 * write.
 *
 * Run with the Firestore emulator:
 *
 *   firebase emulators:exec --only firestore "npm --prefix functions test"
 *
 * The emulator port (8080) comes from firebase.json.
 */

import { readFileSync } from "fs";
import * as path from "path";
import { strict as assert } from "assert";
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { setDoc, doc } from "firebase/firestore";

const PROJECT_ID = "opencastor-rules-test";
const REPO_ROOT = path.resolve(__dirname, "..", "..");
const RULES_PATH = path.join(REPO_ROOT, "firestore.rules");
const MISSIONS_PATH = path.join(REPO_ROOT, "functions", "src", "missions.ts");

const OWNER_UID = "owner-uid-1";
const RRN = "rrn:test:robot-1";

let testEnv: RulesTestEnvironment;

const EMULATOR_HOST = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
const [EMULATOR_ADDR, EMULATOR_PORT] = EMULATOR_HOST.split(":");

describe("firestore.rules — /robots/{rrn}/commands", () => {
  before(async () => {
    try {
      testEnv = await initializeTestEnvironment({
        projectId: PROJECT_ID,
        firestore: {
          rules: readFileSync(RULES_PATH, "utf8"),
          host: EMULATOR_ADDR,
          port: Number(EMULATOR_PORT),
        },
      });
    } catch (err) {
      // Without FIRESTORE_EMULATOR_HOST this falls back to 127.0.0.1:8080,
      // where some other process may well be listening. Say what we tried to
      // talk to, so a stray 404 from an unrelated service is not mistaken for
      // a rules failure.
      throw new Error(
        `could not reach the Firestore emulator at ${EMULATOR_HOST} ` +
          `(${err instanceof Error ? err.message : String(err)}). ` +
          "Run this suite as: " +
          'firebase emulators:exec --only firestore "npm --prefix functions test" ' +
          "— or export FIRESTORE_EMULATOR_HOST if the emulator is already up on " +
          "another port."
      );
    }

    // Seed the robot doc with the Admin path (rules disabled), the way the
    // castor bridge would.
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "robots", RRN), {
        rrn: RRN,
        name: "Test Robot",
        owner: "rrn://test/owner",
        firebase_uid: OWNER_UID,
      });
    });
  });

  after(async () => {
    if (testEnv) await testEnv.cleanup();
  });

  beforeEach(async () => {
    // Keep the seeded robot doc; only clear command writes between tests.
    // clearFirestore() would drop the robot doc too, so re-seed after it.
    await testEnv.clearFirestore();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), "robots", RRN), {
        rrn: RRN,
        name: "Test Robot",
        owner: "rrn://test/owner",
        firebase_uid: OWNER_UID,
      });
    });
  });

  it("test_client_cannot_create_system_scope_command", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertFails(
      setDoc(doc(db, "robots", RRN, "commands", "cmd-system"), {
        instruction: "contribute_start",
        scope: "system",
        issued_by_uid: OWNER_UID,
        issued_at: new Date().toISOString(),
        status: "pending",
      })
    );
  });

  it("test_client_cannot_create_command_without_issued_by_uid", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertFails(
      setDoc(doc(db, "robots", RRN, "commands", "cmd-anon"), {
        instruction: "hello",
        scope: "chat",
        issued_at: new Date().toISOString(),
        status: "pending",
      })
    );
  });

  it("test_owner_can_still_create_a_chat_scope_command", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertSucceeds(
      setDoc(doc(db, "robots", RRN, "commands", "cmd-chat"), {
        instruction: "hello",
        scope: "chat",
        issued_by_uid: OWNER_UID,
        issued_at: new Date().toISOString(),
        status: "pending",
      })
    );
  });

  it("test_client_cannot_forge_issued_by_uid_for_another_user", async () => {
    const db = testEnv.authenticatedContext(OWNER_UID).firestore();
    await assertFails(
      setDoc(doc(db, "robots", RRN, "commands", "cmd-forged"), {
        instruction: "hello",
        scope: "chat",
        issued_by_uid: "someone-else",
        issued_at: new Date().toISOString(),
        status: "pending",
      })
    );
  });

  it("test_non_owner_cannot_create_a_chat_scope_command", async () => {
    const db = testEnv.authenticatedContext("stranger-uid").firestore();
    await assertFails(
      setDoc(doc(db, "robots", RRN, "commands", "cmd-stranger"), {
        instruction: "hello",
        scope: "chat",
        issued_by_uid: "stranger-uid",
        issued_at: new Date().toISOString(),
        status: "pending",
      })
    );
  });
});

describe("missions fanout", () => {
  it("test_mission_fanout_carries_no_participants_field", () => {
    const src = readFileSync(MISSIONS_PATH, "utf8");

    // The fanout is the only place that writes into a robot's command queue.
    const marker = 'context: "mission_thread"';
    const markerAt = src.indexOf(marker);
    assert.notEqual(
      markerAt,
      -1,
      "could not find the mission_thread fanout in missions.ts"
    );

    // Look at the object literal the marker sits in.
    const blockStart = src.lastIndexOf(".set({", markerAt);
    assert.notEqual(blockStart, -1, "could not find the fanout .set({ ... })");
    const blockEnd = src.indexOf("});", markerAt);
    const block = src.slice(blockStart, blockEnd);

    assert.ok(
      !/\bparticipants\s*:/.test(block),
      "mission fanout still writes a participants field into each robot's " +
        "command doc — a robot does not need the roster of the others"
    );
  });
});
