extends RefCounted

const LightingShader = preload("res://scripts/hub_lighting.gdshader")
const MASK_SIZE: int = 64

var _masks: Dictionary = {}
var _materials: Dictionary = {}


func material_for(location_id: String, slot: String, closed: bool = false) -> ShaderMaterial:
	var key: String = location_id + "/" + slot + ("/closed" if closed else "")
	if _materials.has(key):
		return _materials[key]
	var profile: Dictionary = DataLoader.get_record("hub_lighting")["slots"][slot]
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = LightingShader
	material.set_shader_parameter("ambient", float(profile["ambient"]))
	material.set_shader_parameter("light_gain", float(profile["light_gain"]))
	material.set_shader_parameter("light_mask", _mask_for(location_id))
	material.set_shader_parameter("desaturate", closed)
	_materials[key] = material
	return material


func _mask_for(location_id: String) -> Texture2D:
	if _masks.has(location_id):
		return _masks[location_id]
	var mask: Image = Image.create_empty(MASK_SIZE, MASK_SIZE, false, Image.FORMAT_R8)
	mask.fill(Color.BLACK)
	var areas: Array = DataLoader.get_record("hub_lighting")["locations"].get(location_id, {}).get("light_rects", [])
	for area: Array in areas:
		var region: Rect2i = Rect2i(int(float(area[0]) * MASK_SIZE), int(float(area[1]) * MASK_SIZE), ceili(float(area[2]) * MASK_SIZE), ceili(float(area[3]) * MASK_SIZE))
		mask.fill_rect(region.intersection(Rect2i(0, 0, MASK_SIZE, MASK_SIZE)), Color.WHITE)
	var texture: ImageTexture = ImageTexture.create_from_image(mask)
	_masks[location_id] = texture
	return texture
