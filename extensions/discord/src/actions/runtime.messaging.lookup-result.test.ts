import { describe, expect, it } from "vitest";
import {
  compactDiscordLookupPayload,
  DISCORD_LOOKUP_MAX_BYTES,
  DISCORD_LOOKUP_TRUNCATION_NOTICE,
} from "./runtime.messaging.lookup-result.js";

function bytes(value: unknown): number {
  return new TextEncoder().encode(JSON.stringify(value, null, 2)).byteLength;
}

function noisyAuthor(id: string, username: string) {
  return {
    id,
    username,
    global_name: username,
    avatar: "a".repeat(64),
    discriminator: "0",
    public_flags: 0,
    flags: 0,
    banner: null,
    accent_color: null,
    avatar_decoration_data: {
      asset: "decorative-asset",
      sku_id: "123",
    },
    collectibles: {
      nameplate: {
        label: "decorative nameplate",
        palette: "cobalt",
      },
    },
    display_name_styles: {
      font_id: 14,
      effect_id: 8,
      colors: [1, 2, 3, 4],
    },
    vad_colors: null,
    banner_color: null,
    clan: {
      identity_guild_id: "guild",
      tag: "TAG",
    },
    primary_guild: {
      identity_guild_id: "guild",
    },
  };
}

function message(id: string, content: string, authorId = `user-${id}`) {
  return {
    type: 0,
    id,
    channel_id: "channel-1",
    content,
    timestamp: "2026-09-10T08:00:00.000000+00:00",
    edited_timestamp: null,
    author: noisyAuthor(authorId, `name-${authorId}`),
    mentions: [],
    mention_roles: [],
    attachments: [],
    embeds: [],
    components: [],
    flags: 0,
    pinned: false,
    mention_everyone: false,
    tts: false,
    timestampMs: 1,
    timestampUtc: "duplicate timestamp",
  };
}

describe("Discord lookup result projection", () => {
  it("strips decorative profile/API metadata while keeping message semantics", () => {
    const target = message("2", "Original replied-to message");

    const reply = {
      ...message("1", "Reply"),
      type: 19,
      mentions: [noisyAuthor("user-2", "target-user")],
      message_reference: {
        type: 0,
        channel_id: "channel-1",
        message_id: "2",
        guild_id: "guild-1",
      },
      referenced_message: target,
    };

    const raw = {
      ok: true,
      channelId: "channel-1",
      messages: [reply, target],
    };

    const compact = compactDiscordLookupPayload(raw);
    const messages = compact.messages as Array<Record<string, unknown>>;
    const first = messages[0];
    const author = first.author as Record<string, unknown>;
    const reference = first.message_reference as Record<string, unknown>;

    expect(first.content).toBe("Reply");
    expect(author.id).toBe("user-1");
    expect(author.username).toBe("name-user-1");
    expect(author.avatar).toBeUndefined();
    expect(author.collectibles).toBeUndefined();
    expect(reference.message_id).toBe("2");

    // Target is already present separately, so keep topology without duplicating
    // the whole target body in referenced_message.
    expect(first.referenced_message).toBeUndefined();

    expect(bytes(compact)).toBeLessThan(bytes(raw) * 0.5);
  });

  it("keeps a compact referenced message when it is outside the returned set", () => {
    const reply = {
      ...message("1", "Reply to something outside this lookup"),
      type: 19,
      message_reference: {
        channel_id: "channel-1",
        message_id: "outside",
        guild_id: "guild-1",
      },
      referenced_message: message("outside", "Important missing reply target body", "outside-user"),
    };

    const compact = compactDiscordLookupPayload({
      ok: true,
      channelId: "channel-1",
      messages: [reply],
    });

    const first = (compact.messages as Array<Record<string, unknown>>)[0];

    const referenced = first.referenced_message as Record<string, unknown>;

    const author = referenced.author as Record<string, unknown>;

    expect(referenced.content).toBe("Important missing reply target body");
    expect(author.id).toBe("outside-user");
    expect(author.avatar).toBeUndefined();
  });

  it("caps reduced chat lookups at 8 KB and tells the model not to retry", () => {
    const manyMessages = Array.from({ length: 30 }, (_, index) =>
      message(String(index), `${index}: ${"x".repeat(1200)}`),
    );

    const compact = compactDiscordLookupPayload({
      ok: true,
      channelId: "channel-1",
      messages: manyMessages,
    });

    expect(bytes(compact)).toBeLessThanOrEqual(DISCORD_LOOKUP_MAX_BYTES);
    expect(compact.truncated).toBe(true);
    expect(compact.notice).toBe(DISCORD_LOOKUP_TRUNCATION_NOTICE);

    const kept = compact.messages as Array<Record<string, unknown>>;

    expect(kept.length).toBeGreaterThan(0);
    expect(kept.length).toBeLessThan(manyMessages.length);
  });

  it("drops Discord search analytics metadata but keeps search messages", () => {
    const compact = compactDiscordLookupPayload({
      ok: true,
      results: {
        analytics_id: "provider-tracking-token",
        total_results: 1,
        messages: [[message("1", "Useful search result")]],
      },
    });

    const results = compact.results as Record<string, unknown>;

    expect(results.analytics_id).toBeUndefined();
    expect(results.total_results).toBe(1);
    expect(results.messages).toBeDefined();
  });
});
