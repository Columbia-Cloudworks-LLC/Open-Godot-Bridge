@tool
extends RefCounted
## Wire-protocol constants shared with ogb-mcp (see PROTOCOL.md).
##
## Keep this file in sync with ogb-mcp/src/protocol/. The ogb-mcp test suite
## parses this file and fails if the constants drift apart.

const PROTOCOL_VERSION := 1
const PLUGIN_VERSION := "0.1.0"

const DEFAULT_PORT := 6510
## The server tries DEFAULT_PORT .. DEFAULT_PORT + PORT_RANGE - 1 and uses the
## first free one, so several editors can run side by side.
const PORT_RANGE := 10
const BIND_ADDRESS := "127.0.0.1"

## Discovery file written while the bridge is running. Lives in the project's
## .godot/ cache directory, which Godot already keeps out of version control.
const SESSION_FILE_PATH := "res://.godot/ogb_bridge/session.json"

## Seconds a client has to complete bridge.handshake before being dropped.
const AUTH_TIMEOUT_SEC := 5.0

## Limits applied to every WebSocket connection.
const MAX_INBOUND_BYTES := 4 * 1024 * 1024
const MAX_OUTBOUND_BYTES := 32 * 1024 * 1024

# --- Methods -----------------------------------------------------------------

const METHOD_HANDSHAKE := "bridge.handshake"
const METHOD_PROJECT_STATUS := "project_status"
const METHOD_PROJECT_INFO := "project_info"
const METHOD_SCENE_INSPECT := "scene_inspect"
const METHOD_SCENE_MUTATE := "scene_mutate"

# --- Error codes ---------------------------------------------------------------

# JSON-RPC 2.0 reserved codes.
const PARSE_ERROR := -32700
const INVALID_REQUEST := -32600
const METHOD_NOT_FOUND := -32601
const INVALID_PARAMS := -32602
const INTERNAL_ERROR := -32603

# Bridge-level codes.
const UNAUTHORIZED := -32000
const PROTOCOL_MISMATCH := -32001

# Editor/domain codes.
const NO_SCENE_OPEN := -32010
const NODE_NOT_FOUND := -32011
const INVALID_OPERATION := -32012
const UNSAVED_CHANGES := -32013

# --- WebSocket close codes -----------------------------------------------------

## Application-specific (4000-4999): client never authenticated in time.
const CLOSE_AUTH_TIMEOUT := 4001
