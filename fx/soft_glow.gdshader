// Glowing gas for plasma and flashes: added onto the scene, so it brightens what is behind it.
// See soft_sprite.gdshaderinc.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

#include "res://fx/soft_sprite.gdshaderinc"
