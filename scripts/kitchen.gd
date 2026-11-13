extends VBoxContainer

signal finished(result: Error)

const Conditions = preload("res://scripts/condition_evaluator.gd")
const Inventory = preload("res://scripts/inventory.gd")
const Cooking = preload("res://scripts/cooking_math.gd")
const State = preload("res://scripts/domestic_state.gd")
const Widgets = preload("res://scripts/domestic_widgets.gd")
const Text = preload("res://scripts/ui_text.gd")
const Token = preload("res://scripts/cooking_token.gd")
const Zone = preload("res://scripts/kitchen_zone.gd")
const Appearance = preload("res://scripts/cooking_appearance.gd")

var _recipe_id: String = ""
var _counter: Control
var _background: TextureRect
var _zones: Dictionary = {}
var _refresh_queued: bool = false


func _ready() -> void:
    size_flags_vertical = Control.SIZE_EXPAND_FILL
    EffectApplier.domestic_changed.connect(_queue_refresh)
    GameState.restored.connect(_queue_refresh)
    add_theme_constant_override("separation", 8)
    refresh()


func _queue_refresh() -> void:
    if is_inside_tree() and not _refresh_queued:
        _refresh_queued = true
        refresh.call_deferred()


func refresh() -> void:
    _refresh_queued = false
    if not is_inside_tree():
        return
    Widgets.clear(self)
    _zones.clear()
    var kitchen: Dictionary = GameState.state.get("kitchen", {})
    if not kitchen.is_empty():
        _recipe_id = str(kitchen["recipe"])
    elif _recipe_id not in GameState.state.get("known_recipes", []):
        _recipe_id = str(GameState.state["known_recipes"][0])
    _recipe_controls(kitchen)
    var body: HBoxContainer = HBoxContainer.new()
    body.size_flags_vertical = Control.SIZE_EXPAND_FILL
    body.add_theme_constant_override("separation", 12)
    add_child(body)
    _counter = Control.new()
    _counter.name = "Counter"
    _counter.custom_minimum_size = Vector2(300, 160)
    _counter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _counter.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
    body.add_child(_counter)
    _background = TextureRect.new()
    _background.name = "CounterBackground"
    _background.texture = load(str(DataLoader.get_record("kitchen_layout")["background"])) as Texture2D
    _background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    _background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    _background.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _counter.add_child(_background)
    _background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    for zone_id: String in State.ZONES:
        var zone: Zone = _zone(zone_id, kitchen)
        _counter.add_child(zone)
        _zones[zone_id] = zone
    _counter.resized.connect(_layout_zones)
    _render_stock(body, kitchen)
    var actions: HBoxContainer = HBoxContainer.new()
    actions.add_theme_constant_override("separation", 10)
    add_child(actions)
    var finish: Button = Widgets.button("Finish", "ui_kitchen_finish", _finish, Conditions.can_finish_cooking())
    finish.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    actions.add_child(finish)
    actions.add_child(Widgets.button("Cancel", "ui_kitchen_cancel", EffectApplier.cancel_cooking, not kitchen.is_empty()))
    _layout_zones.call_deferred()


func _recipe_controls(kitchen: Dictionary) -> void:
    var row: HBoxContainer = HBoxContainer.new()
    row.add_theme_constant_override("separation", 12)
    add_child(row)
    var select: OptionButton = OptionButton.new()
    select.name = "Recipe"
    select.custom_minimum_size.y = 32
    select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var known: Array = GameState.state["known_recipes"]
    for recipe_id: String in known:
        select.add_item(str(DataLoader.get_record(recipe_id)["name"]))
    select.selected = known.find(_recipe_id)
    select.disabled = not kitchen.is_empty()
    select.item_selected.connect(func(index: int) -> void:
        _recipe_id = str(known[index])
        refresh())
    var required: PackedStringArray = []
    for ingredient: Dictionary in DataLoader.get_record(_recipe_id)["ingredients"]:
        required.append("%s ×%d" % [DataLoader.get_record(str(ingredient["item"]))["name"], int(ingredient["count"])])
    select.tooltip_text = Text.get_text("ui_kitchen_required", {"items": ", ".join(required)}) + "\n" + Text.get_text("ui_kitchen_help")
    row.add_child(select)
    var skill: Label = Widgets.label(Text.get_text("ui_home_skill", {"skill": GameState.state["cooking_skill"], "quality": Cooking.quality(int(GameState.state["cooking_skill"]))}), 13)
    skill.autowrap_mode = TextServer.AUTOWRAP_OFF
    skill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    row.add_child(skill)


func _render_stock(body: HBoxContainer, kitchen: Dictionary) -> void:
    var scroll: ScrollContainer = ScrollContainer.new()
    scroll.custom_minimum_size.x = 160
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    body.add_child(scroll)
    var stock: VBoxContainer = VBoxContainer.new()
    stock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    stock.add_theme_constant_override("separation", 8)
    scroll.add_child(stock)
    stock.add_child(Widgets.label(Text.get_text("ui_kitchen_ingredients"), 18))
    var count: int = 0
    for entry: Dictionary in GameState.state.get("inventory", []):
        var item_id: String = str(entry["item"])
        var item: Dictionary = DataLoader.get_record(item_id)
        if item.get("preparations", []).is_empty():
            continue
        var available: int = int(entry["count"]) - State.reserved(item_id, kitchen)
        if available <= 0:
            continue
        count += 1
        var token: Token = Token.new()
        token.name = item_id
        token.item_id = item_id
        token.custom_minimum_size = Vector2(64, 64)
        token.tooltip_text = str(item["name"])
        stock.add_child(token)
        stock.add_child(Widgets.label(str(item["name"]), 14))
        stock.add_child(Widgets.label(Text.get_text("ui_kitchen_available", {"count": available}), 13))
    if count == 0:
        stock.add_child(Widgets.label(Text.get_text("ui_kitchen_on_counter" if not kitchen.is_empty() else "ui_kitchen_buy_hint"), 14))


func _zone(zone_id: String, kitchen: Dictionary) -> Zone:
    var zone: Zone = Zone.new()
    zone.name = zone_id
    zone.tooltip_text = Text.get_text("ui_kitchen_" + zone_id)
    zone.accepts = func(item_id: String, entry_index: int) -> bool:
        return Conditions.can_prepare_ingredient(_recipe_id, item_id, zone_id, entry_index)
    zone.received = func(item_id: String, entry_index: int) -> void:
        finished.emit(EffectApplier.prepare_ingredient(_recipe_id, item_id, zone_id, entry_index))
    var tokens: HBoxContainer = HBoxContainer.new()
    tokens.name = "Tokens"
    tokens.mouse_filter = Control.MOUSE_FILTER_IGNORE
    tokens.add_theme_constant_override("separation", 2)
    zone.add_child(tokens)
    tokens.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    tokens.offset_left = 3
    tokens.offset_right = -3
    tokens.offset_top = 3
    tokens.offset_bottom = -3
    var names: PackedStringArray = []
    var entries: Array = kitchen.get("entries", [])
    for index: int in range(entries.size()):
        var entry: Dictionary = entries[index]
        if entry["zone"] != zone_id:
            continue
        var token: Token = Token.new()
        token.name = "Prepared" if index == 0 else "Prepared_" + str(index)
        token.item_id = str(entry["item"])
        token.entry_index = index
        token.steps.assign(entry["steps"])
        token.plated = zone_id == "plate"
        token.show_plate = false
        token.custom_minimum_size = Vector2(24, 24)
        token.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        token.size_flags_vertical = Control.SIZE_EXPAND_FILL
        token.tooltip_text = Appearance.ingredient_name(token.item_id, token.steps, token.plated)
        tokens.add_child(token)
        names.append(token.tooltip_text)
    zone.occupied = not names.is_empty()
    var label: Label = Widgets.label("\n".join(names), 12)
    label.name = "PreparedName" if zone.occupied else "ZoneHint"
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.add_theme_color_override("font_outline_color", Color(0.05, 0.025, 0.01))
    label.add_theme_constant_override("outline_size", 4)
    label.visible = zone.occupied
    zone.add_child(label)
    if zone_id != "plate":
        var action: Button = Button.new()
        action.name = "Process"
        action.text = Text.get_text("ui_kitchen_action_" + zone_id)
        action.visible = zone.occupied
        action.disabled = not Conditions.can_process_kitchen_zone(zone_id)
        action.flat = true
        action.add_theme_font_size_override("font_size", 13)
        action.add_theme_color_override("font_outline_color", Color.BLACK)
        action.add_theme_constant_override("outline_size", 3)
        action.pressed.connect(func() -> void: finished.emit(EffectApplier.process_kitchen_zone(zone_id)))
        zone.add_child(action)
    return zone


func image_rect() -> Rect2:
    if not is_instance_valid(_counter) or _background.texture == null:
        return Rect2()
    var dimensions: Vector2 = _background.texture.get_size()
    var scale: float = minf(_counter.size.x / dimensions.x, _counter.size.y / dimensions.y)
    var display_size: Vector2 = dimensions * scale
    return Rect2((_counter.size - display_size) * 0.5, display_size)


func _layout_zones() -> void:
    if not is_inside_tree() or not is_instance_valid(_counter):
        return
    var display: Rect2 = image_rect()
    var layout: Dictionary = DataLoader.get_record("kitchen_layout")["zones"]
    for zone_id: String in _zones:
        var rect: Array = layout[zone_id]["drop_rect"]
        var zone: Zone = _zones[zone_id]
        zone.position = display.position + Vector2(float(rect[0]), float(rect[1])) * display.size
        zone.size = Vector2(float(rect[2]), float(rect[3])) * display.size
        var label: Label = zone.get_node("PreparedName" if zone.occupied else "ZoneHint")
        label.position = Vector2(-5, zone.size.y + 4)
        label.size = Vector2(zone.size.x + 10, 76)
        if zone.has_node("Process"):
            var action: Button = zone.get_node("Process")
            action.position = Vector2(-4, -32)
            action.size = Vector2(zone.size.x + 8, 28)


func _finish() -> void:
    finished.emit(EffectApplier.finish_cooking())
