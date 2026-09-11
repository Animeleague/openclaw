import { describe, expect, it } from "vitest";
import { normalizeMessageActionInput } from "./message-action-normalization.js";

describe("Discord legacy channelId normalization", () => {
  it("preserves channel semantics when read channelId is projected to to", () => {
    const result = normalizeMessageActionInput({
      action: "read",
      args: {
        channel: "discord",
        channelId: "1538566856682766406",
      },
    });

    expect(result.target).toBe("channel:1538566856682766406");
    expect(result.to).toBe("channel:1538566856682766406");
    expect(result.channelId).toBeUndefined();
  });

  it("does not reinterpret an explicit generic to target", () => {
    const result = normalizeMessageActionInput({
      action: "read",
      args: {
        channel: "discord",
        to: "1538566856682766406",
      },
    });

    expect(result.target).toBe("1538566856682766406");
    expect(result.to).toBe("1538566856682766406");
  });
});
