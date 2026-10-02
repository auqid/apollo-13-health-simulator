extends Node
## Root scene: the 3D cabin with the effects that drive it, then the HUD, notices and the debug
## panel on top.

const UiStyle := preload("res://scenes/ui/ui_style.gd")
const CabinScene := preload("res://scenes/cabin/cabin.tscn")
const Cabin := preload("res://scenes/cabin/cabin.gd")
const Effects := preload("res://fx/effects.gd")
const BioAudio := preload("res://audio/bio_audio.gd")
const Hud := preload("res://scenes/ui/hud.gd")
const Notice := preload("res://scenes/ui/notice.gd")
const DebugPanel := preload("res://scenes/ui/debug_panel.gd")
const StageCard := preload("res://scenes/ui/stage_card.gd")


func _ready() -> void:
	RenderingServer.set_default_clear_color(UiStyle.BACKDROP)
	var cabin: Cabin = CabinScene.instantiate()
	add_child(cabin)
	var effects := Effects.new()
	effects.cabin = cabin
	add_child(effects)
	add_child(BioAudio.new())
	add_child(Hud.new())
	add_child(Notice.new())
	add_child(StageCard.new())
	add_child(DebugPanel.new())
