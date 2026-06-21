extends CanvasLayer

# ── Recipe definitions ────────────────────────────────────────────────────────
const RECIPES: Array[Dictionary] = [
	{
		id          = "pickaxe",
		name        = "Pickaxe",
		description = "Mine ore deposits and stones.",
		ingredients = [{"item": "Log", "qty": 1}, {"item": "Rock", "qty": 2}],
		result      = {"item": "Pickaxe", "qty": 1},
		unique      = true,
		prereq_task = -1,
	},
	{
		id          = "hammer",
		name        = "Hammer",
		description = "Used at the Anvil to forge metal plates. 25 uses.",
		ingredients = [{"item": "Iron Plate", "qty": 5}, {"item": "Log", "qty": 1}],
		result      = {"item": "Hammer", "qty": 1},
		unique      = false,
		prereq_task = -1,
	},
	{
		id          = "forge",
		name        = "Forge",
		description = "Smelts ores into heated metals. Fuel: Heated Coal.",
		ingredients = [
			{"item": "Rock",       "qty": 300},
			{"item": "Iron Plate", "qty": 10},
			{"item": "Heated Coal","qty": 1},
		],
		result      = {"item": "Forge", "qty": 1},
		unique      = true,
		placeable   = true,
		prereq_task = -1,
	},
	{
		id          = "extrusion_machine",
		name        = "Extrusion Machine",
		description = "Industrial extrusion. (Coming soon)",
		ingredients = [{"item": "Steel", "qty": 12}],
		result      = {"item": "Extrusion Machine", "qty": 1},
		unique      = true,
		placeable   = true,
		prereq_task = -1,
	},
	{
		id          = "anvil",
		name        = "Anvil",
		description = "Forge heated metals into plates with a hammer.",
		ingredients = [{"item": "Iron Plate", "qty": 15}],
		result      = {"item": "Anvil", "qty": 1},
		unique      = true,
		placeable   = true,
		prereq_task = -1,
	},
]

# ── State ─────────────────────────────────────────────────────────────────────
var _panel: Panel
var _inv_container: VBoxContainer
var _avail_container: VBoxContainer
var _all_container: VBoxContainer
var _tab: int = 0   # 0 = Available, 1 = All Recipes

func _ready() -> void:
	visible = false
	add_to_group("crafting_ui")
	_build_ui()
	Inventory.inventory_changed.connect(_refresh)

func open() -> void:
	visible = true
	GameManager.block_input = true
	_refresh()

# ── Build ─────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.45)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.position = Vector2(-290, -210)
	_panel.size     = Vector2(580, 420)
	add_child(_panel)

	# ── Left half: inventory ──────────────────────────────────────────────────
	var left := VBoxContainer.new()
	left.position      = Vector2(10, 10)
	left.size          = Vector2(260, 400)
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(left)

	var inv_title := Label.new()
	inv_title.text = "— INVENTORY —"
	inv_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inv_title.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3, 1))
	left.add_child(inv_title)
	left.add_child(HSeparator.new())

	var inv_scroll := ScrollContainer.new()
	inv_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(inv_scroll)

	_inv_container = VBoxContainer.new()
	_inv_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv_scroll.add_child(_inv_container)

	var divider := VSeparator.new()
	divider.position = Vector2(276, 10)
	divider.size     = Vector2(4, 400)
	_panel.add_child(divider)

	# ── Right half: crafting ──────────────────────────────────────────────────
	var right := VBoxContainer.new()
	right.position = Vector2(290, 10)
	right.size     = Vector2(280, 400)
	_panel.add_child(right)

	var craft_title := Label.new()
	craft_title.text = "— CRAFTING —"
	craft_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	craft_title.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3, 1))
	right.add_child(craft_title)

	var tab_row := HBoxContainer.new()
	right.add_child(tab_row)

	var avail_btn := Button.new()
	avail_btn.text = "Available"
	avail_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	avail_btn.pressed.connect(func(): _switch_tab(0))
	tab_row.add_child(avail_btn)

	var all_btn := Button.new()
	all_btn.text = "All Recipes"
	all_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	all_btn.pressed.connect(func(): _switch_tab(1))
	tab_row.add_child(all_btn)

	var craft_scroll := ScrollContainer.new()
	craft_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(craft_scroll)

	var craft_content := VBoxContainer.new()
	craft_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	craft_scroll.add_child(craft_content)

	_avail_container = VBoxContainer.new()
	_avail_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	craft_content.add_child(_avail_container)

	_all_container = VBoxContainer.new()
	_all_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_all_container.visible = false
	craft_content.add_child(_all_container)

	var hint := Label.new()
	hint.text = "[ ESC ] to close"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
	right.add_child(hint)

func _switch_tab(t: int) -> void:
	_tab = t
	_avail_container.visible = t == 0
	_all_container.visible   = t == 1

# ── Refresh ───────────────────────────────────────────────────────────────────

func _refresh() -> void:
	if not visible:
		return
	_refresh_inventory()
	_refresh_available()
	_refresh_all()

func _refresh_inventory() -> void:
	for c in _inv_container.get_children():
		c.queue_free()
	if Inventory.items.is_empty():
		var lbl := Label.new()
		lbl.text = "  No items."
		lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
		_inv_container.add_child(lbl)
		return
	for item in Inventory.items:
		var lbl := Label.new()
		lbl.text = "  %s  ×%d" % [item["name"], item.get("quantity", 1)]
		_inv_container.add_child(lbl)

func _refresh_available() -> void:
	for c in _avail_container.get_children():
		c.queue_free()
	var any_shown := false
	for recipe in RECIPES:
		if _is_locked(recipe):
			continue
		any_shown = true
		_avail_container.add_child(_make_recipe_card(recipe, true))
	if not any_shown:
		var lbl := Label.new()
		lbl.text = "  Nothing available to craft."
		lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
		_avail_container.add_child(lbl)

func _refresh_all() -> void:
	for c in _all_container.get_children():
		c.queue_free()
	for recipe in RECIPES:
		_all_container.add_child(_make_recipe_card(recipe, false))

func _is_locked(recipe: Dictionary) -> bool:
	if recipe.get("unique") == true and GameManager.get(recipe["id"] + "_crafted") == true:
		return true
	for ing in recipe.ingredients:
		if Inventory.get_item_count(ing.item) < ing.qty:
			return true
	return false

func _missing_reason(recipe: Dictionary) -> String:
	if recipe.get("unique") == true and GameManager.get(recipe["id"] + "_crafted") == true:
		return "Already crafted."
	var missing: Array[String] = []
	for ing in recipe.ingredients:
		var have := Inventory.get_item_count(ing.item)
		if have < ing.qty:
			missing.append("Need ×%d %s" % [ing.qty, ing.item])
	return "\n".join(missing)

func _make_recipe_card(recipe: Dictionary, compact: bool) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var col := VBoxContainer.new()
	col.offset_left = 6
	col.offset_right = -6
	card.add_child(col)

	var locked := _is_locked(recipe)
	var name_lbl := Label.new()
	name_lbl.text = recipe.name + (" [PLACE]" if recipe.get("placeable") else "")
	name_lbl.add_theme_color_override("font_color",
		Color(0.5, 0.5, 0.5, 1) if locked else Color(0.9, 0.85, 0.5, 1))
	col.add_child(name_lbl)

	for ing in recipe.ingredients:
		var ing_lbl := Label.new()
		ing_lbl.text = "  × %d %s" % [ing.qty, ing.item]
		ing_lbl.add_theme_font_size_override("font_size", 9)
		ing_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
		col.add_child(ing_lbl)

	if not compact or locked:
		var info_lbl := Label.new()
		if locked:
			info_lbl.text = _missing_reason(recipe)
			info_lbl.add_theme_color_override("font_color", Color(0.8, 0.3, 0.3, 1))
		else:
			info_lbl.text = recipe.get("description", "")
			info_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
		info_lbl.add_theme_font_size_override("font_size", 9)
		info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		col.add_child(info_lbl)

	if not locked:
		var btn := Button.new()
		btn.text = "CRAFT & PLACE" if recipe.get("placeable") else "CRAFT"
		btn.pressed.connect(func(): _do_craft(recipe))
		col.add_child(btn)

	col.add_child(HSeparator.new())
	return card

func _do_craft(recipe: Dictionary) -> void:
	if _is_locked(recipe):
		return
	for ing in recipe.ingredients:
		Inventory.remove_item(ing.item, ing.qty)
	var result_name: String = recipe.result.item
	var result_qty: int = recipe.result.qty
	Inventory.add_item({"name": result_name, "description": recipe.get("description", ""), "quantity": result_qty})
	GameManager.item_picked_up.emit(result_name, result_qty)
	GameManager.feedback_requested.emit("Crafted: %s" % result_name)
	# Advance task on pickaxe craft
	if recipe["id"] == "pickaxe":
		GameManager.task_index = max(GameManager.task_index, 2)
		GameManager.secondary_task_changed.emit()
	if recipe.get("unique", false):
		GameManager.set(recipe["id"] + "_crafted", true)
	# Trigger placement for machine recipes
	if recipe.get("placeable", false):
		visible = false
		GameManager.block_input = false
		GameManager.placement_requested.emit(result_name)
		return
	_refresh()

# ── Input ─────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		visible = false
		GameManager.block_input = false
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
			and (event as InputEventMouseButton).pressed:
		if not _panel.get_global_rect().has_point(event.position):
			visible = false
			GameManager.block_input = false
			get_viewport().set_input_as_handled()
