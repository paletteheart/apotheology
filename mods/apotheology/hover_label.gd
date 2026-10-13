extends Control

const POPUP_SCENE: PackedScene = preload("res://main/ui/menu/game_menu/inventory_widget/item_popup/item_popup.tscn")
const POPUP_GAP: Vector2 = Vector2(2, 0)
const SELF_PATH: String = "res://mods/apotheology/hover_label.gd"

var feature: String = ""
var text: String = "":
	set(value):
		text = value
		_refresh()
var popup: ItemPopup
var hovered: bool = false

static func attach(target: Node, feature_name: String, area_size: Vector2 = Vector2.ZERO) -> Control :
	var hover: Control = load(SELF_PATH).new()
	hover.name = "Hover"
	hover.feature = feature_name
	target.add_child(hover)
	if area_size == Vector2.ZERO:
		hover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		hover.size = area_size
	return hover

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	popup = POPUP_SCENE.instantiate()
	popup.held_item = true
	popup.top_level = true
	add_child(popup)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	_refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		hovered = false
		_refresh()


func _on_mouse_entered() -> void :
	hovered = true
	_refresh()
	


func _on_mouse_exited() -> void :
	hovered = false
	_refresh()
	

func _refresh() -> void :
	if popup == null:
		return
	popup.get_node("%Label").text = text
	popup.reset_size()
	var unlocked: bool = feature == "" or Engine.get_meta("apotheology").is_ajna_feature_on(feature)
	var should_show: bool = hovered and unlocked and text != ""
	if should_show and not popup.displayed:
		var area: Rect2 = get_global_rect()
		popup.global_position = Vector2(area.end.x, area.position.y) + POPUP_GAP
		popup.enter()
	elif not should_show:
		popup.exit()
