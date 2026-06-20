extends CanvasLayer

# Items that cannot go in the hotbar
const UNEQUIPPABLE: Array[String] = [
	"Knowledge Fragment", "Sword", "Spear",
	"Forge", "Anvil", "Extrusion Machine",
]

# Weapons that go in the weapon slot (not hotbar)
const WEAPONS: Array[String] = ["Sword", "Spear"]

var _panel: Panel
var _inv_container: VBoxContainer
var _boon_container: VBoxContainer
var _selected_item: String = ""  # item selected for hotbar assignment
var _selected_lbl: Label = null
var _show_boons: bool = false    # left panel tab toggle

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

	# ── Left: tab buttons ────────────────────────────────────────────────────
	var tab_inv := Button.new()
	tab_inv.name = "TabInv"
	tab_inv.text = "Items"
	tab_inv.position = Vector2(4, 32)
	tab_inv.size = Vector2(148, 18)
	tab_inv.flat = false
	tab_inv.add_theme_font_size_override("font_size", 8)
	tab_inv.pressed.connect(func():
		_show_boons = false
		_refresh()
	)
	_panel.add_child(tab_inv)

	var tab_boon := Button.new()
	tab_boon.name = "TabBoon"
	tab_boon.text = "Boons"
	tab_boon.position = Vector2(158, 32)
	tab_boon.size = Vector2(148, 18)
	tab_boon.flat = false
	tab_boon.add_theme_font_size_override("font_size", 8)
	tab_boon.pressed.connect(func():
		_show_boons = true
		_refresh()
	)
	_panel.add_child(tab_boon)

	var inv_scroll := ScrollContainer.new()
	inv_scroll.position = Vector2(4, 52)
	inv_scroll.size = Vector2(302, 388)
	_panel.add_child(inv_scroll)

	_inv_container = VBoxContainer.new()
	_inv_container.name = "InvContainer"
	_inv_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv_scroll.add_child(_inv_container)

	var boon_scroll := ScrollContainer.new()
	boon_scroll.name = "BoonScroll"
	boon_scroll.position = Vector2(4, 52)
	boon_scroll.size = Vector2(302, 388)
	boon_scroll.visible = false
	_panel.add_child(boon_scroll)

	_boon_container = VBoxContainer.new()
	_boon_container.name = "BoonContainer"
	_boon_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	boon_scroll.add_child(_boon_container)

	# ── Right: Armor / Boons + Hotbar ────────────────────────────────────────
	var right_title := Label.new()
	right_title.text = "Armor / Boons"
	right_title.position = Vector2(316, 32)
	right_title.size = Vector2(318, 16)
	right_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right_title.add_theme_font_size_override("font_size", 9)
	right_title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	_panel.add_child(right_title)

	# Armor slots: 2×2 grid (Helmet, Chest, Boots, Weapon)
	const SLOT_NAMES: Array = ["Helmet", "Chest", "Boots", "Weapon"]
	const SLOT_W: float = 110.0
	const SLOT_H: float = 90.0
	const SLOT_GAP: float = 10.0
	const GRID_X: float = 330.0
	const GRID_Y: float = 55.0
	for idx in 4:
		var col := idx % 2
		var row := idx / 2
		var sx: float = GRID_X + col * (SLOT_W + SLOT_GAP)
		var sy: float = GRID_Y + row * (SLOT_H + SLOT_GAP)
		var slot_bg := ColorRect.new()
		slot_bg.position = Vector2(sx, sy)
		slot_bg.size = Vector2(SLOT_W, SLOT_H)
		slot_bg.color = Color(0.08, 0.08, 0.08, 0.9)
		_panel.add_child(slot_bg)
		var slot_lbl := Label.new()
		slot_lbl.name = "ArmorSlot%d" % idx
		slot_lbl.position = Vector2(sx, sy)
		slot_lbl.size = Vector2(SLOT_W, SLOT_H)
		slot_lbl.text = SLOT_NAMES[idx]
		slot_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slot_lbl.add_theme_font_size_override("font_size", 13)
		slot_lbl.add_theme_color_override("font_color", Color(0.3, 0.3, 0.3, 1))
		_panel.add_child(slot_lbl)

	# Boon slot (centred below armor grid)
	var boon_x: float = GRID_X + (SLOT_W + SLOT_GAP) * 0.5 - 60.0
	var boon_y: float = GRID_Y + 2.0 * (SLOT_H + SLOT_GAP)
	var boon_bg := ColorRect.new()
	boon_bg.position = Vector2(boon_x, boon_y)
	boon_bg.size = Vector2(120.0, 80.0)
	boon_bg.color = Color(0.08, 0.08, 0.08, 0.9)
	_panel.add_child(boon_bg)
	var boon_lbl := Label.new()
	boon_lbl.position = Vector2(boon_x, boon_y)
	boon_lbl.size = Vector2(120.0, 80.0)
	boon_lbl.text = "Boon"
	boon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	boon_lbl.add_theme_font_size_override("font_size", 13)
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

	var hb_hint := Label.new()
	hb_hint.text = "← click item, then click slot to assign"
	hb_hint.position = Vector2(316, 374)
	hb_hint.size = Vector2(318, 14)
	hb_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hb_hint.add_theme_font_size_override("font_size", 7)
	hb_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
	_panel.add_child(hb_hint)

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
		# Invisible button over slot to capture clicks
		var hb_btn := Button.new()
		hb_btn.position = Vector2(hb_x, 390.0)
		hb_btn.size = Vector2(HB_SLOT_W, HB_SLOT_H)
		hb_btn.flat = true
		hb_btn.modulate.a = 0.0
		var slot_idx := i
		hb_btn.pressed.connect(func(): _assign_to_hotbar(slot_idx))
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

func _auto_equip(item_name: String) -> void:
	# Find first empty slot; if none, use currently selected slot
	var target_slot := GameManager.hotbar_selected
	for i in 5:
		if GameManager.hotbar[i].is_empty():
			target_slot = i
			break
	_assign_to_hotbar_slot(item_name, target_slot)

func _assign_to_hotbar(slot: int) -> void:
	if _selected_item.is_empty():
		return
	if _selected_item in UNEQUIPPABLE:
		GameManager.feedback_requested.emit("Can't equip that.")
		return
	_assign_to_hotbar_slot(_selected_item, slot)
	_selected_item = ""
	_selected_lbl = null
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
	var boon_scroll := _panel.get_node_or_null("BoonScroll") as ScrollContainer
	if boon_scroll != null:
		_inv_container.get_parent().visible = not _show_boons
		boon_scroll.visible = _show_boons

	# Boon tab content
	if _boon_container != null:
		for c in _boon_container.get_children():
			c.queue_free()
		var boon_lbl := Label.new()
		boon_lbl.text = "  No boons found yet."
		boon_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
		boon_lbl.add_theme_font_size_override("font_size", 9)
		_boon_container.add_child(boon_lbl)

	# Inventory list
	for c in _inv_container.get_children():
		c.queue_free()

	if Inventory.items.is_empty():
		var lbl := Label.new()
		lbl.text = "  No items."
		lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
		_inv_container.add_child(lbl)
	else:
		for item in Inventory.items:
			var item_name: String = item["name"]
			var qty: int = item.get("quantity", 1)
			var in_hotbar := GameManager.hotbar.has(item_name)
			var is_weapon := item_name in WEAPONS

			var row := HBoxContainer.new()
			_inv_container.add_child(row)

			var lbl := Label.new()
			var hotbar_slot := -1
			for j in 5:
				if GameManager.hotbar[j] == item_name:
					hotbar_slot = j
					break
			if hotbar_slot >= 0:
				lbl.text = "  [%d] %s ×%d" % [hotbar_slot + 1, item_name, qty]
				lbl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45, 1))
			else:
				lbl.text = "  %s ×%d" % [item_name, qty]
				lbl.add_theme_color_override("font_color", Color(0.88, 0.88, 0.88, 1))
			if item_name == _selected_item:
				lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2, 1))
			lbl.add_theme_font_size_override("font_size", 10)
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl.tooltip_text = item.get("description", "")
			row.add_child(lbl)

			# Unequip from hotbar button
			if in_hotbar and item_name not in UNEQUIPPABLE:
				var unbtn := Button.new()
				unbtn.text = "×"
				unbtn.add_theme_font_size_override("font_size", 8)
				var captured := item_name
				unbtn.pressed.connect(func():
					for k in 5:
						if GameManager.hotbar[k] == captured:
							GameManager.hotbar[k] = ""
					GameManager.hotbar_changed.emit()
					_refresh()
				)
				row.add_child(unbtn)

			if is_weapon:
				# Weapon slot button
				var equipped: bool = GameManager.equipped_weapon == item_name
				var wbtn := Button.new()
				wbtn.text = "Unequip" if equipped else "Equip Weapon"
				wbtn.add_theme_font_size_override("font_size", 8)
				var captured := item_name
				wbtn.pressed.connect(func():
					if GameManager.equipped_weapon == captured:
						GameManager.equipped_weapon = ""
					else:
						GameManager.equipped_weapon = captured
					_refresh()
				)
				row.add_child(wbtn)
			elif item_name not in UNEQUIPPABLE:
				# Equip to hotbar — auto-finds first free slot
				var btn := Button.new()
				btn.text = "Equip"
				btn.add_theme_font_size_override("font_size", 8)
				var captured := item_name
				btn.pressed.connect(func():
					_auto_equip(captured)
					_refresh()
				)
				row.add_child(btn)

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
		bg.color = Color(0.25, 0.22, 0.08, 0.9) if is_sel else Color(0.12, 0.12, 0.12, 0.9)
		if slot_item.is_empty():
			lbl2.text = ""
		else:
			lbl2.text = slot_item.left(10)
			lbl2.add_theme_color_override("font_color", Color(1, 1, 1, 1))

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory"):
		visible = !visible
		GameManager.block_input = visible
		if visible:
			_refresh()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and visible:
		visible = false
		GameManager.block_input = false
		get_viewport().set_input_as_handled()
	elif visible and event is InputEventMouseButton \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
			and (event as InputEventMouseButton).pressed:
		var vp_size := get_viewport().get_visible_rect().size
		var panel_rect := Rect2(vp_size * 0.5 + Vector2(-320, -240), Vector2(640, 480))
		if not panel_rect.has_point((event as InputEventMouseButton).position):
			visible = false
			GameManager.block_input = false
			get_viewport().set_input_as_handled()
