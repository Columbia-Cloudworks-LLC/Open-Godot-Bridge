@tool
extends Node
## Ties the WebSocket transport to the JSON-RPC router and owns per-client
## sessions, authentication and the discovery file.

const Protocol := preload("protocol.gd")
const RpcRouter := preload("rpc_router.gd")
const SessionFile := preload("session_file.gd")
const WsServer := preload("ws_server.gd")

## The EditorPlugin that owns this bridge. Handlers use it for editor-only
## APIs such as get_undo_redo().
var plugin: EditorPlugin
var router := RpcRouter.new()
## Shared secret clients must present in bridge.handshake.
var token: String

var _server: WsServer
var _sessions: Dictionary = {}  # int -> RpcRouter.Session
## Handler modules are RefCounted; Callables don't keep their target alive,
## so the bridge holds them for its whole lifetime.
var _modules: Array[RefCounted] = []


func _init(p_plugin: EditorPlugin = null) -> void:
	plugin = p_plugin
	name = "OgbBridge"
	token = Crypto.new().generate_random_bytes(32).hex_encode()
	# Built here rather than in _ready(): plugins enter the tree while the
	# editor is still starting up, so _ready() can run after start().
	_server = WsServer.new()
	_server.name = "WsServer"
	_server.inbound_buffer_size = Protocol.MAX_INBOUND_BYTES
	_server.outbound_buffer_size = Protocol.MAX_OUTBOUND_BYTES
	_server.peer_connected.connect(_on_peer_connected)
	_server.peer_disconnected.connect(_on_peer_disconnected)
	_server.text_received.connect(_on_text_received)
	add_child(_server)


## Registers a handler module: any object with `register(router)`.
func install(module: RefCounted) -> void:
	_modules.append(module)
	module.register(router)


## Starts listening. Returns the bound port, or 0 on failure.
func start() -> int:
	var port := _server.listen_in_range(Protocol.DEFAULT_PORT, Protocol.PORT_RANGE, Protocol.BIND_ADDRESS)
	if port == 0:
		push_error("[OGB] No free port in %d-%d; bridge disabled." % [
			Protocol.DEFAULT_PORT, Protocol.DEFAULT_PORT + Protocol.PORT_RANGE - 1])
		return 0
	var err := SessionFile.write(port, token)
	if err != OK:
		push_warning("[OGB] Could not write %s (%s); ogb-mcp will not find this editor automatically." % [
			Protocol.SESSION_FILE_PATH, error_string(err)])
	print("[OGB] Bridge listening on ws://%s:%d" % [Protocol.BIND_ADDRESS, port])
	return port


func stop() -> void:
	if _server != null and _server.is_listening():
		_server.stop()
		SessionFile.remove()
	_sessions.clear()


func get_port() -> int:
	return _server.get_port() if _server != null else 0


func client_count() -> int:
	return _sessions.size()


func _exit_tree() -> void:
	stop()


func _on_peer_connected(peer_id: int) -> void:
	_sessions[peer_id] = RpcRouter.Session.new(peer_id)
	get_tree().create_timer(Protocol.AUTH_TIMEOUT_SEC).timeout.connect(_enforce_auth_timeout.bind(peer_id))


func _on_peer_disconnected(peer_id: int, _code: int, _reason: String) -> void:
	var session: RpcRouter.Session = _sessions.get(peer_id)
	_sessions.erase(peer_id)
	if session != null and session.authenticated:
		print("[OGB] Client disconnected: %s" % session.client_info.get("name", "unknown"))


func _on_text_received(peer_id: int, text: String) -> void:
	var session: RpcRouter.Session = _sessions.get(peer_id)
	if session == null:
		return
	var reply: String = await router.handle_text(session, text)
	# The peer may have gone away while an async handler was running.
	if not reply.is_empty() and _sessions.has(peer_id):
		_server.send_text(peer_id, reply)


func _enforce_auth_timeout(peer_id: int) -> void:
	var session: RpcRouter.Session = _sessions.get(peer_id)
	if session != null and not session.authenticated:
		_server.disconnect_peer(peer_id, Protocol.CLOSE_AUTH_TIMEOUT, "Handshake timeout")
