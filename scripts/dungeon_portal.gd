extends Area2D

const DUNGEON_SCENE: String = "res://scenes/dungeon.tscn"

var pulse_timer: float = 0.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	pulse_timer += delta
	$Body.color = Color(
		0.4 + sin(pulse_timer * 3.0) * 0.1,
		0.0,
		0.8 + sin(pulse_timer * 3.0) * 0.2,
		1.0
	)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		get_tree().change_scene_to_file(DUNGEON_SCENE)
