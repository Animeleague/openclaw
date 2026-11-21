import { describe, expect, it } from "vitest";
import { commitForgeLunaRoomContextTransaction } from "./forge-luna-room-transaction.js";

function fakeClient(turnId = "turn-1") {
  const calls: Array<{ method: string; params: unknown }> = [];
  return {
    calls,
    client: {
      request: async (method: string, params: unknown) => {
        calls.push({ method, params });
        if (method === "thread/read") {
          return {
            thread: {
              id: "thread-1",
              turns: [{ id: turnId, items: [] }],
            },
          };
        }
        return {};
      },
    },
  };
}

describe("Forge Luna room-context native transaction", () => {
  it("rolls back and injects only the clean visible pair for a normal reply", async () => {
    const fake = fakeClient();

    const result = await commitForgeLunaRoomContextTransaction({
      client: fake.client as never,
      threadId: "thread-1",
      turnId: "turn-1",
      cleanUserText: "[meta x]\nhello",
      assistantText: "hi Mike",
      exactNoReply: false,
    });

    expect(result).toEqual({ rolledBack: true, injectedCleanPair: true });
    expect(fake.calls.map((call) => call.method)).toEqual([
      "thread/read",
      "thread/rollback",
      "thread/inject_items",
    ]);
    expect(fake.calls[2]?.params).toMatchObject({
      threadId: "thread-1",
      items: [
        { type: "message", role: "user", content: [{ type: "input_text", text: "[meta x]\nhello" }] },
        { type: "message", role: "assistant", content: [{ type: "output_text", text: "hi Mike" }] },
      ],
    });
  });

  it("rolls back and injects nothing for exact NO_REPLY", async () => {
    const fake = fakeClient();

    const result = await commitForgeLunaRoomContextTransaction({
      client: fake.client as never,
      threadId: "thread-1",
      turnId: "turn-1",
      cleanUserText: "[meta x]\ndo not reply",
      assistantText: "NO_REPLY",
      exactNoReply: true,
    });

    expect(result).toEqual({ rolledBack: true, injectedCleanPair: false });
    expect(fake.calls.map((call) => call.method)).toEqual(["thread/read", "thread/rollback"]);
  });

  it("refuses to roll back when the owned turn is no longer the native tail", async () => {
    const fake = fakeClient("newer-turn");

    await expect(
      commitForgeLunaRoomContextTransaction({
        client: fake.client as never,
        threadId: "thread-1",
        turnId: "turn-1",
        cleanUserText: "hello",
        assistantText: "hi",
        exactNoReply: false,
      }),
    ).rejects.toThrow(/expected latest turn turn-1/iu);

    expect(fake.calls.map((call) => call.method)).toEqual(["thread/read"]);
  });
});
