# OpenGodot Bridge (`ogb`)

An MIT-licensed bridge between a stock **Godot 4.3+** editor and any
[Model Context Protocol](https://modelcontextprotocol.io) client (Claude Code,
Cursor, VS Code, local LLM hosts). It gives agents direct access to the live
scene tree, and every mutation is undoable with Ctrl+Z.

> **Status:** Phase 1 is in progress. The WebSocket JSON-RPC server, handshake,
> `project_status` and the protocol types are done. `project_info`,
> `scene_inspect`, `scene_mutate` and the MCP stdio server are next. See
> [SPEC.md](SPEC.md) for the roadmap.

## How it works

```
MCP client ──stdio──▶ ogb-mcp ──WebSocket / JSON-RPC 2.0──▶ ogb_bridge (EditorPlugin)
                       (Node)       ws://127.0.0.1:6510          inside Godot editor
```

- **[`addons/ogb_bridge/`](addons/ogb_bridge/)** is the GDScript editor plugin. It runs a
  localhost-only WebSocket server and maps JSON-RPC methods onto `EditorInterface`
  and `EditorUndoRedoManager`.
- **[`ogb-mcp/`](ogb-mcp/)** is the TypeScript MCP server. It discovers the running
  editor through `.godot/ogb_bridge/session.json` and exposes the bridge methods as MCP tools.

The wire format, authentication, error codes and Variant encoding are documented in
[PROTOCOL.md](PROTOCOL.md).

## Repository layout

```
addons/ogb_bridge/
  plugin.cfg, plugin.gd      EditorPlugin entry point (lifecycle only)
  core/
    protocol.gd              constants & error codes (mirrored in ogb-mcp)
    ws_server.gd             TCPServer + WebSocketPeer transport
    rpc_router.gd            JSON-RPC 2.0 parsing, dispatch, batching, auth gate
    rpc_error.gd             error value returned by handlers
    variant_codec.gd         Godot Variant <-> JSON
    session_file.gd          discovery file
    bridge.gd                wires transport, router and sessions together
  handlers/
    bridge_handlers.gd       bridge.handshake, project_status
ogb-mcp/
  src/protocol/              JSON-RPC envelopes, method schemas & result types,
                             error codes, Variant types, session file
  test/                      vitest suite (includes a GDScript<->TS drift check)
  scripts/smoke.mjs          end-to-end check against a running editor
project.godot                dev project: open the repo in Godot to work on the addon
```

## Development

### Plugin

Open this repository in Godot 4.3 or newer. The plugin is already enabled in
the dev `project.godot`. The Output panel should show:

```
[OGB] Bridge listening on ws://127.0.0.1:6510
```

To use the plugin in your own game, copy `addons/ogb_bridge/` into your project
and enable it in **Project → Project Settings → Plugins**.

### ogb-mcp

```sh
cd ogb-mcp
npm install
npm test           # unit tests, including the protocol drift check
npm run typecheck
npm run build
```

### Plugin tests (headless Godot)

```sh
godot --headless --path . --script res://tests/test_variant_codec.gd
```

With the editor open, run an end-to-end check:

```sh
node ogb-mcp/scripts/smoke.mjs .   # path to the Godot project
```

> **WSL note:** Windows Godot listens on Windows' loopback, which a WSL process
> can't reach in WSL's default NAT networking mode. Either run the client with
> Windows `node.exe`, or enable `networkingMode=mirrored` in `.wslconfig`.

## License

[MIT](LICENSE)
