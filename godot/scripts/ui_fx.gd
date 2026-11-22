class_name UiFx
extends RefCounted
## Small reusable UI animations (tweens). All of them are safe to call repeatedly:
## a new animation on a control replaces the previous one.


## Scale + fade a control in from slightly small ("pop"), with an overshoot.
static func pop_in(control: Control, delay := 0.0, from_scale := 0.85) -> void:
	_center_pivot(control)
	control.scale = Vector2.ONE * from_scale
	control.modulate.a = 0.0
	var tween := _fresh(control)
	tween.set_parallel(true)
	tween.tween_property(control, "scale", Vector2.ONE, 0.35).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "modulate:a", 1.0, 0.2).set_delay(delay)


## Slide a bottom-anchored panel up from below the screen and fade it in.
static func slide_up(control: Control, distance := 120.0) -> void:
	var final_y := control.position.y
	control.position.y = final_y + distance
	control.modulate.a = 0.0
	var tween := _fresh(control)
	tween.set_parallel(true)
	tween.tween_property(control, "position:y", final_y, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "modulate:a", 1.0, 0.25)


## Slide down and fade out, then hide and run `done`.
static func slide_down(control: Control, done := Callable(), distance := 120.0) -> void:
	var start_y := control.position.y
	var tween := _fresh(control)
	tween.set_parallel(true)
	tween.tween_property(control, "position:y", start_y + distance, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(control, "modulate:a", 0.0, 0.2)
	tween.chain().tween_callback(func() -> void:
		control.visible = false
		control.position.y = start_y
		control.modulate.a = 1.0
		if done.is_valid():
			done.call())


## Text changed: fade it up with a little pop. (Scale/alpha only, so it also
## works for labels inside containers, which own their position.)
static func text_in(label: Control) -> void:
	label.pivot_offset = Vector2(0.0, label.size.y * 0.5) # grow from the left edge
	label.modulate.a = 0.0
	label.scale = Vector2(0.94, 0.94)
	var tween := _fresh(label)
	tween.set_parallel(true)
	tween.tween_property(label, "modulate:a", 1.0, 0.25)
	tween.tween_property(label, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Springy press feedback for any button: squash on press, bounce back on release.
static func add_press_bounce(button: BaseButton) -> void:
	button.resized.connect(_center_pivot.bind(button))
	_center_pivot(button)
	button.button_down.connect(func() -> void:
		var tween := _fresh(button)
		tween.tween_property(button, "scale", Vector2.ONE * 0.9, 0.08).set_ease(Tween.EASE_OUT))
	button.button_up.connect(func() -> void:
		var tween := _fresh(button)
		tween.tween_property(button, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT))


static func _center_pivot(control: Control) -> void:
	control.pivot_offset = control.size * 0.5


## One tween per control: kill the last one so animations never fight.
static func _fresh(control: Control) -> Tween:
	if control.has_meta("_ui_fx_tween"):
		var old: Variant = control.get_meta("_ui_fx_tween")
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
	var tween := control.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS) # UI keeps animating while the game is paused
	control.set_meta("_ui_fx_tween", tween)
	return tween
