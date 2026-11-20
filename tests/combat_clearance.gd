extends Node

const Routes = preload("res://scripts/combat_routes.gd")
const Movement = preload("res://scripts/combat_movement.gd")
const Math = preload("res://scripts/combat_math.gd")
const Roster = preload("res://scripts/combat_roster.gd")

var check_count: int = 0
var failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var origin: Vector2i = Vector2i(16, 12)
	var settings: Dictionary = DataLoader.get_record("ship_main")["movement"]
	for facing: int in range(8):
		var vessel: Dictionary = {"pos": Math.coordinates(origin), "facing": facing}
		var turn: Dictionary = {"origin": vessel["pos"].duplicate(), "facing": facing, "history": []}
		var bow: Vector2i = origin + Movement.DIRECTIONS[facing]
		var destination: Vector2i = origin + Movement.DIRECTIONS[facing] * 3
		var neighbors: Array[Vector2i] = []
		for offset: Vector2i in Movement.DIRECTIONS:
			var occupied: Vector2i = origin + offset
			if occupied == bow:
				continue
			neighbors.append(occupied)
			var route: Array[Vector2i] = Routes.path(vessel, destination, turn, 6, settings, [occupied])
			_check(not route.is_empty(), "Side or stern contact preserves forward movement at heading %d beside %s" % [facing, occupied])
			for point: Vector2i in route:
				_check(point != occupied, "The route never enters the adjacent ship's cell")
		_check(not Routes.path(vessel, destination, turn, 6, settings, neighbors).is_empty(), "A clear bow remains passable with all other neighboring cells occupied")
		_check(Routes.path(vessel, destination, turn, 6, settings, [bow]).is_empty(), "A ship directly blocking the bow prevents forward movement")
		_check(not Movement.clear_segment(origin, origin + Movement.DIRECTIONS[facing] * 2, [bow]), "A route cannot pass through a ship's interior")
	_check(Movement.clear_segment(Vector2i(10, 10), Vector2i(11, 9), [Vector2i(11, 10)]), "A diagonal grazing a side-cell corner is allowed")
	_check(not Movement.clear_segment(Vector2i(10, 10), Vector2i(12, 10), [Vector2i(11, 10)]), "Interior intersection is still blocked")
	for failure: String in failures:
		printerr("FAIL: " + failure)
	print("Combat clearance checks: %d passed, %d failed" % [check_count - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	check_count += 1
	if not condition:
		failures.append(message)
