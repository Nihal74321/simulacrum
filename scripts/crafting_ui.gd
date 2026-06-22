extends CanvasLayer

# ── Recipe definitions ────────────────────────────────────────────────────────
const RECIPES: Array[Dictionary] = [
	{
		id          = "pickaxe",
		name        = "Pickaxe",
		category    = "gear",
		description = "Mine ore deposits and stones.",
		ingredients = [{"item": "Log", "qty": 1}, {"item": "Rock", "qty": 2}],
		result      = {"item": "Pickaxe", "qty": 1},
		unique      = true,
		prereq_task = -1,
	},
	{
		id          = "axe",
		name        = "Axe",
		category    = "gear",
		description = "Chop logs from trees.",
		ingredients = [{"item": "Log", "qty": 1}, {"item": "Rock", "qty": 2}],
		result      = {"item": "Axe", "qty": 1},
		unique      = true,
		prereq_task = -1,
	},
	{
		id          = "sickle",
		name        = "Sickle",
		category    = "gear",
		description = "Open chests.",
		ingredients = [{"item": "Iron Plate", "qty": 1}, {"item": "Rock", "qty": 4}, {"item": "Log", "qty": 1}],
		result      = {"item": "Sickle", "qty": 1},
		unique      = true,
		prereq_task = -1,
	},
	{
		id          = "broadaxe",
		name        = "Broadaxe",
		category    = "gear",
		description = "Improved combat axe.",
		ingredients = [{"item": "Iron Plate", "qty": 2}, {"item": "Rock", "qty": 20}, {"item": "Log", "qty": 2}],
		result      = {"item": "Broadaxe", "qty": 1},
		unique      = true,
		prereq_task = -1,
	},
	{
		id          = "great_axe",
		name        = "Great Axe",
		category    = "gear",
		description = "Devastating weapon. Requires Anvil — bring 12 Iron Plates.",
		ingredients = [{"item": "Iron Plate", "qty": 12}],
		result      = {"item": "Great Axe", "qty": 1},
		unique      = true,
		prereq_task = -1,
	},
	{
		id          = "crossbow",
		name        = "Crossbow",
		category    = "gear",
		description = "Ranged weapon. 10-tile range, 4 damage, 2s cooldown. 10% miss chance.",
		ingredients = [{"item": "Log", "qty": 50}, {"item": "Iron Plate", "qty": 10}, {"item": "String", "qty": 5}],
		result      = {"item": "Crossbow", "qty": 1},
		unique      = true,
		prereq_task = -1,
	},
	{
		id          = "hammer",
		name        = "Hammer",
		category    = "items",
		description = "Used at the Anvil to forge metal plates. 25 uses.",
		ingredients = [{"item": "Iron Plate", "qty": 5}, {"item": "Log", "qty": 1}],
		result      = {"item": "Hammer", "qty": 1},
		unique      = false,
		prereq_task = -1,
	},
	{
		id          = "forge",
		name        = "Forge",
		category    = "machines",
		description = "Smelts ores into plates using geothermal heat.",
		ingredients = [{"item": "Iron Plate", "qty": 4}, {"item": "Rock", "qty": 300}, {"item": "Coal", "qty": 50}],
		result      = {"item": "Forge", "qty": 1},
		unique      = false,
		placeable   = true,
		prereq_task = -1,
	},
	{
		id          = "workstation",
		name        = "Work Station",
		category    = "machines",
		description = "Exchange 4 Boon Fragments for a random boon.",
		ingredients = [{"item": "Iron Plate", "qty": 8}, {"item": "Log", "qty": 4}],
		result      = {"item": "Work Station", "qty": 1},
		unique      = true,
		placeable   = true,
		prereq_task = -1,
	},
	{
		id          = "extrusion_machine",
		name        = "Extrusion Machine",
		category    = "machines",
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
		category    = "machines",
		description = "Forge heated metals into plates with a hammer.",
		ingredients = [{"item": "Iron Plate", "qty": 15}],
		result      = {"item": "Anvil", "qty": 1},
		unique      = true,
		placeable   = true,
		prereq_task = -1,
	},
]

# Tools/weapons excluded from the crafting-UI inventory list (items only)
const GEAR_ITEMS: Array[String] = ["Pickaxe", "Axe", "Sickle", "Broadaxe", "Great Axe", "Crossbow"]

# ── State ─────────────────────────────────────────────────────────────────────
var _panel: Panel
var _inv_container: VBoxContainer
var _craft_container: VBoxContainer
var _craft_tab: String = "gear"   # gear / items / machines
var _inv_search: String = ""
var _craft_search: String = ""

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

	# 1.5× wider than the old 580px panel → 870px
	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.position = Vector2(-435, -230)
	_panel.size     = Vector2(870, 460)
	add_child(_panel)

	# ── Left: inventory (items only) ──────────────────────────────────────────
	var inv_title := Label.new()
	inv_title.text = "— INVENTORY —"
	inv_title.position = Vector2(10, 8)
	inv_title.size = Vector2(300, 18)
	inv_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inv_title.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3, 1))
	_panel.add_child(inv_title)

	var inv_search := LineEdit.new()
	inv_search.name = "InvSearch"
	inv_search.position = Vector2(10, 32)
	inv_search.size = Vector2(300, 24)
	inv_search.placeholder_text = "Search items…"
	inv_search.add_theme_font_size_override("font_size", 9)
	inv_search.text_changed.connect(func(t: String):
		_inv_search = t.strip_edges().to_lower()
		_refresh()
	)
	_panel.add_child(inv_search)

	var inv_scroll := ScrollContainer.new()
	inv_scroll.position = Vector2(10, 68)
	inv_scroll.size = Vector2(300, 382)
	inv_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(inv_scroll)
	_inv_container = VBoxContainer.new()
	_inv_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inv_container.add_theme_constant_override("separation", 3)
	inv_scroll.add_child(_inv_container)

	# Vertical divider
	var divider := ColorRect.new()
	divider.color = Color(0.4, 0.4, 0.4, 0.5)
	divider.position = Vector2(320, 10)
	divider.size     = Vector2(1, 440)
	_panel.add_child(divider)

	# ── Right: crafting ───────────────────────────────────────────────────────
	var craft_title := Label.new()
	craft_title.text = "— CRAFTING —"
	craft_title.position = Vector2(330, 8)
	craft_title.size = Vector2(530, 18)
	craft_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	craft_title.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3, 1))
	_panel.add_child(craft_title)

	# Category tabs
	var tabs := [["Gear", "gear"], ["Items", "items"], ["Machines", "machines"]]
	var tab_w: float = 172.0
	for ti in 3:
		var tb := Button.new()
		tb.text = tabs[ti][0]
		tb.position = Vector2(330.0 + ti * (tab_w + 3.0), 32)
		tb.size = Vector2(tab_w, 20)
		tb.add_theme_font_size_override("font_size", 9)
		var cat: String = tabs[ti][1]
		tb.pressed.connect(func():
			_craft_tab = cat
			_refresh()
		)
		_panel.add_child(tb)

	var craft_search := LineEdit.new()
	craft_search.name = "CraftSearch"
	craft_search.position = Vector2(330, 58)
	craft_search.size = Vector2(530, 24)
	craft_search.placeholder_text = "Search recipes…"
	craft_search.add_theme_font_size_override("font_size", 9)
	craft_search.text_changed.connect(func(t: String):
		_craft_search = t.strip_edges().to_lower()
		_refresh()
	)
	_panel.add_child(craft_search)

	var craft_scroll := ScrollContainer.new()
	craft_scroll.position = Vector2(330, 90)
	craft_scroll.size = Vector2(530, 340)
	craft_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(craft_scroll)
	_craft_container = VBoxContainer.new()
	_craft_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_craft_container.add_theme_constant_override("separation", 4)
	craft_scroll.add_child(_craft_container)

	var hint := Label.new()
	hint.text = "[ ESC ] to close"
	hint.position = Vector2(330, 436)
	hint.size = Vector2(530, 16)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_font_size_override("font_size", 8)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
	_panel.add_child(hint)

# ── Refresh ───────────────────────────────────────────────────────────────────

func _refresh() -> void:
	if not visible:
		return
	_refresh_inventory()
	_refresh_crafting()

func _refresh_inventory() -> void:
	for c in _inv_container.get_children():
		c.queue_free()
	var any := false
	for item in Inventory.items:
		var nm: String = item["name"]
		if nm in GEAR_ITEMS:
			continue  # tools/weapons excluded — items only
		if not _inv_search.is_empty() and not nm.to_lower().contains(_inv_search):
			continue
		var lbl := Label.new()
		lbl.text = "  %s  ×%d" % [nm, item.get("quantity", 1)]
		lbl.add_theme_font_size_override("font_size", 10)
		_inv_container.add_child(lbl)
		any = true
	if not any:
		var lbl := Label.new()
		lbl.text = "  No matching items." if not _inv_search.is_empty() else "  No items."
		lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
		_inv_container.add_child(lbl)

func _refresh_crafting() -> void:
	for c in _craft_container.get_children():
		c.queue_free()
	var any := false
	for recipe in RECIPES:
		if recipe.get("category", "") != _craft_tab:
			continue
		if not _craft_search.is_empty() and not String(recipe.name).to_lower().contains(_craft_search):
			continue
		_craft_container.add_child(_make_recipe_card(recipe))
		any = true
	if not any:
		var lbl := Label.new()
		lbl.text = "  No matching recipes." if not _craft_search.is_empty() else "  Nothing here."
		lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
		_craft_container.add_child(lbl)

func _is_locked(recipe: Dictionary) -> bool:
	if recipe.get("unique") == true and GameManager.get(recipe["id"] + "_crafted") == true:
		return true
	for ing in recipe.ingredients:
		if Inventory.get_item_count(ing.item) < ing.qty:
			return true
	return false

func _make_recipe_card(recipe: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	card.add_child(col)

	var locked := _is_locked(recipe)
	var already_crafted: bool = recipe.get("unique") == true and GameManager.get(recipe["id"] + "_crafted") == true

	# Header row: name + TRACK toggle
	var header := HBoxContainer.new()
	col.add_child(header)

	var name_lbl := Label.new()
	name_lbl.text = recipe.name + (" [PLACE]" if recipe.get("placeable") else "")
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_color_override("font_color",
		Color(0.5, 0.5, 0.5, 1) if locked else Color(0.9, 0.85, 0.5, 1))
	header.add_child(name_lbl)

	var tracked := GameManager.is_recipe_tracked(recipe.name)
	var track_btn := Button.new()
	track_btn.text = "TRACKING" if tracked else "TRACK"
	track_btn.add_theme_font_size_override("font_size", 8)
	if tracked:
		track_btn.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0, 1))
	track_btn.pressed.connect(func():
		GameManager.toggle_tracked_recipe(recipe)
		_refresh()
	)
	header.add_child(track_btn)

	# Ingredients with live have/need counts
	for ing in recipe.ingredients:
		var have := Inventory.get_item_count(ing.item)
		var ing_lbl := Label.new()
		ing_lbl.text = "  %s  %d/%d" % [ing.item, have, ing.qty]
		ing_lbl.add_theme_font_size_override("font_size", 9)
		ing_lbl.add_theme_color_override("font_color",
			Color(0.45, 0.85, 0.45, 1) if have >= ing.qty else Color(0.85, 0.45, 0.45, 1))
		col.add_child(ing_lbl)

	# Description / status
	var info_lbl := Label.new()
	if already_crafted:
		info_lbl.text = "Already crafted."
		info_lbl.add_theme_color_override("font_color", Color(0.8, 0.3, 0.3, 1))
	else:
		info_lbl.text = recipe.get("description", "")
		info_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
	info_lbl.add_theme_font_size_override("font_size", 9)
	info_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(info_lbl)

	var btn := Button.new()
	btn.text = "CRAFT & PLACE" if recipe.get("placeable") else "CRAFT"
	btn.disabled = locked
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
		close()
		GameManager.placement_requested.emit(result_name)
		return
	_refresh()

# ── Input ─────────────────────────────────────────────────────────────────────

func _clear_search() -> void:
	_inv_search = ""
	_craft_search = ""
	var inv_sb := _panel.get_node_or_null("InvSearch") as LineEdit
	if inv_sb != null:
		inv_sb.text = ""
	var craft_sb := _panel.get_node_or_null("CraftSearch") as LineEdit
	if craft_sb != null:
		craft_sb.text = ""

func close() -> void:
	visible = false
	GameManager.block_input = false
	_clear_search()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	# Don't act on keys typed into a search field (except ESC)
	if event is InputEventKey and get_viewport().gui_get_focus_owner() is LineEdit \
			and not event.is_action_pressed("ui_cancel"):
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
			and (event as InputEventMouseButton).pressed:
		if not _panel.get_global_rect().has_point(event.position):
			close()
			get_viewport().set_input_as_handled()
