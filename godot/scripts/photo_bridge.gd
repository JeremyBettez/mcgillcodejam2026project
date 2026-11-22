class_name PhotoBridge
extends Node
## Gets a photo from the player as JPEG bytes in memory (never written to disk).
## Web: uses window.photoTown from godot/web/photo-town.js (camera app or photo picker).
## Desktop (editor testing): opens a native file dialog.

signal photo_ready(jpeg: PackedByteArray, texture: ImageTexture)
signal photo_failed(message: String) # empty message = player cancelled

const MAX_SIDE := 1024

var _js: JavaScriptObject
var _js_callback: JavaScriptObject # must stay referenced while JS may call it


func _ready() -> void:
	if OS.has_feature("web"):
		_js = JavaScriptBridge.get_interface("photoTown")
		if _js:
			_js_callback = JavaScriptBridge.create_callback(_on_js_photo)


## True when photos can be picked at all on this platform.
func is_available() -> bool:
	if OS.has_feature("web"):
		return _js != null
	return true


## source: "camera" or "library".
func pick(source: String) -> void:
	if OS.has_feature("web"):
		if _js == null:
			photo_failed.emit("Photo input isn't available in this browser.")
			return
		_js.pickPhoto(source, _js_callback)
	else:
		_pick_desktop()


## Asks for a name with the browser's prompt on web. Returns null if cancelled
## or if not on web (callers then use the LineEdit text as typed).
func ask_name(current: String) -> Variant:
	if _js == null:
		return null
	var value: Variant = _js.askName(current)
	return value if value is String else null


func _on_js_photo(args: Array) -> void:
	var data: Variant = JSON.parse_string(str(args[0])) if not args.is_empty() else null
	if not data is Dictionary:
		photo_failed.emit("Something went wrong reading the photo.")
		return
	var result: Dictionary = data
	if not result.get("ok", false):
		photo_failed.emit("" if result.get("cancelled", false) else str(result.get("error", "Couldn't get a photo.")))
		return
	_finish(Marshalls.base64_to_raw(str(result.get("base64", ""))))


func _pick_desktop() -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		photo_failed.emit("No file picker on this platform.")
		return
	DisplayServer.file_dialog_show(
		"Choose a full-body photo",
		OS.get_system_dir(OS.SYSTEM_DIR_PICTURES),
		"",
		false,
		DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
		PackedStringArray(["*.jpg, *.jpeg, *.png, *.webp ; Images"]),
		_on_desktop_file
	)


func _on_desktop_file(status: bool, paths: PackedStringArray, _filter: int) -> void:
	if not status or paths.is_empty():
		photo_failed.emit("")
		return
	var image: Image = null
	if FileAccess.file_exists(paths[0]):
		image = Image.load_from_file(paths[0])
	if image == null or image.is_empty():
		photo_failed.emit("Could not read that photo. Try a JPEG or PNG.")
		return
	_finish(encode_jpeg(image))


## Shrink to MAX_SIDE and re-encode as JPEG (also drops any metadata).
static func encode_jpeg(image: Image) -> PackedByteArray:
	var longest := maxi(image.get_width(), image.get_height())
	if longest > MAX_SIDE:
		var s := float(MAX_SIDE) / longest
		image.resize(maxi(1, roundi(image.get_width() * s)), maxi(1, roundi(image.get_height() * s)), Image.INTERPOLATE_LANCZOS)
	image.convert(Image.FORMAT_RGB8)
	return image.save_jpg_to_buffer(0.9)


func _finish(jpeg: PackedByteArray) -> void:
	var image := Image.new()
	if jpeg.is_empty() or image.load_jpg_from_buffer(jpeg) != OK:
		photo_failed.emit("Could not read that photo. Try a JPEG or PNG.")
		return
	photo_ready.emit(jpeg, ImageTexture.create_from_image(image))
