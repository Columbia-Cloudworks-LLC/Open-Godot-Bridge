@tool
extends EditorPlugin
## Entry point. Keeps lifecycle wiring only; behaviour lives in core/ and
## handlers/.

const Bridge := preload("core/bridge.gd")
const BridgeHandlers := preload("handlers/bridge_handlers.gd")

var _bridge: Bridge


func _enter_tree() -> void:
	_bridge = Bridge.new(self)
	add_child(_bridge)
	_bridge.install(BridgeHandlers.new(_bridge))
	_bridge.start()


func _exit_tree() -> void:
	if _bridge != null:
		_bridge.stop()
		_bridge.queue_free()
		_bridge = null
