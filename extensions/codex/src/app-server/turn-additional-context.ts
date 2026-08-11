import { Buffer } from "node:buffer";
import type { CodexTurnStartParams } from "./protocol.js";

export type CodexAdditionalContext = NonNullable<CodexTurnStartParams["additionalContext"]>;

// Codex bounds each additionalContext value by token count. Keep chunks
// conservatively small by UTF-8 bytes so user-editable reference context is
// not silently truncated before it reaches the model.
const CODEX_ADDITIONAL_CONTEXT_CHUNK_MAX_UTF8_BYTES = 900;

export function buildCodexUntrustedAdditionalContextChunks(params: {
  keyPrefix: string;
  value?: string;
}): CodexAdditionalContext | undefined {
  const value = params.value?.trim();
  if (!value) {
    return undefined;
  }
  const chunks = splitUtf8ByByteBudget(value, CODEX_ADDITIONAL_CONTEXT_CHUNK_MAX_UTF8_BYTES);
  const context: CodexAdditionalContext = {};
  for (const [index, chunk] of chunks.entries()) {
    const key = `${params.keyPrefix}_${String(index).padStart(4, "0")}`;
    context[key] = { kind: "untrusted", value: chunk };
  }
  return context;
}

export function mergeCodexAdditionalContext(
  ...contexts: Array<CodexAdditionalContext | undefined>
): CodexAdditionalContext | undefined {
  const merged: CodexAdditionalContext = {};
  for (const context of contexts) {
    if (context) {
      Object.assign(merged, context);
    }
  }
  return Object.keys(merged).length > 0 ? merged : undefined;
}

export function detachCodexRuntimeContext(params: {
  promptText: string;
  runtimeContext?: string;
}): { promptText: string; runtimeContext?: string } {
  const runtimeContext = params.runtimeContext?.trim();
  if (!runtimeContext) {
    return { promptText: params.promptText };
  }
  const prefix = `${runtimeContext}\n\n`;
  if (!params.promptText.startsWith(prefix)) {
    return { promptText: params.promptText };
  }
  return {
    promptText: params.promptText.slice(prefix.length),
    runtimeContext,
  };
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
