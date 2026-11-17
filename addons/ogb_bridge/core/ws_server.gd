@tool
extends Node
## Minimal multi-client WebSocket server built on TCPServer + WebSocketPeer.
##
## Pure transport: knows nothing about JSON-RPC. Polls from _process, which
## runs in the editor because this script is a @tool script.

signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int, code: int, reason: String)
signal text_received(peer_id: int, text: String)

## Connections must finish the HTTP upgrade within this window.
const UPGRADE_TIMEOUT_MS := 3000
const CLOSE_GOING_AWAY := 1001
const CLOSE_UNSUPPORTED_DATA := 1003

class _PendingPeer:
	var ws: WebSocketPeer
	var started_ms: int

	func _init(p_ws: WebSocketPeer) -> void:
		ws = p_ws
		started_ms = Time.get_ticks_msec()


var inbound_buffer_size := 4 * 1024 * 1024
var outbound_buffer_size := 32 * 1024 * 1024

var _tcp := TCPServer.new()
var _upgrading: Array[_PendingPeer] = []
var _peers: Dictionary = {}  # int -> WebSocketPeer
var _next_peer_id := 1


func _init() -> void:
	# Idle until listen(). Not done in _ready(), which may run after listen().
	set_process(false)


func is_listening() -> bool:
	return _tcp.is_listening()


func get_port() -> int:
	return _tcp.get_local_port() if _tcp.is_listening() else 0


func listen(port: int, bind_address: String) -> Error:
	stop()
	var err := _tcp.listen(port, bind_address)
	if err == OK:
		set_process(true)
	return err


## Listens on the first free port in [first_port, first_port + count).
## Returns the bound port, or 0 if none was free.
func listen_in_range(first_port: int, count: int, bind_address: String) -> int:
	for port in range(first_port, first_port + count):
		if listen(port, bind_address) == OK:
			return port
	return 0


func stop() -> void:
	for peer_id: int in _peers.keys():
		disconnect_peer(peer_id, CLOSE_GOING_AWAY, "Server shutting down")
	# Give close frames a chance to go out before the sockets are dropped.
	for ws: WebSocketPeer in _peers.values():
		ws.poll()
	_peers.clear()
	_upgrading.clear()
	_tcp.stop()
	set_process(false)


func send_text(peer_id: int, text: String) -> Error:
	var ws: WebSocketPeer = _peers.get(peer_id)
	if ws == null or ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return ERR_UNAVAILABLE
	return ws.send_text(text)


func disconnect_peer(peer_id: int, code := 1000, reason := "") -> void:
	var ws: WebSocketPeer = _peers.get(peer_id)
	if ws != null:
		ws.close(code, reason)


func peer_count() -> int:
	return _peers.size()


func _process(_delta: float) -> void:
	_accept_new_connections()
	_poll_upgrading()
	_poll_peers()


func _accept_new_connections() -> void:
	while _tcp.is_connection_available():
		var stream := _tcp.take_connection()
		var ws := WebSocketPeer.new()
		ws.inbound_buffer_size = inbound_buffer_size
		ws.outbound_buffer_size = outbound_buffer_size
		if ws.accept_stream(stream) == OK:
			_upgrading.append(_PendingPeer.new(ws))


func _poll_upgrading() -> void:
	var now := Time.get_ticks_msec()
	# Iterate backwards so removal is safe.
	for i in range(_upgrading.size() - 1, -1, -1):
		var pending := _upgrading[i]
		pending.ws.poll()
		match pending.ws.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				_upgrading.remove_at(i)
				var peer_id := _next_peer_id
				_next_peer_id += 1
				_peers[peer_id] = pending.ws
				peer_connected.emit(peer_id)
			WebSocketPeer.STATE_CONNECTING:
				if now - pending.started_ms > UPGRADE_TIMEOUT_MS:
					pending.ws.close()
					_upgrading.remove_at(i)
			_:
				_upgrading.remove_at(i)


func _poll_peers() -> void:
	# Snapshot the ids: signal handlers may disconnect peers mid-iteration.
	for peer_id: int in _peers.keys():
		var ws: WebSocketPeer = _peers.get(peer_id)
		if ws == null:
			continue
		ws.poll()
		while ws.get_ready_state() == WebSocketPeer.STATE_OPEN and ws.get_available_packet_count() > 0:
			var packet := ws.get_packet()
			if ws.was_string_packet():
				text_received.emit(peer_id, packet.get_string_from_utf8())
			else:
				ws.close(CLOSE_UNSUPPORTED_DATA, "Binary frames are not supported")
		if ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			_peers.erase(peer_id)
			peer_disconnected.emit(peer_id, ws.get_close_code(), ws.get_close_reason())
