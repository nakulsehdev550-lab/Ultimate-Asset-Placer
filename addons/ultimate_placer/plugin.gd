@tool
extends EditorPlugin

## Ultimate Asset Placer — plugin entry point.
##
## Owns the four long-lived pieces of the addon (placer, panel, physics
## controller, thumbnail generator), registers the docks, and routes 3D
## viewport input to the placer. Asset thumbnails are produced exclusively by
## uap_thumb_gen.gd's offline studio renderer; this file holds no capture
## logic of its own.

const THUMB_CACHE_ROOT := "user://uap_thumbnails/"
## Layouts written by older plugin versions, removed once per session on
## startup. The flat parent folder is pre-2.0 (scene shots and asset thumbs
## shared one folder and collided by hash); scenes/ held live-viewport
## captures that no code has read since the studio renderer took over.
const LEGACY_CACHE_DIRS: Array[String] = [
	"user://uap_thumbnails/scenes/",
]

var _manager:       Node    = null
var _settings_dock: Control = null
var _browser_dock:  Control = null
var _placer:        Node    = null
var _physics_ctrl:  Node    = null

func _enter_tree() -> void:
	var addon_root: String = get_script().resource_path.get_base_dir() + "/"

	# The addon self-locates its folder, which keeps it working from any path —
	# but that also means a second copy left in the project boots a complete
	# second panel and second thumbnail studio alongside the real one. The
	# first copy loaded wins; this copy bows out with an actionable message.
	var _base_ctrl := get_editor_interface().get_base_control()
	for existing in _base_ctrl.find_children("UAP_Manager*", "", true, false):
		if is_instance_valid(existing) and existing.is_inside_tree() \
				and not existing.is_queued_for_deletion():
			print("[Ultimate Asset Placer] DUPLICATE COPY DETECTED — a copy of this plugin is already active in this editor session. Skipping the copy loaded from %s" % addon_root)
			print("[Ultimate Asset Placer] FIX: Project Settings → Plugins → disable/remove the duplicate Ultimate Asset Placer entry (or delete the leftover addon folder), then restart the editor.")
			return

	_purge_legacy_caches()

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

	# On a brand-new install the editor may still be importing the addon's own
	# icon .svg files when the UI above is first built. Buttons work fine
	# without an icon (text labels remain); once the import pass finishes we
	# refresh so the icons catch up without requiring a project reload.
	var efs := get_editor_interface().get_resource_filesystem()
	if efs != null and not efs.resources_reimported.is_connected(_on_resources_reimported):
		efs.resources_reimported.connect(_on_resources_reimported)

	print("[Ultimate Asset Placer v%s] Ready." % _get_plugin_version())

func _on_resources_reimported(_resources: PackedStringArray) -> void:
	if is_instance_valid(_manager) and _manager.has_method("refresh_icons"):
		_manager.call("refresh_icons")

func _get_plugin_version() -> String:
	## Single source of truth lives in uap_icons.gd's get_plugin_version(),
	## so every displayed version number reads the same plugin.cfg value.
	return UAPIcons.get_plugin_version()

func _exit_tree() -> void:
	var efs := get_editor_interface().get_resource_filesystem()
	if efs != null and efs.resources_reimported.is_connected(_on_resources_reimported):
		efs.resources_reimported.disconnect(_on_resources_reimported)

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

func _purge_legacy_caches() -> void:
	## Best-effort removal of cache layouts written by older versions.
	## A locked or missing file must never break startup.
	for f in _list_pngs(THUMB_CACHE_ROOT):
		DirAccess.remove_absolute(THUMB_CACHE_ROOT + f)
	for d in LEGACY_CACHE_DIRS:
		var da := DirAccess.open(d)
		if da != null:
			da.list_dir_begin()
			var f := da.get_next()
			while f != "":
				if not da.current_is_dir():
					DirAccess.remove_absolute(d + f)
				f = da.get_next()
			da.list_dir_end()
		DirAccess.remove_absolute(d)

func _list_pngs(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var da := DirAccess.open(dir_path)
	if da == null: return out
	da.list_dir_begin()
	var f := da.get_next()
	while f != "":
		if not da.current_is_dir() and f.ends_with(".png"):
			out.append(f)
		f = da.get_next()
	da.list_dir_end()
	return out
