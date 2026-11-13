extends Control

const Appearance = preload("res://scripts/heroine_appearance.gd")
const Layer = preload("res://scripts/portrait_layer.gd")
const Widgets = preload("res://scripts/hub_widgets.gd")

var heroine_id: String = ""
var appearance: Dictionary = {}


func _init() -> void:
	custom_minimum_size = Vector2(72, 88)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	for layer_name: String in ["Base", "Face", "Blush"]:
		var layer: Layer = Layer.new()
		layer.name = layer_name
		layer.layer = layer_name.to_lower()
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(layer)
		layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	EffectApplier.domestic_changed.connect(refresh)
	EffectApplier.relationships_changed.connect(refresh)
	GameState.restored.connect(refresh)
	Clock.time_changed.connect(func(_day: int, _slot: String) -> void: refresh())
	refresh()


func refresh() -> void:
	if not is_inside_tree() or not has_node("Blush"):
		return
	var blueprint: Dictionary = DataLoader.get_record(heroine_id)
	appearance = Appearance.select(blueprint, GameState.state.get("heroines", {}).get(heroine_id, {}))
	tooltip_text = str(blueprint.get("name", ""))
	for layer: Layer in get_children():
		layer.color = Widgets.identity_color(heroine_id)
		layer.face = str(appearance["face"])
		layer.blush = int(appearance["blush"])
		layer.visible = layer.layer != "blush" or layer.blush > 0
		layer.queue_redraw()
