import { describe, expect, it } from "vitest";
import {
  Method,
  paramsSchemas,
  sceneInspectParamsSchema,
  sceneMutateParamsSchema,
  projectInfoParamsSchema,
  vector2,
} from "../src/protocol/index.js";

describe("param schemas", () => {
  it("has a schema for every method", () => {
    expect(Object.keys(paramsSchemas).sort()).toEqual(Object.values(Method).sort());
  });

  it("applies defaults", () => {
    expect(sceneInspectParamsSchema.parse({})).toEqual({
      node_path: ".",
      max_depth: 32,
      include_properties: true,
      include_signals: true,
    });
    expect(projectInfoParamsSchema.parse({})).toEqual({ include_files: true, max_depth: 4 });
  });

  it("rejects unknown keys", () => {
    expect(sceneInspectParamsSchema.safeParse({ nodepath: "." }).success).toBe(false);
  });
});

describe("scene_mutate operations", () => {
  const parse = (operations: unknown[]) => sceneMutateParamsSchema.safeParse({ operations });

  it("accepts a mixed batch", () => {
    const result = parse([
      { op: "add_node", parent: ".", name: "Player", type: "CharacterBody2D", properties: { position: vector2(10, 20) } },
      { op: "add_node", parent: "Player", name: "Gun", scene: "res://gun.tscn" },
      { op: "set_property", path: "Player", property: "motion_mode", value: 1 },
      { op: "connect_signal", source: "Player/Area", signal: "body_entered", target: ".", method: "_on_hit" },
      { op: "remove_node", path: "Old" },
    ]);
    expect(result.success).toBe(true);
  });

  it("requires exactly one of type or scene for add_node", () => {
    expect(parse([{ op: "add_node", parent: ".", name: "A" }]).success).toBe(false);
    expect(parse([{ op: "add_node", parent: ".", name: "A", type: "Node", scene: "res://a.tscn" }]).success).toBe(
      false,
    );
  });

  it("rejects unknown ops, empty batches and non-res scene paths", () => {
    expect(parse([{ op: "rename_node", path: "A" }]).success).toBe(false);
    expect(parse([]).success).toBe(false);
    expect(parse([{ op: "add_node", parent: ".", name: "A", scene: "/tmp/a.tscn" }]).success).toBe(false);
  });

  it("accepts arbitrary JSON values (decoded type-aware by the plugin)", () => {
    expect(parse([{ op: "set_property", path: ".", property: "x", value: { nested: [1, "a", null] } }]).success).toBe(
      true,
    );
  });
});
