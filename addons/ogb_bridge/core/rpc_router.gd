@tool
extends RefCounted
## JSON-RPC 2.0 request router.
##
## Transport-agnostic: takes a raw text frame plus the caller's [Session] and
## returns the text frame to send back ("" when no reply is due, e.g. for
## notifications).
##
## Handler contract:
##   func handler(params: Dictionary, session: Session) -> Variant
## A handler returns its result (any Variant; it is passed through
## VariantCodec.encode) or an RpcError instance. Handlers may `await`.
## Results must be non-null: a GDScript runtime error aborts the handler and
## yields null, so the router reports null as an internal error.

const Protocol := preload("protocol.gd")
const RpcError := preload("rpc_error.gd")
const VariantCodec := preload("variant_codec.gd")


## Per-connection state, owned by the transport layer.
class Session:
	extends RefCounted
	var peer_id: int
	var authenticated := false
	var client_info := {}

	func _init(p_peer_id: int) -> void:
		peer_id = p_peer_id


class _Route:
	var handler: Callable
	var requires_auth: bool

	func _init(p_handler: Callable, p_requires_auth: bool) -> void:
		handler = p_handler
		requires_auth = p_requires_auth


var _routes: Dictionary = {}  # String -> _Route


func register(method: String, handler: Callable, requires_auth := true) -> void:
	assert(not _routes.has(method), "Duplicate RPC method: %s" % method)
	_routes[method] = _Route.new(handler, requires_auth)


func has_method_named(method: String) -> bool:
	return _routes.has(method)


func method_names() -> PackedStringArray:
	var names := PackedStringArray(_routes.keys())
	names.sort()
	return names


## Handles one inbound text frame. Returns the serialized reply, or "" if
## nothing should be sent.
func handle_text(session: Session, text: String) -> String:
	var json := JSON.new()
	if json.parse(text) != OK:
		var err := RpcError.new(Protocol.PARSE_ERROR, "Parse error: %s (line %d)" % [json.get_error_message(), json.get_error_line()])
		return _serialize(_error_response(null, err))

	var message: Variant = json.data
	if message is Array:
		if message.is_empty():
			return _serialize(_error_response(null, RpcError.new(Protocol.INVALID_REQUEST, "Empty batch.")))
		var replies := []
		for item: Variant in message:
			var reply: Variant = await _handle_message(session, item)
			if reply != null:
				replies.append(reply)
		return _serialize(replies) if not replies.is_empty() else ""

	var single: Variant = await _handle_message(session, message)
	return _serialize(single) if single != null else ""


## Returns a response Dictionary, or null for notifications.
func _handle_message(session: Session, message: Variant) -> Variant:
	if not (message is Dictionary):
		return _error_response(null, RpcError.new(Protocol.INVALID_REQUEST, "Request must be an object."))

	var request: Dictionary = message
	var has_id := request.has("id")
	var id: Variant = _normalize_id(request.get("id"))
	if has_id and not _is_valid_id(id):
		return _error_response(null, RpcError.new(Protocol.INVALID_REQUEST, "'id' must be a string, number or null."))
	# Check types before comparing: in Godot 4, == between a String and a
	# number is a runtime error rather than false.
	var version: Variant = request.get("jsonrpc")
	if not (version is String and version == "2.0"):
		return _error_response(id, RpcError.new(Protocol.INVALID_REQUEST, "'jsonrpc' must be \"2.0\"."))
	if not (request.get("method") is String):
		return _error_response(id, RpcError.new(Protocol.INVALID_REQUEST, "'method' must be a string."))

	var params: Variant = request.get("params", {})
	if params == null:
		params = {}
	var result: Variant = await _dispatch(session, request["method"], params)

	if not has_id:
		return null  # Notification: never reply, even on error.
	if result is RpcError:
		return _error_response(id, result)
	return {"jsonrpc": "2.0", "id": id, "result": VariantCodec.encode(result)}


func _dispatch(session: Session, method: String, params: Variant) -> Variant:
	var route: _Route = _routes.get(method)
	if route == null:
		return RpcError.new(Protocol.METHOD_NOT_FOUND, "Method not found: %s" % method)
	if route.requires_auth and not session.authenticated:
		return RpcError.new(Protocol.UNAUTHORIZED, "Call %s first." % Protocol.METHOD_HANDSHAKE)
	if not (params is Dictionary):
		return RpcError.new(Protocol.INVALID_PARAMS, "'params' must be an object.")

	var result: Variant = await route.handler.call(params, session)
	if result == null:
		push_error("[OGB] Handler for '%s' returned null (script error?)." % method)
		return RpcError.new(Protocol.INTERNAL_ERROR, "Handler for '%s' failed; see the Godot output panel." % method)
	return result


static func _error_response(id: Variant, err: RpcError) -> Dictionary:
	return {"jsonrpc": "2.0", "id": id, "error": err.to_dict()}


## Godot's JSON parser yields floats for every number; restore integral ids so
## they round-trip unchanged.
static func _normalize_id(id: Variant) -> Variant:
	if id is float and is_finite(id) and id == floorf(id):
		return int(id)
	return id


static func _is_valid_id(id: Variant) -> bool:
	return id == null or id is String or id is int or id is float


static func _serialize(value: Variant) -> String:
	return JSON.stringify(value)
