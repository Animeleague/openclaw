import type { CodexAppServerClient } from "./client.js";

type ForgeLunaRoomContextClient = Pick<CodexAppServerClient, "request">;

export type ForgeLunaRoomContextTransactionResult = {
  rolledBack: true;
  injectedCleanPair: boolean;
};

/**
 * Replace one completed dirty Luna room-context turn with the visible native
 * history that should survive it. The target must still be the latest native
 * turn because thread/rollback operates from the tail.
 */
export async function commitForgeLunaRoomContextTransaction(params: {
  client: ForgeLunaRoomContextClient;
  signal?: AbortSignal;
  threadId: string;
  turnId: string;
  cleanUserText: string;
  assistantText: string;
  exactNoReply: boolean;
}): Promise<ForgeLunaRoomContextTransactionResult> {
  const read = await params.client.request(
    "thread/read",
    { threadId: params.threadId, includeTurns: true },
    { signal: params.signal },
  );
  const turns = Array.isArray(read.thread?.turns) ? read.thread.turns : [];
  const latestTurn = turns.at(-1);

  if (!latestTurn || latestTurn.id !== params.turnId) {
    throw new Error(
      `Forge Luna room-context transaction expected latest turn ${params.turnId}, got ${latestTurn?.id ?? "none"}`,
    );
  }

  const cleanUserText = params.cleanUserText.trim();
  const assistantText = params.assistantText.trim();

  if (!cleanUserText) {
    throw new Error("Forge Luna room-context transaction has no clean user text");
  }
  if (params.exactNoReply) {
    if (assistantText !== "NO_REPLY") {
      throw new Error("Forge Luna NO_REPLY transaction/native result mismatch");
    }
  } else if (!assistantText) {
    throw new Error("Forge Luna room-context transaction has no assistant text");
  }

  await params.client.request(
    "thread/rollback",
    { threadId: params.threadId, numTurns: 1 },
    { signal: params.signal },
  );

  if (!params.exactNoReply) {
    await params.client.request(
      "thread/inject_items",
      {
        threadId: params.threadId,
        items: [
          {
            type: "message",
            role: "user",
            content: [{ type: "input_text", text: cleanUserText }],
          },
          {
            type: "message",
            role: "assistant",
            content: [{ type: "output_text", text: assistantText }],
          },
        ],
      },
      { signal: params.signal },
    );
  }

  return {
    rolledBack: true,
    injectedCleanPair: !params.exactNoReply,
  };
}
