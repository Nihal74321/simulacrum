extends Node

const SAVE_DIR  := "user://saves"
const SAVE_PATH := "user://saves/game.save"

const AUTOSAVE_INTERVAL: float = 300.0  # 5 minutes

var _autosave_timer: float = 0.0
var _was_paused: bool = false
var _ready_to_save: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_initial_load")

func _initial_load() -> void:
	if save_exists():
		load_game()
	_ready_to_save = true

func _process(delta: float) -> void:
	if not _ready_to_save:
		return
	if GameManager.dungeon_active:
		_was_paused = get_tree().paused
		return

	_autosave_timer += delta
	if _autosave_timer >= AUTOSAVE_INTERVAL:
		_autosave_timer = 0.0
		save_game(false)

	var is_paused := get_tree().paused
	if is_paused and not _was_paused:
		save_game(false)
	_was_paused = is_paused

func save_game(show_feedback: bool = true) -> void:
	if GameManager.dungeon_active:
		return

	var player := get_tree().get_first_node_in_group("player") as Node2D
	var player_pos := Vector2.ZERO
	var player_health := 100
	if player != null:
		player_pos = player.global_position
		player_health = int(player.get("health"))

	var inv_arr: Array = []
	for item in Inventory.items:
		inv_arr.append({
			"name"        : str(item.get("name", "")),
			"description" : str(item.get("description", "")),
			"quantity"    : int(item.get("quantity", 1)),
		})

	var machines_arr: Array = []
	for m in GameManager.placed_machines:
		var p: Vector2 = m.get("pos", Vector2.ZERO)
		machines_arr.append({"type": str(m.get("type", "")), "x": p.x, "y": p.y})

	var home := GameManager.home_position
	var data: Dictionary = {
		"version"          : 1,
		"task_index"       : GameManager.task_index,
		"hotbar"           : Array(GameManager.hotbar),
		"hotbar_selected"  : GameManager.hotbar_selected,
		"equipped_weapon"  : GameManager.equipped_weapon,
		"active_boons"     : Array(GameManager.active_boons),
		"boon_fragments"   : GameManager.boon_fragments,
		"home_x"           : home.x,
		"home_y"           : home.y,
		"sim_iterations"   : GameManager.sim_iterations,
		"sim_engine_fixed" : GameManager.sim_engine_fixed,
		"placed_machines"  : machines_arr,
		"player_x"         : player_pos.x,
		"player_y"         : player_pos.y,
		"player_health"    : player_health,
		"inventory"        : inv_arr,
		"forge_states"     : _serialize_dict(GameManager.forge_states),
		"vent_states"      : _serialize_dict(GameManager.vent_states),
	}

	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	if show_feedback:
		GameManager.feedback_requested.emit("Game saved.")

func _serialize_dict(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in d.keys():
		out[str(k)] = d[k]
	return out

func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()

	var result = JSON.parse_string(text)
	if not (result is Dictionary):
		return
	var data: Dictionary = result

	GameManager.task_index        = int(data.get("task_index", 0))
	GameManager.hotbar_selected   = int(data.get("hotbar_selected", 0))
	GameManager.equipped_weapon   = str(data.get("equipped_weapon", ""))
	GameManager.boon_fragments    = int(data.get("boon_fragments", 0))
	GameManager.sim_iterations    = int(data.get("sim_iterations", 0))
	GameManager.sim_engine_fixed  = bool(data.get("sim_engine_fixed", false))
	GameManager.home_position     = Vector2(
		float(data.get("home_x", INF)),
		float(data.get("home_y", INF))
	)

	var hotbar_raw = data.get("hotbar", [])
	for i in 5:
		GameManager.hotbar[i] = str(hotbar_raw[i]) if i < hotbar_raw.size() else ""

	GameManager.active_boons.clear()
	for b in data.get("active_boons", []):
		GameManager.active_boons.append(str(b))

	GameManager.placed_machines.clear()
	for m in data.get("placed_machines", []):
		GameManager.placed_machines.append({
			"type" : str(m.get("type", "")),
			"pos"  : Vector2(float(m.get("x", 0)), float(m.get("y", 0))),
		})

	Inventory.items.clear()
	for item in data.get("inventory", []):
		Inventory.items.append({
			"name"        : str(item.get("name", "")),
			"description" : str(item.get("description", "")),
			"quantity"    : int(item.get("quantity", 1)),
		})
	Inventory.inventory_changed.emit()

	for key in data.get("forge_states", {}).keys():
		GameManager.forge_states[key] = data["forge_states"][key]
	for key in data.get("vent_states", {}).keys():
		GameManager.vent_states[key] = data["vent_states"][key]

	# Queue player restore — applied in player.gd _ready()
	GameManager._save_restore_pos    = Vector2(float(data.get("player_x", 0)), float(data.get("player_y", 0)))
	GameManager._save_restore_health = int(data.get("player_health", 100))

func clear_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)

func save_exists() -> bool:
	return FileAccess.file_exists(SAVE_PATH)
