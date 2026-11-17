@tool
extends RefCounted
## Discovery file that tells ogb-mcp where the bridge listens and which token
## to authenticate with. Written on start, removed on shutdown.

const Protocol := preload("protocol.gd")


static func write(port: int, token: String) -> Error:
	var path := ProjectSettings.globalize_path(Protocol.SESSION_FILE_PATH)
	var err := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if err != OK:
		return err
	# Create the file and restrict it to the owner before the token goes in.
	# (No-op on Windows, where the user profile ACLs already apply.)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.close()
	FileAccess.set_unix_permissions(path, FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER)
	file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({
		"protocol_version": Protocol.PROTOCOL_VERSION,
		"plugin_version": Protocol.PLUGIN_VERSION,
		"host": Protocol.BIND_ADDRESS,
		"port": port,
		"token": token,
		"pid": OS.get_process_id(),
		"godot_version": Engine.get_version_info()["string"],
		"started_at": Time.get_datetime_string_from_system(true) + "Z",
	}, "  "))
	file.close()
	return OK


static func remove() -> void:
	var path := ProjectSettings.globalize_path(Protocol.SESSION_FILE_PATH)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
