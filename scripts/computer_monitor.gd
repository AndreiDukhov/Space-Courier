extends Panel

const Style = preload("res://scripts/hub_widgets.gd")
const Text = preload("res://scripts/ui_text.gd")
const SCREEN: Rect2 = Rect2(0.0546875, 0.075, 0.890625, 0.73)

@onready var artwork: TextureRect = $Artwork
@onready var content: Control = $TerminalContent
@onready var close_button: Button = $CloseTerminal


func _ready() -> void:
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	close_button.tooltip_text = Text.get_text("ui_room_power")
	close_button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	close_button.add_theme_stylebox_override("hover", Style.box(Color(0.15, 0.55, 0.5, 0.35), 20))
	close_button.add_theme_stylebox_override("pressed", Style.box(Color(0.2, 0.75, 0.65, 0.5), 20))
	close_button.add_theme_stylebox_override("focus", Style.box(Color.TRANSPARENT, 20, Color(0.5, 1.0, 0.9), 1))
	resized.connect(_layout_monitor)
	_layout_monitor.call_deferred()


func _layout_monitor() -> void:
	var available: Vector2 = (size - Vector2(64, 28)).max(Vector2.ONE)
	var image_size: Vector2 = artwork.texture.get_size()
	var scale: float = minf(available.x / image_size.x, available.y / image_size.y)
	var rendered: Vector2 = image_size * scale
	var origin: Vector2 = (size - rendered) * 0.5
	artwork.position = origin
	artwork.size = rendered
	content.position = origin + SCREEN.position * rendered
	content.size = SCREEN.size * rendered
	close_button.size = Vector2(40, 40)
	close_button.position = origin + Vector2(0.5, 0.84875) * rendered - close_button.size * 0.5
