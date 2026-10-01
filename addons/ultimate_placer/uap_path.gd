@tool
extends Path3D

signal build_warning(message: String)

const LAYER_SCATTER = 0
const LAYER_DEFORM  = 1

@export var l_type:       Array[int]     = []
@export var l_mesh:       Array[String]  = [] 
@export var l_spacing:    Array[float]   = []
@export var l_offset:     Array[Vector3] = []
@export var l_scale:      Array[Vector3] = []
@export var l_uv_tile:    Array[Vector2] = []
@export var l_align:      Array[bool]    = []
@export var l_rnd_yaw:    Array[float]   = []
@export var l_flip_faces: Array[bool]    = []
@export var l_visible:    Array[bool]    = []
@export var l_use_mm:     Array[bool]    = [] # MultiMesh packing vs individual MeshInstance3D nodes
@export var l_col_bake:   Array[bool]    = [] # Generate collision on bake
@export var l_scale_start:Array[float]   = [] # Scale multiplier at the start of the curve
@export var l_scale_end:  Array[float]   = [] # Scale multiplier at the end of the curve
@export var l_twist:      Array[float]   = [] # Total twist (degrees) accumulated from start to end
@export var l_seed:       Array[int]     = [] # Per-layer RNG seed; keeps Random Yaw stable across rebuilds and scene reloads

@export_group("Terrain Probe")
## How far above each curve point to start the downward raycast. Increase this
## if your terrain sits far above the curve (e.g. a huge stylised landscape).
@export var terrain_probe_up: float = 500.0
## How far below each curve point the downward raycast will search before
## giving up. Increase this for very tall scenes or points placed high in the air.
@export var terrain_probe_down: float = 5000.0

var editor_plugin: EditorPlugin = null

var _nodes: Array[Node] = []
var _all_dirty: bool = true
var _dirty_layers: Dictionary = {}   # idx -> true, when only some layers changed
var _last_rebuild_ms: int = 0

## Rebuilds are driven from _process so curve drags coalesce: while the user
## is dragging control points the rebuild rate is capped, but an isolated
## edit after a quiet period rebuilds on the very next frame.
const REBUILD_MIN_INTERVAL := 0.08

func _ready() -> void:
        if not Engine.is_editor_hint(): return
        _cleanup_orphans()
        if curve == null: curve = Curve3D.new()
        if not curve.changed.is_connected(_on_curve_changed):
                curve.changed.connect(_on_curve_changed)
        _all_dirty = true

func _process(_delta: float) -> void:
        if not Engine.is_editor_hint(): return
        if not _all_dirty and _dirty_layers.is_empty(): return
        var since := float(Time.get_ticks_msec() - _last_rebuild_ms) / 1000.0
        if since < REBUILD_MIN_INTERVAL: return
        _last_rebuild_ms = Time.get_ticks_msec()
        _rebuild_all()

func _on_curve_changed() -> void: _all_dirty = true

func force_rebuild() -> void:
        _all_dirty = true
        _last_rebuild_ms = 0

func _cleanup_orphans() -> void:
        ## Removes nodes this script is about to regenerate anyway, plus
        ## ownerless leftovers from interrupted rebuilds. Layer_* children are
        ## removed EVEN when owned (they are saved with the scene, but the
        ## layer arrays are the source of truth — keeping them would collide
        ## with the rebuild and duplicate every layer on each reload).
        ## Other owned children (user-placed nodes, @-renamed instances) are
        ## never touched.
        for c in get_children():
                var nm := String(c.name)
                var is_layer := nm.begins_with("Layer_") \
                                and (nm.ends_with("_Scatter") or nm.ends_with("_Deform"))
                if not is_layer and c.owner != null: continue
                if is_layer or nm.begins_with("@") or nm.begins_with("del_"):
                        c.name = "del_" + str(randi())
                        c.queue_free()

func add_layer(type: int, path: String) -> void:
        l_type.append(type); l_mesh.append(path)
        l_spacing.append(2.0); l_offset.append(Vector3.ZERO)
        l_scale.append(Vector3.ONE); l_uv_tile.append(Vector2(1.0, 1.0))
        l_align.append(true); l_rnd_yaw.append(0.0)
        l_flip_faces.append(false); l_visible.append(true)
        l_use_mm.append(true); l_col_bake.append(false)
        l_scale_start.append(1.0); l_scale_end.append(1.0); l_twist.append(0.0)
        l_seed.append(randi())
        _nodes.append(null); _all_dirty = true

func remove_layer(idx: int) -> void:
        if idx < 0 or idx >= l_type.size(): return
        if idx < _nodes.size() and is_instance_valid(_nodes[idx]):
                _nodes[idx].name = "del_" + str(randi())
                _nodes[idx].queue_free()
                _nodes[idx] = null
        l_type.remove_at(idx); l_mesh.remove_at(idx)
        l_spacing.remove_at(idx); l_offset.remove_at(idx)
        l_scale.remove_at(idx); l_uv_tile.remove_at(idx)
        l_align.remove_at(idx); l_rnd_yaw.remove_at(idx)
        l_flip_faces.remove_at(idx); l_visible.remove_at(idx)
        l_use_mm.remove_at(idx); l_col_bake.remove_at(idx)
        l_scale_start.remove_at(idx); l_scale_end.remove_at(idx); l_twist.remove_at(idx)
        if idx < l_seed.size(): l_seed.remove_at(idx)
        _nodes.remove_at(idx); _all_dirty = true   # indices shift — everything rebuilds

func update_layer(idx: int, prop: String, val: Variant) -> void:
        if idx < 0 or idx >= l_type.size(): return
        match prop:
                "spacing": l_spacing[idx] = val
                "offset_x": l_offset[idx].x = val
                "offset_y": l_offset[idx].y = val
                "offset_z": l_offset[idx].z = val
                "scale_x": l_scale[idx].x = val
                "scale_y": l_scale[idx].y = val
                "scale_z": l_scale[idx].z = val
                "uv_x": l_uv_tile[idx].x = val
                "uv_y": l_uv_tile[idx].y = val
                "align": l_align[idx] = val
                "rnd_yaw": l_rnd_yaw[idx] = val
                "flip_faces": l_flip_faces[idx] = val
                "mesh": l_mesh[idx] = val
                "visible": l_visible[idx] = val
                "use_mm": l_use_mm[idx] = val
                "col_bake": l_col_bake[idx] = val
                "scale_start": l_scale_start[idx] = val
                "scale_end": l_scale_end[idx] = val
                "twist": l_twist[idx] = val
                "seed": l_seed[idx] = val if val is int else randi()
        _dirty_layers[idx] = true

# ═══════════════════════════════════════════════════════════════════════════════
# TERRAIN SNAPPING LOGIC
# ═══════════════════════════════════════════════════════════════════════════════

func _raycast_down(global_pos: Vector3) -> Variant:
        if not is_inside_tree(): return null
        var space = get_world_3d().direct_space_state
        if space == null: return null
        var start = Vector3(global_pos.x, global_pos.y + terrain_probe_up, global_pos.z)
        var end = Vector3(global_pos.x, global_pos.y - terrain_probe_down, global_pos.z)
        var q = PhysicsRayQueryParameters3D.create(start, end)
        var hit = space.intersect_ray(q)
        if hit.is_empty(): return null
        return hit.position

func snap_lowest_to_ground() -> Dictionary:
        ## Drops the whole path so its LOWEST point touches the ground.
        var lowest_y = INF
        var drop = 0.0
        var hit_count = 0
        for i in curve.point_count:
                var gp = to_global(curve.get_point_position(i))
                var hit = _raycast_down(gp)
                if hit != null:
                        hit_count += 1
                        if gp.y < lowest_y:
                                lowest_y = gp.y
                                drop = gp.y - hit.y
        if hit_count > 0 and lowest_y < INF:
                global_position.y -= drop
                _all_dirty = true
        return {"hit": hit_count, "total": curve.point_count}

func conform_to_terrain() -> Dictionary:
        var before := _snapshot_curve()
        var result := _conform_points()
        _commit_curve_undo("UAP: Wrap Points to Terrain", before)
        return result

func _conform_points() -> Dictionary:
        var hit_count = 0
        for i in curve.point_count:
                var gp = to_global(curve.get_point_position(i))
                var hit = _raycast_down(gp)
                if hit != null:
                        hit_count += 1
                        curve.set_point_position(i, to_local(hit))
        _all_dirty = true
        return {"hit": hit_count, "total": curve.point_count}

func subdivide_and_conform() -> void:
        var length = curve.get_baked_length()
        if length < 0.1: return
        var before := _snapshot_curve()
        var step = 1.0
        var count = int(length / step) + 1
        var new_pts = []
        for i in count:
                var t = minf(i * step, length)
                new_pts.append(curve.sample_baked(t))
        curve.clear_points()
        for p in new_pts:
                curve.add_point(p)
        _conform_points()
        _sharpen_points()
        _commit_curve_undo("UAP: Subdivide & Wrap to Terrain", before)

func smooth_all_points() -> void:
        var before := _snapshot_curve()
        for i in curve.point_count:
                var pre = curve.get_point_position(max(0, i-1))
                var nxt = curve.get_point_position(min(curve.point_count-1, i+1))
                var dir = (nxt - pre) * 0.25
                curve.set_point_in(i, -dir)
                curve.set_point_out(i, dir)
        _commit_curve_undo("UAP: Smooth Points", before)

func sharpen_all_points() -> void:
        var before := _snapshot_curve()
        _sharpen_points()
        _commit_curve_undo("UAP: Sharpen Points", before)

func _sharpen_points() -> void:
        for i in curve.point_count:
                curve.set_point_in(i, Vector3.ZERO)
                curve.set_point_out(i, Vector3.ZERO)

func _snapshot_curve() -> Array:
        ## Flat per-point snapshot: [pos, in, out] triplets. Curve edits issued
        ## from script are not captured by the editor's own undo system, so the
        ## destructive terrain tools record one themselves.
        var snap: Array = []
        for i in curve.point_count:
                snap.append(curve.get_point_position(i))
                snap.append(curve.get_point_in(i))
                snap.append(curve.get_point_out(i))
        return snap

func _restore_curve_points(snap: Array) -> void:
        curve.clear_points()
        var i := 0
        while i + 2 < snap.size():
                curve.add_point(snap[i], snap[i + 1], snap[i + 2])
                i += 3
        _all_dirty = true

func _open_scene_undo_action(ur: EditorUndoRedoManager, action_name: String) -> void:
        ## Creates the action in the edited scene's undo history so references
        ## to scene nodes pass the manager's history validation (the default
        ## plugin context is the GLOBAL history).
        var scene_root := EditorInterface.get_edited_scene_root()
        if scene_root != null: ur.create_action(action_name, 0, scene_root)
        else: ur.create_action(action_name)

func _commit_curve_undo(action_name: String, before: Array) -> void:
        var ur: Variant = _undo_redo()
        if ur == null: return
        _open_scene_undo_action(ur, action_name)
        ur.add_do_method(self, "_restore_curve_points", _snapshot_curve())
        ur.add_undo_method(self, "_restore_curve_points", before)
        ur.commit_action(false)

# ═══════════════════════════════════════════════════════════════════════════════
# BUILD ENGINE
# ═══════════════════════════════════════════════════════════════════════════════

func _rebuild_all() -> void:
        if curve == null or curve.point_count < 2: return
        var to_build: Array = []
        if _all_dirty:
                for i in range(_nodes.size()):
                        if is_instance_valid(_nodes[i]):
                                _nodes[i].name = "del_" + str(randi())
                                _nodes[i].queue_free()
                _nodes.clear()
                _cleanup_orphans()
                while _nodes.size() < l_type.size(): _nodes.append(null)
                for i in l_type.size():
                        if l_visible[i]: to_build.append(i)
        else:
                var idxs: Array = _dirty_layers.keys()
                idxs.sort()
                for idx_v in idxs:
                        var i := int(idx_v)
                        if i >= _nodes.size(): continue
                        if is_instance_valid(_nodes[i]):
                                _nodes[i].name = "del_" + str(randi())
                                _nodes[i].queue_free()
                                _nodes[i] = null
                        if l_visible[i]: to_build.append(i)
        _all_dirty = false
        _dirty_layers.clear()
        for i in to_build:
                _build_layer(i)

func _build_layer(idx: int) -> void:
        if l_type[idx] == LAYER_SCATTER:
                _build_scatter(idx)
        else:
                var path = l_mesh[idx].split(",")[0].strip_edges()
                if not ResourceLoader.exists(path):
                        build_warning.emit("Deform layer %d: mesh not found at \"%s\"." % [idx, path])
                        return
                var res = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
                var mesh = _extract_mesh(res)
                if mesh: _build_deform(idx, mesh)
                else: build_warning.emit("Deform layer %d: \"%s\" has no usable mesh." % [idx, path])

func _build_scatter(idx: int) -> void:
        var step = maxf(0.1, l_spacing[idx])
        var off = l_offset[idx]; var scl = l_scale[idx]
        var align = l_align[idx]; var rnd = l_rnd_yaw[idx]
        var taper_start = l_scale_start[idx] if idx < l_scale_start.size() else 1.0
        var taper_end   = l_scale_end[idx]   if idx < l_scale_end.size()   else 1.0
        var twist_total = l_twist[idx]       if idx < l_twist.size()       else 0.0
        # Yaw jitter is drawn from a per-layer seeded RNG: the saved scatter
        # layout survives every rebuild and every scene reload instead of
        # re-rolling into a different arrangement each time the curve changes.
        var rng := RandomNumberGenerator.new()
        rng.seed = int(l_seed[idx]) if idx < l_seed.size() else hash("UAP_layer_%d" % idx)
        var length = curve.get_baked_length()
        if length < step: return
        
        var paths = l_mesh[idx].split(",", false)
        var meshes = []
        for p in paths:
                var res = ResourceLoader.load(p.strip_edges(), "", ResourceLoader.CACHE_MODE_REUSE)
                var m = _extract_mesh(res)
                if m: meshes.append(m)
                
        if meshes.is_empty():
                build_warning.emit("Scatter layer %d: no valid meshes found (check the mesh path(s))." % idx)
                return
        var count = int(length / step) + 1
        
        var container = Node3D.new()
        container.name = "Layer_%d_Scatter" % idx
        add_child(container, true) 
        
        var root = get_tree().edited_scene_root if Engine.is_editor_hint() else null
        if root: container.owner = root
        _nodes[idx] = container
        
        var mms = []
        for m in meshes:
                var mm = MultiMesh.new()
                mm.transform_format = MultiMesh.TRANSFORM_3D
                mm.mesh = m; mm.instance_count = count
                mms.append({"mm": mm, "placed": 0})
                
        for i in count:
                var m_idx = i % meshes.size() 
                var t = minf(i * step, length)
                var xf = curve.sample_baked_with_rotation(t, true)
                if not align: xf.basis = Basis.IDENTITY
                
                var right = xf.basis.x.normalized()
                var up = xf.basis.y.normalized()
                var fwd = xf.basis.z.normalized()
                var pos = xf.origin + (right * off.x) + (up * off.y) + (fwd * off.z)
                
                # Taper: scale multiplier interpolated from scale_start (t=0) to
                # scale_end (t=length) — e.g. a fence that's thicker at the base, or
                # a road that narrows toward one end, the way Blender's curve taper
                # / Unreal's Spline Mesh Component scale-along-spline works.
                var t_norm = t / length if length > 0.0 else 0.0
                var taper = lerpf(taper_start, taper_end, t_norm)

                var final_basis = xf.basis
                # Twist: additional rotation around the curve's own forward/tangent
                # axis, accumulating from 0° at the start to twist_total at the end
                # — a screw/rope-twist effect along the whole run.
                if twist_total != 0.0: final_basis = final_basis.rotated(fwd, deg_to_rad(lerpf(0.0, twist_total, t_norm)))
                if rnd > 0.0: final_basis = final_basis.rotated(up, deg_to_rad(rng.randf_range(-rnd, rnd)))
                
                mms[m_idx].mm.set_instance_transform(mms[m_idx].placed, Transform3D(final_basis.scaled(scl * taper), pos))
                mms[m_idx].placed += 1
                
        for i in range(mms.size()):
                var m_data = mms[i]
                m_data.mm.instance_count = m_data.placed
                
                if l_use_mm[idx]:
                        var mmi = MultiMeshInstance3D.new()
                        mmi.multimesh = m_data.mm
                        mmi.name = "MultiMeshPiece_%d" % i
                        container.add_child(mmi, true)
                        if root: mmi.owner = root
                else:
                        for j in m_data.placed:
                                var mi = MeshInstance3D.new()
                                mi.mesh = m_data.mm.mesh
                                mi.transform = m_data.mm.get_instance_transform(j)
                                mi.name = "Piece_%d_%d" % [i, j]
                                container.add_child(mi, true)
                                if root: mi.owner = root

func _build_deform(idx: int, base_mesh: Mesh) -> void:
        var total_len = curve.get_baked_length()
        if total_len < 0.1: return
        
        var off = l_offset[idx]; var scl = l_scale[idx]
        var uv_scl = l_uv_tile[idx]; var flip = l_flip_faces[idx]
        var taper_start = l_scale_start[idx] if idx < l_scale_start.size() else 1.0
        var taper_end   = l_scale_end[idx]   if idx < l_scale_end.size()   else 1.0
        var twist_total = l_twist[idx]       if idx < l_twist.size()       else 0.0
        
        var aabb = base_mesh.get_aabb()
        var mesh_z_len = maxf(0.01, aabb.size.z * scl.z)
        var segments = int(ceil(total_len / mesh_z_len))
        # Hard cap: extreme Scale-Z / long-curve combinations could request
        # tens of thousands of segments, each duplicating every vertex of the
        # base mesh. Past the cap, the same segment count is spread evenly
        # across the curve instead of truncating it partway.
        const MAX_DEFORM_SEGMENTS := 2000
        if segments > MAX_DEFORM_SEGMENTS:
                segments = MAX_DEFORM_SEGMENTS
                mesh_z_len = total_len / float(segments)
                build_warning.emit("Deform layer %d: requested segment count was capped at %d to avoid an excessive vertex count — increase Scale Z or shorten the curve for full density." % [idx, MAX_DEFORM_SEGMENTS])
        
        var st_in = SurfaceTool.new()
        st_in.create_from(base_mesh, 0)
        var arrays = st_in.commit_to_arrays()
        var verts = arrays[Mesh.ARRAY_VERTEX]
        var uvs = arrays[Mesh.ARRAY_TEX_UV]
        var indices = arrays[Mesh.ARRAY_INDEX]
        if verts == null or verts.is_empty():
                build_warning.emit("Deform layer %d: source mesh has no vertices." % idx); return
        if indices == null or indices.is_empty():
                build_warning.emit("Deform layer %d: source mesh has no triangle indices (point clouds / wireframes aren't supported for Deform)." % idx); return
        
        var st_out = SurfaceTool.new()
        st_out.begin(Mesh.PRIMITIVE_TRIANGLES)
        var mat = base_mesh.surface_get_material(0)
        if mat: st_out.set_material(mat)
        
        for s in range(segments):
                var z_start = s * mesh_z_len
                for i in range(verts.size()):
                        var v = verts[i] * scl
                        var ratio = (v.z - aabb.position.z * scl.z) / mesh_z_len
                        var curve_t = clampf(z_start + (ratio * mesh_z_len), 0.0, total_len)
                        
                        var xf = curve.sample_baked_with_rotation(curve_t, true)
                        var local_offset = Vector3(v.x + off.x, v.y + off.y, 0)

                        # Taper + twist happen in the LOCAL cross-section space, before
                        # the curve's own sampled transform is applied — this is the
                        # geometrically correct order (rotate/scale the cross-section
                        # first, then place+orient the whole thing along the spline).
                        var t_norm = curve_t / total_len if total_len > 0.0 else 0.0
                        var taper = lerpf(taper_start, taper_end, t_norm)
                        local_offset.x *= taper
                        local_offset.y *= taper
                        if twist_total != 0.0:
                                var twist_rad = deg_to_rad(lerpf(0.0, twist_total, t_norm))
                                var cs = cos(twist_rad); var sn = sin(twist_rad)
                                local_offset = Vector3(
                                        local_offset.x * cs - local_offset.y * sn,
                                        local_offset.x * sn + local_offset.y * cs,
                                        local_offset.z)
                        
                        if uvs and uvs.size() > i:
                                st_out.set_uv(Vector2(uvs[i].x * uv_scl.x, (uvs[i].y + s) * uv_scl.y))
                                
                        st_out.add_vertex(xf * local_offset)
                        
                var idx_offset = s * verts.size()
                for i in range(0, indices.size(), 3):
                        var i0 = indices[i]; var i1 = indices[i+1]; var i2 = indices[i+2]
                        if flip: 
                                st_out.add_index(i0 + idx_offset)
                                st_out.add_index(i1 + idx_offset)
                                st_out.add_index(i2 + idx_offset)
                        else:
                                st_out.add_index(i0 + idx_offset)
                                st_out.add_index(i2 + idx_offset)
                                st_out.add_index(i1 + idx_offset)
                                
        st_out.generate_normals()
        # generate_tangents() requires UVs; UV-less source meshes would spam
        # errors on every rebuild.
        if uvs != null and not uvs.is_empty(): st_out.generate_tangents()
        var mi = MeshInstance3D.new()
        mi.mesh = st_out.commit()
        mi.name = "Layer_%d_Deform" % idx
        add_child(mi, true)
        
        var root = get_tree().edited_scene_root if Engine.is_editor_hint() else null
        if root: mi.owner = root
        _nodes[idx] = mi

func _undo_redo() -> Variant:
        return editor_plugin.get_undo_redo() if is_instance_valid(editor_plugin) else null

func bake_to_nodes(shape_type: int = 0) -> void:
        if get_parent() == null:
                push_error("Ultimate Asset Placer: bake_to_nodes() aborted — the spline has no parent node to attach the baked result to.")
                return
        var root = owner if owner else get_tree().edited_scene_root
        if root == null:
                push_error("Ultimate Asset Placer: bake_to_nodes() aborted — no scene root found, so the baked nodes would not be saved with the scene.")
                return
        var bake_root = Node3D.new()
        bake_root.name = name + "_Baked"
        # add_child BEFORE any global-transform write: on an orphan node the
        # global setter silently writes into the local transform, which would
        # double the path's own world transform once the node enters the tree.
        get_parent().add_child(bake_root, true)
        bake_root.global_transform = global_transform
        bake_root.owner = root
        
        for i in range(_nodes.size()):
                var n = _nodes[i]
                if not is_instance_valid(n): continue
                
                var add_col = l_col_bake[i]
                
                if l_type[i] == LAYER_SCATTER:
                        var layer_node = Node3D.new(); layer_node.name = "Layer_%d_Scatter" % i
                        bake_root.add_child(layer_node, true); layer_node.owner = root
                        
                        if l_use_mm[i]: # Unpack MultiMesh
                                for mmi in n.get_children():
                                        var mm = (mmi as MultiMeshInstance3D).multimesh
                                        for j in mm.instance_count:
                                                var mi = MeshInstance3D.new()
                                                mi.mesh = mm.mesh
                                                mi.name = "Piece_%d" % j
                                                layer_node.add_child(mi, true); mi.owner = root
                                                mi.transform = mm.get_instance_transform(j)
                                                if add_col: _add_collision(mi, root, shape_type)
                        else: # Clone individual meshes
                                for old_mi in n.get_children():
                                        var mi = old_mi.duplicate()
                                        layer_node.add_child(mi, true); mi.owner = root
                                        if add_col: _add_collision(mi, root, shape_type)
                else:
                        var mi = n.duplicate()
                        mi.name = "Layer_%d_Deform" % i
                        bake_root.add_child(mi, true); mi.owner = root
                        if add_col: _add_collision(mi, root, shape_type)
                        
        _finish_bake("UAP: Bake Spline to Nodes", bake_root, root)

## Bakes all scatter layers as MultiMeshInstance3D nodes instead of individual
## MeshInstance3D nodes.  Deform layers are baked as regular MeshInstance3D
## (they are already a single merged mesh so MultiMesh would give no benefit).
## The spline Path3D is removed after baking, exactly like bake_to_nodes().
func bake_to_multimesh(shape_type: int = 0) -> void:
        if get_parent() == null:
                push_error("Ultimate Asset Placer: bake_to_multimesh() aborted — the spline has no parent node to attach the baked result to.")
                return
        var root = owner if owner else get_tree().edited_scene_root
        if root == null:
                push_error("Ultimate Asset Placer: bake_to_multimesh() aborted — no scene root found, so the baked nodes would not be saved with the scene.")
                return
        var bake_root = Node3D.new()
        bake_root.name = name + "_MMBaked"
        get_parent().add_child(bake_root, true)
        bake_root.global_transform = global_transform
        bake_root.owner = root

        for i in range(_nodes.size()):
                var n = _nodes[i]
                if not is_instance_valid(n): continue

                var add_col = l_col_bake[i]

                if l_type[i] == LAYER_SCATTER:
                        var layer_node = Node3D.new(); layer_node.name = "Layer_%d_MM" % i
                        bake_root.add_child(layer_node, true); layer_node.owner = root

                        if l_use_mm[i]:
                                # Already MultiMesh — clone the MMI nodes directly into the baked root.
                                for mmi_child in n.get_children():
                                        var src_mmi := mmi_child as MultiMeshInstance3D
                                        if src_mmi == null or src_mmi.multimesh == null: continue
                                        var new_mmi := MultiMeshInstance3D.new()
                                        new_mmi.name = src_mmi.name
                                        # Rebuild the MultiMesh resource explicitly instead of
                                        # duplicating it — .duplicate() can fail with a buffer-size
                                        # error. Instance-by-instance copying has no failure mode.
                                        var src_mm := src_mmi.multimesh
                                        var new_mm := MultiMesh.new()
                                        new_mm.transform_format = src_mm.transform_format
                                        new_mm.mesh = src_mm.mesh
                                        new_mm.instance_count = src_mm.instance_count
                                        for inst_idx in src_mm.instance_count:
                                                new_mm.set_instance_transform(inst_idx, src_mm.get_instance_transform(inst_idx))
                                        new_mmi.multimesh = new_mm
                                        layer_node.add_child(new_mmi, true); new_mmi.owner = root
                                        new_mmi.global_transform = src_mmi.global_transform
                                        if add_col:
                                                _add_multimesh_collision(new_mmi, root, shape_type)
                        else:
                                # Individual MeshInstance3D — gather all into one MultiMesh per mesh type.
                                # Group meshes by their Mesh resource so we produce one MMI per unique mesh.
                                var mesh_groups: Dictionary = {}
                                for old_mi_node in n.get_children():
                                        var old_mi := old_mi_node as MeshInstance3D
                                        if old_mi == null or old_mi.mesh == null: continue
                                        var key := old_mi.mesh.get_rid()
                                        if not mesh_groups.has(key):
                                                mesh_groups[key] = {"mesh": old_mi.mesh, "transforms": []}
                                        # Instance transforms are MMI-LOCAL space; convert the
                                        # source instances' world transforms into the new MMI's
                                        # local space (the new MMI sits at bake_root's origin).
                                        var rel: Transform3D = bake_root.global_transform.affine_inverse() * old_mi.global_transform
                                        mesh_groups[key]["transforms"].append(rel)

                                var group_idx := 0
                                for key in mesh_groups.keys():
                                        var gdata: Dictionary = mesh_groups[key]
                                        var mesh_res: Mesh = gdata["mesh"]
                                        var transforms: Array = gdata["transforms"]
                                        var mm := MultiMesh.new()
                                        mm.transform_format = MultiMesh.TRANSFORM_3D
                                        mm.mesh = mesh_res
                                        mm.instance_count = transforms.size()
                                        for t_idx in transforms.size():
                                                mm.set_instance_transform(t_idx, transforms[t_idx] as Transform3D)
                                        var new_mmi := MultiMeshInstance3D.new()
                                        new_mmi.name = "MMI_%d_%d" % [i, group_idx]
                                        new_mmi.multimesh = mm
                                        layer_node.add_child(new_mmi, true); new_mmi.owner = root
                                        if add_col:
                                                _add_multimesh_collision(new_mmi, root, shape_type)
                                        group_idx += 1
                else:
                        # Deform layers are already a single merged MeshInstance3D — no gain from MultiMesh.
                        var mi = n.duplicate()
                        mi.name = "Layer_%d_Deform" % i
                        bake_root.add_child(mi, true); mi.owner = root
                        if add_col: _add_collision(mi, root, shape_type)

        _finish_bake("UAP: Bake Spline to MultiMesh", bake_root, root)

func _finish_bake(action_name: String, bake_root: Node3D, root: Node) -> void:
        ## Shared tail of both bake paths. The path node is removed from the
        ## tree (NOT freed) and handed to the undo system: undo re-adds the
        ## spline and removes the baked root; redo reverses that again. The
        ## references keep both nodes alive while the action sits in history
        ## and free them once the action is erased.
        var parent := get_parent()
        var ur: Variant = _undo_redo()
        if ur == null:
                queue_free()
                return
        if is_instance_valid(parent) and is_inside_tree():
                parent.remove_child(self)
        _open_scene_undo_action(ur, action_name)
        ur.add_do_method(self, "_bake_redo", parent, bake_root)
        ur.add_undo_method(self, "_bake_undo", parent, bake_root)
        ur.add_undo_reference(self)
        ur.add_do_reference(bake_root)
        ur.commit_action(false)

func _bake_redo(parent: Node, bake_root: Node3D) -> void:
        if is_instance_valid(bake_root) and not bake_root.is_inside_tree() and is_instance_valid(parent):
                parent.add_child(bake_root)
        if is_instance_valid(parent) and is_inside_tree() and get_parent() == parent:
                parent.remove_child(self)

func _bake_undo(parent: Node, bake_root: Node3D) -> void:
        if is_instance_valid(bake_root) and bake_root.is_inside_tree():
                bake_root.get_parent().remove_child(bake_root)
        if not is_inside_tree() and is_instance_valid(parent):
                parent.add_child(self)
        _all_dirty = true

# Returns a Shape3D matching the plugin-wide collision shape type convention
# (0=Trimesh, 1=Convex, 2=Box, 3=Sphere, 4=Capsule) used across the whole addon.
func _make_shape(mesh: Mesh, shape_type: int) -> Shape3D:
        var a := mesh.get_aabb()
        match shape_type:
                1: return mesh.create_convex_shape(true, true)
                2:
                        var b := BoxShape3D.new(); b.size = a.size; return b
                3:
                        var s := SphereShape3D.new(); s.radius = maxf(a.size.x, maxf(a.size.y, a.size.z)) * 0.5; return s
                4:
                        var c := CapsuleShape3D.new(); c.radius = maxf(a.size.x, a.size.z) * 0.5
                        c.height = maxf(a.size.y, c.radius * 2.0)
                        return c
        return mesh.create_trimesh_shape()

func _shape_center(mesh: Mesh, shape_type: int) -> Vector3:
        return mesh.get_aabb().get_center() if shape_type in [2, 3, 4] else Vector3.ZERO

# Generates one StaticBody3D with a CollisionShape3D per MultiMesh instance,
# parented to the MultiMeshInstance3D node itself.
func _add_multimesh_collision(mmi: MultiMeshInstance3D, root: Node, shape_type: int = 0) -> void:
        var mm := mmi.multimesh
        if mm == null or mm.mesh == null or mm.instance_count == 0: return
        var shape := _make_shape(mm.mesh, shape_type)
        if shape == null: return
        var center := _shape_center(mm.mesh, shape_type)
        for idx in mm.instance_count:
                var sb := StaticBody3D.new()
                sb.name = "Collision_%d" % idx
                var cs := CollisionShape3D.new()
                cs.name = "Shape"
                cs.shape = shape
                # Both add_child calls MUST happen before either owner assignment:
                # setting cs.owner while sb is still an orphan fails validation
                # ("Owner must be an ancestor in the tree"), and anything that
                # never got an owner is silently dropped when the scene is saved.
                sb.add_child(cs, true)
                mmi.add_child(sb, true)
                sb.owner = root
                cs.owner = root
                # Instance transforms are MMI-local; compose with the MMI's world
                # transform for the body's world pose, and shift the shape so
                # primitive shapes wrap the mesh instead of its AABB origin.
                var inst_xf := mmi.global_transform * mm.get_instance_transform(idx)
                sb.global_transform = inst_xf
                cs.position = center

func _add_collision(mi: MeshInstance3D, root: Node, shape_type: int = 0) -> void:
        if not mi.mesh: return
        var shape = _make_shape(mi.mesh, shape_type)
        if not shape: return
        var sb = StaticBody3D.new()
        sb.name = mi.name + "_Collision"
        var cs = CollisionShape3D.new()
        cs.name = "Shape"
        cs.shape = shape
        cs.position = _shape_center(mi.mesh, shape_type)
        sb.add_child(cs, true)
        mi.add_child(sb, true)
        sb.owner = root
        cs.owner = root

func _extract_mesh(res: Resource) -> Mesh:
        if res is Mesh: return res
        if res is PackedScene:
                # instantiate() returns null for corrupt or failed imports.
                var tmp = (res as PackedScene).instantiate()
                if tmp == null: return null
                var m = _get_first_mesh(tmp); tmp.free()
                return m
        return null

func _get_first_mesh(node: Node) -> Mesh:
        if node is MeshInstance3D and node.mesh: return node.mesh
        if node is MultiMeshInstance3D:
                var mm := (node as MultiMeshInstance3D).multimesh
                if mm != null and mm.mesh != null: return mm.mesh
        for c in node.get_children():
                var m = _get_first_mesh(c)
                if m: return m
        return null
