extends Control

signal fusion_finished(cancel: bool)

var play_up_sound_on_next: bool = false


func _ready() -> void :
	%FusionButton.pressed.connect(_on_fusion_button_pressed)
	%FusionButton.pressed.connect(_on_fusion_button_down)
	%FusionButton.button_up.connect(_on_fusion_button_up)
	%FusionTimer.timeout.connect(_on_fusion_timeout)

	%FusionPredictionIcon.global_position = %ResultSlotPosition.global_position
	
	%RefillButton.pressed.connect(_on_refill_button_pressed)
	%RefillButton.button_up.connect(_on_refill_button_up)
	%MultButton.pressed.connect(_on_mult_button_pressed)
	%MultButton.button_up.connect(_on_mult_button_up)


func _on_fusion_button_down() -> void :
	%DownPlayer.play()


func _on_fusion_button_up() -> void :
	if play_up_sound_on_next:
		%UpPlayer.play()
	play_up_sound_on_next = false


func _on_fusion_timeout() -> void :
	fusion_finished.emit(false)


func _on_fusion_button_pressed() -> void :

	if not Ref.player_fuser.can_fuse():
		play_up_sound_on_next = true
		return

	play_up_sound_on_next = false
	%FusionButton.disabled = true


	for slot in %FusionSource.get_children():
		slot.locked = true
	for slot in %FusionResult.get_children():
		slot.initialize_as_dissolved = true


	%FusionWheel.turn()
	%FusionPlayer.play()
	for slot in %FusionSource.get_children():
		if slot.item_widget != null:
			slot.item_widget.dissolve()


	%FusionTimer.start()

	var cancel: bool = await fusion_finished


	%FusionWheel.stop_turning()
	if cancel:
		for slot in %FusionSource.get_children():
			slot.locked = false
		%FusionButton.disabled = false
		%FusionPlayer.stop()
		return


	Ref.player_fuser.fuse()


	for slot in %FusionSource.get_children():
		slot.locked = false

	%FusionButton.disabled = false
	%UpPlayer.play()

	for slot in %FusionResult.get_children():
		if slot.item_widget != null:
			slot.item_widget.materialize()


func _on_refill_button_pressed() -> void :
	if %FusionButton.disabled:
		return
	%DownPlayer.play()
	Ref.player_fuser.clear_fusion_slots()
	Ref.player_fuser.refill_last_recipe()

func _on_refill_button_up() -> void :
	%UpPlayer.play()


func _on_mult_button_pressed() -> void :
	if %FusionButton.disabled:
		return
	%DownPlayer.play()
	Ref.player_fuser.multiply_recipe()

func _on_mult_button_up() -> void :
	%UpPlayer.play()


func initialize() -> void :
	%FusionSource.initialize(Ref.player_fusion_source)
	%FusionResult.initialize(Ref.player_fusion_result)


func start_processing() -> void :
	%FusionWheel.start_processing()
	%FusionInformation.force_update()


func stop_processing() -> void :
	%FusionTimer.stop()
	%FusionWheel.stop_moving()
	%FusionInformation.force_update()
	fusion_finished.emit(true)
