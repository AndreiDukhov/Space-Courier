extends Node

const Conditions = preload("res://scripts/condition_evaluator.gd")
const PeekState = preload("res://scripts/peek_state.gd")
const Hub = preload("res://scenes/hub.tscn")
const Warm = preload("res://scripts/hub_theme.gd")

var failures: Array[String] = []
var checks: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(DataLoader.load_errors.is_empty(), "Content and source regions validate on startup")
	if not DataLoader.load_errors.is_empty():
		get_tree().quit(1)
		return
	_rules()
	_persistence()
	_validation()
	await _interface()
	for message: String in failures:
		printerr("FAIL: " + message)
	print("Peek door drag checks: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _new_game(origin: String = "hub_corridor") -> void:
	GameState.start_new_game(DataLoader.get_records("heroines"), DataLoader.get_record("ship_main"))
	if origin == "hub_showers":
		Clock.advance_slots(2)
	EffectApplier.move_player(origin)
	for heroine: Dictionary in GameState.state["heroines"].values():
		heroine["loc"] = "hub_kitchen"
		heroine["mood"] = 50.0


func _rules() -> void:
	_new_game()
	_check(GameState.state["peek"].is_empty(), "New games have no pending challenge")
	var unchanged: Dictionary = GameState.serialize()
	_check(EffectApplier.begin_peeking("hub_bedroom") == ERR_UNAVAILABLE and EffectApplier.begin_peeking("missing") == ERR_UNAVAILABLE and GameState.serialize() == unchanged, "Player and unknown bedrooms are not peeking targets")
	for _attempt: int in range(12):
		_check(EffectApplier.begin_peeking("hub_pilot_bedroom") == OK, "Bedroom peeking starts from the corridor")
		var peek: Dictionary = GameState.state["peek"]
		_check(peek.size() == 4 and peek["opening"] == 0 and not peek["noticed"] and peek["limit"] >= 0.35 and peek["limit"] <= 0.65, "Each attempt begins closed with the approved hidden range")
		EffectApplier.end_peeking()
	GameState.state["heroines"]["pilot"]["loc"] = "hub_pilot_bedroom"
	EffectApplier.begin_peeking("hub_pilot_bedroom")
	_check(not Conditions.can_enter("hub_kitchen") and not Conditions.can_wait() and not Conditions.can_use_bedroom_doors(), "Travel and time are blocked during the challenge")
	unchanged = GameState.serialize()
	_check(EffectApplier.begin_peeking("hub_medic_bedroom") == ERR_UNAVAILABLE and GameState.serialize() == unchanged, "An active limit cannot be rerolled by starting twice")
	for sample: Vector2 in [Vector2(0.1, 1), Vector2(0.2, 1), Vector2(0.15, 1), Vector2.ZERO]:
		var elapsed: float = 1.0 if sample.y == 0 else sample.y
		_check(EffectApplier.move_peek_door(sample.x, elapsed) == OK and not GameState.state["peek"]["noticed"], "Slow opening and closing stay safe")
	_check(GameState.state["heroines"]["pilot"]["mood"] == 50, "Careful movement preserves mood")
	unchanged = GameState.serialize()
	for invalid: Vector2 in [Vector2(-0.1, 1), Vector2(1.1, 1), Vector2(0.1, 0), Vector2(0.1, -1), Vector2(INF, 1), Vector2(0.1, NAN)]:
		_check(EffectApplier.move_peek_door(invalid.x, invalid.y) == ERR_UNAVAILABLE and GameState.serialize() == unchanged, "Invalid motion is rejected without mutations")
	_check(EffectApplier.move_peek_door(0.1, 0.01) == OK and GameState.state["peek"]["noticed"] and GameState.state["heroines"]["pilot"]["mood"] == 45, "Fast motion detects the player and applies minus five")
	unchanged = GameState.serialize()
	_check(EffectApplier.move_peek_door(0.2, 1) == ERR_UNAVAILABLE and GameState.serialize() == unchanged, "A finished attempt cannot penalize twice")
	EffectApplier.end_peeking()
	EffectApplier.begin_peeking("hub_pilot_bedroom")
	var beyond: float = float(GameState.state["peek"]["limit"]) + 0.01
	_check(EffectApplier.move_peek_door(beyond, 10) == OK and GameState.state["peek"]["noticed"] and GameState.state["heroines"]["pilot"]["mood"] == 40, "Slow movement beyond the hidden limit also detects")
	EffectApplier.end_peeking()
	EffectApplier.begin_peeking("hub_medic_bedroom")
	var crew: Dictionary = GameState.state["heroines"].duplicate(true)
	EffectApplier.move_peek_door(0.3, 0.01)
	_check(GameState.state["heroines"] == crew, "An empty bedroom has no mood penalty")
	EffectApplier.end_peeking()
	_new_game("hub_showers")
	GameState.state["heroines"]["pilot"]["loc"] = "hub_showers"
	GameState.state["heroines"]["security"]["loc"] = "hub_showers"
	GameState.state["heroines"]["security"]["mood"] = 2.0
	_check(EffectApplier.begin_peeking("hub_showers") == OK, "The shower uses the same challenge")
	EffectApplier.move_peek_door(0.3, 0.01)
	_check(GameState.state["heroines"]["pilot"]["mood"] == 45 and GameState.state["heroines"]["security"]["mood"] == 0 and GameState.state["heroines"]["medic"]["mood"] == 50, "Only current occupants lose mood and zero is the minimum")
	EffectApplier.end_peeking()
	_new_game("hub_kitchen")
	_check(EffectApplier.begin_peeking("hub_pilot_bedroom") == ERR_UNAVAILABLE and EffectApplier.begin_peeking("hub_showers") == ERR_UNAVAILABLE, "Remote peeking is unavailable")


func _persistence() -> void:
	_new_game()
	var legacy: Dictionary = GameState.serialize()
	legacy.erase("peek")
	_check(GameState.restore(legacy) == OK and GameState.state["peek"].is_empty(), "Legacy saves add an empty challenge")
	var migrated: Dictionary = GameState.serialize()
	migrated.erase("peek")
	_check(migrated == legacy, "Migration preserves every previous field")
	GameState.state["heroines"]["pilot"]["loc"] = "hub_pilot_bedroom"
	EffectApplier.begin_peeking("hub_pilot_bedroom")
	EffectApplier.move_peek_door(0.2, 2)
	var saved: Dictionary = GameState.serialize()
	_check(GameState.save_game("user://peek-check.json") == OK and GameState.load_game("user://peek-check.json") == OK and GameState.serialize() == saved, "Active opening and exact hidden limit round-trip")
	EffectApplier.move_peek_door(0.4, 0.01)
	saved = GameState.serialize()
	_check(GameState.save_game("user://peek-check.json") == OK and GameState.load_game("user://peek-check.json") == OK and GameState.serialize() == saved and GameState.state["heroines"]["pilot"]["mood"] == 45, "Restoring detection does not repeat the penalty")
	EffectApplier.end_peeking()
	EffectApplier.begin_peeking("hub_pilot_bedroom")
	saved = GameState.serialize()
	var bad_values: Dictionary = {"location": ["missing", "hub_bedroom", 2], "opening": [-0.01, 1.01, INF, "0"], "limit": [0, 1, NAN, "0.5"], "noticed": [0, "false"]}
	for key: String in bad_values:
		for value: Variant in bad_values[key]:
			var invalid: Dictionary = saved.duplicate(true)
			invalid["peek"][key] = value
			_check(GameState.restore(invalid) == ERR_INVALID_DATA and GameState.serialize() == saved, "Invalid saved " + key + " is rejected atomically")
	for key: String in ["opening", "noticed"]:
		var invalid: Dictionary = saved.duplicate(true)
		invalid["peek"].erase(key)
		_check(GameState.restore(invalid) == ERR_INVALID_DATA, "Missing peek fields are rejected")
	var extra: Dictionary = saved.duplicate(true)
	extra["peek"]["extra"] = true
	_check(GameState.restore(extra) == ERR_INVALID_DATA, "Unapproved fields are rejected")
	var wrong_origin: Dictionary = saved.duplicate(true)
	wrong_origin["location"] = "hub_kitchen"
	_check(GameState.restore(wrong_origin) == ERR_INVALID_DATA, "A challenge cannot restore in another room")
	var over_limit: Dictionary = saved.duplicate(true)
	over_limit["peek"]["opening"] = 0.9
	_check(GameState.restore(over_limit) == ERR_INVALID_DATA, "An undetected opening cannot exceed the saved limit")
	EffectApplier.end_peeking()


func _validation() -> void:
	var layout: Dictionary = DataLoader.get_record("peek_layout").duplicate(true)
	_check(PeekState.validate_layout(layout).is_empty(), "The approved layout validates")
	for rule: String in ["max_speed", "limit", "mood_penalty"]:
		var invalid: Dictionary = layout.duplicate(true)
		invalid["rules"].erase(rule)
		_check(not PeekState.validate_layout(invalid).is_empty(), "Missing rules are rejected")
	for limits: Array in [[0, 0.5], [0.6, 0.3], [0.2, 1], [0.5], [NAN, 0.5]]:
		var invalid: Dictionary = layout.duplicate(true)
		invalid["rules"]["limit"] = limits
		_check(not PeekState.validate_layout(invalid).is_empty(), "Invalid random limit intervals are rejected")
	for zone: String in ["frame", "door"]:
		var invalid: Dictionary = layout.duplicate(true)
		invalid["zones"][zone]["drop_rect"] = [0.5, 0, 0.9, 1]
		_check(not PeekState.validate_layout(invalid).is_empty(), "Out-of-source sprite regions are rejected")


func _interface() -> void:
	_new_game()
	GameState.state["heroines"]["pilot"]["loc"] = "hub_pilot_bedroom"
	var hub: Control = Hub.instantiate()
	add_child(hub)
	await _frames()
	await _click(hub.get_node("BedroomDoors/door_pilot"))
	await _click(hub.get_node("BedroomDoors/DoorMenu").find_child("Peek", true, false))
	_check(hub._peek != null and GameState.state["peek"]["opening"] == 0, "The actual door menu opens the closed challenge")
	var view: Control = hub._peek
	var door: Sprite2D = view._door.door
	var jamb: Sprite2D = view._door.frame
	_check(door.texture is AtlasTexture and jamb.texture is AtlasTexture and door != jamb, "Door and jamb are separate sprites")
	var seam: float = jamb.position.x + jamb.texture.get_width() * jamb.scale.x
	_check(absf(seam - door.position.x) <= 2.1 and door.position.x + door.texture.get_width() * door.scale.x >= view.size.x, "The closed door touches the jamb and fills the screen")
	await _capture("closed")
	await RenderingServer.frame_post_draw
	var pixel: Vector2i = Vector2i(view.size * Vector2(0.34, 0.5))
	var closed_color: Color = get_viewport().get_texture().get_image().get_pixelv(pixel)
	view._room.modulate = Color(0.1, 1, 0.1)
	await _frames()
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().get_pixelv(pixel).is_equal_approx(closed_color), "The old gap is fully occluded when closed")
	view._room.modulate = Color.WHITE
	var point: Vector2 = view.size * Vector2(0.72, 0.5)
	await _motion(point, false)
	_check(GameState.state["peek"]["opening"] == 0, "Moving the mouse without LMB cannot open the door")
	var frame_pos: Vector2 = jamb.position
	await _button(point, true)
	for _step: int in range(20):
		await get_tree().create_timer(0.025).timeout
		point.x += view._door.travel_pixels * 0.002
		await _motion(point, true)
	await _button(point, false)
	_check(not GameState.state["peek"]["noticed"] and is_equal_approx(float(GameState.state["peek"]["opening"]), 0.04), "A real held slow drag opens the door safely")
	_check(jamb.position == frame_pos and door.position.x > seam, "The jamb remains fixed while the door moves")
	var saved: Dictionary = GameState.serialize()
	await _capture("open")
	await _motion(point + Vector2(120, 0), false)
	_check(GameState.serialize() == saved, "Releasing LMB stops the door immediately")
	await _button(point, true)
	await get_tree().create_timer(0.05).timeout
	point.x -= view._door.travel_pixels * 0.005
	await _motion(point, true)
	await _button(point, false)
	_check(is_equal_approx(float(GameState.state["peek"]["opening"]), 0.035), "Dragging left closes the door")
	_check(GameState.restore(saved) == OK, "An active UI can be loaded")
	await _frames()
	view = hub._peek
	_check(view != null and is_equal_approx(float(GameState.state["peek"]["opening"]), 0.04), "The hub restores the saved view and opening")
	point = view.size * Vector2(0.72, 0.5)
	await _button(point, true)
	await get_tree().create_timer(0.03).timeout
	point.x += view._door.travel_pixels * 0.25
	await _motion(point, true)
	await _button(point, false)
	_check(GameState.state["peek"]["noticed"] and view.has_node("Caught") and GameState.state["heroines"]["pilot"]["mood"] == 45, "A fast held drag shows detection and applies the penalty once")
	await _capture("caught")
	saved = GameState.serialize()
	_check(GameState.restore(saved) == OK, "A finished attempt can be restored")
	await _frames()
	_check(hub._peek.has_node("Caught") and GameState.state["heroines"]["pilot"]["mood"] == 45, "Loading the result displays it without a second penalty")
	await _escape()
	_check(hub._peek == null and GameState.state["peek"].is_empty() and not PauseMenu.is_open(), "Esc exits the challenge without a second menu")
	EffectApplier.move_player("hub_tech")
	await _frames()
	hub.open_ship_refit()
	await _frames()
	_check(hub._refit != null and hub._refit.theme == Warm.make(), "Refit uses the hub warm theme")
	var refit: Control = hub._refit
	_check(refit._slots["engine"]["icon"].warm and refit._module_cards.values()[0]._icon.warm, "Sockets and catalog icons use warm colors")
	await _capture("refit")
	await _escape()
	hub.queue_free()
	await _frames()
	_new_game()
	EffectApplier.begin_peeking("hub_pilot_bedroom")
	hub = Hub.instantiate()
	add_child(hub)
	await _frames()
	_check(hub._peek != null, "A newly created hub resumes a pending challenge")
	EffectApplier.end_peeking()
	hub.queue_free()
	await _frames()


func _click(button: Button) -> void:
	await _button(button.get_global_rect().get_center(), true)
	await _button(button.get_global_rect().get_center(), false)


func _button(point: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	get_viewport().push_input(event, true)
	await _frames()


func _motion(point: Vector2, held: bool) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	get_viewport().push_input(event, true)
	await _frames()


func _escape() -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.pressed = pressed
		get_viewport().push_input(event, true)
	await _frames()


func _frames() -> void:
	for _frame: int in range(3):
		await get_tree().process_frame


func _capture(suffix: String) -> void:
	if "--capture-peek-drag" not in OS.get_cmdline_user_args():
		return
	if "--small" in OS.get_cmdline_user_args():
		suffix += "-small"
	await RenderingServer.frame_post_draw
	_check(get_viewport().get_texture().get_image().save_png("res://.godot/peek-drag-" + suffix + ".png") == OK, "Rendered " + suffix)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
