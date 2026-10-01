@tool
extends Node

## Ultimate Asset Placer — Physics Placer (engine-driven)
##
## Lifts selected scene objects into the air, drops them with the project's
## own 3D physics engine (Jolt Physics, or Godot Physics when Jolt isn't
## installed), then bakes the result in place once every object settles.
##
## How it works inside the editor: the editor leaves the 3D physics server
## inactive, but the server is still ours to control. When a simulation
## starts we:
##   1. Create a private physics space (PhysicsServer3D.space_create()).
##   2. Build real rigid bodies in it — one per selected object — using the
##      object's existing collision shapes (scale-baked mirrors), or shapes
##      generated from its meshes when Auto-Add Missing Collision is on.
##   3. Mirror every solid collider in the scene (static geometry, terrain,
##      other props) into that space as STATIC bodies — including trimesh,
##      which is perfectly valid for static replicas.
##   4. Freeze the world's space (space_set_active(world, false)) so the
##      user's scene physics stays untouched, re-activate the physics server
##      (PhysicsServer3D.set_active(true)), and let the engine step the
##      private space on every physics tick — the same C++ solver,
##      broadphase, contact solver and sleeping system the game runtime
##      uses, at engine speed.
##   5. Poll each body's transform once per editor frame and write it back
##      onto the scene node. A body that falls asleep is settled; when every
##      body is settled the result is baked into an undoable action.
## Stopping restores the world space and the server's previous state and
## frees every RID. Nothing scene-side is ever created, so nothing
## temporary can leak into the saved .tscn even if the editor crashes
## mid-run. Contact manifolds and speculative contacts give exact rest
## heights (no floating on corners), and all broadphase/narrowphase/solver
## work happens inside the engine — GDScript only copies transforms.

const TEMP_META    := "_uap_temp_physics_body"   # legacy: temp bodies from ≤2.5.0 runs
const TEMP_NAME    := "__UAP_TempPhysicsCollision__"
const SETTLE_SPEED     := 0.02   # m/s linear — below this, the settle-hold timer runs
const SETTLE_ANG_SPEED := 0.15   # rad/s angular — same idea for spin
const SETTLE_HOLD      := 0.25   # seconds under the settle speeds before we call it landed
const SETTLE_MIN_TIME  := 0.3    # ignore the engine's sleeping flag before this much
                                  # sim time — a fresh body reports SLEEPING=true until
                                  # the engine integrates it once (observed on Jolt)
const WAKE_SPEED       := 0.08   # m/s — a settled body moving faster than this gets
                                  # resumed instead of staying baked mid-motion
const ROT_SETTLE_TIME  := 0.18   # seconds to ease the final ground-align tilt
const MAX_FALL_SPEED   := 60.0   # m/s cap — protects thin floors from tunneling sweeps
const MIN_SHAPE_SIZE   := 0.02   # smallest dimension any generated shape gets
const LARGE_BATCH_WARN := 300
const MAX_MASS         := 100000.0
const MIN_MASS         := 0.05

var editor_plugin: EditorPlugin = null
var panel:         Node         = null

var _running: bool = false
var _bodies:  Array[Dictionary] = []   # simulated objects (one rigid body each)
var _replicas: Array[Dictionary] = []  # static mirrors of the scene's own colliders
var _sim_root: Node = null
var _space: RID = RID()                # private physics space
var _world_space: RID = RID()          # the edited scene's world space (frozen while running)
var _world_was_active: bool = false
var _gravity_last: float = -1.0  # last gravity pushed to the space — changing an
                                 # area param WAKES every body in the space, so this
                                 # must only fire when the value actually changes

func _process(delta: float) -> void:
        if not Engine.is_editor_hint(): return
        if not _running: return
        _step(delta)


# ─── Public API — called by the Physics tab UI ────────────────────────────────

func is_running() -> bool: return _running

func lift_selected() -> void:
        if _running:
                _status("Stop or Cancel the current simulation before lifting more objects.", true)
                return
        var nodes := _selected_roots()
        if nodes.is_empty():
                _status("Select one or more objects in the scene first.", true)
                return

        var height     := _get_float("phys_lift_height")
        var scatter    := _get_bool("phys_lift_scatter")
        var scatter_r  := _get_float("phys_lift_scatter_radius")
        var rand_rot   := _get_bool("phys_lift_random_rot")

        var befores: Array[Transform3D] = []
        var afters:  Array[Transform3D] = []
        for n in nodes:
                var before := n.global_transform
                var after  := before
                after.origin.y += height
                if scatter:
                        after.origin.x += randf_range(-scatter_r, scatter_r)
                        after.origin.z += randf_range(-scatter_r, scatter_r)
                if rand_rot:
                        var s := before.basis.get_scale()
                        after.basis = Basis.from_euler(Vector3(
                                randf_range(0.0, TAU), randf_range(0.0, TAU), randf_range(0.0, TAU)
                        )).scaled(s)
                n.global_transform = after
                befores.append(before); afters.append(after)

        var ur: Variant = _undo_redo()
        if ur:
                ur.create_action("UAP: Lift Selected (%d)" % nodes.size())
                for i in nodes.size():
                        ur.add_do_method(self, "_apply_transform", nodes[i], afters[i])
                        ur.add_undo_method(self, "_apply_transform", nodes[i], befores[i])
                ur.commit_action(false)

        _status("Lifted %d object%s by %.2fm." % [nodes.size(), _plural(nodes.size()), height])

func start_simulation() -> void:
        if _running: return
        var nodes := _selected_roots()
        if nodes.is_empty():
                _status("Select one or more objects to simulate first.", true)
                return
        var scene_root := EditorInterface.get_edited_scene_root()
        if scene_root == null:
                _status("Open a 3D scene first.", true)
                return
        var world3d := scene_root.get_viewport().find_world_3d()
        if world3d == null:
                _status("The current scene has no 3D world to simulate in.", true)
                return
        if nodes.size() > LARGE_BATCH_WARN:
                push_warning("Ultimate Asset Placer: starting a physics simulation on %d objects at once — this can be slow. Consider dropping smaller batches." % nodes.size())

        _sim_root = scene_root
        _world3d = world3d
        _world_space = world3d.get_space()
        _world_was_active = _world_space.get_id() != 0 and PhysicsServer3D.space_is_active(_world_space)

        # Private space: the whole simulation happens in here. Gravity comes
        # from the space's own default area — the space RID doubles as its
        # handle for area_set_param on both GodotPhysics3D and Jolt.
        _space = PhysicsServer3D.space_create()
        PhysicsServer3D.space_set_active(_space, true)
        PhysicsServer3D.area_set_param(_space, PhysicsServer3D.AREA_PARAM_GRAVITY_VECTOR, Vector3.DOWN)
        _gravity_last = maxf(0.0, _get_float("phys_gravity"))
        PhysicsServer3D.area_set_param(_space, PhysicsServer3D.AREA_PARAM_GRAVITY, _gravity_last)

        _bodies.clear()
        _replicas.clear()
        var skipped := 0
        for n in nodes:
                var entry: Variant = _make_body_entry(n)
                if entry != null: _bodies.append(entry)
                else: skipped += 1

        if _bodies.is_empty():
                _teardown_space()
                _sim_root = null
                if skipped > 0:
                        _status("Skipped all %d object%s — no collision and Auto-Add Missing Collision is off." % [skipped, _plural(skipped)], true)
                else:
                        _status("Nothing usable in the current selection.", true)
                return

        # Mirror the rest of the scene (static level geometry, terrain, props NOT
        # being simulated) into the private space so the falling objects have a
        # world to land on. Their own subtrees are excluded — a falling object
        # collides with its own shapes only via its own rigid body.
        _replicas = _build_static_replicas(scene_root)

        # Freeze the user's world so nothing scene-side gets simulated behind
        # their back, then re-activate the physics server: from this moment the
        # engine steps our private space on every physics tick, in C++.
        if _world_space.get_id() != 0:
                PhysicsServer3D.space_set_active(_world_space, false)
        PhysicsServer3D.set_active(true)

        _running = true
        _notify_state(true)
        if skipped > 0:
                _status("Simulating %d object%s (%d skipped — no collision)…" % [_bodies.size(), _plural(_bodies.size()), skipped])
        else:
                _status("Simulating %d object%s…" % [_bodies.size(), _plural(_bodies.size())])

func stop_simulation() -> void:
        _finish(true)

func cancel_simulation() -> void:
        _finish(false)

func get_progress_text() -> String:
        if not _running or _bodies.is_empty(): return ""
        var done := 0
        for e in _bodies:
                if e.get("done", false): done += 1
        return "%d / %d settled" % [done, _bodies.size()]


# ─── Per-frame polling ────────────────────────────────────────────────────────

func _step(delta: float) -> void:
        if _sim_root != null and EditorInterface.get_edited_scene_root() != _sim_root:
                # Scene tab changed out from under us — bake wherever things are
                # rather than keep moving nodes in a scene the user can no longer see.
                _finish(true)
                return
        var root := EditorInterface.get_edited_scene_root()
        if root == null:
                _finish(true)
                return

        # Live gravity: the Gravity slider works while the sim runs. Only pushed
        # when the value actually changes — setting an area parameter wakes every
        # body in the space, so pushing it every frame would stop anything from
        # ever sleeping (and therefore from ever settling).
        var g_now := maxf(0.0, _get_float("phys_gravity"))
        if g_now != _gravity_last:
                _gravity_last = g_now
                PhysicsServer3D.area_set_param(_space, PhysicsServer3D.AREA_PARAM_GRAVITY, _gravity_last)

        var align_ground := _get_bool("phys_align_to_ground")
        var max_fall := maxf(1.0, _get_float("phys_max_fall_time"))
        var dt := minf(delta, 0.1)

        for entry in _bodies:
                if entry.get("done", false):
                        # Wake-watch: a body we already settled can be woken again by a later
                        # impact (the engine sleeps and wakes bodies on its own). Resume it
                        # so its node keeps following the physics until the very end.
                        if float(entry.get("elapsed", 0.0)) > SETTLE_MIN_TIME \
                                        and not bool(PhysicsServer3D.body_get_state(entry["rid"], PhysicsServer3D.BODY_STATE_SLEEPING)):
                                var wlv := PhysicsServer3D.body_get_state(entry["rid"], PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY) as Vector3
                                var wav := PhysicsServer3D.body_get_state(entry["rid"], PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY) as Vector3
                                if wlv.length() > WAKE_SPEED or wav.length() > WAKE_SPEED:
                                        entry["settled"] = false
                                        entry["done"] = false
                                        entry["settle_timer"] = 0.0
                                        entry["elapsed"] = 0.0
                                        continue
                        continue
                var node: Node3D = entry["node"]
                if not is_instance_valid(node):
                        _release_body(entry)
                        entry["done"] = true
                        continue

                if entry.get("settled", false):
                        # Physics finished for this object; it may still be easing its
                        # final ground-align tilt (a node-side, visual-only rotation).
                        _step_settle_rotation(entry, node, dt)
                        continue

                entry["elapsed"] = float(entry["elapsed"]) + dt

                # Pull the authoritative transform from the engine and write it onto
                # the scene node. Scale is re-glued on the node side (the physics body
                # itself is scale-free — scale was baked into its shapes at start).
                var t := PhysicsServer3D.body_get_state(entry["rid"], PhysicsServer3D.BODY_STATE_TRANSFORM) as Transform3D
                var last := entry.get("last_body_t") as Transform3D
                if not t.is_equal_approx(last):
                        node.global_transform = Transform3D(t.basis * (entry["scale_basis"] as Basis), t.origin)
                        entry["last_body_t"] = t

                # Terminal velocity: clamp linear speed so a very long fall can never
                # build up enough speed to sweep through thin geometry.
                var lv := PhysicsServer3D.body_get_state(entry["rid"], PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY) as Vector3
                if lv.length() > MAX_FALL_SPEED:
                        PhysicsServer3D.body_set_state(entry["rid"], PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, lv.limit_length(MAX_FALL_SPEED))

                # Engine says asleep -> truly at rest, nothing left to do.
                # Ignored for the first moments: a fresh body reports
                # SLEEPING=true until the engine has integrated it at least
                # once (observed on Jolt).
                if float(entry["elapsed"]) > SETTLE_MIN_TIME \
                                and bool(PhysicsServer3D.body_get_state(entry["rid"], PhysicsServer3D.BODY_STATE_SLEEPING)):
                        _mark_settled(entry, node, align_ground)
                        continue

                # Safety net: an object that never lands (fell off the world, into an
                # endless shaft, etc.) stops after Max Fall Time instead of simulating
                # forever. Hard-sleeping it parks it exactly where it is — a sleeping
                # body integrates nothing, so it simply hovers — and if anything real
                # later hits it, the wake-watch above resumes the object honestly.
                if float(entry["elapsed"]) > max_fall:
                        if not entry.get("warned_no_land", false):
                                entry["warned_no_land"] = true
                                push_warning("Ultimate Asset Placer: '%s' fell for %.0fs without landing on anything — stopped in place. Make sure there is collision beneath it." % [node.name, max_fall])
                        PhysicsServer3D.body_set_state(entry["rid"], PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
                        PhysicsServer3D.body_set_state(entry["rid"], PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
                        PhysicsServer3D.body_set_state(entry["rid"], PhysicsServer3D.BODY_STATE_SLEEPING, true)
                        _mark_settled(entry, node, align_ground)
                        continue

                # Velocity-based settle (engines without aggressive sleeping, or
                # bodies still barely creeping): hold under the settle speeds for a
                # moment, then treat it as landed.
                var av := PhysicsServer3D.body_get_state(entry["rid"], PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY) as Vector3
                if lv.length() < SETTLE_SPEED and av.length() < SETTLE_ANG_SPEED:
                        entry["settle_timer"] = float(entry["settle_timer"]) + dt
                        if float(entry["settle_timer"]) >= SETTLE_HOLD:
                                _mark_settled(entry, node, align_ground)
                                continue
                else:
                        entry["settle_timer"] = 0.0

        # Authoritative "everything finished" check — covers objects that were
        # still easing their settle rotation on earlier frames, too.
        var all_done := true
        for entry in _bodies:
                if not entry.get("done", false):
                        all_done = false
                        break
        if all_done:
                if _get_bool("phys_auto_stop"):
                        _finish(true)
                else:
                        _status("All objects have settled. Press Stop to bake the result.")
        else:
                _status(get_progress_text())

func _mark_settled(entry: Dictionary, node: Node3D, align_ground: bool) -> void:
        entry["settled"] = true
        entry["settle_timer"] = 0.0
        # The body itself is left exactly as the engine has it — sleeping bodies
        # cost nothing and stay parked, and the wake-watch in _step resumes any
        # settled object that a later impact genuinely moves again. No mode
        # switches, no server mutations: the engine owns its bodies end to end.
        if align_ground:
                var normal := _support_normal(entry)
                var basis := node.global_basis
                if basis.y.dot(normal) < 0.999:
                        entry["settling_rotation"] = true
                        entry["rot_from"] = basis
                        entry["rot_to"] = _align_up_preserve_yaw(basis, normal)
                        entry["rot_t"] = 0.0
                        return
        entry["done"] = true

func _support_normal(entry: Dictionary) -> Vector3:
        ## One-shot query at settle time: the contact normal of whatever the
        ## object is resting on, used by Align to Ground. Falls back to UP.
        if _space.get_id() == 0 or entry["shapes"].is_empty():
                return Vector3.UP
        var space_state := PhysicsServer3D.space_get_direct_state(_space)
        if space_state == null:
                return Vector3.UP
        var node: Node3D = entry["node"]
        if not is_instance_valid(node):
                return Vector3.UP
        var t := PhysicsServer3D.body_get_state(entry["rid"], PhysicsServer3D.BODY_STATE_TRANSFORM) as Transform3D
        var first: Dictionary = entry["shapes"][0]
        var params := PhysicsShapeQueryParameters3D.new()
        params.shape_rid = (first["shape"] as Shape3D).get_rid()
        # Body world pose composed with the shape's own body-local placement
        # (per-part shapes sit away from the body origin).
        params.transform = Transform3D(t.basis, t.origin) * (first["xform"] as Transform3D)
        params.collide_with_bodies = true
        params.collide_with_areas = false
        params.exclude = []
        var rest := space_state.get_rest_info(params)
        if rest.is_empty() or not rest.has("normal"):
                return Vector3.UP
        var n: Vector3 = rest["normal"]
        return n if n != Vector3.ZERO else Vector3.UP

func _step_settle_rotation(entry: Dictionary, node: Node3D, dt: float) -> void:
        if not entry.get("settling_rotation", false):
                entry["done"] = true
                return
        entry["rot_t"] = float(entry["rot_t"]) + dt / ROT_SETTLE_TIME
        var t: float = clampf(float(entry["rot_t"]), 0.0, 1.0)
        var from_b: Basis = entry["rot_from"]
        var to_b:   Basis = entry["rot_to"]
        node.global_basis = from_b.slerp(to_b, ease(t, -2.0))
        if t >= 1.0:
                entry["settling_rotation"] = false
                entry["done"] = true

func _apply_transform(node: Node3D, xform: Transform3D) -> void:
        if is_instance_valid(node): node.global_transform = xform

func _finish(keep: bool) -> void:
        if not _running and _bodies.is_empty() and _space.get_id() == 0: return
        _running = false

        # Teardown order matters and is the one proven safe against the Jolt
        # module in 4.7.1: stop all stepping FIRST, then detach + free every
        # private body and the space itself, and only then unfreeze the scene's
        # own space. Restoring the world space any earlier lets the engine step
        # it while our private bodies still exist, and freeing bodies after that
        # crashes inside Jolt.
        # Deactivate the server FIRST so nothing moves while we restore nodes.
        PhysicsServer3D.set_active(false)

        # Node-side restore / undo snapshot — must run BEFORE _teardown_space()
        # clears the entry list, and touches no server state.
        var changed: Array[Dictionary] = []
        for entry in _bodies:
                var node: Node3D = entry["node"]
                if is_instance_valid(node):
                        if not keep:
                                node.global_transform = entry["start_xform"]
                        elif node.global_transform != (entry["start_xform"] as Transform3D):
                                changed.append(entry)

        if keep and not changed.is_empty():
                var ur: Variant = _undo_redo()
                if ur:
                        ur.create_action("UAP: Physics Simulation (%d object%s)" % [changed.size(), _plural(changed.size())])
                        for entry in changed:
                                var node: Node3D = entry["node"]
                                ur.add_do_method(self, "_apply_transform", node, node.global_transform)
                                ur.add_undo_method(self, "_apply_transform", node, entry["start_xform"])
                        ur.commit_action(false)

        # Server-side teardown while the server is inactive and the world space
        # is still frozen — the sequence proven safe against the Jolt module —
        # then hand the world back exactly as the editor had it.
        _teardown_space()
        if _world_space.get_id() != 0 and _world_was_active:
                PhysicsServer3D.space_set_active(_world_space, true)

        var n := _bodies.size()
        _bodies.clear()
        _replicas.clear()
        _sim_root = null
        _notify_state(false)
        if keep:
                _status("Physics stopped — %d object%s settled in place." % [n, _plural(n)])
        else:
                _status("Simulation cancelled — objects restored.")

func _release_body(entry: Dictionary) -> void:
        ## The scene node vanished mid-sim (deleted, undone away, scene switched):
        ## its physics body has nothing left to drive, so free it immediately.
        _release_rid(entry.get("rid", RID()))
        entry["rid"] = RID()

func _release_rid(rid: RID) -> void:
        ## Frees a body RID safely: DETACH it from its space first. Freeing a body
        ## that is still registered in a space — and especially one currently
        ## in active contact with other bodies — crashes inside the Jolt
        ## module. Detaching drops it out of every contact island, after
        ## which freeing is safe.
        if rid.get_id() == 0:
                return
        if PhysicsServer3D.body_get_space(rid).get_id() != 0:
                PhysicsServer3D.body_set_space(rid, RID())
        PhysicsServer3D.free_rid(rid)

func _teardown_space() -> void:
        for entry in _bodies:
                _release_rid(entry.get("rid", RID()))
        for rep in _replicas:
                _release_rid(rep.get("rid", RID()))
        _bodies.clear()
        _replicas.clear()
        if _space.get_id() != 0:
                PhysicsServer3D.free_rid(_space)
        _space = RID()
        _world_space = RID()


# ─── Building a simulated body from a scene node ──────────────────────────────

func _make_body_entry(node: Node3D) -> Variant:
        if not is_instance_valid(node): return null

        # Clean up any leftover temporary collision from an older plugin
        # version before measuring anything (the engine-driven approach
        # creates no scene nodes at all).
        for c in node.get_children():
                if c is Node and (c as Node).has_meta(TEMP_META):
                        node.remove_child(c); (c as Node).free()

        var meshes: Array = []
        _collect_meshes(node, meshes)

        var existing: Array = []
        _collect_solid_bodies(node, existing)
        var shape_nodes := _collect_shape_nodes(existing)
        var had_existing_collision := not shape_nodes.is_empty()

        if not had_existing_collision and not _get_bool("phys_auto_add_collision"):
                # Auto-Add Missing Collision is off and this object has nothing of
                # its own to fall or land on — skip it rather than guess.
                return null

        var body_origin := node.global_position
        var body_basis := node.global_basis.orthonormalized()
        var body_inv := Transform3D(body_basis, body_origin).affine_inverse()

        var shapes: Array[Dictionary] = []
        if had_existing_collision:
                if _all_shapes_convex_safe(shape_nodes):
                        for cs in shape_nodes:
                                var m := _mirror_convex_shape((cs as CollisionShape3D).shape, body_inv * (cs as CollisionShape3D).global_transform)
                                if not m.is_empty(): shapes.append(m)
                else:
                        # Compound or concave existing collision (trimesh etc.) — a concave
                        # shape is not valid on a moving rigid body, so build convex hulls
                        # from the actual meshes instead ("Convex Hull" semantics).
                        shapes = _hull_shapes_from_meshes(meshes, body_inv)
                        if shapes.is_empty():
                                # No meshes to hull — fall back to a primitive around the
                                # existing collision's own bounds rather than dropping the
                                # object from the simulation.
                                shapes = _primitive_shapes_from_shape_bounds(shape_nodes, body_inv)
        if shapes.is_empty():
                # No existing collision — Auto Shape builds from the real mesh parts.
                shapes = _auto_shapes_from_meshes(meshes, body_inv, _get_int("phys_auto_shape"))
        if shapes.is_empty():
                # No meshes either (empty parent Node3D) — same 0.5 m box the old
                # version's temp collision used as its last-resort fallback.
                var box := BoxShape3D.new()
                box.size = Vector3(0.5, 0.5, 0.5)
                shapes = [{"shape": box, "xform": Transform3D(Basis(), Vector3.ZERO)}]

        # World-space AABB (rotation-only frame) for the mass estimate.
        var volume := _estimate_volume(node, meshes, body_basis)

        var rid := PhysicsServer3D.body_create()
        PhysicsServer3D.body_set_mode(rid, PhysicsServer3D.BODY_MODE_RIGID)
        PhysicsServer3D.body_set_space(rid, _space)
        for s in shapes:
                PhysicsServer3D.body_add_shape(rid, (s["shape"] as Shape3D).get_rid(), s["xform"])
        PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(body_basis, body_origin))
        PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_CAN_SLEEP, true)
        # A brand-new body reports SLEEPING=true until the engine integrates
        # it for the first time (observed on Jolt). Wake it explicitly so the
        # first settle check cannot freeze the object before it ever moved.
        PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_SLEEPING, false)
        PhysicsServer3D.body_set_collision_layer(rid, 1)
        PhysicsServer3D.body_set_collision_mask(rid, 1)
        PhysicsServer3D.body_set_param(rid, PhysicsServer3D.BODY_PARAM_MASS, clampf(volume, MIN_MASS, MAX_MASS))
        PhysicsServer3D.body_set_param(rid, PhysicsServer3D.BODY_PARAM_BOUNCE, clampf(_get_float("phys_bounciness"), 0.0, 1.0))
        PhysicsServer3D.body_set_param(rid, PhysicsServer3D.BODY_PARAM_FRICTION, clampf(_get_float("phys_friction"), 0.0, 1.0))
        # Rolling resistance: a perfect sphere on a plane rolls forever in an
        # ideal solver (no rolling friction exists in real-time engines), so
        # balls would spin in place indefinitely and never look "settled".
        # Light damping stands in for real-world rolling resistance — heavy
        # enough that dropped piles visibly come to rest, light enough that
        # falls, bounces and tumbles still read as physics.
        PhysicsServer3D.body_set_param(rid, PhysicsServer3D.BODY_PARAM_ANGULAR_DAMP, 3.0)
        PhysicsServer3D.body_set_param(rid, PhysicsServer3D.BODY_PARAM_LINEAR_DAMP, 0.3)
        if _get_bool("phys_random_tumble"):
                var axis := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
                if axis.length_squared() < 0.0001: axis = Vector3.UP
                PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY,
                        axis.normalized() * deg_to_rad(randf_range(50.0, 200.0)))

        return {
                "node": node,
                "rid": rid,
                "start_xform": node.global_transform,
                # Scale re-glued onto the node: physics runs on a scale-free body, and
                # the node's own scale (which the visual mesh keeps) rides in here.
                "scale_basis": body_basis.inverse() * node.global_basis,
                "shapes": shapes,
                "last_body_t": Transform3D(body_basis, body_origin),
                "settled": false,
                "done": false,
                "settle_timer": 0.0,
                "elapsed": 0.0,
                "settling_rotation": false,
                "warned_no_land": false,
        }

func _collect_shape_nodes(existing: Array) -> Array:
        ## Every CollisionShape3D with a shape under the given collision bodies.
        var out: Array = []
        for b in existing:
                _collect_shape_nodes_rec(b, out)
        return out

func _collect_shape_nodes_rec(node: Node, out: Array) -> void:
        if node is CollisionShape3D and (node as CollisionShape3D).shape != null:
                out.append(node)
        for c in node.get_children():
                _collect_shape_nodes_rec(c, out)

func _all_shapes_convex_safe(shape_nodes: Array) -> bool:
        ## Convex primitives and hulls are valid on a MOVING body. Trimesh,
        ## heightmaps, infinite planes and ray shapes are not.
        for cs in shape_nodes:
                var shp: Shape3D = (cs as CollisionShape3D).shape
                if shp is ConcavePolygonShape3D or shp is HeightMapShape3D \
                                or shp is WorldBoundaryShape3D or shp is SeparationRayShape3D:
                        return false
        return true

func _mirror_convex_shape(shp: Shape3D, t: Transform3D) -> Dictionary:
        ## Copy a convex shape into body-local space with the transform's scale
        ## BAKED into the shape data (physics bodies run scale-free). Returns
        ## {"shape": copy, "xform": rotation-only local transform}, or {} when
        ## the shape type can't ride a moving body.
        var rot := t.basis.orthonormalized()
        var scl := t.basis.get_scale().abs()
        var uni := (scl.x + scl.y + scl.z) / 3.0
        if uni <= 0.0001: uni = 1.0
        if shp is SphereShape3D:
                var s := SphereShape3D.new()
                s.radius = maxf((shp as SphereShape3D).radius * uni, MIN_SHAPE_SIZE)
                return {"shape": s, "xform": Transform3D(rot, t.origin)}
        if shp is BoxShape3D:
                var b := BoxShape3D.new()
                var sz: Vector3 = (shp as BoxShape3D).size * scl
                b.size = Vector3(maxf(sz.x, MIN_SHAPE_SIZE), maxf(sz.y, MIN_SHAPE_SIZE), maxf(sz.z, MIN_SHAPE_SIZE))
                return {"shape": b, "xform": Transform3D(rot, t.origin)}
        if shp is CapsuleShape3D:
                var c := CapsuleShape3D.new()
                c.radius = maxf((shp as CapsuleShape3D).radius * maxf((scl.x + scl.z) * 0.5, 0.0), MIN_SHAPE_SIZE)
                c.height = maxf((shp as CapsuleShape3D).height * scl.y, c.radius * 2.0 + MIN_SHAPE_SIZE)
                return {"shape": c, "xform": Transform3D(rot, t.origin)}
        if shp is CylinderShape3D:
                var cy := CylinderShape3D.new()
                cy.radius = maxf((shp as CylinderShape3D).radius * maxf((scl.x + scl.z) * 0.5, 0.0), MIN_SHAPE_SIZE)
                cy.height = maxf((shp as CylinderShape3D).height * scl.y, MIN_SHAPE_SIZE)
                return {"shape": cy, "xform": Transform3D(rot, t.origin)}
        if shp is ConvexPolygonShape3D:
                var pts := PackedVector3Array()
                for p in (shp as ConvexPolygonShape3D).points:
                        pts.append(t * p)
                if pts.size() < 4: return {}
                var cp := ConvexPolygonShape3D.new()
                cp.points = pts
                return {"shape": cp, "xform": Transform3D(rot, t.origin)}
        return {}

func _hull_shapes_from_meshes(meshes: Array, body_inv: Transform3D) -> Array[Dictionary]:
        ## One convex hull per mesh part, in body-local space. Godot's own hull
        ## reduction (create_convex_shape with simplify) keeps only the vertices
        ## that define the shape — accurate AND cheap for the solver.
        var out: Array[Dictionary] = []
        for mi_raw in meshes:
                var mi := mi_raw as MeshInstance3D
                if mi.mesh == null: continue
                var hull := mi.mesh.create_convex_shape(true, true)
                if hull == null: continue
                var pts := PackedVector3Array()
                for p in hull.points:
                        pts.append(body_inv * mi.global_transform * p)
                if pts.size() < 4: continue
                var cp := ConvexPolygonShape3D.new()
                cp.points = pts
                out.append({"shape": cp, "xform": Transform3D(Basis(), Vector3.ZERO)})
        return out

func _primitive_shapes_from_shape_bounds(shape_nodes: Array, body_inv: Transform3D) -> Array[Dictionary]:
        ## Last resort when existing collision exists but nothing could be mirrored
        ## or hulled: one box around the combined bounds of that collision.
        var found := false
        var aabb := AABB()
        for cs in shape_nodes:
                var local := body_inv * (cs as CollisionShape3D).global_transform
                var sb := _shape_local_aabb((cs as CollisionShape3D).shape)
                for corner in _aabb_corners(sb):
                        var p := local * corner
                        if not found: aabb = AABB(p, Vector3.ZERO); found = true
                        else: aabb = aabb.expand(p)
        if not found: return []
        var b := BoxShape3D.new()
        b.size = Vector3(maxf(aabb.size.x, MIN_SHAPE_SIZE), maxf(aabb.size.y, MIN_SHAPE_SIZE), maxf(aabb.size.z, MIN_SHAPE_SIZE))
        return [{"shape": b, "xform": Transform3D(Basis(), aabb.get_center())}]

func _auto_shapes_from_meshes(meshes: Array, body_inv: Transform3D, shape_type: int) -> Array[Dictionary]:
        ## Auto Shape — one shape per mesh part, sized from the part's real
        ## geometry, scale-baked into body-local space. 0 Box, 1 Sphere,
        ## 2 Capsule, 3 Convex Hull (Accurate).
        var out: Array[Dictionary] = []
        for mi_raw in meshes:
                var mi := mi_raw as MeshInstance3D
                if mi.mesh == null: continue
                var aabb := mi.mesh.get_aabb()
                if shape_type == 3:
                        var hull := mi.mesh.create_convex_shape(true, true)
                        if hull != null and hull.points.size() >= 4:
                                var pts := PackedVector3Array()
                                for p in hull.points:
                                        pts.append(body_inv * mi.global_transform * p)
                                var cp := ConvexPolygonShape3D.new()
                                cp.points = pts
                                out.append({"shape": cp, "xform": Transform3D(Basis(), Vector3.ZERO)})
                        continue
                var t := body_inv * mi.global_transform
                var rot := t.basis.orthonormalized()
                var scl := t.basis.get_scale().abs()
                var uni := (scl.x + scl.y + scl.z) / 3.0
                if uni <= 0.0001: uni = 1.0
                var size := Vector3(scl.x * aabb.size.x, scl.y * aabb.size.y, scl.z * aabb.size.z)
                size = size.abs()
                var center := t * aabb.get_center()
                if shape_type == 1:
                        var s := SphereShape3D.new()
                        s.radius = maxf(maxf(size.x, maxf(size.y, size.z)) * 0.5, MIN_SHAPE_SIZE)
                        out.append({"shape": s, "xform": Transform3D(rot, center)})
                elif shape_type == 2:
                        var c := CapsuleShape3D.new()
                        c.radius = maxf(maxf(size.x, size.z) * 0.5, MIN_SHAPE_SIZE)
                        c.height = maxf(size.y, c.radius * 2.0 + MIN_SHAPE_SIZE)
                        out.append({"shape": c, "xform": Transform3D(rot, center)})
                else:
                        var b := BoxShape3D.new()
                        b.size = Vector3(maxf(size.x, MIN_SHAPE_SIZE), maxf(size.y, MIN_SHAPE_SIZE), maxf(size.z, MIN_SHAPE_SIZE))
                        out.append({"shape": b, "xform": Transform3D(rot, center)})
        return out

func _shape_local_aabb(shp: Shape3D) -> AABB:
        ## Loose bounds of any shape in its own local space (for fallback boxes).
        if shp is SphereShape3D:
                var r := (shp as SphereShape3D).radius
                return AABB(Vector3(-r, -r, -r), Vector3(r * 2, r * 2, r * 2))
        if shp is BoxShape3D:
                var s := (shp as BoxShape3D).size
                return AABB(-s * 0.5, s)
        if shp is CapsuleShape3D:
                var c := (shp as CapsuleShape3D)
                return AABB(Vector3(-c.radius, -c.height * 0.5, -c.radius), Vector3(c.radius * 2, c.height, c.radius * 2))
        if shp is CylinderShape3D:
                var cy := (shp as CylinderShape3D)
                return AABB(Vector3(-cy.radius, -cy.height * 0.5, -cy.radius), Vector3(cy.radius * 2, cy.height, cy.radius * 2))
        if shp is ConvexPolygonShape3D:
                var pts := (shp as ConvexPolygonShape3D).points
                if pts.is_empty(): return AABB(Vector3(-0.25, -0.25, -0.25), Vector3(0.5, 0.5, 0.5))
                var a := AABB(pts[0], Vector3.ZERO)
                for p in pts: a = a.expand(p)
                return a
        if shp is ConcavePolygonShape3D:
                var faces := (shp as ConcavePolygonShape3D).get_faces()
                if faces.is_empty(): return AABB(Vector3(-0.25, -0.25, -0.25), Vector3(0.5, 0.5, 0.5))
                var a2 := AABB(faces[0], Vector3.ZERO)
                for p in faces: a2 = a2.expand(p)
                return a2
        return AABB(Vector3(-0.25, -0.25, -0.25), Vector3(0.5, 0.5, 0.5))

func _estimate_volume(node: Node3D, meshes: Array, body_basis: Basis) -> float:
        ## AABB-volume mass estimate (uniform density): bigger objects are
        ## genuinely heavier, which is what makes mixed piles settle correctly.
        ## Falls back to the node's own size when there are no meshes.
        var body_inv := Transform3D(body_basis, node.global_position).affine_inverse()
        var found := false
        var aabb := AABB()
        for mi_raw in meshes:
                var mi := mi_raw as MeshInstance3D
                if mi.mesh == null: continue
                var rel := body_inv * mi.global_transform
                for c in _aabb_corners(mi.mesh.get_aabb()):
                        var p := rel * c
                        if not found: aabb = AABB(p, Vector3.ZERO); found = true
                        else: aabb = aabb.expand(p)
        if not found:
                aabb = AABB(Vector3(-0.25, -0.25, -0.25), Vector3(0.5, 0.5, 0.5))
        return maxf(aabb.size.x * aabb.size.y * aabb.size.z, 0.001)


# ─── Mirroring the scene's static world into the private space ───────────────

func _build_static_replicas(scene_root: Node) -> Array[Dictionary]:
        ## Every solid collider in the scene that is NOT part of a simulated
        ## object becomes a static body in the private space — this is the world
        ## the falling objects land on. Concave (trimesh) shapes are perfectly
        ## valid here and are mirrored face-for-face.
        var sim_set := {}
        for entry in _bodies:
                sim_set[entry["node"]] = true
        var out: Array[Dictionary] = []
        _walk_replicas(scene_root, sim_set, out)
        return out

func _walk_replicas(node: Node, sim_set: Dictionary, out: Array[Dictionary]) -> void:
        ## Never walk into a simulated object's subtree — its shapes belong to its
        ## own rigid body, not to the static environment.
        if sim_set.has(node):
                return
        if node is CollisionObject3D and not (node is Area3D) and not (node as Node).has_meta(TEMP_META):
                var shape_nodes: Array = []
                _collect_shape_nodes_excl(node, sim_set, shape_nodes)
                if not shape_nodes.is_empty():
                        out.append(_build_replica_body(node, shape_nodes))
                        return  # everything under this body is already covered
        for c in node.get_children():
                _walk_replicas(c, sim_set, out)

func _collect_shape_nodes_excl(node: Node, sim_set: Dictionary, out: Array) -> void:
        ## Same as _collect_shape_nodes_rec but stops at simulated subtrees.
        if sim_set.has(node):
                return
        if node is CollisionShape3D and (node as CollisionShape3D).shape != null:
                out.append(node)
                return
        for c in node.get_children():
                _collect_shape_nodes_excl(c, sim_set, out)

func _build_replica_body(body: CollisionObject3D, shape_nodes: Array) -> Dictionary:
        var origin := body.global_position
        var basis := body.global_basis.orthonormalized()
        var body_inv := Transform3D(basis, origin).affine_inverse()
        var rid := PhysicsServer3D.body_create()
        PhysicsServer3D.body_set_mode(rid, PhysicsServer3D.BODY_MODE_STATIC)
        PhysicsServer3D.body_set_space(rid, _space)
        PhysicsServer3D.body_set_collision_layer(rid, 1)
        PhysicsServer3D.body_set_collision_mask(rid, 1)
        var kept: Array[Dictionary] = []
        for cs in shape_nodes:
                var shp: Shape3D = (cs as CollisionShape3D).shape
                var t := body_inv * (cs as CollisionShape3D).global_transform
                if shp is ConcavePolygonShape3D:
                        # Mirror the trimesh face-for-face, transform's scale baked in.
                        var faces := (shp as ConcavePolygonShape3D).get_faces()
                        if faces.is_empty(): continue
                        var out_pts := PackedVector3Array()
                        for p in faces:
                                out_pts.append(t * p)
                        var copy := ConcavePolygonShape3D.new()
                        copy.set_faces(out_pts)
                        var rec := {"shape": copy, "xform": Transform3D(Basis(), Vector3.ZERO)}
                        PhysicsServer3D.body_add_shape(rid, copy.get_rid(), rec["xform"])
                        kept.append(rec)
                elif shp is HeightMapShape3D or shp is WorldBoundaryShape3D or shp is SeparationRayShape3D:
                        # No practical scale-bake for these — attach the original shape
                        # with the full (possibly scaled) transform; engines tolerate it.
                        PhysicsServer3D.body_add_shape(rid, shp.get_rid(), t)
                        kept.append({"shape": shp, "xform": t})
                else:
                        var m := _mirror_convex_shape(shp, t)
                        if m.is_empty(): continue
                        PhysicsServer3D.body_add_shape(rid, (m["shape"] as Shape3D).get_rid(), m["xform"])
                        kept.append(m)
        PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(basis, origin))
        return {"rid": rid, "shapes": kept}


# ─── Selection / scene helpers ────────────────────────────────────────────────

func _selected_roots() -> Array[Node3D]:
        var sel := EditorInterface.get_selection().get_selected_nodes()
        var root := EditorInterface.get_edited_scene_root()
        var raw: Array[Node3D] = []
        for n in sel:
                if n is Node3D and is_instance_valid(n) and n != root and not (n as Node).has_meta(TEMP_META):
                        raw.append(n as Node3D)
        var out: Array[Node3D] = []
        for n in raw:
                var is_descendant := false
                for m in raw:
                        if m == n: continue
                        if _is_ancestor_of(m, n): is_descendant = true; break
                if not is_descendant: out.append(n)
        return out

func _is_ancestor_of(maybe_ancestor: Node, node: Node) -> bool:
        var p := node.get_parent()
        while p != null:
                if p == maybe_ancestor: return true
                p = p.get_parent()
        return false

func _collect_meshes(node: Node, out: Array) -> void:
        if node is MeshInstance3D: out.append(node)
        for c in node.get_children(): _collect_meshes(c, out)

func _collect_solid_bodies(node: Node, out: Array) -> void:
        if node is PhysicsBody3D and _has_valid_shape(node):
                out.append(node)
        for c in node.get_children(): _collect_solid_bodies(c, out)

func _has_valid_shape(body: Node) -> bool:
        for c in body.get_children():
                if c is CollisionShape3D and (c as CollisionShape3D).shape != null:
                        return true
        return false

func _aabb_corners(a: AABB) -> Array[Vector3]:
        var c: Array[Vector3] = []
        for cx in [0,1]:
                for cy in [0,1]:
                        for cz in [0,1]:
                                c.append(a.position + Vector3(a.size.x*cx, a.size.y*cy, a.size.z*cz))
        return c

func _align_up_preserve_yaw(basis: Basis, normal: Vector3) -> Basis:
        ## Builds a basis whose up axis is `normal`, keeping as much of the
        ## object's current facing as possible (projected onto the new ground
        ## plane) so it tilts to match a slope instead of spinning to face a
        ## new direction.
        var up_new := normal.normalized()
        var fwd_old := -basis.z
        var fwd_proj := fwd_old - up_new * fwd_old.dot(up_new)
        if fwd_proj.length_squared() < 0.0001:
                fwd_proj = basis.x - up_new * basis.x.dot(up_new)
        fwd_proj = fwd_proj.normalized()
        var back := -fwd_proj
        var right := up_new.cross(back).normalized()
        var true_up := back.cross(right)
        var new_basis := Basis(right, true_up, back)
        return new_basis.orthonormalized().scaled(basis.get_scale())


# ─── Panel plumbing ───────────────────────────────────────────────────────────

var _world3d: World3D = null

func _undo_redo() -> Variant:
        return editor_plugin.get_undo_redo() if is_instance_valid(editor_plugin) else null

func _notify_state(running: bool) -> void:
        if is_instance_valid(panel) and panel.has_method("on_physics_state_changed"):
                panel.call("on_physics_state_changed", running)

func _status(msg: String, warn: bool = false) -> void:
        if is_instance_valid(panel) and panel.has_method("set_status"):
                panel.call("set_status", msg, (Color(1.00, 0.72, 0.18) if warn else null))

func _plural(n: int) -> String: return "" if n == 1 else "s"

func _get_bool(k: String) -> bool:  return bool(panel.get(k))  if is_instance_valid(panel) else false
func _get_float(k: String) -> float: return float(panel.get(k)) if is_instance_valid(panel) else 0.0
func _get_int(k: String) -> int:   return int(panel.get(k))   if is_instance_valid(panel) else 0

func _exit_tree() -> void:
        # Deactivation or editor shutdown mid-simulation: put the physics server
        # and world space back exactly how the editor expects them, always.
        if _running:
                _finish(false)
        else:
                if _world_space.get_id() != 0 and _world_was_active:
                        PhysicsServer3D.space_set_active(_world_space, true)
                if _space.get_id() != 0:
                        _teardown_space()
                PhysicsServer3D.set_active(false)
