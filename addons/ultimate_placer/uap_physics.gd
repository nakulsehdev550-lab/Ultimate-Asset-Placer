@tool
extends Node

## Ultimate Asset Placer — Physics Placer
##
## Lifts selected scene objects into the air and drops them with a small
## hand-rolled physics simulation (gravity + collision response), then bakes
## the result in place once stopped.
##
## Why hand-rolled instead of just dropping in a RigidBody3D: verified
## against a real Godot 4.7.1 editor build that the engine's built-in physics
## step never runs on nodes while you're just editing a scene — a RigidBody3D
## sitting above a floor stayed completely motionless for 170+ editor frames,
## whether it was parented inside the edited scene or entirely outside it.
## Play mode is a separate process; the editor's own process never steps
## PhysicsServer3D dynamics at all. PhysicsDirectSpaceState3D queries
## (cast_motion / get_rest_info / intersect_ray) DO work in-editor though —
## same frame a shape is added, no import/registration delay — so this
## simulates by hand: integrate gravity, sweep a proxy shape each frame,
## resolve bounces off the real collision already in the scene.

const TEMP_META    := "_uap_temp_physics_body"
const TEMP_NAME    := "__UAP_TempPhysicsCollision__"
const SETTLE_SPEED := 0.05   # m/s — below this, the settle-hold timer starts
const SETTLE_HOLD  := 0.22   # seconds under SETTLE_SPEED before we call it landed
const ROT_SETTLE_TIME := 0.18 # seconds to ease the final ground-align tilt
const MARGIN       := 0.02
const PROBE_DISTANCE := 0.25 # meters the ground-contact probe checks ahead. Needs
                              # real slack (not just the physics margin) — a resting
                              # object still has small residual vertical drift between
                              # exact contact events, and a too-tight probe loses
                              # "grounded" status on that drift alone, which starves it
                              # of friction and lets gravity build real speed before
                              # the object either luckily drifts back into range or
                              # fully separates from the surface.
const MAX_FALL_SPEED := 60.0 # m/s terminal velocity — keeps a very long, uninterrupted
                              # fall from ever building enough speed for a single-frame
                              # sweep to tunnel through thin geometry, and keeps the
                              # motion looking physically plausible
const BOUNCE_THRESHOLD_SPEED := 1.5 # m/s — impacts softer than this never bounce at
                                     # all, regardless of Bounciness. Without this, even
                                     # a modest restitution on a sloped surface launches
                                     # the object away along the (tilted) normal, which
                                     # carries real horizontal distance before gravity
                                     # brings it back down — each such landing converts
                                     # more fall speed into slope-sliding speed than the
                                     # brief grounded windows between hops can undo with
                                     # friction, so it never actually stops. Most physics
                                     # engines use exactly this kind of threshold so soft
                                     # contacts settle instead of chattering forever.
const MIN_AABB     := 0.05   # smallest axis a sweep/collision shape is ever built with
const LARGE_BATCH_WARN := 300
const DYNAMIC_IMPACT_DAMPING := 0.25 # A collision against another object still in
                                      # THIS simulation (not real static level geometry)
                                      # keeps only this fraction of its tangential speed,
                                      # on top of never bouncing at all. This system has
                                      # no real momentum exchange between two falling
                                      # objects — each one treats every other object as
                                      # an immovable obstacle when resolving its own
                                      # collision — so a fast, off-centre hit against
                                      # another object (landing on a neighbour in a pile,
                                      # not unlike hitting a sloped surface) can convert
                                      # most of its fall speed into sideways speed through
                                      # the geometry alone, with nothing to conserve it
                                      # correctly. Damping it heavily here is what keeps a
                                      # pile of objects settling predictably instead of
                                      # occasionally launching one sideways.
const STUCK_RESOLVE_ITERATIONS := 8   # depenetration steps to take within a SINGLE
                                       # frame when the "stuck" safety net fires — two
                                       # objects can start already substantially
                                       # overlapping (an easy thing to happen with a
                                       # tight lift/scatter), and since both are usually
                                       # still falling together the whole way down, one
                                       # tiny push per frame might never fully separate
                                       # them; resolving it in one frame instead of
                                       # hundreds is what actually fixes that rather
                                       # than just slowing down how visibly stuck it is.

var editor_plugin: EditorPlugin = null
var panel:         Node         = null

var _running:  bool = false
var _bodies:   Array[Dictionary] = []
var _sim_root: Node = null
var _dynamic_rids: Dictionary = {} # RID -> true, every collider belonging to
                                    # an object in the CURRENT simulation batch


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

	var ur := _undo_redo()
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
	if nodes.size() > LARGE_BATCH_WARN:
		push_warning("Ultimate Asset Placer: starting a physics simulation on %d objects at once — this can be slow. Consider dropping smaller batches." % nodes.size())

	_sim_root = EditorInterface.get_edited_scene_root()
	_bodies.clear()
	var skipped := 0
	for n in nodes:
		var entry := _make_body_entry(n)
		if entry != null: _bodies.append(entry)
		else: skipped += 1

	_dynamic_rids.clear()
	for entry in _bodies:
		for rid in (entry["excludes"] as Array[RID]):
			_dynamic_rids[rid] = true

	if _bodies.is_empty():
		if skipped > 0:
			_status("Skipped all %d object%s — no collision and Auto-Add Missing Collision is off." % [skipped, _plural(skipped)], true)
		else:
			_status("Nothing usable in the current selection.", true)
		return

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


# ─── Simulation step ────────────────────────────────────────────────────────

func _step(delta: float) -> void:
	if _sim_root != null and EditorInterface.get_edited_scene_root() != _sim_root:
		# Scene tab changed out from under us — freeze wherever things are
		# rather than keep moving nodes in a scene the user can no longer see.
		_finish(true)
		return

	var root := EditorInterface.get_edited_scene_root()
	if root == null: _finish(true); return
	var world := (root as Node3D).get_world_3d() if root is Node3D else null
	if world == null: return
	var space := world.direct_space_state
	if space == null: return

	var dt := minf(delta, 1.0 / 30.0) # clamp so an editor stutter can't overshoot a whole frame

	var gravity      := maxf(0.0, _get_float("phys_gravity"))
	var restitution  := clampf(_get_float("phys_bounciness"), 0.0, 1.0)
	var friction     := clampf(_get_float("phys_friction"), 0.0, 1.0)
	var align_ground := _get_bool("phys_align_to_ground")
	var max_fall     := maxf(1.0, _get_float("phys_max_fall_time"))

	var all_done := true

	for entry in _bodies:
		var node: Node3D = entry["node"]
		if not is_instance_valid(node):
			entry["done"] = true
			continue
		if entry.get("done", false):
			continue
		all_done = false

		if entry.get("settled", false):
			_step_settle_rotation(entry, node, dt)
			continue

		entry["elapsed"] = float(entry["elapsed"]) + dt
		if float(entry["elapsed"]) > max_fall:
			if not entry.get("warned_no_land", false):
				entry["warned_no_land"] = true
				push_warning("Ultimate Asset Placer: '%s' fell for %.0fs without landing on anything — stopped in place. Make sure there is collision beneath it." % [node.name, max_fall])
			_land_and_settle(entry, node, align_ground, space, false)
			continue

		var vel: Vector3 = entry["velocity"]
		vel += Vector3(0.0, -gravity, 0.0) * dt
		if vel.length() > MAX_FALL_SPEED: vel = vel.limit_length(MAX_FALL_SPEED)

		if int(entry.get("settle_reject_grace", 0)) > 0:
			entry["settle_reject_grace"] = int(entry["settle_reject_grace"]) - 1

		var proxy: Shape3D = entry["proxy_shape"]
		var local_center: Vector3 = entry["proxy_local_center"]
		var rot_basis := node.global_basis.orthonormalized()
		var query_origin := node.global_position + rot_basis * local_center

		# Persistent ground-contact probe, independent of this frame's main
		# movement sweep below. A fast slide along a slope can mean the
		# object's own downward motion this frame never registers as a fresh
		# penetration — the tangential (sliding) part dominates and the
		# vertical part is tiny — so relying only on the main sweep to gate
		# friction would starve it of friction on exactly the frames it needs
		# it most, and a slope shallower than the friction coefficient would
		# never actually manage to arrest the slide. This short probe along
		# the last known ground normal keeps friction applying every frame
		# the object is still genuinely resting on something, however fast
		# it's sliding, and naturally reports "not grounded" the moment it
		# actually slides off an edge into open air.
		var probe_found_contact := false
		if entry.get("has_ground_normal", false) and int(entry.get("settle_reject_grace", 0)) <= 0:
			var probe_normal: Vector3 = entry["ground_normal"]
			var into_probe := vel.dot(probe_normal)
			# Only treat this as ongoing resting/sliding contact if the object
			# is already moving slowly relative to the surface. A real impact
			# still carrying fall speed from being airborne needs the main
			# sweep's proper bounce-or-absorb handling below — decomposing a
			# large into-surface velocity into normal/tangential here and
			# just capping the normal part would silently dump most of that
			# fall speed into extra sliding speed instead of bouncing or
			# absorbing it, which is exactly what let PropD-style landings
			# snowball into ever-faster slides down a slope.
			if into_probe > -BOUNCE_THRESHOLD_SPEED:
				var probe_params := PhysicsShapeQueryParameters3D.new()
				probe_params.shape_rid = proxy.get_rid()
				probe_params.transform = Transform3D(rot_basis, query_origin)
				probe_params.motion = -probe_normal * PROBE_DISTANCE
				probe_params.collide_with_bodies = true
				probe_params.collide_with_areas = false
				probe_params.margin = MARGIN
				probe_params.exclude = entry["excludes"]
				var probe_cast: Array = space.cast_motion(probe_params)
				if probe_cast.size() > 0 and float(probe_cast[0]) < 0.999:
					probe_found_contact = true
					var vn := probe_normal * vel.dot(probe_normal)
					var vt := vel - vn
					var vt_speed := vt.length()
					var new_vt := Vector3.ZERO
					if vt_speed > 0.0001:
						new_vt = vt.normalized() * maxf(0.0, vt_speed - friction * gravity * dt)
					# The into-surface (normal) component is deliberately left
					# untouched here — gravity's small per-frame addition to it
					# will cross BOUNCE_THRESHOLD_SPEED within a few frames on
					# its own, at which point the main sweep below absorbs or
					# bounces it properly. Artificially capping it here instead
					# (an earlier version of this code did) creates a runaway
					# trap: capping into-speed stops the object from ever
					# moving far enough to leave this probe's short detection
					# range, so it can end up "gliding" indefinitely along a
					# corner or edge instead of either resting or actually
					# falling away from it.
					vel = new_vt + vn

		var motion := vel * dt

		var params := PhysicsShapeQueryParameters3D.new()
		params.shape_rid = proxy.get_rid()
		params.transform = Transform3D(rot_basis, query_origin)
		params.motion = motion
		params.collide_with_bodies = true
		params.collide_with_areas = false
		params.margin = MARGIN
		params.exclude = entry["excludes"]

		var cast: Array = space.cast_motion(params)
		var safe_frac: float = clampf(float(cast[0]) if cast.size() > 0 else 1.0, 0.0, 1.0)

		# Safety net: empirically, if the query shape is ALREADY overlapping a
		# collider at query_origin (residual penetration left over from a
		# previous frame's contact response, or an unlucky landing spot),
		# cast_motion can report full clearance for this frame's sweep even
		# when the object is sitting inside solid geometry — which would
		# otherwise let it silently fall straight through the floor forever.
		# This only needs checking on the "fully clear" result: a sweep that
		# already found a blocking hit below is trusted as-is, so ordinary
		# resting/landing contact (which cast_motion handles correctly, as
		# confirmed by objects settling cleanly on flat ground) never takes
		# this path and never pays its extra query. The ground-contact probe
		# already having found something this frame rules it out too — this
		# is meant to catch a case the rest of the system missed entirely,
		# not to double-check a resting contact the probe already resolved.
		# Skipping it whenever the probe succeeded matters for more than
		# just avoiding redundant queries: this check's own resolution is a
		# blunt, unconditional hard stop, and running it on top of the
		# probe's considered, gradual friction on every single object
		# resting in an ordinary pile — which, once this used a shape that
		# actually matched round objects, agreed with genuine contact far
		# more often — turned an intended rare fallback into a per-object,
		# per-frame cost for the entire remaining simulation.
		var stuck_normal := Vector3.ZERO
		if safe_frac >= 0.999 and not probe_found_contact and int(entry.get("settle_reject_grace", 0)) <= 0:
			var stuck_shape: Shape3D = entry["stuck_probe_shape"]
			var push_step: float = maxf(MARGIN * 2.0, float(entry.get("proxy_half_height", 0.05)) * 0.35)
			var probe_pos := query_origin
			var accumulated_push := Vector3.ZERO
			# Resolve the FULL overlap within this single frame rather than
			# one token nudge per frame: two objects placed close enough to
			# start the simulation already overlapping (an easy thing to
			# happen with a tight lift/scatter, or several props dropped
			# together) can be substantially embedded in each other from
			# frame one, and a single small push per frame could take
			# hundreds of frames — or, since both are usually still falling
			# together the whole way down, might never actually resolve —
			# to separate them. Iterating the check-and-push right here
			# clears even a real, non-trivial overlap in one step.
			for _i in STUCK_RESOLVE_ITERATIONS:
				var stuck_params := PhysicsShapeQueryParameters3D.new()
				stuck_params.shape_rid = stuck_shape.get_rid()
				stuck_params.transform = Transform3D(rot_basis, probe_pos)
				stuck_params.collide_with_bodies = true
				stuck_params.collide_with_areas = false
				stuck_params.margin = MARGIN
				stuck_params.exclude = entry["excludes"]
				var stuck_rest: Dictionary = space.get_rest_info(stuck_params)
				if stuck_rest.is_empty():
					break
				var n: Vector3 = (stuck_rest["normal"] as Vector3) if stuck_rest.has("normal") else Vector3.UP
				if n == Vector3.ZERO: n = Vector3.UP
				stuck_normal = n
				var step: Vector3 = n * push_step
				probe_pos += step
				accumulated_push += step

			if stuck_normal != Vector3.ZERO:
				node.global_position += accumulated_push

		if stuck_normal != Vector3.ZERO:
			pass # position already nudged (possibly repeatedly) above
		else:
			node.global_position += motion * safe_frac

		if safe_frac < 0.999 or stuck_normal != Vector3.ZERO:
			var stuck_normal_source := stuck_normal != Vector3.ZERO
			var normal := stuck_normal
			var hit_dynamic := false
			if not stuck_normal_source:
				var rest_params := PhysicsShapeQueryParameters3D.new()
				rest_params.shape_rid = proxy.get_rid()
				rest_params.transform = Transform3D(rot_basis, query_origin + motion * safe_frac)
				rest_params.collide_with_bodies = true
				rest_params.collide_with_areas = false
				rest_params.margin = MARGIN
				rest_params.exclude = entry["excludes"]
				var rest: Dictionary = space.get_rest_info(rest_params)
				normal = (rest["normal"] as Vector3) if rest.has("normal") else Vector3.UP
				if normal == Vector3.ZERO: normal = Vector3.UP
				if rest.has("rid") and _dynamic_rids.has(rest["rid"]):
					hit_dynamic = true

			if stuck_normal_source:
				# The safety-net path only ever fires in an already-ambiguous
				# spot — typically a seam between two separate collision
				# bodies whose surfaces don't perfectly align — so rather
				# than try to preserve velocity nuance there (which risks
				# turning a one-off correction into sustained jitter or a
				# slow creep), just treat it as a hard stop: zero velocity
				# and let the settle check below take it from there.
				vel = Vector3.ZERO
			else:
				# Tangential friction was already applied above (via the
				# contact probe, using the last known normal) — a fresh hit
				# here only needs to bounce the component going INTO the new
				# normal, plus a matching friction nibble in case this is the
				# very first contact this fall (no ground_normal captured
				# yet, so the probe above had nothing to work with).
				var vn := normal * vel.dot(normal)
				var vt := vel - vn
				var vt_speed := vt.length()
				var new_vt := vt
				if not entry.get("has_ground_normal", false) and vt_speed > 0.0001:
					new_vt = vt.normalized() * maxf(0.0, vt_speed - friction * gravity * dt)
				# Soft contacts don't bounce at all (see BOUNCE_THRESHOLD_SPEED)
				# — only a genuinely hard impact gets the full Bounciness
				# setting. Landing on ANOTHER object still being simulated
				# never bounces at all regardless of speed, full stop: this
				# system treats every other object as an immovable obstacle
				# when resolving a single object's own collision (there is no
				# real momentum exchange between two falling objects), so a
				# bouncy impact between two dynamic bodies doesn't conserve
				# energy the way two real physical objects would — instead of
				# settling, it can inject speed that only compounds through
				# further collisions in a pile. Reserving bounce for genuine
				# static level geometry (where this simplification is exactly
				# correct — the environment truly isn't moving) keeps a pile
				# of falling objects settling predictably instead of
				# occasionally erupting.
				var impact_speed := -vel.dot(normal)
				var eff_restitution := 0.0 if hit_dynamic else (restitution if impact_speed > BOUNCE_THRESHOLD_SPEED else 0.0)
				if hit_dynamic:
					new_vt *= DYNAMIC_IMPACT_DAMPING
				vel = new_vt - vn * eff_restitution

			if normal.dot(Vector3.UP) > 0.3:
				entry["ground_normal"] = normal
				entry["has_ground_normal"] = true

		entry["velocity"] = vel
		# One unified settle check regardless of which branch ran above: a
		# resting object can flicker between "touching" and "just barely
		# clear" from one frame to the next as gravity nudges it into the
		# surface and a small bounce nudges it back out — if settle_timer
		# only accumulated on the "touching" frames it would keep getting
		# reset to zero by the "clear" frames in between and never actually
		# finish settling. What matters is velocity staying low, not which
		# branch produced it.
		if vel.length() < SETTLE_SPEED:
			entry["settle_timer"] = float(entry["settle_timer"]) + dt
			if float(entry["settle_timer"]) > SETTLE_HOLD:
				_land_and_settle(entry, node, align_ground, space, true)
		else:
			entry["settle_timer"] = 0.0
			if safe_frac >= 0.999:
				var tumble_speed: float = entry.get("tumble_speed", 0.0)
				if tumble_speed > 0.0:
					node.global_rotate((entry["tumble_axis"] as Vector3), deg_to_rad(tumble_speed) * dt)

	if all_done:
		if _get_bool("phys_auto_stop"):
			_finish(true)
		else:
			_status("All objects have settled. Press Stop to bake the result.")
	else:
		_status(get_progress_text())

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

func _land_and_settle(entry: Dictionary, node: Node3D, align_ground: bool, space: PhysicsDirectSpaceState3D, verify: bool) -> void:
	if verify and space != null:
		# Before locking this in, confirm this is actually touching
		# something — not just verify the contact that got us here. Two
		# separate collision bodies meeting at a hard edge (a crate or
		# platform sitting on the ground, for instance) can report an
		# inconsistent contact normal right at that seam, frame to frame,
		# which can coax an object into hovering at a quasi-equilibrium
		# height that doesn't correspond to any real resting surface —
		# neither the floor nor the ledge, something in between.
		#
		# This has to be a genuine overlap check against the object's own
		# shape, not a straight-down ray: resting on another object off to
		# one side (leaning on a neighbour in a pile, the single most
		# common way anything actually settles once it's not alone on flat
		# ground) has its real support at an angle, and a ray straight down
		# from dead-centre would sail right past that support and read a
		# large false gap — rejecting a perfectly good, ordinary resting
		# position, not just the genuinely floating one this is actually
		# meant to catch. The already-shrunk stuck-probe shape is exactly
		# the right tool: small enough that ordinary margin-level contact
		# doesn't trip it, but it still finds real contact from any
		# direction, not only straight down.
		var stuck_shape: Shape3D = entry["stuck_probe_shape"]
		var rot_basis := node.global_basis.orthonormalized()
		var query_origin := node.global_position + rot_basis * (entry["proxy_local_center"] as Vector3)
		var check_params := PhysicsShapeQueryParameters3D.new()
		check_params.shape_rid = stuck_shape.get_rid()
		check_params.transform = Transform3D(rot_basis, query_origin)
		check_params.collide_with_bodies = true
		check_params.collide_with_areas = false
		check_params.margin = MARGIN
		check_params.exclude = entry["excludes"]
		var touching: Dictionary = space.get_rest_info(check_params)
		if touching.is_empty():
			# Not actually touching anything at all — this isn't resting,
			# it's floating. Drop the ambiguous tangential drift that
			# likely caused the false settle and give it a clean, decisive
			# nudge downward instead of leaving it to rediscover the same
			# ambiguity next frame. A short grace period also suppresses
			# the ground-contact probe and the "stuck" safety net for the
			# next few frames — otherwise either one can re-freeze the
			# object almost immediately, right back where it started,
			# before it has any real chance to actually fall clear.
			var vy: float = entry["velocity"].y
			entry["velocity"] = Vector3(0.0, minf(vy, -0.5), 0.0)
			entry["settle_timer"] = 0.0
			entry["settle_reject_grace"] = 15
			return

	entry["settled"] = true
	entry["velocity"] = Vector3.ZERO
	entry["settle_timer"] = 0.0
	if align_ground and entry.get("has_ground_normal", false):
		var normal: Vector3 = entry["ground_normal"]
		if node.global_basis.y.dot(normal) < 0.999:
			entry["settling_rotation"] = true
			entry["rot_from"] = node.global_basis
			entry["rot_to"] = _align_up_preserve_yaw(node.global_basis, normal)
			entry["rot_t"] = 0.0
			return
	entry["done"] = true

func _apply_transform(node: Node3D, xform: Transform3D) -> void:
	if is_instance_valid(node): node.global_transform = xform

func _finish(keep: bool) -> void:
	if not _running and _bodies.is_empty(): return
	_running = false
	_sim_root = null
	_dynamic_rids.clear()

	var changed: Array[Dictionary] = []
	for entry in _bodies:
		var node: Node3D = entry["node"]
		if is_instance_valid(node):
			if not keep:
				node.global_transform = entry["start_xform"]
			elif node.global_transform != (entry["start_xform"] as Transform3D):
				changed.append(entry)
		var tb: Node = entry.get("temp_body")
		if entry.get("added_temp", false) and is_instance_valid(tb):
			node.remove_child(tb) if is_instance_valid(node) and tb.get_parent() == node else null
			tb.queue_free()

	if keep and not changed.is_empty():
		var ur := _undo_redo()
		if ur:
			ur.create_action("UAP: Physics Simulation (%d object%s)" % [changed.size(), _plural(changed.size())])
			for entry in changed:
				var node: Node3D = entry["node"]
				ur.add_do_method(self, "_apply_transform", node, node.global_transform)
				ur.add_undo_method(self, "_apply_transform", node, entry["start_xform"])
			ur.commit_action(false)

	var n := _bodies.size()
	_bodies.clear()
	_notify_state(false)
	if keep:
		_status("Physics stopped — %d object%s settled in place." % [n, _plural(n)])
	else:
		_status("Simulation cancelled — objects restored.")


# ─── Building a simulated body from a scene node ──────────────────────────────

func _make_body_entry(node: Node3D) -> Variant:
	if not is_instance_valid(node): return null

	# Clean up any leftover temp collision from a previous, improperly-ended
	# run on this same node (e.g. the editor crashed mid-simulation) before
	# measuring or re-adding anything.
	for c in node.get_children():
		if c is Node and (c as Node).has_meta(TEMP_META):
			node.remove_child(c); (c as Node).free()

	var meshes: Array = []
	_collect_meshes(node, meshes)

	var shapes := _compute_shape_data(node, meshes)
	var world_aabb: AABB = shapes["world_aabb"]

	var existing: Array = []
	_collect_solid_bodies(node, existing)
	var had_existing_collision := not existing.is_empty()

	if not had_existing_collision and not _get_bool("phys_auto_add_collision"):
		# Auto-Add Missing Collision is off and this object has nothing of
		# its own to fall or land on — skip it rather than guess.
		return null

	var temp_body: StaticBody3D = null
	var added_temp := false
	if existing.is_empty():
		temp_body = _build_temp_collision(node, meshes, _get_int("phys_auto_shape"))
		added_temp = true
		existing = [temp_body]

	var excludes: Array[RID] = []
	for b in existing:
		if b is CollisionObject3D: excludes.append((b as CollisionObject3D).get_rid())

	# The sweep proxy is what actually drives this object's own motion each
	# frame, so its shape matters far more than the temp-collision shape
	# other objects see it as: a box standing in for a ball can't roll off
	# a neighbour and will "corner-catch" instead of deflecting smoothly,
	# which is exactly what produces an unnatural rigid tower instead of a
	# settling pile, or an object launched sideways where a real ball would
	# just roll. Prefer the object's own real collision shape when it has
	# exactly one (most accurate — this is literally the shape the user
	# already set up); otherwise build one from Auto Shape, sized and
	# positioned from the actual mesh, not always assumed to be a box.
	var proxy: Shape3D = null
	if had_existing_collision:
		proxy = _extract_single_existing_shape_for_sweep(existing, node)
	if proxy == null:
		proxy = _build_auto_sweep_shape(node, meshes, world_aabb, _get_int("phys_auto_shape"))

	var tumble := _get_bool("phys_random_tumble")

	return {
		"node": node,
		"start_xform": node.global_transform,
		"proxy_shape": proxy,
		"proxy_local_center": world_aabb.get_center(),
		"proxy_half_height": world_aabb.size.y * 0.5,
		"stuck_probe_shape": _make_shrunk_probe(world_aabb.size, proxy),
		"excludes": excludes,
		"temp_body": temp_body,
		"added_temp": added_temp,
		"velocity": Vector3.ZERO,
		"settled": false,
		"done": false,
		"settle_timer": 0.0,
		"elapsed": 0.0,
		"has_ground_normal": false,
		"ground_normal": Vector3.UP,
		"tumble_axis": Vector3(randf_range(-1.0,1.0), randf_range(-1.0,1.0), randf_range(-1.0,1.0)).normalized() if tumble else Vector3.ZERO,
		"tumble_speed": randf_range(50.0, 200.0) if tumble else 0.0,
		"settling_rotation": false,
		"warned_no_land": false,
		"settle_reject_grace": 0,
	}

func _extract_single_existing_shape_for_sweep(bodies: Array, node: Node3D) -> Variant:
	## If this object's existing collision is exactly one safe (non-concave)
	## primitive or convex shape, returns a copy sized for world-scale
	## sweeping — using the object's own real shape is far more accurate
	## than any bounding approximation, and is literally what the user
	## already set up. Returns null for anything compound or concave
	## (Trimesh, HeightMap, etc.), so the caller falls back to a shape
	## built from Auto Shape instead — a concave shape is not reliable as
	## the MOVING shape in a swept collision query.
	if bodies.size() != 1: return null
	var body := bodies[0] as CollisionObject3D
	if body == null: return null
	var found: CollisionShape3D = null
	for c in body.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape != null:
			if found != null: return null  # more than one shape — compound, use the fallback
			found = c
	if found == null: return null
	var shp: Shape3D = found.shape
	if shp is ConcavePolygonShape3D or shp is HeightMapShape3D \
			or shp is WorldBoundaryShape3D or shp is SeparationRayShape3D:
		return null

	# Effective uniform world scale from the CollisionShape3D's own node
	# down through node's global transform, covering both a shape sitting
	# directly on `node` and one nested a level or two inside (exactly how
	# this plugin's own temp collision, and many imported props, are built).
	var cum_scale: Vector3 = found.global_transform.basis.get_scale()
	var uniform_scale: float = (cum_scale.x + cum_scale.y + cum_scale.z) / 3.0
	if uniform_scale <= 0.0001: uniform_scale = 1.0

	if shp is SphereShape3D:
		var s := SphereShape3D.new()
		s.radius = maxf((shp as SphereShape3D).radius * uniform_scale, MIN_AABB * 0.5)
		return s
	if shp is BoxShape3D:
		var b := BoxShape3D.new()
		var sz: Vector3 = (shp as BoxShape3D).size * cum_scale
		b.size = Vector3(maxf(sz.x, MIN_AABB), maxf(sz.y, MIN_AABB), maxf(sz.z, MIN_AABB))
		return b
	if shp is CapsuleShape3D:
		var c := CapsuleShape3D.new()
		c.radius = maxf((shp as CapsuleShape3D).radius * uniform_scale, MIN_AABB * 0.5)
		c.height = maxf((shp as CapsuleShape3D).height * uniform_scale, MIN_AABB)
		return c
	if shp is CylinderShape3D:
		var cy := CylinderShape3D.new()
		cy.radius = maxf((shp as CylinderShape3D).radius * uniform_scale, MIN_AABB * 0.5)
		cy.height = maxf((shp as CylinderShape3D).height * uniform_scale, MIN_AABB)
		return cy
	if shp is ConvexPolygonShape3D:
		var ref_inv := node.global_basis.orthonormalized().inverse()
		var world_pts := PackedVector3Array()
		for p in (shp as ConvexPolygonShape3D).points:
			var world_p: Vector3 = found.global_transform * p
			world_pts.append(ref_inv * (world_p - node.global_position))
		if world_pts.size() < 4: return null
		var cp := ConvexPolygonShape3D.new()
		cp.points = world_pts
		return cp
	return null

func _build_auto_sweep_shape(node: Node3D, meshes: Array, world_aabb: AABB, shape_type: int) -> Shape3D:
	## No usable existing collision — build a sweep proxy from Auto Shape,
	## sized from the real mesh data in the same world-scale, rotation-only
	## frame as world_aabb (see _compute_shape_data). Convex Hull merges
	## actual mesh vertices from every part into one hull, rather than
	## falling back to a box, so "accurate to mesh" genuinely means that.
	match shape_type:
		1:
			var s := SphereShape3D.new()
			s.radius = maxf(world_aabb.size.x, maxf(world_aabb.size.y, world_aabb.size.z)) * 0.5
			return s
		2:
			var c := CapsuleShape3D.new()
			c.radius = maxf(world_aabb.size.x, world_aabb.size.z) * 0.5
			c.height = world_aabb.size.y
			return c
		3:
			var pts := _collect_world_frame_points(node, meshes)
			if pts.size() >= 4:
				var cp := ConvexPolygonShape3D.new()
				cp.points = pts
				return cp
			# fall through to box if there was nothing usable to hull
			var b3 := BoxShape3D.new(); b3.size = world_aabb.size; return b3
		_:
			var b := BoxShape3D.new()
			b.size = world_aabb.size
			return b

func _collect_world_frame_points(node: Node3D, meshes: Array) -> PackedVector3Array:
	## Every mesh part's own hull points, transformed into the same
	## world-scale, rotation-only frame _compute_shape_data uses for
	## world_aabb. Built from each mesh's OWN reduced convex hull (the same
	## create_convex_shape Godot already uses for the temp-collision shapes
	## below), not a raw stride-sample of every vertex — a raw sample of a
	## few hundred points per mesh part still hands the physics engine a
	## needlessly complex shape to sweep every frame this object is active,
	## and it's the query cost, not the one-time hull build, that actually
	## matters here: several such objects densely packed together (a stress
	## test that's exactly this — many round props settling into a tight
	## pile) measured 20-25x slower per frame with the naive version, purely
	# from convex-vs-convex queries between shapes with far more points than
	## the query ever needed to answer "is there a collision" correctly.
	## Godot's own hull reduction keeps only the vertices that actually
	## define the shape, so this is both cheaper AND a closer fit than
	## sampling raw, unreduced mesh vertices ever was.
	const MAX_TOTAL_POINTS := 64
	var ref_inv := node.global_basis.orthonormalized().inverse()
	var out := PackedVector3Array()
	for mi_raw in meshes:
		var mi := mi_raw as MeshInstance3D
		if mi.mesh == null: continue
		var hull := mi.mesh.create_convex_shape(true, true)
		if hull == null: continue
		var rel := ref_inv * mi.global_transform.basis
		var offset := ref_inv * (mi.global_position - node.global_position)
		for p in hull.points:
			out.append(rel * p + offset)
	if out.size() > MAX_TOTAL_POINTS:
		# Still a lot of combined hull points across many mesh parts —
		# thin further with a stride rather than hand the query an
		# unbounded shape, now sampling already-reduced hull vertices
		# instead of raw ones.
		var thinned := PackedVector3Array()
		var step: int = int(ceil(float(out.size()) / float(MAX_TOTAL_POINTS)))
		var i := 0
		while i < out.size():
			thinned.append(out[i])
			i += step
		out = thinned
	return out

func _make_shrunk_probe(size: Vector3, real_shape: Shape3D) -> Shape3D:
	## A deliberately smaller stand-in for the "stuck" safety-net check in
	## _step — a normal resting object always touches within the physics
	## margin, which get_rest_info reports as "overlapping" too, so
	## checking with the real proxy size would treat completely ordinary
	## resting contact as the same emergency case a genuinely embedded
	## object is. Shrinking the test shape adds slack equal to the shrink,
	## so a margin-level touch no longer overlaps it while a real, deep
	## embedding still does.
	##
	## Matching the real proxy's shape TYPE, not just always a box, matters
	## more than it might look: this check is exactly as likely to fire
	## against another rounded object mid-pile as against flat level
	## geometry, and a flat-faced box probe grazing a curved neighbour
	## reads as a simple "flat, straight up" contact regardless of where
	## the two shapes actually meet — which silently discards the real
	## (usually angled) contact geometry an off-centre resting position on
	## a round object depends on, and was exactly what turned one isolated
	## correction into an endless reset loop that never actually settled.
	if real_shape is SphereShape3D:
		var s := SphereShape3D.new()
		s.radius = maxf((real_shape as SphereShape3D).radius * 0.6, 0.05)
		return s
	if real_shape is CapsuleShape3D:
		var c := CapsuleShape3D.new()
		c.radius = maxf((real_shape as CapsuleShape3D).radius * 0.6, 0.05)
		c.height = maxf((real_shape as CapsuleShape3D).height * 0.6, 0.1)
		return c
	if real_shape is CylinderShape3D:
		var cy := CylinderShape3D.new()
		cy.radius = maxf((real_shape as CylinderShape3D).radius * 0.6, 0.05)
		cy.height = maxf((real_shape as CylinderShape3D).height * 0.6, 0.1)
		return cy
	if real_shape is ConvexPolygonShape3D:
		var pts: PackedVector3Array = (real_shape as ConvexPolygonShape3D).points
		if pts.size() >= 4:
			var centroid := Vector3.ZERO
			for p in pts: centroid += p
			centroid /= pts.size()
			var shrunk := PackedVector3Array()
			for p in pts: shrunk.append(centroid + (p - centroid) * 0.6)
			var cp := ConvexPolygonShape3D.new()
			cp.points = shrunk
			return cp
	var b := BoxShape3D.new()
	b.size = Vector3(maxf(size.x * 0.6, 0.05), maxf(size.y * 0.6, 0.05), maxf(size.z * 0.6, 0.05))
	return b

func _compute_shape_data(node: Node3D, meshes: Array) -> Dictionary:
	## Returns a world-scale AABB expressed relative to a pure rotation+
	## translation frame anchored at node's current transform (no scale in
	## the basis). Used for the sweep proxy, which is driven by hand each
	## frame rather than through Godot's node hierarchy, so it needs a real
	## world size and a scale-free basis to stay correct as the object moves.
	var rot_basis := node.global_basis.orthonormalized()
	var rot_ref := Transform3D(rot_basis, node.global_position)
	var rot_inv := rot_ref.affine_inverse()

	var found := false
	var world_aabb := AABB()
	for mi_raw in meshes:
		var mi := mi_raw as MeshInstance3D
		if mi.mesh == null: continue
		var rel := rot_inv * mi.global_transform
		for c in _aabb_corners(mi.mesh.get_aabb()):
			var p := rel * c
			if not found: world_aabb = AABB(p, Vector3.ZERO); found = true
			else: world_aabb = world_aabb.expand(p)

	if not found:
		world_aabb = AABB(Vector3(-0.25,-0.25,-0.25), Vector3(0.5,0.5,0.5))

	for i in 3:
		if world_aabb.size[i] < MIN_AABB:
			var grow: float = (MIN_AABB - world_aabb.size[i]) * 0.5
			world_aabb.position[i] -= grow
			world_aabb.size[i] += grow * 2.0

	return {"world_aabb": world_aabb}

func _build_temp_collision(node: Node3D, meshes: Array, shape_type: int) -> StaticBody3D:
	## Adds a StaticBody3D (one CollisionShape3D per mesh part, same
	## per-mesh approach as the Collision tab's own Auto Collision) as a
	## plain child of `node`. Deliberately NOT owned by the scene root, so
	## if the user saves mid-simulation it never ends up in the .tscn file —
	## it exists purely for this session's collision queries and is removed
	## the moment physics is stopped or cancelled.
	var body := StaticBody3D.new()
	body.name = TEMP_NAME
	body.set_meta(TEMP_META, true)
	var local_inv := node.global_transform.affine_inverse()
	var any_shape := false
	for mi_raw in meshes:
		var mi := mi_raw as MeshInstance3D
		if mi.mesh == null: continue
		var shp := _make_physics_shape(mi.mesh, shape_type)
		if shp == null: continue
		var cs := CollisionShape3D.new(); cs.name = "Shape"; cs.shape = shp
		var rel := local_inv * mi.global_transform
		cs.transform = Transform3D(rel.basis, rel * _physics_shape_center(mi.mesh, shape_type))
		body.add_child(cs)
		any_shape = true
	if not any_shape:
		var cs2 := CollisionShape3D.new(); cs2.name = "Shape"
		var b := BoxShape3D.new(); b.size = Vector3(0.5, 0.5, 0.5)
		cs2.shape = b
		body.add_child(cs2)
	node.add_child(body)
	return body

func _make_physics_shape(mesh: Mesh, st: int) -> Shape3D:
	var a := mesh.get_aabb()
	match st:
		0:
			var b := BoxShape3D.new(); b.size = a.size; return b
		1:
			var s := SphereShape3D.new(); s.radius = maxf(a.size.x, maxf(a.size.y, a.size.z)) * 0.5; return s
		2:
			var c := CapsuleShape3D.new(); c.radius = maxf(a.size.x, a.size.z) * 0.5; c.height = a.size.y; return c
		3:
			return mesh.create_convex_shape(true, true)
	var bd := BoxShape3D.new(); bd.size = a.size; return bd

func _physics_shape_center(mesh: Mesh, st: int) -> Vector3:
	return mesh.get_aabb().get_center() if st != 3 else Vector3.ZERO


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

func _undo_redo() -> Variant:
	return editor_plugin.get_undo_redo() if is_instance_valid(editor_plugin) else null

func _notify_state(running: bool) -> void:
	if is_instance_valid(panel) and panel.has_method("on_physics_state_changed"):
		panel.call("on_physics_state_changed", running)

func _status(msg: String, warn: bool = false) -> void:
	if is_instance_valid(panel) and panel.has_method("set_status"):
		panel.call("set_status", msg, (Color(1.00, 0.72, 0.18) if warn else null))

func _plural(n: int) -> String: return "" if n == 1 else "s"

func _get_bool(k: String)  -> bool:  return bool(panel.get(k))  if is_instance_valid(panel) else false
func _get_float(k: String) -> float: return float(panel.get(k)) if is_instance_valid(panel) else 0.0
func _get_int(k: String)   -> int:   return int(panel.get(k))   if is_instance_valid(panel) else 0
