export const DISCORD_LOOKUP_MAX_BYTES = 8 * 1024;

export const DISCORD_LOOKUP_TRUNCATION_NOTICE =
  "Result truncated at the 8 KB Discord lookup ceiling. Do not run another Discord/KB/history lookup this turn unless Ferefire or a staff member explicitly requested further investigation. Answer from the available context to conserve tokens.";

type UnknownRecord = Record<string, unknown>;

const DISCORD_DECORATIVE_KEYS = new Set([
  "accent_color",
  "analytics_id",
  "avatar",
  "avatar_decoration_data",
  "banner",
  "banner_color",
  "clan",
  "collectibles",
  "display_name_styles",
  "primary_guild",
  "proxy_icon_url",
  "proxy_url",
  "public_flags",
  "timestampMs",
  "timestampUtc",
  "vad_colors",
]);

const DROP_FALSE_KEYS = new Set(["bot", "mention_everyone", "pinned", "tts"]);

const DROP_ZERO_KEYS = new Set(["flags", "public_flags", "type"]);

function asRecord(value: unknown): UnknownRecord | undefined {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? (value as UnknownRecord)
    : undefined;
}

function isEmptyProjectedValue(value: unknown): boolean {
  return (
    value === undefined ||
    value === null ||
    value === "" ||
    (Array.isArray(value) && value.length === 0) ||
    (asRecord(value) !== undefined && Object.keys(value as UnknownRecord).length === 0)
  );
}

function looksLikeDiscordMessage(value: UnknownRecord): boolean {
  return (
    typeof value.id === "string" &&
    (typeof value.content === "string" ||
      typeof value.timestamp === "string" ||
      asRecord(value.author) !== undefined)
  );
}

function collectPrimaryMessageIds(value: unknown, out: Set<string>, key?: string): void {
  // Referenced messages are supporting context, not primary returned messages.
  if (key === "referenced_message") {
    return;
  }

  if (Array.isArray(value)) {
    for (const entry of value) {
      collectPrimaryMessageIds(entry, out, key);
    }
    return;
  }

  const record = asRecord(value);
  if (!record) {
    return;
  }

  if (looksLikeDiscordMessage(record)) {
    out.add(record.id as string);
  }

  for (const [childKey, childValue] of Object.entries(record)) {
    collectPrimaryMessageIds(childValue, out, childKey);
  }
}

function compactDiscordValue(
  value: unknown,
  primaryMessageIds: ReadonlySet<string>,
  key?: string,
  depth = 0,
): unknown {
  if (depth > 16 || value === undefined || value === null) {
    return undefined;
  }

  if (key && DISCORD_DECORATIVE_KEYS.has(key)) {
    return undefined;
  }

  if (key === "discriminator" && value === "0") {
    return undefined;
  }

  if (key && DROP_FALSE_KEYS.has(key) && value === false) {
    return undefined;
  }

  if (key && DROP_ZERO_KEYS.has(key) && value === 0) {
    return undefined;
  }

  if (Array.isArray(value)) {
    const projected = value
      .map((entry) => compactDiscordValue(entry, primaryMessageIds, undefined, depth + 1))
      .filter((entry) => !isEmptyProjectedValue(entry));

    return projected.length > 0 ? projected : undefined;
  }

  const record = asRecord(value);
  if (!record) {
    return value === "" ? undefined : value;
  }

  // If the replied-to message is already separately present in the lookup,
  // message_reference keeps the topology. Don't duplicate the full body again.
  if (key === "referenced_message") {
    const referencedId = typeof record.id === "string" ? record.id : undefined;

    if (referencedId && primaryMessageIds.has(referencedId)) {
      return undefined;
    }
  }

  const projected: UnknownRecord = {};

  for (const [childKey, childValue] of Object.entries(record)) {
    const compacted = compactDiscordValue(childValue, primaryMessageIds, childKey, depth + 1);

    if (!isEmptyProjectedValue(compacted)) {
      projected[childKey] = compacted;
    }
  }

  return Object.keys(projected).length > 0 ? projected : undefined;
}

function serializedBytes(value: unknown): number {
  return new TextEncoder().encode(JSON.stringify(value, null, 2)).byteLength;
}

function withTruncationMarker(payload: UnknownRecord, omittedItems: number): UnknownRecord {
  return {
    ...payload,
    truncated: true,
    ...(omittedItems > 0 ? { omittedItems } : {}),
    notice: DISCORD_LOOKUP_TRUNCATION_NOTICE,
  };
}

function capTopLevelArray(payload: UnknownRecord, key: "messages" | "pins"): UnknownRecord {
  const items = Array.isArray(payload[key]) ? payload[key] : undefined;

  if (!items || serializedBytes(payload) <= DISCORD_LOOKUP_MAX_BYTES) {
    return payload;
  }

  // Preserve complete messages. Never slice the JSON halfway through a message.
  for (let keep = items.length - 1; keep >= 0; keep -= 1) {
    const candidate = withTruncationMarker(
      {
        ...payload,
        [key]: items.slice(0, keep),
      },
      items.length - keep,
    );

    if (serializedBytes(candidate) <= DISCORD_LOOKUP_MAX_BYTES) {
      return candidate;
    }
  }

  return withTruncationMarker(
    {
      ok: payload.ok,
      [key]: [],
    },
    items.length,
  );
}

function capNestedSearchMessages(payload: UnknownRecord): UnknownRecord {
  const results = asRecord(payload.results);
  const groups = results && Array.isArray(results.messages) ? results.messages : undefined;

  if (!groups || serializedBytes(payload) <= DISCORD_LOOKUP_MAX_BYTES) {
    return payload;
  }

  // Discord search returns result groups. Keep complete groups until the cap.
  for (let keep = groups.length - 1; keep >= 0; keep -= 1) {
    const candidate = withTruncationMarker(
      {
        ...payload,
        results: {
          ...results,
          messages: groups.slice(0, keep),
        },
      },
      groups.length - keep,
    );

    if (serializedBytes(candidate) <= DISCORD_LOOKUP_MAX_BYTES) {
      return candidate;
    }
  }

  return withTruncationMarker(
    {
      ok: payload.ok,
      results: {
        messages: [],
      },
    },
    groups.length,
  );
}

function capSingleMessage(payload: UnknownRecord): UnknownRecord {
  if (serializedBytes(payload) <= DISCORD_LOOKUP_MAX_BYTES) {
    return payload;
  }

  const message = asRecord(payload.message);

  if (!message) {
    return withTruncationMarker({ ok: payload.ok }, 1);
  }

  const reduced = { ...message };

  // Only reached for a pathological single message over 8 KB after normal
  // projection. Preserve core identity/text/reply topology as long as possible.
  for (const heavyKey of [
    "components",
    "reactions",
    "embeds",
    "attachments",
    "referenced_message",
    "mentions",
    "sticker_items",
    "poll",
  ]) {
    delete reduced[heavyKey];

    const candidate = withTruncationMarker(
      {
        ...payload,
        message: reduced,
      },
      0,
    );

    if (serializedBytes(candidate) <= DISCORD_LOOKUP_MAX_BYTES) {
      return candidate;
    }
  }

  const content = typeof reduced.content === "string" ? reduced.content : undefined;

  if (content) {
    let low = 0;
    let high = content.length;

    while (low < high) {
      const mid = Math.ceil((low + high) / 2);

      const candidate = withTruncationMarker(
        {
          ...payload,
          message: {
            ...reduced,
            content: `${content.slice(0, mid)}?`,
          },
        },
        0,
      );

      if (serializedBytes(candidate) <= DISCORD_LOOKUP_MAX_BYTES) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }

    const candidate = withTruncationMarker(
      {
        ...payload,
        message: {
          ...reduced,
          content: `${content.slice(0, low)}?`,
        },
      },
      0,
    );

    if (serializedBytes(candidate) <= DISCORD_LOOKUP_MAX_BYTES) {
      return candidate;
    }
  }

  return withTruncationMarker(
    {
      ok: payload.ok,
      message: {
        ...(typeof message.id === "string" ? { id: message.id } : {}),
        ...(asRecord(message.author) ? { author: message.author } : {}),
        ...(asRecord(message.message_reference)
          ? { message_reference: message.message_reference }
          : {}),
      },
    },
    1,
  );
}

function capDiscordLookupPayload(payload: UnknownRecord): UnknownRecord {
  if (serializedBytes(payload) <= DISCORD_LOOKUP_MAX_BYTES) {
    return payload;
  }

  if (Array.isArray(payload.messages)) {
    return capTopLevelArray(payload, "messages");
  }

  if (Array.isArray(payload.pins)) {
    return capTopLevelArray(payload, "pins");
  }

  const results = asRecord(payload.results);

  if (results && Array.isArray(results.messages)) {
    return capNestedSearchMessages(payload);
  }

  if (asRecord(payload.message)) {
    return capSingleMessage(payload);
  }

  return withTruncationMarker({ ok: payload.ok }, 1);
}

export function compactDiscordLookupPayload(payload: UnknownRecord): UnknownRecord {
  const primaryMessageIds = new Set<string>();

  collectPrimaryMessageIds(payload, primaryMessageIds);

  const compacted = compactDiscordValue(payload, primaryMessageIds);

  const projected = asRecord(compacted) ?? { ok: true };

  return capDiscordLookupPayload(projected);
}
