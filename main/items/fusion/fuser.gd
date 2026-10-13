class_name Fuser extends Node

@export var fusion_cache_path: String = "res://main/items/fusion_table_cache.txt"

@export var used_properties: Array[String] = ["clay", "phlegm", "sulfur", "mercury", "aqua", "utility", "edibility", "danger", "wearability", "blockiness", "hate", "lust", "faith"]

@export var used_properties_weights: Dictionary[String, float] = {
	"clay": 1.0,
	"phlegm": 1.0,
	"sulfur": 1.0,
	"mercury": 1.0,
	"aqua": 1.0,
	"utility": 0.5,
	"edibility": 0.5,
	"danger": 0.5,
	"wearability": 0.5,
	"blockiness": 0.5,
	"hate": 1.25,
	"lust": 1.25,
	"faith": 1.25,
}

@export var tags: Array[String] = ["ball", "digital", "gem", "glass", "gold", "magic", "meat", "metal", "plant", "plastic", "stick", "stone", "string", "wood", "shoe", "earth", "fluff", "foliage", "leaf", "cold", "bright", "letter", "magnetite", "ring", "sky", "capsule", "water", "fire"]

@export var tag_magnitude: float = 1.0
@export var color_weight: float = 0.25

@export var samey_punishment: float = 0.35

@export var tiamana_per_rank: float = 0.25
@export var min_tiamana_yield: float = 0.15
@export var repeat_decay: float = 0.3
@export var tiamana_zero_mark: float = 0.01

@export var source: Inventory
@export var result: Inventory

@export var update_fusion_cache: bool = false

var weights: PackedFloat64Array
var id_to_mood_vector: Dictionary[int, PackedFloat64Array]
var id_to_tag_vector: Dictionary[int, PackedByteArray]
var id_to_output_tag_vector: Dictionary[int, PackedByteArray]
var fuseable: Dictionary[int, bool]


var internal_metadata: Dictionary


var fusion_table_loaded: bool = false
var fusion_table_cache: Dictionary[String, int]
var fusion_table: PackedInt32Array
var all_block_ids: PackedInt32Array
var fusion_table_width: int

var closest_distance: float = INF
var last_recipe: Array = []

signal fusion_table_done_loading
signal metadata_changed(metadata: Dictionary)


func _ready() -> void :
	initialize_data()


func initialize_data() -> void :
	if not ItemMap.all_items_loaded:
		await ItemMap.items_done_loading
	print("Initializing fuser...")
	tags.sort()

	for id in ItemMap.all_item_ids:
		var essence: VitalEssence = ItemMap.map(id).essence as VitalEssence
		fuseable[id] = essence.fuseable

		id_to_mood_vector[id] = get_essence_mood_vector(essence)

		var tag_vector: PackedByteArray
		tag_vector.resize(len(tags))

		var output_tag_vector: PackedByteArray
		output_tag_vector.resize(len(tags))

		for i in range(len(tags)):
			if tags[i] in essence.tags:
				tag_vector[i] = 1
			else:
				tag_vector[i] = 0

			if tags[i] in essence.output_tags:
				output_tag_vector[i] = 1
			else:
				output_tag_vector[i] = 0
		id_to_tag_vector[id] = tag_vector
		id_to_output_tag_vector[id] = output_tag_vector

	weights = PackedFloat64Array()
	for property in used_properties:
		weights.append(used_properties_weights[property])

	generate_block_fusion_table()
	fusion_table_loaded = true
	fusion_table_done_loading.emit()
	print("Fusion done.")


func generate_block_fusion_table() -> void :
	if not update_fusion_cache and FileAccess.file_exists(fusion_cache_path):
		print("Loading fusion cache...")
		var load_file: FileAccess = FileAccess.open(fusion_cache_path, FileAccess.READ)
		fusion_table_cache = JSON.to_native(JSON.parse_string(load_file.get_line()))
		load_file.close()
		print("Fusion cache loaded.")

	all_block_ids.clear()
	fusion_table.clear()
	fusion_table_width = 0

	for block in Ref.world.get_block_types():
		all_block_ids.push_back(block.id)

	print("Loading fusion table...")
	fusion_table_width = len(all_block_ids)
	for k in range(len(all_block_ids) * len(all_block_ids)):
		var i: int = int(k / len(all_block_ids))
		var j: int = k % len(all_block_ids)


		if i == 0 and j == 0:
			fusion_table.push_back(0)
			continue


		if i > j:
			fusion_table.push_back(fusion_table[j * fusion_table_width + i])
			continue

		var cache_key: String = str(i) + "," + str(j)
		if cache_key in fusion_table_cache:
			fusion_table.push_back(fusion_table_cache[cache_key])
			continue

		var state_1: ItemState = ItemState.new()
		state_1.id = all_block_ids[i]

		var state_2: ItemState = ItemState.new()
		state_2.id = all_block_ids[j]


		var energy_1: float = ItemMap.map(all_block_ids[i]).essence.energy
		var energy_2: float = ItemMap.map(all_block_ids[j]).essence.energy
		if energy_1 > energy_2:
			state_1.count = 1
			state_2.count = clamp(round(energy_1 / energy_2), 1, 50)
		else:
			state_1.count = clamp(round(energy_2 / energy_1), 1, 50)
			state_2.count = 1

		var to_fuse: Array[ItemState] = [state_1, state_2]
		var block_fusion_result: ItemState = get_fusion_result_static(to_fuse)
		var block_fusion_item: Item = ItemMap.map(block_fusion_result.id)

		if not block_fusion_item is Block or block_fusion_item.internal or block_fusion_item.living_block_path != "":
			fusion_table.push_back(all_block_ids[i])
		else:
			fusion_table.push_back(block_fusion_result.id)

		fusion_table_cache[cache_key] = fusion_table[len(fusion_table) - 1]
	print("Fusion table loaded.")


	var save_file: FileAccess = FileAccess.open(fusion_cache_path, FileAccess.WRITE_READ)
	if save_file != null:
		save_file.store_line(JSON.stringify(JSON.from_native(fusion_table_cache)))
		save_file.close()
	else:
		printerr("Can't write to fusion cache.")


func can_fuse() -> bool:

	if result.items[0] != null:
		return false


	var used_ids: Dictionary[int, bool]
	var non_null_count: int = 0
	for i in range(source.capacity):
		var state: ItemState = source.items[i]
		if state == null:
			continue
		non_null_count += 1
		used_ids[state.id] = true


	if used_ids.size() == 1 and not ItemMap.map(used_ids[used_ids.keys()[0]]).essence.fuseable:
		return false

	return used_ids.size() >= 1 and non_null_count > 1



func get_fusion_result_static(nonempty_item_states: Array[ItemState], store_metadata: bool = false, metadata: Dictionary = {}) -> ItemState:

	var total_energy: float = 0.0
	for state in nonempty_item_states:
		var essence: Essence = ItemMap.map(state.id).essence
		total_energy += state.count * essence.energy

	if total_energy <= 0:
		total_energy = 0.01

	var mood_vector: PackedFloat64Array
	mood_vector.resize(len(used_properties))
	mood_vector.fill(0)

	var tag_vector: PackedByteArray
	tag_vector.resize(len(tags))
	tag_vector.fill(0)

	var output_tag_vector: PackedByteArray
	output_tag_vector.resize(len(tags))
	output_tag_vector.fill(0)

	var used_ids: Dictionary[int, bool] = {}
	var average_color: Color = Color()


	for state in nonempty_item_states:
		used_ids[state.id] = true

		var item: Item = ItemMap.map(state.id)
		var essence: Essence = item.essence
		var ratio: float = essence.energy * state.count / float(total_energy)
		for i in range(len(used_properties)):
			mood_vector[i] += weights[i] * ratio * essence.get(used_properties[i])

		var other_tag_vector: PackedByteArray = id_to_tag_vector[state.id]
		var other_output_tag_vector: PackedByteArray = id_to_output_tag_vector[state.id]

		for i in range(len(tags)):
			if other_tag_vector[i] > 0:
				tag_vector[i] = 1
			if other_output_tag_vector[i] > 0:
				output_tag_vector[i] = 1

		average_color += item.color * ratio

	var closest_item: Item
	closest_distance = INF
	var ranked: Array[Dictionary] = []
	for id in id_to_mood_vector:
		if not fuseable[id]:
			continue

		var item: Item = ItemMap.map(id)
		var potential_tag_vector: PackedByteArray = id_to_tag_vector[id]
		var tag_sameness: float = tag_similarity(tag_vector, potential_tag_vector)
		var tag_output_match: float = tag_priority(output_tag_vector, potential_tag_vector)
		var color_dist: float = color_distance(item.color, average_color)
		var essence_distance: float = distance(mood_vector, id_to_mood_vector[id])
		essence_distance -= tag_sameness * tag_magnitude + tag_output_match
		essence_distance += color_dist * color_weight

		essence_distance -= 2.5 * item.essence.bias


		if id in used_ids:
			essence_distance += samey_punishment
		if store_metadata:
			_insert_ranked(ranked, id, essence_distance, Engine.get_meta("apotheology").MAX_NEIGHBORS + 1)
		if essence_distance < closest_distance:
			closest_item = ItemMap.map(id)
			closest_distance = essence_distance


	if used_ids.size() == 1:
		closest_item = ItemMap.map(used_ids.keys()[0])










	var result_item: ItemState = ItemState.new()
	result_item.initialize(closest_item)
	result_item.count = clamp(round(total_energy / closest_item.essence.energy), 1, closest_item.stack_size)

	if store_metadata:
		metadata["lame_fusion"] = result_item.id in used_ids
		metadata["energy"] = total_energy
		metadata["output_energy"] = result_item.count * closest_item.essence.energy
		metadata["mood_vector"] = mood_vector
		metadata["color"] = average_color
		metadata["rank"] = closest_item.essence.rank
		
		var active_tags: Array[String] = []
		var active_output_tags: Array[String] = []
		for i in range(len(tags)):
			if tag_vector[i] > 0:
				active_tags.append(tags[i])
		for i in range(len(tags)):
			if output_tag_vector[i] > 0:
				active_output_tags.append(tags[i])
		metadata["tags"] = active_tags
		metadata["output_tags"] = active_output_tags
		
		metadata["closest_dist"] = closest_distance
		var neighbors: Array[int] = []
		var neighbors_dist: Array[float] = []
		for i in ranked:
			if i.id != closest_item.id and len(neighbors) < Engine.get_meta("apotheology").MAX_NEIGHBORS:
				neighbors.append(i.id)
				neighbors_dist.append(i.distance)
		metadata["neighbors"] = neighbors
		metadata["neighbors_dist"] = neighbors_dist
		ranked = []

		if not metadata["lame_fusion"]:
			var repeat_fusion_count: int = Ref.discovery_manager.fused_ids.get(result_item.id, 0)
			var base_yield: float = (min_tiamana_yield + closest_item.essence.rank * tiamana_per_rank) * pow(repeat_decay, repeat_fusion_count)
			if base_yield < tiamana_zero_mark:
				metadata["lame_fusion"] = true
				metadata["tiamana_yield"] = 0.0
			else:
				metadata["tiamana_yield"] = base_yield
		else:
			metadata["tiamana_yield"] = 0.0

	return result_item


func get_fusion_result(store_metadata: bool = false) -> ItemState:
	if not can_fuse():
		if store_metadata:
			metadata_changed.emit({})
		return null


	var source_item_states: Array[ItemState] = []
	for i in range(source.capacity):
		source_item_states.append(source.items[i])

	var nonempty_item_states: Array[ItemState] = []
	for state in source_item_states:
		if state != null and state.count > 0:
			nonempty_item_states.append(state)

	if len(nonempty_item_states) == 0:
		if store_metadata:
			metadata_changed.emit({})
		return null

	if store_metadata:
		internal_metadata = {}
		var item_result: ItemState = get_fusion_result_static(nonempty_item_states, true, internal_metadata)
		metadata_changed.emit(internal_metadata.duplicate())
		return item_result
	else:
		return get_fusion_result_static(nonempty_item_states)



func fuse() -> void :
	if not can_fuse():
		return

	var result_item: ItemState = get_fusion_result(true)
	var result_item_resource: Item = ItemMap.map(result_item.id)


	if not internal_metadata["lame_fusion"]:
		Ref.discovery_manager.fused_ids[result_item_resource.id] = (Ref.discovery_manager.fused_ids.get(result_item_resource.id, 0) + 1)
		Ref.player.get_node("%Level").give_tiamana(internal_metadata["tiamana_yield"], Level.TiamanaSource.FUSION)
		print("Tiamana yield: ", internal_metadata["tiamana_yield"])

	last_recipe = []
	for i in range(source.capacity):
		var state: ItemState = source.items[i]
		if state == null:
			last_recipe.append(null)
		else:
			last_recipe.append({"id": state.id, "count": state.count})

	
	var source_item_states: Array[ItemState] = []
	for i in range(source.capacity):
		source_item_states.append(source.items[i])
		source.set_item(i, null)

	result.set_item(0, result_item)

	Steamworks.increment_statistic("fusion_count")
	Steamworks.set_achievement("FIRST_FUSION")

	if result_item_resource is Spawner:
		Steamworks.set_achievement("LIVING_FUSION")
	if result_item_resource.essence.rank >= 0.5:
		Steamworks.set_achievement("RARE_FUSION")


func death_fusion() -> void :
	for i in range(0, Ref.player_inventory.capacity / 3, 1):
		var item_1: ItemState = Ref.player_inventory.items[i * 3 + 0]
		var item_2: ItemState = Ref.player_inventory.items[i * 3 + 1]
		var item_3: ItemState = Ref.player_inventory.items[i * 3 + 2]

		var to_fuse: Array[ItemState] = []
		if item_1 != null:
			to_fuse.append(item_1)
		if item_2 != null:
			to_fuse.append(item_2)
		if item_3 != null:
			to_fuse.append(item_3)

		if len(to_fuse) == 0:
			continue

		var fusion_result: ItemState = get_fusion_result_static(to_fuse)

		Ref.player_inventory.items[i * 3 + 0] = null
		Ref.player_inventory.items[i * 3 + 1] = null
		Ref.player_inventory.items[i * 3 + 2] = null

		Ref.player_inventory.items[i * 3 + randi_range(0, 2)] = (fusion_result.duplicate() if is_instance_valid(fusion_result) else null)


func distance(v1: PackedFloat64Array, v2: PackedFloat64Array) -> float:
	assert (len(v1) == len(v2))
	var distance_squared: float = 0
	for i in range(len(v1)):
		distance_squared += pow(v1[i] - v2[i], 2.0)
	return sqrt(distance_squared)


func tag_similarity(v1: PackedByteArray, v2: PackedByteArray) -> float:
	var similarity: float = 0.0
	for i in range(len(v1)):
		var active_1: bool = v1[i]
		var active_2: bool = v2[i]
		similarity += float(active_1 and active_2)

	return similarity


func tag_priority(v1: PackedByteArray, v2: PackedByteArray) -> float:
	var similarity: float = 0.0
	for i in range(len(v1)):
		var active_1: bool = v1[i]
		var active_2: bool = v2[i]
		similarity += 1000.0 * float(active_1 and active_2)
	return similarity


func get_essence_mood_vector(essence: Essence) -> PackedFloat64Array:
	var mood_vector: PackedFloat64Array
	mood_vector.resize(len(used_properties))
	mood_vector.fill(0)
	for i in range(len(used_properties)):
		mood_vector[i] = essence.get(used_properties[i])
	return mood_vector


func color_distance(c1: Color, c2: Color) -> float:
	return sqrt(pow(c1.r - c2.r, 2) + pow(c1.g - c2.g, 2) + pow(c1.b - c2.b, 2))


func refill_last_recipe() -> bool:
	if last_recipe.is_empty():
		return false
	
	#clear_fusion_slots()
	
	var ingredients: Dictionary[int, int] = {}
	for i in last_recipe:
		if i != null:
			ingredients[i.id] = ingredients.get(i.id, 0) + i.count
	
	# Go through all items currently in your inventory and make sure you have
	# enough of each ingredient
	var inventories: Array[Inventory] = [Ref.player_inventory, Ref.player_hotbar]
	for id in ingredients:
		var holding: int = 0
		for i in inventories:
			for j in range(i.capacity):
				var state: ItemState = i.items[j]
				if state != null and state.id == id:
					holding += state.count
		if holding < ingredients[id]:
			return false
			
	for i in range(min(len(last_recipe), source.capacity)):
		var entry = last_recipe[i]
		if entry == null:
			continue
		source.set_item(i, _take_from_player(entry.id, entry.count))
	return true


func multiply_recipe() -> bool:
	var recipe = []
	var ingredients: Dictionary[int, int] = {}
	for i in source.capacity:
		var state: ItemState = source.items[i]
		if state != null:
			recipe.append({"id": state.id, "count": state.count})
			ingredients[state.id] = ingredients.get(state.id, 0) + state.count
		else:
			recipe.append(null)
	
	if ingredients.is_empty():
		return false
	
	# Go through all items currently in your inventory and make sure you have
	# enough of each ingredient
	var inventories: Array[Inventory] = [Ref.player_inventory, Ref.player_hotbar]
	for id in ingredients:
		var holding: int = 0
		for i in inventories:
			for j in range(i.capacity):
				var state: ItemState = i.items[j]
				if state != null and state.id == id:
					holding += state.count
		if holding < ingredients[id]:
			return false
			
	for i in range(min(len(recipe), source.capacity)):
		var entry = recipe[i]
		if entry == null:
			continue
		var new_stack: ItemState = _take_from_player(entry.id, entry.count, false)
		if new_stack != null:
			new_stack = source.accept(new_stack, false)
		if new_stack != null:
			new_stack = source.accept(new_stack)
		if new_stack != null:
			return false
		_take_from_player(entry.id, entry.count)
	return true


# stolen from game_menu.gd
func clear_fusion_slots() -> void :
	for inventory in [Ref.player_fusion_source, Ref.player_fusion_result]:
		for i in range(len(inventory.items)):
			var item_state: ItemState = inventory.items[i]
			if item_state == null:
				continue
			inventory.set_item(i, null)
			var remaining_item: ItemState = Ref.player_inventory.accept(item_state)
			if remaining_item != null:
				remaining_item = Ref.player_hotbar.accept(remaining_item)
			if remaining_item != null:
				Ref.player.get_node("%DropItems").drop_item(remaining_item)


func _take_from_player(id: int, amount: int, remove: bool = true) -> ItemState:
	var inventories: Array[Inventory] = [Ref.player_inventory, Ref.player_hotbar]
	var taken: ItemState = null
	for inventory in inventories:
		for i in range(inventory.capacity):
			if amount <= 0:
				return taken
				
			var state: ItemState = inventory.items[i]
			
			if state == null or state.id != id:
				continue
				
			if taken == null and state.count <= amount:
				if remove:
					inventory.set_item(i, null)
				taken = state
				amount -= state.count
			else:
				var take_count: int = min(amount, state.count)
				if taken == null:
					taken = ItemState.new()
					taken.initialize(ItemMap.map(id))
					taken.count = 0
				taken.count += take_count
				amount -= take_count
				if remove:
					inventory.change_amount(i, -take_count)
	return taken

func _insert_ranked(ranked: Array[Dictionary], id: int, distance: float, limit: int) -> void :
	var i: int = len(ranked)
	while i > 0 and ranked[i - 1].distance > distance:
		i -= 1
	if i >= limit:
		return
	ranked.insert(i, {"id": id, "distance": distance})
	if len(ranked) > limit:
		ranked.pop_back()
