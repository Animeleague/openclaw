import fs from "node:fs/promises";
import path from "node:path";
import { describe, expect, it } from "vitest";
import type { CodexTurnStartParams } from "./protocol.js";
import {
  createParams,
  createResumeHarness,
  createStartedThreadHarness,
  runCodexAppServerAttempt,
  setupRunAttemptTestHooks,
  tempDir,
} from "./run-attempt-test-harness.js";

setupRunAttemptTestHooks();

type TurnHarness =
  | ReturnType<typeof createStartedThreadHarness>
  | ReturnType<typeof createResumeHarness>;

function readTurnStartParams(harness: TurnHarness): CodexTurnStartParams {
  const request = harness.requests.find((entry) => entry.method === "turn/start");
  if (!request?.params || typeof request.params !== "object") {
    throw new Error("expected turn/start params");
  }
  return request.params as CodexTurnStartParams;
}

function readInputText(params: CodexTurnStartParams): string {
  return params.input
    .map((item) => (item.type === "text" ? item.text : ""))
    .filter(Boolean)
    .join("\n");
}

function readOpenClawRuntimeContext(params: CodexTurnStartParams): string {
  return Object.entries(params.additionalContext ?? {})
    .filter(([key]) => key.startsWith("openclaw_runtime_context_"))
    .toSorted(([left], [right]) => left.localeCompare(right))
    .map(([, entry]) => {
      expect(entry.kind).toBe("untrusted");
      return entry.value;
    })
    .join("");
}

describe("Codex runtime context native-history isolation", () => {
  it("keeps runtime reference context out of normal user input across three native turns", async () => {
    const sessionFile = path.join(tempDir, "runtime-context-session.jsonl");
    const workspaceDir = path.join(tempDir, "runtime-context-workspace");
    const canary = "runtime-context-canary-must-not-become-user-history";
    await fs.mkdir(workspaceDir, { recursive: true });
    await fs.writeFile(path.join(workspaceDir, "BOOTSTRAP.md"), canary, "utf8");

    const params = createParams(sessionFile, workspaceDir, {
      prompt: "actual user request",
    });

    for (let turnIndex = 0; turnIndex < 3; turnIndex += 1) {
      const harness: TurnHarness =
        turnIndex === 0 ? createStartedThreadHarness() : createResumeHarness();
      const run = runCodexAppServerAttempt(params);
      await harness.waitForMethod("turn/start");

      const turnStart = readTurnStartParams(harness);
      const inputText = readInputText(turnStart);
      const runtimeContext = readOpenClawRuntimeContext(turnStart);

      expect(inputText).toContain("actual user request");
      expect(inputText).not.toContain("OpenClaw runtime context for this turn:");
      expect(inputText).not.toContain(canary);
      expect(runtimeContext).toContain("OpenClaw runtime context for this turn:");
      expect(runtimeContext).toContain(canary);

      if (turnIndex > 0) {
        expect(harness.requests.some((entry) => entry.method === "thread/resume")).toBe(true);
      }

      await harness.completeTurn({ threadId: "thread-1", turnId: "turn-1" });
      await run;
    }
  });
});
