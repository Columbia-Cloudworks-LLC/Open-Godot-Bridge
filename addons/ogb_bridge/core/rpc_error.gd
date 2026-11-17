@tool
extends RefCounted
## A JSON-RPC error value.
##
## Handlers signal failure by returning an instance of this class instead of a
## result; the router turns it into a JSON-RPC error response. Use the codes
## in protocol.gd:
##
##     return RpcError.new(Protocol.NODE_NOT_FOUND, "Node not found: %s" % path, {"path": path})

var code: int
var message: String
var data: Variant


func _init(p_code: int, p_message: String, p_data: Variant = null) -> void:
	code = p_code
	message = p_message
	data = p_data


func to_dict() -> Dictionary:
	var out := {"code": code, "message": message}
	if data != null:
		out["data"] = data
	return out
