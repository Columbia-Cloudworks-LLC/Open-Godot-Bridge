/**
 * Wire-protocol constants shared with the Godot plugin.
 *
 * Mirror of addons/ogb_bridge/core/protocol.gd — `test/protocol-sync.test.ts`
 * fails if the two drift apart.
 */

export const PROTOCOL_VERSION = 1;

export const DEFAULT_PORT = 6510;
/** The plugin binds the first free port in [DEFAULT_PORT, DEFAULT_PORT + PORT_RANGE). */
export const PORT_RANGE = 10;
export const BIND_ADDRESS = "127.0.0.1";

/** Discovery file, relative to the Godot project root (`res://`). */
export const SESSION_FILE_RELATIVE_PATH = ".godot/ogb_bridge/session.json";

/** Seconds a client has to complete `bridge.handshake` before being dropped. */
export const AUTH_TIMEOUT_SEC = 5.0;

export const MAX_INBOUND_BYTES = 4 * 1024 * 1024;
export const MAX_OUTBOUND_BYTES = 32 * 1024 * 1024;

/** WebSocket close code sent when a client never authenticates. */
export const CLOSE_AUTH_TIMEOUT = 4001;

export const Method = {
  HANDSHAKE: "bridge.handshake",
  PROJECT_STATUS: "project_status",
  PROJECT_INFO: "project_info",
  SCENE_INSPECT: "scene_inspect",
  SCENE_MUTATE: "scene_mutate",
} as const;

export type MethodName = (typeof Method)[keyof typeof Method];
