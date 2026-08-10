/**
 * Preserve a stable Codex dynamic-tool schema across image and text turns.
 *
 * Native vision makes the image tool redundant for the current attachment, but
 * removing it only on image-bearing turns changes the registered tool schema and
 * can force an otherwise reusable native thread to rotate.
 */
export function filterToolsForVisionInputs<T extends { name?: string }>(
  tools: T[],
  _params: {
    modelHasVision: boolean;
    hasInboundImages: boolean;
  },
): T[] {
  return tools;
}
