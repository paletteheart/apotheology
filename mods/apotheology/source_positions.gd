extends Control

const HoverLabel = preload("res://mods/apotheology/hover_label.gd")

const GLOW_SCENE: PackedScene = preload("res://main/ui/menu/game_menu/rosary_screen/bead_light/bead_light.tscn")
const SLOT_CENTER: Vector2 = Vector2(11, 11)
const GLOW_OFFSET: Vector2 = Vector2(16, 16)
const GLOW_SCALE_X: float = 0.5
const GLOW_SCALE_Y_MIN: float = 0.025
const GLOW_SCALE_Y_MAX: float = 0.1
const MAX_GLOW: float = 0.7
const GLOW_COLOR: Color = Color.WHITE
const HOVER_SIZE: Vector2 = Vector2(8, 8)
const LABEL_FORMAT: String = "%d%%"

var glows: Array[Sprite2D] = []
var target_strengths: PackedFloat64Array = []
var beam_labels: Array[HoverLabel] = []

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var result_center: Vector2 = %ResultSlotPosition.global_position + SLOT_CENTER
	for marker in get_children():
		var slot_center: Vector2 = marker.global_position + SLOT_CENTER
		var direction: Vector2 = (result_center - slot_center).normalized()
		var glow: Sprite2D = GLOW_SCENE.instantiate()
		var hover: HoverLabel = HoverLabel.attach(marker, "beam_labels", HOVER_SIZE)
		glow.position = SLOT_CENTER + direction * GLOW_OFFSET
		glow.rotation = direction.angle()
		glow.scale = Vector2(GLOW_SCALE_X, GLOW_SCALE_Y_MAX)
		glow.modulate = GLOW_COLOR
		glow.self_modulate.a = 0.0
		hover.position = glow.position - HOVER_SIZE/2.0
		marker.add_child(glow)
		beam_labels.append(hover)
		glows.append(glow)
	
	target_strengths.resize(len(glows))
	target_strengths.fill(0.0)
	Ref.player_fusion_source.refresh.connect(_on_source_refreshed)
	Engine.get_meta("apotheology").ajna_changed.connect(_refresh_glows)
	_refresh_glows()

func _on_source_refreshed(_index: int) -> void:
	var source: Inventory = Ref.player_fusion_source
	var energies: PackedFloat64Array = []
	energies.resize(len(glows))
	energies.fill(0.0)
	var total_energy: float = 0.0
	var max_energy: float = 0.0
	
	for i in range(min(source.capacity, len(glows))):
		var state: ItemState = source.items[i]
		if state == null or state.count <= 0:
			continue
		energies[i] = state.count * ItemMap.map(state.id).essence.energy
		total_energy += energies[i]
		if energies[i] > max_energy: max_energy = energies[i]
		
	for i in range(len(glows)):
		target_strengths[i] = 0.0 if total_energy <= 0.0 else energies[i] / max_energy
	
	for i in range(len(beam_labels)):
		beam_labels[i].text = "" if energies[i] <= 0.0 else LABEL_FORMAT % roundi(100.0 * energies[i] / total_energy)

func _refresh_glows(_value: int = 1) -> void :
	for i in glows:
		i.visible = Engine.get_meta("apotheology").is_ajna_feature_on("energy_beams")
		
		
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	for i in range(len(glows)):
		var target: float = target_strengths[i] * MAX_GLOW
		var target_thickness: float = target_strengths[i] * (GLOW_SCALE_Y_MAX-GLOW_SCALE_Y_MIN) + GLOW_SCALE_Y_MIN
		glows[i].self_modulate.a = lerp(glows[i].self_modulate.a, target, clamp(delta*6.0, 0.0, 1.0))
		glows[i].scale.y = lerp(glows[i].scale.y, target_thickness, clamp(delta*6.0, 0.0, 1.0))
