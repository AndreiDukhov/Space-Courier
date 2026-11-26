extends Node2D

const Opaque = preload("res://scripts/peek_opaque.gdshader")

var door: Sprite2D
var frame: Sprite2D
var travel_pixels: float = 1.0
var _source: Texture2D
var _seam: float = 0.0
var _top: float = 0.0


func _ready() -> void:
	var layout: Dictionary = DataLoader.get_record("peek_layout")
	_source = load(str(layout["background"])) as Texture2D
	door = _sprite("Door", layout["zones"]["door"]["drop_rect"])
	frame = _sprite("Frame", layout["zones"]["frame"]["drop_rect"])


func _sprite(node_name: String, region: Array) -> Sprite2D:
	var atlas: AtlasTexture = AtlasTexture.new()
	atlas.atlas = _source
	atlas.region = Rect2(Vector2(float(region[0]), float(region[1])) * _source.get_size(), Vector2(float(region[2]), float(region[3])) * _source.get_size())
	atlas.filter_clip = true
	var sprite: Sprite2D = Sprite2D.new()
	sprite.name = node_name
	sprite.centered = false
	sprite.texture = atlas
	var opaque: ShaderMaterial = ShaderMaterial.new()
	opaque.shader = Opaque
	sprite.material = opaque
	add_child(sprite)
	return sprite


func layout(view_size: Vector2) -> void:
	var horizontal: float = view_size.x / _source.get_width()
	var vertical: float = maxf(horizontal, view_size.y / _source.get_height())
	_top = (view_size.y - _source.get_height() * vertical) * 0.5
	frame.position = Vector2(0, _top)
	frame.scale = Vector2(horizontal, vertical)
	_seam = frame.texture.get_width() * horizontal - 2
	travel_pixels = maxf(1, view_size.x - _seam)
	door.scale = Vector2((travel_pixels + 2) / door.texture.get_width(), vertical)


func show_opening(opening: float) -> void:
	door.position = Vector2(_seam + opening * travel_pixels, _top)


func contains_global(point: Vector2) -> bool:
	return door.get_rect().has_point(door.to_local(point))
