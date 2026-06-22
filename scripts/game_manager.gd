extends Node

signal health_changed(current: int, maximum: int)
signal godmode_changed(enabled: bool)
signal dungeon_new_requested
signal dungeon_over_requested
signal dungeon_free_requested
signal feedback_requested(message: String)
signal error_requested(message: String)
signal player_died
signal player_damaged
signal player_healed
signal item_picked_up(item_name: String, quantity: int)
signal secondary_task_changed
signal placement_requested(machine_name: String)
signal hotbar_changed

var pause_on_defocus: bool = true
var godmode: bool = false
var gamespeed_level: int = 1
var speed_level: int = 3
var dungeon_active: bool = false
var sim_iterations: int = 0

# Sprint state — written by player.gd, read by hud.gd
var sprint_energy: float = 5.0
var sprint_active: bool = false

var home_position: Vector2 = Vector2(INF, INF)
var task_index: int = 0
var dungeon_explored_tiles: Dictionary = {}  # Vector2i -> true

# Hotbar — 5 slots, each is an item name or ""
var hotbar: Array = ["", "", "", "", ""]
var hotbar_selected: int = 0  # 0-4
var equipped_weapon: String = ""  # e.g. "Sword"
var block_input: bool = false  # true when any fullscreen GUI is open

# Timer persistence — vents/forges save state here before scene change
var vent_states: Dictionary = {}   # pos_key -> state dict
var forge_states: Dictionary = {}  # pos_key -> state dict

# Placed machines persist through scene changes
var placed_machines: Array = []    # [{type: String, pos: Vector2}]

# Per-recipe unique craft flags (keyed by recipe id + "_crafted")
var forge_crafted: bool = false
var extrusion_machine_crafted: bool = false
var anvil_crafted: bool = false
var workstation_crafted: bool = false

# Simulacrum Engine repair persists across scene changes
var sim_engine_fixed: bool = false

# Recipes the player has flagged with [TRACK] — shown in the HUD task panel
# Each entry: {name: String, ingredients: Array[{item, qty}]}
var tracked_recipes: Array = []

func is_recipe_tracked(recipe_name: String) -> bool:
	for r in tracked_recipes:
		if r.get("name", "") == recipe_name:
			return true
	return false

func toggle_tracked_recipe(recipe: Dictionary) -> void:
	var rname: String = recipe.get("name", "")
	for i in tracked_recipes.size():
		if tracked_recipes[i].get("name", "") == rname:
			tracked_recipes.remove_at(i)
			return
	tracked_recipes.append({name = rname, ingredients = recipe.get("ingredients", [])})

# Boons
var active_boons: Array[String] = []
var boon_fragments: int = 0

# Save-system restore targets (set by SaveManager.load_game, consumed by player._ready)
var _save_restore_pos: Vector2    = Vector2(INF, INF)
var _save_restore_health: int     = -1

# Godmode inventory snapshot — saved before giving all items
var _godmode_inv_snapshot: Array  = []
var _godmode_was_active: bool     = false

func has_boon(boon_id: String) -> bool:
	return active_boons.has(boon_id)

func grant_boon(boon_id: String) -> void:
	if not active_boons.has(boon_id):
		active_boons.append(boon_id)
		feedback_requested.emit("Boon gained: %s" % boon_id)

func remove_boon(boon_id: String) -> void:
	active_boons.erase(boon_id)

func get_speed_multiplier() -> float:
	var base: float = float(speed_level) / 3.0  # level 3 = 1.0x, 1 = 0.33x, 5 = 1.67x
	if godmode:
		base *= 1.5
	return base

func set_speed(level: int) -> void:
	speed_level = clamp(level, 1, 5)
	feedback_requested.emit("Movement speed: %d" % speed_level)

func get_sim_cost() -> int:
	# 500, 1250, 2500, 5000, 10000, …
	if sim_iterations == 0:
		return 500
	if sim_iterations == 1:
		return 1250
	return 1250 * (1 << (sim_iterations - 1))

const _GODMODE_ITEMS: Array = [
	["Pickaxe", 1], ["Hammer", 5], ["Axe", 1], ["Sickle", 1], ["Great Axe", 1],
	["Crossbow", 1],
	["Log", 999], ["Rock", 999], ["Coal", 999], ["Heated Coal", 99],
	["Iron Ore", 999], ["Copper Ore", 999], ["Gold Ore", 999],
	["Heated Iron Ore", 99], ["Heated Copper Ore", 99], ["Heated Gold Ore", 99],
	["Iron Plate", 999], ["Copper Plate", 999], ["Gold Plate", 999],
	["Steel", 99], ["Knowledge Fragment", 9999],
	["Healing Vial", 50], ["String", 50],
]

func set_godmode(enabled: bool) -> void:
	if enabled and not _godmode_was_active:
		# Snapshot current inventory before flooding it
		_godmode_inv_snapshot = []
		for item in Inventory.items:
			_godmode_inv_snapshot.append(item.duplicate())
		_godmode_was_active = true
	elif not enabled and _godmode_was_active:
		# Restore pre-godmode inventory
		Inventory.items.clear()
		for item in _godmode_inv_snapshot:
			Inventory.items.append(item.duplicate())
		Inventory.inventory_changed.emit()
		_godmode_inv_snapshot.clear()
		_godmode_was_active = false

	godmode = enabled
	godmode_changed.emit(enabled)
	if enabled:
		for entry in _GODMODE_ITEMS:
			Inventory.add_item({
				"name": entry[0],
				"description": "",
				"quantity": entry[1],
			})
	feedback_requested.emit("God Mode: %s" % ("ON" if enabled else "OFF"))

func set_gamespeed(level: int) -> void:
	gamespeed_level = clamp(level, 1, 50)
	Engine.time_scale = float(gamespeed_level)
	feedback_requested.emit("Game speed: %dx" % gamespeed_level)
