@tool
extends EditorPlugin

## Ultimate Asset Placer — Plugin Entry Point v2.0
##
## Minecraft-style scene thumbnail capture:
## Hooks EditorInterface.get_editor_main_screen() to detect when the user
## switches scene tabs. Captures the 3D viewport BEFORE the switch happens
## by polling the current scene path every frame and saving when it changes.
## Also captures on scene_closed and when the plugin exits.

const THUMB_CACHE_DIR := "user://uap_thumbnails/scenes/"
const THUMB_CACHE_ROOT := "user://uap_thumbnails/" ## parent shared with uap_thumb_gen.gd's assets/ folder
const THUMB_SIZE      := Vector2i(256, 256)
const THUMB_MANIFEST  := THUMB_CACHE_DIR + "manifest.cfg"
const THUMB_MAX_FILES := 2000 ## soft cap; oldest orphan-checked entries get pruned past this

var _manager:       Node    = null
var _settings_dock: Control = null
var _browser_dock:  Control = null
var _placer:        Node    = null
var _physics_ctrl:  Node    = null

# We need a real Node in the tree to get _process — plugin _process is unreliable
var _ticker: Node = null

# Scene-capture state
# We track the TYPE of the scene at the moment we first see it.
# By the time _do_capture fires, get_edited_scene_root() may already show
# the NEW scene — so we must NOT query it inside _do_capture.
var _current_scene_path:    String = ""
var _current_scene_is_2d:   bool   = false
var _pending_capture_path:  String = ""
var _pending_capture_is_2d: bool   = false
var _capture_cooldown:      int    = 0

func _enter_tree() -> void:
	# Resolve our own folder from where Godot actually loaded this script,
	# instead of assuming a fixed "res://addons/ultimate_placer/" path. This
	# is the fix for a real crash: if this addon ends up nested one level
	# deeper than expected (e.g. a zip extracted with an extra wrapper
	# folder around it, or renamed for organizational reasons), every
	# hardcoded load() call below would silently fail with "File not found"
	# and the whole plugin would fail to initialize.
	var addon_root: String = get_script().resource_path.get_base_dir() + "/"

	DirAccess.make_dir_recursive_absolute(THUMB_CACHE_DIR)
	_cleanup_orphaned_thumbnails()

	_placer = load(addon_root + "ultimate_placer.gd").new()
	_placer.name = "UAP_Placer"
	_placer.set("editor_plugin", self)
	add_child(_placer)

	_manager = load(addon_root + "ultimate_panel.gd").new()
	_manager.name = "UAP_Manager"
	_manager.set("placer", _placer)
	_placer.set("panel", _manager)

	_physics_ctrl = load(addon_root + "uap_physics.gd").new()
	_physics_ctrl.name = "UAP_Physics"
	_physics_ctrl.set("editor_plugin", self)
	_physics_ctrl.set("panel", _manager)
	_manager.set("physics_ctrl", _physics_ctrl)
	add_child(_physics_ctrl)

	get_editor_interface().get_base_control().add_child(_manager)
	_manager.hide()

	_settings_dock = _manager.get_settings_ui()
	_browser_dock  = _manager.get_browser_ui()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _settings_dock)
	add_control_to_bottom_panel(_browser_dock, "Asset Browser")

	# Create a ticker node so we reliably get _process every frame
	_ticker = Node.new()
	_ticker.name = "__UAP_Ticker__"
	_ticker.set_script(_make_ticker_script())
	_ticker.set("plugin_ref", self)
	get_editor_interface().get_base_control().add_child(_ticker)

	# Connect close signal for capture-on-close
	scene_closed.connect(_on_scene_closed)

	# Record what is already open — store path AND type before any switch
	var cur_root := get_editor_interface().get_edited_scene_root()
	if cur_root != null and not cur_root.scene_file_path.is_empty():
		_current_scene_path  = cur_root.scene_file_path
		_current_scene_is_2d = (cur_root is Node2D) or (cur_root is Control)

	# On a brand-new install, Godot may still be importing the addon's own
	# icon .svg files (and other resources) when the plugin above first
	# builds its UI — verified as a real race via testing a genuinely fresh
	# project import, not assumed. Buttons still work fine without an icon
	# (text labels remain), but once import actually finishes we take the
	# opportunity to refresh tab icons in case any came up empty the first time.
	var efs := get_editor_interface().get_resource_filesystem()
	if efs != null and not efs.resources_reimported.is_connected(_on_resources_reimported):
		efs.resources_reimported.connect(_on_resources_reimported)

	print("[Ultimate Asset Placer v%s] Ready." % _get_plugin_version())

func _on_resources_reimported(_resources: PackedStringArray) -> void:
	if is_instance_valid(_manager) and _manager.has_method("refresh_icons"):
		_manager.call("refresh_icons")

func _get_plugin_version() -> String:
	## Single source of truth lives in uap_icons.gd's get_plugin_version() —
	## every place in the addon that displays a version number calls the
	## same function, so they can never drift out of sync with each other
	## the way "1.5.0" was found hardcoded in more than one place.
	return UAPIcons.get_plugin_version()

func _exit_tree() -> void:
	# Capture the currently visible scene before the plugin shuts down
	_do_capture(_current_scene_path, _current_scene_is_2d)

	if scene_closed.is_connected(_on_scene_closed):
		scene_closed.disconnect(_on_scene_closed)

	var efs := get_editor_interface().get_resource_filesystem()
	if efs != null and efs.resources_reimported.is_connected(_on_resources_reimported):
		efs.resources_reimported.disconnect(_on_resources_reimported)

	if is_instance_valid(_ticker):
		_ticker.queue_free()
	_ticker = null

	if is_instance_valid(_placer):
		_placer.call("cleanup"); _placer.queue_free()
	if is_instance_valid(_physics_ctrl):
		if _physics_ctrl.call("is_running"): _physics_ctrl.call("cancel_simulation")
		_physics_ctrl.queue_free()
	if is_instance_valid(_settings_dock):
		remove_control_from_docks(_settings_dock); _settings_dock.queue_free()
	if is_instance_valid(_browser_dock):
		remove_control_from_bottom_panel(_browser_dock); _browser_dock.queue_free()
	if is_instance_valid(_manager):
		_manager.queue_free()

	_placer = null; _settings_dock = null
	_browser_dock = null; _manager = null; _physics_ctrl = null

func _handles(object: Object) -> bool:
	return object is Node3D

func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if is_instance_valid(_placer):
		var consumed: bool = _placer.call("handle_input", camera, event)
		if consumed:
			get_viewport().set_input_as_handled()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS

# ── Called by ticker node every editor frame ──────────────────────────────────
func tick() -> void:
	# Handle pending delayed capture (from scene_closed)
	if not _pending_capture_path.is_empty():
		if _capture_cooldown > 0:
			_capture_cooldown -= 1
		else:
			_do_capture(_pending_capture_path, _pending_capture_is_2d)
			_pending_capture_path = ""; _pending_capture_is_2d = false

	# Poll for scene tab switch
	var now_path := _get_current_scene_path()
	if now_path == _current_scene_path: return

	# ── Scene switched ────────────────────────────────────────────────────────
	# At this exact frame, get_edited_scene_root() ALREADY returns the NEW root.
	# But we stored _current_scene_is_2d from the PREVIOUS frame when the old
	# scene was still active — so we use that, NOT get_edited_scene_root() here.
	if not _current_scene_path.is_empty():
		_do_capture(_current_scene_path, _current_scene_is_2d)

	# Now update to new scene — record its type immediately for next switch
	_current_scene_path = now_path
	_current_scene_is_2d = false
	if not now_path.is_empty():
		var new_root := get_editor_interface().get_edited_scene_root()
		if is_instance_valid(new_root):
			_current_scene_is_2d = (new_root is Node2D) or (new_root is Control)

# ── On scene tab closed ───────────────────────────────────────────────────────
func _on_scene_closed(filepath: String) -> void:
	if filepath.is_empty(): return
	# The scene root is still available briefly when this signal fires
	var closed_root := get_editor_interface().get_edited_scene_root()
	var is_2d := false
	if is_instance_valid(closed_root) and closed_root.scene_file_path == filepath:
		is_2d = (closed_root is Node2D) or (closed_root is Control)
	elif filepath == _current_scene_path:
		# Fall back to our tracked type
		is_2d = _current_scene_is_2d
	_pending_capture_path  = filepath
	_pending_capture_is_2d = is_2d
	_capture_cooldown      = 3
	if filepath == _current_scene_path:
		_current_scene_path  = ""; _current_scene_is_2d = false

# ── Viewport capture ──────────────────────────────────────────────────────────
func _do_capture(scene_path: String, is_2d: bool = false) -> void:
	if scene_path.is_empty(): return

	if is_2d:
		# 2D scene: use uap_thumb_gen's offline 2D SubViewport renderer.
		# The 3D viewport shows nothing useful for these.
		if is_instance_valid(_manager):
			var thumb_gen: Node = _manager.get("_thumb_gen")
			if is_instance_valid(thumb_gen) and not thumb_gen.has_disk_cache(scene_path):
				thumb_gen.enqueue_2d(scene_path)
		return

	# ── 3D scene: capture the editor's 3D viewport ────────────────────────────
	var vp: Viewport = get_editor_interface().get_editor_viewport_3d(0)
	if not is_instance_valid(vp): return

	var vp_tex := vp.get_texture()
	if vp_tex == null: return

	var img := vp_tex.get_image()
	if img == null or img.is_empty(): return
	if _image_is_blank(img): return

	# Centre-crop to square (editor viewport is 16:9)
	var w := img.get_width(); var h := img.get_height()
	if w > 0 and h > 0 and w != h:
		var sq := mini(w, h)
		var ox := (w - sq) / 2; var oy := (h - sq) / 2
		img = img.get_region(Rect2i(ox, oy, sq, sq))

	if img.is_empty(): return
	img.resize(THUMB_SIZE.x, THUMB_SIZE.y, Image.INTERPOLATE_LANCZOS)

	var cp  := _cache_path_for(scene_path)
	var err := img.save_png(cp)
	if err == OK and is_instance_valid(_manager):
		_manager.call("invalidate_thumb_cache", scene_path)

func _image_is_blank(img: Image) -> bool:
	## Returns true if the image is a solid uniform colour (nothing rendered).
	## Samples a 4x4 grid of pixels and checks variance.
	var w := img.get_width(); var h := img.get_height()
	if w < 4 or h < 4: return true
	var ref := img.get_pixel(w / 2, h / 2)
	for xi in 4:
		for yi in 4:
			var c := img.get_pixel(xi * (w-1) / 3, yi * (h-1) / 3)
			if absf(c.r-ref.r)+absf(c.g-ref.g)+absf(c.b-ref.b) > 0.08:
				return false
	return true

func _get_current_scene_path() -> String:
	var root := get_editor_interface().get_edited_scene_root()
	if root == null: return ""
	return root.scene_file_path

func _cache_path_for(scene_path: String) -> String:
	var hash := scene_path.md5_text()
	_remember_manifest_entry(hash, scene_path)
	return THUMB_CACHE_DIR + hash + ".png"

func _remember_manifest_entry(hash: String, scene_path: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(THUMB_MANIFEST) # ok to fail on first run — starts empty
	cfg.set_value("scenes", hash, scene_path)
	cfg.save(THUMB_MANIFEST)

func _migrate_pre_2_0_flat_cache() -> void:
	## Pre-2.0 versions stored scene screenshots AND asset-preview thumbnails
	## side by side in the same flat "user://uap_thumbnails/" folder, hashed
	## the same way — a real cache-collision bug (see uap_thumb_gen.gd header
	## comment). 2.0 splits them into scenes/ and assets/ subfolders. Any
	## loose .png sitting directly in the parent folder is guaranteed to be
	## from that old scheme and guaranteed stale under the new one, so it's
	## safe to remove once, on first run after upgrading.
	var parent_dir := THUMB_CACHE_ROOT # ".../uap_thumbnails/" — shared parent, NOT the scenes/ subfolder
	var da := DirAccess.open(parent_dir)
	if da == null: return
	da.list_dir_begin()
	var f := da.get_next()
	var removed := 0
	while f != "":
		if not da.current_is_dir() and f.ends_with(".png"):
			da.remove(f)
			removed += 1
		f = da.get_next()
	da.list_dir_end()
	if removed > 0:
		print("[Ultimate Asset Placer] Migrated cache layout — removed %d thumbnail(s) from the old shared cache folder." % removed)

func _cleanup_orphaned_thumbnails() -> void:
	## Thumbnails are cached by an md5 of the scene path. If a scene gets
	## renamed or deleted, its old thumbnail used to linger on disk forever.
	## We keep a small manifest (hash -> original path) and, once per editor
	## session, drop any cached PNG whose source scene no longer exists.
	_migrate_pre_2_0_flat_cache()

	var cfg := ConfigFile.new()
	if cfg.load(THUMB_MANIFEST) != OK:
		return # no manifest yet (fresh install, or pre-2.0 cache) — nothing to reconcile

	var da := DirAccess.open(THUMB_CACHE_DIR)
	var removed := 0
	for hash in cfg.get_section_keys("scenes"):
		var original_path: String = cfg.get_value("scenes", hash, "")
		if original_path.is_empty() or FileAccess.file_exists(original_path):
			continue
		var png_path := THUMB_CACHE_DIR + hash + ".png"
		if da != null and FileAccess.file_exists(png_path):
			da.remove(png_path)
			removed += 1
		cfg.erase_section_key("scenes", hash)

	# Soft cap: if we somehow still have more cached PNGs than THUMB_MAX_FILES
	# (e.g. manifest lost/rebuilt), trim the oldest-modified files first.
	if da != null:
		var files: Array[String] = []
		da.list_dir_begin()
		var f := da.get_next()
		while f != "":
			if f.ends_with(".png"): files.append(f)
			f = da.get_next()
		da.list_dir_end()
		if files.size() > THUMB_MAX_FILES:
			files.sort_custom(func(a, b):
				return FileAccess.get_modified_time(THUMB_CACHE_DIR + a) < FileAccess.get_modified_time(THUMB_CACHE_DIR + b))
			for i in (files.size() - THUMB_MAX_FILES):
				da.remove(THUMB_CACHE_DIR + files[i])
				removed += 1

	if removed > 0:
		cfg.save(THUMB_MANIFEST)
		print("[Ultimate Asset Placer] Cleaned up %d stale/excess cached thumbnail(s)." % removed)

# ── Inline ticker script ───────────────────────────────────────────────────────
func _make_ticker_script() -> GDScript:
	## Returns a tiny GDScript that calls plugin_ref.tick() every frame.
	## We create it in-code so we don't need a separate file.
	var src := """
@tool
extends Node
var plugin_ref = null
func _process(_dt: float) -> void:
	if plugin_ref != null and is_instance_valid(plugin_ref):
		plugin_ref.tick()
"""
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s
