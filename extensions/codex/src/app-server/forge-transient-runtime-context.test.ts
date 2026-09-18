import { Buffer } from "node:buffer";
import { describe, expect, it } from "vitest";
import {
  buildForgeTransientAdditionalContext,
  extractForgeTransientRuntimeContext,
} from "./forge-transient-runtime-context.js";

describe("Forge transient runtime context carrier", () => {
  it("extracts Forge current-turn context while leaving the durable Discord prompt clean", () => {
    const room = [
      "[FORGE_LIVE_CHANNEL_30_BEGIN]",
      "Previous messages from this Discord channel, oldest first; 2 shown:",
      "- first",
      "- second",
      "[FORGE_LIVE_CHANNEL_30_END]",
    ].join("\n");
    const source = [
      "OpenClaw runtime context for this turn:",
      "workspace reference",
      "",
      room,
      "",
      "Current user request:",
      "[meta channel=discord]",
      "hello Luna",
    ].join("\n");

    const result = extractForgeTransientRuntimeContext({
      messageProvider: "discord",
      promptText: source,
    });

    expect(result).toBeDefined();
    expect(result?.promptText).toBe("[meta channel=discord]\nhello Luna");
    expect(result?.promptText).not.toContain("FORGE_LIVE_CHANNEL_30_BEGIN");
    expect(result?.transientText).toContain(room);
    expect(result?.transientText).toContain("OpenClaw runtime context for this turn:");
  });

  it("chunks extracted context into bounded untrusted additionalContext entries", () => {
    const value = `[FORGE_LIVE_CHANNEL_30_BEGIN]\n${"x".repeat(1_900)}\n[FORGE_LIVE_CHANNEL_30_END]`;
    const context = buildForgeTransientAdditionalContext(value);

    expect(context).toBeDefined();
    const entries = Object.entries(context ?? {}).toSorted(([left], [right]) =>
      left.localeCompare(right),
    );
    expect(entries.length).toBeGreaterThan(1);
    expect(entries.every(([key]) => key.startsWith("forge_current_turn_context_"))).toBe(true);
    expect(entries.every(([, entry]) => entry.kind === "untrusted")).toBe(true);
    expect(entries.every(([, entry]) => Buffer.byteLength(entry.value, "utf8") <= 900)).toBe(true);
    expect(entries.map(([, entry]) => entry.value).join("")).toBe(value);
  });

  it("does nothing outside Discord", () => {
    expect(
      extractForgeTransientRuntimeContext({
        messageProvider: "telegram",
        promptText: "transient\n[meta x]\nhello",
      }),
    ).toBeUndefined();
  });
});
