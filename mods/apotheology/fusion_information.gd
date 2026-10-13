extends Control

const HoverLabel = preload("res://mods/apotheology/hover_label.gd")

const INFO_NAMES: Dictionary[String, String] = {
	"Background": "",
	"Projector": "",
	"Projector2": "",
	"ColorIndicator": "chroma",
}
const KNOB_NAMES: Array[String] = ["clay", "phlegm", "sulfur", "mercury", "aqua", "utility", "edibility", "danger", "wearability", "blockiness", "rank", "hate", "lust", "faith"]
const ENERGY_NAME: String = "energy"
const TIAMANA_NAME: String = "tiamana"
const NEW_TEXT: Dictionary[String, String] = {"new": "novel", "seen": "familiar", "empty": "empty"}
const VALUE_DECIMALS: int = 2

const TAGS: Array[String] = ["ball", "digital", "gem", "glass", "gold", "magic", "meat", "metal", "plant", "plastic", "stick", "stone", "string", "wood", "shoe", "earth", "fluff", "foliage", "leaf", "cold", "bright", "letter", "magnetite", "ring", "sky", "capsule", "water", "fire"]
const TAG_ICON_DIR: String = "res://mods/apotheology/textures/tags/"
const ICON_SIZE: Vector2 = Vector2(11, 11)
const ICON_COLOR: Color = Color.LIGHT_GRAY
const BOB_HEIGHT: float = 2.0
const BOB_SPEED: float = 2.0
const TAG_GLOW_SCENE: PackedScene = preload("res://main/ui/menu/game_menu/rosary_screen/bead_light/bead_light.tscn")
const GLOW_SCALE: float = 0.4
const GLOW_STRENGTH: float = 0.15
const TAG_LIGHT_STRENGTH: float = 0.2
const FADE_TIME: float = 0.25
const BLINK_TIME: float = 0.15

var fusion_data: Dictionary
var new_item: bool = false
var tag_textures: Dictionary[String, Texture2D] = {}
var tag_icons: Dictionary[String, Control] = {}
var bob_time: float = 0.0
var tag_material: ShaderMaterial
var remove_cache: Array[Control] = []
var layout_tween: Tween
var visibility_tween: Tween

var knob_labels: Array[HoverLabel] = []
var energy_label: HoverLabel
var tiamana_label: HoverLabel
var new_label: HoverLabel
var has_result: bool = false


func _ready() -> void :
	_load_tag_textures()
	tag_material = ShaderMaterial.new()
	tag_material.shader = preload("res://main/ui/filter/self_dither.gdshader")
	tag_material.set_shader_parameter("flitter_speed", $Background.material.get_shader_parameter("flitter_speed"))
	tag_material.set_shader_parameter("bit_depth", 22.0)
	%TagIcons.grow_horizontal = Control.GROW_DIRECTION_END
	%TagLight.modulate = ICON_COLOR
	%TagLight.modulate.a = 0.0
	Ref.player_fuser.metadata_changed.connect(_on_metadata_changed)
	%FusionPredictionIcon.new_status_changed.connect(_on_new_status_changed)
	_create_info_labels()
	_on_metadata_changed({})
	Engine.get_meta("apotheology").ajna_changed.connect(_refresh_tag_icons)
	_refresh_tag_icons()


func _on_new_status_changed(val: bool) -> void :
	new_item = val
	_update_info_labels()


func _on_metadata_changed(metadata: Dictionary) -> void :
	has_result = not metadata.is_empty()
	if metadata.is_empty():
		fusion_data.energy = 0.0
		fusion_data.tiamana_yield = 0.0
		fusion_data.mood_vector = (PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]) if not ItemMap.all_items_loaded else Ref.player_fuser.get_essence_mood_vector(ItemMap.map(1).essence))
		fusion_data.color = Color.BLACK
		fusion_data.rank = 0.0
		fusion_data.tags = []
		fusion_data.output_tags = []
	else:
		fusion_data = metadata

	fusion_data.mood_vector = fusion_data.mood_vector.duplicate()
	fusion_data.mood_vector.insert(10, fusion_data.rank)
	for i in range(len(fusion_data.mood_vector)):
		%Knobs.get_child(i).set_target(fusion_data.mood_vector[i])
	
	_update_tag_icons(fusion_data.tags, fusion_data.output_tags)
	_update_tag_light()
	_update_info_labels()


func _process(delta: float) -> void :
	if not is_visible_in_tree():
		return
	%ColorIndicatorLight.modulate = lerp( %ColorIndicatorLight.modulate, fusion_data.color, clamp(delta * 6.0, 0.0, 1.0))
	%ColorIndicatorLight.modulate.a = fusion_data.color.v
	%EnergyLight.modulate.a = lerp( %EnergyLight.modulate.a, clamp(fusion_data.energy / 6.0, 0.0, 1.0), clamp(delta * 6.0, 0.0, 1.0))
	%SeenLight.modulate.a = lerp( %SeenLight.modulate.a, 1.0 if new_item else 0.0, clamp(delta * 6.0, 0.0, 1.0))
	%ExcessLight.modulate.a = lerp( %ExcessLight.modulate.a, clamp(fusion_data.tiamana_yield, 0.0, 1.0), clamp(delta * 6.0, 0.0, 1.0))
	bob_time += delta
	for i in %TagIcons.get_children():
		var sprite: TextureRect = i.get_child(0)
		sprite.position.y = round(sin(bob_time*BOB_SPEED + i.get_meta("phase", 0.0)) * BOB_HEIGHT)

func _load_tag_textures() -> void :
	for i in range(len(TAGS)):
		var path: String = TAG_ICON_DIR + ("tag%d.png" % (i+1))
		var texture: Texture2D = load(path)
		if texture == null:
			push_warning("Missing tag icon: " + path)
			continue
		tag_textures[TAGS[i]] = texture
		
func _update_tag_icons(tags: Array, output_tags: Array) -> void :
	# Skip whatever layout tweening is happening
	if layout_tween != null and layout_tween.is_valid():
		layout_tween.kill()
	for i in remove_cache:
		_free_tag_icon(i)
	remove_cache.clear()
	
	# Create ordered list of tags
	var present_tags: Array[String] = []
	for i in output_tags:
		if tag_textures.has(i) and i not in present_tags:
			present_tags.append(i)
	for i in tags:
		if tag_textures.has(i) and i not in present_tags:
			present_tags.append(i)
	
	# Mark old tags for removal
	for i in tag_icons.keys():
		if i not in present_tags:
			remove_cache.append(tag_icons[i])
			tag_icons[i].get_child(0).get_node("Hover").text = ""
			tag_icons.erase(i)
	
	# Add and style new tags
	for i in present_tags:
		if not tag_icons.has(i):
			_add_tag_icon(i)
		var sprite: TextureRect = tag_icons[i].get_child(0)
		var glow: Sprite2D = sprite.get_node("Glow")
		var old_tween: Tween = sprite.get_meta("style_tween") if sprite.has_meta("style_tween") else null
		if old_tween != null and old_tween.is_valid(): old_tween.kill() # Stop any current animations
		var tween: Tween = sprite.create_tween().set_parallel()
		# Create a pseudo-random color for output tags
		var random: int = rand_from_seed(i.hash())[0]
		var output_color = Color.from_hsv(posmod(random, 512) / 512.0, 1.0, 1.0)
		
		tween.tween_property(sprite, "self_modulate", output_color.lightened(0.9) if i in output_tags else ICON_COLOR, FADE_TIME)
		tween.tween_property(glow, "self_modulate:a", GLOW_STRENGTH if i in output_tags else 0.0, FADE_TIME)
		sprite.set_meta("style_tween", tween)
		
		glow.modulate = output_color
	
	var reorder: bool = false
	for i in range(len(present_tags)):
		if tag_icons[present_tags[i]].get_index() != i:
			reorder = true
			break
	
	if reorder:
		_reorder_tag_icons(present_tags)
	else:
		for i in remove_cache:
			_fade_tag_icon(i, 0.0, _finish_removing.bind(i))
		for i in present_tags:
			_fade_tag_icon(tag_icons[i], 1.0)

func _add_tag_icon(tag: String) -> void :
	var container: Control = Control.new()
	container.custom_minimum_size = ICON_SIZE
	container.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	container.set_meta("phase", TAGS.find(tag) * 0.8)
	
	var sprite: TextureRect = TextureRect.new()
	sprite.texture = tag_textures[tag]
	sprite.material = tag_material
	container.add_child(sprite)
	
	var glow: Sprite2D = TAG_GLOW_SCENE.instantiate()
	glow.name = "Glow"
	glow.show_behind_parent = true
	glow.position = ICON_SIZE / 2.0
	glow.scale = Vector2.ONE * GLOW_SCALE
	glow.self_modulate.a = 0.0
	sprite.add_child(glow)
	
	container.modulate.a = 0.0
	%TagIcons.add_child(container)
	HoverLabel.attach(sprite, "tag_labels").text = tag
	container.create_tween().tween_property(container, "modulate:a", 1.0, FADE_TIME)
	tag_icons[tag] = container
	
	
func _fade_tag_icon(container: Control, target: float, on_done: Callable = Callable()) -> void :
	var old_tween: Tween = container.get_meta("fade_tween") if container.has_meta("fade_tween") else null
	if old_tween != null and old_tween.is_valid(): old_tween.kill() # Stop any current animations
	var tween: Tween = container.create_tween()
	tween.tween_property(container, "modulate:a", target, FADE_TIME)
	if on_done.is_valid():
		tween.tween_callback(on_done)
	container.set_meta("fade_tween", tween)

func _finish_removing(container: Control) -> void :
	remove_cache.erase(container)
	_free_tag_icon(container)

	
func _reorder_tag_icons(tags: Array[String]) -> void :
	layout_tween = create_tween().set_parallel()
	for i in %TagIcons.get_children():
		var old_tween: Tween = i.get_meta("fade_tween") if i.has_meta("fade_tween") else null
		if old_tween != null and old_tween.is_valid(): old_tween.kill() # Stop any current animations
		layout_tween.tween_property(i, "modulate:a", 0.0, BLINK_TIME)
	layout_tween.chain().tween_callback(_apply_tag_order.bind(tags))
	layout_tween.chain()
	for i in tags:
		layout_tween.tween_property(tag_icons[i], "modulate:a", 1.0, FADE_TIME)

func _apply_tag_order(tags: Array[String]) -> void :
	for i in remove_cache:
		_free_tag_icon(i)
	remove_cache.clear()
	for i in range(len(tags)):
		%TagIcons.move_child(tag_icons[tags[i]], i)


func _free_tag_icon(container: Control) -> void :
	if not is_instance_valid(container):
		return
	if container.get_parent() != null:
		container.get_parent().remove_child(container)
	container.queue_free()

	
func _refresh_tag_icons(_value: int = 1) -> void :
	if visibility_tween != null and visibility_tween.is_valid(): visibility_tween.kill()
	var target: float = 1.0 if Engine.get_meta("apotheology").is_ajna_feature_on("tag_icons") else 0.0
	visibility_tween = %TagIcons.create_tween()
	visibility_tween.tween_property(%TagIcons, "modulate:a", target, FADE_TIME)
	_update_tag_light()

func _update_tag_light() -> void :
	var shown: bool = fusion_data.tags != [] and Engine.get_meta("apotheology").is_ajna_feature_on("tag_icons")
	%TagLight.create_tween().tween_property(%TagLight, "modulate:a", TAG_LIGHT_STRENGTH if shown else 0.0, FADE_TIME)
	
	
func _create_info_labels() -> void :
	for i in INFO_NAMES:
		HoverLabel.attach(get_node(i), "info_labels").text = INFO_NAMES[i]
	for i in %Knobs.get_children():
		knob_labels.append(HoverLabel.attach(i, "info_labels"))
	energy_label = HoverLabel.attach($EnergyIndicator, "info_labels")
	tiamana_label = HoverLabel.attach($ExcessEnergyIndicator, "info_labels")
	new_label = HoverLabel.attach($FusionSeenItem, "info_labels")


func _update_info_labels() -> void :
	if knob_labels.is_empty():
		return
	for i in range(len(knob_labels)):
		var knob_name: String = KNOB_NAMES[i] if i < len(KNOB_NAMES) else ""
		knob_labels[i].text = _value_text(knob_name, fusion_data.mood_vector[i])
	energy_label.text = _value_text(ENERGY_NAME, fusion_data.energy)
	tiamana_label.text = _value_text(TIAMANA_NAME, fusion_data.tiamana_yield)
	var state: String = "empty" if not has_result else ("new" if new_item else "seen")
	new_label.text = NEW_TEXT[state]

func _value_text(name: String, value: float) -> String:
	return ("%s: %s" % [name, String.num(value, VALUE_DECIMALS)]).strip_edges()


func force_update() -> void :
	%ColorIndicatorLight.modulate = fusion_data.color
	%ColorIndicatorLight.modulate.a = fusion_data.color.v
	%EnergyLight.modulate.a = clamp(fusion_data.energy / 6.0, 0.0, 1.0)
	%SeenLight.modulate.a = 1.0 if new_item else 0.0
	%ExcessLight.modulate.a = clamp(fusion_data.tiamana_yield, 0.0, 1.0)
	for i in range(len(fusion_data.mood_vector)):
		%Knobs.get_child(i).force_update()
	for i in tag_icons.values():
		i.modulate.a = 1.0
