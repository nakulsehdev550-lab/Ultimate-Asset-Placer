@tool
extends Node

enum PlaceMode  { FREE = 0, GRID = 1, SURFACE = 2, VERTEX = 3, SPLINE = 4 }
enum ScrollMode { OFF = 0, SCALE = 1, ROT_Y = 2, ROT_X = 3, ROT_Z = 4, HEIGHT = 5 }

const GHOST_ALPHA     := 0.42
const GRID_LINES      := 80
const GHOST_COLOR     := Color(0.35, 0.65, 1.00, GHOST_ALPHA)
const HOLD_DELAY      := 0.35
const HOLD_RATE_SLOW  := 0.12
const HOLD_RATE_FAST  := 0.022
const HOLD_ACCEL_TIME := 1.5
## Brush painting used to fire once per raw mouse-motion event with no gate at
## all — OS/driver mouse-move event rates vary wildly, so painting slowly
## (many events, little distance) could deposit unbounded amounts in one spot
## while a fast sweep deposited comparatively little. Gate it to a fixed wall
## clock rate instead so density is consistent regardless of input event noise.
const BRUSH_PAINT_INTERVAL_MSEC := 30

var editor_plugin: EditorPlugin = null
var panel:         Node         = null

var _is_placing:     bool    = false
var _asset_path:     String  = ""
var _ghost:          Node3D  = null
var _grid_mesh:      MeshInstance3D = null
var _lmb_down:       bool    = false
var _last_paint_pos: Vector3 = Vector3.ZERO
var _last_world_pos: Vector3 = Vector3.ZERO
var _has_valid_pos:  bool    = false
var _surface_normal: Vector3 = Vector3.UP
var _rot_x: float = 0.0; var _rot_y: float = 0.0; var _rot_z: float = 0.0
var _flip_x: bool = false; var _flip_z: bool = false
var _held_keys: Dictionary = {}

var _mm_instances:  Dictionary = {}
var _mm_transforms: Dictionary = {}
var _mm_parent:     Node3D     = null
var _mm_stroke_counts_before: Dictionary = {}
var _mm_stroke_had_paint:     bool       = false

# Vertex-snap mesh cache — rebuilding the full scene mesh list used to happen
# on EVERY mouse-motion event while in Vertex mode (a real perf cliff on
# scenes with thousands of meshes, which is exactly what this plugin is
# advertised for). Instead we cache it and only mark it dirty when the
# scene tree actually changes.
var _vertex_mesh_cache:  Array = []
var _vertex_cache_dirty: bool  = true

func _ready() -> void:
	if not Engine.is_editor_hint(): return
	var tree := get_tree()
	if tree != null:
		if not tree.node_added.is_connected(_on_scene_tree_changed):
			tree.node_added.connect(_on_scene_tree_changed)
		if not tree.node_removed.is_connected(_on_scene_tree_changed):
			tree.node_removed.connect(_on_scene_tree_changed)

func _on_scene_tree_changed(_node: Node) -> void:
	_vertex_cache_dirty = true

var _brush_ghost:        MeshInstance3D = null
var _brush_pos:          Vector3        = Vector3.ZERO
var _brush_painting:     bool           = false
var _last_brush_paint_msec: int         = 0
var _brush_radius:       float          = 2.0
var _brush_texture_path: String         = ""
var _brush_image:        Image          = null
var _brush_stroke_rids:  Array[RID]     = []

func start_placement(path: String) -> void:
	var was_placing := _is_placing
	_asset_path = path; _is_placing = true; _lmb_down = false; _has_valid_pos = false
	if not was_placing:
		_rot_x = 0.0; _rot_y = 0.0; _rot_z = 0.0
		_flip_x = false; _flip_z = false; _ensure_node3d_selected()
	
	_refresh_ghosts()
	rebuild_grid()
	if is_instance_valid(panel): panel.call("update_rot_display", _rot_x, _rot_y, _rot_z)

func refresh_ghosts() -> void:
	_refresh_ghosts()

func _refresh_ghosts() -> void:
	var mode := _get_int("place_mode")
	var use_brush := _get_bool("paint_mode") and _get_bool("paint_as_brush")
	
	if mode == PlaceMode.SPLINE:
		_remove_ghost()
		_remove_brush_ghost()
	elif use_brush:
		_remove_ghost()
		_spawn_brush_ghost()
		_brush_radius = _get_float("brush_radius") if is_instance_valid(panel) else _brush_radius
		_brush_texture_path = str(panel.get("brush_texture_path")) if is_instance_valid(panel) else _brush_texture_path
		if not _brush_texture_path.is_empty(): set_brush_texture_path(_brush_texture_path)
		_update_brush_ghost_size()
		if _has_valid_pos: _update_brush_ghost_pos(_last_world_pos)
	else:
		_remove_brush_ghost()
		_spawn_ghost(_asset_path)
		if _has_valid_pos: _move_ghost(_last_world_pos)

func set_rotation(rx: float, ry: float, rz: float) -> void:
	_rot_x = rx; _rot_y = ry; _rot_z = rz; _apply_ghost_transform()

func apply_preset_orient(rx: float, ry: float, rz: float) -> void:
	_rot_x = rx; _rot_y = ry; _rot_z = rz; _apply_ghost_transform()
	if is_instance_valid(panel): panel.call("update_rot_display", _rot_x, _rot_y, _rot_z)

func cancel_placement() -> void:
	_is_placing = false; _lmb_down = false; _has_valid_pos = false
	_held_keys.clear(); _mm_stroke_had_paint = false; _mm_stroke_counts_before.clear()
	_brush_painting = false
	_brush_stroke_rids.clear()
	_remove_ghost(); _remove_brush_ghost(); _remove_grid()
	if is_instance_valid(panel): panel.call("on_placement_stopped")

func set_brush_radius(r: float) -> void:
	_brush_radius = maxf(0.1, r)
	_update_brush_ghost_size()

func set_brush_texture_path(path: String) -> void:
	_brush_texture_path = path
	if path.is_empty():
		_brush_image = null; return
	if not ResourceLoader.exists(path): _brush_image = null; return
	var tex := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE) as Texture2D
	if tex != null:
		_brush_image = tex.get_image()
		if _brush_image != null and _brush_image.is_compressed():
			_brush_image.decompress()
		if _brush_image != null and _brush_image.get_format() != Image.FORMAT_RGBA8:
			_brush_image.convert(Image.FORMAT_RGBA8)
	else:
		_brush_image = null

func rebuild_grid() -> void:
	_remove_grid()
	if _get_int("place_mode") != PlaceMode.GRID: return
	if not is_instance_valid(panel) or not bool(panel.get("show_grid")): return
	var root := EditorInterface.get_edited_scene_root()
	if root != null and root is Node3D: _build_grid(root as Node3D)

func cleanup() -> void:
	_remove_ghost(); _remove_brush_ghost(); _remove_grid()
	_mm_instances.clear(); _mm_transforms.clear()
	_mm_stroke_counts_before.clear(); _mm_parent = null
	_brush_image = null
	_brush_stroke_rids.clear()

func instantiate_resource_pub(res: Resource) -> Node3D:
	return _instantiate_resource(res)

func _process(delta: float) -> void:
	if not _is_placing or _held_keys.is_empty(): return
	for kc in _held_keys.keys():
		var info: Dictionary = _held_keys[kc]
		info["elapsed"] += delta
		if info["elapsed"] < HOLD_DELAY: continue
		info["next_fire"] -= delta
		if info["next_fire"] <= 0.0:
			var ht: float = float(info["elapsed"]) - HOLD_DELAY
			info["next_fire"] = lerpf(HOLD_RATE_SLOW, HOLD_RATE_FAST, clampf(ht / HOLD_ACCEL_TIME, 0.0, 1.0))
			_apply_key_action(kc, info["shift"])

func handle_input(camera: Camera3D, event: InputEvent) -> bool:
	if not _is_placing: return false

	if event is InputEventMouseMotion:
		var mo := event as InputEventMouseMotion
		var lmb_held := (mo.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
		if mo.button_mask == 0 or lmb_held:
			var pos: Variant = _world_hit(camera, mo.position)
			if pos != null:
				_last_world_pos = pos; _has_valid_pos = true; _move_ghost(pos)
				var mode := _get_int("place_mode")
				var paint_enabled := _get_bool("paint_mode")
				
				if lmb_held and paint_enabled and mode != PlaceMode.SPLINE:
					if _get_bool("paint_as_brush"):
						if _brush_painting:
							var now_msec := Time.get_ticks_msec()
							if now_msec - _last_brush_paint_msec >= BRUSH_PAINT_INTERVAL_MSEC:
								_last_brush_paint_msec = now_msec
								_brush_paint(pos as Vector3)
					else:
						if _lmb_down:
							var dist := maxf(0.01, _get_float("grid_size") * _get_float("paint_spacing"))
							if (pos as Vector3).distance_to(_last_paint_pos) >= dist:
								_last_paint_pos = pos; _commit_place(pos)
		return false

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var sm := _get_int("scroll_mode")
		if sm != ScrollMode.OFF:
			if mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				if mb.pressed: _apply_scroll(sm, 1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0)
				return true
		if mb.alt_pressed and not mb.ctrl_pressed and sm == ScrollMode.OFF:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP   and mb.pressed: _nudge_height(_get_height_step()); return true
			if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed: _nudge_height(-_get_height_step()); return true
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var mode := _get_int("place_mode")
			if mb.pressed:
				if mb.alt_pressed:
					# Eyedropper: Alt+Click an already-placed object to make its
					# source asset the active one for further placement. Intent
					# here is clearly "pick", not "place", so we consume the
					# click either way rather than falling through to a normal
					# placement on a miss.
					if not _try_eyedropper(camera, mb.position) and is_instance_valid(panel):
						panel.call("set_status", "Nothing pickable under the cursor (needs a collision shape).", null)
					return true
				if mode == PlaceMode.SPLINE:
					# Spline point-editing is handled entirely by Godot's own
					# native Path3D curve editor toolbar in the 3D viewport.
					# We must NOT consume this click, and must NOT touch our
					# own click-tracking state — doing either would block or
					# interfere with that native tool.
					return false

				_lmb_down = true
				_brush_stroke_rids.clear()
				if _get_bool("paint_mode") and _get_bool("paint_as_brush"):
					_brush_painting = true
					_last_brush_paint_msec = 0
				else:
					if _get_bool("multimesh_mode"): _mm_stroke_begin()
					var pos: Variant = _world_hit(camera, mb.position)
					if pos == null and _has_valid_pos: pos = _last_world_pos
					if pos != null: _last_paint_pos = pos; _commit_place(pos)
			else:
				if mode == PlaceMode.SPLINE:
					return false
				_lmb_down = false
				_brush_painting = false
				if _get_bool("multimesh_mode"): _mm_stroke_end()
			return true
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			cancel_placement(); return true

	if event is InputEventKey:
		var ke := event as InputEventKey
		if not ke.pressed: _held_keys.erase(ke.keycode); return false
		if ke.pressed and not ke.echo:
			_held_keys[ke.keycode] = {"elapsed": 0.0, "next_fire": 0.0, "shift": ke.shift_pressed}
			return _handle_key_press(ke)

	return false

func _handle_key_press(ke: InputEventKey) -> bool:
	var k := ke.keycode
	if k == KEY_ESCAPE: cancel_placement(); return true
	if k == _get_key("flip_x"):   _flip_x = not _flip_x; _apply_ghost_transform(); return true
	if k == _get_key("flip_z"):   _flip_z = not _flip_z; _apply_ghost_transform(); return true
	if k == _get_key("reset_rot"):
		_rot_x = 0.0; _rot_y = 0.0; _rot_z = 0.0; _flip_x = false; _flip_z = false
		_sync_rot(); return true
	return _apply_key_action(k, ke.shift_pressed)

func _apply_key_action(k: int, shift: bool) -> bool:
	var snap := _get_rot_snap(); var step := snap if snap >= 0.5 else 1.0
	var d := step * (-1.0 if shift else 1.0)
	if k == _get_key("rotate_y"): _rot_y = fmod(_rot_y + d, 360.0); _sync_rot(); return true
	if k == _get_key("rotate_x"): _rot_x = fmod(_rot_x + d, 360.0); _sync_rot(); return true
	if k == _get_key("rotate_z"): _rot_z = fmod(_rot_z + d, 360.0); _sync_rot(); return true
	if k == _get_key("scale_up"):   _nudge_scale(0.1*(1.0 if not shift else 0.25)); _apply_ghost_transform(); return true
	if k == _get_key("scale_down"): _nudge_scale(-0.1*(1.0 if not shift else 0.25)); _apply_ghost_transform(); return true
	if k == _get_key("height_up"):   _nudge_height(_get_height_step()); return true
	if k == _get_key("height_down"): _nudge_height(-_get_height_step()); return true
	if k == _get_key("layer_up"):
		if is_instance_valid(panel): panel.call("nudge_grid_height", _get_float("grid_size")); return true
	if k == _get_key("layer_down"):
		if is_instance_valid(panel): panel.call("nudge_grid_height", -_get_float("grid_size")); return true
	return false

func _apply_scroll(sm: int, dir: float) -> void:
	var rs := _get_rot_snap(); if rs < 0.5: rs = 1.0
	match sm:
		ScrollMode.SCALE:  _nudge_scale(0.1*dir); _apply_ghost_transform()
		ScrollMode.ROT_Y:  _rot_y = fmod(_rot_y + rs*dir, 360.0); _sync_rot()
		ScrollMode.ROT_X:  _rot_x = fmod(_rot_x + rs*dir, 360.0); _sync_rot()
		ScrollMode.ROT_Z:  _rot_z = fmod(_rot_z + rs*dir, 360.0); _sync_rot()
		ScrollMode.HEIGHT: _nudge_height(_get_height_step()*dir)

func _nudge_scale(d: float) -> void:
	if is_instance_valid(panel): panel.call("nudge_scale", d)
func _nudge_height(d: float) -> void:
	if is_instance_valid(panel): panel.call("nudge_height", d)
func _sync_rot() -> void:
	_apply_ghost_transform()
	if is_instance_valid(panel): panel.call("update_rot_display", _rot_x, _rot_y, _rot_z)

func _get_place_path() -> String:
	if is_instance_valid(panel):
		# Prioritize manual multi-selection for random painting
		var ms_path: String = panel.call("get_random_multi_selected_path")
		if not ms_path.is_empty(): 
			return ms_path
			
		# Fallback to group random placer
		if bool(panel.get("random_group_place")):
			var rp: String = panel.call("get_random_group_path")
			if not rp.is_empty(): 
				return rp
				
	return _asset_path

func _world_hit(camera: Camera3D, mp: Vector2) -> Variant:
	if camera == null: return null
	
	if _get_bool("paint_mode") and _get_bool("paint_as_brush"):
		return _hit_surface(camera, mp)
		
	match _get_int("place_mode"):
		PlaceMode.FREE:    return _hit_plane(camera, mp, false)
		PlaceMode.GRID:    return _hit_plane(camera, mp, true)
		PlaceMode.SURFACE: return _hit_surface(camera, mp)
		PlaceMode.VERTEX:  return _hit_vertex(camera, mp)
		PlaceMode.SPLINE:  return _hit_surface(camera, mp)
	return _hit_plane(camera, mp, true)

func _hit_plane(camera: Camera3D, mp: Vector2, snap_xz: bool) -> Variant:
	var gy := _get_float("grid_height")
	var org := camera.project_ray_origin(mp); var dir := camera.project_ray_normal(mp)
	var hit: Variant = Plane(Vector3.UP, gy).intersects_ray(org, dir)
	if hit == null: hit = Vector3(org.x + dir.x*100.0, gy, org.z + dir.z*100.0)
	var p := (hit as Vector3); p.y = gy
	return _snap_xz(p) if snap_xz else p

func _hit_surface(camera: Camera3D, mp: Vector2) -> Variant:
	var root := EditorInterface.get_edited_scene_root()
	if root == null: return null
	var hit := _raycast_scene(root, camera, mp)
	if hit.is_empty(): return _hit_plane(camera, mp, false)
	_surface_normal = hit["normal"] as Vector3
	return hit["pos"] as Vector3

func _hit_vertex(camera: Camera3D, mp: Vector2) -> Variant:
	var root := EditorInterface.get_edited_scene_root()
	if root == null: return null
	var free_pos: Variant = _hit_plane(camera, mp, false)
	if free_pos == null: return null
	var fp := free_pos as Vector3

	var ghost_offsets: Array[Vector3] = []
	if is_instance_valid(_ghost):
		var gm: Array = []; _collect_meshes(_ghost, gm)
		for mi_raw in gm:
			var gmi := mi_raw as MeshInstance3D
			if gmi.mesh == null: continue
			var ab := gmi.mesh.get_aabb()
			for cx in [0,1]:
				for cy in [0,1]:
					for cz in [0,1]:
						ghost_offsets.append((gmi.global_transform*(ab.position+Vector3(ab.size.x*cx,ab.size.y*cy,ab.size.z*cz))) - _ghost.global_position)
	if ghost_offsets.is_empty(): return fp

	var best_sd   := _get_float("vertex_snap_strength")
	var best_pos: Variant = null
	if _vertex_cache_dirty:
		_vertex_mesh_cache.clear()
		_collect_meshes(root, _vertex_mesh_cache)
		_vertex_cache_dirty = false
	for mi_raw in _vertex_mesh_cache:
		var mi := mi_raw as MeshInstance3D
		if not is_instance_valid(mi) or mi.mesh == null or _is_ghost_child(mi): continue
		var xform := mi.global_transform; var aabb := mi.mesh.get_aabb()
		for cx in [0,1]:
			for cy in [0,1]:
				for cz in [0,1]:
					var tw := xform*(aabb.position+Vector3(aabb.size.x*cx,aabb.size.y*cy,aabb.size.z*cz))
					if not camera.is_position_in_frustum(tw): continue
					var t_sv := camera.unproject_position(tw)
					for goff in ghost_offsets:
						var gc := fp + goff
						if not camera.is_position_in_frustum(gc): continue
						var sd := camera.unproject_position(gc).distance_to(t_sv)
						if sd < best_sd: best_sd = sd; best_pos = fp + (tw - gc)
	return best_pos if best_pos != null else fp

func _spawn_ghost(path: String) -> void:
	_remove_ghost()
	var root := EditorInterface.get_edited_scene_root()
	if root == null or not root is Node3D:
		if is_instance_valid(panel): panel.call("set_status", "⚠ Open a 3D scene first.", null)
		return
	if not ResourceLoader.exists(path): return
	var res := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	if res == null: return
	var inst := _instantiate_resource(res)
	if inst == null: return
	_ghost = Node3D.new(); _ghost.name = "__UAP_Ghost__"
	(root as Node3D).add_child(_ghost, true); _ghost.add_child(inst, true)
	_colorize_ghost(_ghost); _apply_ghost_transform()

func _remove_ghost() -> void:
	if is_instance_valid(_ghost):
		# queue_free() is deferred, not immediate — if a new ghost is spawned
		# within the same frame (e.g. rapidly switching assets), the old one
		# would still technically be in the tree and collide on name with the
		# replacement. Rename it out of the way first, matching the same
		# defensive pattern already used for spline layer rebuilds in
		# uap_path.gd (_nodes[idx].name = "del_"+str(randi()) before queue_free).
		_ghost.name = "del_" + str(randi())
		_ghost.queue_free(); _ghost = null

func _move_ghost(world_pos: Vector3) -> void:
	if _get_bool("paint_mode") and _get_bool("paint_as_brush"):
		_brush_pos = world_pos
		_update_brush_ghost_pos(world_pos)
		return
	
	var mode := _get_int("place_mode")
	if mode == PlaceMode.SPLINE: return
	if not is_instance_valid(_ghost): return
	
	var ho := _get_float("height_offset"); var gy := _get_float("grid_height")
	var final_pos := world_pos
	
	if mode == PlaceMode.SURFACE:
		var norm := _surface_normal.normalized()
		if norm.length_squared() < 0.5: norm = Vector3.UP
		var fb := _build_surface_basis(norm)
		var mesh := _ghost_first_mesh()
		var push := _aabb_push_along_normal(mesh, fb, norm) if mesh != null else 0.0
		final_pos = world_pos + norm*(push+ho)
		var scl := _get_effective_scale()
		_ghost.global_position = final_pos
		if _get_bool("align_to_normal"): _ghost.global_basis = fb.scaled(scl)
		else: _ghost.rotation_degrees = Vector3(_rot_x,_rot_y,_rot_z); _ghost.scale = scl
		return
	elif mode == PlaceMode.GRID: final_pos.y = maxf(world_pos.y, gy) + ho
	else: final_pos.y = world_pos.y + ho
	
	_ghost.global_position = final_pos; _apply_ghost_transform()

func _apply_ghost_transform() -> void:
	if not is_instance_valid(_ghost): return
	var scl := _get_effective_scale()
	if _get_int("place_mode") == PlaceMode.SURFACE and _get_bool("align_to_normal"):
		var norm := _surface_normal.normalized()
		if norm.length_squared() < 0.5: norm = Vector3.UP
		_ghost.global_basis = _build_surface_basis(norm).scaled(scl)
	else:
		_ghost.rotation_degrees = Vector3(_rot_x,_rot_y,_rot_z); _ghost.scale = scl

func _build_surface_basis(norm: Vector3) -> Basis:
	var euler := Vector3(deg_to_rad(_rot_x), deg_to_rad(_rot_y), deg_to_rad(_rot_z))
	if norm.dot(Vector3.UP) > 0.9999:
		return Basis.from_euler(euler)
	elif norm.dot(-Vector3.UP) > 0.9999:
		return Basis.from_euler(Vector3(deg_to_rad(180.0+_rot_x), deg_to_rad(_rot_y), deg_to_rad(_rot_z)))
	else:
		return Basis(Quaternion(Vector3.UP, norm)) * Basis.from_euler(euler)

func _aabb_push_along_normal(mesh: Mesh, rot: Basis, normal: Vector3) -> float:
	if mesh == null: return 0.0
	var aabb := mesh.get_aabb(); var min_proj := INF
	for cx in [0,1]:
		for cy in [0,1]:
			for cz in [0,1]:
				min_proj = minf(min_proj, (rot*(aabb.position+Vector3(aabb.size.x*cx,aabb.size.y*cy,aabb.size.z*cz))).dot(normal))
	return 0.0 if (min_proj == INF or min_proj >= 0.0) else -min_proj

func _ghost_first_mesh() -> Mesh:
	if not is_instance_valid(_ghost): return null
	var gm: Array = []; _collect_meshes(_ghost, gm)
	for r in gm:
		if (r as MeshInstance3D).mesh != null: return (r as MeshInstance3D).mesh
	return null

func _colorize_ghost(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh == null: pass
		else:
			var mat := StandardMaterial3D.new()
			mat.albedo_color          = GHOST_COLOR
			mat.transparency          = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.shading_mode          = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.cull_mode             = BaseMaterial3D.CULL_DISABLED
			mat.render_priority       = 1
			mat.flags_no_depth_test   = true
			# Neon glow emission on ghost objects
			mat.emission_enabled      = true
			mat.emission              = Color(0.35, 0.65, 1.00, 1.0)
			mat.emission_energy_multiplier = 1.8
			var sc := mi.get_surface_override_material_count()
			if sc == 0: mi.material_override = mat
			else:
				for i in sc: mi.set_surface_override_material(i, mat)
	for c in node.get_children(): _colorize_ghost(c)

func _build_grid(root: Node3D) -> void:
	var gs := maxf(_get_float("grid_size"), 0.01); var gy := _get_float("grid_height")
	var half := float(GRID_LINES/2)*gs; var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(-(GRID_LINES/2), (GRID_LINES/2)+1):
		var c := Color(0.55,0.72,1.0,0.6) if (i%5==0) else Color(0.35,0.52,0.85,0.22)
		var co := float(i)*gs
		im.surface_set_color(c); im.surface_add_vertex(Vector3(co,gy,-half))
		im.surface_set_color(c); im.surface_add_vertex(Vector3(co,gy, half))
		im.surface_set_color(c); im.surface_add_vertex(Vector3(-half,gy,co))
		im.surface_set_color(c); im.surface_add_vertex(Vector3( half,gy,co))
	im.surface_end()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true; mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; mat.flags_do_not_receive_shadows = true
	im.surface_set_material(0, mat)
	_grid_mesh = MeshInstance3D.new(); _grid_mesh.name = "__UAP_Grid__"
	_grid_mesh.mesh = im; _grid_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(_grid_mesh, true)

func _remove_grid() -> void:
	if is_instance_valid(_grid_mesh):
		# See _remove_ghost() for why the rename-before-free is needed here.
		_grid_mesh.name = "del_" + str(randi())
		_grid_mesh.queue_free(); _grid_mesh = null

func _raycast_scene(root: Node, camera: Camera3D, mp: Vector2) -> Dictionary:
	if not root is Node3D or camera == null: return {}
	var world := (root as Node3D).get_world_3d(); if world == null: return {}
	var space := world.direct_space_state; if space == null: return {}
	var origin := camera.project_ray_origin(mp)
	var query  := PhysicsRayQueryParameters3D.create(origin, origin+camera.project_ray_normal(mp)*2000.0)
	query.collide_with_areas = false
	if is_instance_valid(_ghost):
		var excl: Array[RID] = []; _collect_rids(_ghost, excl)
		if not excl.is_empty(): query.exclude = excl
	var r := space.intersect_ray(query)
	return {} if r.is_empty() else {"pos": r["position"], "normal": r["normal"], "collider": r.get("collider")}

func _try_eyedropper(camera: Camera3D, mp: Vector2) -> bool:
	## Alt+Click on an already-placed object: picks its source asset and
	## makes it the active asset for further placement, the way most DCC/
	## level tools offer an eyedropper. Only works on objects with a
	## collision shape (it walks up from a physics raycast hit) — objects
	## placed without collision can't be picked this way, same limitation
	## Surface-mode raycasting already has.
	var root := EditorInterface.get_edited_scene_root()
	if root == null or not is_instance_valid(panel): return false
	var hit := _raycast_scene(root, camera, mp)
	if hit.is_empty(): return false
	var collider: Object = hit.get("collider")
	if collider == null or not (collider is Node): return false
	var n: Node = collider as Node
	# Walk up from the hit collider looking for the nearest ancestor that is
	# itself an instanced asset (scene_file_path set), same identity check
	# used elsewhere in the plugin (e.g. "can't place a scene inside itself").
	while n != null and n != root:
		if n is Node3D and not (n as Node3D).scene_file_path.is_empty():
			panel.call("activate_asset_from_eyedropper", (n as Node3D).scene_file_path)
			return true
		n = n.get_parent()
	return false


func _collect_rids(node: Node, out: Array[RID]) -> void:
	if node is PhysicsBody3D: out.append((node as PhysicsBody3D).get_rid())
	for c in node.get_children(): _collect_rids(c, out)

func _snap_xz(pos: Vector3) -> Vector3:
	var gs := _get_float("grid_size"); if gs <= 0.0: return pos
	return Vector3(snapped(pos.x,gs), pos.y, snapped(pos.z,gs))

func _commit_place(world_pos: Vector3) -> void:
	if _asset_path.is_empty(): return
	var root := EditorInterface.get_edited_scene_root(); if root == null: return
	var place_path := _get_place_path(); if place_path.is_empty(): return

	if _get_bool("multimesh_mode"): _mm_paint(world_pos); return

	if not ResourceLoader.exists(place_path): return
	var res := ResourceLoader.load(place_path, "", ResourceLoader.CACHE_MODE_REUSE)
	if res == null: return
	var node := _instantiate_resource(res); if node == null: return
	node.name = place_path.get_file().get_basename()

	var parent := _resolve_parent(root)
	var gy := _get_float("grid_height"); var ho := _get_float("height_offset")
	var mode := _get_int("place_mode"); var pos := world_pos
	
	# Separate normal height offset so it matches ghost logic precisely
	var norm := _surface_normal if _surface_normal.length_squared() > 0.1 else Vector3.UP
	if mode == PlaceMode.GRID: pos.y = maxf(world_pos.y,gy) + ho
	elif mode == PlaceMode.SURFACE: pos = world_pos + norm * ho
	else: pos.y = world_pos.y + ho

	if _get_bool("paint_mode") and _get_bool("paint_scatter"):
		var r := _get_float("scatter_radius"); pos.x += randf_range(-r,r); pos.z += randf_range(-r,r)

	var rx := _rot_x; var ry := _rot_y; var rz := _rot_z
	if _get_bool("random_rot"):   ry = randf_range(_get_float("rrot_min"), _get_float("rrot_max"))
	if _get_bool("random_tilt"):
		rx += randf_range(_get_float("rtilt_min"), _get_float("rtilt_max"))
		rz += randf_range(_get_float("rtilt_min"), _get_float("rtilt_max"))
	var scl := _get_effective_scale()
	if _get_bool("random_scale"): scl *= randf_range(_get_float("rscale_min"), _get_float("rscale_max"))

	var align_normal := mode == PlaceMode.SURFACE and _get_bool("align_to_normal")
	var sc  := bool(panel.get("collision_enabled"))     if is_instance_valid(panel) else false
	var cbt := int(panel.get("collision_body_type"))    if is_instance_valid(panel) else 0
	var cst := int(panel.get("collision_shape_type"))   if is_instance_valid(panel) else 0
	var cu  := bool(panel.get("collision_auto_unpack")) if is_instance_valid(panel) else true
	var mp2 := str(panel.get("material_override_path"))     if is_instance_valid(panel) else ""
	var me  := bool(panel.get("material_override_enabled")) if is_instance_valid(panel) else false
	var unpack_scenes := bool(panel.get("unpack_scenes")) if is_instance_valid(panel) else false
	var dname := place_path.get_file().get_basename()

	if editor_plugin != null:
		var ur := editor_plugin.get_undo_redo()
		_do_place(node, parent, pos, rx, ry, rz, scl, align_normal, norm, sc, cbt, cst, cu, me, mp2, unpack_scenes, place_path, dname, mode == PlaceMode.SURFACE)
		var pr := _find_placed_root(node)
		ur.create_action("UAP: Place " + dname)
		ur.add_do_method(self, "_redo_place", place_path, parent, pos, rx, ry, rz, scl, align_normal, norm, sc, cbt, cst, cu, me, mp2, unpack_scenes, place_path, dname, mode == PlaceMode.SURFACE)
		ur.add_undo_method(self, "_undo_place", pr)
		ur.commit_action(false)
	else:
		_do_place(node, parent, pos, rx, ry, rz, scl, align_normal, norm, sc, cbt, cst, cu, me, mp2, unpack_scenes, place_path, dname, mode == PlaceMode.SURFACE)

func _do_place(node: Node3D, parent: Node3D, pos: Vector3,
		rx: float, ry: float, rz: float, scl: Vector3,
		align_normal: bool, norm: Vector3,
		spawn_col: bool, btype: int, stype: int, cu: bool,
		mat_en: bool, mat_path: String, unpack_scenes: bool, 
		place_path: String, desired_name: String = "",
		is_surf_mode: bool = false) -> void:
			
	if not is_instance_valid(parent): return
	# Set a clean name BEFORE adding to tree so Godot never auto-generates @NodeXXX
	var base_name := desired_name if not desired_name.is_empty() else place_path.get_file().get_basename()
	# Sanitize: replace any invalid name characters
	base_name = base_name.replace(" ", "_")
	if base_name.is_empty(): base_name = "Asset"
	# Ensure uniqueness among siblings without relying on Godot's @NodeXXX fallback.
	# When RigidBody auto-collision is used (btype == 1) the mesh node is reparented
	# inside a "<base_name>_RB" wrapper, so parent.has_node(base_name) always returns
	# false and every tree gets the same base name → duplicate _RB names → Godot renames
	# them to @RigidBody3D@XXXXX → _find_placed_root can't detect them → undo fails.
	# Fix: also check for the _RB wrapper so each successive placement gets a fresh suffix.
	if parent.has_node(base_name) or parent.has_node(base_name + "_RB"):
		var idx := 2
		while parent.has_node("%s_%d" % [base_name, idx]) or \
			  parent.has_node("%s_%d_RB" % [base_name, idx]): idx += 1
		base_name = "%s_%d" % [base_name, idx]
	node.name = base_name
	parent.add_child(node)
	
	var root := EditorInterface.get_edited_scene_root()
	var is_packed_scene = node.scene_file_path != ""
	
	if unpack_scenes:
		_unpack(node, root)
	else:
		if is_packed_scene:
			node.owner = root
		else:
			_set_owner_recursive(node, root)

	var final_pos := pos
	var is_surf := is_surf_mode
	
	if is_surf:
		var up := norm.normalized()
		if not align_normal or up.length_squared() < 0.5: up = Vector3.UP
		
		var rb: Basis
		if align_normal: rb = _build_surface_basis_from(up, rx, ry, rz)
		else: rb = Basis.from_euler(Vector3(deg_to_rad(rx),deg_to_rad(ry),deg_to_rad(rz)))
		
		var tp := 0.0
		var meshes: Array = []; _collect_meshes(node, meshes)
		for mi_raw in meshes:
			var mi := mi_raw as MeshInstance3D
			if mi.mesh != null: tp = maxf(tp, _aabb_push_along_normal(mi.mesh, rb, up))
			
		final_pos = pos + up * tp
		
		if align_normal:
			if up.dot(Vector3.UP) > 0.9999:
				node.rotation_degrees = Vector3(rx,ry,rz); node.scale = scl
			elif up.dot(-Vector3.UP) > 0.9999:
				node.rotation_degrees = Vector3(180.0+rx,ry,rz); node.scale = scl
			else:
				node.global_basis = (Basis(Quaternion(Vector3.UP,up)) * Basis.from_euler(Vector3(deg_to_rad(rx),deg_to_rad(ry),deg_to_rad(rz)))).scaled(scl)
		else:
			node.rotation_degrees = Vector3(rx, ry, rz); node.scale = scl
	else:
		node.rotation_degrees = Vector3(rx, ry, rz); node.scale = scl
		
	node.global_position = final_pos
	
	if mat_en and not mat_path.is_empty() and ResourceLoader.exists(mat_path):
		var mat := ResourceLoader.load(mat_path, "", ResourceLoader.CACHE_MODE_REUSE) as Material
		var mm2 := int(panel.get("material_override_mode")) if is_instance_valid(panel) else 0
		if mat != null: _apply_material_override(node, mat, mm2)

	EditorInterface.get_selection().clear(); EditorInterface.get_selection().add_node(node)
	
	if spawn_col:
		_add_collision(node, btype, stype, unpack_scenes)
		_collect_rids(node, _brush_stroke_rids)

	node.scale = scl * 0.01
	var tw := node.create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(node,"scale",scl*1.10,0.09)
	tw.tween_property(node,"scale",scl*0.95,0.05)
	tw.tween_property(node,"scale",scl,0.04)

func _build_surface_basis_from(up: Vector3, rx: float, ry: float, rz: float) -> Basis:
	var euler := Vector3(deg_to_rad(rx), deg_to_rad(ry), deg_to_rad(rz))
	if up.dot(Vector3.UP) > 0.9999:      return Basis.from_euler(euler)
	elif up.dot(-Vector3.UP) > 0.9999:   return Basis.from_euler(Vector3(deg_to_rad(180.0+rx),deg_to_rad(ry),deg_to_rad(rz)))
	else: return Basis(Quaternion(Vector3.UP,up)) * Basis.from_euler(euler)

func _redo_place(asset_path: String, parent: Node3D, pos: Vector3,
		rx: float, ry: float, rz: float, scl: Vector3,
		align_normal: bool, norm: Vector3,
		spawn_col: bool, btype: int, stype: int, cu: bool,
		mat_en: bool, mat_path: String, unpack_scenes: bool, 
		place_path: String, desired_name: String, is_surf_mode: bool = false) -> void:
			
	if not ResourceLoader.exists(asset_path) or not is_instance_valid(parent): return
	var res := ResourceLoader.load(asset_path, "", ResourceLoader.CACHE_MODE_REUSE)
	if res == null: return
	var node := _instantiate_resource(res); if node == null: return
	_do_place(node, parent, pos, rx, ry, rz, scl, align_normal, norm, spawn_col, btype, stype, cu, mat_en, mat_path, unpack_scenes, place_path, desired_name, is_surf_mode)

func _find_placed_root(node: Node3D) -> Node3D:
	if not is_instance_valid(node): return node
	var par := node.get_parent()
	# When RigidBody auto-collision is used, the mesh node is reparented inside a
	# new RigidBody3D wrapper.  The wrapper is the true undo target.
	# We identify it by type (RigidBody3D) and by the naming convention
	# "<meshname>_RB" — but also accept any RigidBody3D parent whose name ends
	# with "_RB" in case Godot uniquified the mesh node name after reparenting.
	if is_instance_valid(par) and par is RigidBody3D:
		var rb := par as RigidBody3D
		if rb.name.ends_with("_RB"): return rb
	return node

func _find_placed_siblings(node: Node3D) -> Array:
	# Return the placed root plus any sibling collision nodes spawned alongside it
	var roots: Array = []
	var placed_root := _find_placed_root(node)
	roots.append(placed_root)
	if is_instance_valid(placed_root):
		var par := placed_root.get_parent()
		if is_instance_valid(par):
			# Sibling collision is named "<node_name>_Collision"
			var col_name := placed_root.name + "_Collision"
			var col := par.get_node_or_null(col_name)
			if is_instance_valid(col) and col != placed_root:
				roots.append(col)
	return roots

func _undo_place(placed_root: Node3D) -> void:
	if not is_instance_valid(placed_root): return
	# For RigidBody mode placed_root IS the RigidBody3D wrapper — its mesh child
	# and CollisionShape3D children are freed automatically with it, so no
	# sibling lookup is needed or correct.
	# For StaticBody/Area/CharacterBody (no unpack) a sibling "_Collision" body
	# was spawned next to the mesh node — remove that too.
	if not (placed_root is RigidBody3D):
		var par := placed_root.get_parent()
		if is_instance_valid(par):
			var col_name := placed_root.name + "_Collision"
			var col := par.get_node_or_null(col_name)
			if is_instance_valid(col) and col != placed_root: col.queue_free()
	placed_root.queue_free()

func _resolve_parent(root: Node) -> Node3D:
	if is_instance_valid(panel):
		var pn: Variant = panel.get("parent_node")
		if pn != null and is_instance_valid(pn as Object) and pn is Node3D: return pn as Node3D
		var pp := str(panel.get("parent_path"))
		if pp != "":
			var f := root.get_node_or_null(pp)
			if f != null and f is Node3D: return f as Node3D
	return root as Node3D

func mm_clear() -> void:
	# This previously only reset in-memory tracking (_mm_instances etc.)
	# without ever touching the scene — the "Clear" button looked like it
	# worked (status message, internal state reset) but the painted
	# MultiMesh geometry was still sitting in the scene the whole time,
	# now silently disconnected from the plugin's own bookkeeping. Painting
	# the same asset again afterward would then create a second, duplicate
	# MultiMeshInstance3D rather than continuing the (still-visible) old one.
	if is_instance_valid(_mm_parent):
		# Deferred free — rename first so an immediate repaint can't collide
		# with the not-yet-actually-removed node (see _remove_ghost() for
		# the same pattern/reasoning).
		_mm_parent.name = "del_" + str(randi())
		_mm_parent.queue_free()
	_mm_instances.clear(); _mm_transforms.clear()
	_mm_stroke_counts_before.clear(); _mm_stroke_had_paint = false; _mm_parent = null

func mm_commit_to_scene() -> void: pass

func _mm_stroke_begin() -> void:
	_mm_stroke_counts_before.clear(); _mm_stroke_had_paint = false
	for path in _mm_transforms.keys():
		_mm_stroke_counts_before[path] = (_mm_transforms[path] as Array).size()

func _mm_stroke_end() -> void:
	if not _mm_stroke_had_paint: return
	_mm_stroke_had_paint = false
	if editor_plugin == null: return
	var ur := editor_plugin.get_undo_redo()
	ur.create_action("UAP: MultiMesh Paint Stroke")
	for path in _mm_transforms.keys():
		var before: int = _mm_stroke_counts_before.get(path, 0)
		var after:  int = (_mm_transforms[path] as Array).size()
		if after > before:
			ur.add_do_method(self,   "_mm_restore_count", path, after)
			ur.add_undo_method(self, "_mm_restore_count", path, before)
	ur.commit_action(false)

func _mm_restore_count(path: String, count: int) -> void:
	if not _mm_transforms.has(path): return
	var transforms: Array = _mm_transforms[path]
	while transforms.size() > count: transforms.pop_back()
	var mmi := _mm_instances.get(path) as MultiMeshInstance3D
	if not is_instance_valid(mmi): return
	var mm := mmi.multimesh; if mm == null: return
	mm.instance_count = transforms.size()
	for i in transforms.size(): mm.set_instance_transform(i, transforms[i] as Transform3D)

func mm_generate_collision() -> void:
	if not is_instance_valid(panel): return
	var root := EditorInterface.get_edited_scene_root(); if root == null: return
	var btype := int(panel.get("collision_body_type"))
	var stype := int(panel.get("collision_shape_type"))
	if stype == 0 and btype in [1,2]: stype = 1
	var generated := 0
	for path in _mm_instances.keys():
		var mmi := _mm_instances[path] as MultiMeshInstance3D
		if not is_instance_valid(mmi): continue
		var mm := mmi.multimesh; if mm == null or mm.instance_count == 0: continue
		var base_mesh: Mesh = mm.mesh; if base_mesh == null: continue
		var shape := _make_shape(base_mesh, stype); if shape == null: continue
		# Regenerating should REPLACE this asset's collision, not accumulate a
		# second set of bodies alongside the first every time the button is
		# clicked (found while auditing node naming — this was previously
		# also a naming bug, since the accumulated duplicate would collide
		# on name; fixing the underlying accumulation is the more complete
		# fix). Remove any previous collision for this exact MultiMesh first.
		var old_body := root.get_node_or_null(mmi.name+"_Collision")
		if is_instance_valid(old_body):
			old_body.name = "del_" + str(randi())
			old_body.queue_free()
		var body_node: Node3D
		match btype:
			0: body_node = StaticBody3D.new()
			1: body_node = RigidBody3D.new()
			2: body_node = CharacterBody3D.new()
			3: body_node = Area3D.new()
			_: body_node = StaticBody3D.new()
		body_node.name = mmi.name+"_Collision"; root.add_child(body_node, true); body_node.owner = root
		for i in mm.instance_count:
			var cs := CollisionShape3D.new()
			cs.name = "Shape_%d" % i
			cs.shape = shape; cs.position = _shape_center(base_mesh, stype)
			body_node.add_child(cs, true); cs.owner = root
			cs.global_transform = mm.get_instance_transform(i)
			generated += 1
	if is_instance_valid(panel):
		panel.call("set_status",
			("Generated collision for %d instances." % generated) if generated > 0
			else "No MultiMesh instances found.", null)

func _mm_paint(world_pos: Vector3) -> void:
	var root := EditorInterface.get_edited_scene_root(); if root == null: return
	var place_path := _get_place_path(); if place_path.is_empty(): return
	if not is_instance_valid(_mm_parent):
		# Reattach to a node already in the live scene before creating a new
		# one. _mm_parent is only an in-memory reference — it does not
		# survive a scene reopen or the plugin reloading, but the actual
		# saved node does. Without this, resuming MultiMesh painting after
		# reopening the project would create a second "UAP_MultiMeshPaint"
		# node instead of continuing to use the one already there.
		var existing_parent := root.get_node_or_null("UAP_MultiMeshPaint")
		if existing_parent != null and existing_parent is Node3D:
			_mm_parent = existing_parent as Node3D
		else:
			_mm_parent = Node3D.new(); _mm_parent.name = "UAP_MultiMeshPaint"
			root.add_child(_mm_parent, true); _mm_parent.owner = root

	var ho := _get_float("height_offset"); var mode := _get_int("place_mode")
	var pos := world_pos
	if _get_bool("paint_scatter"):
		var r := _get_float("scatter_radius"); pos.x += randf_range(-r,r); pos.z += randf_range(-r,r)
	var norm := (_surface_normal if _surface_normal.length_squared()>0.1 else Vector3.UP).normalized()
	if mode == PlaceMode.SURFACE: pos = pos+norm*ho
	else: pos.y = pos.y+ho

	var rx := _rot_x; var ry := _rot_y; var rz := _rot_z
	if _get_bool("random_rot"):  ry = randf_range(_get_float("rrot_min"),_get_float("rrot_max"))
	if _get_bool("random_tilt"):
		rx += randf_range(_get_float("rtilt_min"),_get_float("rtilt_max"))
		rz += randf_range(_get_float("rtilt_min"),_get_float("rtilt_max"))
	var scl := _get_effective_scale()
	if _get_bool("random_scale"): scl *= randf_range(_get_float("rscale_min"),_get_float("rscale_max"))

	var fb: Basis
	if mode == PlaceMode.SURFACE and _get_bool("align_to_normal"):
		fb = _build_surface_basis_from(norm, rx, ry, rz)
	else:
		fb = Basis.from_euler(Vector3(deg_to_rad(rx),deg_to_rad(ry),deg_to_rad(rz)))

	var xform := Transform3D(fb.scaled(scl), pos)
	var mmi   := _mm_get_or_create(place_path, root); if mmi == null: return

	if not _mm_stroke_counts_before.has(place_path):
		_mm_stroke_counts_before[place_path] = (_mm_transforms.get(place_path, []) as Array).size()

	if not _mm_transforms.has(place_path): _mm_transforms[place_path] = []
	(_mm_transforms[place_path] as Array).append(xform)
	_mm_stroke_had_paint = true

	var transforms: Array = _mm_transforms[place_path]
	var mm := (mmi as MultiMeshInstance3D).multimesh; if mm == null: return
	mm.instance_count = transforms.size()
	for i in transforms.size(): mm.set_instance_transform(i, transforms[i] as Transform3D)

func _mm_get_or_create(path: String, root: Node) -> MultiMeshInstance3D:
	var mmi: MultiMeshInstance3D = null

	if _mm_instances.has(path):
		var ex := _mm_instances[path] as MultiMeshInstance3D
		if is_instance_valid(ex): mmi = ex

	if mmi == null:
		if not ResourceLoader.exists(path): return null
		var res := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE); if res == null: return null

		var base_mesh: Mesh = null
		if   res is Mesh:       base_mesh = res as Mesh
		elif res is PackedScene:
			var tmp := (res as PackedScene).instantiate(); if tmp == null: return null
			var ms: Array[MeshInstance3D] = []; _collect_meshes(tmp, ms)
			if not ms.is_empty() and ms[0].mesh != null: base_mesh = ms[0].mesh
			tmp.queue_free()

		if base_mesh == null: return null
		var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = base_mesh; mm.instance_count = 0
		var expected_name := "UAP_MM_"+path.get_file().get_basename()
		var par_node := _mm_parent if is_instance_valid(_mm_parent) else root
		# Same reasoning as the _mm_parent reattachment above: reuse a
		# matching node already in the live scene rather than creating a
		# disconnected duplicate alongside it.
		var existing := par_node.get_node_or_null(expected_name)
		if existing != null and existing is MultiMeshInstance3D and (existing as MultiMeshInstance3D).multimesh != null and (existing as MultiMeshInstance3D).multimesh.mesh != null:
			mmi = existing as MultiMeshInstance3D
			# Rehydrate the in-memory transform list from the existing
			# multimesh's actual instance data so painting more onto it
			# appends rather than silently restarting from empty. (Reading
			# instance transforms back out of a MultiMesh's GPU-side buffer
			# is unreliable under the dummy rendering driver used for
			# headless testing — this path is exercised and structurally
			# verified there, but exact transform-value fidelity could only
			# be confirmed in a real editor session.)
			if not _mm_transforms.has(path):
				var restored: Array = []
				for i in mmi.multimesh.instance_count: restored.append(mmi.multimesh.get_instance_transform(i))
				_mm_transforms[path] = restored
		else:
			mmi = MultiMeshInstance3D.new()
			mmi.name = expected_name; mmi.multimesh = mm
			par_node.add_child(mmi, true); _set_owner_recursive(mmi, EditorInterface.get_edited_scene_root())
		_mm_instances[path] = mmi

	# Sync material override every call (not just at creation) — otherwise
	# toggling "Enable Override" ON after an asset's MultiMeshInstance3D
	# already exists would never apply to that asset again, since the old
	# code only ever checked this once, at first-paint time.
	var me := bool(panel.get("material_override_enabled")) if is_instance_valid(panel) else false
	var mp := str(panel.get("material_override_path"))    if is_instance_valid(panel) else ""
	if me and not mp.is_empty() and ResourceLoader.exists(mp):
		var mat := ResourceLoader.load(mp, "", ResourceLoader.CACHE_MODE_REUSE) as Material
		if mat != null and mmi.material_override != mat:
			mmi.material_override = mat
	elif mmi.material_override != null:
		# Override was turned off (or path cleared/invalidated) after this
		# MultiMeshInstance3D was created — clear it back to the mesh's own
		# material rather than leaving a stale override applied forever.
		mmi.material_override = null

	return mmi

func _apply_material_override(node: Node, mat: Material, mode: int = 0) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mode == 1:
			# Next-pass mode: set surface override materials so other instances are NOT affected.
			var count := mi.get_surface_override_material_count()
			if count == 0 and mi.mesh != null:
				count = mi.mesh.get_surface_count()
			for i in count:
				# ALWAYS duplicate before mutating. Both a pre-existing per-surface
				# override (mi.get_surface_override_material) AND the mesh's own
				# baked-in material (mi.mesh.surface_get_material) can be a resource
				# SHARED across every other instance of this same asset — Godot does
				# not duplicate sub-resources on instantiate() unless they are
				# explicitly marked "local to scene", which placed assets normally
				# are not (this is especially common for imported glTF/GLB models,
				# which typically apply their materials via a per-surface override
				# slot rather than baking them into the Mesh resource). Mutating a
				# shared material's next_pass in place silently re-materializes on
				# every other placed copy of that asset, past AND future. Verified
				# empirically with a reproduction test, not assumed: the previous
				# code only duplicated when reading from mi.mesh.surface_get_material
				# and used the pre-existing override directly, unduplicated, when one
				# existed — which is the exact common case that was breaking.
				var source: Material = mi.get_surface_override_material(i)
				if source == null and mi.mesh != null:
					source = mi.mesh.surface_get_material(i)
				var existing: Material = source.duplicate(false) if source != null else StandardMaterial3D.new()
				if existing.next_pass != mat:
					existing.next_pass = mat
				mi.set_surface_override_material(i, existing)
		else:
			# Override mode: per-instance override — safe, does not affect other instances
			mi.material_override = mat
	for c in node.get_children(): _apply_material_override(c, mat, mode)

func _add_collision(node: Node3D, btype: int, stype: int, unpack_scenes: bool) -> void:
	var root := EditorInterface.get_edited_scene_root(); if root == null: return
	var eff := stype; if eff == 0 and btype in [1,2]: eff = 1
	var is_packed = node.scene_file_path != ""

	if btype == 1:
		var par := node.get_parent(); if par == null: return
		var sp := node.global_position; var sr := node.global_basis.orthonormalized(); var ss := node.scale
		par.remove_child(node)
		var rb := RigidBody3D.new()
		# Set a provisional name before add_child so Godot has something to work with,
		# then immediately correct it afterwards — Godot may have uniquified it.
		var rb_base := node.name + "_RB"
		rb.name = rb_base
		par.add_child(rb)
		# Enforce our naming convention regardless of what Godot did during add_child.
		# This guarantees the name ends with "_RB" so _find_placed_root can detect it.
		if not (rb.name as String).ends_with("_RB"):
			var safe := rb_base
			var idx2 := 2
			while par.has_node(safe): safe = "%s_%d" % [rb_base, idx2]; idx2 += 1
			rb.name = safe
		rb.owner = root; rb.global_position = sp; rb.global_basis = sr
		node.position = Vector3.ZERO; node.rotation = Vector3.ZERO; node.scale = ss
		rb.add_child(node)
		
		if unpack_scenes: _unpack(node, root)
		else: 
			if is_packed: node.owner = root 
			else: _set_owner_recursive(node, root)
		
		var meshes: Array[MeshInstance3D] = []; _collect_meshes(node, meshes)
		for mi in meshes:
			if mi.mesh == null: continue
			var cs := CollisionShape3D.new(); cs.name = "Shape"; cs.shape = _make_shape(mi.mesh, eff)
			var m2r := rb.global_transform.affine_inverse()*mi.global_transform
			cs.transform = Transform3D(m2r.basis, m2r*_shape_center(mi.mesh,eff))
			rb.add_child(cs, true); cs.owner = root
	else:
		if unpack_scenes:
			var meshes: Array[MeshInstance3D] = []; _collect_meshes(node, meshes)
			for mi in meshes:
				if not mi.mesh: continue
				match btype:
					0: _attach_body(mi, StaticBody3D.new(),    mi.mesh, eff, root)
					2: _attach_body(mi, CharacterBody3D.new(), mi.mesh, eff, root)
					3: _attach_body(mi, Area3D.new(),          mi.mesh, eff, root)
		else:
			# Spawn sibling collision next to the instantiated scene
			var parent = node.get_parent()
			if parent == null: return

			var body: CollisionObject3D
			match btype:
				0: body = StaticBody3D.new()
				2: body = CharacterBody3D.new()
				3: body = Area3D.new()
				_: body = StaticBody3D.new()
			
			body.name = node.name + "_Collision"
			parent.add_child(body, true)
			body.owner = root
			body.global_transform = node.global_transform

			var meshes: Array[MeshInstance3D] = []; _collect_meshes(node, meshes)
			for mi in meshes:
				if not mi.mesh: continue
				var cs := CollisionShape3D.new()
				cs.name = "Shape"
				cs.shape = _make_shape(mi.mesh, eff)
				var rel = node.global_transform.affine_inverse() * mi.global_transform
				cs.transform = Transform3D(rel.basis, rel * _shape_center(mi.mesh, eff))
				body.add_child(cs, true)
				cs.owner = root

func _attach_body(p: MeshInstance3D, body: Node, mesh: Mesh, st: int, root: Node) -> void:
	body.name = p.name + "_Collision"
	p.add_child(body, true); body.set_owner(root); _attach_shape(body, mesh, st, root)
	
func _attach_shape(body: Node, mesh: Mesh, st: int, root: Node) -> void:
	if mesh == null: return
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	cs.shape = _make_shape(mesh,st); cs.position = _shape_center(mesh,st)
	body.add_child(cs, true); cs.set_owner(root)
	
func _make_shape(mesh: Mesh, st: int) -> Shape3D:
	var a := mesh.get_aabb()
	match st:
		0: return mesh.create_trimesh_shape()
		1: return mesh.create_convex_shape(true,true)
		2: var b := BoxShape3D.new(); b.size   = a.size; return b
		3: var s := SphereShape3D.new();  s.radius = maxf(a.size.x,maxf(a.size.y,a.size.z))*0.5; return s
		4: var c := CapsuleShape3D.new(); c.radius = maxf(a.size.x,a.size.z)*0.5; c.height = a.size.y; return c
	return mesh.create_trimesh_shape()
	
func _shape_center(mesh: Mesh, st: int) -> Vector3:
	return mesh.get_aabb().get_center() if st in [2,3,4] else Vector3.ZERO

func _spawn_brush_ghost() -> void:
	_remove_brush_ghost()
	var root := EditorInterface.get_edited_scene_root()
	if root == null: return
	
	var mesh := TorusMesh.new()
	mesh.inner_radius = maxf(0.01, _brush_radius - 0.15)
	mesh.outer_radius = _brush_radius
	mesh.rings = 32
	mesh.ring_segments = 16
	
	var mat := StandardMaterial3D.new()
	mat.albedo_color               = Color(0.55, 0.25, 1.0, 0.75)
	mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode                  = BaseMaterial3D.CULL_DISABLED
	mat.render_priority            = 2
	mat.flags_no_depth_test        = true
	# Neon glow: emissive purple-cyan ring
	mat.emission_enabled           = true
	mat.emission                   = Color(0.70, 0.30, 1.0, 1.0)
	mat.emission_energy_multiplier = 3.5
	mesh.surface_set_material(0, mat)
	
	_brush_ghost = MeshInstance3D.new()
	_brush_ghost.name = "__UAP_BrushGhost__"
	_brush_ghost.mesh = mesh
	_brush_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(root as Node3D).add_child(_brush_ghost, true)

func _remove_brush_ghost() -> void:
	if is_instance_valid(_brush_ghost):
		# See _remove_ghost() for why the rename-before-free is needed here.
		_brush_ghost.name = "del_" + str(randi())
		_brush_ghost.queue_free(); _brush_ghost = null

func _update_brush_ghost_pos(pos: Vector3) -> void:
	if not is_instance_valid(_brush_ghost): _spawn_brush_ghost()
	if is_instance_valid(_brush_ghost):
		_brush_ghost.global_position = pos
		var mode := _get_int("place_mode")
		if mode == PlaceMode.SURFACE and _get_bool("align_to_normal") and _surface_normal.length_squared() > 0.5:
			var norm = _surface_normal.normalized()
			if norm.dot(Vector3.UP) > 0.999:
				_brush_ghost.global_basis = Basis()
			elif norm.dot(-Vector3.UP) > 0.999:
				_brush_ghost.global_basis = Basis().rotated(Vector3.RIGHT, PI)
			else:
				var axis = Vector3.UP.cross(norm).normalized()
				var angle = acos(Vector3.UP.dot(norm))
				_brush_ghost.global_basis = Basis(axis, angle)
		else:
			_brush_ghost.global_basis = Basis()

func _update_brush_ghost_size() -> void:
	if not is_instance_valid(_brush_ghost): return
	var mesh := _brush_ghost.mesh as TorusMesh
	if mesh != null:
		mesh.inner_radius = maxf(0.01, _brush_radius - 0.15)
		mesh.outer_radius = _brush_radius

func _brush_mask_sample(local_offset: Vector2) -> float:
	var falloff: float = _get_float("brush_falloff") if is_instance_valid(panel) else 0.5
	var dist := local_offset.length() / _brush_radius
	if dist >= 1.0: return 0.0
	var falloff_weight := 1.0 if falloff < 0.01 else (1.0 - pow(dist, 2.0 / maxf(falloff, 0.01)))
	falloff_weight = clampf(falloff_weight, 0.0, 1.0)
	if _brush_image == null: return falloff_weight
	var u := (local_offset.x / _brush_radius) * 0.5 + 0.5
	var v := (local_offset.y / _brush_radius) * 0.5 + 0.5
	u = clampf(u, 0.0, 1.0); v = clampf(v, 0.0, 1.0)
	var px := int(u * (_brush_image.get_width()  - 1))
	var py := int(v * (_brush_image.get_height() - 1))
	var mask_val := _brush_image.get_pixel(px, py).r
	return falloff_weight * mask_val

func _brush_paint(center: Vector3) -> void:
	if _asset_path.is_empty(): return
	var root := EditorInterface.get_edited_scene_root()
	if root == null: return
	
	var mode := _get_int("place_mode")
	var snap_surf  := (mode == PlaceMode.SURFACE)
	var align_surf := (mode == PlaceMode.SURFACE) and _get_bool("align_to_normal")
	var area       := PI * _brush_radius * _brush_radius
	var density    := _get_float("brush_density") if is_instance_valid(panel) else 0.5
	var expected   := area * density
	# Cap raised from a flat 12 (which saturated probability to ~1.0 for any
	# reasonably sized brush, making density/radius stop mattering) to 150.
	# Call frequency is now itself wall-clock throttled (BRUSH_PAINT_INTERVAL_MSEC),
	# so a higher per-call ceiling no longer risks runaway instance counts —
	# it now actually lets big/dense brushes look as dense as configured.
	var attempts   := maxi(3, int(expected * 2.5))
	attempts       = mini(attempts, 150)
	for _i in attempts:
		var angle     := randf() * TAU
		var radius    := sqrt(randf()) * _brush_radius
		var local_off := Vector2(cos(angle) * radius, sin(angle) * radius)
		var prob      := _brush_mask_sample(local_off) * (expected / float(attempts))
		if randf() > prob: continue
		var world_pt  := center + Vector3(local_off.x, 0.0, local_off.y)
		var hit_pos   := world_pt
		var hit_norm  := Vector3.UP
		if snap_surf:
			var world3d := (root as Node3D).get_world_3d()
			if world3d != null:
				var space := world3d.direct_space_state
				if space != null:
					var ray_start := world_pt + Vector3.UP * (_brush_radius + 2.0)
					var ray_end   := world_pt - Vector3.UP * (_brush_radius + 10.0)
					var query     := PhysicsRayQueryParameters3D.create(ray_start, ray_end)
					query.collide_with_areas = false
					
					var excl: Array[RID] = []
					if is_instance_valid(_ghost): _collect_rids(_ghost, excl)
					if not _brush_stroke_rids.is_empty(): excl.append_array(_brush_stroke_rids)
					
					if not excl.is_empty(): query.exclude = excl
					var r := space.intersect_ray(query)
					if not r.is_empty():
						hit_pos  = r["position"] as Vector3
						hit_norm = r["normal"]   as Vector3
		if align_surf: _surface_normal = hit_norm
		else:          _surface_normal = Vector3.UP
		_commit_place(hit_pos)

func _instantiate_resource(res: Resource) -> Node3D:
	if res is PackedScene:
		var i: Node = (res as PackedScene).instantiate()
		if i is Node3D: return i as Node3D
		i.queue_free(); return null
	if res is Mesh:
		var mi := MeshInstance3D.new(); mi.mesh = res as Mesh; return mi
	return null

func _get_effective_scale() -> Vector3:
	var s := _get_place_scale()
	if _flip_x: s.x = -absf(s.x)
	if _flip_z: s.z = -absf(s.z)
	return s

func _collect_meshes(node: Node, out: Array) -> void:
	if node is MeshInstance3D: out.append(node as MeshInstance3D)
	for c in node.get_children(): _collect_meshes(c, out)

func _is_ghost_child(node: Node) -> bool:
	if not is_instance_valid(_ghost): return false
	var cur := node
	while cur != null:
		if cur == _ghost: return true
		cur = cur.get_parent()
	return false

func _set_owner_recursive(node: Node, root: Node) -> void:
	if not is_instance_valid(node) or node == root: return
	node.owner = root
	for c in node.get_children(): _set_owner_recursive(c, root)

func _unpack(node: Node, root: Node) -> void:
	if not is_instance_valid(node): return
	if node.scene_file_path != "": node.scene_file_path = ""
	if node != root: node.set_owner(root)
	for c in node.get_children(): _unpack(c, root)

func _ensure_node3d_selected() -> void:
	var sel := EditorInterface.get_selection()
	for n in sel.get_selected_nodes(): if n is Node3D: return
	var root := EditorInterface.get_edited_scene_root()
	if is_instance_valid(root) and root is Node3D: sel.add_node(root)

func _get_bool(k: String)  -> bool:  return bool(panel.get(k))  if is_instance_valid(panel) else false
func _get_float(k: String) -> float: return float(panel.get(k)) if is_instance_valid(panel) else 0.0
func _get_int(k: String)   -> int:   return int(panel.get(k))   if is_instance_valid(panel) else 0
func _get_key(a: String) -> int:
	if is_instance_valid(panel):
		var sh := panel.get("shortcuts") as Dictionary
		if sh.has(a): return int(sh[a])
	return -1
func _get_rot_snap() -> float:
	return float(panel.call("get_rot_snap")) if is_instance_valid(panel) else 90.0
func _get_place_scale() -> Vector3:
	return panel.call("get_place_scale") as Vector3 if is_instance_valid(panel) else Vector3.ONE
func _get_height_step() -> float:
	if is_instance_valid(panel) and bool(panel.get("height_snap")):
		var gs := _get_float("grid_size"); return gs if gs > 0.0 else 1.0
	return 0.1
