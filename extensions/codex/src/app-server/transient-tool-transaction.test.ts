import { beforeEach, describe, expect, it, vi } from "vitest";
import type { CodexAppServerClient } from "./client.js";
import type {
  CodexAppServerBindingIdentity,
  CodexAppServerBindingStore,
  CodexAppServerThreadBinding,
} from "./session-binding.js";
import type { CodexAppServerThreadLifecycleBinding } from "./thread-lifecycle.js";

const liveThreadMocks = vi.hoisted(() => ({
  retain: vi.fn(),
  release: vi.fn(),
}));

vi.mock("./client-runtime.js", async (importOriginal) => ({
  ...(await importOriginal()),
  retainCodexAppServerLiveThread: liveThreadMocks.retain,
  releaseCodexAppServerLiveThread: liveThreadMocks.release,
}));

import {
  abandonCodexTransientToolTransactionV4,
  prepareCodexTransientToolTransactionV4,
  promoteCodexTransientToolTransactionV4,
} from "./transient-tool-transaction.js";

const bindingIdentity: CodexAppServerBindingIdentity = {
  kind: "session",
  agentId: "main",
  sessionId: "session-1",
  sessionKey: "global",
};

function sourceBinding(): CodexAppServerThreadLifecycleBinding {
  return {
    threadId: "thread-dirty",
    clientId: "client-1",
    cwd: "C:\\forge",
    rolloutPath: "C:\\rollouts\\dirty.jsonl",
    model: "gpt-5.6-sol",
    modelProvider: "openai",
    serviceTier: "default",
    historyCoveredThrough: "2026-09-15T20:00:00.000Z",
    dynamicToolsFingerprint: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    lifecycle: { action: "resumed" },
    liveThreadConfigFingerprint: "cfg-1",
  };
}

function clientStub() {
  const request = vi.fn(async (method: string) => {
    if (method === "thread/fork") {
      return {
        model: "gpt-5.6-sol",
        modelProvider: "openai",
        thread: {
          id: "thread-clean",
          path: "C:\\rollouts\\clean.jsonl",
          turns: [],
        },
      };
    }
    return {};
  });
  return {
    client: { request } as unknown as CodexAppServerClient,
    request,
  };
}

beforeEach(() => {
  liveThreadMocks.retain.mockReset().mockResolvedValue(true);
  liveThreadMocks.release.mockReset().mockResolvedValue(true);
});

describe("transient tools V4 clean fork", () => {
  it("forks exactly before the active tool-bearing turn and retains the clean fork warm", async () => {
    const { client, request } = clientStub();
    const transaction = await prepareCodexTransientToolTransactionV4({
      client,
      thread: sourceBinding(),
      turnId: "turn-tool",
      timeoutMs: 30_000,
    });

    expect(request).toHaveBeenCalledWith(
      "thread/fork",
      {
        threadId: "thread-dirty",
        beforeTurnId: "turn-tool",
        excludeTurns: true,
      },
      { timeoutMs: 30_000 },
    );
    expect(liveThreadMocks.retain).toHaveBeenCalledWith(
      client,
      "thread-clean",
      undefined,
      "cfg-1",
      "default",
    );
    expect(transaction).toMatchObject({
      sourceThreadId: "thread-dirty",
      sourceTurnId: "turn-tool",
      cleanThreadId: "thread-clean",
      cleanRolloutPath: "C:\\rollouts\\clean.jsonl",
      promoted: false,
      retained: true,
    });
  });

  it("injects only the clean user/final-answer pair then atomically replaces the dirty binding", async () => {
    const { client, request } = clientStub();
    const current = sourceBinding();
    const mutate = vi.fn(async () => true);
    const bindingStore = {
      read: vi.fn(async () => current),
      mutate,
    } as unknown as CodexAppServerBindingStore;
    const transaction = {
      sourceThreadId: "thread-dirty",
      sourceTurnId: "turn-tool",
      cleanThreadId: "thread-clean",
      cleanRolloutPath: "C:\\rollouts\\clean.jsonl",
      promoted: false,
      retained: true,
    };

    await expect(
      promoteCodexTransientToolTransactionV4({
        client,
        bindingStore,
        bindingIdentity,
        transaction,
        userText: "Use the web tool, then tell me the answer.",
        assistantText: "The clean final answer.",
        timeoutMs: 30_000,
      }),
    ).resolves.toBe(true);

    expect(request).toHaveBeenCalledWith(
      "thread/inject_items",
      {
        threadId: "thread-clean",
        items: [
          {
            type: "message",
            role: "user",
            content: [
              {
                type: "input_text",
                text: "Use the web tool, then tell me the answer.",
              },
            ],
          },
          {
            type: "message",
            role: "assistant",
            content: [{ type: "output_text", text: "The clean final answer." }],
          },
        ],
      },
      { timeoutMs: 30_000 },
    );
    expect(mutate).toHaveBeenCalledWith(bindingIdentity, {
      kind: "replace-thread",
      expectedThreadId: "thread-dirty",
      binding: expect.objectContaining({
        threadId: "thread-clean",
        rolloutPath: "C:\\rollouts\\clean.jsonl",
        clientId: "client-1",
        model: "gpt-5.6-sol",
        dynamicToolsFingerprint:
          "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      }),
    });
    expect(transaction.promoted).toBe(true);
  });

  it("refuses promotion when the durable owner changed before finalization", async () => {
    const { client, request } = clientStub();
    const bindingStore = {
      read: vi.fn(async () => ({ ...sourceBinding(), threadId: "thread-newer" })),
      mutate: vi.fn(),
    } as unknown as CodexAppServerBindingStore;
    const transaction = {
      sourceThreadId: "thread-dirty",
      sourceTurnId: "turn-tool",
      cleanThreadId: "thread-clean",
      promoted: false,
      retained: true,
    };

    await expect(
      promoteCodexTransientToolTransactionV4({
        client,
        bindingStore,
        bindingIdentity,
        transaction,
        userText: "question",
        assistantText: "answer",
        timeoutMs: 30_000,
      }),
    ).resolves.toBe(false);

    expect(request).not.toHaveBeenCalledWith(
      "thread/inject_items",
      expect.anything(),
      expect.anything(),
    );
    expect(bindingStore.mutate).not.toHaveBeenCalled();
    expect(transaction.promoted).toBe(false);
  });

  it("releases and archives an unpromoted clean fork", async () => {
    const { client, request } = clientStub();
    const transaction = {
      sourceThreadId: "thread-dirty",
      sourceTurnId: "turn-tool",
      cleanThreadId: "thread-clean",
      promoted: false,
      retained: true,
    };

    await abandonCodexTransientToolTransactionV4({
      client,
      transaction,
      timeoutMs: 5_000,
    });

    expect(liveThreadMocks.release).toHaveBeenCalledWith(client, "thread-clean");
    expect(request).toHaveBeenCalledWith(
      "thread/archive",
      { threadId: "thread-clean" },
      { timeoutMs: 5_000 },
    );
    expect(transaction.retained).toBe(false);
  });

  it("never archives an adopted clean fork during cleanup", async () => {
    const { client, request } = clientStub();
    const transaction = {
      sourceThreadId: "thread-dirty",
      sourceTurnId: "turn-tool",
      cleanThreadId: "thread-clean",
      promoted: true,
      retained: true,
    };

    await abandonCodexTransientToolTransactionV4({
      client,
      transaction,
      timeoutMs: 5_000,
    });

    expect(liveThreadMocks.release).not.toHaveBeenCalled();
    expect(request).not.toHaveBeenCalled();
  });
});
