class_name WorldStore
extends RefCounted
## Saves the player's world on this device (user://, which is IndexedDB on web):
##   user://world.json            {"version": 1, "residents": [{id, name, x, z, created}]}
##   user://residents/<id>.glb    the generated model (never the photo)
## Every call fails soft: it returns false/empty and the game keeps running.

const INDEX_PATH := "user://world.json"
const MODEL_DIR := "user://residents"
const VERSION := 1


static func new_id() -> String:
	return "%d_%05d" % [int(Time.get_unix_time_from_system()), randi() % 100000]


static func load_index() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if not FileAccess.file_exists(INDEX_PATH):
		return entries
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(INDEX_PATH))
	if not data is Dictionary or not (data as Dictionary).get("residents") is Array:
		push_warning("WorldStore: world.json unreadable, starting fresh")
		return entries
	for item: Variant in data.residents:
		if item is Dictionary and str(item.get("id", "")).is_valid_filename() and FileAccess.file_exists(model_path(str(item.id))):
			entries.append(item)
	return entries


static func save_index(entries: Array[Dictionary]) -> bool:
	var file := FileAccess.open(INDEX_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("WorldStore: can't write world.json (%s)" % error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify({"version": VERSION, "residents": entries}, "  "))
	file.close()
	return true


static func model_path(id: String) -> String:
	return "%s/%s.glb" % [MODEL_DIR, id]


static func save_model(id: String, glb: PackedByteArray) -> bool:
	if DirAccess.make_dir_recursive_absolute(MODEL_DIR) != OK:
		push_warning("WorldStore: can't create %s" % MODEL_DIR)
		return false
	var file := FileAccess.open(model_path(id), FileAccess.WRITE)
	if file == null:
		push_warning("WorldStore: can't write model %s" % id)
		return false
	file.store_buffer(glb)
	file.close()
	return true


static func load_model(id: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(model_path(id))


static func delete_model(id: String) -> void:
	if FileAccess.file_exists(model_path(id)):
		DirAccess.remove_absolute(model_path(id))
