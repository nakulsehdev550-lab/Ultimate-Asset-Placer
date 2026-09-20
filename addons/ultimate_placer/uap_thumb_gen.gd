@tool
extends Node

## UAP Offline Scene Thumbnail Generator — v2.0
##
## Strategy (in order of preference):
## 1. In-memory cache (_thumb_cache in panel) — instant, already done by caller
## 2. Disk cache (user://uap_thumbnails/assets/) — instant PNG load, no re-render
## 3. EditorResourcePreview — fast, zero CPU, works for scenes Godot has seen
## 4. Offline SubViewport render — for scenes never previewed before
##
## The SubViewport uses own_world_3d + GEN_EDIT_STATE_DISABLED so the
## instantiated scene is completely isolated: no gizmos, no flicker, no physics.

signal thumbnail_ready(path: String, tex: ImageTexture)

# ── Constants ────────────────────────────────────────────────────────────────
# Resolution tiers: render/cache thumbnails at a size matched to the browser's
# current preview-size slider instead of a flat resolution for everything.
# Small preview sizes (lots of cards visible at once) get a cheap, fast,
# low-res render; large preview sizes (fewer cards, each bigger on screen)
# get a sharp, higher-res render. Each tier caches independently on disk, so
# dragging the slider back down instantly reuses whatever was already made.
const RES_TIERS: Array[int] = [64, 96, 128, 192, 256]
const THUMB_SIZE      := Vector2i(256, 256)  # legacy/max-tier fallback for callers that don't specify
var _current_tier: int = 256
const SETTLE_FRAMES   := 5
const SETTLE_FRAMES_2D := 3     # 2D settles faster
const MAX_WAIT_FRAMES := 120
# NOTE: this MUST be a different directory than plugin.gd's THUMB_CACHE_DIR.
# plugin.gd caches "live viewport screenshots" of currently-open scenes; this
# file caches "isolated studio-lit previews" of placeable assets. A .tscn file
# can be BOTH a placeable asset and a scene you open directly to edit — if the
# two systems shared a cache directory keyed by the same md5(path), whichever
# one wrote last would silently clobber the other's PNG with the wrong image.
const DISK_CACHE_DIR  := "user://uap_thumbnails/assets/"
const BG_COLOR        := Color(0.15, 0.16, 0.21, 1.0)
const BG_COLOR_2D     := Color(0.20, 0.22, 0.28, 1.0)

# ── 3D SubViewport studio ─────────────────────────────────────────────────────
var _vp:        SubViewport        = null
var _camera:    Camera3D           = null
var _sun:       DirectionalLight3D = null
var _fill:      DirectionalLight3D = null
var _rim:       DirectionalLight3D = null
var _env_node:  WorldEnvironment   = null

# ── 2D SubViewport studio ─────────────────────────────────────────────────────
var _vp2d:      SubViewport = null   # separate VP for 2D scenes

# ── 3D Queue state ────────────────────────────────────────────────────────────
var _queue:     Array  = []
var _cur_path:  String = ""
var _cur_inst:  Node   = null
var _frame:     int    = 0
var _active:    bool   = false

# ── 2D Queue state ────────────────────────────────────────────────────────────
var _queue_2d:      Array  = []
var _cur_path_2d:   String = ""
var _cur_inst_2d:   Node   = null
var _frame_2d:      int    = 0
var _active_2d:     bool   = false

# ── EditorResourcePreview state ──────────────────────────────────────────────
var _erp_pending: Dictionary = {}

# ── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	_ensure_cache_dir()
	_build_viewport()
	_build_viewport_2d()

func _ensure_cache_dir() -> void:
	DirAccess.make_dir_recursive_absolute(DISK_CACHE_DIR)

func _build_viewport() -> void:
	_vp = SubViewport.new()
	_vp.name                       = "__UAPRender__"
	_vp.size                       = Vector2i(_current_tier, _current_tier)
	_vp.msaa_3d                    = Viewport.MSAA_4X  # smooth edges — previously unset (aliased/jagged by default)
	_vp.transparent_bg             = false
	_vp.render_target_update_mode  = SubViewport.UPDATE_DISABLED
	_vp.render_target_clear_mode   = SubViewport.CLEAR_MODE_ALWAYS
	_vp.audio_listener_enable_3d   = false
	_vp.own_world_3d               = true      # completely isolated world
	_vp.world_3d                   = World3D.new()
	add_child(_vp)

	# Environment
	var env                 := Environment.new()
	env.background_mode      = Environment.BG_COLOR
	env.background_color     = BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color  = Color(0.65, 0.70, 0.85)
	env.ambient_light_energy = 0.80
	env.tonemap_mode         = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure     = 1.0; env.tonemap_white = 1.0
	env.glow_enabled  = false; env.ssao_enabled  = false
	env.ssil_enabled  = false; env.ssr_enabled   = false
	env.sdfgi_enabled = false; env.fog_enabled   = false
	_env_node             = WorldEnvironment.new()
	_env_node.environment = env
	_vp.add_child(_env_node)

	# Camera
	_camera             = Camera3D.new()
	_camera.fov         = 50.0
	_camera.near        = 0.005
	_camera.far         = 20000.0
	_camera.current     = true
	_camera.environment = env
	_vp.add_child(_camera)

	# 3-point lighting
	_sun = DirectionalLight3D.new(); _sun.shadow_enabled = false
	_sun.rotation_degrees = Vector3(-45.0, -30.0, 0.0)
	_sun.light_energy = 1.20; _sun.light_color = Color(1.00, 0.97, 0.88)
	_vp.add_child(_sun)

	_fill = DirectionalLight3D.new(); _fill.shadow_enabled = false
	_fill.rotation_degrees = Vector3(-10.0, 160.0, 0.0)
	_fill.light_energy = 0.45; _fill.light_color = Color(0.70, 0.84, 1.00)
	_vp.add_child(_fill)

	_rim = DirectionalLight3D.new(); _rim.shadow_enabled = false
	_rim.rotation_degrees = Vector3(-20.0, -150.0, 0.0)
	_rim.light_energy = 0.22; _rim.light_color = Color(0.90, 0.95, 1.00)
	_vp.add_child(_rim)

func _build_viewport_2d() -> void:
	_vp2d = SubViewport.new()
	_vp2d.name                      = "__UAPRender2D__"
	_vp2d.size                      = Vector2i(_current_tier, _current_tier)
	_vp2d.msaa_2d                   = Viewport.MSAA_4X
	_vp2d.transparent_bg            = false
	_vp2d.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp2d.render_target_clear_mode  = SubViewport.CLEAR_MODE_ALWAYS
	_vp2d.audio_listener_enable_2d  = false
	add_child(_vp2d)
	# Background colour rect
	var bg_canvas := CanvasLayer.new(); bg_canvas.name = "__UAP2DBG__"
	bg_canvas.layer = -128
	var bg_rect := ColorRect.new()
	bg_rect.color = BG_COLOR_2D
	bg_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_canvas.add_child(bg_rect)
	_vp2d.add_child(bg_canvas)

# ── Public API ────────────────────────────────────────────────────────────────
func enqueue(path: String) -> void:
	if path == _cur_path or path in _queue or _erp_pending.has(path): return
	_queue.append(path)
	if not _active: call_deferred("_next")

func enqueue_2d(path: String) -> void:
	## Enqueue a 2D / Control scene for offline rendering.
	if path == _cur_path_2d or path in _queue_2d: return
	_queue_2d.append(path)
	if not _active_2d: call_deferred("_next_2d")

func clear_queue() -> void:
	_queue.clear(); _erp_pending.clear(); _evict()
	_active = false; _cur_path = ""
	_queue_2d.clear(); _evict_2d()
	_active_2d = false; _cur_path_2d = ""

func queue_size() -> int:
	return _queue.size() + _erp_pending.size() + (1 if _active else 0)

# ── Disk Cache ────────────────────────────────────────────────────────────────
func cache_path_for(p: String) -> String:
	# Keyed by tier too -- a 64px and a 256px render of the same asset are
	# cached as separate files, so switching preview sizes never displays a
	# stale/mismatched resolution and never has to throw away the other tier.
	return DISK_CACHE_DIR + p.md5_text() + "_" + str(_current_tier) + ".png"

func resolution_tier_for_preview_size(preview_px: int) -> int:
	# Render at ~1.5x the on-screen size so it still looks crisp on HiDPI
	# displays, then snap up to the nearest available tier.
	var target := int(preview_px * 1.5)
	for t in RES_TIERS:
		if target <= t: return t
	return RES_TIERS[RES_TIERS.size() - 1]

func set_preview_resolution(preview_px: int) -> bool:
	## Called by the panel whenever the browser's preview-size slider moves.
	## Returns true if the resolution TIER actually changed (crossed a
	## boundary) so the caller knows whether already-displayed thumbnails are
	## worth refreshing at the new tier; a small slider nudge that stays
	## within the same tier is a no-op and returns false.
	var new_tier := resolution_tier_for_preview_size(preview_px)
	if new_tier == _current_tier: return false
	_current_tier = new_tier
	if is_instance_valid(_vp):
		_vp.size = Vector2i(new_tier, new_tier)
		# Cheaper AA for small/frequent tiers, nicer AA for large/rare ones —
		# small thumbnails are rendered far more often (every card in a dense
		# grid) so keep that path light; large ones are fewer and each one
		# is bigger on screen, so it's worth spending more per-render.
		_vp.msaa_3d = Viewport.MSAA_2X if new_tier <= 96 else Viewport.MSAA_4X
	if is_instance_valid(_vp2d):
		_vp2d.size = Vector2i(new_tier, new_tier)
	return true

func has_disk_cache(p: String) -> bool:
	return FileAccess.file_exists(cache_path_for(p))

func load_disk_cache(p: String) -> ImageTexture:
	var cp := cache_path_for(p)
	if not FileAccess.file_exists(cp): return null
	var img := Image.load_from_file(cp)
	if img == null or img.is_empty(): return null
	return ImageTexture.create_from_image(img)

func invalidate_cache(p: String) -> void:
	# Clears every tier's cached file for this path, not just the current one.
	for t in RES_TIERS:
		var cp := DISK_CACHE_DIR + p.md5_text() + "_" + str(t) + ".png"
		if FileAccess.file_exists(cp): DirAccess.remove_absolute(cp)

# ── Generator Loop ────────────────────────────────────────────────────────────
func _next() -> void:
	if _queue.is_empty():
		_active = false; _cur_path = ""
		if is_instance_valid(_vp):
			_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return

	_active   = true
	_cur_path = _queue.pop_front() as String
	_frame    = 0
	_evict()

	# ── 1. Disk cache fast-path ────────────────────────────────────────────
	if has_disk_cache(_cur_path):
		var cached := load_disk_cache(_cur_path)
		var done   := _cur_path
		_cur_path = ""; _active = false
		thumbnail_ready.emit(done, cached)
		call_deferred("_next"); return

	# ── 2. Try EditorResourcePreview first ────────────────────────────────
	# Godot may already have a cached preview (if the scene was ever opened).
	# If it returns null within ~2 frames, we fall back to VP render.
	_erp_pending[_cur_path] = true
	EditorInterface.get_resource_previewer().queue_resource_preview(
		_cur_path, self, "_on_erp_result", _cur_path)
	# Don't advance _active yet — _on_erp_result handles the transition

func _on_erp_result(res_path: String, preview: Texture2D,
		_small: Texture2D, userdata: Variant) -> void:
	var path := userdata as String
	if not _erp_pending.has(path): return   # stale / cleared
	_erp_pending.erase(path)

	if preview != null:
		# EditorResourcePreview succeeded — save to disk cache too
		var img := preview.get_image()
		if img != null and not img.is_empty():
			img.save_png(cache_path_for(path))
		var tex := ImageTexture.create_from_image(img) if img != null else null
		# Emit with the original Texture2D if we couldn't make ImageTexture
		var emit_tex: ImageTexture = tex
		if emit_tex == null:
			# Wrap the Texture2D preview as-is (panel accepts ImageTexture)
			# Fall through to VP render instead
			_queue_vp_render(path)
			return
		if path == _cur_path: _cur_path = ""; _active = false
		thumbnail_ready.emit(path, emit_tex)
		if not _active: call_deferred("_next")
		return

	# EditorResourcePreview returned null — fall back to SubViewport render
	_queue_vp_render(path)

func _queue_vp_render(path: String) -> void:
	## Kick off the SubViewport offline render for this path.
	## Called either immediately (when ERP returns null) or deferred.
	if path != _cur_path:
		# The panel may have moved to a different item — re-queue at front
		_queue.push_front(path)
		if not _active: call_deferred("_next")
		return
	# path == _cur_path, we're still processing the same item
	_frame = 0
	_evict()
	_vp_render_path(_cur_path)

func _vp_render_path(path: String) -> void:
	# ── Validate ───────────────────────────────────────────────────────────
	if not ResourceLoader.exists(path):
		_skip_current(); return
	# NOTE: we deliberately do NOT gate on file extension here. Imported 3D
	# formats (.glb/.gltf/.obj/.fbx/.dae/...) all load as PackedScene just
	# like a literal .tscn does — an extension allowlist previously rejected
	# every one of them from ever reaching the offline-render fallback, so if
	# EditorResourcePreview ever failed to produce a preview for one (which
	# does happen — e.g. right after a fresh import, or an import warning),
	# that asset was permanently stuck with no thumbnail. The `res is
	# PackedScene` check below is the real, sufficient safety net.

	# ── Load PackedScene ───────────────────────────────────────────────────
	# CACHE_MODE_REUSE: re-uses already loaded resource, avoids double parse.
	var res: Resource = ResourceLoader.load(path, "PackedScene",
		ResourceLoader.CACHE_MODE_REUSE)
	if res == null or not (res is PackedScene):
		_skip_current(); return

	# ── Instantiate — GEN_EDIT_STATE_DISABLED stops tool scripts / gizmos ─
	var inst: Node = (res as PackedScene).instantiate(
		PackedScene.GEN_EDIT_STATE_DISABLED)
	if not is_instance_valid(inst):
		_skip_current(); return

	# ── 2D / non-3D scene → permanent fail, emit null ─────────────────────
	if not (inst is Node3D):
		inst.queue_free()
		var done2 := _cur_path; _cur_path = ""; _active = false
		thumbnail_ready.emit(done2, null)
		call_deferred("_next"); return

	# ── Silence all processing (physics, audio, particles, animation) ──────
	_silence_node(inst)
	_cur_inst = inst
	_vp.add_child(inst)

	# ── Wait one frame so nodes fully enter tree, then fit camera ─────────
	await get_tree().process_frame
	# Defensive re-check: the plugin may have been disabled, the queue may
	# have moved on, or the instance may have been freed while we were
	# suspended. Check the viewport too, since it (and this whole node) can
	# be torn down mid-await if the editor closes or the plugin is disabled.
	if not is_instance_valid(_vp) or not is_instance_valid(_cur_inst) or _cur_path != path:
		return
	_fit_camera(inst as Node3D)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS

func _skip_current() -> void:
	var done := _cur_path
	_evict(); _cur_path = ""; _active = false
	thumbnail_ready.emit(done, null)   # null → panel marks permanent fail
	call_deferred("_next")

func _evict() -> void:
	if is_instance_valid(_cur_inst):
		if is_instance_valid(_vp) and _cur_inst.get_parent() == _vp:
			_vp.remove_child(_cur_inst)
		_cur_inst.queue_free()
		_cur_inst = null
	if is_instance_valid(_vp):
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED

# ── 2D Generator Loop ─────────────────────────────────────────────────────────
func _next_2d() -> void:
	if _queue_2d.is_empty():
		_active_2d = false; _cur_path_2d = ""
		if is_instance_valid(_vp2d):
			_vp2d.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return

	_active_2d   = true
	_cur_path_2d = _queue_2d.pop_front() as String
	_frame_2d    = 0
	_evict_2d()

	# Disk cache fast-path
	if has_disk_cache(_cur_path_2d):
		var cached := load_disk_cache(_cur_path_2d)
		var done   := _cur_path_2d
		_cur_path_2d = ""; _active_2d = false
		thumbnail_ready.emit(done, cached)
		call_deferred("_next_2d"); return

	# Validate
	if not ResourceLoader.exists(_cur_path_2d):
		_skip_current_2d(); return
	var ext := _cur_path_2d.get_extension().to_lower()
	if ext != "tscn" and ext != "scn":
		_skip_current_2d(); return

	var res: Resource = ResourceLoader.load(_cur_path_2d, "PackedScene",
		ResourceLoader.CACHE_MODE_REUSE)
	if res == null or not (res is PackedScene):
		_skip_current_2d(); return

	var inst: Node = (res as PackedScene).instantiate(
		PackedScene.GEN_EDIT_STATE_DISABLED)
	if not is_instance_valid(inst):
		_skip_current_2d(); return

	# Only handle Node2D and Control scenes here
	if not (inst is Node2D or inst is Control):
		inst.queue_free(); _skip_current_2d(); return

	_silence_node(inst)
	_cur_inst_2d = inst
	_vp2d.add_child(inst)

	var path_snapshot := _cur_path_2d
	# Wait a frame so the node enters the tree and canvas items initialise
	await get_tree().process_frame
	if not is_instance_valid(_vp2d) or not is_instance_valid(_cur_inst_2d) or _cur_path_2d != path_snapshot:
		return

	# Fit the viewport around the scene's content
	_fit_camera_2d(inst)
	_vp2d.render_target_update_mode = SubViewport.UPDATE_ALWAYS

func _process(_dt: float) -> void:
	# ── 3D capture tick ────────────────────────────────────────────────────────
	if _active and not _cur_path.is_empty():
		if not _erp_pending.has(_cur_path) and is_instance_valid(_vp):
			if _vp.render_target_update_mode != SubViewport.UPDATE_DISABLED:
				_frame += 1
				if _frame > MAX_WAIT_FRAMES:
					_skip_current()
				elif _frame >= SETTLE_FRAMES:
					var vp_tex := _vp.get_texture()
					if vp_tex != null:
						var img := vp_tex.get_image()
						if img != null and not img.is_empty():
							_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
							_smart_crop(img)
							img = _fit_into_square(img, _current_tier)
							img.save_png(cache_path_for(_cur_path))
							var tex  := ImageTexture.create_from_image(img)
							var done := _cur_path
							_evict(); _cur_path = ""; _active = false
							thumbnail_ready.emit(done, tex)
							call_deferred("_next")

	# ── 2D capture tick ────────────────────────────────────────────────────────
	if _active_2d and not _cur_path_2d.is_empty() and is_instance_valid(_vp2d):
		if _vp2d.render_target_update_mode != SubViewport.UPDATE_DISABLED:
			_frame_2d += 1
			if _frame_2d > MAX_WAIT_FRAMES:
				_skip_current_2d()
			elif _frame_2d >= SETTLE_FRAMES_2D:
				var vp_tex2 := _vp2d.get_texture()
				if vp_tex2 != null:
					var img2 := vp_tex2.get_image()
					if img2 != null and not img2.is_empty():
						_vp2d.render_target_update_mode = SubViewport.UPDATE_DISABLED
						img2.resize(_current_tier, _current_tier, Image.INTERPOLATE_LANCZOS)
						img2.save_png(cache_path_for(_cur_path_2d))
						var tex2  := ImageTexture.create_from_image(img2)
						var done2 := _cur_path_2d
						_evict_2d(); _cur_path_2d = ""; _active_2d = false
						thumbnail_ready.emit(done2, tex2)
						call_deferred("_next_2d")

func _skip_current_2d() -> void:
	var done := _cur_path_2d
	_evict_2d(); _cur_path_2d = ""; _active_2d = false
	thumbnail_ready.emit(done, null)
	call_deferred("_next_2d")

func _evict_2d() -> void:
	if is_instance_valid(_cur_inst_2d):
		if is_instance_valid(_vp2d) and _cur_inst_2d.get_parent() == _vp2d:
			_vp2d.remove_child(_cur_inst_2d)
		_cur_inst_2d.queue_free()
		_cur_inst_2d = null
	if is_instance_valid(_vp2d):
		_vp2d.render_target_update_mode = SubViewport.UPDATE_DISABLED

# ── 2D Camera Fitting ─────────────────────────────────────────────────────────
func _fit_camera_2d(root: Node) -> void:
	## Adjusts the 2D SubViewport canvas transform so the scene content fills
	## the thumbnail. Collects all CanvasItem global rects, then scales/offsets.
	var rect := _collect_rect2d(root)

	if rect.size.length() < 2.0:
		# No detectable 2D content — use a default full-screen region
		rect = Rect2(Vector2.ZERO, Vector2(1152, 648))

	# Add padding
	rect = rect.grow(maxf(rect.size.x, rect.size.y) * 0.05)

	# Scale the viewport canvas so the content fills the current render tier
	var scale_x := float(_current_tier) / maxf(rect.size.x, 1.0)
	var scale_y := float(_current_tier) / maxf(rect.size.y, 1.0)
	var scale   := minf(scale_x, scale_y)   # uniform scale, no stretch

	# Offset so rect.position maps to canvas origin
	var offset := -rect.position * scale

	# Centre if one axis has padding
	var render_w := rect.size.x * scale
	var render_h := rect.size.y * scale
	offset.x += (_current_tier - render_w) * 0.5
	offset.y += (_current_tier - render_h) * 0.5

	var xf := Transform2D(0.0, Vector2(scale, scale), 0.0, offset)
	_vp2d.canvas_transform = xf

func _collect_rect2d(node: Node) -> Rect2:
	return _collect_rect2d_r(node, Rect2(), false)[0]

func _collect_rect2d_r(node: Node, r: Rect2, started: bool) -> Array:
	if node is CanvasItem:
		var ci := node as CanvasItem
		if ci.visible:
			var item_rect := Rect2()
			if ci is Control:
				item_rect = Rect2((ci as Control).global_position, (ci as Control).size)
				if item_rect.size.length() > 0.5:
					r = item_rect if not started else r.merge(item_rect); started = true
			elif ci is Node2D:
				var n2 := ci as Node2D
				# Try Sprite2D/AnimatedSprite2D texture size
				var sz := Vector2(64, 64)
				if n2 is Sprite2D and (n2 as Sprite2D).texture != null:
					sz = Vector2((n2 as Sprite2D).texture.get_size())
				elif n2 is AnimatedSprite2D:
					var asp := n2 as AnimatedSprite2D
					if asp.sprite_frames != null:
						var frames := asp.sprite_frames
						if frames.get_animation_names().size() > 0:
							var anim := frames.get_animation_names()[0]
							if frames.get_frame_count(anim) > 0:
								var tex := frames.get_frame_texture(anim, 0)
								if tex != null: sz = Vector2(tex.get_size())
				item_rect = Rect2(n2.global_position - sz * 0.5, sz)
				r = item_rect if not started else r.merge(item_rect); started = true
	for c in node.get_children():
		var result := _collect_rect2d_r(c, r, started)
		r = result[0]; started = result[1]
	return [r, started]

func _fit_camera(root: Node3D) -> void:
	# Collect AABB from all visual geometry
	var aabb := _collect_aabb(root, Transform3D.IDENTITY)

	# If no mesh geometry found, try to use all Node3D positions as bounds
	if aabb.size.length_squared() < 0.0001:
		aabb = _collect_positions(root, Transform3D.IDENTITY)

	# Final fallback — generic box that works for most humanoid/vehicle scales
	if aabb.size.length_squared() < 0.0001:
		aabb = AABB(Vector3(-1.0, 0.0, -1.0), Vector3(2.0, 2.0, 2.0))

	var center := aabb.get_center()
	var dir     := Vector3(0.60, 0.50, 1.00).normalized()

	# Build the camera's basis for this fixed viewing direction so we can
	# measure the AABB's ACTUAL projected extent along the camera's right/up
	# axes, instead of using the full diagonal as a blanket radius (which
	# treats every object as if it were bounded by a sphere — very
	# conservative for long/thin or flat assets like fences, planks, or
	# floor tiles, leaving them small and adrift in the frame instead of
	# filling it the way a properly centered, well-composed thumbnail should).
	var fwd   := -dir
	var right := fwd.cross(Vector3.UP)
	if right.length_squared() < 0.0001: right = Vector3.RIGHT
	right = right.normalized()
	var up := right.cross(fwd).normalized()

	var max_right := 0.0
	var max_up    := 0.0
	for i in 8:
		var corner := aabb.position + Vector3(
			aabb.size.x * float(i & 1),
			aabb.size.y * float((i >> 1) & 1),
			aabb.size.z * float((i >> 2) & 1))
		var rel := corner - center
		max_right = maxf(max_right, absf(rel.dot(right)))
		max_up    = maxf(max_up,    absf(rel.dot(up)))
	max_right = maxf(max_right, 0.05)
	max_up    = maxf(max_up, 0.05)

	# Thumbnails always render into a square viewport, so horizontal and
	# vertical FOV are equal here — fit whichever axis is the binding
	# constraint for this particular object's proportions.
	var fov_r  := deg_to_rad(_camera.fov * 0.5)
	var dist   := maxf(max_up, max_right) / tan(fov_r)
	dist *= 1.18   # small padding margin so the object doesn't touch the edge
	dist = maxf(dist, 0.5)

	_camera.global_position = center + dir * dist
	_camera.look_at(center, Vector3.UP)
	_camera.near = maxf(0.005, dist * 0.002)
	_camera.far  = maxf(1000.0, dist * 50.0)

func _collect_aabb(node: Node, pxf: Transform3D) -> AABB:
	var xf := pxf
	if node is Node3D: xf = pxf * (node as Node3D).transform
	var r := AABB()

	# MeshInstance3D — most common
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var a := xf * mi.mesh.get_aabb()
			r = a if r.size.length_squared() < 0.0001 else r.merge(a)

	# MultiMeshInstance3D
	elif node is MultiMeshInstance3D:
		var mmi := node as MultiMeshInstance3D
		if mmi.multimesh != null and mmi.multimesh.mesh != null:
			var a := xf * mmi.multimesh.mesh.get_aabb()
			r = a if r.size.length_squared() < 0.0001 else r.merge(a)

	# CSG shapes, Sprite3D/AnimatedSprite3D, Label3D, decals, particles, and any
	# other VisualInstance3D — all of these expose a real get_aabb() that Godot
	# computes from their actual generated geometry. Verified empirically: one
	# process_frame after entering the tree (which is exactly when _fit_camera
	# runs) is enough for CSG shapes to report their true, correct bounds — so
	# we use the real box instead of a guessed proxy, and only fall back to a
	# proxy if the engine genuinely has nothing yet (size still zero).
	elif node is VisualInstance3D:
		var vis := node as VisualInstance3D
		var real_aabb := vis.get_aabb()
		var a: AABB
		if real_aabb.size.length_squared() > 0.0001:
			a = xf * real_aabb
		elif node is CSGShape3D:
			var sz := Vector3(2.0, 2.0, 2.0)   # safe default, only used pre-rebuild
			a = xf * AABB(Vector3(-sz.x, -sz.y, -sz.z) * 0.5, sz)
		else:
			a = xf * AABB(Vector3(-0.5, -0.5, -0.5), Vector3(1.0, 1.0, 1.0))
		r = a if r.size.length_squared() < 0.0001 else r.merge(a)

	for c in node.get_children():
		var ca := _collect_aabb(c, xf)
		if ca.size.length_squared() > 0.0001:
			r = ca if r.size.length_squared() < 0.0001 else r.merge(ca)
	return r

func _collect_positions(node: Node, pxf: Transform3D) -> AABB:
	## Fallback: builds a bounding box from Node3D positions so the camera
	## is at least centered on the scene hierarchy even with no mesh data.
	var xf := pxf
	if node is Node3D: xf = pxf * (node as Node3D).transform
	var r  := AABB()
	if node is Node3D:
		var pos := xf.origin
		var dot := AABB(pos - Vector3(0.5,0.5,0.5), Vector3(1,1,1))
		r = dot if r.size.length_squared() < 0.0001 else r.merge(dot)
	for c in node.get_children():
		var ca := _collect_positions(c, xf)
		if ca.size.length_squared() > 0.0001:
			r = ca if r.size.length_squared() < 0.0001 else r.merge(ca)
	return r

# ── Silence Node ─────────────────────────────────────────────────────────────
func _silence_node(n: Node) -> void:
	n.set_process(false); n.set_physics_process(false)
	n.set_process_input(false); n.set_process_unhandled_input(false)
	n.set_process_unhandled_key_input(false)
	n.set_process_internal(false); n.set_physics_process_internal(false)
	if n is AnimationPlayer:
		(n as AnimationPlayer).active  = false
		(n as AnimationPlayer).autoplay = ""
	if n is AnimationTree:       (n as AnimationTree).active           = false
	if n is AudioStreamPlayer:   (n as AudioStreamPlayer).playing      = false
	if n is AudioStreamPlayer3D: (n as AudioStreamPlayer3D).playing    = false
	if n is CollisionShape3D:    (n as CollisionShape3D).disabled      = true
	if n is CollisionPolygon3D:  (n as CollisionPolygon3D).disabled    = true
	if n is RigidBody3D:         (n as RigidBody3D).freeze             = true
	if n is Area3D:
		(n as Area3D).monitoring = false; (n as Area3D).monitorable = false
	if n is GPUParticles3D: (n as GPUParticles3D).emitting = false
	if n is CPUParticles3D: (n as CPUParticles3D).emitting = false
	for c in n.get_children(): _silence_node(c)

# ── Fit into square ────────────────────────────────────────────────────────────
# Scales img proportionally to fit within size x size, then centers it on a
# transparent background canvas of exactly size x size.  This prevents the
# stretching that occurs when a non-square cropped image is force-resized.
func _fit_into_square(img: Image, size: int) -> Image:
	var sw := img.get_width(); var sh := img.get_height()
	if sw <= 0 or sh <= 0:
		return img
	var scale := minf(float(size) / float(sw), float(size) / float(sh))
	var nw := maxi(1, int(sw * scale)); var nh := maxi(1, int(sh * scale))
	img.resize(nw, nh, Image.INTERPOLATE_LANCZOS)
	if nw == size and nh == size:
		return img
	var canvas := Image.create(size, size, true, img.get_format())
	canvas.fill(Color(0, 0, 0, 0))
	var ox := (size - nw) / 2; var oy := (size - nh) / 2
	canvas.blit_rect(img, Rect2i(0, 0, nw, nh), Vector2i(ox, oy))
	return canvas

# ── Smart Crop ────────────────────────────────────────────────────────────────
func _smart_crop(img: Image) -> void:
	if img.get_width() < 32 or img.get_height() < 32: return
	var bg := img.get_pixel(0, 0); var t := 0.06
	var x0 := 0; var y0 := 0
	var x1 := img.get_width() - 1; var y1 := img.get_height() - 1
	while x0 < x1 - 8 and _col_is_bg(img, x0,  y0, y1, bg, t): x0 += 1
	while x1 > x0 + 8 and _col_is_bg(img, x1,  y0, y1, bg, t): x1 -= 1
	while y0 < y1 - 8 and _row_is_bg(img, y0, x0, x1, bg, t):  y0 += 1
	while y1 > y0 + 8 and _row_is_bg(img, y1, x0, x1, bg, t):  y1 -= 1
	var pad := 8
	x0 = max(0,x0-pad); y0 = max(0,y0-pad)
	x1 = min(img.get_width()-1,x1+pad); y1 = min(img.get_height()-1,y1+pad)
	var w := x1-x0; var h := y1-y0
	if w>16 and h>16 and (x0>2 or y0>2 or x1<img.get_width()-3 or y1<img.get_height()-3):
		img.copy_from(img.get_region(Rect2i(x0,y0,w,h)))

func _col_is_bg(img:Image,x:int,y0:int,y1:int,bg:Color,t:float)->bool:
	var step := max(1,(y1-y0)/10)
	for y in range(y0,y1,step):
		var c:=img.get_pixel(x,y)
		if absf(c.r-bg.r)+absf(c.g-bg.g)+absf(c.b-bg.b)>t*3.0: return false
	return true

func _row_is_bg(img:Image,y:int,x0:int,x1:int,bg:Color,t:float)->bool:
	var step := max(1,(x1-x0)/10)
	for x in range(x0,x1,step):
		var c:=img.get_pixel(x,y)
		if absf(c.r-bg.r)+absf(c.g-bg.g)+absf(c.b-bg.b)>t*3.0: return false
	return true
