# OGB Wire Protocol (v1)

How `ogb-mcp` talks to the `ogb_bridge` Godot editor plugin. Normative
sources: [`protocol.gd`](addons/ogb_bridge/core/protocol.gd) and
[`ogb-mcp/src/protocol/`](ogb-mcp/src/protocol/). A test keeps their constants in sync.

## Transport

- WebSocket, **text frames only** (a binary frame closes the connection with code 1003).
- One JSON-RPC 2.0 message or batch per frame.
- The plugin binds **127.0.0.1** only, on the first free port in `6510–6519`.
- Max inbound frame size is 4 MiB. Max outbound frame size is 32 MiB.

## Discovery

While the bridge runs, the plugin writes `<project>/.godot/ogb_bridge/session.json`
(mode `0600` on Unix) and deletes it on shutdown:

```json
{
  "protocol_version": 1,
  "plugin_version": "0.1.0",
  "host": "127.0.0.1",
  "port": 6510,
  "token": "<64 hex chars, regenerated each editor session>",
  "pid": 12345,
  "godot_version": "4.3-stable (official)",
  "started_at": "2026-11-16T12:00:00Z"
}
```

`.godot/` is Godot's cache directory and is already gitignored by Godot projects.

## Authentication

Browsers can open WebSockets to localhost from any web page, so the socket is
not trusted on its own. The first call on a connection must be `bridge.handshake`
with the token from the session file. Until it succeeds, every other method
returns `UNAUTHORIZED`. A connection that hasn't authenticated after 5 s is
closed with code `4001`.

```json
→ {"jsonrpc":"2.0","id":1,"method":"bridge.handshake",
   "params":{"protocol_version":1,"token":"…","client":{"name":"ogb-mcp","version":"0.1.0"}}}
← {"jsonrpc":"2.0","id":1,"result":{"protocol_version":1,"plugin_version":"0.1.0",
   "godot":{"string":"4.3-stable (official)","major":4,"minor":3,"patch":0,"status":"stable"},
   "project":{"name":"My Game","path":"/home/me/my-game"},
   "methods":["bridge.handshake","project_status", …]}}
```

A different `protocol_version` fails with `PROTOCOL_MISMATCH`, and `error.data`
holds `{client, server}`.

## Messages

Standard JSON-RPC 2.0 rules apply:

- `params` must be an object (named parameters) or omitted.
- Requests without an `id` are notifications and get no reply.
- Batches (arrays) are supported. The plugin processes their entries in order.
- Godot's JSON parser reads all numbers as floats. The plugin converts integral
  ids back to integers, so ids round-trip unchanged.

## Methods

| Method             | Phase | Params / result types (TS)                              |
|--------------------|-------|---------------------------------------------------------|
| `bridge.handshake` | 1     | `HandshakeParams` → `HandshakeResult`                   |
| `project_status`   | 1     | `{}` → `ProjectStatusResult`                            |
| `project_info`     | 1     | `ProjectInfoParams` → `ProjectInfoResult`               |
| `scene_inspect`    | 1     | `SceneInspectParams` → `SceneInspectResult`             |
| `scene_mutate`     | 1     | `SceneMutateParams` → `SceneMutateResult`               |

The full field-level contract, with descriptions, is in
[`methods.ts`](ogb-mcp/src/protocol/methods.ts).

Node paths are always relative to the root of the scene being edited, using
NodePath syntax (`"."` is the root, `"Player/Sprite2D"` is a descendant).

`scene_mutate` is **atomic**: every operation is validated before anything is
applied. All operations are then committed as one `EditorUndoRedoManager`
action, so one Ctrl+Z reverts the whole batch. If an operation fails, nothing
is applied, and `error.data.operation_index` identifies the failing operation.

## Errors

| Code   | Name                | Meaning                                         |
|--------|---------------------|-------------------------------------------------|
| -32700 | `PARSE_ERROR`       | Frame is not valid JSON                         |
| -32600 | `INVALID_REQUEST`   | Not a valid JSON-RPC request                    |
| -32601 | `METHOD_NOT_FOUND`  | Unknown method                                  |
| -32602 | `INVALID_PARAMS`    | Bad or missing parameters, malformed values     |
| -32603 | `INTERNAL_ERROR`    | Handler crashed (details in Godot's Output)     |
| -32000 | `UNAUTHORIZED`      | Handshake missing or token wrong                |
| -32001 | `PROTOCOL_MISMATCH` | Client and plugin protocol versions differ      |
| -32010 | `NO_SCENE_OPEN`     | The method needs an open scene                  |
| -32011 | `NODE_NOT_FOUND`    | A node path did not resolve                     |
| -32012 | `INVALID_OPERATION` | Valid request the editor refused (unknown class, missing property, …) |
| -32013 | `UNSAVED_CHANGES`   | Would touch a file that has unsaved editor changes |

## Value encoding

JSON-native values pass through unchanged, and `StringName` becomes a string.
Other Variant types become tagged objects:

```json
{"$type": "Vector2", "value": [10, 20]}
```

| `$type`                                     | `value`                                              |
|---------------------------------------------|------------------------------------------------------|
| `Vector2`, `Vector2i`                       | `[x, y]`                                             |
| `Vector3`, `Vector3i`                       | `[x, y, z]`                                          |
| `Vector4`, `Vector4i`, `Quaternion`         | `[x, y, z, w]`                                       |
| `Rect2`, `Rect2i`                           | `[x, y, width, height]`                              |
| `Color`                                     | `[r, g, b, a]` (input also: `[r, g, b]`, `"#rrggbb"`) |
| `Plane`                                     | `[normal.x, normal.y, normal.z, d]`                  |
| `AABB`                                      | `[pos.x, pos.y, pos.z, size.x, size.y, size.z]`      |
| `Transform2D`                               | `[x.x, x.y, y.x, y.y, origin.x, origin.y]`           |
| `Basis`                                     | 9 numbers, column-major (x, y, z axes)               |
| `Transform3D`                               | Basis (9) + origin (3)                               |
| `Projection`                                | 16 numbers, column-major                             |
| `NodePath`                                  | `"../Path"`                                          |
| `float`                                     | `"nan"`, `"inf"`, `"-inf"` (non-finite floats only)  |
| `PackedByteArray`                           | base64 string                                        |
| `PackedVector{2,3,4}Array`, `PackedColorArray` | array of element tuples                           |

Other packed arrays become plain JSON arrays. Objects are encoded by reference:

- `{"$type":"Resource","class":"Texture2D","path":"res://icon.svg"}`. On input, the plugin loads `path`.
- `{"$type":"Node","class":"Sprite2D","name":"Sprite"}` is output only.
- `{"$type":"Object","class":"…"}` is output only.
- `Callable`, `Signal` and `RID` become `{"$type":"Callable","repr":"…"}` and are output only.

Dictionary keys that aren't strings are serialized with `var_to_str()`.

JSON has a single number type, and Godot parses every number as a float. A
plain `3` therefore reaches the plugin as `3.0`. Handlers that write values,
such as `scene_mutate`, convert them to the target property's declared type
(int, enum, …). Integer vector types (`Vector2i`, …) keep their type because
their tag names it.
