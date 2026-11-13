extends TextureRect


func _ready() -> void:
	name = "SpaceBackdrop"
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	show_behind_parent = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	EffectApplier.galaxy_changed.connect(refresh)
	GameState.restored.connect(refresh)
	refresh()


func refresh() -> void:
	var system: Dictionary = DataLoader.get_record(str(GameState.state["current_system"]))
	texture = load(str(system["background"])) as Texture2D
