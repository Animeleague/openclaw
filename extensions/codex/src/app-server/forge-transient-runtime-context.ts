import { Buffer } from "node:buffer";
import type { CodexTurnStartParams } from "./protocol.js";

export type ForgeTransientRuntimeCarrier = {
  promptText: string;
  transientText: string;
};

type CodexAdditionalContext = NonNullable<CodexTurnStartParams["additionalContext"]>;

const FORGE_ADDITIONAL_CONTEXT_CHUNK_MAX_UTF8_BYTES = 900;

/**
 * FORGE_CODEX_TRANSIENT_RUNTIME_CONTEXT_V6
 *
 * Discord monitor context is assembled ahead of the durable user prompt by
 * before_prompt_build. Strip that transient prefix back out before turn/start
 * so Codex never persists it as native user history.
 *
 * The extracted block is delivered separately through turn/start.additionalContext
 * as untrusted current-turn reference data. It must not be promoted into native
 * user history or collaboration/developer instructions.
 */
export function extractForgeTransientRuntimeContext(params: {
  messageProvider?: string;
  promptText: string;
}): ForgeTransientRuntimeCarrier | undefined {
  if (params.messageProvider !== "discord") {
    return undefined;
  }

  const source = params.promptText;
  const marker = "\n[meta ";

  let durableStart = source.lastIndexOf(marker);
  if (durableStart >= 0) {
    durableStart += 1;
  } else if (source.startsWith("[meta ")) {
    durableStart = 0;
  } else {
    return undefined;
  }

  let transientText = source.slice(0, durableStart).trim();
  const durablePromptText = source.slice(durableStart).trimStart();

  transientText = transientText.replace(/\n*Current user request:\s*$/iu, "").trim();

  if (!transientText || !durablePromptText) {
    return undefined;
  }

  return {
    promptText: durablePromptText,
    transientText,
  };
}

export function buildForgeTransientAdditionalContext(
  transientText: string | undefined,
): CodexAdditionalContext | undefined {
  const value = transientText?.trim();
  if (!value) {
    return undefined;
  }

  const chunks = splitUtf8ByByteBudget(value, FORGE_ADDITIONAL_CONTEXT_CHUNK_MAX_UTF8_BYTES);
  const context: CodexAdditionalContext = {};
  for (const [index, chunk] of chunks.entries()) {
    context[`forge_current_turn_context_${String(index).padStart(4, "0")}`] = {
      kind: "untrusted",
      value: chunk,
    };
  }
  return context;
}

function splitUtf8ByByteBudget(value: string, maxBytes: number): string[] {
  const chunks: string[] = [];
  let chunk = "";
  let chunkBytes = 0;

  for (const symbol of value) {
    const symbolBytes = Buffer.byteLength(symbol, "utf8");
    if (chunk && chunkBytes + symbolBytes > maxBytes) {
      chunks.push(chunk);
      chunk = "";
      chunkBytes = 0;
    }
    chunk += symbol;
    chunkBytes += symbolBytes;
  }

  if (chunk) {
    chunks.push(chunk);
  }
  return chunks;
}
