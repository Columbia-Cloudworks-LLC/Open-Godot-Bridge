# Project Specification: OpenGodot Bridge (`ogb`)

## 1. Objective
Build an open-source, MIT-licensed local bridge that connects standard Godot 4.3+ editors to any Model Context Protocol (MCP) client (Claude Code, Cursor, VS Code, local Ollama/LM Studio) over `stdio`. 

The system eliminates copy-paste workflows by giving AI agents direct, undo-safe access to the live Godot scene tree, project settings, runtime debugger output, input injection, and viewport capture—while wrapping every agent turn in an atomic Git-backed rollback boundary.

## 2. Core Design Principles
* **Zero Engine Forking:** Must run as a standard `EditorPlugin` inside stock Godot 4.3+ without modifying engine binaries or corrupting global user `EditorSettings`.
* **Undo-Safe Mutations:** Every scene/node modification executed via RPC must wrap operations in Godot's `EditorUndoRedoManager` so native `Ctrl+Z` works cleanly.
* **Atomic Turn Receipts:** Every MCP tool session or agent turn tracks file diffs and supports one-click per-file or per-hunk rollback without polluting the user's primary Git commit history.
* **Spec-First Guardrails:** Enforces project-level `GAME-BRIEF.md` (scope control) and `AGENTS.md` (Godot 4 API conventions) templates when initializing a workspace.

## 3. System Architecture
Two decoupled components communicating over a local WebSocket (default `ws://127.0.0.1:6510`):

1. **Godot EditorPlugin (`addons/ogb_bridge/` - GDScript):**
   * Runs inside the Godot editor process.
   * Exposes a local JSON-RPC 2.0 WebSocket server on startup.
   * Interfaces directly with `EditorInterface`, `EditorUndoRedoManager`, `EditorDebuggerPlugin`, `ProjectSettings`, `InputMap`, and `Viewport`.
   * Provides a toggleable editor layout preset (`Minimal` vs. `Standard` dock visibility) via a toolbar button.

2. **MCP Host & Turn Manager (`ogb-mcp` - Rust or TypeScript):**
   * Exposes a standard MCP server over `stdio`.
   * **Lazy Tool Discovery:** When no Godot instance is connected on the local socket, exposes only a single tool (`project_status`) explaining how to launch Godot with the plugin enabled. Once connected, dynamically registers the full toolset.
   * **Shadow Diff Tracker:** Takes a lightweight filesystem/Git snapshot before write operations to compute turn receipts (`Changed X files, +Y -Z`) and enable hunk-level reverts.

## 4. JSON-RPC & MCP Tool Contract
Implement the following MCP tools, mapped 1:1 to JSON-RPC methods on the Godot plugin:

* `project_status`: Checks WebSocket connection health, Godot version, active project path, and current scene.
* `project_info`: Reads `project.godot` and returns main scene, autoload singletons, `InputMap` actions, and directory tree.
* `scene_inspect`: Serializes the currently open scene tree (node names, types, paths, exported properties, and connected signals) into structured JSON.
* `scene_mutate`: Performs batch node operations (`add_node`, `remove_node`, `set_property`, `connect_signal`) wrapped in a single `EditorUndoRedoManager` action. Checks for unsaved editor buffers before touching files on disk.
* `run_project`: Triggers `F5` (main scene) or `F6` (current scene), captures `stdout`/`stderr`, and hooks `EditorDebuggerPlugin` to return GDScript parse errors, runtime exceptions, and stack traces (`file:line`).
* `stop_project`: Terminates the running game instance cleanly.
* `inject_input`: Sends timed sequences of `InputEventKey`, `InputEventMouseButton`, or `InputEventAction` into the running game instance for deterministic playtesting.
* `capture_viewport`: Captures a PNG of either the 2D/3D editor viewport or the running game viewport and returns it as base64 image content.

## 5. Phased Implementation Plan
* **Phase 1 (MVP Bridge):** Build `addons/ogb_bridge/` with the WebSocket JSON-RPC server, `project_info`, `scene_inspect`, `scene_mutate` (with `EditorUndoRedoManager`), and a minimal `ogb-mcp` `stdio` server exposing those tools.
* **Phase 2 (Execution & Vision Loop):** Add `EditorDebuggerPlugin` error capture, `run_project` / `stop_project`, `capture_viewport`, and `inject_input`.
* **Phase 3 (Safety & Spec Scaffolding):** Add the shadow diff tracker / hunk rollback CLI commands, `Minimal` / `Standard` editor layout toggle, and `GAME-BRIEF.md` / `AGENTS.md` workspace initializer.