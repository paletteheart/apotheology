extends "res://mods/qualiamods/mod_base.gd"

signal ajna_changed(value: int)

const SAVE_KEY: String = "node/player/ajna"
const START_AJNA: int = 1
const MAX_NEIGHBORS: int = 7
const CLAIRVOYANCE_PERK: String = "res://mods/apotheology/clairvoyance_perk.tres"

const FUSION_SCREEN_SCENE: String = "res://mods/apotheology/fusion_screen.tscn"

const SETTINGS_PREFIX: String = "apotheology_"
const AJNA_STAT_POSITION: int = 3
const STAT_DESCRIPTION_SCENE: String = "res://main/ui/menu/game_menu/equipment_screen/stat_description.tscn"

# The list of features and the ajna level where they are enabled
const AJNA_UNLOCKS: Dictionary[String, int] = {
	"energy_beams": 3,
	"tag_icons": 4,
	"beam_labels": 5,
	"neighbor_labels": 6,
	"tag_labels": 7,
	"info_labels": 8,
}

# The list of toggles in the settings, [key, text]
const SETTINGS_TOGGLES: Array = [
	["info_labels", "info panel labels"],
	["energy_beams", "energy beams"],
	["beam_labels", "energy beam labels"],
	["tag_icons", "tag icons"],
	["tag_labels", "tag icon labels"],
	["neighbors", "neighbor icons"],
	["neighbor_labels", "neighbor distance labels"],
]

var settings_tab_ref: RefCounted
var settings_rows: Dictionary = {}
var ajna_stat_row: Control
var status_node: Node

var ajna: int = START_AJNA:
	set(val):
		ajna = clamp(val, START_AJNA, get_max_ajna())
		_announce_ajna()


# ---- Setup ----

func _early_setup() -> void:
	Engine.set_meta("apotheology", self)
	add_to_group("save")

func _game_ready() -> void:
	Ref.save_file_manager.settings_updated.connect(_announce_ajna)
	_add_clairvoyance_perk()
	_replace_fusion_screen()
	_announce_ajna()
	_add_settings_tab()
	_add_ajna_stat()
	
func _config_changed() -> void:
	log_info("skip_progression = %s" % not is_progression_enabled())
	_announce_ajna()

func _cleanup() -> void:
	Engine.remove_meta("apotheology")

func _replace_fusion_screen() -> void:
	var old_screen: Node = Ref.game_menu.get_node("%FusionScreen")
	var parent: Node = old_screen.get_parent()
	var index: int = old_screen.get_index()
	var new_screen: Node = load(FUSION_SCREEN_SCENE).instantiate()
	
	parent.remove_child(old_screen)
	old_screen.queue_free()
	
	new_screen.name = "FusionScreen"
	parent.add_child(new_screen)
	parent.move_child(new_screen, index)
	new_screen.owner = Ref.game_menu
	new_screen.unique_name_in_owner = true
	new_screen._ready()


# ---- Saving ----

func save_file(file: SaveFile) -> void:
	file.set_data(SAVE_KEY, ajna, true)

func load_file(file: SaveFile) -> void:
	ajna = file.get_data(SAVE_KEY, START_AJNA, true)
	
# ---- Ajna ----

func is_progression_enabled() -> bool:
	return not get_cfg("skip_progression", false)
	
func get_max_ajna() -> int:
	return MAX_NEIGHBORS + 1

func get_effective_ajna() -> int:
	return ajna if is_progression_enabled() else get_max_ajna()

func is_ajna_maxed() -> bool:
	return ajna >= get_max_ajna()

func is_ajna_unlocked(feature: String) -> bool:
	if not AJNA_UNLOCKS.has(feature):
		push_error("Unknown ajna feature: " + feature)
		return false
	return get_effective_ajna() >= AJNA_UNLOCKS[feature]

func is_ajna_setting_on(feature: String) -> bool:
	return Ref.save_file_manager.settings_file.get_data(SETTINGS_PREFIX + feature, true)

func is_ajna_feature_on(feature: String) -> bool:
	return is_ajna_setting_on(feature) and is_ajna_unlocked(feature)

func get_neighbor_count() -> int:
	if not is_ajna_setting_on("neighbors"):
		return 0
	return clamp(get_effective_ajna() - 1, 0, MAX_NEIGHBORS)


# ---- Stats Page ----

func _add_ajna_stat() -> void:
	status_node = Ref.game_menu.get_node("%EquipmentScreen/HBoxContainer/BoostControl/Status")
	var column: Node = status_node.get_child(0)
	ajna_stat_row = load(STAT_DESCRIPTION_SCENE).instantiate()
	column.add_child(ajna_stat_row)
	column.move_child(ajna_stat_row, AJNA_STAT_POSITION)
	status_node.stat_names.insert(AJNA_STAT_POSITION, "ajna")
	
	Ref.player.stats_updated.connect(_queue_ajna_stat)
	Ref.player.get_node("%Level").level_up_complete.connect(_queue_ajna_stat)
	Ref.player.equipment_inventory.item_slot_changed.connect(func(_inventory, _index): _queue_ajna_stat)
	Ref.main.game_playable.connect(_queue_ajna_stat)
	
	status_node.update_all_stats()
	_queue_ajna_stat()
	

func _queue_ajna_stat() -> void:
	_write_ajna_stat.call_deferred()

func _write_ajna_stat() -> void:
	if not is_instance_valid(ajna_stat_row):
		return
	ajna_stat_row.update_value(ajna)
	ajna_stat_row.visible = is_progression_enabled()


# ---- Misc. ----

func _add_settings_tab() -> void:
	settings_tab_ref = settings_tab("apotheology")
	for i in SETTINGS_TOGGLES:
		var button: CheckButton = settings_tab_ref.add_toggle(i[1], i[0], true)
		button.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
		settings_rows[i[0]] = button.get_parent()
	settings_tab_ref.load_values()

func _announce_ajna() -> void:
	ajna_changed.emit(ajna)
	if is_instance_valid(Ref.player):
		Ref.player.stats_updated.emit()

func _add_clairvoyance_perk() -> void:
	var level: Node = Ref.player.get_node("%Level")
	var perk: Resource = load(CLAIRVOYANCE_PERK)
	if perk != null and not level.available_perks.has(perk):
		level.available_perks.append(perk)


# Testing: Page Up / Page Down change ajna, only when run from the editor.
func _input(event: InputEvent) -> void:
	if not OS.is_debug_build() or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_PAGEUP:
		ajna += 1
	elif event.keycode == KEY_PAGEDOWN:
		ajna -= 1
	else:
		return
	log_info("ajna: %d" % ajna)
