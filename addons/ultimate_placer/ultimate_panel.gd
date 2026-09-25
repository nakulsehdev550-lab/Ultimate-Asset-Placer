@tool
extends Control



const CONFIG_PATH := "user://ultimate_asset_placer.cfg"

const ALL_FORMATS   := ["glb","gltf","fbx","obj","dae","blend","tscn","scn","res","mesh"]
const FORMAT_LABELS := ["GLB","GLTF","FBX","OBJ","DAE","BLEND","TSCN","SCN","RES","MESH"]

const C_BG        := Color(0.10, 0.11, 0.14)
const C_SURFACE   := Color(0.16, 0.17, 0.22)
const C_BORDER    := Color(0.22, 0.24, 0.32)
const C_ACCENT    := Color(0.28, 0.62, 1.00)
const C_ACCENT2   := Color(0.45, 0.75, 1.00)
const C_OK        := Color(0.40, 0.85, 0.50)
const C_WARN      := Color(1.00, 0.72, 0.18)
const C_ERROR     := Color(0.92, 0.35, 0.35)
const C_DIM       := Color(0.50, 0.52, 0.60)
const C_HEAD      := Color(0.88, 0.93, 1.00)
const C_TEXT      := Color(0.80, 0.83, 0.90)
const C_PLACING   := Color(1.00, 0.84, 0.22)
# 2.4: resting card face = INSET dark — the same value as S_INSET_BG used by
# the group chips/rows, so cards read as carved into the panel instead of
# blending into it (previous lighter fill was "too similar to the background").
const C_CARD_BG   := Color(0.078, 0.085, 0.115)
const C_CARD_BD   := Color(0.22, 0.24, 0.32)
const C_SEL_BD    := Color(0.28, 0.62, 1.00)
const C_MULTI     := Color(1.00, 0.72, 0.18)

const MODE_LABELS := ["Free","Grid","Surface","Vertex","Spline"]
const MODE_TIPS   := [
        "Free: place anywhere on the Y plane, no snapping",
        "Grid: snap to grid on XZ, grid visualised in viewport",
        "Surface: place on any physics surface",
        "Vertex: moves freely, snaps when close to a mesh corner",
        "Spline: click to add points and repeat assets along a curve",
]
const MODE_COLORS := [
        Color(0.52,0.54,0.60),Color(0.28,0.62,1.00),Color(0.40,0.85,0.50),
        Color(1.00,0.72,0.18),Color(0.40,1.00,0.72),
]
# Indices visible as buttons in mode bar (Spline=4 removed — it has its own tab)
const MODE_BUTTON_INDICES := [0, 1, 2, 3]
const SCROLL_LABELS := ["Off","Scale","Rot Y","Rot X","Rot Z","Height"]
const KEY_NAMES: Dictionary = {
        "None":KEY_NONE,"Q":KEY_Q,"W":KEY_W,"E":KEY_E,"R":KEY_R,"T":KEY_T,"Y":KEY_Y,
        "U":KEY_U,"I":KEY_I,"O":KEY_O,"P":KEY_P,"F":KEY_F,"G":KEY_G,"H":KEY_H,
        "J":KEY_J,"K":KEY_K,"Z":KEY_Z,"X":KEY_X,"C":KEY_C,"V":KEY_V,"B":KEY_B,
        "N":KEY_N,"M":KEY_M,"[":KEY_BRACKETLEFT,"]":KEY_BRACKETRIGHT,
        "PageUp":KEY_PAGEUP,"PageDown":KEY_PAGEDOWN,"Home":KEY_HOME,"End":KEY_END,
        "Insert":KEY_INSERT,"Delete":KEY_DELETE,
}
const SHORTCUT_LABELS: Dictionary = {
        "rotate_y":"Rotate Y  (Shift=CCW)","rotate_x":"Pitch X   (Shift=rev)",
        "rotate_z":"Roll Z    (Shift=rev)","scale_up":"Scale Up","scale_down":"Scale Down",
        "height_up":"Height Up","height_down":"Height Down","layer_up":"Layer Up",
        "layer_down":"Layer Down","flip_x":"Flip X","flip_z":"Flip Z","reset_rot":"Reset Transform",
}

const BUILD_BATCH      := 15
const THUMB_INTERVAL   := 0.1
const MAX_PER_TICK     := 2
const MAX_CACHE_LOADS  := 8   # disk-PNG loads per visibility tick (spreads decode cost)
const THUMB_CACHE_MAX  := 500
const SCAN_DIRS_FRAME  := 6
const SKIP_DIRS := [".godot", ".import", ".git", ".vs"]
const ALL_PREVIEW_EXTS := ["glb","gltf","fbx","obj","dae","res","mesh","tscn","scn"]


# ─── SliderSpin: horizontal slider + editable number field ────────────────────
class SliderSpin extends HBoxContainer:
        signal value_changed(v: float)
        var value: float = 0.0
        var min_value: float = 0.0
        var max_value: float = 1.0
        var step: float = 0.01
        var _slider: HSlider = null
        var _edit: LineEdit = null
        var _updating: bool = false

        func _ready() -> void:
                var es := EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0
                add_theme_constant_override("separation", 4)
                size_flags_horizontal = SIZE_EXPAND_FILL
                _slider = HSlider.new()
                _slider.min_value = min_value; _slider.max_value = max_value
                _slider.step = step; _slider.value = value
                _slider.size_flags_horizontal = SIZE_EXPAND_FILL
                _slider.size_flags_vertical = SIZE_SHRINK_CENTER
                _slider.custom_minimum_size = Vector2(50, 0)
                _slider.value_changed.connect(_on_slider_changed)
                add_child(_slider)
                _edit = LineEdit.new()
                _edit.custom_minimum_size = Vector2(62 * es, 0)
                _edit.size_flags_horizontal = SIZE_SHRINK_END
                _edit.size_flags_vertical = SIZE_SHRINK_CENTER
                _edit.add_theme_constant_override("minimum_character_width", 1)
                _edit.text = _fmt(value)
                _edit.text_submitted.connect(_on_edit_submitted)
                _edit.focus_exited.connect(_on_edit_focus_exit)
                add_child(_edit)

        func _on_slider_changed(v: float) -> void:
                if _updating: return
                _updating = true; value = v
                if is_instance_valid(_edit): _edit.text = _fmt(v)
                _updating = false; value_changed.emit(v)

        func _on_edit_submitted(text: String) -> void:
                _apply_text(text)
                if is_instance_valid(_edit): _edit.release_focus()

        func _on_edit_focus_exit() -> void:
                _apply_text(_edit.text if is_instance_valid(_edit) else "0")

        func _apply_text(text: String) -> void:
                if _updating: return
                _updating = true
                var v := float(text)
                # Allow any typed value — do NOT clamp to min/max.
                # The slider thumb is clamped visually; the actual value can exceed limits.
                value = v
                if is_instance_valid(_slider): _slider.value = clampf(v, min_value, max_value)
                if is_instance_valid(_edit): _edit.text = _fmt(v)
                _updating = false; value_changed.emit(v)

        func _fmt(v: float) -> String:
                if step >= 1.0: return "%d" % int(v)
                elif step >= 0.1: return "%.1f" % v
                elif step >= 0.01: return "%.2f" % v
                else: return "%.4f" % v

        func set_value_no_signal(v: float) -> void:
                _updating = true
                value = v  # No clamping — allow any value
                if is_instance_valid(_slider): _slider.value = clampf(v, min_value, max_value)
                if is_instance_valid(_edit): _edit.text = _fmt(v)
                _updating = false

# ─── CompactSpin (used by spline sub-UI) ─────────────────────────────────────
class CompactSpin extends HBoxContainer:
        signal value_changed(v: float)
        var value:float=0.0; var min_value:float=-1e9; var max_value:float=1e9; var step:float=1.0
        var _edit:LineEdit=null
        func _get_minimum_size()->Vector2: return Vector2.ZERO
        func _ready()->void:
                var es := EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0
                add_theme_constant_override("separation",0)
                size_flags_horizontal=SIZE_EXPAND_FILL; size_flags_vertical=SIZE_SHRINK_CENTER
                custom_minimum_size=Vector2.ZERO
                _edit=LineEdit.new(); _edit.size_flags_horizontal=SIZE_EXPAND_FILL
                _edit.size_flags_vertical=SIZE_SHRINK_CENTER; _edit.custom_minimum_size=Vector2.ZERO
                _edit.add_theme_constant_override("minimum_character_width",1)
                _edit.text=_fmt(value)
                _edit.text_submitted.connect(_on_submitted); _edit.focus_exited.connect(_on_focus_exit)
                add_child(_edit)
                var col:=VBoxContainer.new(); col.size_flags_horizontal=SIZE_SHRINK_END
                col.size_flags_vertical=SIZE_SHRINK_CENTER; col.custom_minimum_size=Vector2(int(16*es),0)
                col.add_theme_constant_override("separation",0); add_child(col)
                for arrow in [["+",_step_up],["-",_step_down]]:
                        var btn:=Button.new(); btn.text=arrow[0]; btn.flat=true
                        btn.size_flags_vertical=SIZE_SHRINK_CENTER; btn.custom_minimum_size=Vector2(int(16*es),int(10*es))
                        btn.pressed.connect(arrow[1] as Callable); col.add_child(btn)
        func _gui_input(event:InputEvent)->void:
                if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
                        match (event as InputEventMouseButton).button_index:
                                MOUSE_BUTTON_WHEEL_UP:  _step_up(); accept_event()
                                MOUSE_BUTTON_WHEEL_DOWN:_step_down();accept_event()
        func _fmt(v:float)->String:
                var s:="%.4f"%v
                if "." in s: s=s.rstrip("0").rstrip(".")
                return s
        func _step_up()  ->void: _set_emit(snapped(value+step,step))
        func _step_down()->void: _set_emit(snapped(value-step,step))
        func _on_submitted(text:String)->void:
                # Allow any typed value — no clamping to min/max
                _set_emit(float(text))
                if is_instance_valid(_edit): _edit.release_focus()
        func _on_focus_exit()->void:
                _set_emit(float(_edit.text if is_instance_valid(_edit) else "0"))
        func _set_emit(v:float)->void:
                value=v; if is_instance_valid(_edit):_edit.text=_fmt(v); value_changed.emit(v)
        func set_value_no_signal(v:float)->void:
                value=v  # No clamping
                if is_instance_valid(_edit): _edit.text=_fmt(value)


# ─── State Variables ──────────────────────────────────────────────────────────
var placer:Node=null
var physics_ctrl:Node=null
var _es:float=1.0
var place_mode:int=1; var scroll_mode:int=0
var grid_enabled:bool=true; var grid_size:float=1.0
var grid_height:float=0.0; var height_offset:float=0.0
var height_snap:bool=false; var show_grid:bool=true
# 2.5 rev 8 — infinite-grid follow: the floor's half-extent is configurable
# ("View Dist", used to be hardwired at 40 m) and every plane can re-center
# on the viewport camera as you navigate (lines stay locked onto world grid
# multiples, so the grid never slides — it just extends wherever you go).
var grid_view_dist:float=40.0
var grid_follow:bool=true
# 2.5 rev 7 — axis wall grids: vertical snap planes toggled individually.
#   X grid = XY plane at z = x_grid_pos (snaps X + Y, orange lines)
#   Z grid = ZY plane at x = z_grid_pos (snaps Z + Y, green lines)
# Size (View Dist) = half-extent in metres, pos = offset along the
# perpendicular axis, cy = vertical centre of the wall (follow-off only).
var x_grid_enabled:bool=false; var x_grid_size:float=10.0
var x_grid_pos:float=0.0; var x_grid_cy:float=0.0
var z_grid_enabled:bool=false; var z_grid_size:float=10.0
var z_grid_pos:float=0.0; var z_grid_cy:float=0.0
var x_grid_follow:bool=true; var z_grid_follow:bool=true
var align_to_normal:bool=false; var vertex_snap_mesh:bool=false
var vertex_snap_strength:float=42.0
var rotation_snap_mode:int=1; var custom_snap_deg:float=15.0
var random_rot:bool=false; var rrot_min:float=0.0; var rrot_max:float=360.0
var random_tilt:bool=false; var rtilt_min:float=-10.0; var rtilt_max:float=10.0
var uniform_scale:bool=true; var place_scale_all:float=1.0
var place_scale_x:float=1.0; var place_scale_y:float=1.0; var place_scale_z:float=1.0
var random_scale:bool=false; var rscale_min:float=0.8; var rscale_max:float=1.2
var paint_mode:bool=false; var paint_spacing:float=0.5
var paint_scatter:bool=false; var scatter_radius:float=0.5
var random_group_place:bool=false; var unpack_scenes:bool=false
var paint_as_brush:bool=false; var brush_radius:float=2.0
var brush_density:float=0.5; var brush_falloff:float=0.5
var brush_texture_path:String=""
var _active_spline_tool:Node=null
var multimesh_mode:bool=false; var mm_collision_enabled:bool=false
var parent_path:String=""; var parent_node:Node=null
var collision_enabled:bool=false; var collision_body_type:int=0
var collision_shape_type:int=0; var collision_auto_unpack:bool=true
var material_override_enabled:bool=false; var material_override_path:String=""
var material_override_mode:int=0
var phys_lift_height:float=3.0; var phys_lift_scatter:bool=false
var phys_lift_scatter_radius:float=0.5; var phys_lift_random_rot:bool=false
var phys_gravity:float=9.8; var phys_bounciness:float=0.15; var phys_friction:float=0.55
var phys_align_to_ground:bool=true; var phys_random_tumble:bool=false
var phys_auto_shape:int=0; var phys_max_fall_time:float=15.0; var phys_auto_stop:bool=true
var phys_auto_add_collision:bool=true
var import_formats:Array=ALL_FORMATS.duplicate()
var current_folder:String="res://"; var selected_path:String=""
var shortcuts:Dictionary={
        "rotate_y":KEY_R,"rotate_x":KEY_E,"rotate_z":KEY_Q,
        "scale_up":KEY_BRACKETRIGHT,"scale_down":KEY_BRACKETLEFT,
        "height_up":KEY_PAGEUP,"height_down":KEY_PAGEDOWN,
        "layer_up":KEY_HOME,"layer_down":KEY_END,
        "flip_x":KEY_G,"flip_z":KEY_B,"reset_rot":KEY_T,
}
var _preview_size:int=88; var _all_paths:Array=[]; var _groups:Array=[]
var _grid_rm:int=0   # 0 since rev 4: the favorite star sits FULLY INSIDE the
                     # card (pinned to the thumbnail's top-right corner), so
                     # nothing overhangs the grid anymore. Kept in the column
                     # math so a future reservation needs no re-derivation.
var _favorite_paths:Array=[]  ## Favorites' actual storage — a separate list, NOT a _groups entry
var _active_group:int=-1; var _is_placing:bool=false
var items_per_page:int=1000; var current_page:int=0
var _visible_paths_filtered:Array=[]
var _thumb_cache:Dictionary={}; var _thumb_lru:Array=[]
var _thumb_pending:Dictionary={}; var _thumb_heavy_count:int=0
var _thumb_perm_failed:Dictionary={}; var _card_ir_map:Dictionary={}
var _card_fav_btn_map:Dictionary={}
var _ir_path_map:Dictionary={}; var _thumb_retry_queue:Array=[]
var _thumb_retry_timer:float=0.0; var _thumb_check_timer:float=0.0
var _scan_dir_queue:Array=[]; var _is_scanning:bool=false
var _build_queue:Array=[]; var _visible_paths_ordered:Array=[]
var _multi_selected:Array=[]; var _last_clicked_path:String=""
var _selected_path_ui:String=""; var _card_map:Dictionary={}
var _browser_generation:int=0  # Increments on each rebuild; prevents stale thumbnail callbacks
var _hidden_paths:Array=[]  ## Assets removed from the browser list via right-click. Persisted; reversible.

# ─── UI Overhaul 2.1: Left tab rail + Docs window + 3D tactile styles ────────
var _tab_rail:VBoxContainer=null          # Blender-style vertical icon bar
var _rail_buttons:Array=[]                # index-aligned with _settings_tabs feature tabs
var _rail_docs_btn:Button=null            # opens the docs popup window instead of switching tabs
var _docs_window:Window=null              # centered documentation window
var _docs_rtl:RichTextLabel=null          # chapter content renderer
var _docs_chapter_btns:Array=[]
var _docs_cur_chapter:int=0
var _docs_was_open:bool=false             # rail highlight state helper

# Tab rail icon names, index-aligned with the feature tabs built below
# (Place, Transform, Paint, Spline, Material, Groups, Keys, Collision, Physics).
const RAIL_ICON_NAMES := ["tab_place","tab_transform","tab_paint","tab_spline","tab_material","tab_collision","tab_physics","tab_groups","tab_keys"]

# Shared style constants for the 3D tactile language:
#  • raised  = active/selected  (full color, darker bottom edge, subtle drop shadow)
#  • inset   = chips/groups/sections (carved INTO the panel: darker fill, no
#              outline border anywhere, single darker line along the BOTTOM edge)
#  • idle    = resting buttons  (clean flat dark, no white highlight)
# Text on raised faces is plain near-white — NO dark font outline.
const S_IDLE_BG      := Color(0.165,0.175,0.225)
const S_IDLE_HOVER   := Color(0.205,0.215,0.275)
const S_IDLE_PRESSED := Color(0.135,0.145,0.19)
const S_INSET_BG     := Color(0.078,0.085,0.115)
const S_INSET_HOVER  := Color(0.095,0.103,0.138)
const S_INSET_SHADOW := Color(0.028,0.031,0.045)
const S_INSET_ACTIVE_BG    := Color(0.085,0.190,0.310)
const S_INSET_ACTIVE_EDGE  := Color(0.030,0.068,0.115)
const S_SECTION_BG   := Color(0.098,0.105,0.138)
const S_SECTION_LINE := Color(0.024,0.027,0.038)
# 2.3 card states: the thumbnail WELL is tinted to match the card's active
# state, so the blue/amber 3D selection reads around the thumbnail too
# instead of only on the name row at the bottom.
const C_WELL_BG      := Color(0.055,0.060,0.082)   # resting: deepest inset layer (darker than the card face)
const C_WELL_SEL     := Color(0.125,0.235,0.360)   # single-select: blue-tinted
const C_WELL_MULTI   := Color(0.330,0.245,0.090)   # multi-select: amber-tinted
# 2.5 rev 3: ONLY standalone panel-level action buttons are raised (Start
# Physics row, Create New Spline, Exit Spline Mode, Reset All to Defaults and
# the Groups-tab action cluster). Buttons INSIDE a group section keep the
# quiet idle look. One face color per meaning — all deliberately dark,
# on-theme, and clearly distinct from the panel bg.
const C_BTN_ACTION  := Color(0.16,0.34,0.55)   # steel blue — standalone panel actions
const C_BTN_DANGER  := Color(0.45,0.16,0.16)   # dark red     — destructive standalone actions
const C_BTN_STOP    := Color(0.48,0.34,0.08)   # dark amber   — stop/hold actions
# Tab → docs chapter (order = TabContainer page order):
# Place→"Place Tab", Transform→"Transform Tab", Paint→"Paint Tab",
# Spline→"Spline Tab", Material→"Material & Collision",
# Groups→"Groups & Favorites", Keys→"Keys & Shortcuts",
# Collision→"Material & Collision", Physics→"Physics Tab".
const TAB_DOCS_CHAPTER := [4,5,6,7,8,8,9,10,11]

# Page opened when the user clicks the animated rating stars pinned to the
# right corner of the header title row. Swap this one constant to point the
# stars at a different ratings page (itch.io rate page for the plugin).
const RATING_URL := "https://choco-ted.itch.io/ultimate-asset-placer-godot-45-gd-script/rate?source=game"

var settings_ui:VBoxContainer=null; var browser_ui:VBoxContainer=null
var _search_panel:VBoxContainer=null; var _folder_edit:LineEdit=null
var _search_edit:LineEdit=null; var _asset_grid:GridContainer=null
var _asset_scroll:ScrollContainer=null; var _status_lbl:Label=null
var _stop_btn:Button=null; var _group_bar:FlowContainer=null
var _preview_lbl:Label=null; var _settings_tabs:TabContainer=null
var _mode_buttons:Array=[]; var _scroll_buttons:Array=[]
var _group_list_vbox:VBoxContainer=null; var _group_drop:OptionButton=null
var _group_chip_btns:Array=[]   # filter-bar chips, in visual order
var _group_chip_idxs:Array=[]    # matching filter indices: -1 All, -2 Favorites, 0..n groups
var _multisel_bar:HBoxContainer=null; var _multisel_lbl:Label=null
var _multisel_group_opt:OptionButton=null
# 2.2: tab-name header + instant rail hover-name
var _tab_header_lbl:Label=null
var _tab_help_btn:Button=null
# 2.3: global dressing-pass counters (reported once at startup).
var _theme_n_b:int=0; var _theme_n_o:int=0; var _theme_n_l:int=0
var _rail_tip_layer:Control=null; var _rail_tip_panel:PanelContainer=null; var _rail_tip_lbl:Label=null
# 2.2: advanced header collapse — when collapsed, the group chip strip moves
# INTO the title bar so every group stays one click away.
var _header_title_row:HBoxContainer=null; var _header_title_lbl:Label=null
# Master header collapse (title row / search rows / status bar as one block).
# 2.2: the "Search & Filters" section toggle was removed — only the master
# collapse remains, and it keeps the group chips visible on the bar.
var _header_collapsed:bool=false
var _header_master_btn:Button=null; var _header_ver_lbl:Label=null
# 2.5 rev 6: header layout — version label sits NEXT to the title text, and a
# flexible spacer pushes the rating stars + collapse chevron to the RIGHT
# CORNER. The stars are pinned there permanently (they are NOT part of the
# group chip strip, so they never wrap or move with the group buttons).
var _header_spacer:Control=null; var _rating_stars:Control=null
# 2.5 rev 7 — retractable rating stars. The arrow button tucks the stars away
# or reveals them again; the hidden state is SESSION-ONLY on purpose: opening
# (or expanding) the asset browser always shows the stars by default.
var _header_stars_btn:Button=null
var _stars_hidden:bool=false
var _status_bar_panel:PanelContainer=null
var _rot_x_spin:SliderSpin=null; var _rot_y_spin:SliderSpin=null; var _rot_z_spin:SliderSpin=null
var _grid_size_spin:SliderSpin=null; var _grid_h_spin:SliderSpin=null
var _height_spin:SliderSpin=null; var _scale_spin:SliderSpin=null
var _scale_x_spin:SliderSpin=null; var _scale_y_spin:SliderSpin=null; var _scale_z_spin:SliderSpin=null
var _custom_row:HBoxContainer=null; var _custom_spin:SliderSpin=null
var _xyz_box:VBoxContainer=null; var _rot_opt:OptionButton=null
var _parent_edit:LineEdit=null; var _col_warn_lbl:Label=null
var _mat_path_lbl:Label=null; var _mat_mode_opt:OptionButton=null
var _uni_scale_row:HBoxContainer=null; var _zoo_spacing_spin:SliderSpin=null
var _format_btns:Array=[]; var _vss_spin:SliderSpin=null; var _page_lbl:Label=null

var _zoo_show_labels:bool=true; var _zoo_paths_to_measure:Array=[]
var _zoo_source:int=0; var _zoo_source_opt:OptionButton=null # 0=All, 1=Group filter, 2=Selected
var _zoo_items:Array=[]; var _zoo_node:Node3D=null
var _zoo_x_off:Array=[]; var _zoo_z_off:Array=[]
var _zoo_cols:int=1; var _zoo_index:int=0; var _zoo_is_building:bool=false
const ZOO_BATCH:=3; const ZOO_MEASURE_BATCH:=2
var _capturing_action:String=""; var _key_capture_btns:Dictionary={}

# ─── Offline Thumbnail Generator (for .tscn/.scn) ────────────────────────────
var _thumb_gen:Node=null                 # uap_thumb_gen.gd SubViewport instance
var _thumb_gen_ir_map:Dictionary={}      # path -> ir instance_id (for callback)

# ─── Spline Mode Management ───────────────────────────────────────────────────
var _prev_place_mode:int=1               # mode to restore when exiting spline
var _spline_mode_active:bool=false
var _spline_mode_lbl:Label=null          # status label inside Spline tab
var _spline_status_icon:TextureRect=null # status dot icon inside Spline tab

# ─── Physics Placer UI ─────────────────────────────────────────────────────────
var _phys_status_lbl:Label=null
var _phys_status_icon:TextureRect=null
var _phys_start_btn:Button=null
var _phys_stop_btn:Button=null
var _phys_cancel_btn:Button=null
var _phys_shape_warn_lbl:Label=null

func get_settings_ui() -> Control: return settings_ui
func get_browser_ui() -> Control: return browser_ui

func refresh_icons() -> void:
        ## Called by plugin.gd once Godot confirms a resource-import pass has
        ## finished. On a brand-new install, the very first UI build can happen
        ## before the addon's own icon .svg files have finished importing —
        ## buttons still work fine (text labels remain either way), but this lets
        ## the icons catch up without requiring the user to reload the project.
        UAPIcons.clear_cache()
        if is_instance_valid(_settings_tabs):
                var icon_by_tab_name := {
                        "Place":"tab_place", "Transform":"tab_transform", "Paint":"tab_paint",
                        "Spline":"tab_spline", "Material":"tab_material", "Groups":"tab_groups",
                        "Keys":"tab_keys", "Collision":"tab_collision", "Physics":"tab_physics",
                }
                for i in _settings_tabs.get_tab_count():
                        var tab_name := _settings_tabs.get_tab_title(i)
                        if icon_by_tab_name.has(tab_name):
                                var tex := UAPIcons.get_icon(icon_by_tab_name[tab_name])
                                if tex != null: _settings_tabs.set_tab_icon(i, tex)
        # Re-dress the left rail with freshly-imported icons (and tooltips).
        if is_instance_valid(_tab_rail) and is_instance_valid(_settings_tabs):
                for i in _rail_buttons.size():
                        var rb := _rail_buttons[i] as Button
                        if not is_instance_valid(rb) or i >= RAIL_ICON_NAMES.size(): continue
                        if i < _settings_tabs.get_tab_count():
                                rb.tooltip_text = _settings_tabs.get_tab_title(i)
                        var rtex := UAPIcons.get_icon_sized(RAIL_ICON_NAMES[i], maxi(12,int(20*_es)))
                        if rtex != null: rb.icon = rtex
                _refresh_tab_rail()
        if is_instance_valid(_rail_docs_btn):
                var dtex := UAPIcons.get_icon_sized("tab_docs", maxi(12,int(20*_es)))
                if dtex != null: _rail_docs_btn.icon = dtex
        # Card favorite stars suffer from the same first-import race as the tab
        # icons (they are built once with the grid), so re-apply them here too.
        # 2.5: same EXACT size formula as _add_card (the old 18px refresh size
        # drifted from the 16px build size) — with ignore_texture_size any
        # drift would only scale, never shift the layout, but staying equal
        # keeps the star crisp at 1:1 pixels.
        var fav_size := maxi(12,int(16*_es))
        for p in _card_fav_btn_map.keys():
                var fb := _card_fav_btn_map[p] as TextureButton
                if not is_instance_valid(fb): continue
                var ftex := UAPIcons.get_icon_outlined("feature_favorite", fav_size)
                if ftex != null: fb.texture_normal = ftex
                if _card_map.has(p):
                        var fc := _card_map[p] as PanelContainer
                        if is_instance_valid(fc): _update_card_favorite_star(fc, p)
        # Header chevron (master collapse) — refresh its icon/tooltip state.
        _apply_header_collapsed()
        _update_spline_mode_label()


# ─── Lifecycle ────────────────────────────────────────────────────────────────
func _addon_root()->String:
        ## Resolves this addon's real install folder from where Godot actually
        ## loaded THIS script, instead of assuming a fixed folder name — the
        ## fix for a real crash when the addon ends up nested one level deeper
        ## than expected (e.g. a zip extracted with an extra wrapper folder).
        return get_script().resource_path.get_base_dir()+"/"

func _ready()->void:
        if Engine.is_editor_hint(): _es=EditorInterface.get_editor_scale()
        _load_config(); _build_ui()
        await get_tree().process_frame; await get_tree().process_frame
        # ── Offline Scene Thumbnail Generator ─────────────────────────────────────
        if Engine.is_editor_hint():
                var tg_script = load(_addon_root()+"uap_thumb_gen.gd")
                if tg_script != null:
                        _thumb_gen = tg_script.new()
                        _thumb_gen.name = "__UAPThumbGen__"
                        add_child(_thumb_gen)
                        _thumb_gen.thumbnail_ready.connect(_on_thumb_gen_ready)
                        var m0:=_card_thumb_metrics(_preview_size)
                        _thumb_gen.call("set_preview_metrics",m0.x,m0.y)
        _scan_folder()

func _process(delta:float)->void:
        if is_instance_valid(physics_ctrl) and bool(physics_ctrl.call("is_running")): _update_phys_ui()
        if _is_scanning: _tick_scan()
        if not _zoo_paths_to_measure.is_empty(): _tick_zoo_measure()
        if _zoo_is_building: _tick_zoo_build()
        var was_building := not _build_queue.is_empty()
        if was_building: _tick_build_queue()
        if was_building and _build_queue.is_empty(): _thumb_check_timer = 0.0
        if not _thumb_retry_queue.is_empty():
                _thumb_retry_timer -= delta
                if _thumb_retry_timer <= 0.0:
                        _thumb_retry_timer = 0.5
                        _process_thumb_retries()
        _thumb_check_timer -= delta
        if _thumb_check_timer <= 0.0:
                _thumb_check_timer = THUMB_INTERVAL
                _check_visible_thumbnails()

func _tick_build_queue()->void:
        var count := 0
        while not _build_queue.is_empty() and count < BUILD_BATCH:
                _add_card(_build_queue.pop_front() as String); count += 1
        if count > 0: _update_columns()
        if not _build_queue.is_empty():
                set_status("Building browser... %d / %d" % [_visible_paths_ordered.size()-_build_queue.size(), _visible_paths_ordered.size()], C_DIM)
        else:
                set_status("Loaded %d assets — click any to start placing" % _visible_paths_ordered.size(), C_OK)

func _tick_scan()->void:
        var count:=0
        while not _scan_dir_queue.is_empty() and count<SCAN_DIRS_FRAME:
                _scan_one_dir(_scan_dir_queue.pop_front() as String); count+=1
        if _scan_dir_queue.is_empty():
                _is_scanning=false; _on_scan_finished()
        else:
                set_status("Scanning... %d files, %d dirs left"%[_all_paths.size(),_scan_dir_queue.size()], C_DIM)

func _scan_one_dir(folder:String)->void:
        var da:=DirAccess.open(folder); if da==null: return
        da.list_dir_begin(); var fn:=da.get_next()
        while fn!="":
                if not fn.begins_with("."):
                        var full:=folder.path_join(fn)
                        if da.current_is_dir():
                                if fn not in SKIP_DIRS: _scan_dir_queue.append(full)
                        elif fn.get_extension().to_lower() in import_formats:
                                if not _hidden_paths.has(full): _all_paths.append(full)
                fn=da.get_next()
        da.list_dir_end()

func _on_scan_finished()->void:
        var filter:=_search_edit.text if is_instance_valid(_search_edit) else ""
        _rebuild_browser(filter)
        set_status("Loaded %d assets — click any to start placing"%_all_paths.size(),C_OK)

func _can_preview_path(path:String)->bool: return path.get_extension().to_lower() in ALL_PREVIEW_EXTS

func _check_visible_thumbnails()->void:
        if not is_instance_valid(_asset_scroll): return
        var scroll_rect := _asset_scroll.get_global_rect()
        if scroll_rect.size.x <= 1.0 or scroll_rect.size.y <= 1.0: return
        var load_rect := scroll_rect.grow_side(SIDE_BOTTOM, float(_preview_size))

        var dispatched := 0      # studio render dispatches this tick
        var cache_loads := 0     # disk PNG loads this tick (each decodes a file)

        for path in _visible_paths_ordered:
                if dispatched >= MAX_PER_TICK: break
                if _thumb_cache.has(path): continue
                if _thumb_pending.has(path):
                        # Safety net: a pending entry older than 10s means its
                        # render was silently lost (e.g. an aborted coroutine).
                        # Drop the stale entry so the path can be re-dispatched
                        # — a thumbnail can never get permanently wedged.
                        if Time.get_ticks_msec() - int(_thumb_pending[path]) < 10000: continue
                        _thumb_pending.erase(path); _thumb_gen_ir_map.erase(path)
                if _thumb_perm_failed.has(path): continue
                if not _can_preview_path(path): continue

                var ir := _card_ir_map.get(path, null) as TextureRect
                if not is_instance_valid(ir) or not ir.is_inside_tree(): continue
                if ir.size.x < 1.0 or ir.size.y < 1.0: continue
                if not load_rect.intersects(ir.get_global_rect()): continue

                var ir_id := ir.get_instance_id()

                # ── Disk cache first (any format — instant PNG load) ──────────
                if _thumb_gen != null and _thumb_gen.has_disk_cache(path):
                        if cache_loads >= MAX_CACHE_LOADS: break   # spread decode cost — no spikes
                        var cached_tex: ImageTexture = _thumb_gen.load_disk_cache(path) as ImageTexture
                        cache_loads += 1
                        if cached_tex != null:
                                _thumb_cache_set(path, cached_tex)
                                _set_texture_safely(path, cached_tex, ir_id)
                                continue
                # ── Offline studio render (single unified queue) ──────────────
                # rev 4: EVERY format goes through uap_thumb_gen now. The old
                # light-format path fed cards the editor's small SQUARE previews
                # — pillarboxed bars in the rectangular wells and blurry upscale
                # on big cards. Self-rendering gives every asset the same
                # studio-lit, aspect-exact, disk-cached thumbnail.
                if _thumb_gen == null: continue
                if _thumb_gen_ir_map.has(path): continue   # already queued in renderer
                _thumb_pending[path] = Time.get_ticks_msec()   # dispatch timestamp (stale-detect)
                _thumb_heavy_count += 1
                _thumb_gen_ir_map[path] = ir_id
                _thumb_gen.enqueue(path)
                dispatched += 1

func _process_thumb_retries()->void:
        if _thumb_retry_queue.is_empty(): return
        var entry = _thumb_retry_queue.pop_front(); var ed = entry as Dictionary
        var path = ed["path"] as String; var ir_id = ed["ir_id"] as int
        var gen = ed.get("gen", _browser_generation) as int
        if gen != _browser_generation: return
        if _thumb_cache.has(path): _set_texture_safely(path, _thumb_cache[path], ir_id); return
        # Everything funnels through the offline studio renderer now.
        if _thumb_gen != null and not _thumb_gen_ir_map.has(path):
                _thumb_pending[path] = Time.get_ticks_msec(); _thumb_heavy_count += 1
                _thumb_gen_ir_map[path] = ir_id; _thumb_gen.enqueue(path)

# Called by uap_thumb_gen when a thumbnail is ready (offline studio render)
func _on_thumb_gen_ready(path: String, tex: ImageTexture) -> void:
        var ir_id: int = _thumb_gen_ir_map.get(path, 0) as int
        _thumb_gen_ir_map.erase(path)
        _thumb_pending.erase(path)
        if _thumb_heavy_count > 0: _thumb_heavy_count -= 1

        if tex == null:
                # Could not render: 2D scene, broken deps, or non-3D root.
                # Mark permanent fail — no retry this session, no error output.
                _thumb_perm_failed[path] = true
                return

        _thumb_cache_set(path, tex)
        # Prefer live card-map lookup — ir_id may be stale if browser was rebuilt
        var ir := _card_ir_map.get(path, null) as TextureRect
        if is_instance_valid(ir):
                _set_texture_safely(path, tex, ir.get_instance_id())
        elif ir_id != 0:
                _set_texture_safely(path, tex, ir_id)

func _set_texture_safely(path:String, tex:Texture2D, ir_id:int)->void:
        var ir = instance_from_id(ir_id) as TextureRect
        if is_instance_valid(ir) and ir.get_meta("uap_path","") == path: _card_apply_texture(ir,tex)

## rev 4: real thumbnails are GENERATED at the well's exact aspect ratio, so
## STRETCH_KEEP_ASPECT_COVERED fills the well edge-to-edge with zero bars.
## COVERED is also the structural anti-bar guarantee: if a stale or mismatched
## texture ever lands in a card anyway (different slider size, old cache), it
## is centre-CROPPED by a hair instead of pillarboxed with black bars.
##  • small editor fallback icons (16-32px theme icons shown before a render
##    exists) → draw at native size, centered. Scaling those up to the well
##    height produced a huge blurry icon (spotted in the 2.2 editor run).
func _card_apply_texture(ir:TextureRect, tex:Texture2D)->void:
        if ir==null or tex==null: return
        # native-size mode is only safe when the texture is small on BOTH
        # axes (theme fallback icons). A wide texture under the height limit
        # would have been drawn at native width and spilled over the card —
        # now it scales like every real thumbnail. Combined with
        # ir.clip_contents this makes thumbnail overflow structurally
        # impossible.
        var lim:=float(maxi(40,int(40*_es)))
        var ts:=tex.get_size()
        var native:bool=ts.x<lim and ts.y<lim
        ir.stretch_mode=TextureRect.STRETCH_KEEP_CENTERED if native else TextureRect.STRETCH_KEEP_ASPECT_COVERED
        ir.texture=tex

func _thumb_cache_set(path:String, tex:Texture2D)->void:
        if _thumb_cache.has(path): _thumb_lru.erase(path)
        _thumb_cache[path]=tex; _thumb_lru.append(path)
        while _thumb_lru.size()>THUMB_CACHE_MAX: _thumb_cache.erase(_thumb_lru.pop_front() as String)

func invalidate_thumb_cache(path: String) -> void:
        ## Called by plugin.gd after a scene screenshot is saved to disk.
        ## Removes the in-memory entry so the next visibility check reloads from disk.
        _thumb_cache.erase(path); _thumb_lru.erase(path)
        _thumb_perm_failed.erase(path)
        _thumb_pending.erase(path)
        _thumb_gen_ir_map.erase(path)
        # If this path is currently visible in the browser, reload immediately
        var ir := _card_ir_map.get(path, null) as TextureRect
        if not is_instance_valid(ir): return
        if _thumb_gen != null and _thumb_gen.has_disk_cache(path):
                var tex: ImageTexture = _thumb_gen.load_disk_cache(path) as ImageTexture
                if tex != null:
                        _thumb_cache_set(path, tex)
                        _set_texture_safely(path, tex, ir.get_instance_id())

func get_random_multi_selected_path()->String:
        if _multi_selected.size()>1:
                var valid:Array=[]
                for p in _multi_selected:
                        if ResourceLoader.exists(p as String): valid.append(p)
                if not valid.is_empty(): return valid[randi()%valid.size()] as String
        return ""

func _paths_for_active_group()->Array:
        if _active_group==-2: return _favorite_paths
        if _active_group>=0 and _active_group<_groups.size():
                return (_groups[_active_group] as Dictionary)["paths"] as Array
        return []

func is_favorite(path:String)->bool:
        return _favorite_paths.has(path)

func _update_card_favorite_star(card:PanelContainer,path:String)->void:
        if not _card_fav_btn_map.has(path): return
        var btn:=_card_fav_btn_map[path] as TextureButton
        if not is_instance_valid(btn): return
        # 2.5: the star is a TextureButton now (see _add_card) — it has no
        # per-state icon theme colors, so the dim-white vs gold language is
        # applied through self_modulate. Same contrast values as before.
        if is_favorite(path):
                btn.self_modulate=C_WARN
        else:
                btn.self_modulate=Color(1,1,1,0.6)

func toggle_favorite(path:String)->void:
        if _favorite_paths.has(path): _favorite_paths.erase(path)
        else: _favorite_paths.append(path)
        _rebuild_group_bar(); _save_config()
        # Refresh just this card's star overlay rather than rebuilding the whole
        # grid — toggling a favorite shouldn't cost a full browser rebuild.
        if _card_map.has(path):
                var card:=_card_map[path] as PanelContainer
                if is_instance_valid(card): _update_card_favorite_star(card,path)
        # If Favorites is the active filter, un-favoriting should drop the card
        # from view immediately rather than leaving a stale, no-longer-favorited
        # card visible until the next unrelated rebuild.
        if _active_group==-2: _rebuild_browser_now()

func get_random_group_path()->String:
        var paths:Array=_paths_for_active_group()
        if paths.is_empty(): return ""
        var valid:Array=[]
        for p in paths:
                if ResourceLoader.exists(p as String): valid.append(p)
        return "" if valid.is_empty() else valid[randi()%valid.size()] as String

func _input(event:InputEvent)->void:
        if not _capturing_action.is_empty() and event is InputEventKey:
                var ke:=event as InputEventKey; if not ke.pressed: return
                get_viewport().set_input_as_handled()
                if ke.keycode==KEY_ESCAPE:
                        var ob:=_key_capture_btns.get(_capturing_action) as Button
                        if is_instance_valid(ob): ob.text=_keycode_to_display(shortcuts.get(_capturing_action,KEY_NONE)); ob.remove_theme_color_override("font_color")
                        _capturing_action=""; return
                shortcuts[_capturing_action]=ke.keycode
                var btn:=_key_capture_btns.get(_capturing_action) as Button
                if is_instance_valid(btn): btn.text=_keycode_to_display(ke.keycode); btn.remove_theme_color_override("font_color")
                _capturing_action=""; _save_config(); return

        # Ctrl+A (Cmd+A on macOS) — select all currently-visible assets in the
        # browser. Scoped to "mouse is over the browser" so this doesn't hijack
        # Ctrl+A from, say, the script editor or a LineEdit's own select-all-text.
        if event is InputEventKey:
                var kev:=event as InputEventKey
                if kev.pressed and not kev.echo and kev.keycode==KEY_A and kev.is_command_or_control_pressed():
                        var focused:=get_viewport().gui_get_focus_owner()
                        if focused is LineEdit or focused is TextEdit: return
                        if not is_instance_valid(_asset_scroll): return
                        if not _asset_scroll.get_global_rect().has_point(_asset_scroll.get_global_mouse_position()): return
                        _select_all_assets()
                        get_viewport().set_input_as_handled()
                return

        if not event is InputEventMouseButton: return
        var mb:=event as InputEventMouseButton
        if not mb.ctrl_pressed or not mb.pressed: return
        if is_instance_valid(browser_ui) and not browser_ui.get_global_rect().has_point(mb.global_position): return
        if mb.button_index==MOUSE_BUTTON_WHEEL_UP: _set_preview_size(_preview_size+8); get_viewport().set_input_as_handled()
        elif mb.button_index==MOUSE_BUTTON_WHEEL_DOWN: _set_preview_size(_preview_size-8); get_viewport().set_input_as_handled()

func _set_preview_size(v:int)->void:
        _preview_size=clampi(v,int(54*_es),int(200*_es))
        if is_instance_valid(_preview_lbl): _preview_lbl.text="%dpx"%_preview_size
        if is_instance_valid(_thumb_gen):
                var m:=_card_thumb_metrics(_preview_size)
                var size_changed:bool=_thumb_gen.call("set_preview_metrics",m.x,m.y)
                if size_changed:
                        # Crossed into a different render size — the in-memory cache
                        # holds textures rendered for the OLD size, so drop it and let
                        # everything re-fetch (disk cache for that size, if it already
                        # exists from a previous visit at this slider position, or a
                        # fresh studio render).
                        _thumb_pending.clear(); _thumb_cache.clear(); _thumb_lru.clear()
                        _thumb_gen_ir_map.clear()
                        _thumb_gen.call("clear_queue")
        _save_config(); _rebuild_browser_now()

func _update_columns()->void:
        if not is_instance_valid(_asset_grid) or not is_instance_valid(_asset_scroll): return
        # _grid_rm is 0 since rev 4 (the favorite star sits fully inside the
        # card, nothing overhangs the grid) — kept in the formula so a future
        # reservation needs no re-derivation.
        var w:=_asset_scroll.size.x-float(_grid_rm)
        if w<20.0: w=browser_ui.size.x-4.0
        if w<20.0: w=180.0
        # Exact slot math: every card is a square of _preview_size px, so
        # `cols` cards plus (cols-1) separators must never exceed the visible
        # width. This is what guarantees cards can never overlap or clip —
        # the old formula (w/(S+6)) could overestimate by one column and let
        # the grid overflow horizontally.
        var sep:int=_asset_grid.get_theme_constant("h_separation")
        var cols:=maxi(1,int((w+sep)/float(_preview_size+sep)))
        var n:=_asset_grid.get_child_count()
        if n>0: cols=mini(cols,n)
        _asset_grid.columns=cols


# ─── UI Helpers ───────────────────────────────────────────────────────────────
func _lbl(text:String, color:Color=C_TEXT)->Label:
        var l:=Label.new(); l.text=text; l.add_theme_color_override("font_color",color); return l

func _sep()->HSeparator: return HSeparator.new()

func _chk(val:bool, tip:String="")->CheckButton:
        var c:=CheckButton.new(); c.button_pressed=val; c.tooltip_text=tip; return c

func _info(parent:Node, text:String)->void:
        var l:=Label.new(); l.text=text; l.add_theme_color_override("font_color",C_DIM)
        l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; parent.add_child(l)

func _row(label:String, parent:Node, lw:int=90)->HBoxContainer:
        var row:=HBoxContainer.new(); row.add_theme_constant_override("separation",5)
        row.size_flags_horizontal=SIZE_EXPAND_FILL; row.custom_minimum_size=Vector2.ZERO
        var l:=Label.new(); l.text=label; l.add_theme_color_override("font_color",C_TEXT)
        l.size_flags_horizontal=SIZE_SHRINK_BEGIN; l.custom_minimum_size=Vector2(int(lw*_es),0); l.clip_text=true
        row.add_child(l); parent.add_child(row); return row

func _row_chk(label:String, parent:Node, val:bool, cb:Callable, tip:String="")->CheckButton:
        var row:=_row(label,parent); var c:=_chk(val,tip); c.toggled.connect(cb); row.add_child(c); return c

func _ss(lo:float, hi:float, val:float, step:float)->SliderSpin:
        var s:=SliderSpin.new(); s.min_value=lo; s.max_value=hi; s.value=val; s.step=step; return s

func _spin(lo:float, hi:float, val:float, step:float)->CompactSpin:
        var s:=CompactSpin.new(); s.min_value=lo; s.max_value=hi; s.value=val; s.step=step; return s

# ─── 3D Tactile Style Helpers (2.1 UI overhaul) ─────────────────────────────
## Raised "tactile" active style: SOLID full-color face (no transparency),
## a darker bottom edge that reads as the button's lower bevel, and a subtle
## drop shadow so the control physically sits above the panel.
func _style_raised(bg:Color, radius:int=4)->StyleBoxFlat:
        var sb:=StyleBoxFlat.new()
        sb.bg_color=bg
        sb.set_corner_radius_all(radius)
        sb.border_width_bottom=maxi(2,int(3*_es))
        sb.border_color=bg.darkened(0.45)
        sb.shadow_color=Color(0,0,0,0.40)
        sb.shadow_size=maxi(2,int(3*_es))
        sb.shadow_offset=Vector2(0,int(2*_es))
        sb.content_margin_left=int(8*_es); sb.content_margin_right=int(8*_es)
        sb.content_margin_top=int(4*_es);  sb.content_margin_bottom=int(5*_es)
        return sb

## Inset "carved" style: a surface recessed INTO the panel. Darker fill than
## the surrounding panel, NO outline border on any side — the only edge
## marking is a single darker line along the BOTTOM edge, which reads exactly
## like the bottom bevel of the raised style but inverted: the surface looks
## chiseled inward instead of sitting outward. Used for group chips, group
## rows and the collapsible section boxes so every "group" shares one design.
func _style_inset(active:bool)->StyleBoxFlat:
        var sb:=StyleBoxFlat.new()
        sb.bg_color=S_INSET_ACTIVE_BG if active else S_INSET_BG
        sb.set_corner_radius_all(4)
        sb.border_width_bottom=maxi(2,int(2*_es))
        sb.border_color=S_INSET_ACTIVE_EDGE if active else S_INSET_SHADOW
        sb.content_margin_left=int(8*_es); sb.content_margin_right=int(8*_es)
        sb.content_margin_top=int(4*_es);  sb.content_margin_bottom=int(4*_es)
        return sb

## Clean idle style for resting buttons: flat dark, NO white highlight.
func _style_idle()->StyleBoxFlat:
        var sb:=StyleBoxFlat.new()
        sb.bg_color=S_IDLE_BG
        sb.set_corner_radius_all(3)
        sb.content_margin_left=int(7*_es); sb.content_margin_right=int(7*_es)
        sb.content_margin_top=int(3*_es);  sb.content_margin_bottom=int(4*_es)
        return sb

func _style_idle_hover()->StyleBoxFlat:
        var sb:=_style_idle(); sb.bg_color=S_IDLE_HOVER; return sb
func _style_idle_pressed()->StyleBoxFlat:
        var sb:=_style_idle(); sb.bg_color=S_IDLE_PRESSED; return sb

## Applies a full set of stylebox state overrides at once.
func _apply_states(btn:Button, normal:StyleBox, hover:StyleBox, pressed:StyleBox)->void:
        btn.add_theme_stylebox_override("normal",normal)
        btn.add_theme_stylebox_override("hover",hover)
        btn.add_theme_stylebox_override("pressed",pressed)
        btn.add_theme_stylebox_override("hover_pressed",pressed)
        btn.add_theme_stylebox_override("focus",StyleBoxEmpty.new())
        btn.add_theme_stylebox_override("disabled",normal)

## Plain near-white text for raised faces — deliberately NO dark font
## outline (the outline was removed in 2.2: it read as a dirty black border
## around every active button label).
func _apply_raised_text(btn:Button)->void:
        for cn in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color"]:
                btn.add_theme_color_override(cn,Color(0.96,0.98,1.0))

## Restores default editor-theme text colors on an idle button.
func _clear_raised_text(btn:Button)->void:
        for cn in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color","font_outline_color"]:
                if btn.has_theme_color_override(cn): btn.remove_theme_color_override(cn)
        if btn.has_theme_constant_override("outline_size"): btn.remove_theme_constant_override("outline_size")

## One-call dressing for a resting (non-active) button.
func _style_idle_button(btn:Button)->void:
        _apply_states(btn,_style_idle(),_style_idle_hover(),_style_idle_pressed())
        _clear_raised_text(btn)
        btn.focus_mode=Control.FOCUS_NONE
        btn.set_meta("uap_styled",true)   # 2.3: marks the control for the global walker

## One-call dressing for an ACTIVE raised button in the given color.
func _style_raised_button(btn:Button,color:Color,hover_lighten:float=0.08)->void:
        _apply_states(btn,_style_raised(color),_style_raised(color.lightened(hover_lighten)),_style_raised(color))
        _apply_raised_text(btn)
        btn.focus_mode=Control.FOCUS_NONE
        btn.set_meta("uap_styled",true)   # 2.3: marks the control for the global walker

## One-call dressing for an inset chip (groups, format toggles).
func _style_inset_button(btn:Button,active:Color=Color(0.80,0.85,0.92),inactive:Color=Color(0.62,0.65,0.73))->void:
        _apply_states(btn,_style_inset(false),_style_inset_hover_box(),_style_inset(true))
        btn.add_theme_color_override("font_color",inactive)
        btn.add_theme_color_override("font_hover_color",Color(0.85,0.88,0.95))
        btn.add_theme_color_override("font_pressed_color",active)
        btn.add_theme_color_override("font_hover_pressed_color",Color(0.90,0.93,1.0))
        btn.add_theme_color_override("font_focus_color",inactive)
        btn.focus_mode=Control.FOCUS_NONE
        btn.set_meta("uap_styled",true)   # 2.3: marks the control for the global walker

func _style_inset_hover_box()->StyleBoxFlat:
        var sb:=_style_inset(false); sb.bg_color=S_INSET_HOVER; return sb

# ─── 2.3 Global dressing pass ───────────────────────────────────────────────
## The redesigned theme covers every control the build code styles EXPLICITLY
## (mode/scroll buttons, rail, chips, sections…), but a handful of controls
## were still created bare and therefore kept the bright default editor look
## ("Create Asset Zoo", the Source dropdown, misc action buttons, LineEdits).
## This walker dresses EVERY bare Button / OptionButton / LineEdit under the
## panel in the carved dark language. Controls that already carry their own
## stylebox overrides — or that opted out via the "uap_styled" meta — are
## left untouched, so the raised/inset/flat designs all survive.
func _apply_uap_theme(root:Node)->void:
        _theme_n_b=0; _theme_n_o=0; _theme_n_l=0
        _apply_uap_theme_walk(root)
        # 2.5: the per-pass result is NO LONGER printed to the Output dock —
        # it was a debug leftover from the 2.3 theme system and spammed two
        # lines on every panel build. The counters are kept (harness can read
        # them) but the plugin is silent by default now.

func _apply_uap_theme_walk(node:Node)->void:
        # OptionButton extends Button — test it FIRST.
        if node is OptionButton:
                var ob:=node as OptionButton
                if not ob.has_meta("uap_styled"):
                        _style_option_button(ob); _theme_n_o+=1
        elif node is Button:
                var b:=node as Button
                if not b.has_meta("uap_styled") and not b.has_theme_stylebox_override("normal"):
                        _style_idle_button(b); _theme_n_b+=1
        elif node is LineEdit:
                var le:=node as LineEdit
                if not le.has_meta("uap_styled"):
                        _style_line_edit(le); _theme_n_l+=1
        for c in node.get_children(): _apply_uap_theme_walk(c)

## Dark carved style for the remaining bare buttons is _style_idle_button;
## this adds the dropdown-specific pieces: text colors, arrow tint and a
## themed popup list (the bright default PopupMenu was singled out in the
## feedback screenshot as not fitting the redesign).
func _style_option_button(ob:OptionButton)->void:
        ob.set_meta("uap_styled",true)
        _apply_states(ob,_style_idle(),_style_idle_hover(),_style_idle_pressed())
        ob.add_theme_color_override("font_color",C_TEXT)
        ob.add_theme_color_override("font_focus_color",C_TEXT)
        ob.add_theme_color_override("font_hover_color",Color(0.92,0.95,1.0))
        ob.add_theme_color_override("font_pressed_color",Color(0.95,0.97,1.0))
        ob.add_theme_color_override("font_hover_pressed_color",Color(0.95,0.97,1.0))
        ob.add_theme_color_override("font_disabled_color",Color(0.45,0.47,0.55))
        # The arrow icon follows the Button icon-color overrides in Godot 4.
        ob.add_theme_color_override("icon_normal_color",Color(0.60,0.63,0.72))
        ob.add_theme_color_override("icon_hover_color",Color(0.90,0.93,1.0))
        ob.add_theme_color_override("icon_pressed_color",Color(0.95,0.97,1.0))
        ob.add_theme_color_override("icon_hover_pressed_color",Color(0.95,0.97,1.0))
        ob.add_theme_color_override("icon_focus_color",Color(0.60,0.63,0.72))
        ob.focus_mode=Control.FOCUS_NONE
        var pop:=ob.get_popup()
        if pop!=null: _style_popup_menu(pop)

## Carved-in LineEdit: darker-than-panel fill, bottom edge line, no outline
## ring; focus deepens the fill and turns the bottom line blue.
func _style_line_edit(le:LineEdit)->void:
        le.set_meta("uap_styled",true)
        var n:=StyleBoxFlat.new(); n.bg_color=S_SECTION_BG; n.set_corner_radius_all(4)
        n.border_width_bottom=maxi(1,int(2*_es)); n.border_color=S_SECTION_LINE
        n.content_margin_left=int(7*_es); n.content_margin_right=int(7*_es)
        n.content_margin_top=int(3*_es);  n.content_margin_bottom=int(3*_es)
        var f:=StyleBoxFlat.new(); f.bg_color=S_INSET_BG; f.set_corner_radius_all(4)
        f.border_width_bottom=maxi(1,int(2*_es)); f.border_color=Color(0.20,0.44,0.72)
        f.content_margin_left=int(7*_es); f.content_margin_right=int(7*_es)
        f.content_margin_top=int(3*_es);  f.content_margin_bottom=int(3*_es)
        var ro:=StyleBoxFlat.new(); ro.bg_color=S_INSET_BG; ro.set_corner_radius_all(4)
        ro.border_width_bottom=maxi(1,int(2*_es)); ro.border_color=S_SECTION_LINE
        ro.content_margin_left=int(7*_es); ro.content_margin_right=int(7*_es)
        ro.content_margin_top=int(3*_es);  ro.content_margin_bottom=int(3*_es)
        le.add_theme_stylebox_override("normal",n)
        le.add_theme_stylebox_override("focus",f)
        le.add_theme_stylebox_override("read_only",ro)
        le.add_theme_color_override("font_color",C_TEXT)
        le.add_theme_color_override("font_placeholder_color",Color(0.50,0.52,0.60,0.55))
        le.add_theme_color_override("font_readonly_color",Color(0.55,0.57,0.65))
        le.add_theme_color_override("caret_color",C_ACCENT)
        le.add_theme_color_override("selection_color",Color(0.28,0.62,1.0,0.35))

func _section(parent:VBoxContainer, title:String, open:bool=true)->VBoxContainer:
        # 2.2 carved-in group design (shared with group chips/rows):
        #   • fill clearly DARKER than the panel — no semitransparent middle
        #   • NO outline border on any side
        #   • one darker line along the BOTTOM edge → the box reads as carved
        #     into the panel (same visual language as the chips/rows).
        var pc:=PanelContainer.new(); pc.size_flags_horizontal=SIZE_EXPAND_FILL
        var ps:=StyleBoxFlat.new(); ps.bg_color=S_SECTION_BG; ps.set_corner_radius_all(4)
        ps.border_width_bottom=maxi(2,int(2*_es)); ps.border_color=S_SECTION_LINE
        ps.set_content_margin_all(0); pc.add_theme_stylebox_override("panel",ps); parent.add_child(pc)
        var outer:=VBoxContainer.new(); outer.size_flags_horizontal=SIZE_EXPAND_FILL
        outer.add_theme_constant_override("separation",0); pc.add_child(outer)
        var hdr:=Button.new(); hdr.flat=true; hdr.alignment=HORIZONTAL_ALIGNMENT_LEFT
        hdr.size_flags_horizontal=SIZE_EXPAND_FILL
        hdr.text="  "+title
        UAPIcons.set_button_icon(hdr, "action_chevron_down" if open else "action_chevron_right")
        hdr.add_theme_color_override("font_color",C_HEAD)
        # Header row blends into the section surface; only a subtle lighten on
        # hover signals clickability. No accent fill, no border.
        var hs:=StyleBoxFlat.new(); hs.bg_color=Color(0,0,0,0); hs.set_corner_radius_all(0)
        hs.set_content_margin_all(6)
        var hs_hover:=StyleBoxFlat.new(); hs_hover.bg_color=Color(1,1,1,0.04); hs_hover.set_corner_radius_all(0)
        hs_hover.set_content_margin_all(6)
        hdr.add_theme_stylebox_override("normal",hs); hdr.add_theme_stylebox_override("hover",hs_hover)
        hdr.add_theme_stylebox_override("pressed",hs); hdr.add_theme_stylebox_override("focus",StyleBoxEmpty.new())
        outer.add_child(hdr)
        var wrap:=MarginContainer.new(); wrap.visible=open; wrap.size_flags_horizontal=SIZE_EXPAND_FILL
        for s in ["margin_left","margin_right","margin_top","margin_bottom"]: wrap.add_theme_constant_override(s,8)
        outer.add_child(wrap)
        var body:=VBoxContainer.new(); body.size_flags_horizontal=SIZE_EXPAND_FILL
        body.add_theme_constant_override("separation",5); wrap.add_child(body)
        hdr.pressed.connect(func():
                wrap.visible=not wrap.visible
                UAPIcons.set_button_icon(hdr, "action_chevron_down" if wrap.visible else "action_chevron_right"))
        return body

func _make_tab(n:String, icon_name:String="")->VBoxContainer:
        var sc:=ScrollContainer.new(); sc.name=n
        sc.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO
        sc.size_flags_horizontal=SIZE_EXPAND_FILL; sc.size_flags_vertical=SIZE_EXPAND_FILL
        _settings_tabs.add_child(sc)
        if not icon_name.is_empty():
                var tex := UAPIcons.get_icon(icon_name)
                if tex != null:
                        _settings_tabs.set_tab_icon(_settings_tabs.get_tab_idx_from_control(sc), tex)
        var mg:=MarginContainer.new(); mg.size_flags_horizontal=SIZE_EXPAND_FILL
        for s in ["margin_left","margin_right","margin_top","margin_bottom"]: mg.add_theme_constant_override(s,6)
        sc.add_child(mg)
        var vb:=VBoxContainer.new(); vb.size_flags_horizontal=SIZE_EXPAND_FILL
        vb.add_theme_constant_override("separation",6); mg.add_child(vb); return vb

# ─── Main Build ───────────────────────────────────────────────────────────────
func _build_ui()->void:
        settings_ui=VBoxContainer.new(); settings_ui.name="UAP Settings"
        settings_ui.size_flags_horizontal=SIZE_EXPAND_FILL; settings_ui.size_flags_vertical=SIZE_EXPAND_FILL
        browser_ui=VBoxContainer.new(); browser_ui.name="UAP Browser"
        browser_ui.size_flags_horizontal=SIZE_EXPAND_FILL; browser_ui.size_flags_vertical=SIZE_EXPAND_FILL
        browser_ui.custom_minimum_size=Vector2(0, int(200*_es))
        _build_header(browser_ui); _build_browser_panel(browser_ui)
        _apply_header_collapsed()
        _build_mode_bar(settings_ui); settings_ui.add_child(_sep()); _build_settings_panel(settings_ui)
        # 2.3: after every control exists, sweep the whole panel once and dress
        # all bare buttons/dropdowns/line-edits in the redesigned theme (the
        # "Create Asset Zoo" button and the Source dropdown were still bright
        # editor-default before this pass).
        # NOTE: settings_ui/browser_ui are deliberately NOT children of this
        # node at build time — plugin.gd hands them to the dock system right
        # after _ready — so the walk must start from BOTH roots explicitly.
        _apply_uap_theme(settings_ui)
        _apply_uap_theme(browser_ui)

## Applies _header_collapsed to the header block: version label, title text,
## the folder/search rows and the status bar hide when collapsed — while the
## group chip strip moves INTO the title bar (2.2 advanced collapse), so all
## groups remain one click away in the slim state.
## Called once after _build_header()/_build_browser_panel() build all the
## nodes it touches, and again every time the button is pressed.
func _apply_header_collapsed()->void:
        # 2.2 advanced collapse:
        #   • expanded  → title bar shows "Ultimate Asset Placer" + version;
        #     the group chips live in their row above the browser as before.
        #   • collapsed → the SAME chip strip is moved INTO the title bar, so
        #     every group stays directly clickable while the panel is collapsed.
        if not is_instance_valid(_header_master_btn): return
        var collapsed:bool=_header_collapsed
        if is_instance_valid(_header_ver_lbl): _header_ver_lbl.visible=not collapsed
        if is_instance_valid(_header_title_lbl): _header_title_lbl.visible=not collapsed
        if is_instance_valid(_status_bar_panel): _status_bar_panel.visible=not collapsed
        if is_instance_valid(_search_panel): _search_panel.visible=not collapsed
        if is_instance_valid(_header_spacer):
                # Expanded → spacer eats the free width (title+version hug the
                # left, stars+chevron pin the right corner). Collapsed → the
                # chip strip is EXPAND_FILL, so the spacer must give up its
                # share or the chips would float with a hole in the middle.
                _header_spacer.size_flags_horizontal=SIZE_FILL if collapsed else SIZE_EXPAND_FILL
        if is_instance_valid(_group_bar):
                if collapsed:
                        if _group_bar.get_parent()!=_header_title_row:
                                var old:=_group_bar.get_parent()
                                if old!=null: old.remove_child(_group_bar)
                                _header_title_row.add_child(_group_bar)
                                _header_title_row.move_child(_group_bar,1)
                                _group_bar.size_flags_horizontal=SIZE_EXPAND_FILL
                                _group_bar.size_flags_vertical=SIZE_EXPAND_FILL
                                _group_bar.visible=true
                else:
                        if _group_bar.get_parent()!=_search_panel:
                                var old:=_group_bar.get_parent()
                                if old!=null: old.remove_child(_group_bar)
                                _search_panel.add_child(_group_bar)
                                # folder row, search row, chips, multi-select bar
                                _search_panel.move_child(_group_bar,2)
                                _group_bar.size_flags_horizontal=SIZE_EXPAND_FILL
                                _group_bar.size_flags_vertical=0
                                _group_bar.visible=true
        UAPIcons.set_button_icon(_header_master_btn, "action_chevron_right" if collapsed else "action_chevron_down")
        _header_master_btn.tooltip_text="Expand panel" if collapsed else "Collapse panel — groups stay on the bar"

func _build_header(root:VBoxContainer)->void:
        var hp:=PanelContainer.new(); hp.size_flags_horizontal=SIZE_EXPAND_FILL
        var hs:=StyleBoxFlat.new(); hs.bg_color=Color(0.09,0.10,0.14); hs.set_corner_radius_all(0)
        hs.set_content_margin_all(7); hs.border_color=C_ACCENT; hs.border_width_bottom=2
        hp.add_theme_stylebox_override("panel",hs); root.add_child(hp)
        var vb:=VBoxContainer.new(); vb.size_flags_horizontal=SIZE_EXPAND_FILL
        vb.clip_contents=true; vb.add_theme_constant_override("separation",5); hp.add_child(vb)
        var tr:=HBoxContainer.new(); tr.add_theme_constant_override("separation",6)
        tr.size_flags_horizontal=SIZE_EXPAND_FILL; vb.add_child(tr)
        _header_title_row=tr
        var bar:=ColorRect.new(); bar.color=C_ACCENT; bar.custom_minimum_size=Vector2(3,0)
        bar.size_flags_vertical=SIZE_EXPAND_FILL; tr.add_child(bar)
        var tl:=Label.new(); tl.text="Ultimate Asset Placer"; tl.add_theme_color_override("font_color",C_HEAD)
        # 2.5 rev 6: the title NO LONGER expands across the bar — it hugs the
        # left edge so the version label can sit right next to the text, and a
        # flexible spacer pushes the rating stars + chevron to the right corner.
        # NOTE: clip_text must stay OFF here — a clipping label's minimum width
        # collapses to ~1 glyph, which would render the title as just "U".
        tr.add_child(tl)
        _header_title_lbl=tl
        _header_ver_lbl=Label.new(); _header_ver_lbl.text=UAPIcons.get_plugin_version(); _header_ver_lbl.add_theme_color_override("font_color",C_DIM)
        _header_ver_lbl.tooltip_text="Ultimate Asset Placer version"
        tr.add_child(_header_ver_lbl)
        # Flexible spacer: expanded → eats all free width so stars+chevron pin
        # the right corner; collapsed → shrinks away so the chip strip takes it.
        _header_spacer=Control.new(); _header_spacer.size_flags_horizontal=SIZE_EXPAND_FILL
        tr.add_child(_header_spacer)
        # 2.5 rev 7: retractable rating stars — this little arrow tucks the
        # stars away (» action_arrow_right) or brings them back (« 
        # action_arrow_left). Row order stays: [spacer][retract][STARS][chevron],
        # so the stars keep hugging the right corner when visible.
        _header_stars_btn=Button.new(); _header_stars_btn.flat=true
        _header_stars_btn.focus_mode=Control.FOCUS_NONE
        UAPIcons.set_button_icon(_header_stars_btn, "action_arrow_right")
        _header_stars_btn.tooltip_text="Hide rating stars"
        _header_stars_btn.pressed.connect(_toggle_stars_hidden)
        tr.add_child(_header_stars_btn)
        # Animated rating stars — pinned to the RIGHT CORNER (where the version
        # label used to sit), before the collapse chevron. Never in the chips.
        _build_rating_stars()
        _header_master_btn=Button.new(); _header_master_btn.flat=true
        _header_master_btn.focus_mode=Control.FOCUS_NONE
        _header_master_btn.size_flags_horizontal=SIZE_SHRINK_END
        tr.add_child(_header_master_btn)
        _header_master_btn.pressed.connect(func():
                var was_collapsed:bool=_header_collapsed
                _header_collapsed=not _header_collapsed
                # Opening/expanding the browser ALWAYS brings the rating stars
                # back — hiding them is a manual, session-only choice (rev 7).
                if was_collapsed:
                        _stars_hidden=false; _apply_stars_hidden()
                _apply_header_collapsed(); _save_config())
        # 2.2: the "Search & Filters" collapse toggle is GONE — the folder,
        # search and group rows are always visible while the panel is expanded.
        # The only remaining collapse is the master bar, which keeps the group
        # chips reachable in its collapsed state.
        _search_panel=VBoxContainer.new(); _search_panel.size_flags_horizontal=SIZE_EXPAND_FILL
        _search_panel.add_theme_constant_override("separation",5); vb.add_child(_search_panel)
        var fr:=HBoxContainer.new(); fr.add_theme_constant_override("separation",3)
        fr.size_flags_horizontal=SIZE_EXPAND_FILL; fr.clip_contents=true; _search_panel.add_child(fr)
        var flbl:=Label.new(); flbl.text="Folder:"; flbl.custom_minimum_size=Vector2(int(44*_es),0)
        flbl.add_theme_color_override("font_color",C_DIM); fr.add_child(flbl)
        _folder_edit=LineEdit.new(); _folder_edit.text=current_folder
        _folder_edit.size_flags_horizontal=SIZE_EXPAND_FILL
        _folder_edit.text_submitted.connect(_on_folder_submitted); fr.add_child(_folder_edit)
        var brw:=Button.new(); brw.tooltip_text="Browse..."; UAPIcons.set_button_icon(brw, "action_browse"); brw.pressed.connect(_on_browse_pressed); fr.add_child(brw)
        var rfr:=Button.new(); rfr.text="Refresh"; rfr.tooltip_text="Refresh folder scan"
        UAPIcons.set_button_icon(rfr, "action_refresh")
        rfr.pressed.connect(_scan_folder); fr.add_child(rfr)
        var sr:=HBoxContainer.new(); sr.add_theme_constant_override("separation",3)
        sr.size_flags_horizontal=SIZE_EXPAND_FILL; sr.clip_contents=true; _search_panel.add_child(sr)
        _search_edit=LineEdit.new(); _search_edit.placeholder_text="Search assets..."
        _search_edit.size_flags_horizontal=SIZE_EXPAND_FILL
        _search_edit.text_changed.connect(_on_search_changed); sr.add_child(_search_edit)
        _preview_lbl=Label.new(); _preview_lbl.text="%dpx"%_preview_size
        _preview_lbl.tooltip_text="Ctrl+Scroll to resize thumbnails"
        _preview_lbl.add_theme_color_override("font_color",C_DIM)
        _preview_lbl.size_flags_horizontal=SIZE_SHRINK_END; _preview_lbl.clip_text=true
        _preview_lbl.custom_minimum_size=Vector2.ZERO; sr.add_child(_preview_lbl)
        var clrb:=Button.new(); clrb.text="Clear"
        clrb.size_flags_horizontal=SIZE_SHRINK_END; clrb.pressed.connect(_on_clear_browser); sr.add_child(clrb)
        for b:Button in [brw,rfr,clrb]: _style_idle_button(b)
        _group_bar=FlowContainer.new(); _group_bar.size_flags_horizontal=SIZE_EXPAND_FILL
        _group_bar.clip_contents=true; _group_bar.add_theme_constant_override("h_separation",2)
        _group_bar.add_theme_constant_override("v_separation",2); _search_panel.add_child(_group_bar)
        _rebuild_group_bar()
        _multisel_bar=HBoxContainer.new(); _multisel_bar.size_flags_horizontal=SIZE_EXPAND_FILL
        _multisel_bar.add_theme_constant_override("separation",4); _multisel_bar.visible=false; _search_panel.add_child(_multisel_bar)
        _multisel_lbl=Label.new(); _multisel_lbl.add_theme_color_override("font_color",C_MULTI)
        _multisel_lbl.size_flags_horizontal=SIZE_EXPAND_FILL; _multisel_bar.add_child(_multisel_lbl)
        _multisel_group_opt=OptionButton.new(); _multisel_group_opt.size_flags_horizontal=SIZE_EXPAND_FILL
        _multisel_group_opt.add_icon_item(UAPIcons.get_icon("feature_favorite"), "Favorites")
        for g in _groups: _multisel_group_opt.add_item((g as Dictionary)["name"])
        _multisel_bar.add_child(_multisel_group_opt)
        var asel:=Button.new(); asel.text="Add All"; asel.tooltip_text="Add all selected to chosen group"
        asel.pressed.connect(_on_add_multi_selected_to_group); _multisel_bar.add_child(asel)
        var rmsel:=Button.new(); rmsel.text="Remove"
        rmsel.tooltip_text="Remove all selected assets from the current group\n(or from all groups if viewing All/search)"
        rmsel.pressed.connect(_on_smart_remove_from_group); _multisel_bar.add_child(rmsel)
        var csel:=Button.new(); csel.text="X"; csel.pressed.connect(_clear_multi_select); _multisel_bar.add_child(csel)
        for b:Button in [asel,rmsel,csel]: _style_idle_button(b)
        rmsel.add_theme_color_override("font_color",C_ERROR)

func _build_mode_bar(root:VBoxContainer)->void:
        var mp:=PanelContainer.new(); mp.size_flags_horizontal=SIZE_EXPAND_FILL
        var ms:=StyleBoxFlat.new(); ms.bg_color=Color(0.11,0.12,0.16)
        ms.border_color=C_BORDER; ms.border_width_bottom=1; ms.set_content_margin_all(6)
        mp.add_theme_stylebox_override("panel",ms); root.add_child(mp)
        var vb:=VBoxContainer.new(); vb.size_flags_horizontal=SIZE_EXPAND_FILL
        vb.clip_contents=true; vb.add_theme_constant_override("separation",5); mp.add_child(vb)
        var ml:=Label.new(); ml.text="PLACEMENT MODE"; ml.add_theme_color_override("font_color",C_DIM); vb.add_child(ml)
        var mf:=HBoxContainer.new(); mf.size_flags_horizontal=SIZE_EXPAND_FILL; mf.clip_contents=true
        mf.add_theme_constant_override("separation",3); vb.add_child(mf)
        _mode_buttons.clear()
        # Only show Free/Grid/Surface/Vertex buttons here — Spline is in its own tab
        for i in MODE_BUTTON_INDICES:
                var mi:int = i as int
                var btn:=Button.new(); btn.text=MODE_LABELS[mi]; btn.toggle_mode=true
                btn.tooltip_text=MODE_TIPS[mi]; btn.button_pressed=(mi==place_mode)
                btn.size_flags_horizontal=SIZE_EXPAND_FILL
                btn.pressed.connect(_on_mode_selected.bind(mi)); _mode_buttons.append(btn); mf.add_child(btn)
        _refresh_mode_buttons()
        vb.add_child(_sep())
        var sl:=Label.new(); sl.text="SCROLL WHEEL CONTROL"; sl.add_theme_color_override("font_color",C_DIM); vb.add_child(sl)
        var sf:=HBoxContainer.new(); sf.size_flags_horizontal=SIZE_EXPAND_FILL; sf.clip_contents=true
        sf.add_theme_constant_override("separation",3); vb.add_child(sf)
        _scroll_buttons.clear()
        for i in SCROLL_LABELS.size():
                var btn:=Button.new(); btn.text=SCROLL_LABELS[i]; btn.toggle_mode=true
                btn.button_pressed=(i==scroll_mode); btn.size_flags_horizontal=SIZE_EXPAND_FILL
                btn.pressed.connect(_on_scroll_mode_selected.bind(i)); _scroll_buttons.append(btn); sf.add_child(btn)
        _refresh_scroll_buttons()

func _build_browser_panel(root:VBoxContainer)->void:
        var stp:=PanelContainer.new(); stp.size_flags_horizontal=SIZE_EXPAND_FILL
        var ss:=StyleBoxFlat.new(); ss.bg_color=Color(0.08,0.09,0.12); ss.set_corner_radius_all(3)
        ss.set_content_margin_all(5); stp.add_theme_stylebox_override("panel",ss); root.add_child(stp)
        _status_bar_panel=stp
        var str_r:=HBoxContainer.new(); str_r.add_theme_constant_override("separation",4)
        str_r.size_flags_horizontal=SIZE_EXPAND_FILL; str_r.clip_contents=true; stp.add_child(str_r)
        _status_lbl=Label.new(); _status_lbl.text="Click an asset to start placing"
        _status_lbl.size_flags_horizontal=SIZE_EXPAND_FILL
        _status_lbl.add_theme_color_override("font_color",C_OK); _status_lbl.clip_text=true; str_r.add_child(_status_lbl)
        _stop_btn=Button.new(); _stop_btn.text="Stop"; _stop_btn.disabled=true
        _stop_btn.size_flags_horizontal=SIZE_SHRINK_END; _stop_btn.pressed.connect(_on_stop_pressed); str_r.add_child(_stop_btn)
        _style_idle_button(_stop_btn)
        var pg_wrap:=HBoxContainer.new(); pg_wrap.alignment=BoxContainer.ALIGNMENT_CENTER
        pg_wrap.size_flags_horizontal=SIZE_EXPAND_FILL
        var pb1:=Button.new(); UAPIcons.set_button_icon(pb1, "action_arrow_left"); pb1.tooltip_text="Previous page"; pb1.pressed.connect(_prev_page); pg_wrap.add_child(pb1)
        _page_lbl=Label.new(); _page_lbl.text="Page 1/1"; _page_lbl.custom_minimum_size=Vector2(int(80*_es),0)
        _page_lbl.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; pg_wrap.add_child(_page_lbl)
        var pb2:=Button.new(); UAPIcons.set_button_icon(pb2, "action_arrow_right"); pb2.tooltip_text="Next page"; pb2.pressed.connect(_next_page); pg_wrap.add_child(pb2)
        _style_idle_button(pb1); _style_idle_button(pb2)
        root.add_child(pg_wrap)
        _asset_scroll=ScrollContainer.new()
        _asset_scroll.size_flags_horizontal=SIZE_EXPAND_FILL; _asset_scroll.size_flags_vertical=SIZE_EXPAND_FILL
        _asset_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
        _asset_scroll.clip_contents=true; _asset_scroll.custom_minimum_size=Vector2(0,int(60*_es))
        _asset_scroll.resized.connect(func(): call_deferred("_update_columns"))
        _asset_scroll.set_drag_forwarding(Callable(),_can_drop_asset_files,_drop_asset_files)
        _asset_scroll.get_v_scroll_bar().value_changed.connect(func(_v:float): _thumb_check_timer=0.0)
        root.add_child(_asset_scroll)
        _asset_grid=GridContainer.new(); _asset_grid.columns=3
        _asset_grid.size_flags_horizontal=SIZE_EXPAND_FILL
        # 2.4: rows get clearly more breathing room than columns — the name row
        # makes every card bottom-heavy, so equal gaps read vertically cramped
        # ("upper row is very close to the bottom row").
        _asset_grid.add_theme_constant_override("h_separation",6); _asset_grid.add_theme_constant_override("v_separation",maxi(6,int(10*_es)))
        # rev 4: the favorite star sits FULLY INSIDE the card (pinned to the
        # thumbnail's top-right corner) — nothing overhangs the grid anymore,
        # so the old reserved right strip is gone. The wrapper stays as a
        # zero-margin passthrough so the layout tree is unchanged.
        _grid_rm=0
        var grid_margin:=MarginContainer.new()
        grid_margin.add_theme_constant_override("margin_left",0)
        grid_margin.add_theme_constant_override("margin_right",_grid_rm)
        grid_margin.add_theme_constant_override("margin_top",0)
        grid_margin.add_theme_constant_override("margin_bottom",0)
        _asset_scroll.add_child(grid_margin)
        grid_margin.add_child(_asset_grid)

func _build_settings_panel(root:VBoxContainer)->void:
        # ── 2.1 UI overhaul: Blender-style icon rail ────────────────────────────
        # The TabContainer is kept as the underlying page host (its tab API is
        # used everywhere for titles/icons), but its own tab bar is hidden and
        # replaced by a vertical icon-only rail on the LEFT edge of the panel.
        # Every feature is one click away with no horizontal scrolling, exactly
        # like Blender's editor toolbar.
        # ── 2.2 additions ─────────────────────────────────────────────────────
        #  • A slim header bar above the tab page always shows the NAME of the
        #    active tab ("Place", "Transform", ...).
        #  • Hovering a rail icon pops an instant name label (no editor-tooltip
        #    delay) right next to the rail.
        var outer:=HBoxContainer.new()
        outer.size_flags_horizontal=SIZE_EXPAND_FILL; outer.size_flags_vertical=SIZE_EXPAND_FILL
        outer.add_theme_constant_override("separation",int(5*_es))
        root.add_child(outer)
        _build_tab_rail(outer)
        var right:=VBoxContainer.new(); right.size_flags_horizontal=SIZE_EXPAND_FILL
        right.size_flags_vertical=SIZE_EXPAND_FILL; right.add_theme_constant_override("separation",int(5*_es))
        outer.add_child(right)
        # Tab-name header: carved bar matching the section language. 2.3 adds
        # an info button on the right end that opens the docs chapter for the
        # tab that is currently active.
        var thp:=PanelContainer.new(); thp.size_flags_horizontal=SIZE_EXPAND_FILL
        var tsb:=StyleBoxFlat.new(); tsb.bg_color=S_SECTION_BG; tsb.set_corner_radius_all(4)
        tsb.border_width_bottom=maxi(2,int(2*_es)); tsb.border_color=S_SECTION_LINE
        tsb.content_margin_left=int(9*_es); tsb.content_margin_right=int(6*_es)
        tsb.content_margin_top=int(4*_es); tsb.content_margin_bottom=int(4*_es)
        thp.add_theme_stylebox_override("panel",tsb); right.add_child(thp)
        var th_hb:=HBoxContainer.new(); th_hb.size_flags_horizontal=SIZE_EXPAND_FILL
        th_hb.add_theme_constant_override("separation",int(6*_es)); thp.add_child(th_hb)
        _tab_header_lbl=Label.new(); _tab_header_lbl.text="Place"
        _tab_header_lbl.size_flags_horizontal=SIZE_EXPAND_FILL
        _tab_header_lbl.add_theme_color_override("font_color",C_HEAD)
        th_hb.add_child(_tab_header_lbl)
        _tab_help_btn=Button.new(); _tab_help_btn.flat=true
        _tab_help_btn.focus_mode=Control.FOCUS_NONE
        _tab_help_btn.custom_minimum_size=Vector2(int(20*_es),int(20*_es))
        UAPIcons.set_button_icon_sized(_tab_help_btn,"status_info",maxi(10,int(15*_es)))
        _tab_help_btn.add_theme_color_override("icon_normal_color",Color(0.60,0.63,0.72))
        _tab_help_btn.add_theme_color_override("icon_hover_color",Color(0.95,0.97,1.0))
        _tab_help_btn.add_theme_color_override("icon_pressed_color",Color(1,1,1))
        _tab_help_btn.add_theme_color_override("icon_focus_color",Color(0.95,0.97,1.0))
        _tab_help_btn.set_meta("uap_styled",true)   # keep the global walker's hands off this flat button
        _tab_help_btn.pressed.connect(func(): _open_docs_window(_chapter_for_active_tab()))
        _tab_help_btn.tooltip_text="Open the docs chapter for this tab"
        th_hb.add_child(_tab_help_btn)
        _settings_tabs=TabContainer.new(); _settings_tabs.size_flags_horizontal=SIZE_EXPAND_FILL
        _settings_tabs.size_flags_vertical=SIZE_EXPAND_FILL; _settings_tabs.clip_contents=true
        _settings_tabs.custom_minimum_size=Vector2(0,int(80*_es))
        _settings_tabs.tabs_visible=false   # rail replaces the built-in tab bar
        right.add_child(_settings_tabs)
        _build_place_tab(); _build_transform_tab(); _build_paint_tab()
        _build_spline_tab(); _build_material_tab(); _build_collision_tab()
        _build_physics_tab(); _build_groups_tab(); _build_keys_tab()
        # Docs is NOT a tab page anymore: the rail's docs button opens a
        # dedicated chapter-style window in the center of the screen.
        _build_docs_rail_button()
        _refresh_tab_rail()
        _settings_tabs.tab_changed.connect(func(_i:int): _refresh_tab_rail())
        # Instant hover-name layer (2.2): a plain Control cannot clip nor
        # re-layout the tip, and being the LAST child of `outer` it draws on
        # top of the tab pages. Zero min-size → invisible to the HBox layout.
        _rail_tip_layer=Control.new(); _rail_tip_layer.mouse_filter=Control.MOUSE_FILTER_IGNORE
        _rail_tip_layer.custom_minimum_size=Vector2.ZERO
        _rail_tip_layer.size_flags_horizontal=0; _rail_tip_layer.size_flags_vertical=0
        outer.add_child(_rail_tip_layer)
        _rail_tip_panel=PanelContainer.new(); _rail_tip_panel.visible=false
        _rail_tip_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
        var tsb2:=StyleBoxFlat.new(); tsb2.bg_color=Color(0.06,0.068,0.095)
        tsb2.set_corner_radius_all(3)
        tsb2.border_width_bottom=maxi(1,int(2*_es)); tsb2.border_color=Color(0.018,0.02,0.03)
        tsb2.content_margin_left=int(7*_es); tsb2.content_margin_right=int(7*_es)
        tsb2.content_margin_top=int(2*_es); tsb2.content_margin_bottom=int(2*_es)
        _rail_tip_panel.add_theme_stylebox_override("panel",tsb2)
        _rail_tip_lbl=Label.new(); _rail_tip_lbl.mouse_filter=Control.MOUSE_FILTER_IGNORE
        _rail_tip_lbl.add_theme_color_override("font_color",Color(0.92,0.95,1.0))
        _rail_tip_lbl.add_theme_font_size_override("font_size",maxi(10,int(12*_es)))
        _rail_tip_panel.add_child(_rail_tip_lbl)
        _rail_tip_layer.add_child(_rail_tip_panel)

## Instant rail hover-name (2.2). Shown immediately on mouse_entered — much
## faster than the editor's native tooltip, and positioned next to the rail
## like Blender's toolbar labels.
func _show_rail_tip(btn:Control,text:String)->void:
        if not is_instance_valid(_rail_tip_panel) or not is_instance_valid(_rail_tip_layer): return
        if not btn.is_inside_tree(): return
        _rail_tip_lbl.text=text
        _rail_tip_panel.reset_size()
        _rail_tip_panel.visible=true
        var r:=btn.get_global_rect()
        var pos:=Vector2(r.position.x+r.size.x+int(6*_es),
                r.position.y+r.size.y*0.5-_rail_tip_panel.size.y*0.5)
        # Keep the tip vertically inside the settings panel. NOTE: the tip
        # layer itself is a zero-size helper control — clamp against its
        # PARENT (the panel's HBox), which has the real bounds.
        var bounds:Rect2=_rail_tip_layer.get_parent().get_global_rect()
        pos.y=clampf(pos.y,bounds.position.y,bounds.end.y-_rail_tip_panel.size.y)
        pos.x=clampf(pos.x,bounds.position.x,bounds.end.x-_rail_tip_panel.size.x)
        _rail_tip_panel.global_position=pos

func _hide_rail_tip()->void:
        if is_instance_valid(_rail_tip_panel): _rail_tip_panel.visible=false

# ─── Left Tab Rail (Blender-style) ───────────────────────────────────────────
func _build_tab_rail(parent:Control)->void:
        var rail_panel:=PanelContainer.new()
        rail_panel.size_flags_vertical=SIZE_EXPAND_FILL
        var rs:=StyleBoxFlat.new(); rs.bg_color=Color(0.082,0.09,0.125)
        rs.set_corner_radius_all(4)
        rs.set_content_margin_all(int(3*_es))
        rail_panel.add_theme_stylebox_override("panel",rs)
        parent.add_child(rail_panel)
        var sc:=ScrollContainer.new()
        sc.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
        sc.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO
        sc.size_flags_vertical=SIZE_EXPAND_FILL
        sc.custom_minimum_size=Vector2(int(42*_es),0)
        sc.add_theme_constant_override("scrollbar_margin_right",0)
        rail_panel.add_child(sc)
        _tab_rail=VBoxContainer.new()
        _tab_rail.size_flags_horizontal=SIZE_EXPAND_FILL
        _tab_rail.add_theme_constant_override("separation",int(3*_es))
        sc.add_child(_tab_rail)
        _rail_buttons.clear()
        for i in RAIL_ICON_NAMES.size():
                var btn:=_make_rail_button(RAIL_ICON_NAMES[i],true)
                btn.pressed.connect(_on_rail_tab_pressed.bind(i))
                # 2.2: instant hover-name — show this tab's title immediately
                # next to the rail (no native tooltip delay).
                btn.mouse_entered.connect(func():
                        if is_instance_valid(_settings_tabs) and i<_settings_tabs.get_tab_count():
                                _show_rail_tip(btn,_settings_tabs.get_tab_title(i)))
                btn.mouse_exited.connect(_hide_rail_tip)
                _tab_rail.add_child(btn); _rail_buttons.append(btn)

func _make_rail_button(icon_name:String, dim_icon:bool)->Button:
        var btn:=Button.new()
        btn.toggle_mode=true
        btn.focus_mode=Control.FOCUS_NONE
        btn.custom_minimum_size=Vector2(int(36*_es),int(36*_es))
        btn.tooltip_text=""
        var tex:=UAPIcons.get_icon_sized(icon_name,maxi(12,int(20*_es)))
        if tex!=null: btn.icon=tex
        btn.expand_icon=false
        if dim_icon: _dim_rail_button(btn)
        return btn

## Neutral resting look for a rail button: no background, softly dimmed icon.
func _dim_rail_button(btn:Button)->void:
        _apply_states(btn,StyleBoxEmpty.new(),_style_idle_hover(),_style_idle_pressed())
        _clear_raised_text(btn)
        btn.add_theme_color_override("icon_normal_color",Color(0.63,0.66,0.76))
        btn.add_theme_color_override("icon_hover_color",Color(0.88,0.91,1.0))
        btn.add_theme_color_override("icon_pressed_color",Color(0.96,0.98,1.0))
        btn.add_theme_color_override("icon_hover_pressed_color",Color(0.96,0.98,1.0))
        btn.add_theme_color_override("icon_focus_color",Color(0.88,0.91,1.0))

## Active rail look: the shared blue raised 3D style with a bright icon.
func _raise_rail_button(btn:Button)->void:
        _apply_states(btn,_style_raised(C_ACCENT),_style_raised(C_ACCENT.lightened(0.08)),_style_raised(C_ACCENT))
        btn.add_theme_color_override("icon_normal_color",Color(0.98,1.0,1.0))
        btn.add_theme_color_override("icon_hover_color",Color(1,1,1))
        btn.add_theme_color_override("icon_pressed_color",Color(1,1,1))
        btn.add_theme_color_override("icon_hover_pressed_color",Color(1,1,1))
        btn.add_theme_color_override("icon_focus_color",Color(1,1,1))

func _on_rail_tab_pressed(idx:int)->void:
        if is_instance_valid(_settings_tabs): _settings_tabs.current_tab=idx
        _refresh_tab_rail()

## Re-dresses every rail button to match the TabContainer's live state and
## keeps the tab-name header above the page in sync.
func _refresh_tab_rail()->void:
        if not is_instance_valid(_tab_rail): return
        var cur:int=_settings_tabs.current_tab if is_instance_valid(_settings_tabs) else 0
        for i in _rail_buttons.size():
                var btn:=_rail_buttons[i] as Button
                if not is_instance_valid(btn): continue
                var active:bool=(i==cur)
                btn.set_pressed_no_signal(active)
                if active: _raise_rail_button(btn)
                else: _dim_rail_button(btn)
        if is_instance_valid(_tab_header_lbl) and is_instance_valid(_settings_tabs) and cur<_settings_tabs.get_tab_count():
                _tab_header_lbl.text=_settings_tabs.get_tab_title(cur)
                # Keep the header info button's tooltip on the ACTIVE tab.
                if is_instance_valid(_tab_help_btn):
                        _tab_help_btn.tooltip_text="Help — open the docs chapter for the %s tab"%_settings_tabs.get_tab_title(cur)

## 2.3: chapter index in uap_docs.get_chapters() that documents the tab that
## is currently active (mapping table TAB_DOCS_CHAPTER, page order aligned).
func _chapter_for_active_tab()->int:
        if not is_instance_valid(_settings_tabs): return 0
        var cur:int=_settings_tabs.current_tab
        if cur<0 or cur>=TAB_DOCS_CHAPTER.size(): return 0
        return TAB_DOCS_CHAPTER[cur]

func _build_docs_rail_button()->void:
        if not is_instance_valid(_tab_rail): return
        var sp:=Control.new(); sp.custom_minimum_size=Vector2(0,int(4*_es)); _tab_rail.add_child(sp)
        var line:=HSeparator.new(); _tab_rail.add_child(line)
        _rail_docs_btn=_make_rail_button("tab_docs",true)
        _rail_docs_btn.tooltip_text="Docs — open the full documentation window"
        # 2.5: the rail's Docs button ALWAYS opens the Welcome chapter — it
        # used to inherit whatever chapter the last per-tab "i" button had
        # opened (chapter=-1 kept the previous selection), which read like a
        # bug. Per-tab help buttons still pass their own explicit chapter.
        _rail_docs_btn.pressed.connect(func(): _open_docs_window(0))
        _rail_docs_btn.mouse_entered.connect(func(): _show_rail_tip(_rail_docs_btn,"Docs"))
        _rail_docs_btn.mouse_exited.connect(_hide_rail_tip)
        _tab_rail.add_child(_rail_docs_btn)
        _dim_rail_button(_rail_docs_btn)


# ─── TABS ─────────────────────────────────────────────────────────────────────
func _build_place_tab()->void:
        var vb:=_make_tab("Place", "tab_place")
        var pc:=_section(vb,"Parent Node",false)
        _info(pc,"Placed assets will be children of this node.")
        var pr:=_row("Parent",pc)
        _parent_edit=LineEdit.new(); _parent_edit.placeholder_text="(scene root)"; _parent_edit.editable=false
        _parent_edit.size_flags_horizontal=SIZE_EXPAND_FILL; pr.add_child(_parent_edit)
        var pkb:=Button.new(); pkb.text="Pick"; pkb.pressed.connect(_on_pick_parent); pr.add_child(pkb)
        var clp:=Button.new(); clp.text="X"; clp.pressed.connect(_on_clear_parent); pr.add_child(clp)
        var us:=_section(vb,"Scene Settings")
        _row_chk("Unpack Scenes",us,unpack_scenes,func(v:bool):unpack_scenes=v;_save_config(),
                "If True, scene structure is fully visible in the tree.\nIf False, scenes remain packed instances.")
        var g:=_section(vb,"Grid & Snapping")
        _row_chk("Show Grid",g,show_grid,_on_show_grid_changed,"Show grid lines in 3D viewport")
        _row_chk("Snap to Grid",g,grid_enabled,_on_grid_enabled_changed,"Snap placement to grid XZ")
        var gsr:=_row("Grid Size",g); _grid_size_spin=_ss(0.0625,200.0,grid_size,0.0625)
        _grid_size_spin.value_changed.connect(_on_grid_size_changed); gsr.add_child(_grid_size_spin)
        var gml:=Label.new(); gml.text="m"; gml.add_theme_color_override("font_color",C_DIM); gsr.add_child(gml)
        var grb:=Button.new(); grb.text="1m"
        grb.pressed.connect(func(): grid_size=1.0; if is_instance_valid(_grid_size_spin):_grid_size_spin.set_value_no_signal(1.0); if is_instance_valid(placer):placer.call("rebuild_grid"); _save_config())
        gsr.add_child(grb)
        var ghr:=_row("Grid Y",g); _grid_h_spin=_ss(-100.0,100.0,grid_height,0.5)
        _grid_h_spin.value_changed.connect(_on_grid_h_changed); ghr.add_child(_grid_h_spin)
        var ld:=Button.new(); UAPIcons.set_button_icon(ld, "action_chevron_down"); ld.tooltip_text="Lower grid height"; ld.pressed.connect(func(): nudge_grid_height(-grid_size)); ghr.add_child(ld)
        var lu:=Button.new(); UAPIcons.set_button_icon(lu, "action_chevron_up"); lu.tooltip_text="Raise grid height"; lu.pressed.connect(func(): nudge_grid_height(grid_size)); ghr.add_child(lu)
        var gvr:=_row("View Dist",g); var gvs:=_ss(1.0,2000.0,grid_view_dist,1.0)
        gvs.value_changed.connect(_on_grid_vd_changed); gvr.add_child(gvs)
        var gvu:=Label.new(); gvu.text="m"; gvu.add_theme_color_override("font_color",C_DIM); gvr.add_child(gvu)
        gvs.tooltip_text="Half-extent of the floor grid in metres. The grid re-centers on the viewport camera as you navigate, so a big view distance means visible grid everywhere you go."
        _row_chk("Floor Follow Cam",g,grid_follow,_on_grid_follow_changed,
                "When ON the floor grid rides the viewport camera — as you move, the grid re-renders around you (lines stay locked onto world grid multiples, so nothing slides). Turn OFF to pin it to the world center.")
        # 2.5 rev 7 — axis wall grids, living in the grid group as requested.
        # Each one toggles on/off individually: ON draws the wall grid in the
        # viewport (Grid mode, respects the master Show Grid toggle) and lets
        # objects snap onto that plane. With several enabled, the plane closest
        # to the camera under the mouse wins.
        _info(g,"Axis wall grids snap objects onto vertical planes — X grid = XY plane (orange), Z grid = ZY plane (green). With several on, the plane closest to the camera wins. Every plane follows the viewport camera and can be made huge via its View Dist slider.")
        _row_chk("X Axis Grid",g,x_grid_enabled,_on_x_grid_changed,"Wall grid on the XY plane — snaps X + Y, locks Z to Pos Z")
        _row_chk("X Follow Cam",g,x_grid_follow,_on_x_grid_follow_changed,
                "When ON the X wall rides the viewport camera in X and Y (the wall plane itself stays at Pos Z). Turn OFF to pin it at Center Y.")
        var xsr:=_row("X View Dist",g); var xss:=_ss(0.5,2000.0,x_grid_size,0.5)
        xss.value_changed.connect(_on_x_grid_size_changed); xsr.add_child(xss)
        var xsu:=Label.new(); xsu.text="m"; xsu.add_theme_color_override("font_color",C_DIM); xsr.add_child(xsu)
        xss.tooltip_text="Half-extent of the X wall grid in metres (how far it reaches from the camera)."
        var xpr:=_row("X Pos Z",g); var xps:=_ss(-2000.0,2000.0,x_grid_pos,0.5)
        xps.value_changed.connect(_on_x_grid_pos_changed); xpr.add_child(xps)
        var xpu:=Label.new(); xpu.text="m"; xpu.add_theme_color_override("font_color",C_DIM); xpr.add_child(xpu)
        var xcr:=_row("X Center Y",g); var xcs:=_ss(-2000.0,2000.0,x_grid_cy,0.5)
        xcs.value_changed.connect(_on_x_grid_cy_changed); xcr.add_child(xcs)
        var xcu:=Label.new(); xcu.text="m"; xcu.add_theme_color_override("font_color",C_DIM); xcr.add_child(xcu)
        _row_chk("Z Axis Grid",g,z_grid_enabled,_on_z_grid_changed,"Wall grid on the ZY plane — snaps Z + Y, locks X to Pos X")
        _row_chk("Z Follow Cam",g,z_grid_follow,_on_z_grid_follow_changed,
                "When ON the Z wall rides the viewport camera in Z and Y (the wall plane itself stays at Pos X). Turn OFF to pin it at Center Y.")
        var zsr:=_row("Z View Dist",g); var zss:=_ss(0.5,2000.0,z_grid_size,0.5)
        zss.value_changed.connect(_on_z_grid_size_changed); zsr.add_child(zss)
        var zsu:=Label.new(); zsu.text="m"; zsu.add_theme_color_override("font_color",C_DIM); zsr.add_child(zsu)
        zss.tooltip_text="Half-extent of the Z wall grid in metres (how far it reaches from the camera)."
        var zpr:=_row("Z Pos X",g); var zps:=_ss(-2000.0,2000.0,z_grid_pos,0.5)
        zps.value_changed.connect(_on_z_grid_pos_changed); zpr.add_child(zps)
        var zpu:=Label.new(); zpu.text="m"; zpu.add_theme_color_override("font_color",C_DIM); zpr.add_child(zpu)
        var zcr:=_row("Z Center Y",g); var zcs:=_ss(-2000.0,2000.0,z_grid_cy,0.5)
        zcs.value_changed.connect(_on_z_grid_cy_changed); zcr.add_child(zcs)
        var zcu:=Label.new(); zcu.text="m"; zcu.add_theme_color_override("font_color",C_DIM); zcr.add_child(zcu)
        var h:=_section(vb,"Height Offset")
        var hor:=_row("Offset Y",h); _height_spin=_ss(-500.0,500.0,height_offset,0.05)
        _height_spin.value_changed.connect(_on_height_changed); hor.add_child(_height_spin)
        _row_chk("Snap Height",h,height_snap,_on_height_snap_changed,"Snap to Grid Size steps")
        var sv:=_section(vb,"Surface & Vertex Options",false)
        _row_chk("Align to Normal",sv,align_to_normal,_on_align_normal_changed,"Surface mode: tilt asset to surface normal.")
        _row_chk("Mesh Vertex Snap",sv,vertex_snap_mesh,_on_vertex_mesh_changed,"Vertex mode: test actual mesh vertices.")
        var vssr:=_row("Magnet px",sv); _vss_spin=_ss(5.0,300.0,vertex_snap_strength,1.0)
        _vss_spin.value_changed.connect(func(v:float): vertex_snap_strength=v;_save_config()); vssr.add_child(_vss_spin)
        var ff:=_section(vb,"Format Filter",false)
        _info(ff,"Choose which 3D formats to scan. Right-click any asset card to remove it from the browser list; bring removed assets back anytime — drag them in from the FileSystem dock, import their folder, or use the Restore Hidden button below.")
        var fmt_flow:=FlowContainer.new(); fmt_flow.size_flags_horizontal=SIZE_EXPAND_FILL
        fmt_flow.add_theme_constant_override("h_separation",3); fmt_flow.add_theme_constant_override("v_separation",3); ff.add_child(fmt_flow)
        _format_btns.clear()
        for i in ALL_FORMATS.size():
                var ext:=ALL_FORMATS[i] as String; var fb:=Button.new(); fb.text=FORMAT_LABELS[i]
                fb.toggle_mode=true; fb.button_pressed=import_formats.has(ext); fb.tooltip_text="."+ext
                fb.pressed.connect(_on_format_toggled.bind(ext)); fmt_flow.add_child(fb); _format_btns.append(fb)
                _style_inset_button(fb)
        var fr2:=HBoxContainer.new(); fr2.add_theme_constant_override("separation",4); ff.add_child(fr2)
        var allb:=Button.new(); allb.text="All On"
        allb.pressed.connect(func(): import_formats=ALL_FORMATS.duplicate(); for fb in _format_btns:(fb as Button).button_pressed=true; _scan_folder();_save_config())
        fr2.add_child(allb)
        var nonb:=Button.new(); nonb.text="All Off"
        nonb.pressed.connect(func(): import_formats.clear(); for fb in _format_btns:(fb as Button).button_pressed=false; _scan_folder();_save_config())
        fr2.add_child(nonb)
        var rhb:=Button.new(); rhb.text="Restore Hidden"
        rhb.tooltip_text="Bring back every asset that was removed from the browser list via right-click."
        rhb.pressed.connect(func():
                if _hidden_paths.is_empty():
                        set_status("No hidden assets to restore.",C_DIM); return
                var n:=_hidden_paths.size(); _hidden_paths.clear()
                _scan_folder(); _save_config()
                set_status("Restored %d previously removed asset(s)."%n,C_OK))
        fr2.add_child(rhb)
        _style_idle_button(allb); _style_idle_button(nonb); _style_idle_button(rhb)
        var zoo:=_section(vb,"Asset Zoo",false)
        _info(zoo,"Lays out assets in a grid for inspection. Choose which assets to include below.")
        var zr:=HBoxContainer.new(); zr.add_theme_constant_override("separation",4); zoo.add_child(zr)
        var zb:=Button.new(); zb.text="Create Asset Zoo"; zb.size_flags_horizontal=SIZE_EXPAND_FILL
        UAPIcons.set_button_icon(zb, "feature_zoo")
        zb.pressed.connect(_on_zoo_pressed); zr.add_child(zb)
        var zsrc_row:=_row("Source",zoo)
        _zoo_source_opt=OptionButton.new(); _zoo_source_opt.size_flags_horizontal=SIZE_EXPAND_FILL
        _zoo_source_opt.add_item("All Loaded Assets"); _zoo_source_opt.set_item_tooltip(0,"Every asset ever loaded into the browser this session.")
        _zoo_source_opt.add_item("Current Group Filter"); _zoo_source_opt.set_item_tooltip(1,"Whatever group/Favorites filter is active in the browser bar right now.")
        _zoo_source_opt.add_item("Selected Assets"); _zoo_source_opt.set_item_tooltip(2,"Only the assets currently multi-selected (Ctrl/Shift-click) in the browser.")
        _zoo_source_opt.selected=_zoo_source
        _zoo_source_opt.item_selected.connect(func(idx:int): _zoo_source=idx; _save_config())
        zsrc_row.add_child(_zoo_source_opt)
        var zsp:=_row("Spacing",zoo); _zoo_spacing_spin=_ss(0.5,50.0,2.0,0.5); zsp.add_child(_zoo_spacing_spin)
        var zlr:=_row("Show Labels",zoo)
        var zlchk:=_chk(_zoo_show_labels,"Show floating Label3D names above each asset.")
        zlchk.toggled.connect(func(v:bool): _zoo_show_labels=v;_save_config()); zlr.add_child(zlchk)

func _build_transform_tab()->void:
        var vb:=_make_tab("Transform", "tab_transform")
        var rot:=_section(vb,"Rotation Snap")
        var rmr:=_row("Snap Mode",rot); _rot_opt=OptionButton.new(); _rot_opt.size_flags_horizontal=SIZE_EXPAND_FILL
        for it in ["Free","90 deg","45 deg","15 deg","Custom"]: _rot_opt.add_item(it)
        _rot_opt.selected=rotation_snap_mode; _rot_opt.item_selected.connect(_on_rot_mode_changed); rmr.add_child(_rot_opt)
        _custom_row=_row("Custom deg",rot); _custom_row.visible=(rotation_snap_mode==4)
        _custom_spin=_ss(0.5,180.0,custom_snap_deg,0.5)
        _custom_spin.value_changed.connect(_on_custom_deg_changed); _custom_row.add_child(_custom_spin)
        var rv:=_section(vb,"Current Rotation")
        var xr:=_row("Rot X",rv); _rot_x_spin=_ss(-360.0,360.0,0.0,1.0); _rot_x_spin.value_changed.connect(_on_rot_x_changed); xr.add_child(_rot_x_spin)
        var yr:=_row("Rot Y",rv); _rot_y_spin=_ss(-360.0,360.0,0.0,1.0); _rot_y_spin.value_changed.connect(_on_rot_y_changed); yr.add_child(_rot_y_spin)
        var zr2:=_row("Rot Z",rv); _rot_z_spin=_ss(-360.0,360.0,0.0,1.0); _rot_z_spin.value_changed.connect(_on_rot_z_changed); zr2.add_child(_rot_z_spin)
        var rb2:=Button.new(); rb2.text="Reset X Y Z"; rb2.size_flags_horizontal=SIZE_EXPAND_FILL
        rb2.pressed.connect(func(): if is_instance_valid(placer):placer.call("apply_preset_orient",0.0,0.0,0.0)); rv.add_child(rb2)
        var oi:=_section(vb,"Quick Orient Presets",false)
        var of_:=FlowContainer.new(); of_.size_flags_horizontal=SIZE_EXPAND_FILL
        of_.add_theme_constant_override("h_separation",3); of_.add_theme_constant_override("v_separation",3); oi.add_child(of_)
        _orient_btn(of_,"Normal",0,0,0); _orient_btn(of_,"Upside Down",180,0,0)
        _orient_btn(of_,"Lay Fwd",90,0,0); _orient_btn(of_,"Lay Back",-90,0,0)
        _orient_btn(of_,"Tilt L",0,0,-90); _orient_btn(of_,"Tilt R",0,0,90)
        _orient_btn(of_,"Turn 90",0,90,0); _orient_btn(of_,"Turn 180",0,180,0)
        var rr:=_section(vb,"Random Rotation")
        _row_chk("Enable",rr,random_rot,_on_random_rot_changed)
        var rmnr:=_row("Min deg",rr); var rmins:=_ss(-360.0,360.0,rrot_min,1.0)
        rmins.value_changed.connect(func(v:float):rrot_min=v;_save_config()); rmnr.add_child(rmins)
        var rmxr:=_row("Max deg",rr); var rmaxs:=_ss(-360.0,360.0,rrot_max,1.0)
        rmaxs.value_changed.connect(func(v:float):rrot_max=v;_save_config()); rmxr.add_child(rmaxs)
        var rt:=_section(vb,"Random Tilt"); _info(rt,"Tilts X and Z randomly.")
        _row_chk("Enable",rt,random_tilt,func(v:bool):random_tilt=v;_save_config())
        var rtmr:=_row("+/- Max deg",rt); var rtms:=_ss(0.0,180.0,rtilt_max,0.5)
        rtms.value_changed.connect(func(v:float):rtilt_max=v;rtilt_min=-v;_save_config()); rtmr.add_child(rtms)
        var sc:=_section(vb,"Scale")
        var sp2:=FlowContainer.new(); sp2.size_flags_horizontal=SIZE_EXPAND_FILL
        sp2.add_theme_constant_override("h_separation",3); sp2.add_theme_constant_override("v_separation",3); sc.add_child(sp2)
        for pv:float in [0.25,0.5,1.0,1.5,2.0,3.0,5.0]:
                var pb:=Button.new(); var raw:="%.4f"%pv; raw=raw.rstrip("0").rstrip(".")
                pb.text="x"+raw; pb.pressed.connect(_apply_scale_preset.bind(pv)); sp2.add_child(pb)
        var unir:=_row("Uniform",sc); var unic:=_chk(uniform_scale); unic.toggled.connect(_on_uniform_toggled); unir.add_child(unic)
        var u2:=_row("Scale",sc); u2.visible=uniform_scale
        _scale_spin=_ss(0.01,20.0,place_scale_all,0.01); _scale_spin.value_changed.connect(_on_scale_all_changed)
        u2.add_child(_scale_spin); _uni_scale_row=u2
        _xyz_box=VBoxContainer.new(); _xyz_box.visible=not uniform_scale; _xyz_box.size_flags_horizontal=SIZE_EXPAND_FILL
        _xyz_box.add_theme_constant_override("separation",4); sc.add_child(_xyz_box)
        var sxr:=_row("X",_xyz_box); _scale_x_spin=_ss(0.01,20.0,place_scale_x,0.01); _scale_x_spin.value_changed.connect(_on_scale_x_changed); sxr.add_child(_scale_x_spin)
        var syr:=_row("Y",_xyz_box); _scale_y_spin=_ss(0.01,20.0,place_scale_y,0.01); _scale_y_spin.value_changed.connect(_on_scale_y_changed); syr.add_child(_scale_y_spin)
        var szr:=_row("Z",_xyz_box); _scale_z_spin=_ss(0.01,20.0,place_scale_z,0.01); _scale_z_spin.value_changed.connect(_on_scale_z_changed); szr.add_child(_scale_z_spin)
        var rs:=_section(vb,"Random Scale")
        _row_chk("Enable",rs,random_scale,_on_random_scale_changed)
        var rsmn:=_row("Min",rs); var rsmins:=_ss(0.01,20.0,rscale_min,0.01)
        rsmins.value_changed.connect(func(v:float):rscale_min=v;_save_config()); rsmn.add_child(rsmins)
        var rsmx:=_row("Max",rs); var rsmaxs:=_ss(0.01,20.0,rscale_max,0.01)
        rsmaxs.value_changed.connect(func(v:float):rscale_max=v;_save_config()); rsmx.add_child(rsmaxs)

func _orient_btn(parent:Container,label:String,rx:float,ry:float,rz:float)->void:
        var btn:=Button.new(); btn.text=label
        btn.pressed.connect(func(): if is_instance_valid(placer):placer.call("apply_preset_orient",rx,ry,rz)); parent.add_child(btn)

func _apply_scale_preset(v:float)->void:
        if uniform_scale:
                place_scale_all=v;place_scale_x=v;place_scale_y=v;place_scale_z=v
                if is_instance_valid(_scale_spin):_scale_spin.set_value_no_signal(v)
        else:
                place_scale_x=v;place_scale_y=v;place_scale_z=v
                if is_instance_valid(_scale_x_spin):_scale_x_spin.set_value_no_signal(v)
                if is_instance_valid(_scale_y_spin):_scale_y_spin.set_value_no_signal(v)
                if is_instance_valid(_scale_z_spin):_scale_z_spin.set_value_no_signal(v)
        _save_config()

func _build_paint_tab()->void:
        var vb:=_make_tab("Paint", "tab_paint")
        var pm:=_section(vb,"Paint Mode")
        _row_chk("Enable Paint",pm,paint_mode,_on_paint_changed,"Hold LMB and drag to place continuously")
        var spr:=_row("Spacing",pm); var sps:=_ss(0.1,10.0,paint_spacing,0.05)
        sps.value_changed.connect(func(v:float):paint_spacing=v;_save_config()); spr.add_child(sps)
        _row_chk("Scatter",pm,paint_scatter,func(v:bool):paint_scatter=v;_save_config(),"Random XZ offset")
        var scr:=_row("Scatter R",pm); var scs:=_ss(0.01,50.0,scatter_radius,0.05)
        scs.value_changed.connect(func(v:float):scatter_radius=v;_save_config()); scr.add_child(scs)
        var br:=_section(vb,"Volumetric Brush",false)
        _info(br,"Replaces drag-painting with a volumetric ring brush. Assets scatter inside the circle.")
        var _br_row:=_row("Use Brush",br)
        var brchk:=_chk(paint_as_brush,"Use Brush instead of single-instance dragging")
        brchk.toggled.connect(func(v:bool): paint_as_brush=v;_save_config(); if is_instance_valid(placer):placer.call("refresh_ghosts"))
        _br_row.add_child(brchk)
        var rr:=_row("Radius m",br); var rs:=_ss(0.1,50.0,brush_radius,0.1)
        rs.value_changed.connect(_on_brush_radius_changed); rr.add_child(rs)
        var dr:=_row("Density",br); var ds:=_ss(0.05,10.0,brush_density,0.05)
        ds.value_changed.connect(func(v:float):brush_density=v;_save_config()); dr.add_child(ds)
        var ffr:=_row("Falloff",br); var fs:=_ss(0.0,1.0,brush_falloff,0.05)
        fs.value_changed.connect(func(v:float):brush_falloff=v;_save_config()); ffr.add_child(fs)
        var mpr:=_row("Mask Texture",br)
        var mlbl:=Label.new(); mlbl.text="(none)" if brush_texture_path.is_empty() else brush_texture_path.get_file()
        mlbl.size_flags_horizontal=SIZE_EXPAND_FILL; mlbl.add_theme_color_override("font_color",C_DIM); mlbl.clip_text=true; mpr.add_child(mlbl)
        var mpk:=Button.new(); mpk.text="Pick"
        mpk.pressed.connect(func():
                var dlg:=EditorFileDialog.new(); dlg.file_mode=EditorFileDialog.FILE_MODE_OPEN_FILE
                dlg.access=EditorFileDialog.ACCESS_RESOURCES
                dlg.filters=PackedStringArray(["*.png ; PNG Image","*.jpg ; JPG Image","*.webp ; WebP Image"])
                dlg.file_selected.connect(func(p:String): brush_texture_path=p;mlbl.text=p.get_file();_save_config(); if is_instance_valid(placer):placer.call("set_brush_texture_path",p))
                add_child(dlg); dlg.popup_centered(Vector2i(700,500)))
        mpr.add_child(mpk)
        var mclr:=Button.new(); mclr.text="X"
        mclr.pressed.connect(func(): brush_texture_path="";mlbl.text="(none)";_save_config(); if is_instance_valid(placer):placer.call("set_brush_texture_path",""))
        mpr.add_child(mclr)
        var rgp:=_section(vb,"Random Group Placer")
        var _rgp_row:=_row("Enable",rgp)
        var _rgp_chk:=_chk(random_group_place,"Random asset from active group per placement")
        _rgp_chk.toggled.connect(func(v:bool): random_group_place=v;_save_config(); if v and _active_group==-1:set_status("Activate a group in the browser bar first.",C_WARN))
        _rgp_row.add_child(_rgp_chk)
        _info(rgp,"If MULTIPLE items are selected in the browser, the brush will automatically random-paint those instead.")
        var mm:=_section(vb,"MultiMesh Painter",false)
        _row_chk("MultiMesh Mode",mm,multimesh_mode,_on_multimesh_toggled,"Paint multiple instances as one MultiMesh")
        _row_chk("Add Collision",mm,mm_collision_enabled,func(v:bool):mm_collision_enabled=v;_save_config())
        var mclr_btn:=Button.new(); mclr_btn.text="Clear All MultiMesh Instances"
        mclr_btn.size_flags_horizontal=SIZE_EXPAND_FILL; mclr_btn.pressed.connect(_on_mm_clear); mm.add_child(mclr_btn)
        var mcol:=Button.new(); mcol.text="Generate Instance Collision"
        mcol.size_flags_horizontal=SIZE_EXPAND_FILL; mcol.pressed.connect(_on_mm_generate_collision); mm.add_child(mcol)
        var mbk:=Button.new(); mbk.text="Commit MultiMesh"; mbk.size_flags_horizontal=SIZE_EXPAND_FILL
        mbk.pressed.connect(func(): if is_instance_valid(placer):placer.call("mm_commit_to_scene");set_status("MultiMesh committed.",C_OK))
        mm.add_child(mbk)

func _active_group_name()->String:
        if _active_group==-2: return "Favorites"
        if _active_group>=0 and _active_group<_groups.size(): return str((_groups[_active_group] as Dictionary)["name"])
        return "(no group active)"


func _build_spline_tab()->void:
        var vb:=_make_tab("Spline", "tab_spline")
        # ── Mode status banner ────────────────────────────────────────────────────
        var status_row:=HBoxContainer.new(); status_row.add_theme_constant_override("separation",6)
        status_row.size_flags_horizontal=SIZE_EXPAND_FILL; vb.add_child(status_row)
        _spline_status_icon=TextureRect.new()
        _spline_status_icon.custom_minimum_size=Vector2(13,13)
        _spline_status_icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        _spline_status_icon.size_flags_vertical=SIZE_SHRINK_CENTER
        status_row.add_child(_spline_status_icon)
        _spline_mode_lbl=Label.new()
        _spline_mode_lbl.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
        _spline_mode_lbl.size_flags_horizontal=SIZE_EXPAND_FILL
        status_row.add_child(_spline_mode_lbl)
        # 2.5 rev 3: "Create New Spline" was pulled OUT of the group — the user
        # wants it as a standalone tab-level action sitting directly ABOVE the
        # Exit button, and NEITHER of them inside the "1. Spline Node Setup"
        # section. Both sit straight on the panel, so both get the raised 3D
        # face (same treatment as Start Physics) to stay readable as buttons.
        var create_row:=HBoxContainer.new(); create_row.add_theme_constant_override("separation",4); vb.add_child(create_row)
        var csbtn:=Button.new(); csbtn.text="+ Create New Spline"; csbtn.size_flags_horizontal=SIZE_EXPAND_FILL
        _style_raised_button(csbtn,C_BTN_ACTION)
        csbtn.pressed.connect(_on_create_spline_node); create_row.add_child(csbtn)
        var exit_row:=HBoxContainer.new(); exit_row.add_theme_constant_override("separation",4); vb.add_child(exit_row)
        var exit_btn:=Button.new(); exit_btn.text="Exit Spline Mode"; exit_btn.size_flags_horizontal=SIZE_EXPAND_FILL
        UAPIcons.set_button_icon(exit_btn, "action_close")
        _style_raised_button(exit_btn,C_BTN_ACTION)
        exit_btn.tooltip_text="Restore the previous placement mode and re-enable the ghost cursor."
        exit_btn.pressed.connect(_exit_spline_mode); exit_row.add_child(exit_btn)
        _update_spline_mode_label()
        # 2.5: the long "Advanced Spline System…" description block was removed
        # — every tab has an "i" help button now, so paragraphs like this one
        # only pushed the actual controls further down the panel.
        vb.add_child(_sep())
        var cs_sec:=_section(vb,"1. Spline Node Setup")
        var btn_row1:=HBoxContainer.new()
        # 2.5 rev 3: buttons INSIDE a group section keep the quiet idle look —
        # only standalone panel-level actions are raised.
        var selbtn:=Button.new(); selbtn.text="Use Selected Spline"; selbtn.size_flags_horizontal=SIZE_EXPAND_FILL
        selbtn.pressed.connect(_on_select_existing_spline); btn_row1.add_child(selbtn); cs_sec.add_child(btn_row1)
        var util_row:=HBoxContainer.new()
        var sm_btn:=Button.new(); sm_btn.text="Smooth"; sm_btn.size_flags_horizontal=SIZE_EXPAND_FILL
        sm_btn.pressed.connect(func(): if is_instance_valid(_active_spline_tool):_active_spline_tool.call("smooth_all_points"))
        var sh_btn:=Button.new(); sh_btn.text="Sharpen"; sh_btn.size_flags_horizontal=SIZE_EXPAND_FILL
        sh_btn.pressed.connect(func(): if is_instance_valid(_active_spline_tool):_active_spline_tool.call("sharpen_all_points"))
        util_row.add_child(sm_btn); util_row.add_child(sh_btn); cs_sec.add_child(util_row)
        var del_btn:=Button.new(); del_btn.text="Delete Active Spline"
        del_btn.add_theme_color_override("font_color",C_ERROR)
        del_btn.pressed.connect(_on_delete_active_spline); cs_sec.add_child(del_btn)
        vb.add_child(_sep())
        var ts:=_section(vb,"2. Terrain Snapping")
        _info(ts,"Requires physics collision below the spline.")
        var drop_btn:=Button.new(); drop_btn.text="Drop to Ground (Keep Shape)"
        drop_btn.tooltip_text="Moves the whole spline down so the lowest point touches the floor."
        drop_btn.pressed.connect(func():
                if not is_instance_valid(_active_spline_tool): return
                var r:Dictionary = _active_spline_tool.call("snap_lowest_to_ground")
                if r.get("hit",0) == 0: set_status("No ground found below any point — check for missing collision.",C_WARN)
                elif r.get("hit",0) < r.get("total",0): set_status("Dropped to ground (%d/%d points found a surface)."%[r["hit"],r["total"]],C_WARN)
                else: set_status("Spline dropped to ground.",C_OK))
        ts.add_child(drop_btn)
        var conf_btn:=Button.new(); conf_btn.text="Wrap Points to Terrain"
        conf_btn.tooltip_text="Drops existing control points directly onto the collision surface."
        conf_btn.pressed.connect(func():
                if not is_instance_valid(_active_spline_tool): return
                var r:Dictionary = _active_spline_tool.call("conform_to_terrain")
                if r.get("hit",0) == 0: set_status("No ground found below any point — check for missing collision.",C_WARN)
                elif r.get("hit",0) < r.get("total",0): set_status("Wrapped to terrain (%d/%d points found a surface)."%[r["hit"],r["total"]],C_WARN)
                else: set_status("All points wrapped to terrain.",C_OK))
        ts.add_child(conf_btn)
        var conf2_btn:=Button.new(); conf2_btn.text="Subdivide & Wrap (Exact Shape)"
        conf2_btn.tooltip_text="Adds points every 1 meter and hugs hills and cliffs exactly."
        conf2_btn.pressed.connect(func(): if is_instance_valid(_active_spline_tool):_active_spline_tool.call("subdivide_and_conform")); ts.add_child(conf2_btn)
        vb.add_child(_sep())
        var lm:=_section(vb,"3. Layer Manager")
        var btn_row2:=HBoxContainer.new()
        var add_rep:=Button.new(); add_rep.text="+ Scatter (Props)"; add_rep.size_flags_horizontal=SIZE_EXPAND_FILL
        add_rep.pressed.connect(func(): _on_add_spline_layer(0)); btn_row2.add_child(add_rep)
        var add_str:=Button.new(); add_str.text="+ Deform (Roads)"; add_str.size_flags_horizontal=SIZE_EXPAND_FILL
        add_str.pressed.connect(func(): _on_add_spline_layer(1)); btn_row2.add_child(add_str); lm.add_child(btn_row2)
        var layer_vbox:=VBoxContainer.new(); layer_vbox.name="SplineLayerList"; lm.add_child(layer_vbox)
        vb.add_child(_sep())
        var uc:=_section(vb,"4. Bake to Scene",false)
        _info(uc,"Procedural Splines respawn objects if you delete them. To delete individual parts, you MUST BAKE the spline first!")
        var bake_btn:=Button.new(); bake_btn.text="BAKE TO NODES (Finalize)"
        bake_btn.custom_minimum_size=Vector2(0,int(40*_es)); bake_btn.add_theme_color_override("font_color",C_OK)
        bake_btn.pressed.connect(func():
                if is_instance_valid(_active_spline_tool):
                        _active_spline_tool.call("bake_to_nodes"); _active_spline_tool=null
                        _exit_spline_mode()
                        _rebuild_spline_layer_ui(); set_status("Spline baked! You can now edit or delete individual pieces.",C_OK))
        uc.add_child(bake_btn)
        var bake_mm_btn:=Button.new(); bake_mm_btn.text="BAKE TO MULTIMESH (Performance)"
        bake_mm_btn.custom_minimum_size=Vector2(0,int(40*_es)); bake_mm_btn.add_theme_color_override("font_color",C_ACCENT)
        bake_mm_btn.tooltip_text="Bakes scatter layers as MultiMeshInstance3D nodes instead of individual MeshInstance3D nodes. Ideal for grass, rocks, and any layer with many repeated instances. Deform layers are baked as a regular mesh."
        bake_mm_btn.pressed.connect(func():
                if is_instance_valid(_active_spline_tool):
                        _active_spline_tool.call("bake_to_multimesh"); _active_spline_tool=null
                        _exit_spline_mode()
                        _rebuild_spline_layer_ui(); set_status("Spline baked as MultiMesh! Scatter layers are now MultiMeshInstance3D for best performance.",C_ACCENT))
        uc.add_child(bake_mm_btn)

# ─── Spline Mode Helpers ──────────────────────────────────────────────────────
func _enter_spline_mode()->void:
        if place_mode != 4: _prev_place_mode = place_mode
        place_mode = 4
        _spline_mode_active = true
        _refresh_mode_buttons()
        if is_instance_valid(placer):
                # Defensive: guarantee no stale in-progress placement carries into
                # Spline mode. If _is_placing were left true, viewport clicks would
                # be intercepted before Godot's native Path3D curve-editing toolbar
                # ever saw them.
                placer.call("cancel_placement")
                placer.call("refresh_ghosts"); placer.call("rebuild_grid")
        on_placement_stopped()
        _update_spline_mode_label()

func _exit_spline_mode()->void:
        place_mode = _prev_place_mode
        _spline_mode_active = false
        _refresh_mode_buttons()
        if is_instance_valid(placer): placer.call("refresh_ghosts"); placer.call("rebuild_grid")
        _update_spline_mode_label()
        _save_config()

func _update_spline_mode_label()->void:
        if not is_instance_valid(_spline_mode_lbl): return
        if _spline_mode_active and is_instance_valid(_active_spline_tool):
                _spline_mode_lbl.text = "SPLINE MODE ACTIVE  —  %s\nViewport LMB clicks edit the curve. Press 'Exit Spline Mode' to resume normal placement." % _active_spline_tool.name
                _spline_mode_lbl.add_theme_color_override("font_color",C_OK)
                UAPIcons.set_texture_rect(_spline_status_icon,"status_dot_filled",C_OK)
        elif _spline_mode_active:
                _spline_mode_lbl.text = "Spline mode active but no spline node selected."
                _spline_mode_lbl.add_theme_color_override("font_color",C_WARN)
                UAPIcons.set_texture_rect(_spline_status_icon,"status_dot_filled",C_WARN)
        else:
                _spline_mode_lbl.text = "No spline active  —  Create or select a spline below."
                _spline_mode_lbl.add_theme_color_override("font_color",C_DIM)
                UAPIcons.set_texture_rect(_spline_status_icon,"status_dot_ring",C_DIM)

func _connect_spline_warnings(node:Node)->void:
        if not is_instance_valid(node): return
        if node.has_signal("build_warning") and not node.is_connected("build_warning", _on_spline_build_warning):
                node.connect("build_warning", _on_spline_build_warning)

func _on_spline_build_warning(message:String)->void:
        set_status(message, C_WARN)

func _on_create_spline_node()->void:
        var root:=EditorInterface.get_edited_scene_root()
        if root==null or not root is Node3D: set_status("Open a 3D scene first.",C_WARN); return
        var script:=load(_addon_root()+"uap_path.gd")
        if script==null: set_status("uap_path.gd not found.",C_ERROR); return
        var p3d:=Path3D.new()
        p3d.curve=Curve3D.new()
        # Assign a unique name BEFORE adding to tree to avoid Godot auto-naming (@NodeXXX)
        var base_name:="AdvancedSpline"; var candidate:=base_name; var n_idx:=1
        while (root as Node3D).has_node(candidate):
                n_idx+=1; candidate=base_name+"_%d"%n_idx
        p3d.name=candidate
        p3d.set_script(script)
        (root as Node3D).add_child(p3d); p3d.owner=root
        _active_spline_tool=p3d
        _connect_spline_warnings(_active_spline_tool)
        EditorInterface.get_selection().clear(); EditorInterface.get_selection().add_node(p3d)
        _enter_spline_mode()   # auto-activate mode 4 so the placer doesn't steal viewport clicks
        _rebuild_spline_layer_ui(); set_status("Advanced Spline created: "+p3d.name,C_OK)

func _delete_spline_node(node:Node)->void:
        if is_instance_valid(node): node.queue_free()
        if _active_spline_tool==node: _active_spline_tool=null
        _rebuild_spline_layer_ui()

func _on_select_existing_spline()->void:
        var sel:=EditorInterface.get_selection().get_selected_nodes()
        for n in sel:
                if n is Path3D and n.get_script()!=null:
                        _active_spline_tool=n
                        _connect_spline_warnings(_active_spline_tool)
                        _enter_spline_mode()   # auto-activate mode 4
                        _rebuild_spline_layer_ui()
                        set_status("Active spline: "+n.name,C_OK); return
        set_status("Select a Path3D with UAPSplineTool script.",C_WARN)

func _on_add_spline_layer(ltype:int)->void:
        if not is_instance_valid(_active_spline_tool): return
        if selected_path.is_empty(): return
        _active_spline_tool.call("add_layer",ltype,selected_path); _rebuild_spline_layer_ui()

func _on_remove_spline_layer(idx:int)->void:
        if not is_instance_valid(_active_spline_tool): return
        _active_spline_tool.call("remove_layer",idx); _rebuild_spline_layer_ui()

func _on_spline_force_rebuild()->void:
        if not is_instance_valid(_active_spline_tool): return
        _active_spline_tool.call("force_rebuild")

func _on_delete_active_spline()->void:
        if not is_instance_valid(_active_spline_tool): return
        var node:=_active_spline_tool; _active_spline_tool=null
        node.queue_free()
        _exit_spline_mode()
        _rebuild_spline_layer_ui()

func _rebuild_spline_layer_ui()->void:
        _update_spline_mode_label()
        if not is_instance_valid(_settings_tabs): return
        var sc:Node=null
        for i in _settings_tabs.get_child_count():
                if _settings_tabs.get_child(i).name=="Spline": sc=_settings_tabs.get_child(i); break
        if sc==null: return
        var llv:=_find_node_named("SplineLayerList",sc); if llv==null: return
        for c in llv.get_children(): llv.remove_child(c); c.queue_free()
        if not is_instance_valid(_active_spline_tool): return
        var count:int=_active_spline_tool.l_type.size()
        for i in count:
                var type=_active_spline_tool.l_type[i]
                var label="Scatter: " if type==0 else "Deform: "
                var sec:=_section(llv,label+str(_active_spline_tool.l_mesh[i].get_file().get_basename()),false)
                _row_chk("Add Collision on Bake",sec,bool(_active_spline_tool.l_col_bake[i]),
                        func(v:bool): _active_spline_tool.call("update_layer",i,"col_bake",v),
                        "Generates accurate Trimesh StaticBody collisions automatically when you press Bake.")
                sec.add_child(HSeparator.new())
                if type==0:
                        var mesh_row:=_row("Meshes",sec)
                        var mesh_edit:=LineEdit.new(); mesh_edit.text=_active_spline_tool.l_mesh[i]
                        mesh_edit.size_flags_horizontal=SIZE_EXPAND_FILL
                        mesh_edit.text_submitted.connect(func(t:String): _active_spline_tool.call("update_layer",i,"mesh",t))
                        mesh_row.add_child(mesh_edit)
                        var add_btn:=Button.new(); add_btn.text="+ Add Selected"
                        add_btn.pressed.connect(func():
                                if selected_path.is_empty(): set_status("Select an asset in the browser first.",C_WARN); return
                                var current=_active_spline_tool.l_mesh[i]
                                _active_spline_tool.call("update_layer",i,"mesh",current+", "+selected_path); _rebuild_spline_layer_ui())
                        mesh_row.add_child(add_btn)
                        var sr2:=_row("Spacing",sec)
                        var sv2:=_ss(0.1,100.0,float(_active_spline_tool.l_spacing[i]),0.1)
                        sv2.value_changed.connect(func(v:float): _active_spline_tool.call("update_layer",i,"spacing",v)); sr2.add_child(sv2)
                        _row_chk("Align to Curve",sec,bool(_active_spline_tool.l_align[i]),
                                func(v:bool): _active_spline_tool.call("update_layer",i,"align",v))
                        _row_chk("Use MultiMesh (Optimization)",sec,bool(_active_spline_tool.l_use_mm[i]),
                                func(v:bool): _active_spline_tool.call("update_layer",i,"use_mm",v),
                                "ON: Uses heavy optimization.\nOFF: Spawns individual mesh nodes so you can delete them before baking.")
                        var yr2:=_row("Rnd Yaw deg",sec)
                        var yv2:=_ss(0.0,180.0,float(_active_spline_tool.l_rnd_yaw[i]),1.0)
                        yv2.value_changed.connect(func(v:float): _active_spline_tool.call("update_layer",i,"rnd_yaw",v)); yr2.add_child(yv2)
                if type==1:
                        _row_chk("Invert Faces (Inside-Out)",sec,bool(_active_spline_tool.l_flip_faces[i]),
                                func(v:bool): _active_spline_tool.call("update_layer",i,"flip_faces",v),
                                "Check this if your road or track is facing backwards.")
                var scl_row:=_row("Scale X|Y|Z",sec)
                var scl=_active_spline_tool.l_scale[i] as Vector3
                var sx=_ss(0.01,10.0,scl.x,0.01); sx.value_changed.connect(func(v:float): _active_spline_tool.call("update_layer",i,"scale_x",v))
                var sy=_ss(0.01,10.0,scl.y,0.01); sy.value_changed.connect(func(v:float): _active_spline_tool.call("update_layer",i,"scale_y",v))
                var sz=_ss(0.01,10.0,scl.z,0.01); sz.value_changed.connect(func(v:float): _active_spline_tool.call("update_layer",i,"scale_z",v))
                scl_row.add_child(sx); scl_row.add_child(sy); scl_row.add_child(sz)
                var taper_row:=_row("Taper Start|End",sec)
                var tp_start:float=float(_active_spline_tool.l_scale_start[i]) if i<_active_spline_tool.l_scale_start.size() else 1.0
                var tp_end:float=float(_active_spline_tool.l_scale_end[i]) if i<_active_spline_tool.l_scale_end.size() else 1.0
                var ts=_ss(0.01,10.0,tp_start,0.01); ts.tooltip_text="Scale multiplier at the START of the curve (e.g. a fence post thicker at the base)."
                ts.value_changed.connect(func(v:float): _active_spline_tool.call("update_layer",i,"scale_start",v))
                var te=_ss(0.01,10.0,tp_end,0.01); te.tooltip_text="Scale multiplier at the END of the curve (e.g. a road narrowing toward one end)."
                te.value_changed.connect(func(v:float): _active_spline_tool.call("update_layer",i,"scale_end",v))
                taper_row.add_child(ts); taper_row.add_child(te)
                var twist_row:=_row("Twist deg",sec)
                var twist_val:float=float(_active_spline_tool.l_twist[i]) if i<_active_spline_tool.l_twist.size() else 0.0
                var tw=_ss(-3600.0,3600.0,twist_val,1.0); tw.tooltip_text="Total rotation (degrees) accumulated from the start to the end of the curve — a screw/rope-twist effect."
                tw.value_changed.connect(func(v:float): _active_spline_tool.call("update_layer",i,"twist",v))
                twist_row.add_child(tw)
                var off_row:=_row("Offset X|Y|Z",sec)
                var off=_active_spline_tool.l_offset[i] as Vector3
                var ox=_ss(-50.0,50.0,off.x,0.1); ox.value_changed.connect(func(v:float): _active_spline_tool.call("update_layer",i,"offset_x",v))
                var oy=_ss(-50.0,50.0,off.y,0.1); oy.value_changed.connect(func(v:float): _active_spline_tool.call("update_layer",i,"offset_y",v))
                var oz=_ss(-50.0,50.0,off.z,0.1); oz.value_changed.connect(func(v:float): _active_spline_tool.call("update_layer",i,"offset_z",v))
                off_row.add_child(ox); off_row.add_child(oy); off_row.add_child(oz)
                if type==1:
                        var uv_row:=_row("UV Tile X|Y",sec)
                        var uv=_active_spline_tool.l_uv_tile[i] as Vector2
                        var ux=_ss(0.01,50.0,uv.x,0.1); ux.value_changed.connect(func(v:float): _active_spline_tool.call("update_layer",i,"uv_x",v))
                        var uy=_ss(0.01,50.0,uv.y,0.1); uy.value_changed.connect(func(v:float): _active_spline_tool.call("update_layer",i,"uv_y",v))
                        uv_row.add_child(ux); uv_row.add_child(uy)
                var bot:=HBoxContainer.new()
                var rm:=Button.new(); rm.text="Remove Layer"
                rm.pressed.connect(func(): _active_spline_tool.call("remove_layer",i); _rebuild_spline_layer_ui()); bot.add_child(rm); sec.add_child(bot)

func _build_material_tab()->void:
        var vb:=_make_tab("Material", "tab_material")
        var mo:=_section(vb,"Material Override")
        _row_chk("Enable Override",mo,material_override_enabled,_on_mat_override_toggled,"Apply to all MeshInstances on place")
        var mr:=_row("Apply Mode",mo); _mat_mode_opt=OptionButton.new(); _mat_mode_opt.size_flags_horizontal=SIZE_EXPAND_FILL
        _mat_mode_opt.add_item("Replace"); _mat_mode_opt.add_item("Next Pass")
        _mat_mode_opt.selected=material_override_mode
        _mat_mode_opt.item_selected.connect(func(i:int):material_override_mode=i;_save_config()); mr.add_child(_mat_mode_opt)
        var mpr:=_row("Material",mo)
        _mat_path_lbl=Label.new(); _mat_path_lbl.text="(none)" if material_override_path.is_empty() else material_override_path.get_file()
        _mat_path_lbl.size_flags_horizontal=SIZE_EXPAND_FILL; _mat_path_lbl.add_theme_color_override("font_color",C_DIM); _mat_path_lbl.clip_text=true; mpr.add_child(_mat_path_lbl)
        var mpk:=Button.new(); mpk.text="Pick"; mpk.pressed.connect(_on_pick_material); mpr.add_child(mpk)
        var mcl:=Button.new(); mcl.text="X"; mcl.pressed.connect(_on_clear_material); mpr.add_child(mcl)

func _build_groups_tab()->void:
        var vb:=_make_tab("Groups", "tab_groups")
        var ar:=HBoxContainer.new(); ar.add_theme_constant_override("separation",4); vb.add_child(ar)
        var ne:=LineEdit.new(); ne.placeholder_text="New group name..."; ne.size_flags_horizontal=SIZE_EXPAND_FILL; ar.add_child(ne)
        var ab:=Button.new(); ab.text="+ Add"; ab.pressed.connect(_on_add_group.bind(ne)); ar.add_child(ab)
        # 2.5 rev 3: standalone panel-level action (not inside any section) —
        # raised 3D face so it never blends into the panel. Same rule that
        # fixed Start Physics: standalone + blends → raised, in-group → idle.
        _style_raised_button(ab,C_BTN_ACTION)
        vb.add_child(_sep())
        _group_list_vbox=VBoxContainer.new(); _group_list_vbox.size_flags_horizontal=SIZE_EXPAND_FILL
        _group_list_vbox.add_theme_constant_override("separation",3); vb.add_child(_group_list_vbox); _rebuild_group_list()
        vb.add_child(_sep())
        # ── Add selected asset to a group ────────────────────────────────────────────
        var ator:=VBoxContainer.new(); ator.size_flags_horizontal=SIZE_EXPAND_FILL
        ator.add_theme_constant_override("separation",3); vb.add_child(ator)
        var ar2:=HBoxContainer.new(); ar2.add_theme_constant_override("separation",4)
        ar2.size_flags_horizontal=SIZE_EXPAND_FILL; ator.add_child(ar2)
        var go:=OptionButton.new(); go.size_flags_horizontal=SIZE_EXPAND_FILL; go.name="GroupDrop"
        go.add_icon_item(UAPIcons.get_icon("feature_favorite"), "Favorites")
        for g in _groups: go.add_item((g as Dictionary)["name"])
        ar2.add_child(go); _group_drop=go
        var gb:=Button.new(); gb.text="Add"; gb.tooltip_text="Add the currently selected/multi-selected asset(s) to the group above."
        _style_raised_button(gb,C_BTN_ACTION)
        gb.pressed.connect(_on_add_to_group.bind(go)); ar2.add_child(gb)
        var gbr:=Button.new(); UAPIcons.set_button_icon(gbr,"action_browse")
        _style_raised_button(gbr,C_BTN_ACTION)
        gbr.tooltip_text="Import an entire folder of assets into the group above."
        gbr.pressed.connect(_on_import_folder_to_group.bind(go)); ar2.add_child(gbr)
        # ── Remove selected asset(s) from groups ─────────────────────────────────────
        # The remove system is smart: it detects which groups the selected asset(s) are
        # in automatically — no need to pick a group from a dropdown.
        # • When viewing a specific group: removes only from that group.
        # • When viewing All / Favorites / search: removes from every group they belong to.
        var rmr:=HBoxContainer.new(); rmr.add_theme_constant_override("separation",4)
        rmr.size_flags_horizontal=SIZE_EXPAND_FILL; ator.add_child(rmr)
        var rm_info:=Label.new(); rm_info.text="Remove selected:"
        rm_info.add_theme_color_override("font_color",C_DIM); rm_info.size_flags_horizontal=SIZE_EXPAND_FILL; rmr.add_child(rm_info)
        var rm_btn:=Button.new(); rm_btn.text="Remove from Group"
        # 2.5 rev 3: standalone destructive action → raised dark-red danger face
        # with crisp white text (replaces the old dim red-on-dark label).
        _style_raised_button(rm_btn,C_BTN_DANGER)
        rm_btn.tooltip_text="Removes selected asset(s) from the currently viewed group.\nIf viewing All or search, removes from every group they belong to.\nSupports multi-selection (Ctrl+Click / Shift+Click)."
        rm_btn.pressed.connect(_on_smart_remove_from_group); rmr.add_child(rm_btn)
        # 2.5: the multi-line Drag & Drop hint section was removed — same
        # reason as the Spline/Physics paragraphs: the per-tab "i" button and
        # the Docs window cover it, and the groups tab reads much tighter now.

func _on_smart_remove_from_group()->void:
        # Collect the paths to remove: multi-selected takes priority, then single selected.
        var targets:Array=[]
        if not _multi_selected.is_empty(): targets=_multi_selected.duplicate()
        elif not selected_path.is_empty(): targets=[selected_path]
        if targets.is_empty(): set_status("Select one or more assets first.",C_WARN); return

        var removed:int=0

        if _active_group==-2:
                # Viewing Favorites — remove from Favorites only.
                for p in targets:
                        if _favorite_paths.has(p): _favorite_paths.erase(p); removed+=1
        elif _active_group>=0 and _active_group<_groups.size():
                # Viewing a specific named group — remove only from that group.
                var gd:=_groups[_active_group] as Dictionary
                for p in targets:
                        if gd["paths"].has(p): gd["paths"].erase(p); removed+=1
        else:
                # Viewing All or search results — remove from every group the asset is
                # in, including Favorites (consistent with the tooltip's promise).
                for p in targets:
                        if _favorite_paths.has(p): _favorite_paths.erase(p); removed+=1
                for g in _groups:
                        for p in targets:
                                if (g as Dictionary)["paths"].has(p): (g as Dictionary)["paths"].erase(p); removed+=1

        if removed>0:
                _save_config(); _rebuild_group_list(); _rebuild_group_bar()
                # Refresh the browser so removed assets disappear when inside a group view.
                if _active_group != -1: _rebuild_browser_now()
                var noun:="asset" if targets.size()==1 else "assets"
                set_status("Removed %d %s from group(s)." % [targets.size(), noun], C_OK)
                if not _multi_selected.is_empty(): _clear_multi_select()
        else:
                set_status("Selected asset(s) are not in any group.",C_WARN)

func _on_import_folder_to_group(opt:OptionButton)->void:
        var dlg:=EditorFileDialog.new(); dlg.file_mode=EditorFileDialog.FILE_MODE_OPEN_DIR
        dlg.access=EditorFileDialog.ACCESS_RESOURCES
        dlg.dir_selected.connect(_do_import_folder_to_group.bind(opt.selected))
        add_child(dlg); dlg.popup_centered(Vector2i(700,500))

func _do_import_folder_to_group(dir:String,group_idx:int)->void:
        var new_paths:Array=[]; _collect_files(dir,new_paths)
        if new_paths.is_empty(): set_status("No supported assets found in that folder.",C_WARN); return
        var restored:=_unhide_paths(new_paths)
        var added:=0
        if group_idx==0:
                for p in new_paths:
                        if not _favorite_paths.has(p): _favorite_paths.append(p); added+=1
        elif group_idx-1<_groups.size():
                var gd:=_groups[group_idx-1] as Dictionary
                for p in new_paths:
                        if not gd["paths"].has(p): gd["paths"].append(p); added+=1
        var ba:=0
        for p in new_paths:
                if not _all_paths.has(p): _all_paths.append(p); ba+=1
        if ba>0 or restored>0: _rebuild_browser_now()
        _rebuild_group_list(); _rebuild_group_bar(); _save_config()
        if restored>0: set_status("Imported %d assets into group (%d restored from the removed list)."%[added,restored],C_OK)
        else: set_status("Imported %d assets into group."%added,C_OK)

func _build_keys_tab()->void:
        var vb:=_make_tab("Keys", "tab_keys")
        _key_capture_btns.clear()
        for action in SHORTCUT_LABELS.keys():
                var row:=_row(str(SHORTCUT_LABELS[action]),vb,130)
                var kbtn:=Button.new(); kbtn.size_flags_horizontal=SIZE_EXPAND_FILL
                kbtn.text=_keycode_to_display(shortcuts.get(action,KEY_NONE))
                var ac:=str(action); kbtn.pressed.connect(_on_capture_start.bind(ac))
                row.add_child(kbtn); _key_capture_btns[action]=kbtn
        vb.add_child(_sep())
        var rb:=Button.new(); rb.text="Reset All to Defaults"
        _style_raised_button(rb,C_BTN_ACTION)
        rb.size_flags_horizontal=SIZE_EXPAND_FILL; rb.pressed.connect(_on_reset_shortcuts); vb.add_child(rb)

func _build_collision_tab()->void:
        var vb:=_make_tab("Collision", "tab_collision")
        var col:=_section(vb,"Auto Collision")
        _row_chk("Enable on Place",col,collision_enabled,_on_col_enabled_changed)
        var body:=_section(vb,"Body Type")
        var bo:=OptionButton.new(); bo.size_flags_horizontal=SIZE_EXPAND_FILL
        for it in ["StaticBody3D","RigidBody3D","CharacterBody3D","Area3D"]: bo.add_item(it)
        bo.selected=collision_body_type; bo.item_selected.connect(_on_col_body_changed); body.add_child(bo)
        var shp:=_section(vb,"Shape Type")
        var so:=OptionButton.new(); so.size_flags_horizontal=SIZE_EXPAND_FILL
        for it in ["Trimesh","Convex Hull","Box","Sphere","Capsule"]: so.add_item(it)
        so.selected=collision_shape_type; so.item_selected.connect(_on_col_shape_changed); shp.add_child(so)
        _col_warn_lbl=Label.new(); _col_warn_lbl.text="Warning: Trimesh invalid for dynamic bodies."
        _col_warn_lbl.add_theme_color_override("font_color",C_WARN)
        _col_warn_lbl.visible=_col_warn_needed(); shp.add_child(_col_warn_lbl)
        var fbx:=_section(vb,"FBX / GLTF Options",false)
        _row_chk("Auto-Unpack",fbx,collision_auto_unpack,func(v:bool):collision_auto_unpack=v;_save_config())

func _col_warn_needed()->bool: return collision_shape_type==0 and collision_body_type in [1,2]

func _build_physics_tab()->void:
        var vb:=_make_tab("Physics", "tab_physics")
        # 2.5: the long "Drop already-placed objects…" description is gone —
        # the "i" button on this tab's header opens the Physics docs chapter.

        var status_row:=HBoxContainer.new(); status_row.add_theme_constant_override("separation",6)
        status_row.size_flags_horizontal=SIZE_EXPAND_FILL; vb.add_child(status_row)
        _phys_status_icon=TextureRect.new()
        _phys_status_icon.custom_minimum_size=Vector2(13,13)
        _phys_status_icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        _phys_status_icon.size_flags_vertical=SIZE_SHRINK_CENTER
        status_row.add_child(_phys_status_icon)
        _phys_status_lbl=Label.new()
        _phys_status_lbl.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
        _phys_status_lbl.size_flags_horizontal=SIZE_EXPAND_FILL
        status_row.add_child(_phys_status_lbl)

        var btn_row:=HBoxContainer.new(); btn_row.add_theme_constant_override("separation",4); vb.add_child(btn_row)
        _phys_start_btn=Button.new(); _phys_start_btn.text="Start Physics"; _phys_start_btn.size_flags_horizontal=SIZE_EXPAND_FILL
        UAPIcons.set_button_icon(_phys_start_btn,"action_bake")
        # 2.5: Start Physics is THE primary action of this tab, but it was
        # created bare and the global walker dressed it with the low-contrast
        # idle style — nearly the same color as the panel, so it didn't read
        # as a button at all. Give it a raised BLUE face (the same tactile
        # language as the active mode buttons): clearly visible against the
        # dark panel, unmistakably a button, still on-theme and NOT white.
        _style_raised_button(_phys_start_btn,C_BTN_ACTION)
        _phys_start_btn.tooltip_text="Simulate the currently selected object(s) falling and settling."
        _phys_start_btn.pressed.connect(func(): if is_instance_valid(physics_ctrl): physics_ctrl.call("start_simulation"))
        btn_row.add_child(_phys_start_btn)
        _phys_stop_btn=Button.new(); _phys_stop_btn.text="Stop"; _phys_stop_btn.size_flags_horizontal=SIZE_EXPAND_FILL
        UAPIcons.set_button_icon(_phys_stop_btn,"action_stop")
        # 2.5: while simulating, Stop/Cancel replace Start Physics in this row —
        # they get the same raised treatment so the whole row keeps its
        # unmistakable button look (amber = freeze, red = abort).
        _style_raised_button(_phys_stop_btn,C_BTN_STOP)
        _phys_stop_btn.tooltip_text="Freeze everything exactly where it is right now and remove any temporary collision."
        _phys_stop_btn.pressed.connect(func(): if is_instance_valid(physics_ctrl): physics_ctrl.call("stop_simulation"))
        btn_row.add_child(_phys_stop_btn)
        _phys_cancel_btn=Button.new(); _phys_cancel_btn.text="Cancel"; _phys_cancel_btn.size_flags_horizontal=SIZE_EXPAND_FILL
        UAPIcons.set_button_icon(_phys_cancel_btn,"action_reset")
        _style_raised_button(_phys_cancel_btn,C_BTN_DANGER)
        _phys_cancel_btn.tooltip_text="Abort and restore every object to where it was before this simulation started."
        _phys_cancel_btn.pressed.connect(func(): if is_instance_valid(physics_ctrl): physics_ctrl.call("cancel_simulation"))
        btn_row.add_child(_phys_cancel_btn)
        vb.add_child(_sep())

        var lift:=_section(vb,"Lift Selected")
        var lhr:=_row("Height",lift); var lh_spin:=_ss(0.1,200.0,phys_lift_height,0.1)
        lh_spin.value_changed.connect(func(v:float): phys_lift_height=v;_save_config()); lhr.add_child(lh_spin)
        var lml:=Label.new(); lml.text="m"; lml.add_theme_color_override("font_color",C_DIM); lhr.add_child(lml)
        _row_chk("Random Scatter",lift,phys_lift_scatter,func(v:bool):phys_lift_scatter=v;_save_config(),
                "Nudge each object sideways by a random amount so a lifted pile doesn't line up perfectly.")
        var lsr:=_row("Scatter Radius",lift); var ls_spin:=_ss(0.0,50.0,phys_lift_scatter_radius,0.1)
        ls_spin.value_changed.connect(func(v:float): phys_lift_scatter_radius=v;_save_config()); lsr.add_child(ls_spin)
        _row_chk("Random Rotation",lift,phys_lift_random_rot,func(v:bool):phys_lift_random_rot=v;_save_config(),
                "Randomize orientation on lift, so a dropped pile of debris doesn't look uniform.")
        var lift_btn:=Button.new(); lift_btn.text="Lift Selected Up"; lift_btn.size_flags_horizontal=SIZE_EXPAND_FILL
        UAPIcons.set_button_icon(lift_btn,"action_chevron_up")
        lift_btn.tooltip_text="Raise every selected object straight up by Height, ready to drop."
        lift_btn.pressed.connect(func(): if is_instance_valid(physics_ctrl): physics_ctrl.call("lift_selected"))
        lift.add_child(lift_btn)

        var sim:=_section(vb,"Simulation")
        var gr:=_row("Gravity",sim); var g_spin:=_ss(0.0,100.0,phys_gravity,0.1)
        g_spin.value_changed.connect(func(v:float): phys_gravity=v;_save_config()); gr.add_child(g_spin)
        var bn:=_row("Bounciness",sim); var b_spin:=_ss(0.0,1.0,phys_bounciness,0.01)
        b_spin.value_changed.connect(func(v:float): phys_bounciness=v;_save_config()); bn.add_child(b_spin)
        var fr:=_row("Friction",sim); var f_spin:=_ss(0.0,1.0,phys_friction,0.01)
        f_spin.value_changed.connect(func(v:float): phys_friction=v;_save_config()); fr.add_child(f_spin)
        _row_chk("Align to Ground",sim,phys_align_to_ground,func(v:bool):phys_align_to_ground=v;_save_config(),
                "Tilt each object to match the slope it lands on once it settles, same normal-alignment Surface mode uses.")
        _row_chk("Random Tumble",sim,phys_random_tumble,func(v:bool):phys_random_tumble=v;_save_config(),
                "Spin objects gently while they're airborne, for a less robotic-looking fall. Stops the moment they land.")
        var mfr:=_row("Max Fall Time",sim); var mf_spin:=_ss(1.0,120.0,phys_max_fall_time,1.0)
        mf_spin.value_changed.connect(func(v:float): phys_max_fall_time=v;_save_config()); mfr.add_child(mf_spin)
        var mfl:=Label.new(); mfl.text="s"; mfl.add_theme_color_override("font_color",C_DIM); mfr.add_child(mfl)
        _row_chk("Auto-Stop When Settled",sim,phys_auto_stop,func(v:bool):phys_auto_stop=v;_save_config(),
                "Automatically bake the result the moment every falling object has come to rest.")

        var col:=_section(vb,"Auto Collision (temporary)",false)
        _row_chk("Auto-Add Missing Collision",col,phys_auto_add_collision,func(v:bool):phys_auto_add_collision=v;_save_config(),
                "When ON, an object with no collision of its own gets a temporary shape for the duration of the simulation so it can land and be landed on, then it's removed. When OFF, such objects are skipped instead of getting anything added automatically. Objects that already have collision are always used exactly as they are and are never touched either way.")
        # 2.5: the long Auto Shape explanation paragraph was removed — the
        # OptionButton's per-item tooltips + the "i" button carry that info.
        var so:=OptionButton.new(); so.size_flags_horizontal=SIZE_EXPAND_FILL
        for it in ["Box","Sphere","Capsule","Convex Hull (Accurate)"]: so.add_item(it)
        so.selected=phys_auto_shape
        so.item_selected.connect(func(i:int): phys_auto_shape=i;_save_config())
        col.add_child(so)

        _update_phys_ui()

func on_physics_state_changed(_running:bool)->void:
        _update_phys_ui()

func _update_phys_ui()->void:
        if not is_instance_valid(_phys_status_lbl): return
        var running:=is_instance_valid(physics_ctrl) and bool(physics_ctrl.call("is_running"))
        if running:
                var prog:String=str(physics_ctrl.call("get_progress_text")) if is_instance_valid(physics_ctrl) else ""
                _phys_status_lbl.text="SIMULATING  —  %s\nStop to bake the result in place, or Cancel to abort." % prog
                _phys_status_lbl.add_theme_color_override("font_color",C_OK)
                UAPIcons.set_texture_rect(_phys_status_icon,"status_dot_filled",C_OK)
        else:
                _phys_status_lbl.text="Idle. Select object(s) in the viewport, then Lift and/or Start Physics."
                _phys_status_lbl.add_theme_color_override("font_color",C_DIM)
                UAPIcons.set_texture_rect(_phys_status_icon,"status_dot_ring",C_DIM)
        if is_instance_valid(_phys_start_btn): _phys_start_btn.visible = not running
        if is_instance_valid(_phys_stop_btn): _phys_stop_btn.visible = running
        if is_instance_valid(_phys_cancel_btn): _phys_cancel_btn.visible = running

# ─── Docs Window (2.1) ────────────────────────────────────────────────────────
## Docs no longer live in a tab. The rail's Docs button opens a dedicated,
## editor-centered window with a chapter sidebar on the left — click any
## chapter to jump straight to that section. Closing the window simply
## restores the rail highlight; the feature tab that was selected before is
## still the selected one (the window never touches _settings_tabs).
func _open_docs_window(chapter:int=0)->void:
        if _docs_window==null: _build_docs_window()
        if _docs_window==null: return
        _docs_was_open=true
        # The per-tab help ("i") buttons pass the chapter that matches the
        # currently-active tab; every other caller (rail Docs button) gets the
        # default 0 = the Welcome & Quick Start chapter.
        if _docs_rtl==null or _docs_rtl.get_parent()==null:
                _select_docs_chapter(_docs_cur_chapter)
        _docs_window.popup_centered(Vector2i(mini(int(1020*_es),int(get_viewport_rect().size.x*0.85)),mini(int(720*_es),int(get_viewport_rect().size.y*0.85))))
        if chapter>=0: _select_docs_chapter(chapter)
        if is_instance_valid(_rail_docs_btn):
                _rail_docs_btn.set_pressed_no_signal(true)
                _raise_rail_button(_rail_docs_btn)
        set_status("Docs opened in a separate window.",C_DIM)

func _close_docs_window()->void:
        _docs_was_open=false
        if is_instance_valid(_docs_window): _docs_window.hide()
        if is_instance_valid(_rail_docs_btn):
                _rail_docs_btn.set_pressed_no_signal(false)
                _dim_rail_button(_rail_docs_btn)
        # Restore the rail highlight to the feature tab that is currently
        # active — this is the tab that was selected before the docs window
        # was opened, because the window never changes _settings_tabs.
        _refresh_tab_rail()

func _build_docs_window()->void:
        var docs_script=load(_addon_root()+"uap_docs.gd")
        if docs_script==null or not docs_script.has_method("get_chapters"):
                push_warning("Ultimate Asset Placer: uap_docs.gd could not be loaded — docs window unavailable.")
                return
        _docs_window=Window.new()
        _docs_window.title="Ultimate Asset Placer — Documentation  (v%s)"%UAPIcons.get_plugin_version()
        _docs_window.min_size=Vector2i(int(720*_es),int(480*_es))
        _docs_window.close_requested.connect(_close_docs_window)
        add_child(_docs_window)
        # A Window does NOT auto-expand its children (unlike containers) — the
        # root panel must be anchored to the full content rect explicitly, and
        # it doubles as the dark backdrop for the whole window.
        var root_pc:=PanelContainer.new()
        root_pc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        var rps:=StyleBoxFlat.new(); rps.bg_color=Color(0.095,0.105,0.14)
        rps.set_content_margin_all(0)
        root_pc.add_theme_stylebox_override("panel",rps)
        _docs_window.add_child(root_pc)
        var margin:=MarginContainer.new()
        for s in ["margin_left","margin_right","margin_top","margin_bottom"]: margin.add_theme_constant_override(s,int(8*_es))
        root_pc.add_child(margin)
        var hb:=HBoxContainer.new(); hb.add_theme_constant_override("separation",int(10*_es))
        hb.size_flags_horizontal=SIZE_EXPAND_FILL; hb.size_flags_vertical=SIZE_EXPAND_FILL
        margin.add_child(hb)
        # ── Chapter sidebar (left) ──
        var side_pc:=PanelContainer.new(); side_pc.size_flags_vertical=SIZE_EXPAND_FILL
        var sps:=StyleBoxFlat.new(); sps.bg_color=Color(0.082,0.09,0.125); sps.set_corner_radius_all(4)
        sps.set_content_margin_all(int(5*_es)); side_pc.add_theme_stylebox_override("panel",sps)
        var side_sc:=ScrollContainer.new()
        side_sc.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
        side_sc.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO
        side_sc.size_flags_vertical=SIZE_EXPAND_FILL
        side_sc.custom_minimum_size=Vector2(int(190*_es),0)
        side_pc.add_child(side_sc)
        var side_vb:=VBoxContainer.new(); side_vb.size_flags_horizontal=SIZE_EXPAND_FILL
        side_vb.add_theme_constant_override("separation",int(3*_es)); side_sc.add_child(side_vb)
        var chapters:Array=docs_script.get_chapters()
        _docs_chapter_btns.clear()
        for i in chapters.size():
                var ch:Dictionary=chapters[i]
                var cb:=Button.new(); cb.toggle_mode=true
                cb.text="  "+str(ch["title"])
                cb.alignment=HORIZONTAL_ALIGNMENT_LEFT
                cb.size_flags_horizontal=SIZE_EXPAND_FILL
                cb.clip_text=true
                cb.focus_mode=Control.FOCUS_NONE
                cb.tooltip_text=str(ch["title"])
                UAPIcons.set_button_icon_sized(cb,str(ch["icon"]),maxi(12,int(16*_es)))
                cb.pressed.connect(_on_docs_chapter_pressed.bind(i))
                side_vb.add_child(cb); _docs_chapter_btns.append(cb)
        hb.add_child(side_pc)
        # ── Chapter content (right) ──
        var content_pc:=PanelContainer.new(); content_pc.size_flags_horizontal=SIZE_EXPAND_FILL
        content_pc.size_flags_vertical=SIZE_EXPAND_FILL
        var cps:=StyleBoxFlat.new(); cps.bg_color=Color(0.095,0.105,0.14); cps.set_corner_radius_all(4)
        cps.set_content_margin_all(int(10*_es)); content_pc.add_theme_stylebox_override("panel",cps)
        hb.add_child(content_pc)
        _docs_rtl=RichTextLabel.new()
        _docs_rtl.bbcode_enabled=true
        _docs_rtl.fit_content=false
        _docs_rtl.scroll_active=true
        _docs_rtl.size_flags_horizontal=SIZE_EXPAND_FILL
        _docs_rtl.size_flags_vertical=SIZE_EXPAND_FILL
        _docs_rtl.meta_underlined=true
        _docs_rtl.meta_clicked.connect(func(meta): OS.shell_open(str(meta)))
        # A native window does not inherit the editor theme — pin the text
        # colors so the body copy stays readable on the dark backdrop.
        _docs_rtl.add_theme_color_override("default_color",Color(0.82,0.85,0.92))
        _docs_rtl.add_theme_color_override("font_normal_color",Color(0.82,0.85,0.92))
        _docs_rtl.add_theme_color_override("font_bold_color",Color(0.93,0.96,1.0))
        _docs_rtl.add_theme_color_override("font_italic_color",Color(0.78,0.82,0.9))
        _docs_rtl.add_theme_color_override("font_selected_color",Color(1,1,1))
        content_pc.add_child(_docs_rtl)
        _select_docs_chapter(0)

func _on_docs_chapter_pressed(idx:int)->void:
        _select_docs_chapter(idx)

func _select_docs_chapter(idx:int)->void:
        if _docs_rtl==null: return
        var docs_script=load(_addon_root()+"uap_docs.gd")
        if docs_script==null or not docs_script.has_method("get_chapters"): return
        var chapters:Array=docs_script.get_chapters()
        if idx<0 or idx>=chapters.size(): idx=0
        _docs_cur_chapter=idx
        var ch:Dictionary=chapters[idx]
        var text:String=str(ch["text"])
        # The docs templates keep icon paths AND the version number as tokens so
        # they can never drift out of sync with the actual addon folder/version.
        text=text.replace("res://addons/ultimate_placer/icons/",UAPIcons.get_icon_dir())
        text=text.replace("{{VERSION}}",UAPIcons.get_plugin_version())
        _docs_rtl.text=text
        _docs_rtl.scroll_to_line(0)
        for i in _docs_chapter_btns.size():
                var btn:=_docs_chapter_btns[i] as Button
                if not is_instance_valid(btn): continue
                var active:bool=(i==idx)
                btn.set_pressed_no_signal(active)
                if active: _raise_rail_button(btn)
                else:
                        _apply_states(btn,_style_idle(),_style_idle_hover(),_style_idle_pressed())
                        btn.add_theme_color_override("icon_normal_color",Color(0.63,0.66,0.76))
                        btn.add_theme_color_override("icon_hover_color",Color(0.95,0.97,1.0))
                        btn.add_theme_color_override("icon_pressed_color",Color(1,1,1))
                        btn.add_theme_color_override("icon_hover_pressed_color",Color(1,1,1))
                        btn.add_theme_color_override("icon_focus_color",Color(0.95,0.97,1.0))


# ─── Mode/Scroll refresh ──────────────────────────────────────────────────────
func _on_mode_selected(idx:int)->void:
        place_mode=idx; _refresh_mode_buttons()
        if is_instance_valid(placer):
                placer.call("refresh_ghosts"); placer.call("rebuild_grid")
                if _is_placing and not selected_path.is_empty(): placer.call("start_placement",selected_path)
        _save_config()

func _on_scroll_mode_selected(idx:int)->void: scroll_mode=idx; _refresh_scroll_buttons(); _save_config()

func _refresh_mode_buttons()->void:
        # _mode_buttons array aligns with MODE_BUTTON_INDICES (no Spline button)
        for b_idx in _mode_buttons.size():
                var mode_idx:int = MODE_BUTTON_INDICES[b_idx] as int
                var btn:=_mode_buttons[b_idx] as Button; if not is_instance_valid(btn): continue
                btn.button_pressed=(mode_idx==place_mode)
                if mode_idx==place_mode:
                        # 3D tactile ACTIVE look: solid full-color face, darker
                        # bottom bevel, subtle drop shadow — no transparency,
                        # no outline ring.
                        var c:=MODE_COLORS[mode_idx] as Color
                        _apply_states(btn,_style_raised(c),_style_raised(c.lightened(0.08)),_style_raised(c))
                        _apply_raised_text(btn)
                else:
                        # Clean dark idle look: no white highlight.
                        _apply_states(btn,_style_idle(),_style_idle_hover(),_style_idle_pressed())
                        _clear_raised_text(btn)
                        btn.add_theme_color_override("font_color",Color(0.72,0.75,0.84))

func _refresh_scroll_buttons()->void:
        for i in _scroll_buttons.size():
                var btn:=_scroll_buttons[i] as Button; if not is_instance_valid(btn): continue
                btn.button_pressed=(i==scroll_mode)
                if i==scroll_mode:
                        # Active scroll target gets the same blue 3D tactile look.
                        # NOTE: this now includes "Off" (index 0) — every active
                        # state is highlighted, no exceptions.
                        _apply_states(btn,_style_raised(C_ACCENT),_style_raised(C_ACCENT.lightened(0.08)),_style_raised(C_ACCENT))
                        _apply_raised_text(btn)
                else:
                        _apply_states(btn,_style_idle(),_style_idle_hover(),_style_idle_pressed())
                        _clear_raised_text(btn)
                        btn.add_theme_color_override("font_color",Color(0.72,0.75,0.84))

# ─── Event Handlers ───────────────────────────────────────────────────────────
func _on_brush_radius_changed(v:float)->void:
        brush_radius=v; _save_config(); if is_instance_valid(placer):placer.call("set_brush_radius",v)

func _on_show_grid_changed(v:bool)->void: show_grid=v; if is_instance_valid(placer):placer.call("rebuild_grid"); _save_config()
func _on_grid_enabled_changed(v:bool)->void: grid_enabled=v; _save_config()
func _on_grid_size_changed(v:float)->void: grid_size=v; if is_instance_valid(placer):placer.call("rebuild_grid"); _save_config()
func _on_grid_h_changed(v:float)->void: grid_height=v; if is_instance_valid(placer):placer.call("rebuild_grid"); _save_config()
# 2.5 rev 7 — axis wall grid handlers (rebuild so the wall lines follow live).
func _on_x_grid_changed(v:bool)->void: x_grid_enabled=v; if is_instance_valid(placer):placer.call("rebuild_grid"); _save_config()
func _on_x_grid_size_changed(v:float)->void: x_grid_size=v; if is_instance_valid(placer):placer.call("rebuild_grid"); _save_config()
func _on_x_grid_pos_changed(v:float)->void: x_grid_pos=v; if is_instance_valid(placer):placer.call("rebuild_grid"); _save_config()
func _on_x_grid_cy_changed(v:float)->void: x_grid_cy=v; if is_instance_valid(placer):placer.call("rebuild_grid"); _save_config()
func _on_z_grid_changed(v:bool)->void: z_grid_enabled=v; if is_instance_valid(placer):placer.call("rebuild_grid"); _save_config()
func _on_z_grid_size_changed(v:float)->void: z_grid_size=v; if is_instance_valid(placer):placer.call("rebuild_grid"); _save_config()
func _on_z_grid_pos_changed(v:float)->void: z_grid_pos=v; if is_instance_valid(placer):placer.call("rebuild_grid"); _save_config()
func _on_z_grid_cy_changed(v:float)->void: z_grid_cy=v; if is_instance_valid(placer):placer.call("rebuild_grid"); _save_config()
func _on_grid_vd_changed(v:float)->void: grid_view_dist=v; if is_instance_valid(placer):placer.call("rebuild_grid"); _save_config()
func _on_grid_follow_changed(v:bool)->void: grid_follow=v; if is_instance_valid(placer):placer.call("rebuild_grid"); _save_config()
func _on_x_grid_follow_changed(v:bool)->void: x_grid_follow=v; if is_instance_valid(placer):placer.call("rebuild_grid"); _save_config()
func _on_z_grid_follow_changed(v:bool)->void: z_grid_follow=v; if is_instance_valid(placer):placer.call("rebuild_grid"); _save_config()
func _on_height_changed(v:float)->void: height_offset=v; _save_config()
func _on_height_snap_changed(v:bool)->void: height_snap=v; _save_config()
func _on_align_normal_changed(v:bool)->void: align_to_normal=v; _save_config(); if is_instance_valid(placer):placer.call("refresh_ghosts")
func _on_vertex_mesh_changed(v:bool)->void: vertex_snap_mesh=v; _save_config()
func _on_paint_changed(v:bool)->void: paint_mode=v; _save_config(); if is_instance_valid(placer):placer.call("refresh_ghosts")
func _on_multimesh_toggled(v:bool)->void: multimesh_mode=v; if not v and is_instance_valid(placer):placer.call("mm_commit_to_scene"); _save_config()
func _on_mm_clear()->void: if is_instance_valid(placer):placer.call("mm_clear"); set_status("MultiMesh cleared.",C_WARN)
func _on_mm_generate_collision()->void: if is_instance_valid(placer):placer.call("mm_generate_collision")
func _on_pick_parent()->void:
        var nodes:=EditorInterface.get_selection().get_selected_nodes()
        if nodes.is_empty(): set_status("Select a Node3D first.",C_WARN); return
        var n:=nodes[0] as Node; if not n is Node3D: set_status("Parent must be a Node3D.",C_WARN); return
        var root:=EditorInterface.get_edited_scene_root(); if n==root: _on_clear_parent(); return
        parent_node=n; parent_path=str(root.get_path_to(n))
        if is_instance_valid(_parent_edit): _parent_edit.text=n.name
        set_status("Parent: "+n.name,C_OK); _save_config()
func _on_clear_parent()->void:
        parent_node=null; parent_path=""
        if is_instance_valid(_parent_edit): _parent_edit.text=""; _parent_edit.placeholder_text="(scene root)"
        set_status("Parent cleared.",C_DIM); _save_config()
func _on_rot_mode_changed(idx:int)->void: rotation_snap_mode=idx; if is_instance_valid(_custom_row):_custom_row.visible=(idx==4); _save_config()
func _on_custom_deg_changed(v:float)->void: custom_snap_deg=v; _save_config()
func _on_random_rot_changed(v:bool)->void: random_rot=v; _save_config()
func _on_random_scale_changed(v:bool)->void: random_scale=v; _save_config()
func _on_rot_x_changed(v:float)->void:
        if is_instance_valid(placer): placer.call("set_rotation",v,_rot_y_spin.value if is_instance_valid(_rot_y_spin) else 0.0,_rot_z_spin.value if is_instance_valid(_rot_z_spin) else 0.0)
func _on_rot_y_changed(v:float)->void:
        if is_instance_valid(placer): placer.call("set_rotation",_rot_x_spin.value if is_instance_valid(_rot_x_spin) else 0.0,v,_rot_z_spin.value if is_instance_valid(_rot_z_spin) else 0.0)
func _on_rot_z_changed(v:float)->void:
        if is_instance_valid(placer): placer.call("set_rotation",_rot_x_spin.value if is_instance_valid(_rot_x_spin) else 0.0,_rot_y_spin.value if is_instance_valid(_rot_y_spin) else 0.0,v)
func _on_uniform_toggled(v:bool)->void:
        uniform_scale=v; if is_instance_valid(_uni_scale_row):_uni_scale_row.visible=v
        if is_instance_valid(_xyz_box):_xyz_box.visible=not v; _save_config()
func _on_scale_all_changed(v:float)->void: place_scale_all=v;place_scale_x=v;place_scale_y=v;place_scale_z=v;_save_config()
func _on_scale_x_changed(v:float)->void: place_scale_x=v;_save_config()
func _on_scale_y_changed(v:float)->void: place_scale_y=v;_save_config()
func _on_scale_z_changed(v:float)->void: place_scale_z=v;_save_config()
func _on_mat_override_toggled(v:bool)->void: material_override_enabled=v;_save_config()
func _on_pick_material()->void:
        var dlg:=EditorFileDialog.new(); dlg.file_mode=EditorFileDialog.FILE_MODE_OPEN_FILE
        dlg.access=EditorFileDialog.ACCESS_RESOURCES
        dlg.filters=PackedStringArray(["*.tres ; Material Resource","*.res ; Binary Resource"])
        dlg.file_selected.connect(_on_material_chosen); add_child(dlg); dlg.popup_centered(Vector2i(700,500))
func _on_material_chosen(path:String)->void:
        material_override_path=path; if is_instance_valid(_mat_path_lbl):_mat_path_lbl.text=path.get_file(); _save_config()
func _on_clear_material()->void:
        material_override_path=""; if is_instance_valid(_mat_path_lbl):_mat_path_lbl.text="(none)"; _save_config()
func _on_capture_start(action:String)->void:
        if not _capturing_action.is_empty():
                var ob:=_key_capture_btns.get(_capturing_action) as Button
                if is_instance_valid(ob): ob.text=_keycode_to_display(shortcuts.get(_capturing_action,KEY_NONE)); ob.remove_theme_color_override("font_color")
        _capturing_action=action
        var btn:=_key_capture_btns.get(action) as Button
        if is_instance_valid(btn): btn.text="[ press any key... ]"; btn.add_theme_color_override("font_color",C_WARN)
func _keycode_to_display(kc:int)->String: return "(none)" if kc==KEY_NONE or kc==0 else OS.get_keycode_string(kc)
func _on_reset_shortcuts()->void:
        shortcuts={"rotate_y":KEY_R,"rotate_x":KEY_E,"rotate_z":KEY_Q,"scale_up":KEY_BRACKETRIGHT,
                "scale_down":KEY_BRACKETLEFT,"height_up":KEY_PAGEUP,"height_down":KEY_PAGEDOWN,
                "layer_up":KEY_HOME,"layer_down":KEY_END,"flip_x":KEY_G,"flip_z":KEY_B,"reset_rot":KEY_T}
        _capturing_action=""
        for action in _key_capture_btns.keys():
                var btn:=_key_capture_btns[action] as Button
                if is_instance_valid(btn): btn.text=_keycode_to_display(shortcuts.get(action,KEY_NONE)); btn.remove_theme_color_override("font_color")
        _save_config()
func _on_col_enabled_changed(v:bool)->void: collision_enabled=v;_save_config()
func _on_col_body_changed(idx:int)->void: collision_body_type=idx; if is_instance_valid(_col_warn_lbl):_col_warn_lbl.visible=_col_warn_needed();_save_config()
func _on_col_shape_changed(idx:int)->void: collision_shape_type=idx; if is_instance_valid(_col_warn_lbl):_col_warn_lbl.visible=_col_warn_needed();_save_config()
func _on_folder_submitted(text:String)->void: current_folder=text;_save_config();_scan_folder()
func _on_browse_pressed()->void:
        var dlg:=EditorFileDialog.new(); dlg.file_mode=EditorFileDialog.FILE_MODE_OPEN_DIR
        dlg.access=EditorFileDialog.ACCESS_RESOURCES; dlg.dir_selected.connect(_on_dir_chosen)
        add_child(dlg); dlg.popup_centered(Vector2i(700,500))
func _on_dir_chosen(dir:String)->void:
        _is_scanning=false; _scan_dir_queue.clear()
        current_folder=dir; if is_instance_valid(_folder_edit):_folder_edit.text=dir; _save_config(); _scan_folder()
func _on_search_changed(text:String)->void: current_page=0; _rebuild_browser(text)

func _scan_folder()->void:
        _is_scanning=false; _scan_dir_queue.clear()
        _all_paths.clear(); _build_queue.clear()
        _thumb_pending.clear(); _ir_path_map.clear(); _card_ir_map.clear(); _card_fav_btn_map.clear()
        _thumb_retry_queue.clear(); _thumb_perm_failed.clear(); _thumb_heavy_count=0
        _scan_dir_queue=[current_folder]; _is_scanning=true; set_status("Scanning...",C_DIM)

func _on_clear_browser()->void:
        if is_instance_valid(placer):placer.call("cancel_placement")
        _is_scanning=false; _scan_dir_queue.clear()
        _all_paths.clear(); _build_queue.clear()
        _thumb_pending.clear(); _thumb_cache.clear(); _thumb_lru.clear()
        _ir_path_map.clear(); _card_ir_map.clear(); _card_fav_btn_map.clear()
        _thumb_retry_queue.clear(); _thumb_perm_failed.clear(); _thumb_heavy_count=0
        if is_instance_valid(_search_edit): _search_edit.text=""
        _rebuild_browser(""); set_status("Browser cleared.",C_DIM); _save_config()

func _unhide_paths(paths:Array)->int:
        ## 2.5 rev 8 bugfix — assets removed via right-click "Remove from list"
        ## live in _hidden_paths, which is filtered out of EVERY browser view and
        ## every rescan. Any explicit re-add gesture (drag & drop from the
        ## FileSystem dock, folder import, extra-path merge) must also lift that
        ## flag, otherwise the asset would silently stay invisible forever no
        ## matter how often the user re-added it. Returns how many were restored.
        var n:=0
        for p in paths:
                if _hidden_paths.has(p): _hidden_paths.erase(p); n+=1
        return n

func _merge_extra_paths(extras:Array)->void:
        _unhide_paths(extras)
        for p in extras:
                if ResourceLoader.exists(p) and not _all_paths.has(p): _all_paths.append(p)
        if not extras.is_empty(): _rebuild_browser_now()

func _collect_files(folder:String,out:Array)->void:
        var da:=DirAccess.open(folder); if da==null: return
        da.list_dir_begin(); var fn:=da.get_next()
        while fn!="":
                if not fn.begins_with("."):
                        var full:=folder.path_join(fn)
                        if da.current_is_dir():
                                if fn not in SKIP_DIRS: _collect_files(full,out)
                        elif fn.get_extension().to_lower() in import_formats: out.append(full)
                fn=da.get_next()
        da.list_dir_end()

const _DRAG_EXTS:=["glb","gltf","fbx","obj","dae","blend","tscn","scn","res","mesh"]

func _can_drop_asset_files(_at:Vector2,data:Variant)->bool:
        if not data is Dictionary or not (data as Dictionary).has("files"): return false
        for f in (data as Dictionary)["files"] as Array:
                if (f as String).get_extension().to_lower() in _DRAG_EXTS: return true
        return false

func _drop_asset_files(_at:Vector2,data:Variant)->void:
        if not data is Dictionary: return
        var files:=(data as Dictionary).get("files",[]) as Array
        var globally_added:=0      # files newly added to the global _all_paths list
        var group_added:=0         # files newly added to the active group
        var group_paths:Array=[]   # files eligible to add to the active group

        for f in files:
                var fs:=f as String
                if not fs.get_extension().to_lower() in _DRAG_EXTS: continue
                # Always collect for potential group membership regardless of global presence.
                group_paths.append(fs)
                if not _all_paths.has(fs):
                        _all_paths.append(fs); globally_added+=1
        # 2.5 rev 8 bugfix — dropping an asset back in is an explicit "I want this
        # back" gesture: lift the right-click "Remove from list" hidden flag so
        # the rebuilt browser actually shows the card again.
        var restored:=_unhide_paths(group_paths)

        # Add to active group — this runs even for files already in _all_paths.
        if _active_group==-2:
                for p in group_paths:
                        if not _favorite_paths.has(p): _favorite_paths.append(p); group_added+=1
        elif _active_group>=0 and _active_group<_groups.size():
                var gd:=_groups[_active_group] as Dictionary
                for p in group_paths:
                        if not gd["paths"].has(p): gd["paths"].append(p); group_added+=1

        var total:=maxi(globally_added, group_added)
        if total>0 or group_added>0 or restored>0:
                var filter:=_search_edit.text if is_instance_valid(_search_edit) else ""
                _rebuild_browser(filter); _rebuild_group_list(); _rebuild_group_bar()
                _save_config()
                var suffix:="" if restored==0 else " (%d restored)"%restored
                if group_added>0 and globally_added==0:
                        set_status("Added %d asset(s) to group."%group_added+suffix, C_OK)
                elif group_added>0:
                        set_status("Added %d asset(s) to browser and group."%group_added+suffix, C_OK)
                else:
                        set_status("Added %d asset(s) to browser."%globally_added+suffix, C_OK)
        elif not group_paths.is_empty():
                if restored>0: set_status("Restored %d asset(s) that were removed from the list."%restored,C_OK)
                else: set_status("Asset(s) already in the current group.",C_DIM)

func _prev_page()->void:
        if current_page>0: current_page-=1; _rebuild_browser_now()

func _next_page()->void:
        var total_pages=int(max(1,ceil(_visible_paths_filtered.size()/float(items_per_page))))
        if current_page<total_pages-1: current_page+=1; _rebuild_browser_now()

func _rebuild_browser_now()->void:
        _rebuild_browser(_search_edit.text if is_instance_valid(_search_edit) else "")

func _rebuild_browser(filter:String)->void:
        if not is_instance_valid(_asset_grid): return
        # Increment generation — all in-flight thumbnail callbacks from the previous
        # browser layout will see a mismatched generation and discard themselves safely.
        _browser_generation += 1
        _build_queue.clear(); _thumb_pending.clear(); _thumb_retry_queue.clear()
        _thumb_check_timer=THUMB_INTERVAL; _thumb_heavy_count=0
        # Clear offline renderer queue — paths from the old page are no longer visible
        _thumb_gen_ir_map.clear()
        if _thumb_gen != null: _thumb_gen.clear_queue()
        for c in _asset_grid.get_children(): _asset_grid.remove_child(c); c.queue_free()
        _card_map.clear(); _card_ir_map.clear(); _ir_path_map.clear(); _card_fav_btn_map.clear()
        _selected_path_ui=""
        _visible_paths_filtered=_filtered_paths(filter)
        var total_pages=int(max(1,ceil(_visible_paths_filtered.size()/float(items_per_page))))
        current_page=clampi(current_page,0,total_pages-1)
        var start_idx=current_page*items_per_page
        var end_idx=mini(start_idx+items_per_page,_visible_paths_filtered.size())
        _visible_paths_ordered=_visible_paths_filtered.slice(start_idx,end_idx)
        if is_instance_valid(_page_lbl): _page_lbl.text="Page %d/%d"%[(current_page+1),total_pages]
        _build_queue=_visible_paths_ordered.duplicate()
        call_deferred("_update_columns")

func _filtered_paths(filter:String)->Array:
        var base:Array = _all_paths if _active_group==-1 else _paths_for_active_group()
        # Format filter, applied regardless of view. "All" already got this for
        # free (import_formats gates what _scan_one_dir() puts into _all_paths,
        # and every checkbox toggle triggers a rescan) — but a named group or
        # Favorites is a persisted, hand-curated path list that is NEVER
        # rescanned on toggle, so without this it silently ignored the format
        # checkboxes entirely. Filtering here is non-destructive: it only
        # affects what's displayed, not the group's actual stored membership, so
        # toggling a format back on immediately reveals matching items again
        # instead of requiring them to be re-added.
        base=base.filter(func(p): return (p as String).get_extension().to_lower() in import_formats)
        # Assets removed via the card context menu stay out of every view
        # (including group views) until explicitly restored.
        base=base.filter(func(p): return not _hidden_paths.has(p))
        if filter.strip_edges().is_empty(): return base
        var lf:=filter.to_lower(); var result:Array=[]
        for p in base:
                if (p as String).get_file().to_lower().contains(lf): result.append(p)
        return result

func _card_thumb_metrics(S:int)->Vector2i:
        ## THE single source of truth for the thumbnail well's pixel size at a
        ## given card size. Used by _add_card to build the well AND pushed into
        ## the thumbnail generator (set_preview_metrics) so every thumbnail is
        ## RENDERED at exactly the well's aspect ratio and ~1.5x its resolution
        ## — that is what makes textures fill the well edge-to-edge with no
        ## black bars at any preview size.
        var pad:int=maxi(3,int(4*_es))          # inner padding inside the card
        var lbl_h:int=maxi(14,int(17*_es))      # name row height
        var sep:int=maxi(2,int(3*_es))          # gap thumb↔name
        return Vector2i(S-2*pad, S-2*pad-lbl_h-sep)

func _add_card(path:String)->void:
        # ── 2.2 square card design ────────────────────────────────────────────
        # Cards are now perfectly SQUARE cells: a landscape (rectangular)
        # thumbnail area on top + the asset name inside the card at the
        # bottom. This replaces the old portrait card (square thumb + name
        # hanging below) that overflowed the grid slot and looked cluttered.
        #
        # Cards still live inside a plain Control wrapper, not directly in
        # _asset_grid. Reason (verified with an isolated repro in 2.1):
        # `card` is a PanelContainer, and Godot's Container base class
        # force-resizes EVERY direct child Control to fill its own content
        # rect on every layout pass — silently overriding any manually-set
        # anchors/position/size on that child. That's what made the favorite
        # star's clickable rect cover the whole card. `wrapper` is a plain
        # Control (not a Container), so the star can sit as a sibling with
        # its own small rect and actually stick.
        var S:int=_preview_size
        var pad:int=maxi(3,int(4*_es))          # inner padding inside the card
        var sep:int=maxi(2,int(3*_es))          # gap thumb↔name
        var lbl_h:int=maxi(14,int(17*_es))      # name row height
        var inner_w:int=S-2*pad
        var thumb_h:int=S-2*pad-lbl_h-sep       # exact square budget: no overflow
        var wrapper:=Control.new()
        wrapper.custom_minimum_size=Vector2(S,S)   # SQUARE cell
        wrapper.mouse_filter=Control.MOUSE_FILTER_IGNORE
        var card:=PanelContainer.new()
        card.set_anchors_preset(Control.PRESET_FULL_RECT)
        card.mouse_filter=Control.MOUSE_FILTER_STOP
        # 2.4 resting card face: dark INSET 3D — the same carved treatment as
        # the group chips/rows: fill clearly darker than the panel, single
        # darker line along the bottom edge, no border anywhere else. The
        # helper bakes the same content margins (pad) that every state
        # stylebox now carries, so the layout never shifts on select/deselect.
        var normal_style:=_card_select_stylebox(false)
        card.add_theme_stylebox_override("panel",normal_style)
        var vb:=VBoxContainer.new(); vb.add_theme_constant_override("separation",sep)
        vb.mouse_filter=Control.MOUSE_FILTER_IGNORE; card.add_child(vb)
        # Thumbnail well: a slightly darker rectangular surface (same carved
        # language as the groups) that gives the landscape thumbnail a crisp
        # frame. Thumbnails are GENERATED at exactly this well's aspect ratio
        # (see _card_thumb_metrics + set_preview_metrics), so the texture
        # fills it edge-to-edge — no bars, no cropping.
        var well:=PanelContainer.new()
        var wsb:=StyleBoxFlat.new(); wsb.bg_color=C_WELL_BG; wsb.set_corner_radius_all(3)
        wsb.set_content_margin_all(0)
        well.add_theme_stylebox_override("panel",wsb)
        well.size_flags_horizontal=SIZE_EXPAND_FILL
        # 2.5: the thumbnail can NEVER spill out of the well again — no matter
        # what a texture or stretch mode does, drawing is clipped to the well
        # rect ("thumbnails coming on top of the cards" report).
        well.clip_contents=true
        # 2.3 CRITICAL: the well is a PanelContainer, which STOPS mouse events
        # by default — clicks on the thumbnail were being eaten here and never
        # reached the card's gui_input (that's why only clicking the title
        # selected a card). IGNORE lets the click fall through to the card
        # itself, so the ENTIRE card is clickable: thumbnail, name, padding.
        well.mouse_filter=Control.MOUSE_FILTER_IGNORE
        # rev 4: the well spans the card's FULL inner width again. (2.5 rev 1-3
        # stopped it one pad short of the right edge to reserve a star zone for
        # the half-outside "corner badge" star — that design is gone: the star
        # now sits fully inside ON the thumbnail's top-right corner, exactly
        # like the user's green-check mockup.)
        vb.add_child(well)
        # The well is remembered on the card so _card_apply_state() can tint it
        # blue/amber together with the card face (see 2.3 selection design).
        card.set_meta("uap_well",well)
        var thumb_w:int=inner_w   # rev 4: full inner width (no star-zone reserve)
        var ir:=TextureRect.new(); ir.custom_minimum_size=Vector2(thumb_w,thumb_h)
        ir.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
        ir.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
        # 2.5: belt-and-suspenders for the same overflow report — even if a
        # future stretch mode ever draws beyond the TextureRect's bounds, the
        # texture is clipped to them and can never sit "on top of the card".
        ir.clip_contents=true
        ir.mouse_filter=Control.MOUSE_FILTER_IGNORE; well.add_child(ir)
        ir.set_meta("uap_path",path)
        _card_ir_map[path]=ir; _ir_path_map[ir.get_instance_id()]=path
        if _thumb_cache.has(path): _card_apply_texture(ir,_thumb_cache[path] as Texture2D)
        else:
                var fb:=_fallback_icon(path); if fb!=null: _card_apply_texture(ir,fb)
        var nl:=Label.new(); nl.text=path.get_file().get_basename(); nl.clip_text=true
        nl.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
        nl.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
        nl.add_theme_font_size_override("font_size",maxi(10,int(11*_es)))
        # 2.4 name: near-white text with a black outline — ASSET BROWSER CARD
        # NAMES ONLY. Every other label/button in the plugin keeps its plain
        # look (the 2.2 pass removed outlines everywhere else on purpose).
        nl.add_theme_color_override("font_color",Color(0.93,0.95,1.0))
        nl.add_theme_color_override("font_outline_color",Color(0,0,0,1))
        nl.add_theme_constant_override("outline_size",maxi(2,int(3*_es)))
        # CRITICAL (verified by probe): the ambient editor theme's Label
        # "normal" stylebox carries content margins that INFLATE the label's
        # minimum size (name row measured 24px tall instead of the budgeted
        # 17 — silently overflowing the square card). A zero-margin
        # StyleBoxEmpty makes min size = pure text, so the square card budget
        # math (lbl_h) is exact. Same lesson as the star button in 2.1.
        nl.add_theme_stylebox_override("normal",StyleBoxEmpty.new())
        nl.custom_minimum_size=Vector2(0,lbl_h)
        nl.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
        nl.mouse_filter=Control.MOUSE_FILTER_IGNORE; vb.add_child(nl)
        card.tooltip_text=path
        var ext2:=path.get_extension().to_lower()
        if (ext2=="tscn" or ext2=="scn"):
                var opened_root:=EditorInterface.get_edited_scene_root()
                if is_instance_valid(opened_root) and opened_root.scene_file_path==path:
                        # 2.4: same inset language as the resting card, but with
                        # a warm dark fill so the open state still pops; the
                        # "Opened" chip on the thumbnail (below) now carries the
                        # open signal — the name stays uniform white/outline.
                        var open_style:=StyleBoxFlat.new()
                        open_style.bg_color=Color(0.216,0.118,0.048)
                        open_style.set_corner_radius_all(5)
                        open_style.border_width_bottom=maxi(2,int(2*_es))
                        open_style.border_color=Color(0.082,0.042,0.016)
                        open_style.content_margin_left=pad; open_style.content_margin_right=pad
                        open_style.content_margin_top=pad;  open_style.content_margin_bottom=pad
                        card.add_theme_stylebox_override("panel",open_style)
                        card.tooltip_text=path+"\nCurrently open — cannot place inside itself."
                        # "Opened" chip pinned to the THUMBNAIL's bottom-left
                        # corner (user request). It is a child of the
                        # TextureRect — a plain Control, not a Container — so
                        # its anchors/offsets are deterministic and the square
                        # card budget is untouched.
                        var chip:=Label.new(); chip.text="Opened"
                        chip.mouse_filter=Control.MOUSE_FILTER_IGNORE
                        var chip_h:=maxi(11,int(13*_es))
                        chip.anchor_left=0.0; chip.anchor_right=0.0
                        chip.anchor_top=1.0;  chip.anchor_bottom=1.0
                        chip.offset_left=int(3*_es)
                        chip.offset_right=chip.offset_left+maxi(40,int(46*_es))
                        chip.offset_bottom=-int(2*_es)
                        chip.offset_top=chip.offset_bottom-chip_h
                        chip.horizontal_alignment=HORIZONTAL_ALIGNMENT_LEFT
                        chip.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
                        chip.add_theme_font_size_override("font_size",maxi(8,int(9*_es)))
                        chip.add_theme_color_override("font_color",C_WARN)
                        chip.add_theme_color_override("font_outline_color",Color(0,0,0,1))
                        chip.add_theme_constant_override("outline_size",maxi(2,int(2*_es)))
                        # Zero-margin stylebox: without it the ambient editor
                        # theme inflates the label's minimum size far beyond
                        # the 13px chip rect and the chip spills out of the
                        # thumbnail (confirmed by probe + harness).
                        chip.add_theme_stylebox_override("normal",StyleBoxEmpty.new())
                        ir.add_child(chip)
        if _multi_selected.has(path):
                _card_apply_state(card,2)
        wrapper.add_child(card)
        # Favorite star: a SIBLING of `card` inside `wrapper`, not a child of
        # `card` — see the comment at the top of this function for why.
        # rev 4 star placement — FINAL design taken literally from the user's
        # green-check mockup: the star is pinned ON the THUMBNAIL's top-right
        # corner, fully INSIDE the card. Its top edge lines up with the well's
        # top edge and its right edge with the well's right edge (both are
        # `pad` inside the card's edges, because the card's stylebox content
        # margin is the same `pad` on every side) — so the star sits exactly
        # on the thumbnail's corner, never overflows the card, and never
        # floats in the gap between cards (the red-X complaint). It overlaps
        # the thumbnail's corner on purpose; legibility over any thumbnail is
        # handled by the dark outline baked into the texture via
        # UAPIcons.get_icon_outlined().
        #
        # CONTROL TYPE — TextureButton, not Button (kept from 2.5): a (flat,
        # icon-only, StyleBoxEmpty-overridden) Button still inherits the
        # editor theme's Button minimum size (measured 32x28 at es=1 in the
        # 4.7.1 editor). Godot grows the control to its minimum size in the
        # END direction, so the 16px button silently became a 32x28 rect
        # starting at its offset position — the ICON drew left-aligned inside
        # that oversized rect, i.e. several px off the intended corner. That
        # was the real root cause of "the star position is wrong" in every
        # earlier round. TextureButton has no text, no font, no styleboxes:
        # with ignore_texture_size its minimum size is ZERO — the offsets
        # below are therefore the final rect, pixel-exact, on every theme.
        var fav_btn:=TextureButton.new()
        var fav_size:=maxi(12,int(16*_es))
        var fav_m:int=pad   # same inset as the card padding → well's corner
        fav_btn.ignore_texture_size=true          # min size = 0: rect == offsets
        fav_btn.stretch_mode=TextureButton.STRETCH_SCALE
        fav_btn.anchor_left=1.0; fav_btn.anchor_right=1.0
        fav_btn.anchor_top=0.0;  fav_btn.anchor_bottom=0.0
        fav_btn.offset_left=-(fav_m+fav_size)     # fully inside the card
        fav_btn.offset_right=-fav_m               # right edge == well's right edge
        fav_btn.offset_top=fav_m                  # top edge    == well's top edge
        fav_btn.offset_bottom=fav_m+fav_size
        # Legibility over any thumbnail is handled by a dark outline baked
        # directly into the texture via UAPIcons.get_icon_outlined().
        var fav_tex:=UAPIcons.get_icon_outlined("feature_favorite",fav_size)
        if fav_tex != null: fav_btn.texture_normal=fav_tex
        fav_btn.tooltip_text="Toggle Favorite"
        fav_btn.focus_mode=Control.FOCUS_NONE
        wrapper.add_child(fav_btn)
        _card_fav_btn_map[path]=fav_btn
        _update_card_favorite_star(card,path)
        # Hover feedback (TextureButton has no theme hover states): brighten a
        # dim (unfavorited) star under the mouse; favorited stars stay gold.
        fav_btn.mouse_entered.connect(func():
                if not is_favorite(path): fav_btn.self_modulate=Color(1,1,1,0.95))
        fav_btn.mouse_exited.connect(func():
                if _card_map.has(path):
                        var fc: PanelContainer=_card_map[path]
                        if is_instance_valid(fc): _update_card_favorite_star(fc,path))
        fav_btn.pressed.connect(func(): toggle_favorite(path))
        var card_path:=path
        card.gui_input.connect(func(ev:InputEvent):
                if not ev is InputEventMouseButton: return
                var mb:=ev as InputEventMouseButton
                if mb.button_index==MOUSE_BUTTON_LEFT and mb.pressed:
                        if mb.ctrl_pressed: _toggle_multi_select(card_path,card)
                        elif mb.shift_pressed: _range_select(card_path)
                        else: _clear_multi_select(); _select_card(card_path,card,normal_style)
                elif mb.button_index==MOUSE_BUTTON_RIGHT and mb.pressed:
                        # Context menu: favorites / add-to-group / remove from list.
                        get_viewport().set_input_as_handled()
                        _open_card_context_menu(card_path))
        _card_map[path]=card; _asset_grid.add_child(wrapper)

func _fallback_icon(path:String)->Texture2D:
        var theme:=EditorInterface.get_editor_theme(); if theme==null: return null
        var ext:=path.get_extension().to_lower(); var icon_name:String
        match ext:
                "tscn","scn":             icon_name="PackedScene"
                "glb","gltf","fbx","dae": icon_name="MeshInstance3D"
                "blend":                  icon_name="MeshInstance3D"
                "obj","mesh":             icon_name="Mesh"
                "res":                    icon_name="Resource"
                _:                        icon_name="Object"
        for candidate in [icon_name,"MeshInstance3D","Object","Node"]:
                if theme.has_icon(candidate,"EditorIcons"): return theme.get_icon(candidate,"EditorIcons")
        return null

# ─── Asset Card Right-Click Context Menu (2.1) ──────────────────────────────
## Right-clicking an asset card opens a themed popup with quick actions:
##   • Open Scene / View Model (2.4 — single asset only)
##   • Toggle Favorites for the card (or all cards in the active multi-selection)
##   • Add to any created group (submenu)
##   • Remove the asset(s) from the browser list (reversible, never deletes files)
## If the right-clicked card is part of the current multi-selection, the menu
## operates on the WHOLE selection; otherwise it operates on that single card.
func _open_card_context_menu(path:String)->void:
        var targets:Array = _multi_selected.duplicate() if (_multi_selected.size()>0 and _multi_selected.has(path)) else [path]
        targets = targets.filter(func(p): return p is String and ResourceLoader.exists(p))
        if targets.is_empty(): return
        var menu:=PopupMenu.new()
        _style_popup_menu(menu)
        # 2.4 — single-target convenience: open a scene in the editor, or view
        # a model. Only offered for ONE asset (multi-target has no meaningful
        # single "open" action) and only for scene/model formats.
        if targets.size()==1:
                var p0:=targets[0] as String
                var ext0:=p0.get_extension().to_lower()
                var is_scene0:=ext0=="tscn" or ext0=="scn"
                var is_model0:=ext0 in ["obj","glb","gltf","fbx","dae","blend","mesh","res"]
                if is_scene0 or is_model0:
                        var ov_icon:=_editor_icon(["PackedScene","Load"] if is_scene0 else ["Mesh","MeshInstance3D"])
                        var ov_idx:=menu.get_item_count()
                        menu.add_icon_item(ov_icon, "Open Scene" if is_scene0 else "View Model", 3)
                        menu.set_item_tooltip(ov_idx,
                                "Open this scene in the editor." if is_scene0 else
                                "View this model: mesh resources (obj/mesh) and imported scene formats (glb/gltf/fbx/blend) are opened in the Inspector with an interactive 3D mesh preview.")
        var all_fav:bool=true
        for p in targets:
                if not is_favorite(p): all_fav=false; break
        var noun:="Selected (%d)"%targets.size() if targets.size()>1 else path.get_file().get_basename()
        var fav_label := "Remove from Favorites" if all_fav else "Add to Favorites"
        var fav_icon  := "action_delete" if all_fav else "feature_favorite"
        var fav_idx := menu.get_item_count()
        menu.add_icon_item(UAPIcons.get_icon(fav_icon), fav_label, 0)
        menu.set_item_tooltip(fav_idx,"Toggle the favorite star for %s."%noun)
        var group_menu:=PopupMenu.new()
        _style_popup_menu(group_menu)
        for i in _groups.size():
                group_menu.add_icon_item(UAPIcons.get_icon("tab_groups"), str((_groups[i] as Dictionary)["name"]), 100+i)
        if _groups.is_empty():
                group_menu.add_item("(no groups yet — create one in the Groups tab)",-1)
                group_menu.set_item_disabled(0,true)
        group_menu.id_pressed.connect(_on_ctx_add_to_group.bind(targets))
        menu.add_submenu_node_item("Add to Group", group_menu, 1)
        menu.set_item_icon(menu.get_item_index(1), UAPIcons.get_icon("tab_groups"))
        menu.add_separator()
        var rm_idx := menu.get_item_count()
        menu.add_icon_item(UAPIcons.get_icon("action_delete"), "Remove from Asset List", 2)
        menu.set_item_tooltip(rm_idx,"Hide %s from the browser list.\nFiles are NOT deleted. Restore via Place tab → Format Filter → Restore Hidden."%noun)
        # NOTE: PopupMenu has no per-item FONT color API in Godot 4.7 — tint the
        # icon red instead, which keeps the destructive action visually distinct.
        menu.set_item_icon_modulate(rm_idx,C_ERROR)
        menu.id_pressed.connect(_on_ctx_menu_id.bind(targets))
        add_child(menu)
        menu.position=Vector2i(get_viewport().get_mouse_position())
        menu.popup()
        # One-shot menu: free it as soon as it closes so repeated right-clicks
        # never accumulate hidden PopupMenu nodes under the manager.
        menu.popup_hide.connect(menu.queue_free)

func _style_popup_menu(menu:PopupMenu)->void:
        var ps:=StyleBoxFlat.new(); ps.bg_color=Color(0.115,0.125,0.165)
        ps.set_corner_radius_all(4); ps.set_content_margin_all(int(4*_es))
        ps.border_width_bottom=1; ps.border_width_top=1
        ps.border_color=Color(0.03,0.033,0.05)
        menu.add_theme_stylebox_override("panel",ps)
        var hs:=StyleBoxFlat.new(); hs.bg_color=Color(0.28,0.62,1.0,0.9); hs.set_corner_radius_all(3)
        hs.content_margin_left=int(6*_es); hs.content_margin_right=int(6*_es)
        hs.content_margin_top=int(2*_es); hs.content_margin_bottom=int(2*_es)
        menu.add_theme_stylebox_override("hover",hs)
        menu.add_theme_color_override("font_color",Color(0.80,0.83,0.90))
        menu.add_theme_color_override("font_hover_color",Color(1,1,1))
        menu.add_theme_color_override("font_disabled_color",Color(0.45,0.47,0.55))
        menu.add_theme_constant_override("v_separation",int(2*_es))

func _on_ctx_menu_id(id:int, targets:Array)->void:
        match id:
                0:
                        # Match the label that was shown: if ALL were favorites we remove.
                        var all_fav:bool=true
                        for p in targets:
                                if not is_favorite(p): all_fav=false; break
                        for p in targets:
                                if all_fav and is_favorite(p): _favorite_paths.erase(p)
                                elif not all_fav and not is_favorite(p): _favorite_paths.append(p)
                        _rebuild_group_bar(); _save_config()
                        for p in targets:
                                if _card_map.has(p):
                                        var c:=_card_map[p] as PanelContainer
                                        if is_instance_valid(c): _update_card_favorite_star(c,p)
                        if _active_group==-2: _rebuild_browser_now()
                        set_status(("Removed from Favorites: " if all_fav else "Added to Favorites: ")+_ctx_target_summary(targets),C_OK)
                2:
                        var removed:int=0
                        for p in targets:
                                if not _hidden_paths.has(p): _hidden_paths.append(p)
                                if _all_paths.has(p): _all_paths.erase(p)
                                if _multi_selected.has(p): _multi_selected.erase(p)
                                removed+=1
                        _save_config(); _rebuild_browser_now()
                        set_status("Removed %d asset(s) from the list (restorable)."%removed,C_WARN)
                3:
                        # 2.4 — Open Scene / View Model (single target only).
                        if targets.size()==1: _open_or_view_asset(targets[0] as String)

func _editor_icon(names:Array)->Texture2D:
        ## Fetches the first available editor theme icon from `names`, falling
        ## back to the plugin's own browse icon so the menu item never ends up
        ## icon-less regardless of editor theme differences.
        var et:=EditorInterface.get_editor_theme()
        if et!=null:
                for n in names:
                        if et.has_icon(n as String,"EditorIcons"): return et.get_icon(n as String,"EditorIcons")
        return UAPIcons.get_icon("action_browse")

func _open_or_view_asset(path:String)->void:
        ## 2.4 — "Open Scene" / "View Model" from the card context menu.
        ## Scenes open in the editor (the native unsaved-changes confirmation
        ## applies). Models open in the Inspector: mesh resources (obj/mesh)
        ## directly, and imported scene formats (glb/gltf/fbx/blend) via their
        ## first mesh — both render an interactive 3D preview there.
        if not ResourceLoader.exists(path):
                set_status("File not found: "+path.get_file(),C_ERROR); return
        var ext:=path.get_extension().to_lower()
        var is_scene:=ext=="tscn" or ext=="scn"
        # Switching context: cancel any active placement ghost first so it
        # cannot leak across a scene change.
        if _is_placing: _on_stop_pressed()
        if is_scene:
                var root:=EditorInterface.get_edited_scene_root()
                if is_instance_valid(root) and root.scene_file_path==path:
                        set_status("This scene is already open in the editor.",C_WARN); return
                EditorInterface.open_scene_from_path(path)
                set_status("Opened scene: "+path.get_file(),C_OK)
                return
        var res:Resource = ResourceLoader.load(path)
        if res==null:
                set_status("Could not load: "+path.get_file(),C_ERROR); return
        if res is PackedScene and not is_scene:
                # Imported model scene (glb/gltf/fbx/blend). NOTE (verified in
                # the 4.7.1 harness): EditorInterface.open_scene_from_path() is
                # a SILENT NO-OP for imported scenes — no error, no scene
                # switch. So instead: instantiate off-tree, pull the first mesh
                # and open it in the Inspector, which renders an interactive 3D
                # preview. If the scene has no mesh, show the resource itself.
                var ps:=res as PackedScene
                var inst:Node = ps.instantiate()
                var mesh:=_find_first_mesh(inst)
                if inst!=null: inst.free()
                if mesh!=null:
                        EditorInterface.edit_resource(mesh)
                        set_status("Viewing model: "+path.get_file()+" (mesh preview in Inspector)",C_OK)
                else:
                        EditorInterface.edit_resource(res)
                        set_status("Viewing model: "+path.get_file(),C_OK)
        else:
                EditorInterface.edit_resource(res)
                set_status("Viewing: "+path.get_file(),C_OK)

func _find_first_mesh(node:Node)->Mesh:
        ## Depth-first search for the first renderable mesh inside an
        ## instantiated model scene (used by "View Model").
        if node is MeshInstance3D:
                var m:Mesh=(node as MeshInstance3D).mesh
                if m!=null: return m
        for c in node.get_children():
                var r:=_find_first_mesh(c)
                if r!=null: return r
        return null

func _on_ctx_add_to_group(group_idx:int, targets:Array)->void:
        if group_idx<100: return
        var gi:int=group_idx-100
        if gi>=_groups.size(): return
        var gd:=_groups[gi] as Dictionary
        var added:int=0
        for p in targets:
                if not (gd["paths"] as Array).has(p): (gd["paths"] as Array).append(p); added+=1
        _rebuild_group_list(); _rebuild_group_bar(); _save_config()
        set_status("Added %d asset(s) to group \"%s\"."%[added,gd["name"]],C_OK)

func _ctx_target_summary(targets:Array)->String:
        if targets.size()==1: return (targets[0] as String).get_file().get_basename()
        return "%d assets"%targets.size()

func _select_card(path:String,card:PanelContainer,normal_style:StyleBoxFlat)->void:
        if not ResourceLoader.exists(path):
                set_status("File not found: "+path.get_file()+" — refresh the browser.",C_ERROR); return
        var ext:=path.get_extension().to_lower()
        if ext=="tscn" or ext=="scn":
                var root:=EditorInterface.get_edited_scene_root()
                if is_instance_valid(root):
                        var open_path:=root.scene_file_path
                        if not open_path.is_empty() and open_path==path:
                                set_status("This scene is currently open — cannot place it inside itself.",C_WARN); return
        if not _selected_path_ui.is_empty() and _card_map.has(_selected_path_ui):
                var prev:=_card_map[_selected_path_ui] as PanelContainer
                if is_instance_valid(prev) and prev!=card:
                        _card_apply_state(prev,0)
        selected_path=path; _selected_path_ui=path; _last_clicked_path=path
        # Active card = blue 3D raised across the WHOLE card: solid blue face,
        # darker bottom bevel, plus a blue-tinted thumbnail well so the blue
        # reads around the image too — same tactile language as the mode/scroll
        # buttons, in blue as requested.
        _card_apply_state(card,1)
        var root:=EditorInterface.get_edited_scene_root()
        if root==null or not root is Node3D:
                set_status("Open a 3D scene first to start placing assets.",C_WARN); return
        if is_instance_valid(placer):placer.call("start_placement",path)
        _is_placing=true
        if is_instance_valid(_stop_btn):_stop_btn.disabled=false
        set_status("Placing: "+path.get_file().get_basename()+"   |   RMB / ESC = cancel",C_PLACING)

func activate_asset_from_eyedropper(path:String)->void:
        ## Called from ultimate_placer.gd when Alt+Click picks an already-placed
        ## object in the viewport — makes its source asset the active one for
        ## further placement, same as clicking its card, without requiring the
        ## user to go find and click that card themselves.
        if not ResourceLoader.exists(path):
                set_status("Eyedropper: source asset no longer exists at "+path,C_WARN); return
        if _card_map.has(path):
                var card:=_card_map[path] as PanelContainer
                if is_instance_valid(card):
                        var ns:=_card_select_stylebox(false)
                        _select_card(path,card,ns)
                        # Scroll the browser so the newly-active card is actually visible,
                        # not just selected off-screen with no visual confirmation.
                        if is_instance_valid(_asset_scroll):
                                var card_y:=card.get_global_rect().position.y-_asset_scroll.get_global_rect().position.y+_asset_scroll.scroll_vertical
                                _asset_scroll.scroll_vertical=maxi(0,int(card_y-_asset_scroll.size.y*0.5))
                        return
        # Asset exists but isn't currently visible in the browser (filtered out
        # by the active group/search/format filter) — still activate it directly.
        selected_path=path; _selected_path_ui=path
        if is_instance_valid(placer): placer.call("start_placement",path)
        _is_placing=true
        if is_instance_valid(_stop_btn): _stop_btn.disabled=false
        set_status("Picked: "+path.get_file().get_basename()+" (hidden by current filter)   |   RMB / ESC = cancel",C_PLACING)

func _card_select_stylebox(selected:bool)->StyleBoxFlat:
        # 2.4 card faces. Resting (selected=false): dark INSET 3D — carved into
        # the panel exactly like the group chips/rows: fill clearly darker than
        # the panel, a single darker line along the bottom edge, no border on
        # any other side. selected=true is kept for compatibility and returns
        # the raised amber multi-select treatment (see below).
        var sb:=StyleBoxFlat.new(); sb.set_corner_radius_all(5)
        if selected:
                return _card_select_stylebox_raised(C_MULTI)
        sb.bg_color=C_CARD_BG
        sb.border_width_bottom=maxi(2,int(2*_es))
        sb.border_color=S_INSET_SHADOW
        # Content margins MUST match the initial card stylebox (pad), otherwise
        # the thumb well would change width every time a card is deselected.
        sb.content_margin_left=maxi(3,int(4*_es)); sb.content_margin_right=maxi(3,int(4*_es))
        sb.content_margin_top=maxi(3,int(4*_es));  sb.content_margin_bottom=maxi(3,int(4*_es))
        return sb

## Raised 3D treatment for an "active" card (blue by default, amber for
## multi-select): solid face + darker bottom bevel + soft drop shadow.
func _card_select_stylebox_raised(color:Color)->StyleBoxFlat:
        var sb:=StyleBoxFlat.new(); sb.set_corner_radius_all(5)
        sb.bg_color=color.darkened(0.15)
        sb.border_width_bottom=maxi(2,int(3*_es))
        sb.border_color=color.darkened(0.5)
        sb.shadow_color=Color(0,0,0,0.35); sb.shadow_size=int(3*_es)
        sb.shadow_offset=Vector2(0,int(2*_es))
        # Same content margins as the resting face — selecting a card must
        # never shift its internal layout (the well used to widen by 2*pad).
        sb.content_margin_left=maxi(3,int(4*_es)); sb.content_margin_right=maxi(3,int(4*_es))
        sb.content_margin_top=maxi(3,int(4*_es));  sb.content_margin_bottom=maxi(3,int(4*_es))
        return sb

## 2.3 — ONE entry point for every card visual state. `card` is the
## PanelContainer (as stored in _card_map), `state`:
##   0 = resting        → dark INSET face (2.4: carved like the groups) +
##                        neutral darkest-layer well
##   1 = single-select  → BLUE raised 3D face + blue-tinted well FRAMED in
##                        blue (2.4: ring around the thumbnail)
##   2 = multi-select   → AMBER raised 3D face (same bevel+shadow language,
##                        previously a flat bordered box with no 3D) +
##                        amber-tinted well
func _card_apply_state(card:PanelContainer, state:int)->void:
        if not is_instance_valid(card): return
        var well_v:Variant = card.get_meta("uap_well", null) if card.has_meta("uap_well") else null
        match state:
                1:
                        card.add_theme_stylebox_override("panel",_card_select_stylebox_raised(C_SEL_BD))
                        _card_well_bg(well_v,C_WELL_SEL,C_SEL_BD)
                2:
                        card.add_theme_stylebox_override("panel",_card_select_stylebox_raised(C_MULTI))
                        _card_well_bg(well_v,C_WELL_MULTI,C_MULTI)
                _:
                        card.add_theme_stylebox_override("panel",_card_select_stylebox(false))
                        _card_well_bg(well_v,C_WELL_BG)

## Re-tints a card's thumbnail well (see _card_apply_state). Accepts an
## untyped ref because the meta lookup may return null for old cards.
func _card_well_bg(well_v:Variant, col:Color, ring:=Color(0,0,0,0))->void:
        if well_v==null or not (well_v is PanelContainer): return
        var well:=well_v as PanelContainer
        if not is_instance_valid(well): return
        var sb:=StyleBoxFlat.new(); sb.bg_color=col; sb.set_corner_radius_all(3)
        sb.set_content_margin_all(0)
        if ring.a>0.0:
                # 2.4 active well: the thumbnail is FRAMED by a ring in the
                # active color (blue single-select / amber multi-select) on top
                # of the tinted background — the selection reads around the
                # image, not just under it.
                sb.set_border_width_all(maxi(1,int(2*_es)))
                sb.border_color=ring
        else:
                # Resting well: deepest layer of the inset stack + bottom line.
                sb.border_width_bottom=1
                sb.border_color=S_INSET_SHADOW
        well.add_theme_stylebox_override("panel",sb)

func _toggle_multi_select(path:String,card:PanelContainer)->void:
        if _multi_selected.has(path):
                _multi_selected.erase(path)
                _card_apply_state(card,0)
        else:
                _multi_selected.append(path); _last_clicked_path=path
                _card_apply_state(card,2)
        _update_multi_select_bar()

func _range_select(path:String)->void:
        if _last_clicked_path.is_empty() or not _visible_paths_ordered.has(_last_clicked_path): _last_clicked_path=path
        var a:=_visible_paths_ordered.find(_last_clicked_path); var b:=_visible_paths_ordered.find(path)
        if a<0 or b<0: return
        if a>b: var tmp:=a; a=b; b=tmp
        for i in range(a,b+1):
                var p:=_visible_paths_ordered[i] as String
                if not _multi_selected.has(p): _multi_selected.append(p)
                var c:=_card_map.get(p,null) as PanelContainer
                if is_instance_valid(c): _card_apply_state(c,2)
        _update_multi_select_bar()

func _select_all_assets()->void:
        ## Ctrl+A (or Cmd+A on macOS) while hovering the asset browser: select
        ## every currently-visible asset (respects the active search/format/group
        ## filter, same set the grid is actually showing).
        if _visible_paths_ordered.is_empty():
                set_status("Nothing to select — the browser is empty.",C_WARN); return
        _multi_selected=_visible_paths_ordered.duplicate()
        _last_clicked_path=_visible_paths_ordered[_visible_paths_ordered.size()-1]
        for p in _multi_selected:
                var c:=_card_map.get(p,null) as PanelContainer
                if is_instance_valid(c): _card_apply_state(c,2)
        _update_multi_select_bar()
        set_status("Selected all %d assets in view."%_multi_selected.size(),C_OK)

func _clear_multi_select()->void:
        for path in _multi_selected:
                var c:=_card_map.get(path,null) as PanelContainer
                if is_instance_valid(c) and path!=_selected_path_ui:
                        _card_apply_state(c,0)
        _multi_selected.clear(); _update_multi_select_bar()

func _update_multi_select_bar()->void:
        if not is_instance_valid(_multisel_bar): return
        _multisel_bar.visible=(_multi_selected.size()>0)
        if is_instance_valid(_multisel_lbl): _multisel_lbl.text="%d selected"%_multi_selected.size()

func _on_add_multi_selected_to_group()->void:
        if _multi_selected.is_empty(): set_status("No assets selected.",C_WARN); return
        if not is_instance_valid(_multisel_group_opt): return
        var idx:=_multisel_group_opt.selected; var added:=0
        if idx==0:
                for p in _multi_selected:
                        if not _favorite_paths.has(p): _favorite_paths.append(p); added+=1
        elif idx-1<_groups.size():
                var gd:=_groups[idx-1] as Dictionary
                for p in _multi_selected:
                        if not gd["paths"].has(p): gd["paths"].append(p); added+=1
        _rebuild_group_list(); _rebuild_group_bar(); _save_config()
        set_status("Added %d assets to group."%added,C_OK); _clear_multi_select()

func _on_stop_pressed()->void:
        if is_instance_valid(placer):
                placer.call("cancel_placement")
        if place_mode == 4:
                _exit_spline_mode()
        on_placement_stopped()

func on_placement_stopped()->void:
        _is_placing=false
        if not _selected_path_ui.is_empty() and _card_map.has(_selected_path_ui):
                var prev:=_card_map[_selected_path_ui] as PanelContainer
                if is_instance_valid(prev):
                        _card_apply_state(prev,0)
        _selected_path_ui=""; selected_path=""
        if is_instance_valid(_stop_btn):_stop_btn.disabled=true
        set_status("Click an asset to start placing",C_OK)

func _on_format_toggled(ext:String)->void:
        if import_formats.has(ext): import_formats.erase(ext)
        else: import_formats.append(ext)
        _scan_folder(); _save_config()

func _on_group_filter(idx:int)->void:
        _active_group=idx; _refresh_group_chips(); _rebuild_browser_now()

func _rebuild_group_bar()->void:
        if not is_instance_valid(_group_bar): return
        for c in _group_bar.get_children(): _group_bar.remove_child(c); c.queue_free()
        _group_chip_btns.clear(); _group_chip_idxs.clear()
        _add_filter_btn("All",-1); _add_filter_btn("Favorites",-2,"feature_favorite")
        # Migration: older configs may have saved "Favorites" as a regular named
        # group entry. Move its paths into the real _favorite_paths storage
        # (rather than just discarding them) before removing the stale entry, so
        # nobody's existing favorites silently vanish.
        for g in _groups:
                if (g as Dictionary)["name"]=="Favorites":
                        for p in (g as Dictionary)["paths"] as Array:
                                if not _favorite_paths.has(p): _favorite_paths.append(p)
        _groups = _groups.filter(func(g): return (g as Dictionary)["name"] != "Favorites")
        for i in _groups.size(): _add_filter_btn((_groups[i] as Dictionary)["name"],i)
        # (2.5 rev 6) the rating stars are NOT part of the chip strip anymore —
        # they are built once by _build_header() and pinned to the header's
        # right corner, so rebuilding the chips never touches them.
        if is_instance_valid(_group_drop):
                _group_drop.clear(); _group_drop.add_icon_item(UAPIcons.get_icon("feature_favorite"), "Favorites")
                for g in _groups: _group_drop.add_item((g as Dictionary)["name"])
        if is_instance_valid(_multisel_group_opt):
                _multisel_group_opt.clear(); _multisel_group_opt.add_icon_item(UAPIcons.get_icon("feature_favorite"), "Favorites")
                for g in _groups: _multisel_group_opt.add_item((g as Dictionary)["name"])

func _add_filter_btn(label:String,idx:int,icon_name:String="")->void:
        var btn:=Button.new(); btn.text=label; btn.toggle_mode=true
        if not icon_name.is_empty(): UAPIcons.set_button_icon(btn, icon_name)
        btn.button_pressed=(_active_group==idx)
        btn.pressed.connect(func(): _on_group_filter(idx))
        # Groups/Filters chips: inset 3D — recessed INTO the panel, darker than
        # the panel, dark top inner edge. Active chip = recessed blue with a
        # light-blue label. No semitransparent fills, no outline rings.
        _style_inset_button(btn, Color(0.78,0.88,1.0), Color(0.60,0.63,0.72))
        if icon_name=="feature_favorite":
                _tint_fav_chip(btn)
        _group_bar.add_child(btn)
        _group_chip_btns.append(btn); _group_chip_idxs.append(idx)

func _tint_fav_chip(btn:Button)->void:
        btn.add_theme_color_override("icon_normal_color",Color(0.60,0.63,0.72))
        btn.add_theme_color_override("icon_hover_color",Color(0.9,0.93,1.0))
        btn.add_theme_color_override("icon_pressed_color",C_WARN)
        btn.add_theme_color_override("icon_hover_pressed_color",C_WARN.lightened(0.15))
        btn.add_theme_color_override("icon_focus_color",Color(0.60,0.63,0.72))

## Builds the animated rating stars ONCE and pins them to the RIGHT CORNER of
## the header title row (2.5 rev 6) — between the flexible spacer and the
## collapse chevron, exactly where the version label used to sit. The stars
## are NOT a child of the group chip strip: they never wrap with the group
## buttons and they never move when the collapse toggles — the chips come and
## go around them while the stars stay pinned. Clicking the stars area opens
## RATING_URL in the user's browser.
func _build_rating_stars()->void:
        if is_instance_valid(_rating_stars): return
        var RatingStars := load(get_script().resource_path.get_base_dir() + "/uap_rating.gd")
        if RatingStars == null: return
        var stars:Control = RatingStars.new(_es)
        stars.name = "UAP_RatingStars"
        stars.activated.connect(_open_rating_page)
        _rating_stars = stars
        _header_title_row.add_child(stars)
        # Keep the stars BEFORE the collapse chevron (right corner of the row).
        if is_instance_valid(_header_master_btn):
                _header_title_row.move_child(stars, _header_title_row.get_child_index(_header_master_btn))

func _open_rating_page()->void:
        set_status("Opening the ratings page — thank you for rating Ultimate Asset Placer!", null)
        OS.shell_open(RATING_URL)

## 2.5 rev 7 — tucks the rating stars behind the retract arrow (or reveals
## them again). Session-only state on purpose: the asset browser ALWAYS opens
## with the stars visible, and expanding the collapsed bar re-shows them too.
func _toggle_stars_hidden()->void:
        _stars_hidden = not _stars_hidden
        _apply_stars_hidden()

func _apply_stars_hidden()->void:
        if is_instance_valid(_rating_stars): _rating_stars.visible = not _stars_hidden
        if is_instance_valid(_header_stars_btn):
                UAPIcons.set_button_icon(_header_stars_btn,
                        "action_arrow_left" if _stars_hidden else "action_arrow_right")
                _header_stars_btn.tooltip_text = "Show rating stars" if _stars_hidden else "Hide rating stars"

## Keeps the filter-bar chips in sync with _active_group: exactly ONE chip
## reads as active at any time. (The pressed state of a toggle button is set
## automatically on click, so the previously-active chip must be unpressed
## explicitly — without this, every chip ever clicked stayed highlighted.)
func _refresh_group_chips()->void:
        for i in _group_chip_btns.size():
                var btn:=_group_chip_btns[i] as Button
                if not is_instance_valid(btn): continue
                var chip_idx:int=_group_chip_idxs[i] if i<_group_chip_idxs.size() else -1
                var active:bool=(_active_group==chip_idx)
                btn.set_pressed_no_signal(active)
                _style_inset_button(btn, Color(0.78,0.88,1.0), Color(0.60,0.63,0.72))
                if btn.icon!=null and btn.icon==UAPIcons.get_icon("feature_favorite"):
                        _tint_fav_chip(btn)

func _on_add_group(ne:LineEdit)->void:
        var gn:=ne.text.strip_edges(); if gn.is_empty(): return
        _groups.append({"name":gn,"paths":[]}); ne.text=""
        _rebuild_group_list(); _rebuild_group_bar(); _save_config()

func _on_remove_group(idx:int)->void:
        _groups.remove_at(idx)
        if _active_group>=_groups.size(): _active_group=-1
        _rebuild_group_list(); _rebuild_group_bar(); _save_config()

func _on_add_to_group(opt:OptionButton)->void:
        if selected_path.is_empty(): set_status("Select an asset first.",C_WARN); return
        var idx:=opt.selected
        if idx==0:
                if not _favorite_paths.has(selected_path): _favorite_paths.append(selected_path)
        elif idx-1<_groups.size():
                var gd:=_groups[idx-1] as Dictionary
                if not gd["paths"].has(selected_path): gd["paths"].append(selected_path)
        _rebuild_group_list(); _rebuild_group_bar(); _save_config()

func _rebuild_group_list()->void:
        if not is_instance_valid(_group_list_vbox): return
        for c in _group_list_vbox.get_children(): _group_list_vbox.remove_child(c); c.queue_free()
        for i in _groups.size():
                var gd:=_groups[i] as Dictionary
                # Group rows: same inset 3D language as the group chips — a
                # recessed, darker-than-panel row instead of a bare label.
                var row_pc:=PanelContainer.new(); row_pc.size_flags_horizontal=SIZE_EXPAND_FILL
                var inset:=_style_inset(false)
                inset.content_margin_left=int(8*_es); inset.content_margin_right=int(6*_es)
                inset.content_margin_top=int(5*_es); inset.content_margin_bottom=int(5*_es)
                row_pc.add_theme_stylebox_override("panel",inset)
                _group_list_vbox.add_child(row_pc)
                var row:=HBoxContainer.new(); row.add_theme_constant_override("separation",4)
                row.size_flags_horizontal=SIZE_EXPAND_FILL; row_pc.add_child(row)
                var ic:=TextureRect.new(); UAPIcons.set_texture_rect(ic,"tab_groups",Color(0.55,0.72,0.95))
                ic.custom_minimum_size=Vector2(int(14*_es),int(14*_es))
                ic.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
                ic.size_flags_vertical=SIZE_SHRINK_CENTER; row.add_child(ic)
                var lbl:=Label.new(); lbl.text=str(gd["name"])
                lbl.add_theme_color_override("font_color",Color(0.82,0.86,0.95))
                lbl.size_flags_horizontal=SIZE_EXPAND_FILL; lbl.clip_text=true; row.add_child(lbl)
                var cnt:=Label.new(); cnt.text=str((gd["paths"] as Array).size())
                cnt.add_theme_color_override("font_color",C_DIM); row.add_child(cnt)
                var db:=Button.new(); db.text="X"; db.pressed.connect(_on_remove_group.bind(i))
                db.tooltip_text="Delete this group (assets are kept — only the group is removed)"
                _style_idle_button(db); row.add_child(db)

func _find_node_named(n:String,from:Node)->Node:
        if from.name==n: return from
        for c in from.get_children():
                var r:=_find_node_named(n,c); if r!=null: return r
        return null

func update_rot_display(rx:float,ry:float,rz:float)->void:
        if is_instance_valid(_rot_x_spin): _rot_x_spin.set_value_no_signal(rx)
        if is_instance_valid(_rot_y_spin): _rot_y_spin.set_value_no_signal(ry)
        if is_instance_valid(_rot_z_spin): _rot_z_spin.set_value_no_signal(rz)

func get_place_scale()->Vector3:
        return Vector3(place_scale_all,place_scale_all,place_scale_all) if uniform_scale else Vector3(place_scale_x,place_scale_y,place_scale_z)

func get_rot_snap()->float:
        match rotation_snap_mode:
                0: return 0.0
                1: return 90.0
                2: return 45.0
                3: return 15.0
                4: return custom_snap_deg
        return 90.0

func nudge_height(delta:float)->void:
        if height_snap:
                var step:=grid_size if grid_size>0.0 else 1.0; height_offset=snapped(height_offset+delta,step)
        else: height_offset+=delta
        if is_instance_valid(_height_spin): _height_spin.set_value_no_signal(height_offset); _save_config()

func nudge_grid_height(delta:float)->void:
        grid_height+=delta
        if is_instance_valid(_grid_h_spin): _grid_h_spin.set_value_no_signal(grid_height)
        if is_instance_valid(placer):placer.call("rebuild_grid"); _save_config()

func nudge_scale(delta:float)->void:
        if uniform_scale:
                place_scale_all=maxf(0.01,place_scale_all+delta)
                place_scale_x=place_scale_all; place_scale_y=place_scale_all; place_scale_z=place_scale_all
                if is_instance_valid(_scale_spin):_scale_spin.set_value_no_signal(place_scale_all)
        else:
                place_scale_x=maxf(0.01,place_scale_x+delta); place_scale_y=maxf(0.01,place_scale_y+delta); place_scale_z=maxf(0.01,place_scale_z+delta)
                if is_instance_valid(_scale_x_spin):_scale_x_spin.set_value_no_signal(place_scale_x)
                if is_instance_valid(_scale_y_spin):_scale_y_spin.set_value_no_signal(place_scale_y)
                if is_instance_valid(_scale_z_spin):_scale_z_spin.set_value_no_signal(place_scale_z)
        _save_config()

func set_status(msg:String,color:Variant=null)->void:
        if not is_instance_valid(_status_lbl): return
        _status_lbl.text=msg
        var _sc:Color=C_OK
        if color!=null: _sc=color as Color
        _status_lbl.add_theme_color_override("font_color",_sc)


# ─── Asset Zoo ────────────────────────────────────────────────────────────────
func _on_zoo_pressed()->void:
        var root:=EditorInterface.get_edited_scene_root()
        if root==null or not root is Node3D: set_status("Open a 3D scene first.",C_WARN); return
        if not is_instance_valid(placer): return

        var source_paths:Array
        var source_desc:String
        match _zoo_source:
                1:
                        # Same fix as _filtered_paths(): group/Favorites paths are stored
                        # data, never gated by the format-filter checkboxes on their own,
                        # so apply it here too — otherwise "Current Group Filter" could
                        # build a zoo containing a format the user has toggled off, which
                        # would be an inconsistent, surprising result now that the
                        # browser itself correctly hides those.
                        source_paths=(_paths_for_active_group() as Array).filter(func(p): return (p as String).get_extension().to_lower() in import_formats)
                        source_desc=_active_group_name()
                        if _active_group==-1:
                                set_status("No group filter is active — pick one in the browser bar first, or switch Source to All/Selected.",C_WARN); return
                        if source_paths.is_empty():
                                set_status("The \"%s\" filter has no assets in it."%source_desc,C_WARN); return
                2:
                        source_paths=_multi_selected.duplicate()
                        source_desc="Selected Assets"
                        if source_paths.is_empty():
                                set_status("Nothing is multi-selected — Ctrl/Shift-click some asset cards first.",C_WARN); return
                _:
                        source_paths=_all_paths
                        source_desc="All Loaded Assets"
                        if source_paths.is_empty(): set_status("No assets loaded.",C_WARN); return

        _zoo_is_building=false; _zoo_items.clear(); _zoo_paths_to_measure.clear()
        var zoo:=Node3D.new(); zoo.name="AssetZoo"
        # force_readable_name=true is the actual fix for the reported @Node@6239
        # bug. `zoo.name` WAS already being set before add_child (that part was
        # already correct) — the real cause is that Godot's add_child(), when the
        # requested name collides with an existing sibling (e.g. a second zoo
        # created while an earlier "AssetZoo" is still in the scene), silently
        # DISCARDS the requested name and substitutes its own @Node3D@ID-style
        # placeholder UNLESS force_readable_name is explicitly passed — verified
        # directly against this exact Godot build: default add_child() on a
        # collision produced "@Node3D@2"; force_readable_name=true produced
        # "AssetZoo2", matching the naming scheme actually wanted here.
        (root as Node3D).add_child(zoo, true); zoo.owner=root
        _zoo_node=zoo; _zoo_index=0
        for path in source_paths:
                if ResourceLoader.exists(path): _zoo_paths_to_measure.append(path)
        if _zoo_paths_to_measure.is_empty():
                zoo.queue_free(); set_status("None of the %s assets could be loaded."%source_desc,C_WARN); return
        EditorInterface.get_selection().clear(); EditorInterface.get_selection().add_node(zoo)
        set_status("Zoo (%s): measuring %d assets..."%[source_desc,_zoo_paths_to_measure.size()],C_DIM)

func _tick_zoo_measure()->void:
        if not is_instance_valid(_zoo_node): _zoo_paths_to_measure.clear(); return
        var count:=0
        while not _zoo_paths_to_measure.is_empty() and count<ZOO_MEASURE_BATCH:
                var path:=_zoo_paths_to_measure.pop_front() as String
                if not ResourceLoader.exists(path): count+=1; continue
                var res:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_REUSE)
                if res==null: count+=1; continue
                var aabb:=AABB()
                if res is Mesh: aabb=(res as Mesh).get_aabb()
                elif res is PackedScene:
                        var tmp:=(res as PackedScene).instantiate()
                        if tmp!=null: aabb=_collect_aabb_offline(tmp); tmp.queue_free()
                if aabb.size==Vector3.ZERO: aabb=AABB(Vector3(-0.5,0,-0.5),Vector3(1,1,1))
                _zoo_items.append({"res":res,"path":path,"aabb":aabb,"half":maxf(aabb.size.x,aabb.size.z)*0.5+0.1})
                count+=1
        set_status("Zoo: measuring... %d remaining"%_zoo_paths_to_measure.size(),C_DIM)
        if _zoo_paths_to_measure.is_empty() and not _zoo_items.is_empty(): _zoo_compute_layout()

func _zoo_compute_layout()->void:
        var spacing:=_zoo_spacing_spin.value if is_instance_valid(_zoo_spacing_spin) else 2.0
        var items:=_zoo_items; var cols:=int(ceil(sqrt(float(items.size()))))
        var col_max:Array=[]; var row_max:Array=[]
        for i in items.size():
                var ci:=i%cols; var ri:=i/cols
                while col_max.size()<=ci: col_max.append(0.0)
                while row_max.size()<=ri: row_max.append(0.0)
                var hh:=items[i]["half"] as float
                col_max[ci]=maxf(col_max[ci],hh); row_max[ri]=maxf(row_max[ri],hh)
        var x_off:Array=[]; var acc:=0.0
        for ci in cols: x_off.append(acc+col_max[ci]); acc+=col_max[ci]*2.0+spacing
        var z_off:Array=[]; acc=0.0
        for ri in row_max.size(): z_off.append(acc+row_max[ri]); acc+=row_max[ri]*2.0+spacing
        for i in items.size():
                var ci:=i%cols; var ri:=i/cols
                (items[i] as Dictionary)["x"]=x_off[ci]; (items[i] as Dictionary)["z"]=z_off[ri]
        _zoo_cols=cols; _zoo_x_off=x_off; _zoo_z_off=z_off; _zoo_index=0
        _zoo_is_building=true; set_status("Zoo: placing 0 / %d..."%items.size(),C_DIM)

func _tick_zoo_build()->void:
        if not is_instance_valid(_zoo_node):
                _zoo_is_building=false; _zoo_items.clear(); set_status("Zoo: root deleted — build cancelled.",C_WARN); return
        var root:=EditorInterface.get_edited_scene_root()
        if root==null: _zoo_is_building=false; _zoo_items.clear(); return
        var count:=0
        while _zoo_index<_zoo_items.size() and count<ZOO_BATCH:
                if not is_instance_valid(_zoo_node):
                        _zoo_is_building=false; _zoo_items.clear(); set_status("Zoo: root deleted — build cancelled.",C_WARN); return
                var item:=_zoo_items[_zoo_index] as Dictionary
                var res:=item["res"] as Resource; var aabb:=item["aabb"] as AABB
                var bn:=(item["path"] as String).get_file().get_basename()
                var tx:=item["x"] as float; var tz:=item["z"] as float
                if res!=null and is_instance_valid(placer):
                        var inst:Node3D=placer.call("instantiate_resource_pub",res)
                        if inst!=null and is_instance_valid(_zoo_node):
                                # Resolve a unique name BEFORE add_child, matching the pattern used
                                # for regular placement — renaming AFTER add_child let Godot's
                                # own auto-uniquify kick in unpredictably whenever two zoo items
                                # shared a basename (e.g. "rock.glb" present in two folders),
                                # producing inconsistent-looking names and, in some orderings, a
                                # visible mismatch between the Label3D text and the final node name.
                                var base_name:=bn if not bn.is_empty() else "Asset_%d"%_zoo_index
                                var unique_name:=base_name; var dupe_idx:=2
                                while _zoo_node.has_node(unique_name):
                                        unique_name="%s_%d"%[base_name,dupe_idx]; dupe_idx+=1
                                inst.name=unique_name
                                _zoo_node.add_child(inst, true)
                                _set_owner_recursive(inst,root)
                                inst.position=Vector3(tx-aabb.get_center().x,-aabb.position.y,tz-aabb.get_center().z)
                                if _zoo_show_labels:
                                        var lbl:=Label3D.new()
                                        lbl.name="Label_"+inst.name; lbl.text=inst.name; lbl.pixel_size=0.008
                                        lbl.billboard=BaseMaterial3D.BILLBOARD_ENABLED; lbl.no_depth_test=true
                                        lbl.outline_modulate=Color(0,0,0,1); lbl.outline_size=8; lbl.font_size=32
                                        lbl.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
                                        lbl.position=Vector3(aabb.get_center().x,aabb.size.y+0.35+(-aabb.position.y),aabb.get_center().z)
                                        inst.add_child(lbl, true); lbl.owner=root
                        elif inst!=null: inst.queue_free()
                _zoo_index+=1; count+=1
        if _zoo_index>=_zoo_items.size():
                _zoo_is_building=false; set_status("Zoo: %d assets placed."%_zoo_items.size(),C_OK); _zoo_items.clear()
        else:
                set_status("Zoo: placing %d / %d..."%[_zoo_index,_zoo_items.size()],C_DIM)

func _collect_aabb_offline(node:Node)->AABB:
        var result:=AABB()
        for mi in _find_meshes_offline(node):
                var aabb:=(mi as MeshInstance3D).mesh.get_aabb()
                result=aabb if result.size==Vector3.ZERO else result.merge(aabb)
        return result

func _find_meshes_offline(node:Node)->Array:
        var out:Array=[]
        if node is MeshInstance3D and (node as MeshInstance3D).mesh!=null: out.append(node)
        for c in node.get_children(): out.append_array(_find_meshes_offline(c))
        return out

func _set_owner_recursive(node:Node,root:Node)->void:
        if not is_instance_valid(node) or node==root: return
        node.owner=root
        for c in node.get_children(): _set_owner_recursive(c,root)

func _collect_aabb(node:Node,origin:Node3D,inout:AABB)->AABB:
        if node is MeshInstance3D:
                var mi:=node as MeshInstance3D
                if mi.mesh!=null:
                        var rel:=origin.global_transform.affine_inverse()*mi.global_transform
                        var xf:=rel*mi.mesh.get_aabb()
                        inout=xf if inout.size==Vector3.ZERO else inout.merge(xf)
        for c in node.get_children(): inout=_collect_aabb(c,origin,inout)
        return inout

# ─── Config ───────────────────────────────────────────────────────────────────
func _save_config()->void:
        var cfg:=ConfigFile.new()
        cfg.set_value("s","folder",current_folder)
        var extra:Array=[]
        for p in _all_paths:
                if not (p as String).begins_with(current_folder): extra.append(p)
        cfg.set_value("s","extra_paths",extra)
        cfg.set_value("s","place_mode",place_mode); cfg.set_value("s","scroll_mode",scroll_mode)
        cfg.set_value("s","grid_size",grid_size); cfg.set_value("s","grid_height",grid_height)
        cfg.set_value("s","height_offset",height_offset); cfg.set_value("s","height_snap",height_snap)
        cfg.set_value("s","show_grid",show_grid); cfg.set_value("s","grid_enabled",grid_enabled)
        cfg.set_value("s","x_grid_enabled",x_grid_enabled); cfg.set_value("s","x_grid_size",x_grid_size)
        cfg.set_value("s","x_grid_pos",x_grid_pos); cfg.set_value("s","x_grid_cy",x_grid_cy)
        cfg.set_value("s","grid_view_dist",grid_view_dist); cfg.set_value("s","grid_follow",grid_follow)
        cfg.set_value("s","x_grid_follow",x_grid_follow); cfg.set_value("s","z_grid_follow",z_grid_follow)
        cfg.set_value("s","z_grid_enabled",z_grid_enabled); cfg.set_value("s","z_grid_size",z_grid_size)
        cfg.set_value("s","z_grid_pos",z_grid_pos); cfg.set_value("s","z_grid_cy",z_grid_cy)
        cfg.set_value("s","align_to_normal",align_to_normal); cfg.set_value("s","vertex_snap_mesh",vertex_snap_mesh)
        cfg.set_value("s","vertex_snap_strength",vertex_snap_strength)
        cfg.set_value("s","rot_snap",rotation_snap_mode); cfg.set_value("s","custom_deg",custom_snap_deg)
        cfg.set_value("s","rrot",random_rot); cfg.set_value("s","rrot_min",rrot_min); cfg.set_value("s","rrot_max",rrot_max)
        cfg.set_value("s","uniform",uniform_scale); cfg.set_value("s","scale_all",place_scale_all)
        cfg.set_value("s","scale_x",place_scale_x); cfg.set_value("s","scale_y",place_scale_y); cfg.set_value("s","scale_z",place_scale_z)
        cfg.set_value("s","rscale",random_scale); cfg.set_value("s","rscale_min",rscale_min); cfg.set_value("s","rscale_max",rscale_max)
        cfg.set_value("s","random_tilt",random_tilt); cfg.set_value("s","rtilt_max",rtilt_max)
        cfg.set_value("s","paint",paint_mode); cfg.set_value("s","paint_spacing",paint_spacing)
        cfg.set_value("s","paint_scatter",paint_scatter); cfg.set_value("s","scatter_radius",scatter_radius)
        cfg.set_value("s","random_group_place",random_group_place)
        cfg.set_value("s","unpack_scenes",unpack_scenes)
        cfg.set_value("s","multimesh_mode",multimesh_mode); cfg.set_value("s","mm_col_en",mm_collision_enabled)
        cfg.set_value("s","parent_path",parent_path); cfg.set_value("s","preview_size",_preview_size)
        cfg.set_value("s","col_en",collision_enabled); cfg.set_value("s","col_body",collision_body_type)
        cfg.set_value("s","col_shape",collision_shape_type); cfg.set_value("s","col_unpack",collision_auto_unpack)
        cfg.set_value("s","mat_en",material_override_enabled); cfg.set_value("s","mat_path",material_override_path)
        cfg.set_value("s","mat_mode",material_override_mode); cfg.set_value("s","import_formats",import_formats)
        cfg.set_value("s","zoo_labels",_zoo_show_labels)
        cfg.set_value("s","zoo_source",_zoo_source)
        cfg.set_value("s","header_collapsed",_header_collapsed)
        cfg.set_value("s","paint_as_brush",paint_as_brush)
        cfg.set_value("s","brush_radius",brush_radius); cfg.set_value("s","brush_density",brush_density)
        cfg.set_value("s","brush_falloff",brush_falloff); cfg.set_value("s","brush_tex",brush_texture_path)
        cfg.set_value("s","phys_lift_h",phys_lift_height); cfg.set_value("s","phys_lift_sc",phys_lift_scatter)
        cfg.set_value("s","phys_lift_sc_r",phys_lift_scatter_radius); cfg.set_value("s","phys_lift_rr",phys_lift_random_rot)
        cfg.set_value("s","phys_gravity",phys_gravity); cfg.set_value("s","phys_bounce",phys_bounciness)
        cfg.set_value("s","phys_friction",phys_friction); cfg.set_value("s","phys_align",phys_align_to_ground)
        cfg.set_value("s","phys_tumble",phys_random_tumble); cfg.set_value("s","phys_shape",phys_auto_shape)
        cfg.set_value("s","phys_max_fall",phys_max_fall_time); cfg.set_value("s","phys_auto_stop",phys_auto_stop)
        cfg.set_value("s","phys_auto_add_col",phys_auto_add_collision)
        for a in shortcuts.keys(): cfg.set_value("k",a,shortcuts[a])
        cfg.set_value("g","count",_groups.size())
        for i in _groups.size():
                var g:=_groups[i] as Dictionary
                cfg.set_value("g","g%d_n"%i,g["name"]); cfg.set_value("g","g%d_p"%i,g["paths"])
        cfg.set_value("g","favorites",_favorite_paths)
        cfg.set_value("g","hidden",_hidden_paths)
        cfg.save(CONFIG_PATH)

func _load_config()->void:
        var cfg:=ConfigFile.new(); if cfg.load(CONFIG_PATH)!=OK: return
        current_folder        =cfg.get_value("s","folder","res://")
        var saved_extra:Array =cfg.get_value("s","extra_paths",[]) as Array
        call_deferred("_merge_extra_paths",saved_extra)
        place_mode            =cfg.get_value("s","place_mode",1)
        if place_mode == 4:
                # Spline mode (4) can never be validly restored on load — the active
                # spline *node* it depends on is a live scene reference, which is
                # never persisted. Loading straight into place_mode 4 with no
                # _active_spline_tool used to leave the plugin looking completely
                # dead (no ghost cursor, viewport clicks silently swallowed) with no
                # indication why, until the user happened to click a mode button.
                place_mode = 1
        _prev_place_mode      =place_mode
        scroll_mode           =cfg.get_value("s","scroll_mode",0)
        grid_size             =cfg.get_value("s","grid_size",1.0)
        grid_height           =cfg.get_value("s","grid_height",0.0)
        height_offset         =cfg.get_value("s","height_offset",0.0)
        height_snap           =cfg.get_value("s","height_snap",false)
        show_grid             =cfg.get_value("s","show_grid",true)
        grid_enabled          =cfg.get_value("s","grid_enabled",true)
        x_grid_enabled        =cfg.get_value("s","x_grid_enabled",false)
        x_grid_size           =cfg.get_value("s","x_grid_size",10.0)
        x_grid_pos            =cfg.get_value("s","x_grid_pos",0.0)
        x_grid_cy             =cfg.get_value("s","x_grid_cy",0.0)
        z_grid_enabled        =cfg.get_value("s","z_grid_enabled",false)
        z_grid_size           =cfg.get_value("s","z_grid_size",10.0)
        z_grid_pos            =cfg.get_value("s","z_grid_pos",0.0)
        z_grid_cy             =cfg.get_value("s","z_grid_cy",0.0)
        grid_view_dist        =cfg.get_value("s","grid_view_dist",40.0)
        grid_follow           =cfg.get_value("s","grid_follow",true)
        x_grid_follow         =cfg.get_value("s","x_grid_follow",true)
        z_grid_follow         =cfg.get_value("s","z_grid_follow",true)
        align_to_normal       =cfg.get_value("s","align_to_normal",false)
        vertex_snap_mesh      =cfg.get_value("s","vertex_snap_mesh",false)
        vertex_snap_strength  =cfg.get_value("s","vertex_snap_strength",42.0)
        rotation_snap_mode    =cfg.get_value("s","rot_snap",1)
        custom_snap_deg       =cfg.get_value("s","custom_deg",15.0)
        random_rot            =cfg.get_value("s","rrot",false)
        rrot_min              =cfg.get_value("s","rrot_min",0.0)
        rrot_max              =cfg.get_value("s","rrot_max",360.0)
        uniform_scale         =cfg.get_value("s","uniform",true)
        place_scale_all       =cfg.get_value("s","scale_all",1.0)
        place_scale_x         =cfg.get_value("s","scale_x",1.0)
        place_scale_y         =cfg.get_value("s","scale_y",1.0)
        place_scale_z         =cfg.get_value("s","scale_z",1.0)
        random_scale          =cfg.get_value("s","rscale",false)
        rscale_min            =cfg.get_value("s","rscale_min",0.8)
        rscale_max            =cfg.get_value("s","rscale_max",1.2)
        random_tilt           =cfg.get_value("s","random_tilt",false)
        rtilt_max             =cfg.get_value("s","rtilt_max",10.0); rtilt_min=-rtilt_max
        paint_mode            =cfg.get_value("s","paint",false)
        paint_spacing         =cfg.get_value("s","paint_spacing",0.5)
        paint_scatter         =cfg.get_value("s","paint_scatter",false)
        scatter_radius        =cfg.get_value("s","scatter_radius",0.5)
        random_group_place    =cfg.get_value("s","random_group_place",false)
        unpack_scenes         =cfg.get_value("s","unpack_scenes",false)
        multimesh_mode        =cfg.get_value("s","multimesh_mode",false)
        mm_collision_enabled  =cfg.get_value("s","mm_col_en",false)
        parent_path           =cfg.get_value("s","parent_path","")
        _preview_size         =cfg.get_value("s","preview_size",88)
        collision_enabled     =cfg.get_value("s","col_en",false)
        collision_body_type   =cfg.get_value("s","col_body",0)
        collision_shape_type  =cfg.get_value("s","col_shape",0)
        collision_auto_unpack =cfg.get_value("s","col_unpack",true)
        material_override_enabled=cfg.get_value("s","mat_en",false)
        material_override_path   =cfg.get_value("s","mat_path","")
        material_override_mode   =cfg.get_value("s","mat_mode",0)
        var saved_fmts:Array=cfg.get_value("s","import_formats",ALL_FORMATS.duplicate()) as Array
        import_formats=saved_fmts
        for a in shortcuts.keys():
                if cfg.has_section_key("k",a): shortcuts[a]=cfg.get_value("k",a,shortcuts[a])
        var gc:int=cfg.get_value("g","count",0); _groups.clear()
        for i in gc:
                _groups.append({"name":cfg.get_value("g","g%d_n"%i,"Group"),"paths":cfg.get_value("g","g%d_p"%i,[])})
        _favorite_paths=cfg.get_value("g","favorites",[]) as Array
        _hidden_paths=cfg.get_value("g","hidden",[]) as Array
        # Migration: older configs may have saved "Favorites" as a regular named
        # group entry — Favorites is now always the built-in star slot (-2) and
        # must never live in _groups. Move its paths into _favorite_paths (rather
        # than just discarding them) before removing the stale entry.
        for g in _groups:
                if (g as Dictionary)["name"]=="Favorites":
                        for p in (g as Dictionary)["paths"] as Array:
                                if not _favorite_paths.has(p): _favorite_paths.append(p)
        _groups = _groups.filter(func(g): return (g as Dictionary)["name"] != "Favorites")
        _zoo_show_labels=cfg.get_value("s","zoo_labels",true)
        _zoo_source=clampi(int(cfg.get_value("s","zoo_source",0)),0,2)
        _header_collapsed=cfg.get_value("s","header_collapsed",false)
        paint_as_brush  =cfg.get_value("s","paint_as_brush",false)
        brush_radius    =cfg.get_value("s","brush_radius",2.0)
        brush_density   =cfg.get_value("s","brush_density",0.5)
        brush_falloff   =cfg.get_value("s","brush_falloff",0.5)
        brush_texture_path=cfg.get_value("s","brush_tex","")
        phys_lift_height       =cfg.get_value("s","phys_lift_h",3.0)
        phys_lift_scatter      =cfg.get_value("s","phys_lift_sc",false)
        phys_lift_scatter_radius=cfg.get_value("s","phys_lift_sc_r",0.5)
        phys_lift_random_rot   =cfg.get_value("s","phys_lift_rr",false)
        phys_gravity            =cfg.get_value("s","phys_gravity", float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)))
        phys_bounciness         =cfg.get_value("s","phys_bounce",0.15)
        phys_friction            =cfg.get_value("s","phys_friction",0.55)
        phys_align_to_ground     =cfg.get_value("s","phys_align",true)
        phys_random_tumble       =cfg.get_value("s","phys_tumble",false)
        phys_auto_shape          =cfg.get_value("s","phys_shape",0)
        phys_max_fall_time       =cfg.get_value("s","phys_max_fall",15.0)
        phys_auto_stop           =cfg.get_value("s","phys_auto_stop",true)
        phys_auto_add_collision  =cfg.get_value("s","phys_auto_add_col",true)
