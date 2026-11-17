@tool
extends RefCounted
## bridge.handshake and project_status.

const Protocol := preload("../core/protocol.gd")
const RpcError := preload("../core/rpc_error.gd")
const RpcRouter := preload("../core/rpc_router.gd")
const Bridge := preload("../core/bridge.gd")

var _bridge: Bridge


func _init(bridge: Bridge) -> void:
	_bridge = bridge


func register(router: RpcRouter) -> void:
	router.register(Protocol.METHOD_HANDSHAKE, _handshake, false)
	router.register(Protocol.METHOD_PROJECT_STATUS, _project_status)


func _handshake(params: Dictionary, session: RpcRouter.Session) -> Variant:
	var client_version: Variant = params.get("protocol_version")
	if not (client_version is float or client_version is int):
		return RpcError.new(Protocol.INVALID_PARAMS, "'protocol_version' must be a number.")
	if int(client_version) != Protocol.PROTOCOL_VERSION:
		return RpcError.new(Protocol.PROTOCOL_MISMATCH,
			"Protocol version mismatch: client speaks %d, plugin speaks %d. Update the older side." % [
				int(client_version), Protocol.PROTOCOL_VERSION],
			{"client": int(client_version), "server": Protocol.PROTOCOL_VERSION})

	var presented: Variant = params.get("token")
	if not (presented is String) or not _constant_time_equals(presented, _bridge.token):
		return RpcError.new(Protocol.UNAUTHORIZED, "Invalid token. Read it from %s." % Protocol.SESSION_FILE_PATH)

	var client: Variant = params.get("client", {})
	session.client_info = client if client is Dictionary else {}
	session.authenticated = true
	print("[OGB] Client connected: %s %s" % [
		session.client_info.get("name", "unknown"), session.client_info.get("version", "")])

	return {
		"protocol_version": Protocol.PROTOCOL_VERSION,
		"plugin_version": Protocol.PLUGIN_VERSION,
		"godot": _godot_version(),
		"project": _project_identity(),
		"methods": _bridge.router.method_names(),
	}


func _project_status(_params: Dictionary, _session: RpcRouter.Session) -> Variant:
	var root := EditorInterface.get_edited_scene_root()
	var current_scene: Variant = null
	if root != null:
		var scene_path: Variant = null
		if not root.scene_file_path.is_empty():
			scene_path = root.scene_file_path
		current_scene = {
			"path": scene_path,
			"root_name": String(root.name),
			"root_type": root.get_class(),
		}
	return {
		"plugin_version": Protocol.PLUGIN_VERSION,
		"godot": _godot_version(),
		"project": _project_identity(),
		"current_scene": current_scene,
		"open_scenes": _open_scene_paths(),
		"is_playing": EditorInterface.is_playing_scene(),
		"connected_clients": _bridge.client_count(),
	}


## Saved scenes open in editor tabs. Unsaved tabs report "" and are skipped.
static func _open_scene_paths() -> PackedStringArray:
	var paths := PackedStringArray()
	for path in EditorInterface.get_open_scenes():
		if not path.is_empty():
			paths.append(path)
	return paths


static func _godot_version() -> Dictionary:
	var info := Engine.get_version_info()
	return {
		"string": info["string"],
		"major": info["major"],
		"minor": info["minor"],
		"patch": info["patch"],
		"status": info["status"],
	}


static func _project_identity() -> Dictionary:
	return {
		"name": ProjectSettings.get_setting("application/config/name", ""),
		"path": ProjectSettings.globalize_path("res://").trim_suffix("/"),
	}


## Compares without early exit so response timing doesn't leak the token.
static func _constant_time_equals(a: String, b: String) -> bool:
	var ba := a.to_utf8_buffer()
	var bb := b.to_utf8_buffer()
	var diff := ba.size() ^ bb.size()
	for i in mini(ba.size(), bb.size()):
		diff |= ba[i] ^ bb[i]
	return diff == 0
