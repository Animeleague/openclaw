import type { EmbeddedRunAttemptParams } from "openclaw/plugin-sdk/agent-harness-runtime";
import { describe, expect, it } from "vitest";
import { resolveCodexDynamicToolDirectNames } from "./run-attempt-tools.js";

const baseParams = {} as EmbeddedRunAttemptParams;

describe("resolveCodexDynamicToolDirectNames hot tools", () => {
  it("keeps routine messaging and web tools directly callable", () => {
    expect(resolveCodexDynamicToolDirectNames(baseParams)).toEqual([
      "message",
      "web_fetch",
      "web_search",
    ]);
  });

  it("does not duplicate message for message-tool-only source replies", () => {
    const params = {
      ...baseParams,
      sourceReplyDeliveryMode: "message_tool_only",
    } as EmbeddedRunAttemptParams;

    expect(resolveCodexDynamicToolDirectNames(params)).toEqual([
      "message",
      "web_fetch",
      "web_search",
    ]);
  });
});
