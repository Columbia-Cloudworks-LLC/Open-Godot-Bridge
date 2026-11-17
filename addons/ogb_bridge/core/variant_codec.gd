@tool
extends RefCounted
## Converts Godot Variants to and from JSON-safe values.
##
## JSON-native values (null, bool, int, float, String, Array, Dictionary) pass
## through unchanged. Everything else is encoded as a tagged object:
##
##     {"$type": "Vector2", "value": [1.0, 2.0]}
##
## The exact shape of every tag is documented in PROTOCOL.md and typed in
## ogb-mcp/src/protocol/variant.ts.

const Protocol := preload("protocol.gd")
const RpcError := preload("rpc_error.gd")

const TYPE_KEY := "$type"
const VALUE_KEY := "value"


# --- Encoding ------------------------------------------------------------------

static func encode(v: Variant) -> Variant:
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return v
		TYPE_FLOAT:
			return _encode_float(v)
		TYPE_STRING_NAME:
			return String(v)
		TYPE_NODE_PATH:
			return _tag("NodePath", String(v))
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return _tag(type_string(typeof(v)), [v.x, v.y])
		TYPE_VECTOR3, TYPE_VECTOR3I:
			return _tag(type_string(typeof(v)), [v.x, v.y, v.z])
		TYPE_VECTOR4, TYPE_VECTOR4I:
			return _tag(type_string(typeof(v)), [v.x, v.y, v.z, v.w])
		TYPE_RECT2, TYPE_RECT2I:
			return _tag(type_string(typeof(v)), [v.position.x, v.position.y, v.size.x, v.size.y])
		TYPE_COLOR:
			return _tag("Color", [v.r, v.g, v.b, v.a])
		TYPE_QUATERNION:
			return _tag("Quaternion", [v.x, v.y, v.z, v.w])
		TYPE_PLANE:
			return _tag("Plane", [v.normal.x, v.normal.y, v.normal.z, v.d])
		TYPE_AABB:
			return _tag("AABB", [v.position.x, v.position.y, v.position.z, v.size.x, v.size.y, v.size.z])
		TYPE_TRANSFORM2D:
			return _tag("Transform2D", [v.x.x, v.x.y, v.y.x, v.y.y, v.origin.x, v.origin.y])
		TYPE_BASIS:
			return _tag("Basis", _basis_to_array(v))
		TYPE_TRANSFORM3D:
			return _tag("Transform3D", _basis_to_array(v.basis) + [v.origin.x, v.origin.y, v.origin.z])
		TYPE_PROJECTION:
			var p: Projection = v
			return _tag("Projection", [
				p.x.x, p.x.y, p.x.z, p.x.w,
				p.y.x, p.y.y, p.y.z, p.y.w,
				p.z.x, p.z.y, p.z.z, p.z.w,
				p.w.x, p.w.y, p.w.z, p.w.w,
			])
		TYPE_OBJECT:
			return _encode_object(v)
		TYPE_DICTIONARY:
			var out := {}
			for key: Variant in v:
				out[_encode_key(key)] = encode(v[key])
			return out
		TYPE_ARRAY:
			var out := []
			out.resize(v.size())
			for i in v.size():
				out[i] = encode(v[i])
			return out
		TYPE_PACKED_BYTE_ARRAY:
			return _tag("PackedByteArray", Marshalls.raw_to_base64(v))
		TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
			return Array(v)
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			var out := []
			for f: float in v:
				out.append(_encode_float(f))
			return out
		TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_VECTOR4_ARRAY, TYPE_PACKED_COLOR_ARRAY:
			# Untagged element tuples inside one tag: [[x, y], [x, y], ...].
			var out := []
			for e: Variant in v:
				out.append(encode(e)[VALUE_KEY])
			return _tag(type_string(typeof(v)), out)
		_:
			# Callable, Signal, RID: not transferable, described for humans only.
			return {TYPE_KEY: type_string(typeof(v)), "repr": str(v)}


static func _tag(type_name: String, value: Variant) -> Dictionary:
	return {TYPE_KEY: type_name, VALUE_KEY: value}


static func _encode_float(f: float) -> Variant:
	if is_nan(f):
		return _tag("float", "nan")
	if is_inf(f):
		return _tag("float", "inf" if f > 0.0 else "-inf")
	return f


static func _encode_key(key: Variant) -> String:
	if key is String or key is StringName:
		return String(key)
	return var_to_str(key)


static func _basis_to_array(b: Basis) -> Array:
	# Column-major: x axis, y axis, z axis.
	return [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z]


static func _encode_object(obj: Object) -> Variant:
	if obj == null or not is_instance_valid(obj):
		return null
	if obj is Resource:
		var res := obj as Resource
		var out := {TYPE_KEY: "Resource", "class": res.get_class()}
		# Sub-resources have paths like "res://scene.tscn::Foo_abc"; only
		# report paths that can be loaded on their own.
		if not res.resource_path.is_empty() and not res.resource_path.contains("::"):
			out["path"] = res.resource_path
		return out
	if obj is Node:
		var node := obj as Node
		return {TYPE_KEY: "Node", "class": node.get_class(), "name": String(node.name)}
	return {TYPE_KEY: "Object", "class": obj.get_class()}


# --- Decoding ------------------------------------------------------------------

## Decodes a JSON value produced by [method encode] (or written by a client)
## back into a Variant. Returns an RpcError instance if a tagged value is
## malformed; callers must check with `result is RpcError`.
static func decode(v: Variant) -> Variant:
	match typeof(v):
		TYPE_ARRAY:
			var out := []
			out.resize(v.size())
			for i in v.size():
				var item: Variant = decode(v[i])
				if item is RpcError:
					return item
				out[i] = item
			return out
		TYPE_DICTIONARY:
			if v.has(TYPE_KEY):
				return _decode_tagged(v)
			var out := {}
			for key: Variant in v:
				var item: Variant = decode(v[key])
				if item is RpcError:
					return item
				out[key] = item
			return out
		_:
			return v


static func _decode_tagged(d: Dictionary) -> Variant:
	var type_name: Variant = d[TYPE_KEY]
	if not (type_name is String):
		return RpcError.new(Protocol.INVALID_PARAMS, "'$type' must be a string.", {"value": d})
	var value: Variant = d.get(VALUE_KEY)
	match type_name:
		"NodePath":
			if value is String:
				return NodePath(value)
		"float":
			match value:
				"nan": return NAN
				"inf": return INF
				"-inf": return -INF
		"Vector2":
			if _is_num_array(value, 2): return Vector2(value[0], value[1])
		"Vector2i":
			if _is_num_array(value, 2): return Vector2i(int(value[0]), int(value[1]))
		"Vector3":
			if _is_num_array(value, 3): return Vector3(value[0], value[1], value[2])
		"Vector3i":
			if _is_num_array(value, 3): return Vector3i(int(value[0]), int(value[1]), int(value[2]))
		"Vector4":
			if _is_num_array(value, 4): return Vector4(value[0], value[1], value[2], value[3])
		"Vector4i":
			if _is_num_array(value, 4): return Vector4i(int(value[0]), int(value[1]), int(value[2]), int(value[3]))
		"Rect2":
			if _is_num_array(value, 4): return Rect2(value[0], value[1], value[2], value[3])
		"Rect2i":
			if _is_num_array(value, 4): return Rect2i(int(value[0]), int(value[1]), int(value[2]), int(value[3]))
		"Color":
			if _is_num_array(value, 4): return Color(value[0], value[1], value[2], value[3])
			if _is_num_array(value, 3): return Color(value[0], value[1], value[2])
			if value is String and Color.html_is_valid(value): return Color.html(value)
		"Quaternion":
			if _is_num_array(value, 4): return Quaternion(value[0], value[1], value[2], value[3])
		"Plane":
			if _is_num_array(value, 4): return Plane(value[0], value[1], value[2], value[3])
		"AABB":
			if _is_num_array(value, 6):
				return AABB(Vector3(value[0], value[1], value[2]), Vector3(value[3], value[4], value[5]))
		"Transform2D":
			if _is_num_array(value, 6):
				return Transform2D(Vector2(value[0], value[1]), Vector2(value[2], value[3]), Vector2(value[4], value[5]))
		"Basis":
			if _is_num_array(value, 9):
				return _array_to_basis(value)
		"Transform3D":
			if _is_num_array(value, 12):
				return Transform3D(_array_to_basis(value), Vector3(value[9], value[10], value[11]))
		"Projection":
			if _is_num_array(value, 16):
				return Projection(
					Vector4(value[0], value[1], value[2], value[3]),
					Vector4(value[4], value[5], value[6], value[7]),
					Vector4(value[8], value[9], value[10], value[11]),
					Vector4(value[12], value[13], value[14], value[15]))
		"PackedByteArray":
			if value is String: return Marshalls.base64_to_raw(value)
		"PackedVector2Array", "PackedVector3Array", "PackedVector4Array", "PackedColorArray":
			if value is Array: return _decode_packed(type_name, value)
		"Resource":
			return _decode_resource(d)
		_:
			return RpcError.new(Protocol.INVALID_PARAMS, "Unsupported $type '%s'." % [type_name], {"value": d})
	return RpcError.new(Protocol.INVALID_PARAMS, "Malformed %s value." % [type_name], {"value": d})


static func _is_num_array(v: Variant, size: int) -> bool:
	if not (v is Array) or v.size() != size:
		return false
	for e: Variant in v:
		if not (e is float or e is int):
			return false
	return true


static func _array_to_basis(a: Array) -> Basis:
	return Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8]))


static func _decode_packed(type_name: String, items: Array) -> Variant:
	var element_type: String = type_name.trim_prefix("Packed").trim_suffix("Array")
	var decoded := []
	for item: Variant in items:
		var e: Variant = _decode_tagged({TYPE_KEY: element_type, VALUE_KEY: item})
		if e is RpcError:
			return e
		decoded.append(e)
	match type_name:
		"PackedVector2Array": return PackedVector2Array(decoded)
		"PackedVector3Array": return PackedVector3Array(decoded)
		"PackedVector4Array": return PackedVector4Array(decoded)
		_: return PackedColorArray(decoded)


static func _decode_resource(d: Dictionary) -> Variant:
	var path: Variant = d.get("path")
	if not (path is String) or not path.begins_with("res://"):
		return RpcError.new(Protocol.INVALID_PARAMS, "Resource values must carry a 'res://' path.", {"value": d})
	if not ResourceLoader.exists(path):
		return RpcError.new(Protocol.INVALID_PARAMS, "Resource does not exist: %s" % path, {"path": path})
	var res := ResourceLoader.load(path)
	if res == null:
		return RpcError.new(Protocol.INVALID_PARAMS, "Failed to load resource: %s" % path, {"path": path})
	return res
