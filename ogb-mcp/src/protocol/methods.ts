/**
 * Parameter schemas and result types for every bridge method.
 *
 * The zod schemas are the single source of truth for parameters: ogb-mcp uses
 * them both to validate outgoing requests and as MCP tool input schemas, so
 * the `.describe()` texts are written for the agent reading the tool list.
 *
 * Node paths are always relative to the edited scene's root node, using
 * Godot NodePath syntax: "." is the root, "Player/Sprite2D" a descendant.
 */

import * as z from "zod";
import { Method } from "./constants.js";
import { godotValueSchema, type GodotValue } from "./variant.js";

const nodePathSchema = z
  .string()
  .min(1)
  .describe('Node path relative to the scene root. "." is the root itself, e.g. "Player/Sprite2D".');

const resPathSchema = z.string().regex(/^res:\/\//, 'must start with "res://"');

// --- bridge.handshake ----------------------------------------------------------

export const handshakeParamsSchema = z.strictObject({
  protocol_version: z.int(),
  token: z.string().min(1),
  client: z.strictObject({
    name: z.string(),
    version: z.string(),
  }),
});
export type HandshakeParams = z.infer<typeof handshakeParamsSchema>;

export interface GodotVersion {
  /** e.g. "4.3-stable (official)" */
  string: string;
  major: number;
  minor: number;
  patch: number;
  status: string;
}

export interface ProjectIdentity {
  name: string;
  /** Absolute filesystem path of the project root (`res://`), no trailing slash. */
  path: string;
}

export interface HandshakeResult {
  protocol_version: number;
  plugin_version: string;
  godot: GodotVersion;
  project: ProjectIdentity;
  /** Methods this plugin build implements, sorted. */
  methods: string[];
}

// --- project_status ------------------------------------------------------------

export const projectStatusParamsSchema = z.strictObject({});
export type ProjectStatusParams = z.infer<typeof projectStatusParamsSchema>;

export interface ProjectStatusResult {
  plugin_version: string;
  godot: GodotVersion;
  project: ProjectIdentity;
  /** The scene in the active editor tab, or null when no scene is open. */
  current_scene: {
    /** null for a new scene that has never been saved. */
    path: string | null;
    root_name: string;
    root_type: string;
  } | null;
  /** res:// paths of all scenes open in editor tabs. */
  open_scenes: string[];
  is_playing: boolean;
  connected_clients: number;
}

// --- project_info --------------------------------------------------------------

export const projectInfoParamsSchema = z.strictObject({
  include_files: z.boolean().default(true).describe("Include the res:// directory tree."),
  max_depth: z
    .int()
    .min(1)
    .max(16)
    .default(4)
    .describe("Maximum directory depth of the file tree; deeper directories are marked truncated."),
});
export type ProjectInfoParams = z.input<typeof projectInfoParamsSchema>;

export interface AutoloadInfo {
  name: string;
  /** res:// path of the script or scene. */
  path: string;
  /** True when registered as a global singleton (the "*" prefix in project.godot). */
  singleton: boolean;
}

export interface InputEventInfo {
  /** Event class, e.g. "InputEventKey". */
  type: string;
  /** Human-readable form from InputEvent.as_text(), e.g. "W" or "Joypad Button 0". */
  text: string;
}

export interface InputActionInfo {
  name: string;
  deadzone: number;
  events: InputEventInfo[];
}

export interface FileTreeNode {
  name: string;
  /** res:// path. */
  path: string;
  kind: "dir" | "file";
  children?: FileTreeNode[];
  /** Set on directories whose contents were cut off by max_depth. */
  truncated?: boolean;
}

export interface ProjectInfoResult {
  name: string;
  main_scene: string | null;
  autoloads: AutoloadInfo[];
  /** Project-defined input actions (built-in ui_* actions are omitted). */
  input_actions: InputActionInfo[];
  /** Present when include_files is true. */
  files?: FileTreeNode;
}

// --- scene_inspect -------------------------------------------------------------

export const sceneInspectParamsSchema = z.strictObject({
  node_path: nodePathSchema.default(".").describe("Subtree to inspect; defaults to the whole scene."),
  max_depth: z
    .int()
    .min(0)
    .max(64)
    .default(32)
    .describe("Levels of children to include below node_path. 0 returns only that node."),
  include_properties: z
    .boolean()
    .default(true)
    .describe("Include script-exported properties and properties that differ from their class default."),
  include_signals: z.boolean().default(true).describe("Include persistent signal connections."),
});
export type SceneInspectParams = z.input<typeof sceneInspectParamsSchema>;

export interface SignalConnectionInfo {
  signal: string;
  /** Target node path, relative to the scene root. */
  target: string;
  method: string;
  /** Godot Object.ConnectFlags bitmask. */
  flags: number;
}

export interface SceneNodeInfo {
  name: string;
  /** Engine class, e.g. "CharacterBody2D". */
  type: string;
  /** Path relative to the scene root ("." for the root). */
  path: string;
  /** res:// path of the attached script, if any. */
  script?: string;
  /** For instanced sub-scenes: the res:// path of the instanced scene. */
  scene?: string;
  properties?: Record<string, GodotValue>;
  signals?: SignalConnectionInfo[];
  children: SceneNodeInfo[];
  /** Number of children left out because of max_depth. */
  children_omitted?: number;
}

export interface SceneInspectResult {
  /** null for a scene that has never been saved. */
  scene_path: string | null;
  root: SceneNodeInfo;
}

// --- scene_mutate --------------------------------------------------------------

const propertiesSchema = z
  .record(z.string(), godotValueSchema)
  .describe("Property name to value, applied in order.");

export const addNodeOpSchema = z
  .strictObject({
    op: z.literal("add_node"),
    parent: nodePathSchema.describe("Path of the parent node."),
    name: z.string().min(1).describe("Name of the new node. Must be unique among its siblings."),
    type: z.string().min(1).optional().describe('Engine or script class to instantiate, e.g. "Sprite2D".'),
    scene: resPathSchema.optional().describe("res:// path of a PackedScene to instance instead of a class."),
    properties: propertiesSchema.optional(),
    index: z.int().min(0).optional().describe("Position among the parent's children; appended when omitted."),
  })
  .refine((op) => (op.type === undefined) !== (op.scene === undefined), {
    message: 'add_node needs exactly one of "type" or "scene"',
  });

export const removeNodeOpSchema = z.strictObject({
  op: z.literal("remove_node"),
  path: nodePathSchema.describe("Node to remove, together with its children. Cannot be the scene root."),
});

export const setPropertyOpSchema = z.strictObject({
  op: z.literal("set_property"),
  path: nodePathSchema,
  property: z.string().min(1).describe('Property name, e.g. "position" or "modulate".'),
  value: godotValueSchema,
});

export const connectSignalOpSchema = z.strictObject({
  op: z.literal("connect_signal"),
  source: nodePathSchema.describe("Node that emits the signal."),
  signal: z.string().min(1),
  target: nodePathSchema.describe("Node that receives the signal."),
  method: z.string().min(1).describe("Method on the target. Should exist in the target's script."),
  flags: z
    .int()
    .min(0)
    .optional()
    .describe("Object.ConnectFlags; CONNECT_PERSIST (2) is always added so the connection is saved."),
});

export const sceneOperationSchema = z.discriminatedUnion("op", [
  addNodeOpSchema,
  removeNodeOpSchema,
  setPropertyOpSchema,
  connectSignalOpSchema,
]);
export type SceneOperation = z.infer<typeof sceneOperationSchema>;

export const sceneMutateParamsSchema = z.strictObject({
  operations: z
    .array(sceneOperationSchema)
    .min(1)
    .max(256)
    .describe(
      "Operations applied in order as a single undoable editor action. Later operations may refer to nodes added by earlier ones. If any operation fails, none are applied.",
    ),
  action_name: z.string().min(1).max(120).optional().describe("Label shown in Godot's undo history."),
});
export type SceneMutateParams = z.input<typeof sceneMutateParamsSchema>;

export interface SceneOperationResult {
  index: number;
  op: SceneOperation["op"];
  /** Path of the affected node after the operation (for add_node, the new node). */
  path: string;
}

export interface SceneMutateResult {
  /** Undo-history label of the committed action. */
  action: string;
  applied: number;
  results: SceneOperationResult[];
}

/** `error.data` of a failed scene_mutate: which operation was rejected. */
export interface SceneMutateErrorData {
  operation_index: number;
  [key: string]: unknown;
}

// --- Method map ------------------------------------------------------------------

export const paramsSchemas = {
  [Method.HANDSHAKE]: handshakeParamsSchema,
  [Method.PROJECT_STATUS]: projectStatusParamsSchema,
  [Method.PROJECT_INFO]: projectInfoParamsSchema,
  [Method.SCENE_INSPECT]: sceneInspectParamsSchema,
  [Method.SCENE_MUTATE]: sceneMutateParamsSchema,
} as const;

/** Compile-time map of method name to its params and result types. */
export interface BridgeMethods {
  [Method.HANDSHAKE]: { params: HandshakeParams; result: HandshakeResult };
  [Method.PROJECT_STATUS]: { params: ProjectStatusParams; result: ProjectStatusResult };
  [Method.PROJECT_INFO]: { params: ProjectInfoParams; result: ProjectInfoResult };
  [Method.SCENE_INSPECT]: { params: SceneInspectParams; result: SceneInspectResult };
  [Method.SCENE_MUTATE]: { params: SceneMutateParams; result: SceneMutateResult };
}

export type BridgeMethodName = keyof BridgeMethods;
export type ParamsOf<M extends BridgeMethodName> = BridgeMethods[M]["params"];
export type ResultOf<M extends BridgeMethodName> = BridgeMethods[M]["result"];
