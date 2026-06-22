extends CanvasLayer

# Gear items: tools + weapons that get equip/weapon-slot buttons
const GEAR_ITEMS: Array[String] = ["Pickaxe", "Axe", "Sickle", "Broadaxe", "Great Axe", "Crossbow"]
# Weapons: go to weapon slot, not hotbar
const WEAPONS: Array[String] = ["Great Axe", "Broadaxe", "Crossbow"]
# Boon item names — appear in gear tab with Equip button
const BOON_ITEMS: Array[String] = [
	"Boon of the Traveller", "Boon of Judgement", "Boon of the Hunter", "Iron Gauntlet",
]
# Items with no equip button at all
const UNEQUIPPABLE: Array[String] = [
	"Knowledge Fragment", "Boon Fragment",
	"Forge", "Anvil", "Extrusion Machine", "Work Station",
	"Hammer",
]

var _panel: Panel
var _inv_container: VBoxContainer   # GEAR
var _items_container: VBoxContainer # ITEMS
var _boon_container: VBoxContainer  # BOONS
var _selected_item: String = ""
var _selected_lbl: Label = null
var _tab: int = 0  # 0=GEAR 1=ITEMS 2=BOONS
# Hotbar drag-swap state
var _hb_drag_slot: int = -1
# Slot that just received an assignment — flashes green
var _just_assigned_slot: int = -1
# Search filter (applies to Gear/Items tabs)
var _search_text: String = ""

func _ready() -> void:
	visible = false
	add_to_group("inventory_ui")
	_build_ui()
	Inventory.inventory_changed.connect(_refresh)
	GameManager.hotbar_changed.connect(_refresh)

func _build_ui() -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.45)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.position = Vector2(-320, -240)
	_panel.size = Vector2(640, 480)
	add_child(_panel)

	# ── Title ────────────────────────────────────────────────────────────────
	var title := Label.new()
	title.text = "— SIMULACRUM —"
	title.position = Vector2(0, 8)
	title.size = Vector2(640, 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3, 1))
	_panel.add_child(title)

	# Vertical divider
	var div := ColorRect.new()
	div.color = Color(0.4, 0.4, 0.4, 0.5)
	div.position = Vector2(310, 30)
	div.size = Vector2(1, 440)
	_panel.add_child(div)

	# ── Left: 3-tab buttons ───────────────────────────────────────────────────
	var tab_w: float = 99.0
	var tab_names := ["Gear", "Items", "Boons"]
	for ti in 3:
		var tb := Button.new()
		tb.text = tab_names[ti]
		tb.position = Vector2(4.0 + ti * (tab_w + 2.0), 32)
		tb.size = Vector2(tab_w, 18)
		tb.add_theme_font_size_override("font_size", 8)
		var idx := ti
		tb.pressed.connect(func():
			_tab = idx
			_refresh()
		)
		_panel.add_child(tb)

	# Search box (global filter across Gear / Items / Boons)
	var search := LineEdit.new()
	search.name = "SearchBox"
	search.position = Vector2(4, 54)
	search.size = Vector2(302, 22)
	search.placeholder_text = "Search…"
	search.add_theme_font_size_override("font_size", 9)
	search.text_changed.connect(func(t: String):
		_search_text = t.strip_edges().to_lower()
		_refresh()
	)
	# ESC in search box releases focus (doesn't close the whole UI)
	search.gui_input.connect(func(event: InputEvent):
		if event.is_action_pressed("ui_cancel"):
			search.release_focus()
			get_viewport().set_input_as_handled()
	)
	_panel.add_child(search)

	# GEAR scroll — generous gap below the search box
	var gear_scroll := ScrollContainer.new()
	gear_scroll.name = "GearScroll"
	gear_scroll.position = Vector2(4, 84)
	gear_scroll.size = Vector2(302, 356)
	_panel.add_child(gear_scroll)
	_inv_container = VBoxContainer.new()
	_inv_container.name = "GearContainer"
	_inv_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inv_container.add_theme_constant_override("separation", 4)
	gear_scroll.add_child(_inv_container)

	# ITEMS scroll
	var items_scroll := ScrollContainer.new()
	items_scroll.name = "ItemsScroll"
	items_scroll.position = Vector2(4, 84)
	items_scroll.size = Vector2(302, 356)
	items_scroll.visible = false
	_panel.add_child(items_scroll)
	_items_container = VBoxContainer.new()
	_items_container.name = "ItemsContainer"
	_items_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_items_container.add_theme_constant_override("separation", 4)
	items_scroll.add_child(_items_container)

	# BOONS scroll
	var boon_scroll := ScrollContainer.new()
	boon_scroll.name = "BoonScroll"
	boon_scroll.position = Vector2(4, 84)
	boon_scroll.size = Vector2(302, 356)
	boon_scroll.visible = false
	_panel.add_child(boon_scroll)
	_boon_container = VBoxContainer.new()
	_boon_container.name = "BoonContainer"
	_boon_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	boon_scroll.add_child(_boon_container)

	# ── Right: Equipment + Hotbar ─────────────────────────────────────────────
	var right_title := Label.new()
	right_title.text = "Equipment"
	right_title.position = Vector2(316, 32)
	right_title.size = Vector2(318, 16)
	right_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right_title.add_theme_font_size_override("font_size", 9)
	right_title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	_panel.add_child(right_title)

	# Weapon slot (centred)
	const SLOT_W: float = 230.0
	const SLOT_H: float = 90.0
	const GRID_X: float = 320.0 + (318.0 - 230.0) * 0.5
	const GRID_Y: float = 55.0
	var weapon_bg := ColorRect.new()
	weapon_bg.position = Vector2(GRID_X, GRID_Y)
	weapon_bg.size = Vector2(SLOT_W, SLOT_H)
	weapon_bg.color = Color(0.08, 0.08, 0.08, 0.9)
	_panel.add_child(weapon_bg)
	var weapon_lbl := Label.new()
	weapon_lbl.name = "ArmorSlot3"
	weapon_lbl.position = Vector2(GRID_X, GRID_Y)
	weapon_lbl.size = Vector2(SLOT_W, SLOT_H)
	weapon_lbl.text = "Weapon"
	weapon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	weapon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	weapon_lbl.add_theme_font_size_override("font_size", 13)
	weapon_lbl.add_theme_color_override("font_color", Color(0.3, 0.3, 0.3, 1))
	_panel.add_child(weapon_lbl)

	# Boon slot below weapon
	var boon_y: float = GRID_Y + SLOT_H + 10.0
	var boon_bg := ColorRect.new()
	boon_bg.name = "BoonSlotBg"
	boon_bg.position = Vector2(GRID_X, boon_y)
	boon_bg.size = Vector2(SLOT_W, SLOT_H)
	boon_bg.color = Color(0.08, 0.08, 0.08, 0.9)
	_panel.add_child(boon_bg)
	var boon_lbl := Label.new()
	boon_lbl.name = "ActiveBoonLabel"
	boon_lbl.position = Vector2(GRID_X, boon_y)
	boon_lbl.size = Vector2(SLOT_W, SLOT_H)
	boon_lbl.text = "No Boon"
	boon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	boon_lbl.add_theme_font_size_override("font_size", 11)
	boon_lbl.add_theme_color_override("font_color", Color(0.3, 0.3, 0.3, 1))
	_panel.add_child(boon_lbl)

	# Hotbar section
	var hb_title := Label.new()
	hb_title.text = "Hotbar"
	hb_title.position = Vector2(316, 358)
	hb_title.size = Vector2(318, 16)
	hb_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hb_title.add_theme_font_size_override("font_size", 9)
	hb_title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	_panel.add_child(hb_title)

	# 5 hotbar slot buttons
	const HB_SLOT_W: float = 52.0
	const HB_SLOT_H: float = 44.0
	const HB_GAP: float = 5.0
	var hb_total: float = 5.0 * HB_SLOT_W + 4.0 * HB_GAP
	var hb_start_x: float = 316.0 + (318.0 - hb_total) * 0.5
	for i in 5:
		var hb_x: float = hb_start_x + i * (HB_SLOT_W + HB_GAP)
		var hb_bg := ColorRect.new()
		hb_bg.name = "HBSlotBg%d" % i
		hb_bg.position = Vector2(hb_x, 390.0)
		hb_bg.size = Vector2(HB_SLOT_W, HB_SLOT_H)
		hb_bg.color = Color(0.12, 0.12, 0.12, 0.9)
		_panel.add_child(hb_bg)
		var hb_item_lbl := Label.new()
		hb_item_lbl.name = "HBItemLbl%d" % i
		hb_item_lbl.position = Vector2(hb_x, 390.0)
		hb_item_lbl.size = Vector2(HB_SLOT_W, HB_SLOT_H - 14)
		hb_item_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hb_item_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hb_item_lbl.add_theme_font_size_override("font_size", 6)
		hb_item_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		_panel.add_child(hb_item_lbl)
		var hb_num := Label.new()
		hb_num.position = Vector2(hb_x, 390.0 + HB_SLOT_H - 14)
		hb_num.size = Vector2(HB_SLOT_W, 14)
		hb_num.text = str(i + 1)
		hb_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hb_num.add_theme_font_size_override("font_size", 7)
		hb_num.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
		_panel.add_child(hb_num)
		# Invisible button over slot to capture clicks (item assign OR drag-swap)
		var hb_btn := Button.new()
		hb_btn.position = Vector2(hb_x, 390.0)
		hb_btn.size = Vector2(HB_SLOT_W, HB_SLOT_H)
		hb_btn.flat = true
		hb_btn.modulate.a = 0.0
		var slot_idx := i
		hb_btn.pressed.connect(func():
			if not _selected_item.is_empty():
				_assign_to_hotbar(slot_idx)
			else:
				_hotbar_slot_clicked(slot_idx)
		)
		_panel.add_child(hb_btn)

	# Close hint
	var hint := Label.new()
	hint.text = "[ ESC ] to close"
	hint.position = Vector2(0, 456)
	hint.size = Vector2(640, 16)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_font_size_override("font_size", 8)
	hint.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4, 1))
	_panel.add_child(hint)

func open() -> void:
	visible = true
	GameManager.block_input = true
	_refresh()
	# Auto-focus search box
	var sb := _panel.get_node_or_null("SearchBox") as LineEdit
	if sb != null:
		sb.grab_focus()

func _auto_equip(item_name: String) -> void:
	# Find first empty slot; if none, use currently selected slot
	var target_slot := GameManager.hotbar_selected
	for i in 5:
		if GameManager.hotbar[i].is_empty():
			target_slot = i
			break
	_assign_to_hotbar_slot(item_name, target_slot)

func _hotbar_slot_clicked(slot: int) -> void:
	if _hb_drag_slot == -1:
		# First click: select this slot for swap
		_hb_drag_slot = slot
		_refresh()
	elif _hb_drag_slot == slot:
		# Same slot: deselect
		_hb_drag_slot = -1
		_refresh()
	else:
		# Second click on different slot: swap
		var tmp: String = GameManager.hotbar[_hb_drag_slot]
		GameManager.hotbar[_hb_drag_slot] = GameManager.hotbar[slot]
		GameManager.hotbar[slot] = tmp
		GameManager.hotbar_changed.emit()
		_hb_drag_slot = -1
		_refresh()

func _select_item(item_name: String) -> void:
	# Toggle selection; clears any hotbar-swap selection
	_selected_item = "" if _selected_item == item_name else item_name
	_hb_drag_slot = -1
	_refresh()

func _assign_to_hotbar(slot: int) -> void:
	if _selected_item.is_empty():
		return
	if _selected_item in UNEQUIPPABLE:
		GameManager.feedback_requested.emit("Can't equip that.")
		return
	_assign_to_hotbar_slot(_selected_item, slot)
	_selected_item = ""
	_selected_lbl = null
	_hb_drag_slot = -1
	# Flash the destination slot green, then clear after a moment
	_just_assigned_slot = slot
	get_tree().create_timer(1.0).timeout.connect(func():
		if _just_assigned_slot == slot:
			_just_assigned_slot = -1
			if visible:
				_refresh()
	)
	_refresh()

func _assign_to_hotbar_slot(item_name: String, slot: int) -> void:
	for i in 5:
		if GameManager.hotbar[i] == item_name:
			GameManager.hotbar[i] = ""
	GameManager.hotbar[slot] = item_name
	GameManager.hotbar_changed.emit()

func _refresh() -> void:
	if _inv_container == null:
		return

	# Tab visibility
	_panel.get_node_or_null("GearScroll").visible = (_tab == 0)
	_panel.get_node_or_null("ItemsScroll").visible = (_tab == 1)
	_panel.get_node_or_null("BoonScroll").visible = (_tab == 2)

	# ── BOONS tab ─────────────────────────────────────────────────────────────
	for c in _boon_container.get_children():
		c.queue_free()
	if GameManager.active_boons.is_empty():
		var bl := Label.new()
		bl.text = "  No boons active."
		bl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
		bl.add_theme_font_size_override("font_size", 9)
		_boon_container.add_child(bl)
	else:
		for b in GameManager.active_boons:
			var brow := HBoxContainer.new()
			_boon_container.add_child(brow)
			var bl := Label.new()
			bl.text = "  ★ " + str(b)
			bl.add_theme_color_override("font_color", Color(0.7, 0.5, 1.0, 1))
			bl.add_theme_font_size_override("font_size", 10)
			bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			brow.add_child(bl)
			var unequip_btn := Button.new()
			unequip_btn.text = "Remove"
			unequip_btn.add_theme_font_size_override("font_size", 8)
			unequip_btn.disabled = GameManager.dungeon_active
			unequip_btn.tooltip_text = "Cannot remove boons during a Simulacrum." if GameManager.dungeon_active else ""
			var cap_b := b
			unequip_btn.pressed.connect(func():
				GameManager.remove_boon(cap_b)
				_refresh()
			)
			brow.add_child(unequip_btn)
	var frags_lbl := Label.new()
	frags_lbl.text = "  Boon Fragments: %d" % GameManager.boon_fragments
	frags_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1))
	frags_lbl.add_theme_font_size_override("font_size", 9)
	_boon_container.add_child(frags_lbl)

	# ── GEAR tab ──────────────────────────────────────────────────────────────
	for c in _inv_container.get_children():
		c.queue_free()
	var any_gear := false
	for item in Inventory.items:
		if item["name"] in GEAR_ITEMS and _matches_search(item["name"]):
			_build_item_row(_inv_container, item, true)
			any_gear = true
		elif item["name"] in BOON_ITEMS and _matches_search(item["name"]):
			_build_boon_inv_row(_inv_container, item["name"])
			any_gear = true
	# When searching, also show boon matches inline in gear tab
	if not _search_text.is_empty():
		for b in GameManager.active_boons:
			if b.to_lower().contains(_search_text):
				var bl := Label.new()
				bl.text = "  ★ %s (boon)" % b
				bl.add_theme_color_override("font_color", Color(0.7, 0.5, 1.0, 1))
				bl.add_theme_font_size_override("font_size", 10)
				_inv_container.add_child(bl)
				any_gear = true
	if not any_gear:
		var el := Label.new()
		el.text = "  No matching results." if not _search_text.is_empty() else "  No gear yet."
		el.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
		_inv_container.add_child(el)

	# ── ITEMS tab ─────────────────────────────────────────────────────────────
	for c in _items_container.get_children():
		c.queue_free()
	var any_items := false
	for item in Inventory.items:
		if item["name"] not in GEAR_ITEMS and item["name"] not in BOON_ITEMS \
				and _matches_search(item["name"]):
			_build_item_row(_items_container, item, false)
			any_items = true
	# When searching, also show boon matches inline in items tab
	if not _search_text.is_empty():
		for b in GameManager.active_boons:
			if b.to_lower().contains(_search_text):
				var bl := Label.new()
				bl.text = "  ★ %s (boon)" % b
				bl.add_theme_color_override("font_color", Color(0.7, 0.5, 1.0, 1))
				bl.add_theme_font_size_override("font_size", 10)
				_items_container.add_child(bl)
				any_items = true
	if not any_items:
		var el := Label.new()
		el.text = "  No matching results." if not _search_text.is_empty() else "  No items yet."
		el.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
		_items_container.add_child(el)

	# Refresh hotbar drag highlight
	const HB_SLOT_W2: float = 52.0
	const HB_SLOT_H2: float = 44.0
	const HB_GAP2: float = 5.0
	var hb_total2: float = 5.0 * HB_SLOT_W2 + 4.0 * HB_GAP2
	var hb_start2: float = 316.0 + (318.0 - hb_total2) * 0.5
	for si in 5:
		var bg2 := _panel.get_node_or_null("HBSlotBg%d" % si) as ColorRect
		if bg2 != null:
			if si == _hb_drag_slot:
				bg2.color = Color(0.35, 0.25, 0.05, 0.9)  # orange tint = selected for swap
			else:
				bg2.color = Color(0.12, 0.12, 0.12, 0.9)

	# Refresh active boon label on right panel
	var active_boon_lbl := _panel.get_node_or_null("ActiveBoonLabel") as Label
	if active_boon_lbl != null:
		if GameManager.active_boons.is_empty():
			active_boon_lbl.text = "No Boon"
			active_boon_lbl.add_theme_color_override("font_color", Color(0.3, 0.3, 0.3, 1))
		else:
			active_boon_lbl.text = "\n".join(GameManager.active_boons)
			active_boon_lbl.add_theme_color_override("font_color", Color(0.7, 0.4, 1.0, 1))

	# Refresh weapon slot label on right panel (ArmorSlot3 = Weapon slot)
	var weapon_slot_lbl := _panel.get_node_or_null("ArmorSlot3") as Label
	if weapon_slot_lbl != null:
		if not GameManager.equipped_weapon.is_empty():
			weapon_slot_lbl.text = GameManager.equipped_weapon
			weapon_slot_lbl.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3, 1))
		else:
			weapon_slot_lbl.text = "Weapon"
			weapon_slot_lbl.add_theme_color_override("font_color", Color(0.3, 0.3, 0.3, 1))

	# Refresh hotbar slot displays
	const HB_SLOT_W: float = 52.0
	const HB_SLOT_H: float = 44.0
	for i in 5:
		var bg := _panel.get_node("HBSlotBg%d" % i) as ColorRect
		var lbl2 := _panel.get_node("HBItemLbl%d" % i) as Label
		if bg == null or lbl2 == null:
			continue
		var slot_item: String = GameManager.hotbar[i]
		var is_sel: bool = (i == GameManager.hotbar_selected)
		if i == _just_assigned_slot:
			bg.color = Color(0.15, 0.55, 0.2, 0.95)  # green flash = just assigned
		elif i == _hb_drag_slot:
			bg.color = Color(0.35, 0.25, 0.05, 0.9)   # orange = selected for swap
		elif is_sel:
			bg.color = Color(0.25, 0.22, 0.08, 0.9)
		else:
			bg.color = Color(0.12, 0.12, 0.12, 0.9)
		if slot_item.is_empty():
			lbl2.text = ""
		else:
			lbl2.text = slot_item.left(10)
			lbl2.add_theme_color_override("font_color", Color(1, 1, 1, 1))

func _matches_search(item_name: String) -> bool:
	return _search_text.is_empty() or item_name.to_lower().contains(_search_text)

func _build_item_row(container: VBoxContainer, item: Dictionary, show_equip: bool) -> void:
	var item_name: String = item["name"]
	var qty: int = item.get("quantity", 1)
	var is_weapon := item_name in WEAPONS
	var in_hotbar := GameManager.hotbar.has(item_name)

	var row := HBoxContainer.new()
	container.add_child(row)

	var hotbar_slot := -1
	for j in 5:
		if GameManager.hotbar[j] == item_name:
			hotbar_slot = j; break

	# Clickable name — clicking selects the item (highlights green) for hotbar assignment
	var lbl := Button.new()
	lbl.flat = true
	lbl.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if hotbar_slot >= 0:
		lbl.text = "  [%d] %s ×%d" % [hotbar_slot + 1, item_name, qty]
		lbl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45, 1))
	else:
		lbl.text = "  %s ×%d" % [item_name, qty]
		lbl.add_theme_color_override("font_color", Color(0.88, 0.88, 0.88, 1))
	if item_name == _selected_item:
		lbl.add_theme_color_override("font_color", Color(0.3, 0.95, 0.4, 1))  # green = selected
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.tooltip_text = item.get("description", "")
	if show_equip and item_name not in UNEQUIPPABLE and not is_weapon:
		var cap_sel := item_name
		lbl.pressed.connect(func(): _select_item(cap_sel))
	row.add_child(lbl)

	if not show_equip:
		return

	if in_hotbar and item_name not in UNEQUIPPABLE:
		var unbtn := Button.new()
		unbtn.text = "×"
		unbtn.add_theme_font_size_override("font_size", 8)
		var cap := item_name
		unbtn.pressed.connect(func():
			for k in 5:
				if GameManager.hotbar[k] == cap: GameManager.hotbar[k] = ""
			GameManager.hotbar_changed.emit(); _refresh()
		)
		row.add_child(unbtn)

	if is_weapon:
		var equipped: bool = GameManager.equipped_weapon == item_name
		var wbtn := Button.new()
		wbtn.text = "Unequip" if equipped else "Equip"
		wbtn.add_theme_font_size_override("font_size", 8)
		var cap := item_name
		wbtn.pressed.connect(func():
			GameManager.equipped_weapon = "" if GameManager.equipped_weapon == cap else cap
			_refresh()
		)
		row.add_child(wbtn)
	elif item_name not in UNEQUIPPABLE:
		var btn := Button.new()
		btn.text = "Equip"
		btn.add_theme_font_size_override("font_size", 8)
		var cap := item_name
		btn.pressed.connect(func(): _auto_equip(cap); _refresh())
		row.add_child(btn)

func _build_boon_inv_row(container: VBoxContainer, boon_name: String) -> void:
	var row := HBoxContainer.new()
	container.add_child(row)
	var lbl := Label.new()
	lbl.text = "  ◆ %s" % boon_name
	lbl.add_theme_color_override("font_color", Color(0.75, 0.5, 1.0, 1.0))
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var equip_btn := Button.new()
	equip_btn.text = "Equip"
	equip_btn.add_theme_font_size_override("font_size", 8)
	equip_btn.disabled = GameManager.dungeon_active
	var cap := boon_name
	equip_btn.pressed.connect(func():
		GameManager.grant_boon(cap)
		_refresh()
	)
	row.add_child(equip_btn)

func _clear_search() -> void:
	_search_text = ""
	var sb := _panel.get_node_or_null("SearchBox") as LineEdit
	if sb != null:
		sb.text = ""
	# Also clear any pending item/slot selection highlight
	_selected_item = ""
	_selected_lbl = null
	_hb_drag_slot = -1
	_just_assigned_slot = -1

func _close() -> void:
	visible = false
	GameManager.block_input = false
	_clear_search()

func _unhandled_input(event: InputEvent) -> void:
	# Don't let the toggle key fire while typing in the search field
	if event is InputEventKey and get_viewport().gui_get_focus_owner() is LineEdit \
			and not event.is_action_pressed("ui_cancel"):
		return
	if event.is_action_pressed("toggle_inventory"):
		visible = !visible
		GameManager.block_input = visible
		if visible:
			_refresh()
			var sb2 := _panel.get_node_or_null("SearchBox") as LineEdit
			if sb2 != null:
				sb2.grab_focus()
		else:
			_clear_search()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and visible:
		_close()
		get_viewport().set_input_as_handled()
	elif visible and event is InputEventMouseButton \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
			and (event as InputEventMouseButton).pressed:
		var vp_size := get_viewport().get_visible_rect().size
		var panel_rect := Rect2(vp_size * 0.5 + Vector2(-320, -240), Vector2(640, 480))
		if not panel_rect.has_point((event as InputEventMouseButton).position):
			_close()
			get_viewport().set_input_as_handled()
