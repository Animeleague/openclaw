import { describe, expect, it } from "vitest";
import { buildCodexConversationTurnInput } from "./conversation-turn-input.js";

describe("codex conversation turn input cache stability", () => {
  it("dedupes singular and plural aliases for the same inbound image", () => {
    expect(
      buildCodexConversationTurnInput({
        prompt: "what is this?",
        event: {
          content: "what is this?",
          channel: "discord",
          isGroup: false,
          metadata: {
            mediaPaths: ["/tmp/photo.png"],
            mediaPath: "/tmp/photo.png",
            mediaTypes: ["image/png"],
            mediaType: "image/png",
          },
        },
      }),
    ).toEqual([
      { type: "text", text: "what is this?", text_elements: [] },
      { type: "localImage", path: "/tmp/photo.png" },
    ]);
  });

  it("preserves distinct inbound images while deduping aliases", () => {
    expect(
      buildCodexConversationTurnInput({
        prompt: "compare these",
        event: {
          content: "compare these",
          channel: "discord",
          isGroup: false,
          metadata: {
            mediaPaths: ["/tmp/first.png", "/tmp/second.png"],
            mediaPath: "/tmp/first.png",
            mediaTypes: ["image/png", "image/png"],
            mediaType: "image/png",
          },
        },
      }),
    ).toEqual([
      { type: "text", text: "compare these", text_elements: [] },
      { type: "localImage", path: "/tmp/first.png" },
      { type: "localImage", path: "/tmp/second.png" },
    ]);
  });

  it("keeps repeated plural mime types positionally aligned", () => {
    expect(
      buildCodexConversationTurnInput({
        prompt: "inspect attachments",
        event: {
          content: "inspect attachments",
          channel: "discord",
          isGroup: false,
          metadata: {
            mediaPaths: ["/tmp/photo", "/tmp/readme", "/tmp/notes"],
            mediaPath: "/tmp/photo",
            mediaTypes: ["image/png", "text/plain", "text/plain"],
            mediaType: "image/png",
          },
        },
      }),
    ).toEqual([
      { type: "text", text: "inspect attachments", text_elements: [] },
      { type: "localImage", path: "/tmp/photo" },
    ]);
  });
});
