/**
 * JSON encoding of Godot Variants.
 *
 * Mirror of addons/ogb_bridge/core/variant_codec.gd. JSON-native values pass
 * through unchanged; everything else is a tagged object `{ $type, value }`.
 * StringName is sent as a plain string. Integer-backed types (Vector2i, …)
 * use the same tuple shapes as their float counterparts.
 */

import * as z from "zod";

export const TYPE_KEY = "$type";

type Tuple<N extends number, Acc extends number[] = []> = Acc["length"] extends N ? Acc : Tuple<N, [...Acc, number]>;

export type Vec2Tuple = Tuple<2>;
export type Vec3Tuple = Tuple<3>;
export type Vec4Tuple = Tuple<4>;

/** Tagged types whose `value` is a fixed-length number tuple, with that length. */
export const NUMERIC_TUPLE_TYPES = {
  Vector2: 2,
  Vector2i: 2,
  Vector3: 3,
  Vector3i: 3,
  Vector4: 4,
  Vector4i: 4,
  /** [x, y, width, height] */
  Rect2: 4,
  Rect2i: 4,
  /** [r, g, b, a] in 0..1. On input, [r, g, b] and "#rrggbb[aa]" strings are also accepted. */
  Color: 4,
  /** [x, y, z, w] */
  Quaternion: 4,
  /** [normal.x, normal.y, normal.z, d] */
  Plane: 4,
  /** [position.xyz, size.xyz] */
  AABB: 6,
  /** [x.x, x.y, y.x, y.y, origin.x, origin.y] */
  Transform2D: 6,
  /** Column-major: [x.xyz, y.xyz, z.xyz] */
  Basis: 9,
  /** Basis (column-major) followed by origin.xyz. */
  Transform3D: 12,
  /** Column-major 4x4. */
  Projection: 16,
} as const;

export type NumericTupleTypeName = keyof typeof NUMERIC_TUPLE_TYPES;

export type NumericTupleVariant = {
  [K in NumericTupleTypeName]: { $type: K; value: Tuple<(typeof NUMERIC_TUPLE_TYPES)[K]> };
}[NumericTupleTypeName];

export type PackedVectorVariant =
  | { $type: "PackedVector2Array"; value: Vec2Tuple[] }
  | { $type: "PackedVector3Array"; value: Vec3Tuple[] }
  | { $type: "PackedVector4Array"; value: Vec4Tuple[] }
  | { $type: "PackedColorArray"; value: Vec4Tuple[] };

/** A resource. Only resources with a standalone `res://` path can be sent back to Godot. */
export interface ResourceVariant {
  $type: "Resource";
  class: string;
  path?: string;
}

/** Output only: a node reference found inside a property value. */
export interface NodeVariant {
  $type: "Node";
  class: string;
  name: string;
}

/** Output only: any other object. */
export interface ObjectVariant {
  $type: "Object";
  class: string;
}

/** Output only: values that cannot cross the wire (Callable, Signal, RID). */
export interface OpaqueVariant {
  $type: "Callable" | "Signal" | "RID";
  repr: string;
}

export type TaggedVariant =
  | NumericTupleVariant
  | PackedVectorVariant
  | { $type: "NodePath"; value: string }
  | { $type: "float"; value: "nan" | "inf" | "-inf" }
  | { $type: "PackedByteArray"; value: string /* base64 */ }
  | ResourceVariant
  | NodeVariant
  | ObjectVariant
  | OpaqueVariant;

/** Any value that crosses the wire in a Godot-typed position. */
export type GodotValue =
  | null
  | boolean
  | number
  | string
  | GodotValue[]
  | TaggedVariant
  | { [key: string]: GodotValue };

/**
 * Schema for Godot values sent *to* the plugin. Validation is deliberately
 * loose (any JSON): the plugin decodes tagged values with knowledge of the
 * target property's type and reports precise errors.
 */
export const godotValueSchema = z
  .json()
  .describe(
    'A Godot value. JSON primitives, arrays and objects map directly; other types use tagged objects such as {"$type":"Vector2","value":[10,20]}, {"$type":"Color","value":[1,0,0,1]} or {"$type":"Resource","path":"res://icon.svg"}.',
  );

export function isTagged(value: unknown): value is TaggedVariant {
  return typeof value === "object" && value !== null && !Array.isArray(value) && typeof (value as Record<string, unknown>)[TYPE_KEY] === "string";
}

// --- Constructors for the common cases ---------------------------------------

export const vector2 = (x: number, y: number) => ({ $type: "Vector2", value: [x, y] }) as const satisfies TaggedVariant;
export const vector3 = (x: number, y: number, z: number) =>
  ({ $type: "Vector3", value: [x, y, z] }) as const satisfies TaggedVariant;
export const color = (r: number, g: number, b: number, a = 1) =>
  ({ $type: "Color", value: [r, g, b, a] }) as const satisfies TaggedVariant;
export const nodePath = (path: string) => ({ $type: "NodePath", value: path }) as const satisfies TaggedVariant;
export const resource = (path: string) => ({ $type: "Resource", class: "Resource", path }) as const satisfies TaggedVariant;
