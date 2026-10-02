extends Node
## Root scene: a plain dark background (the 3D cabin goes here later) with the HUD, notices and
## the debug panel.

const UiStyle := preload("res://scenes/ui/ui_style.gd")
const Hud := preload("res://scenes/ui/hud.gd")
const Notice := preload("res://scenes/ui/notice.gd")
const DebugPanel := preload("res://scenes/ui/debug_panel.gd")


func _ready() -> void:
	RenderingServer.set_default_clear_color(UiStyle.BACKDROP)
	add_child(Hud.new())
	add_child(Notice.new())
	add_child(DebugPanel.new())
