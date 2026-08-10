// Codex tests cover run attempt.vision tools plugin behavior.
import { describe, expect, it } from "vitest";
import { filterToolsForVisionInputs } from "./vision-tools.js";

describe("Codex dynamic tool filtering", () => {
  it("keeps the image tool when the model already has inbound vision input", () => {
    const tools = [{ name: "image" }, { name: "read" }, { name: "write" }];
    const filtered = filterToolsForVisionInputs(tools, {
      modelHasVision: true,
      hasInboundImages: true,
    });

    expect(filtered).toBe(tools);
    expect(filtered.map((tool) => tool.name)).toEqual(["image", "read", "write"]);
  });

  it("keeps the same schema for non-vision and non-image turns", () => {
    const tools = [{ name: "image" }, { name: "read" }];

    expect(
      filterToolsForVisionInputs(tools, {
        modelHasVision: false,
        hasInboundImages: true,
      }),
    ).toBe(tools);
    expect(
      filterToolsForVisionInputs(tools, {
        modelHasVision: true,
        hasInboundImages: false,
      }),
    ).toBe(tools);
  });
});
