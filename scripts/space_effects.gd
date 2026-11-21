extends Node3D

const Motion = preload("res://scripts/flight_motion.gd")
const FX = preload("res://scripts/impact_fx.gd")

var _system_id: String = ""


func _ready() -> void:
	name = "SpaceEffects"
	_system_id = str(GameState.state.get("current_system", ""))
	EffectApplier.space_effect.connect(show_effect)
	EffectApplier.galaxy_changed.connect(_on_system_changed)
	GameState.restored.connect(clear)


func clear() -> void:
	_system_id = str(GameState.state.get("current_system", ""))
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()


func show_effect(kind: String, position: Vector2, _npc_id: String) -> void:
	if kind not in ["destroyed", "landing", "takeoff", "star_damage", "arrival"]:
		return
	var centre: Vector3 = Motion.world_position(Motion.coordinates(position), 2.8)
	if kind == "destroyed":
		FX.burst(self, centre, Color(1.0, 0.35, 0.06), 2.3)
		SoundSystem.play_at("sfx_explosion", centre, self)
	elif kind == "star_damage":
		FX.burst(self, centre, Color(1.0, 0.28, 0.04), 0.65)
		SoundSystem.play_at("sfx_heat", centre, self)
	else:
		FX.ripple(self, centre, Color(0.28, 0.65, 1.0) if kind == "arrival" else Color(0.15, 0.85, 0.65), 3.5 if kind == "arrival" else 2.5)
		if kind in ["takeoff", "landing"]:
			SoundSystem.play_at("sfx_" + kind, centre, self)
	while get_child_count() > 18:
		var oldest: Node = get_child(0)
		remove_child(oldest)
		oldest.queue_free()


func _on_system_changed() -> void:
	var previous: String = _system_id
	clear()
	if previous != _system_id:
		show_effect("arrival", Motion.point(GameState.state["flight"]["pos"]), "player")
		SoundSystem.play_jump()
