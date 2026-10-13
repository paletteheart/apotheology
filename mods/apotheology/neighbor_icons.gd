extends Control

const HoverLabel = preload("res://mods/apotheology/hover_label.gd")

const RADIUS: float = 35.0
const ANGLE_STEP: float = 0.7
const MOOD_RANGE: float = 0.6
const MIN_SCALE: float = 0.5
const MAX_SCALE: float = 1.0
const MIN_ALPHA: float = 0.3
const MAX_ALPHA: float = 1.0
const UNDISCOVERED_TINT_AMOUNT: float = 1.0
const FADE_TIME: float = 0.25
const NEIGHBOR_LIGHT_STRENGTH: float = 0.2
const NEIGHBOR_GLOW_SCENE: PackedScene = preload("res://main/ui/menu/game_menu/rosary_screen/bead_light/bead_light.tscn")
const GLOW_SCALE: float = 0.4
const GLOW_STRENGTH: float = 0.4
const GLOW_COLOR: Color = Color.WHITE
const BOB_HEIGHT: float = 2.0
const BOB_SPEED: float = 2.0


var last_metadata: Dictionary = {}
var neighbor_count: int = 0:
	set(value):
		neighbor_count = clamp(value, 0, Engine.get_meta("apotheology").MAX_NEIGHBORS)
		if is_node_ready():
			_on_metadata_changed(last_metadata)

var icons: Array[TextureRect] = []
var shown_ids: Array[int] = []
var tweens: Array[Tween] = []
var bob_time: float = 0.0
var tint_color: Color
var tint_amount: float


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var source: TextureRect = %FusionPredictionIcon
	for i in range(Engine.get_meta("apotheology").MAX_NEIGHBORS):
		var icon: TextureRect = TextureRect.new()
		icon.texture = source.texture
		icon.stretch_mode = source.stretch_mode
		icon.size = source.size
		icon.pivot_offset = source.size / 2.0
		icon.scale = Vector2.ONE * MAX_SCALE
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.material = source.material.duplicate()
		icon.material.set_shader_parameter("alpha", 0.0)
		add_child(icon)
		icon.set_meta("phase", i * 0.8)
		icons.append(icon)
		shown_ids.append(-1)
		tweens.append(null)
		
		tint_color = source.material.get_shader_parameter("tint_color")
		tint_amount = source.material.get_shader_parameter("tint_amount")
		
		var glow: Sprite2D = NEIGHBOR_GLOW_SCENE.instantiate()
		glow.name = "Glow"
		glow.show_behind_parent = true
		glow.position = icon.size / 2.0
		glow.scale = Vector2.ONE * GLOW_SCALE
		glow.modulate = GLOW_COLOR
		glow.self_modulate.a = 0.0
		icon.add_child(glow)
		
		HoverLabel.attach(icon, "neighbor_labels")
	
	Ref.player_fuser.metadata_changed.connect(_on_metadata_changed)
	
	%NeighborsLight.modulate = Color.LIGHT_GRAY
	%NeighborsLight.modulate.a = 0.0
	
	Engine.get_meta("apotheology").ajna_changed.connect(_on_ajna_changed)


func _on_metadata_changed(metadata: Dictionary) -> void :
	last_metadata = metadata
	var neighbors: Array = metadata.get("neighbors", [])
	var count: int = min(neighbor_count, len(neighbors))
	
	# calculate the distances between the output and neighboring items
	var neighbors_dist: Array = metadata.get("neighbors_dist", [])
	var closest_dist: float = metadata.get("closest_dist", 0.0)
	var distances: Array = neighbors_dist.duplicate()
	for i in len(neighbors_dist):
		distances[i] = neighbors_dist[i] - closest_dist
	
	for i in range(len(icons)):
		if i < count:
			var t: float = i - (count - 1) / 2.0
			var angle: float = t * ANGLE_STEP
			var point: Vector2 = (Vector2(cos(angle), sin(angle)) - Vector2.RIGHT) * RADIUS
			
			icons[i].position = point - icons[i].size / 2.0
			icons[i].set_meta("fixed_y", icons[i].position.y)
			
			# check if the items in the slots have changed
			var id: int = neighbors[i]
			if shown_ids[i] != id:
				shown_ids[i] = id
				icons[i].material.set_shader_parameter("icon", ItemMap.map(id).icon)
				
			var distance: float = clamp(1.0 - distances[i] / MOOD_RANGE, 0.0, 1.0)
			var target_scale: float = lerp(MIN_SCALE, MAX_SCALE, distance)
			var target_alpha: float = lerp(MIN_ALPHA, MAX_ALPHA, distance)
			_fade(i, target_alpha, target_scale, false)
			icons[i].get_node("Hover").text = "±%s°" % String.num(distances[i], 2)
			
			_apply_discovery_tint(i, id)
		elif shown_ids[i] != -1:
			shown_ids[i] = -1
			_fade(i, 0.0, 0.0, false)
			icons[i].get_node("Hover").text = ""
			
	
	var light_target: float = NEIGHBOR_LIGHT_STRENGTH if count > 0 else 0.0
	%NeighborsLight.create_tween().tween_property(%NeighborsLight, "modulate:a", light_target, FADE_TIME)


func _fade(i: int, target_alpha: float, target_scale: float, from_zero: bool) -> void :
	if tweens[i] != null and tweens[i].is_valid():
		tweens[i].kill()
	var glow: Sprite2D = icons[i].get_node("Glow")
	var tween: Tween = icons[i].create_tween().set_parallel()
	var alpha_tweener: PropertyTweener = tween.tween_property(icons[i].material, "shader_parameter/alpha", target_alpha, FADE_TIME)
	if from_zero:
		alpha_tweener.from(0.0)
	if target_scale > 0.0:
		tween.tween_property(icons[i], "scale", Vector2.ONE * target_scale, FADE_TIME)
	tween.tween_property(glow, "self_modulate:a", target_alpha * GLOW_STRENGTH, FADE_TIME)
	tweens[i] = tween


func _apply_discovery_tint(i: int, id: int) -> void :
	var discovered: bool = Ref.discovery_manager.is_discovered(id)
	var item_color: Color = ItemMap.map(id).color
	item_color.a = 1.0
	icons[i].material.set_shader_parameter("tint_color", tint_color if discovered else item_color)
	icons[i].material.set_shader_parameter("tint_amount", tint_amount if discovered else UNDISCOVERED_TINT_AMOUNT)
	icons[i].get_node("Glow").modulate = GLOW_COLOR if discovered else item_color
	

func _process(delta: float) -> void:
	bob_time += delta
	for i in get_children():
		i.position.y = round(sin(bob_time*BOB_SPEED + i.get_meta("phase", 0.0)) * BOB_HEIGHT) + i.get_meta("fixed_y", 0.0)


func _on_ajna_changed(_value: int = 1) -> void:
	neighbor_count = Engine.get_meta("apotheology").get_neighbor_count()
	
