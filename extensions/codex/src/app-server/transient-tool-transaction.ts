import { embeddedAgentLog } from "openclaw/plugin-sdk/agent-harness-runtime";
import {
  releaseCodexAppServerLiveThread,
  retainCodexAppServerLiveThread,
} from "./client-runtime.js";
import type { CodexAppServerClient } from "./client.js";
import { assertCodexThreadForkResponse } from "./protocol-validators.js";
import type {
  CodexAppServerBindingIdentity,
  CodexAppServerBindingStore,
  CodexAppServerThreadBinding,
} from "./session-binding.js";
import type { CodexAppServerThreadLifecycleBinding } from "./thread-lifecycle.js";

export const FORGE_TRANSIENT_TOOLS_V4_MARKER = "FORGE_CODEX_TRANSIENT_TOOLS_CLEAN_FORK_V4";

export type CodexTransientToolTransactionV4 = {
  sourceThreadId: string;
  sourceTurnId: string;
  cleanThreadId: string;
  cleanRolloutPath?: string;
  promoted: boolean;
  retained: boolean;
};

async function archiveThreadBestEffort(
  client: CodexAppServerClient,
  threadId: string,
  timeoutMs: number,
): Promise<void> {
  await client
    .request("thread/archive", { threadId }, { timeoutMs })
    .catch(() => undefined);
}

export async function prepareCodexTransientToolTransactionV4(params: {
  client: CodexAppServerClient;
  thread: CodexAppServerThreadLifecycleBinding;
  turnId: string;
  timeoutMs: number;
  signal?: AbortSignal;
}): Promise<CodexTransientToolTransactionV4> {
  if (params.thread.connectionScope === "supervision") {
    throw new Error("Transient tool clean-fork replacement is unavailable for supervised threads");
  }

  // FORGE_CODEX_TRANSIENT_TOOLS_CLEAN_FORK_V4
  // Fork strictly BEFORE the active tool-bearing turn. The original thread may
  // accumulate arbitrary tool traffic; this fork remains a clean copy of the
  // exact warm prefix that existed when the user turn began.
  const raw = await params.client.request(
    "thread/fork",
    {
      threadId: params.thread.threadId,
      beforeTurnId: params.turnId,
      excludeTurns: true,
    },
    {
      timeoutMs: params.timeoutMs,
      ...(params.signal ? { signal: params.signal } : {}),
    },
  );
  const response = assertCodexThreadForkResponse(raw);
  const cleanThreadId = response.thread.id.trim();
  if (!cleanThreadId || cleanThreadId === params.thread.threadId) {
    throw new Error("Codex transient tool fork returned an invalid replacement thread id");
  }

  const cleanRolloutPath = response.thread.path?.trim() || undefined;
  const retained = await retainCodexAppServerLiveThread(
    params.client,
    cleanThreadId,
    undefined,
    params.thread.liveThreadConfigFingerprint,
    params.thread.serviceTier,
  );
  if (!retained) {
    await archiveThreadBestEffort(params.client, cleanThreadId, params.timeoutMs);
    throw new Error("Codex transient tool clean fork could not be retained warm");
  }

  embeddedAgentLog.debug("codex transient tools v4 prepared clean pre-turn fork", {
    sourceThreadId: params.thread.threadId,
    sourceTurnId: params.turnId,
    cleanThreadId,
  });

  return {
    sourceThreadId: params.thread.threadId,
    sourceTurnId: params.turnId,
    cleanThreadId,
    ...(cleanRolloutPath ? { cleanRolloutPath } : {}),
    promoted: false,
    retained: true,
  };
}

function replacementBinding(
  current: CodexAppServerThreadBinding,
  transaction: CodexTransientToolTransactionV4,
): CodexAppServerThreadBinding {
  const { rolloutPath: _oldRolloutPath, ...rest } = current;
  return {
    ...rest,
    threadId: transaction.cleanThreadId,
    ...(transaction.cleanRolloutPath ? { rolloutPath: transaction.cleanRolloutPath } : {}),
    historyCoveredThrough: new Date().toISOString(),
  };
}

export async function promoteCodexTransientToolTransactionV4(params: {
  client: CodexAppServerClient;
  bindingStore: CodexAppServerBindingStore;
  bindingIdentity: CodexAppServerBindingIdentity;
  transaction: CodexTransientToolTransactionV4;
  userText: string;
  assistantText: string;
  timeoutMs: number;
  signal?: AbortSignal;
}): Promise<boolean> {
  const userText = params.userText.trim();
  const assistantText = params.assistantText.trim();
  if (!userText || !assistantText) {
    return false;
  }

  const current = await params.bindingStore.read(params.bindingIdentity);
  if (
    !current ||
    current.threadId !== params.transaction.sourceThreadId ||
    current.connectionScope === "supervision"
  ) {
    return false;
  }

  // Materialize only the clean conversational exchange on the pre-turn fork.
  // Tool calls, tool outputs, intermediate reasoning and native tool items remain
  // solely on the dirty source thread and never enter future model history.
  await params.client.request(
    "thread/inject_items",
    {
      threadId: params.transaction.cleanThreadId,
      items: [
        {
          type: "message",
          role: "user",
          content: [{ type: "input_text", text: userText }],
        },
        {
          type: "message",
          role: "assistant",
          content: [{ type: "output_text", text: assistantText }],
        },
      ],
    },
    {
      timeoutMs: params.timeoutMs,
      ...(params.signal ? { signal: params.signal } : {}),
    },
  );

  const replaced = await params.bindingStore.mutate(params.bindingIdentity, {
    kind: "replace-thread",
    expectedThreadId: params.transaction.sourceThreadId,
    binding: replacementBinding(current, params.transaction),
  });
  if (!replaced) {
    return false;
  }

  params.transaction.promoted = true;
  embeddedAgentLog.info("codex transient tools v4 promoted clean fork after tool turn", {
    sourceThreadId: params.transaction.sourceThreadId,
    sourceTurnId: params.transaction.sourceTurnId,
    cleanThreadId: params.transaction.cleanThreadId,
  });
  return true;
}

export async function abandonCodexTransientToolTransactionV4(params: {
  client: CodexAppServerClient;
  transaction: CodexTransientToolTransactionV4 | undefined;
  timeoutMs: number;
}): Promise<void> {
  const transaction = params.transaction;
  if (!transaction || transaction.promoted) {
    return;
  }

  if (transaction.retained) {
    await releaseCodexAppServerLiveThread(params.client, transaction.cleanThreadId).catch(
      () => false,
    );
    transaction.retained = false;
  }
  await archiveThreadBestEffort(params.client, transaction.cleanThreadId, params.timeoutMs);
}
