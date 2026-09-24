@tool
extends Node

## UAP Offline Scene Thumbnail Generator — v3 (RECTANGULAR STUDIO)
##
## Every asset thumbnail is rendered by this plugin's own isolated SubViewport
## "studio". EditorResourcePreview is NO LONGER used for the asset browser:
## the editor's previews are small SQUARE images that pillarboxed with ugly
## side bars inside the card's rectangular thumbnail well and turned blurry
## the moment the preview-size slider went up. Self-rendering fixes all of
## that in one move:
##
##   • The SubViewport is sized at the EXACT aspect ratio of the card's
##     thumbnail well (the panel pushes the well's pixel size in via
##     set_preview_metrics). The image and the well share one aspect ratio,
##     so the texture fills the well edge-to-edge — no black bars, no
##     letterboxing, no cropping, at every preview size.
##   • Resolution scales with the well: the long side renders at ~1.5x the
##     on-screen size (HiDPI crisp), snapped to RES_TIERS. Big cards get
##     genuinely sharper thumbnails, not upscaled 128px squares.
##   • Every render is disk-cached PER RENDER SIZE (assets_r3/), so
##     generation is a one-time cost per size — the next session and the
##     next slider visit are instant PNG loads.
##   • Bare Mesh resources (.obj/.mesh/... — everything that is NOT a
##     PackedScene) are wrapped in a MeshInstance3D and rendered like any
##     other 3D asset. Node2D/Control scenes are routed to the 2D studio.
##
## The SubViewport uses own_world_3d + GEN_EDIT_STATE_DISABLED so the
## instantiated scene is completely isolated: no gizmos, no flicker, no
## physics, no tool-script side effects.

signal thumbnail_ready(path: String, tex: ImageTexture)

# ── Constants ────────────────────────────────────────────────────────────────
# Resolution tiers for the render's LONG side. The panel pushes the on-screen
# well size in; we render at ~1.5x that (HiDPI headroom) and snap the long
# side up to the nearest tier. The short side follows the exact well aspect.
const RES_TIERS: Array[int] = [64, 96, 128, 192, 256, 320]
const SETTLE_FRAMES   := 5
const SETTLE_FRAMES_2D := 3     # 2D settles faster
const MAX_WAIT_FRAMES := 120
# v3 cache directory — keyed PER RENDER SIZE ("{md5}_{w}x{h}.png"). This is a
# NEW directory on purpose: the old assets/ folder holds SQUARE letterboxed
# PNGs from the v2 generator, and reusing them would put the black bars right
# back. The legacy folder is emptied on startup (best effort).
# NOTE: this MUST be a different directory than plugin.gd's THUMB_CACHE_DIR
# (scenes/). plugin.gd caches "live viewport screenshots" of currently-open
# scenes; this file caches "isolated studio-lit previews" of placeable
# assets. A .tscn file can be BOTH a placeable asset and a scene you open
# directly to edit — if the two systems shared a cache directory keyed by the
# same md5(path), whichever one wrote last would silently clobber the other's
# PNG with the wrong image.
const DISK_CACHE_DIR     := "user://uap_thumbnails/assets_r3/"
const LEGACY_CACHE_DIRS: Array[String] = [
        "user://uap_thumbnails/assets/",   # v2 square letterboxed cache
]
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

# ── Render size ───────────────────────────────────────────────────────────────
# Exact well aspect at ~1.5x resolution. Default is a sane 4:3-ish start;
# the panel overwrites it via set_preview_metrics() right after instancing.
var _render_size := Vector2i(256, 200)

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

# ── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
        _ensure_cache_dir()
        _purge_legacy_caches()
        _build_viewport()
        _build_viewport_2d()

func _ensure_cache_dir() -> void:
        DirAccess.make_dir_recursive_absolute(DISK_CACHE_DIR)

func _purge_legacy_caches() -> void:
        ## Best-effort cleanup: delete the v2 SQUARE cache files so they stop
        ## wasting disk space. Silent — a locked file must never break startup.
        for d in LEGACY_CACHE_DIRS:
                var da := DirAccess.open(d)
                if da == null: continue
                for f in da.get_files():
                        DirAccess.remove_absolute(d + f)

func _build_viewport() -> void:
        _vp = SubViewport.new()
        _vp.name                       = "__UAPRender__"
        _vp.size                       = _render_size
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
        _vp2d.size                      = _render_size
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
        if path == _cur_path or path in _queue: return
        _queue.append(path)
        if not _active: call_deferred("_next")

func enqueue_2d(path: String) -> void:
        ## Enqueue a 2D / Control scene for offline rendering.
        ## Also used internally: the 3D queue routes Node2D/Control roots here.
        if path == _cur_path_2d or path in _queue_2d: return
        _queue_2d.append(path)
        if not _active_2d: call_deferred("_next_2d")

func clear_queue() -> void:
        _queue.clear()
        _active = false; _cur_path = ""
        _evict()
        _queue_2d.clear()
        _active_2d = false; _cur_path_2d = ""
        _evict_2d()

func queue_size() -> int:
        return _queue.size() + _queue_2d.size() + (1 if _active else 0) + (1 if _active_2d else 0)

# ── Render Size / Cache ───────────────────────────────────────────────────────
func set_preview_metrics(thumb_w: int, thumb_h: int) -> bool:
        ## Called by the panel with the card thumbnail well's EXACT pixel size
        ## (the same _card_thumb_metrics() formula the cards are built with).
        ## Sizes the studio viewports at that aspect ratio and ~1.5x the long
        ## side (snapped to RES_TIERS) so thumbnails stay crisp on HiDPI and
        ## on large cards. Returns true if the render size actually changed —
        ## the caller then drops its in-memory textures so cards re-fetch at
        ## the new size; a small slider nudge inside the same tier is a no-op.
        var long_side := maxi(thumb_w, thumb_h)
        var target := int(long_side * 1.5)
        var tier := RES_TIERS[RES_TIERS.size() - 1]
        for t in RES_TIERS:
                if target <= t:
                        tier = t
                        break
        var asp := float(maxi(1, thumb_w)) / float(maxi(1, thumb_h))
        var rw: int
        var rh: int
        if asp >= 1.0:
                rw = tier; rh = maxi(2, int(round(float(tier) / asp)))
        else:
                rh = tier; rw = maxi(2, int(round(float(tier) * asp)))
        rw &= ~1; rh &= ~1   # even dimensions — clean Lanczos halving if ever needed
        var sz := Vector2i(rw, rh)
        if sz == _render_size: return false
        _render_size = sz
        if is_instance_valid(_vp):
                _vp.size = sz
                # Cheaper AA for the small/frequent tiers, nicer AA for the
                # large/rare ones — small thumbnails render far more often
                # (every card in a dense grid), large ones are fewer but each
                # is big on screen, so it's worth spending more per render.
                _vp.msaa_3d = Viewport.MSAA_2X if tier <= 128 else Viewport.MSAA_4X
        if is_instance_valid(_vp2d):
                _vp2d.size = sz
                _vp2d.msaa_2d = Viewport.MSAA_2X if tier <= 128 else Viewport.MSAA_4X
        return true

func cache_path_for(p: String) -> String:
        # Keyed by the EXACT render size ("{md5}_{w}x{h}.png") — a 128x96 and
        # a 320x240 render of the same asset are separate files, so switching
        # preview sizes never displays a stale/mismatched resolution and never
        # has to throw away the other size.
        return DISK_CACHE_DIR + p.md5_text() + "_%dx%d.png" % [_render_size.x, _render_size.y]

func has_disk_cache(p: String) -> bool:
        return FileAccess.file_exists(cache_path_for(p))

func load_disk_cache(p: String) -> ImageTexture:
        var cp := cache_path_for(p)
        if not FileAccess.file_exists(cp): return null
        var img := Image.load_from_file(cp)
        if img == null or img.is_empty(): return null
        return ImageTexture.create_from_image(img)

func invalidate_cache(p: String) -> void:
        # Clears EVERY cached size for this path (all files sharing its md5).
        var prefix := p.md5_text() + "_"
        var da := DirAccess.open(DISK_CACHE_DIR)
        if da == null: return
        for f in da.get_files():
                if f.begins_with(prefix):
                        DirAccess.remove_absolute(DISK_CACHE_DIR + f)

# ── Generator Loop ────────────────────────────────────────────────────────────
func _next() -> void:
        # RE-ENTRANCY GUARD: enqueue() defers one _next() call per item when
        # idle, and several enqueues can land in the same frame — so two
        # deferred _next() calls can fire back-to-back. Without this guard the
        # second call saw an empty queue and reset _active/_cur_path to idle
        # WHILE the first call's render was awaiting its settle frame, which
        # made that render's defensive re-check abort silently — its asset
        # stayed in the panel's pending map forever and never re-rendered
        # (observed as a card whose thumbnail never appeared at a new size).
        if _active: return
        if _queue.is_empty():
                _active = false; _cur_path = ""
                if is_instance_valid(_vp):
                        _vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
                return

        _active   = true
        _cur_path = _queue.pop_front() as String
        _frame    = 0
        _evict()

        # Disk cache fast-path — instant PNG load, no re-render.
        if has_disk_cache(_cur_path):
                var cached := load_disk_cache(_cur_path)
                var done   := _cur_path
                _cur_path = ""; _active = false
                thumbnail_ready.emit(done, cached)
                call_deferred("_next"); return

        # Straight to the offline studio render. (v2 tried EditorResourcePreview
        # here first — its small SQUARE previews were exactly what the user
        # rejected: pillarboxed bars in the rectangular wells and blurry upscale
        # on big cards. Everything now gets the consistent studio treatment.)
        _vp_render_path(_cur_path)

func _vp_render_path(path: String) -> void:
        # ── Validate ───────────────────────────────────────────────────────────
        if not ResourceLoader.exists(path):
                _skip_current(); return
        # NOTE: we deliberately do NOT gate on file extension here. Imported 3D
        # formats (.glb/.gltf/.obj/.fbx/.dae/...) and bare Mesh resources all
        # arrive through the same door — the type checks below are the real,
        # sufficient safety net.

        # Load WITHOUT a type hint: the file may be a PackedScene (.tscn/.glb/
        # .fbx/...) OR a bare Mesh resource (.obj imports as Mesh by default in
        # Godot 4 — those were previously invisible to the offline renderer and
        # had to fall back to the editor's small square previews).
        var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
        if res == null:
                _skip_current(); return

        var inst: Node = null
        if res is PackedScene:
                # GEN_EDIT_STATE_DISABLED stops tool scripts / edit gizmos.
                inst = (res as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_DISABLED)
        elif res is Mesh:
                # Bare mesh (obj/dae/mesh/res/...) → wrap and render directly.
                var mi := MeshInstance3D.new()
                mi.mesh = res as Mesh
                inst = mi
        if not is_instance_valid(inst):
                _skip_current(); return

        # ── 2D / non-3D scene → route to the 2D studio queue ──────────────────
        if not (inst is Node3D):
                _clear_override_slots(inst)
                inst.queue_free()
                var routed := _cur_path
                _cur_path = ""; _active = false
                enqueue_2d(routed)
                call_deferred("_next")
                return

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
                # Godot bug #85817 hardening: assets routinely reference SHARED
                # materials via override slots (material_override + per-surface
                # overrides). Deleting such an instance makes the renderer's
                # deferred update process the now-dangling RIDs and spam
                # "Parameter material is null" four times per instance. Wipe
                # the override slots while the instance is still alive.
                _clear_override_slots(_cur_inst)
                _cur_inst.queue_free()
                _cur_inst = null
        if is_instance_valid(_vp):
                _vp.render_target_update_mode = SubViewport.UPDATE_DISABLED

# ── 2D Generator Loop ─────────────────────────────────────────────────────────
func _next_2d() -> void:
        if _active_2d: return   # same re-entrancy guard as _next()
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
                _clear_override_slots(inst)
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
                if is_instance_valid(_vp):
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
                                                        # The viewport is ALREADY at the card well's exact
                                                        # aspect ratio and resolution — save as-is. (v2
                                                        # smart-cropped pixel-by-pixel and letterboxed the
                                                        # result onto a square transparent canvas, which is
                                                        # where every black bar came from.)
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
                # Same Godot bug #85817 hardening as _evict().
                _clear_override_slots(_cur_inst_2d)
                _cur_inst_2d.queue_free()
                _cur_inst_2d = null
        if is_instance_valid(_vp2d):
                _vp2d.render_target_update_mode = SubViewport.UPDATE_DISABLED

## Wipes material_override / material_overlay / every per-surface override on
## a node tree. See _evict() for the Godot bug #85817 rationale.
func _clear_override_slots(node: Node) -> void:
        if node is MeshInstance3D:
                var mi := node as MeshInstance3D
                if mi.material_override != null: mi.material_override = null
                if mi.material_overlay != null: mi.material_overlay = null
                var sc := mi.get_surface_override_material_count()
                for i in sc:
                        if mi.get_surface_override_material(i) != null:
                                mi.set_surface_override_material(i, null)
        for c in node.get_children(): _clear_override_slots(c)

# ── 2D Camera Fitting ─────────────────────────────────────────────────────────
func _fit_camera_2d(root: Node) -> void:
        ## Adjusts the 2D SubViewport canvas transform so the scene content fills
        ## the render (which is already at the card well's aspect ratio).
        ## Collects all CanvasItem global rects, then scales/offsets. Content
        ## with a different aspect than the well is letterboxed on the studio's
        ## flat background colour — a deliberate, uniform look for UI scenes.
        var rect := _collect_rect2d(root)

        if rect.size.length() < 2.0:
                # No detectable 2D content — use a default full-screen region
                rect = Rect2(Vector2.ZERO, Vector2(1152, 648))

        # Add padding
        rect = rect.grow(maxf(rect.size.x, rect.size.y) * 0.05)

        var vw := float(_vp2d.size.x)
        var vh := float(_vp2d.size.y)

        # Scale the viewport canvas so the content fits inside the render
        var scale_x := vw / maxf(rect.size.x, 1.0)
        var scale_y := vh / maxf(rect.size.y, 1.0)
        var scale   := minf(scale_x, scale_y)   # uniform scale, no stretch

        # Offset so rect.position maps to canvas origin
        var offset := -rect.position * scale

        # Centre if one axis has padding
        var render_w := rect.size.x * scale
        var render_h := rect.size.y * scale
        offset.x += (vw - render_w) * 0.5
        offset.y += (vh - render_h) * 0.5

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

        # The render viewport is RECTANGULAR (exact card-well aspect), so the
        # horizontal and vertical FOV differ. Camera3D.fov is the VERTICAL fov
        # (keep_aspect = KEEP_HEIGHT); tan(hfov/2) = tan(vfov/2) * aspect. Fit
        # whichever axis is the binding constraint for this object's shape —
        # that is what makes every asset fill its frame edge-to-edge.
        var tan_v  := tan(deg_to_rad(_camera.fov * 0.5))
        var asp    := float(_vp.size.x) / float(maxi(1, _vp.size.y))
        var dist   := maxf(max_up / tan_v, max_right / (tan_v * asp))
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
