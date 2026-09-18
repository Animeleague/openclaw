import { describe, expect, it } from "vitest";
import { extractForgeTransientRuntimeContext } from "./forge-transient-runtime-context.js";

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
    expect(result?.developerInstructions).toContain(room);
    expect(result?.developerInstructions).toContain("## Forge Current-Turn Runtime Context");
    expect(result?.developerInstructions.endsWith("</forge_current_turn_context>")).toBe(true);
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
