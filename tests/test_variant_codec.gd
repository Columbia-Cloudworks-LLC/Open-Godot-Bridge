extends SceneTree
## Headless tests for core/variant_codec.gd.
##
##   godot --headless --path . --script res://tests/test_variant_codec.gd
##
## Exits with code 1 on failure.

const VariantCodec := preload("res://addons/ogb_bridge/core/variant_codec.gd")
const RpcError := preload("res://addons/ogb_bridge/core/rpc_error.gd")

var _failures := 0


func _init() -> void:
	_test_round_trips()
	_test_json_shapes()
	_test_decode_errors()
	_test_input_conveniences()
	print("variant_codec: %s" % ("OK" if _failures == 0 else "%d failure(s)" % _failures))
	quit(1 if _failures > 0 else 0)


func _check(label: String, ok: bool, detail: Variant = null) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, "" if detail == null else str(detail)])


## Encodes, pushes through real JSON text, decodes, and compares.
func _round_trip(v: Variant) -> Variant:
	var text := JSON.stringify(VariantCodec.encode(v))
	return VariantCodec.decode(JSON.parse_string(text))


func _test_round_trips() -> void:
	var values: Array = [
		null, true, 1.5, "text",
		Vector2(1.5, -2), Vector2i(3, 4), Vector3(1, 2, 3), Vector3i(-1, 0, 1),
		Vector4(1, 2, 3, 4), Vector4i(1, 2, 3, 4),
		Rect2(1, 2, 3, 4), Rect2i(1, 2, 3, 4),
		Color(0.25, 0.5, 0.75, 1), Quaternion(0, 0, 0, 1), Plane(0, 1, 0, 5),
		AABB(Vector3(1, 2, 3), Vector3(4, 5, 6)),
		Transform2D(0.5, Vector2(10, 20)),
		Basis.from_euler(Vector3(0.5, 0, 0)),
		Transform3D(Basis.from_euler(Vector3(0, 1, 0)), Vector3(1, 2, 3)),
		Projection.create_perspective(60, 1.5, 0.1, 100),
		NodePath("../Player:position"),
		PackedByteArray([0, 1, 254, 255]),
		PackedVector2Array([Vector2(1, 2), Vector2(3, 4)]),
		PackedVector3Array([Vector3(1, 2, 3)]),
		PackedColorArray([Color.RED, Color.BLUE]),
		[1.0, Vector2(1, 1), {"nested": Color.GREEN}],
		{"a": Vector3.ONE, "b": [NodePath("x")]},
	]
	for v: Variant in values:
		var back: Variant = _round_trip(v)
		var same: bool = typeof(back) == typeof(v) and (back == v or (back is Basis or back is Transform3D or back is Projection) and str(back) == str(v))
		_check("round trip %s" % type_string(typeof(v)), same, "%s -> %s" % [v, back])

	# JSON has one number type and Godot parses all numbers as float, so ints
	# come back as equal floats. Handlers coerce by the target property type.
	var int_back: Variant = _round_trip(42)
	_check("int returns as equal float", int_back is float and int_back == 42.0, int_back)
	_check("Vector2i stays integral", _round_trip(Vector2i(3, 4)) is Vector2i)

	var inf_back: Variant = _round_trip(INF)
	_check("round trip INF", inf_back is float and is_inf(inf_back) and inf_back > 0)
	_check("round trip NAN", is_nan(_round_trip(NAN)))
	_check("StringName becomes String", _round_trip(&"name") is String)


func _test_json_shapes() -> void:
	_check("Vector2 shape", VariantCodec.encode(Vector2(1, 2)) == {"$type": "Vector2", "value": [1.0, 2.0]})
	_check("PackedInt32Array is plain array", VariantCodec.encode(PackedInt32Array([1, 2])) == [1, 2])
	var res: Variant = VariantCodec.encode(load("res://addons/ogb_bridge/plugin.gd"))
	_check("Resource carries path", res is Dictionary and res.get("path") == "res://addons/ogb_bridge/plugin.gd", res)
	var non_string_key: Dictionary = VariantCodec.encode({1: "a"})
	_check("non-string keys become strings", non_string_key.keys()[0] is String, non_string_key)


func _test_decode_errors() -> void:
	var cases: Array = [
		{"$type": "Vector2", "value": [1]},
		{"$type": "Vector2", "value": ["a", "b"]},
		{"$type": "Banana", "value": 1},
		{"$type": 7, "value": 1},
		{"$type": "Resource", "path": "/etc/passwd"},
		{"$type": "Resource", "path": "res://does/not/exist.tres"},
		[1, {"$type": "Color", "value": "not-a-color"}],
	]
	for c: Variant in cases:
		_check("rejects %s" % JSON.stringify(c), VariantCodec.decode(c) is RpcError)


func _test_input_conveniences() -> void:
	_check("Color from rgb", VariantCodec.decode({"$type": "Color", "value": [1, 0, 0]}) == Color(1, 0, 0))
	_check("Color from html", VariantCodec.decode({"$type": "Color", "value": "#ff0000"}) == Color(1, 0, 0))
	var r: Variant = VariantCodec.decode({"$type": "Resource", "path": "res://addons/ogb_bridge/plugin.gd"})
	_check("Resource loads by path", r is Script, r)
