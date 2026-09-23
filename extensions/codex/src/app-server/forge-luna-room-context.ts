export const FORGE_LUNA_LATEST10_BEGIN_V120 = "[FORGE_LUNA_LATEST10_BEGIN_V120]";
export const FORGE_LUNA_LATEST10_END_V120 = "[FORGE_LUNA_LATEST10_END_V120]";

export type ForgeLunaRoomContextTurn = {
  cleanPromptText: string;
  roomContextText: string;
  dirtyPromptText: string;
};

/**
 * FORGE_LUNA_ROOM_CONTEXT_TRANSACTION_V120
 *
 * The Discord monitor appends Luna's rolling latest-10 block at the very end
 * of the current prompt. Treat only that exact terminal sentinel block as
 * transactional room context. Earlier marker-like text remains ordinary
 * untrusted user/context text and cannot claim the transaction boundary.
 */
export function extractForgeLunaRoomContextTurn(params: {
  messageProvider?: string;
  promptText: string;
}): ForgeLunaRoomContextTurn | undefined {
  if (params.messageProvider !== "discord") {
    return undefined;
  }

  const source = params.promptText;
  const endMarker = FORGE_LUNA_LATEST10_END_V120;
  const beginMarker = FORGE_LUNA_LATEST10_BEGIN_V120;

  const trimmedEnd = source.trimEnd();
  if (!trimmedEnd.endsWith(endMarker)) {
    return undefined;
  }

  const endIndex = trimmedEnd.length - endMarker.length;
  if (endIndex <= 0 || trimmedEnd[endIndex - 1] !== "\n") {
    return undefined;
  }

  const beginNeedle = `\n${beginMarker}\n`;
  const beginNeedleIndex = trimmedEnd.lastIndexOf(beginNeedle, endIndex - 1);
  const beginsAtStart = trimmedEnd.startsWith(`${beginMarker}\n`);
  const beginIndex = beginNeedleIndex >= 0 ? beginNeedleIndex + 1 : beginsAtStart ? 0 : -1;
  if (beginIndex < 0) {
    return undefined;
  }

  const roomStart = beginIndex + beginMarker.length + 1;
  const roomEnd = endIndex - 1;
  if (roomEnd < roomStart) {
    return undefined;
  }

  const cleanPromptText = trimmedEnd.slice(0, beginIndex).trimEnd();
  const roomContextText = trimmedEnd.slice(roomStart, roomEnd).trim();

  if (!cleanPromptText || !roomContextText) {
    return undefined;
  }

  return {
    cleanPromptText,
    roomContextText,
    dirtyPromptText: [
      roomContextText,
      "",
      "Current user request:",
      cleanPromptText,
    ].join("\n"),
  };
}
