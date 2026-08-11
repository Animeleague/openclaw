import { Buffer } from "node:buffer";
import { describe, expect, it } from "vitest";
import {
  buildCodexUntrustedAdditionalContextChunks,
  detachCodexRuntimeContext,
  mergeCodexAdditionalContext,
} from "./turn-additional-context.js";

describe("Codex turn additional context", () => {
  it("chunks untrusted context without changing its contents", () => {
    const value = `${"a".repeat(897)}😀${"b".repeat(950)}`;
    const context = buildCodexUntrustedAdditionalContextChunks({
      keyPrefix: "openclaw_runtime_context",
      value,
    });

    expect(context).toBeDefined();
    const entries = Object.entries(context ?? {});
    expect(entries.length).toBeGreaterThan(1);
    expect(entries.map(([, entry]) => entry.value).join("")).toBe(value);
    expect(entries.every(([, entry]) => entry.kind === "untrusted")).toBe(true);
    expect(entries.every(([, entry]) => Buffer.byteLength(entry.value, "utf8") <= 900)).toBe(true);
  });

  it("detaches only an exact leading runtime context block", () => {
    const runtimeContext = [
      "OpenClaw runtime context for this turn:",
      "workspace canary",
    ].join("\n");
    const promptText = `${runtimeContext}\n\nCurrent user request:\nhello`;

    expect(detachCodexRuntimeContext({ promptText, runtimeContext })).toEqual({
      promptText: "Current user request:\nhello",
      runtimeContext,
    });
    expect(
      detachCodexRuntimeContext({
        promptText: `prefix\n${promptText}`,
        runtimeContext,
      }),
    ).toEqual({ promptText: `prefix\n${promptText}` });
  });

  it("merges runtime context without overwriting reserved sender context", () => {
    expect(
      mergeCodexAdditionalContext(
        {
          openclaw_runtime_context_0000: { kind: "untrusted", value: "runtime" },
        },
        {
          openclaw_current_sender: { kind: "untrusted", value: "sender" },
        },
      ),
    ).toEqual({
      openclaw_runtime_context_0000: { kind: "untrusted", value: "runtime" },
      openclaw_current_sender: { kind: "untrusted", value: "sender" },
    });
  });
});
