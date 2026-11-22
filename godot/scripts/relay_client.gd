class_name RelayClient
extends Node
## Talks to the Photo Town relay (relay/app.py, a Gradio app) over plain HTTP,
## so the same code runs on desktop and in the phone browser:
##   1. POST {base}/gradio_api/upload            (multipart photo) -> ["<server path>"]
##   2. POST {base}/gradio_api/call/generate     {"data":[FileData]} -> {"event_id"}
##   3. GET  {base}/gradio_api/call/generate/<id> (event stream until complete/error)
##   4. GET  the returned GLB file URL
## The photo is only held in memory for the upload.

signal finished(job_id: int, glb: PackedByteArray)
signal failed(job_id: int, message: String)

const DEFAULT_URL := "http://127.0.0.1:7860"
## Set this after deploying the relay Space (python relay/deploy.py ...),
## e.g. "https://your-name-photo-town-relay.hf.space".
const DEPLOYED_URL := ""
const SETTING := "photo_town/relay_url"
const UPLOAD_TIMEOUT := 30.0
const GENERATE_TIMEOUT := 600.0 # AniGen can take a few minutes

var base_url := DEFAULT_URL


func _ready() -> void:
	base_url = resolve_url()


## Relay URL, first match wins:
##   1. ?relay=https://... on the web page (handy for testing)
##   2. Project setting photo_town/relay_url
##   3. DEPLOYED_URL when the page is not on this computer (phones need HTTPS)
##   4. the local relay at DEFAULT_URL
static func resolve_url() -> String:
	var url := ""
	var on_this_computer := true
	if OS.has_feature("web"):
		var from_query: Variant = JavaScriptBridge.eval("new URLSearchParams(location.search).get('relay') || ''", true)
		if from_query is String:
			url = from_query
		var host: Variant = JavaScriptBridge.eval("location.hostname", true)
		on_this_computer = host is String and host in ["localhost", "127.0.0.1"]
	if url.is_empty():
		url = str(ProjectSettings.get_setting(SETTING, ""))
	if url.is_empty() and not on_this_computer:
		url = DEPLOYED_URL
	if url.is_empty():
		url = DEFAULT_URL
	return url.strip_edges().trim_suffix("/")


## `endpoint`: "generate" (a friend, AniGen) or "generate_place" (a place, TRELLIS).
func generate(job_id: int, jpeg: PackedByteArray, endpoint := "generate") -> void:
	var result: Variant = await _run(jpeg, endpoint)
	if result is PackedByteArray:
		finished.emit(job_id, result)
	else:
		failed.emit(job_id, str(result))


## Returns the GLB bytes, or a String error message for the player.
func _run(jpeg: PackedByteArray, endpoint := "generate") -> Variant:
	# 1. Upload
	var boundary := "PhotoTown%d" % randi()
	var body := PackedByteArray()
	body.append_array(("--%s\r\nContent-Disposition: form-data; name=\"files\"; filename=\"photo.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n" % boundary).to_utf8_buffer())
	body.append_array(jpeg)
	body.append_array(("\r\n--%s--\r\n" % boundary).to_utf8_buffer())
	var up := await _request(base_url + "/gradio_api/upload", HTTPClient.METHOD_POST,
		["Content-Type: multipart/form-data; boundary=" + boundary], body, UPLOAD_TIMEOUT)
	if up.error:
		return up.error
	var paths: Variant = JSON.parse_string(up.text)
	if not paths is Array or (paths as Array).is_empty():
		return "The 3D generator didn't accept the photo."

	# 2. Start the job
	var payload := {"data": [{"path": paths[0], "meta": {"_type": "gradio.FileData"}}]}
	var call := await _request("%s/gradio_api/call/%s" % [base_url, endpoint], HTTPClient.METHOD_POST,
		["Content-Type: application/json"], JSON.stringify(payload).to_utf8_buffer(), UPLOAD_TIMEOUT)
	if call.error:
		return call.error
	var started: Variant = JSON.parse_string(call.text)
	if not started is Dictionary or not (started as Dictionary).has("event_id"):
		return "The 3D generator didn't start the job."

	# 3. Wait for the result (the server closes the stream when done)
	var stream := await _request("%s/gradio_api/call/%s/%s" % [base_url, endpoint, started.event_id],
		HTTPClient.METHOD_GET, [], PackedByteArray(), GENERATE_TIMEOUT)
	if stream.error:
		return stream.error
	var event := parse_event_stream(stream.text)
	if event.name == "error":
		var detail: Variant = JSON.parse_string(event.data) if not event.data.is_empty() else null
		if detail is Dictionary and (detail as Dictionary).get("error") is String and not str(detail.error).is_empty():
			return str(detail.error)
		# Gradio hides unexpected errors (e.g. an unreadable image) as {"error": null}.
		return "3D generation failed. Use a clear full-body photo and try again."
	if event.name != "complete":
		return "3D generation stopped unexpectedly. Please try again."
	var outputs: Variant = JSON.parse_string(event.data)
	if not outputs is Array or (outputs as Array).is_empty() or not outputs[0] is Dictionary:
		return "3D generation returned no model."
	var glb_file: Dictionary = outputs[0]
	var url := str(glb_file.get("url", ""))
	if url.is_empty() and glb_file.has("path"):
		url = "%s/gradio_api/file=%s" % [base_url, glb_file.path]
	if url.is_empty():
		return "3D generation returned no model."

	# 4. Download the model
	var dl := await _request(url, HTTPClient.METHOD_GET, [], PackedByteArray(), UPLOAD_TIMEOUT)
	if dl.error:
		return dl.error
	if dl.bytes.size() < 12 or dl.bytes.slice(0, 4).get_string_from_ascii() != "glTF":
		return "The 3D model download was damaged. Please try again."
	return dl.bytes


## Last `event:` in a Gradio event stream with its `data:` line.
static func parse_event_stream(text: String) -> Dictionary:
	var result := {"name": "", "data": ""}
	var current := ""
	for raw in text.split("\n"):
		var line := raw.strip_edges(false, true)
		if line.begins_with("event:"):
			current = line.substr(6).strip_edges()
		elif line.begins_with("data:") and current != "heartbeat" and not current.is_empty():
			result = {"name": current, "data": line.substr(5).strip_edges()}
	return result


## One HTTP request. Returns {error: String ("" on success), text, bytes}.
func _request(url: String, method: HTTPClient.Method, headers: Array, body: PackedByteArray, timeout: float) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = timeout
	http.download_chunk_size = 65536
	http.accept_gzip = true
	add_child(http)
	var err := http.request_raw(url, PackedStringArray(headers), method, body)
	if err != OK:
		http.queue_free()
		return {"error": "Couldn't reach the 3D generator.", "text": "", "bytes": PackedByteArray()}
	var response: Array = await http.request_completed
	http.queue_free()
	var status: int = response[0]
	var code: int = response[1]
	var bytes: PackedByteArray = response[3]
	var out := {"error": "", "text": bytes.get_string_from_utf8(), "bytes": bytes}
	if status == HTTPRequest.RESULT_TIMEOUT and timeout < GENERATE_TIMEOUT:
		# Short steps (upload/start/download) only time out when the relay can't be reached.
		out.error = "Couldn't reach the 3D generator. Check the connection and try again."
	elif status == HTTPRequest.RESULT_TIMEOUT:
		out.error = "The 3D generator took too long. Please try again."
	elif status != HTTPRequest.RESULT_SUCCESS:
		out.error = "Couldn't reach the 3D generator. Check the connection and try again."
	elif code == 429:
		out.error = "The 3D generator is busy. Try again in a minute."
	elif code >= 500 or code == 404:
		out.error = "The 3D generator is offline right now."
	elif code >= 400:
		out.error = "The 3D generator rejected the request (%d)." % code
	return out
