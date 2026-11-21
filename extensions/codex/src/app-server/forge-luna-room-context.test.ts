import { describe, expect, it } from "vitest";
import {
  extractForgeLunaRoomContextTurn,
  FORGE_LUNA_LATEST10_BEGIN_V120,
  FORGE_LUNA_LATEST10_END_V120,
} from "./forge-luna-room-context.js";

describe("Forge Luna room-context transaction boundary", () => {
  it("extracts only the terminal marked latest-10 tail", () => {
    const prompt = [
      "[meta time=2026-09-23 user=Mike]",
      "",
      "what did I just say?",
      "",
      FORGE_LUNA_LATEST10_BEGIN_V120,
      "[Discord | public | channel gaming-zone] one",
      "",
      "[Discord | public | channel gaming-zone] two",
      FORGE_LUNA_LATEST10_END_V120,
    ].join("\n");

    const result = extractForgeLunaRoomContextTurn({
      messageProvider: "discord",
      promptText: prompt,
    });

    expect(result?.cleanPromptText).toBe(
      "[meta time=2026-09-23 user=Mike]\n\nwhat did I just say?",
    );
    expect(result?.roomContextText).toContain("channel gaming-zone");
    expect(result?.dirtyPromptText).toContain("Current user request:");
    expect(result?.dirtyPromptText).toContain("what did I just say?");
    expect(result?.dirtyPromptText).not.toContain(FORGE_LUNA_LATEST10_BEGIN_V120);
    expect(result?.dirtyPromptText).not.toContain(FORGE_LUNA_LATEST10_END_V120);
  });

  it("uses the final standalone boundary when earlier user text contains marker-like content", () => {
    const prompt = [
      "[meta x]",
      `user typed ${FORGE_LUNA_LATEST10_BEGIN_V120} as ordinary text`,
      "",
      FORGE_LUNA_LATEST10_BEGIN_V120,
      "authoritative tail",
      FORGE_LUNA_LATEST10_END_V120,
    ].join("\n");

    const result = extractForgeLunaRoomContextTurn({
      messageProvider: "discord",
      promptText: prompt,
    });

    expect(result?.cleanPromptText).toContain("user typed");
    expect(result?.roomContextText).toBe("authoritative tail");
  });

  it("refuses a non-terminal or incomplete marker block", () => {
    expect(
      extractForgeLunaRoomContextTurn({
        messageProvider: "discord",
        promptText: [
          "[meta x]",
          FORGE_LUNA_LATEST10_BEGIN_V120,
          "room",
          FORGE_LUNA_LATEST10_END_V120,
          "extra text after boundary",
        ].join("\n"),
      }),
    ).toBeUndefined();

    expect(
      extractForgeLunaRoomContextTurn({
        messageProvider: "discord",
        promptText: `[meta x]\n${FORGE_LUNA_LATEST10_BEGIN_V120}\nroom`,
      }),
    ).toBeUndefined();
  });

  it("does nothing outside Discord", () => {
    expect(
      extractForgeLunaRoomContextTurn({
        messageProvider: "telegram",
        promptText: `x\n${FORGE_LUNA_LATEST10_BEGIN_V120}\nroom\n${FORGE_LUNA_LATEST10_END_V120}`,
      }),
    ).toBeUndefined();
  });
});
