extends Node

signal inventory_changed
signal boons_changed
signal boon_equipped(boon: Dictionary)

const MAX_SLOTS: int = 24

var items: Array[Dictionary] = []
var boons: Array[Dictionary] = []
var equipped_boon: Dictionary = {}

func add_item(item: Dictionary) -> bool:
	for existing in items:
		if existing["name"] == item["name"]:
			existing["quantity"] = existing.get("quantity", 1) + item.get("quantity", 1)
			inventory_changed.emit()
			return true
	if items.size() >= MAX_SLOTS:
		return false
	var entry := item.duplicate()
	if not entry.has("quantity"):
		entry["quantity"] = 1
	items.append(entry)
	inventory_changed.emit()
	return true

func remove_item(item_name: String, quantity: int = 1) -> bool:
	for i in items.size():
		if items[i]["name"] == item_name:
			items[i]["quantity"] -= quantity
			if items[i]["quantity"] <= 0:
				items.remove_at(i)
			inventory_changed.emit()
			return true
	return false

func add_boon(boon: Dictionary) -> void:
	boons.append(boon.duplicate())
	boons_changed.emit()

func equip_boon(boon: Dictionary) -> void:
	equipped_boon = boon.duplicate()
	boon_equipped.emit(equipped_boon)

func get_equipped_boon_name() -> String:
	return equipped_boon.get("name", "No Boon")

func has_item(item_name: String) -> bool:
	for item in items:
		if item["name"] == item_name:
			return true
	return false

func get_item_count(item_name: String) -> int:
	for item in items:
		if item["name"] == item_name:
			return item.get("quantity", 1)
	return 0
