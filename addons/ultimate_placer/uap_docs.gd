@tool
extends RefCounted
## Ultimate Asset Placer documentation, organised as CHAPTERS.
##
## The docs window (opened from the rail's Docs button) lists every chapter
## in a sidebar on the left; clicking one shows its text on the right. Each
## chapter is a self-contained BBCode block. Icon paths and the version
## number stay tokenised ("res://addons/ultimate_placer/icons/..." and
## {{VERSION}}) so the panel can substitute the real install folder and
## plugin version at render time — they can never drift out of sync.

static func get_chapters() -> Array:
        var chapters: Array = []
        chapters.append({
                "title": "Welcome & Quick Start",
                "icon": "sec_quickstart",
                "text": WELCOME,
        })
        chapters.append({
                "title": "The Asset Browser",
                "icon": "sec_browser",
                "text": BROWSER,
        })
        chapters.append({
                "title": "Placement Modes",
                "icon": "tab_place",
                "text": MODES,
        })
        chapters.append({
                "title": "Scroll Wheel Control",
                "icon": "sec_scroll",
                "text": SCROLL,
        })
        chapters.append({
                "title": "Place Tab",
                "icon": "tab_place",
                "text": PLACE,
        })
        chapters.append({
                "title": "Transform Tab",
                "icon": "tab_transform",
                "text": TRANSFORM,
        })
        chapters.append({
                "title": "Paint Tab",
                "icon": "feature_brush",
                "text": PAINT,
        })
        chapters.append({
                "title": "Spline Tab",
                "icon": "tab_spline",
                "text": SPLINE,
        })
        chapters.append({
                "title": "Material & Collision",
                "icon": "tab_material",
                "text": MATCOL,
        })
        chapters.append({
                "title": "Physics Tab",
                "icon": "tab_physics",
                "text": PHYSICS,
        })
        chapters.append({
                "title": "Groups & Favorites",
                "icon": "tab_groups",
                "text": GROUPS,
        })
        chapters.append({
                "title": "Keys & Shortcuts",
                "icon": "tab_keys",
                "text": KEYS,
        })
        chapters.append({
                "title": "Workflow Examples",
                "icon": "sec_workflow",
                "text": WORKFLOWS,
        })
        chapters.append({
                "title": "Tips & Performance",
                "icon": "status_info",
                "text": TIPS,
        })
        chapters.append({
                "title": "Troubleshooting",
                "icon": "sec_troubleshoot",
                "text": TROUBLE,
        })
        return chapters


## Backwards-compatible full-manual text (all chapters joined with dividers).
static func get_manual_text() -> String:
        var out: String = ""
        var first: bool = true
        for ch in get_chapters():
                if not first:
                        out += "\n\n[color=#3a3d50]━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━[/color]\n\n"
                first = false
                out += str(ch["text"])
        return out


static func _h(icon: String, title: String) -> String:
        return "[font_size=17][b][color=#e0e8ff][img=17x17]res://addons/ultimate_placer/icons/%s.svg[/img]  %s[/color][/b][/font_size]" % [icon, title]


static func _info(msg: String) -> String:
        return "[color=#f0b834][img=15x15]res://addons/ultimate_placer/icons/status_info.svg[/img] %s[/color]" % msg


static func _warn(msg: String) -> String:
        return "[color=#e85858][img=15x15]res://addons/ultimate_placer/icons/status_warning.svg[/img] %s[/color]" % msg

static var PLACE: String = _h("tab_place", "PLACE TAB") + """

[color=#46a0f5][b]Parent Node[/b][/color]
By default, placed assets become children of the scene root. You can override this to keep your scene tree organised.

[b]Pick[/b]  — Select a Node3D in the scene tree first, then click Pick. All future placements become children of that node.
[b]X[/b]  — Clears the parent override. Assets go back to the scene root.

""" + _info("Example: select a node called \"Trees\" before clicking Pick, and all tree assets automatically go inside it.") + """

[color=#46a0f5][b]Scene Settings[/b][/color]
[b]Unpack Scenes[/b]  — When OFF (default): placed .tscn files stay as packed instances (a single node). When ON: UAP unpacks the scene so every internal node is individually visible and editable in the tree.
""" + _warn("Unpacked scenes are no longer linked to the original .tscn file. Future changes to the file won't update your placed copy.") + """

[color=#46a0f5][b]Grid & Snapping[/b][/color]
[b]Show Grid[/b]  — Toggles the visual grid lines in the viewport.
[b]Snap to Grid[/b]  — Enables or disables XZ position snapping on the floor grid.
[b]Grid Size[/b]  — Grid cell size in metres. Range: 0.0625 m to 200 m.
[b]Grid Y[/b]  — Height of the grid plane. Step buttons nudge it by one grid unit.
[b]1m button[/b]  — Instantly resets Grid Size to 1.0 metre.

[color=#46a0f5][b]Axis Wall Grids (X / Z)[/b][/color]
Two optional VERTICAL grids that snap objects onto wall planes — perfect for windows, wall torches, shelves, signs and anything else that lives on a vertical surface. Each axis grid toggles on/off individually, and when several are enabled the plane closest to the camera under your mouse wins automatically.
[b]X Axis Grid[/b]  — Wall grid on the XY plane, drawn in ORANGE. Snaps X + Y to Grid Size; Z stays locked to the wall's Pos Z.
[b]X Size / X Pos Z / X Center Y[/b]  — The wall's half-extent, its depth position along Z, and its vertical centre.
[b]Z Axis Grid[/b]  — Wall grid on the ZY plane, drawn in GREEN. Snaps Z + Y to Grid Size; X stays locked to the wall's Pos X.
[b]Z Size / Z Pos X / Z Center Y[/b]  — The same three controls for the Z wall.

Wall grids appear in Grid mode together with the blue floor grid (and respect the master Show Grid toggle), and paint-mode scatter spreads stamps ALONG the active wall instead of off it.

[color=#46a0f5][b]Height Offset[/b][/color]
Adds a fixed vertical offset to every placed asset. Use positive values to float objects above a surface, negative to push them into it (e.g. flowers sinking into grass).

[b]Offset Y[/b]  — Range: -500 m to +500 m.
[b]Snap Height[/b]  — When ON, the offset snaps to multiples of Grid Size.
[b]Height Up / Down keys[/b]  — Default [b]Page Up[/b] / [b]Page Down[/b]. Nudges offset by 0.1 m (or one Grid Size if Snap Height is ON).

[color=#46a0f5][b]Surface & Vertex Options[/b][/color]
[b]Align to Normal[/b]  — (Surface mode) Tilts placed assets to match the surface slope.
[b]Mesh Vertex Snap[/b]  — (Vertex mode) Tests actual geometry vertices instead of bounding-box corners.
[b]Magnet px[/b]  — (Vertex mode) Snap trigger distance in screen pixels. Default: 42.

[color=#46a0f5][b]Format Filter[/b][/color]
Chips for each supported format: [b]GLB, GLTF, FBX, OBJ, DAE, BLEND, TSCN, SCN, RES, MESH[/b]. Lit chip = included in scan. Changing any filter triggers a re-scan automatically.

[b]All On[/b]  — Enables every format.
[b]All Off[/b]  — Disables every format (useful to quickly clear before enabling only what you need).
[b]Restore Hidden[/b]  — Brings back every asset that was removed from the browser list via the right-click menu.

[color=#46a0f5][b]Asset Zoo[/b][/color]
Places every loaded asset in a neat grid inside an [b]AssetZoo[/b] node — a visual 3D catalogue you can walk around.

[b]Source[/b]  — Which assets the zoo includes: [b]All Loaded Assets[/b] (everything loaded into the browser this session), [b]Current Group Filter[/b] (whatever group or Favorites filter is active in the browser bar), or [b]Selected Assets[/b] (only what's currently multi-selected with Ctrl/Shift-click).
[b]Create Asset Zoo[/b]  — Spawns the assets from the chosen Source, auto-spaced by their bounding boxes.
[b]Spacing[/b]  — Gap between assets in metres (default 2.0).
[b]Show Labels[/b]  — Adds a floating Label3D with the filename above each zoo asset.
""" + _warn("Delete the AssetZoo node when done — do not leave it in your final scene.")

static var TRANSFORM: String = _h("tab_transform", "TRANSFORM TAB") + """

[color=#46a0f5][b]Rotation Snap[/b][/color]
Controls how many degrees each keyboard rotation press moves the ghost.

[b]Free[/b]  — No snapping, 1-degree precision.
[b]90 deg[/b]  — Snaps to 0°, 90°, 180°, 270°. Perfect for grid buildings.
[b]45 deg[/b]  — Every 45° — useful for diagonal placements.
[b]15 deg[/b]  — Good middle-ground snapping.
[b]Custom[/b]  — Reveals a slider to set any snap angle from 0.5° to 180°.

[color=#46a0f5][b]Current Rotation[/b][/color]
Three sliders showing the ghost's live rotation. Type a value directly or drag the slider.

[b]Rot X[/b]  — Pitch (forward/backward tilt). Range: -360° to 360°.
[b]Rot Y[/b]  — Yaw (vertical spin). Most commonly used.
[b]Rot Z[/b]  — Roll (left/right lean).
[b]Reset X Y Z[/b]  — Sets all three axes back to 0° instantly.

""" + _info("The sliders update live as you use keyboard shortcuts, and vice versa.") + """

[color=#46a0f5][b]Quick Orient Presets[/b][/color]
One-click buttons to jump to common orientations.

[b]Normal[/b]  → 0, 0, 0  — standard upright.
[b]Upside Down[/b]  → Rx 180° — for ceiling attachments.
[b]Lay Fwd[/b]  → Rx 90° — asset flat, facing forward.
[b]Lay Back[/b]  → Rx -90° — asset flat, facing backward.
[b]Tilt L[/b]  → Rz -90° — leaning left.
[b]Tilt R[/b]  → Rz 90° — leaning right.
[b]Turn 90[/b]  → Ry 90° — facing left.
[b]Turn 180[/b]  → Ry 180° — facing backward.

[color=#46a0f5][b]Random Rotation[/b][/color]
Every placed asset gets a random Y rotation chosen from a range instead of the current Rot Y value.

[b]Enable[/b]  — Toggle random Y rotation on/off.
[b]Min deg[/b]  — Minimum Y rotation. Default: 0°.
[b]Max deg[/b]  — Maximum Y rotation. Default: 360° (fully random).

[color=#46a0f5][b]Random Tilt[/b][/color]
Randomly tilts each asset on both X and Z axes symmetrically — great for imperfect gravestones, leaning poles, scattered rocks.

[b]Enable[/b]  — Toggle random tilt on/off.
[b]+/- Max deg[/b]  — Maximum tilt per axis (symmetric). E.g. 10° = tilts between -10° and +10° on both X and Z.

[color=#46a0f5][b]Scale Presets[/b][/color]
Quick buttons at the top of the Scale section: [b]x0.25  x0.5  x1  x1.5  x2  x3  x5[/b]. Clicking one instantly applies that multiplier to all axes.

[color=#46a0f5][b]Scale Controls[/b][/color]
[b]Uniform toggle[/b]  — ON (default): one slider controls all axes together. OFF: separate X, Y, Z sliders.
[b]Scale slider[/b]  — (Uniform ON) Single multiplier. Default: 1.0. Range: 0.01 to 20.
[b]X / Y / Z sliders[/b]  — (Uniform OFF) Individual axis scale.
[b]Flip X key (G)[/b]  — Mirrors the ghost on X by making the X scale negative.
[b]Flip Z key (B)[/b]  — Mirrors the ghost on Z.
[b]Scale Up / Down keys (] / [)[/b]  — Nudge scale ±0.1 per press. Hold Shift for fine ±0.025 steps.

[color=#46a0f5][b]Random Scale[/b][/color]
Multiplies each placed asset's scale by a random value in the Min–Max range.

[b]Enable[/b]  — Toggle random scale on/off.
[b]Min[/b]  — Minimum multiplier. Default: 0.8.
[b]Max[/b]  — Maximum multiplier. Default: 1.2.

""" + _info("Random scale stacks on top of your base scale. Base 2.0 + range 0.8–1.2 = final scale 1.6–2.4.")

static var PAINT: String = _h("feature_brush", "PAINT TAB") + """

[color=#46a0f5][b]Paint Mode[/b][/color]
When enabled, hold Left Mouse Button and drag to continuously stamp assets as you move — like painting with a brush across the viewport.

[b]Enable Paint[/b]  — Turns paint mode on/off.
[b]Spacing[/b]  — How far apart each stamp must be (as a multiple of Grid Size) before the next one fires. 0.5 = half a grid cell. Lower = denser painting.
[b]Scatter[/b]  — Adds a random XZ offset to each stamp so they don't fall in a perfectly straight line.
[b]Scatter R[/b]  — Radius in metres of the scatter randomness. Larger = more chaotic spread.

""" + _info("Best combo for natural environments: Paint Mode + Random Rotation + Random Scale + Scatter.") + """

[color=#46a0f5][b]Volumetric Brush[/b][/color]
Replaces drag-line painting with a large circular area brush. A glowing purple torus ring follows your cursor. Hold left-click to spray assets randomly inside the ring.

[b]Use Brush[/b]  — Switches from line-painting to the circular brush. Requires Paint Mode to also be ON.
[b]Radius m[/b]  — The brush circle radius in metres (0.1 to 50). Default: 2.0.
[b]Density[/b]  — How many assets to try placing per brush stroke. Higher = more packed. Range: 0.05 to 10.
[b]Falloff[/b]  — 0.0 = uniform density across the whole circle. 1.0 = dense in the centre, sparse at the edge.
[b]Mask Texture — Pick[/b]  — Load a greyscale image (PNG/JPG/WebP). White = full density, Black = no assets. Paint with any custom shape.
[b]Mask Texture — X[/b]  — Clears the mask and returns to a plain circle brush.

""" + _info("The brush works best in Surface mode — it raycasts down individually for each asset placed inside the circle, so everything lands on the terrain.") + """

[color=#46a0f5][b]Random Group Placer[/b][/color]
Makes UAP randomly pick from an entire active group (or your multi-selection) on every placement instead of always using the same asset.

[b]Enable[/b]  — Toggle random group picking on/off.

Priority order for random picking:
[b]1.[/b] Multiple Ctrl-selected assets in the browser → picks from those first.
[b]2.[/b] Random Group Placer ON + active group → picks from the group.
[b]3.[/b] Otherwise → uses the single selected asset.

Example workflow:
• Create a group called \"Forest Trees\". Add oak.glb, pine.glb, birch.glb to it.
• Click the \"Forest Trees\" filter button. Enable Random Group Placer + Paint Mode.
• Start painting — every stamp is randomly one of your three tree types.

[color=#46a0f5][b]MultiMesh Painter[/b][/color]
Instead of placing hundreds of individual nodes, MultiMesh Mode batches all painted assets into a single [b]MultiMeshInstance3D[/b]. Godot renders thousands of MultiMesh instances far more efficiently than separate nodes.

[b]MultiMesh Mode[/b]  — ON: painted assets go into a MultiMeshInstance3D. OFF: normal individual nodes.
[b]Add Collision[/b]  — Also generates collision shapes for MultiMesh instances when painting.
[b]Clear All MultiMesh Instances[/b]  — Removes all painted MultiMesh instances. Use carefully — difficult to undo.
[b]Generate Instance Collision[/b]  — After painting, click to generate collision shapes for all existing MultiMesh instances.
[b]Commit MultiMesh[/b]  — Finalises the MultiMesh data (for compatibility).

""" + _warn("MultiMesh mode only uses the first mesh found in an asset. Complex multi-mesh scenes only render their first mesh in MultiMesh mode.") + "\n" + _info("Undo works per paint stroke (one press+release of left-click = one undo step).")

static var SPLINE: String = _h("tab_spline", "SPLINE TAB (ADVANCED)") + """

The Advanced Spline system builds on Godot's Path3D node. You can scatter props evenly along a curve, or deform a mesh to follow the curve (roads, rivers, fences, walls). The workflow has four numbered steps.

[color=#46a0f5][b]Spline Mode Status Banner[/b][/color]

At the top of the Spline page, a live status banner shows whether Spline Mode is currently active.

[b]● SPLINE MODE ACTIVE — [name][/b]  — Spline mode is on. Viewport left-clicks edit the curve, not place assets. The name of the active spline is shown.
[b]○ No spline active[/b]  — No spline is selected. Create or select one below.

""" + _info("When spline mode is active, normal placement is suspended. Your scroll-wheel modes and mode buttons are ignored until you exit spline mode.") + """

[b]✕ Exit Spline Mode[/b]  — Deactivates spline mode and restores the previous placement mode (Free, Grid, Surface, or Vertex). The spline node is [i]not[/i] deleted — it stays in the scene for later use. Click this when you are done shaping the curve and want to resume placing regular assets.

[color=#46a0f5][b]Step 1 — Spline Node Setup[/b][/color]

[b]+ Create New Spline[/b]  — Creates a uniquely named AdvancedSpline node (Path3D + uap_path.gd script) in your scene. The first spline is named [b]AdvancedSpline[/b]; subsequent ones are named [b]AdvancedSpline_2[/b], [b]AdvancedSpline_3[/b], etc. — never @NodeXXX. Spline mode activates automatically. Use Godot's built-in Path3D editing tool (select the node in the scene tree, then use the toolbar at the top of the 3D viewport) to draw control points.
[b]Use Selected Spline[/b]  — Select an existing AdvancedSpline node in the scene tree, then click this to make it the active spline. Spline mode activates automatically.
[b]Smooth[/b]  — Smooths all control point tangents — creates flowing S-curve shapes.
[b]Sharpen[/b]  — Resets all tangents to zero — creates sharp corner-to-corner straight segments.
[b]Delete Active Spline[/b]  — Removes the active spline node from the scene entirely and exits spline mode.

[color=#46a0f5][b]Step 2 — Terrain Snapping[/b][/color]
After drawing a spline in the air, snap it onto your terrain automatically.

[b]Drop to Ground (Keep Shape)[/b]  — Finds the lowest control point, measures how far above the ground it is, and shifts the entire spline down by that amount. The shape is fully preserved.
[b]Wrap Points to Terrain[/b]  — Raycasts downward from each control point and moves each one individually onto the terrain surface.
[b]Subdivide & Wrap (Exact Shape)[/b]  — Adds new points every 1 metre along the spline first, then wraps all of them to the terrain. Best quality. Follows hills and cliffs precisely.

""" + _warn("Terrain snapping requires physics collision on your terrain (StaticBody3D + CollisionShape3D).") + """

[color=#46a0f5][b]Step 3 — Layer Manager[/b][/color]
Each spline supports multiple layers. Each layer either scatters props or deforms a mesh. Mix as many as you want on one spline.

[b]+ Scatter (Props)[/b]  — Adds a Scatter layer using the currently browser-selected asset. Props are spaced evenly along the curve.
[b]+ Deform (Roads)[/b]  — Adds a Deform layer using the selected asset's mesh, stretched along the full curve length. Ideal for roads, rivers, tunnels.

[b]Scatter layer options:[/b]
  [b]Meshes field[/b]  — Asset path(s) to scatter. Separate multiple paths with commas for random variety. Click [b]+ Add Selected[/b] to append the browser-selected asset.
  [b]Spacing[/b]  — Slider with number field. Distance in metres between instances. You can type any value beyond the slider range — just type it in the number box. Smaller = denser.
  [b]Align to Curve[/b]  — ON: each instance rotates to face along the curve. OFF: all use their default rotation.
  [b]Use MultiMesh[/b]  — ON: render as MultiMesh (very fast, many instances). OFF: individual nodes (deletable before baking).
  [b]Rnd Yaw deg[/b]  — Slider with number field. Random Y rotation applied to each instance within +/- this many degrees.

[b]Deform layer options:[/b]
  [b]Invert Faces[/b]  — Flips mesh faces. Use this if your road or tunnel is inside-out.
  [b]UV Tile X | Y[/b]  — Sliders with number fields. How many times the texture repeats along (X) and across (Y) the deformed mesh. Increase X to fix stretched textures on long roads.

[b]Common options (both layer types):[/b]
  [b]Scale X | Y | Z[/b]  — Sliders with number fields. Non-uniform scale for the layer. Type beyond the slider range for extreme values.
  [b]Offset X | Y | Z[/b]  — Sliders with number fields. Positional offset relative to the curve. Use Offset Y to raise props above the curve surface.
  [b]Add Collision on Bake[/b]  — When checked, collision shapes are generated automatically when you click Bake.
  [b]Remove Layer[/b]  — Deletes this layer from the spline.

[color=#46a0f5][b]Step 4 — Bake to Scene[/b][/color]
Procedural spline objects regenerate whenever the curve changes — you cannot delete individual instances until the spline is baked. Baking converts everything into permanent, editable scene nodes.

[b]BAKE TO NODES (Finalize)[/b]  — Converts all layer instances into regular Godot nodes (one [b]MeshInstance3D[/b] per spline instance). Best when you need to select, move, or delete individual pieces after baking. Spline mode is exited automatically, the Path3D is removed, and if \"Add Collision on Bake\" was checked, collision bodies are generated.

[b]BAKE TO MULTIMESH (Performance)[/b]  — Bakes scatter layers as [b]MultiMeshInstance3D[/b] nodes instead of individual MeshInstance3D nodes. All instances of the same mesh are packed into one MultiMesh, giving the same GPU draw-call savings as the live procedural mode. Deform layers are still baked as a regular MeshInstance3D (they are already a single merged mesh, so MultiMesh would give no benefit). Use this when you are happy with the final result and want maximum runtime performance — grass paths, fence lines, rock scatters, etc.

""" + _info("Use [b]BAKE TO NODES[/b] when you still need to edit or delete individual pieces. Use [b]BAKE TO MULTIMESH[/b] when the layout is final and performance matters most.") + "\n" + _warn("Baking is permanent — there is no undo. Make sure you are satisfied with the result before baking.")

static var MATCOL: String = _h("tab_material", "MATERIAL TAB") + """

Automatically apply a material to every asset you place — useful for colour coding props during layout, applying a tint, or layering a snow/wetness effect.

[b]Enable Override[/b]  — ON: every placed asset gets the selected material applied automatically.

[b]Apply Mode — Replace[/b]  — Replaces all surface materials on the asset with your override material. The original material is completely gone.
[b]Apply Mode — Next Pass[/b]  — Adds your override material as a [b]next_pass[/b] on top of the original material. This layers effects (snow, rain, glow) without destroying the original look. Each placed instance gets its own independent material copy — toggling the override on or off for a new placement does [i]not[/i] affect previously placed instances.

[b]Material — Pick[/b]  — Opens a file picker to select a .tres or .res material file.
[b]Material — X[/b]  — Clears the material override.

""" + _info("Next Pass mode duplicates the base surface material per instance, so turning off the override later won't retroactively change already-placed objects.") + "\n\n" + _h("tab_collision", "COLLISION TAB") + """

Automatically generate collision shapes for every asset placed — no need to manually add StaticBody3D and CollisionShape3D nodes after placing.

[color=#46a0f5][b]Enable on Place[/b][/color]  — When ON, UAP adds a physics body and collision shape to every asset the moment it is placed.

[color=#46a0f5][b]Body Type[/b][/color]
[b]StaticBody3D[/b]  — Default. The object cannot move. Use for floors, walls, terrain, props.
[b]RigidBody3D[/b]  — Physics-simulated. The placed object falls, bounces, and reacts to forces. The mesh becomes a child of the RigidBody.
[b]CharacterBody3D[/b]  — For character controller bodies.
[b]Area3D[/b]  — Creates a trigger zone or pickup area.

[color=#46a0f5][b]Shape Type[/b][/color]
[b]Trimesh[/b]  — Exact mesh collision. Most accurate, slowest at runtime. [b]Only valid for StaticBody3D and Area3D.[/b]
[b]Convex Hull[/b]  — Simplified convex wrapper. Works with all body types. Good balance of accuracy and speed.
[b]Box[/b]  — Simple bounding box. Very fast. Good for furniture, crates, buildings.
[b]Sphere[/b]  — Bounding sphere. Very fast. Good for round objects like rocks and barrels.
[b]Capsule[/b]  — Capsule shape. Good for pillars, poles, bottles.

""" + _warn("Trimesh collision is NOT valid for RigidBody3D or CharacterBody3D. UAP will warn you and upgrade to Convex Hull automatically.") + """

[color=#46a0f5][b]Auto-Unpack (FBX / GLTF Options)[/b][/color]
When ON (default), placed FBX/GLTF scenes are unpacked before collision is added, so shapes attach directly to each MeshInstance3D rather than as a sibling of the packed scene root.
"""

static var PHYSICS: String = _h("tab_physics", "PHYSICS TAB") + """

Take objects already sitting in your scene — a pile of props you dragged in by hand, a batch you just placed, anything selected in the viewport or Scene tree — lift them into the air, drop them, and let them fall, tumble to a stop, and settle naturally against the ground and each other. Turn physics off and everything freezes exactly where it landed.

This does not require pressing Play. Godot's own physics engine only steps while a scene is actually running, so the Physics tab drives its own lightweight simulation entirely inside the editor, sweeping each object's collision shape against whatever is already in your scene every frame.

[color=#46a0f5][b]Lift Selected Up[/b][/color]
[b]Height[/b]  — How far up (in meters) each selected object rises above its current position when you press the button below.
[b]Random Scatter[/b] / [b]Scatter Radius[/b]  — Nudges each object sideways by a random amount on lift, so a pile doesn't come down in a perfect grid.
[b]Random Rotation[/b]  — Randomizes each object's orientation on lift, for a natural-looking jumble of debris.
[b]Lift Selected Up[/b]  — Applies the above to whatever is selected right now. Its own undo step — you can lift without simulating, adjust by hand, then simulate whenever you're ready.

[color=#46a0f5][b]Simulation[/b][/color]
[b]Gravity[/b]  — Downward acceleration in m/s². Defaults to your project's Physics settings; raise or lower it for a heavier or floatier drop.
[b]Bounciness[/b]  — How much velocity survives a hard impact, from 0 (dead stop) to 1 (near-perfectly elastic). Soft, low-speed contact never bounces regardless of this value — only a genuinely hard landing does.
[b]Friction[/b]  — How aggressively sliding is worn down once an object is resting on a surface. Higher values bring a slide to a stop sooner, and a high enough value on a shallow slope will hold an object in place instead of letting it slide at all.
[b]Align to Ground[/b]  — When an object comes to rest, tilts it to match the slope it landed on (same normal-alignment Surface Mode uses for placement), preserving its facing direction — so it settles flat on flat ground and tips naturally on a slope, rather than staying locked to its original orientation.
[b]Random Tumble[/b]  — Adds a light, random spin while an object is airborne, for a less mechanical-looking fall. Stops the instant it lands.
[b]Max Fall Time[/b]  — A safety limit. If an object falls for this many seconds without landing on anything, it's stopped in place and a warning is printed — this is what catches a prop that fell off the edge of your level with nothing beneath it.
[b]Auto-Stop When Settled[/b]  — When ON (default), physics stops itself and bakes the result the instant every object in the batch has come to rest. Turn it off to keep control of exactly when to stop.

[color=#46a0f5][b]Auto Collision (temporary)[/b][/color]
Objects need collision to interact with the simulation. Anything already sitting under a StaticBody3D, RigidBody3D, or CharacterBody3D with a real shape is used exactly as it is and is never modified — this is also what drives that object's own falling motion, so a ball with a real SphereShape3D collider actually rolls like a ball instead of behaving like a box. [b]Auto-Add Missing Collision[/b] — when ON (default), anything with no collision at all gets a temporary shape added for the duration of the simulation only — it is never given an owner, so it does not get written into your scene file even if you save mid-simulation — and it is removed automatically the moment you press Stop or Cancel. Turn this OFF to skip objects with no collision entirely instead of adding anything to them automatically; the status line tells you how many were skipped. Existing collision is never touched, added to, or removed, either way, under any circumstances.
[b]Auto Shape (when missing)[/b]  — the shape used both for a temporary collider and for that object's own falling motion, for anything with no collision of its own: Box, Sphere, Capsule, or Convex Hull. This also decides the fallback shape for an object whose existing collision is a compound of several shapes (Convex Hull can't be built from more than one collider automatically, so it falls back to a bounding shape in that case). Match this to what you're actually dropping — Sphere for balls, Capsule for barrels or bottles — since a mismatched shape (a box standing in for a ball) can't roll or deflect the way the real object would, and dense piles in particular can behave oddly as a result. [b]Convex Hull[/b] builds an actual hull from the real mesh vertices rather than a bounding box, and is the most accurate all-round choice for an irregular mesh or a scene mixing several different shapes at once — it's also the most expensive shape to simulate, since matching against another Convex Hull costs more than matching simple shapes does, so prefer Sphere, Capsule, or Box when one of them already fits what you're dropping, and reserve Convex Hull for batches where nothing simpler will do.

[color=#46a0f5][b]Start Physics / Stop / Cancel[/b][/color]
[b]Start Physics[/b]  — Begins simulating whatever is currently selected. Falling, tumbling, and settling all happen live in the viewport.
[b]Stop[/b]  — Freezes every object exactly where it is right now and bakes the result as a single undo step. Works at any point, mid-fall or fully settled.
[b]Cancel[/b]  — Aborts and restores every object in the batch to exactly where it was before this simulation started. No undo step is created — it's as if physics was never run.

""" + _info("Undo (Ctrl+Z) only sees a simulation once it's been stopped and baked — it won't reach back into a simulation that's still running. Use Cancel to back out of one in progress.") + "\n" + _info("Selecting a parent and one of its own children together simulates only the parent — a child can't meaningfully fall independently of the node it's attached to.") + "\n" + _info("Dropping a large batch (hundreds of objects) at once is more CPU-intensive than placement — for very large scatters, settle them in smaller groups.") + "\n" + _info("An object landing at an angle tilts to match the ground once it settles (see Align to Ground) rather than tipping and rolling onto its side the way a real elongated object might — there's no simulated torque here, only gravity, sweeping, and contact response.")

static var GROUPS: String = _h("tab_groups", "GROUPS & FAVORITES") + """

Groups let you organise assets into named collections. The [b]Favorites[/b] group is built-in. Create as many custom groups as you need.

[b]New group name field + Add[/b]  — Type a name and click Add to create a new group. Every group appears as a recessed inset chip in the browser filter bar and as an inset row in the Groups page.
[b]X (per group)[/b]  — Deletes the group. Assets inside it are NOT deleted — they just lose group membership.

[color=#46a0f5][b]Five ways to add assets to a group:[/b][/color]
[b]1.[/b] Single-click an asset in the browser → choose a group from the [b]Add to group[/b] dropdown → click [b]Add[/b].
[b]2.[/b] Ctrl-click multiple assets → choose a group in the multi-select bar → click [b]Add All[/b].
[b]3.[/b] [b]Right-click any card[/b] (or a multi-selection) → [b]Add to Group ▸[/b] → pick the group.
[b]4.[/b] Click [b]Browse...[/b] in the \"Import Folder to Group\" section → choose a folder → all 3D assets found recursively in that folder are added to the group in bulk.
[b]5.[/b] [b]Drag & Drop[/b] — Drag asset files directly from Godot's FileSystem panel onto the browser area. If a group is currently active (you clicked its filter button), the dropped assets are added to that group automatically as well as to the global asset list.

[color=#46a0f5][b]Removing assets from a group:[/b][/color]
[b]Remove from Group[/b] button (Groups page) — Select one or more assets in the browser first, then click [b]Remove from Group[/b]. No dropdown needed — the plugin detects automatically which group(s) the asset belongs to:
  • Viewing a [b]specific group[/b] → removes from that group only.
  • Viewing [b]Favorites[/b] → removes from Favorites only.
  • Viewing [b]All[/b] or search results → removes from every group the asset is in.

[b]Multi-remove:[/b] Ctrl+Click or Shift+Click to select multiple assets in the browser, then click [b]Remove[/b] in the multi-select bar that appears. All selected assets are removed at once.

""" + _info("Removing from a group does not delete the asset file. It only removes the group membership.") + """

[color=#46a0f5][b]Using groups:[/b][/color]
• Click a group button in the browser filter bar to show only assets in that group.
• Enable [b]Random Group Placer[/b] in the Paint page to randomly pick from the active group on every placement.
"""

static var KEYS: String = _h("tab_keys", "KEYS TAB — CUSTOM SHORTCUTS") + """

Customise every keyboard shortcut used during placement. Click any shortcut button to enter recording mode, then press the key you want to assign.

[b]Rotate Y  (Shift = CCW)[/b]  → default [b]R[/b]
Spins the ghost around the Y axis. Shift reverses direction.

[b]Pitch X  (Shift = rev)[/b]  → default [b]E[/b]
Tilts the ghost forward or backward.

[b]Roll Z  (Shift = rev)[/b]  → default [b]Q[/b]
Rolls the ghost left or right.

[b]Scale Up[/b]  → default [b]][/b]
Makes the ghost bigger by 0.1. Hold Shift for fine steps of 0.025.

[b]Scale Down[/b]  → default [b][[/b]
Makes the ghost smaller. Hold Shift for fine 0.025 steps.

[b]Height Up[/b]  → default [b]Page Up[/b]
Raises the Height Offset by the step size.

[b]Height Down[/b]  → default [b]Page Down[/b]
Lowers the Height Offset.

[b]Layer Up[/b]  → default [b]Home[/b]
Moves the Grid Y plane up by one grid unit.

[b]Layer Down[/b]  → default [b]End[/b]
Moves the Grid Y plane down by one grid unit.

[b]Flip X[/b]  → default [b]G[/b]
Mirrors the ghost on the X axis (negative X scale).

[b]Flip Z[/b]  → default [b]B[/b]
Mirrors the ghost on the Z axis.

[b]Reset Transform[/b]  → default [b]T[/b]
Resets rotation to 0,0,0 and clears both flips.

[b]Reset All to Defaults[/b]  — Restores every shortcut to its factory default key.

""" + _info("Escape and Right Mouse Button always cancel placement — these cannot be rebound.") + "\n" + _info("Keys repeat when held. There is a short initial delay, then they accelerate for faster input.") + "\n\n" + _h("tab_keys", "FULL KEYBOARD SHORTCUT REFERENCE") + """

All shortcuts are active while placing (after clicking an asset card). All are rebindable in the Keys page.

[b]R[/b]  → Rotate Y clockwise  |  [b]Shift+R[/b] → counter-clockwise
[b]E[/b]  → Pitch forward  |  [b]Shift+E[/b] → backward
[b]Q[/b]  → Roll right  |  [b]Shift+Q[/b] → left
[b]][/b]  → Scale Up +0.1  |  [b]Shift+][/b] → fine +0.025
[b][[/b]  → Scale Down -0.1  |  [b]Shift+[[/b] → fine -0.025
[b]Page Up[/b]  → Height Up
[b]Page Down[/b]  → Height Down
[b]Home[/b]  → Layer (Grid Y) Up
[b]End[/b]  → Layer (Grid Y) Down
[b]G[/b]  → Flip X (mirror on X axis)
[b]B[/b]  → Flip Z (mirror on Z axis)
[b]T[/b]  → Reset Transform (rotation + flips to zero)
[b]Escape[/b]  → Cancel placement (always works)
[b]Right Mouse Button[/b]  → Cancel placement (always works)
[b]Alt + Scroll Up[/b]  → Height Offset up (any scroll mode)
[b]Alt + Scroll Down[/b]  → Height Offset down (any scroll mode)
[b]Ctrl + Scroll (browser)[/b]  → Resize thumbnail cards (54 px – 200 px)
[b]Ctrl + Left Click (browser)[/b]  → Toggle multi-select an asset
[b]Shift + Left Click (browser)[/b]  → Range-select assets
[b]Right Click (browser card)[/b]  → Quick actions: favorites, add to group, remove from list
"""

static var WORKFLOWS: String = _h("sec_workflow", "WORKFLOW EXAMPLES") + """

[color=#46a0f5][b]Workflow A — Placing a Grid-Aligned Building[/b][/color]
[b]1.[/b] Place page → Grid Size = 1.0, Snap to Grid = ON.
[b]2.[/b] Mode bar → click [b]Grid[/b].
[b]3.[/b] Collision page → Enable on Place = ON, Body = StaticBody3D, Shape = Box.
[b]4.[/b] Click the building asset in the browser.
[b]5.[/b] Move mouse to the desired grid cell. Press [b]R[/b] to rotate 90° if needed.
[b]6.[/b] Left-click to place. Press Escape when done.

[color=#46a0f5][b]Workflow B — Painting a Natural Forest[/b][/color]
[b]1.[/b] Create a group called \"Trees\". Add 3–5 different tree GLB files to it.
[b]2.[/b] Click the Trees group button in the filter bar.
[b]3.[/b] Mode bar → [b]Surface[/b]. Transform page → Enable Random Rotation (0–360°), Enable Random Scale (0.8–1.3).
[b]4.[/b] Paint page → Enable Paint Mode. Set Spacing to 0.3. Enable Scatter, Radius 0.5. Enable Random Group Placer.
[b]5.[/b] Click any tree in the browser, then hold and drag over terrain. Trees appear randomly.

[color=#46a0f5][b]Workflow C — Creating a Road with the Advanced Spline[/b][/color]
[b]1.[/b] Make sure terrain has StaticBody3D collision.
[b]2.[/b] Select your road mesh asset in the browser.
[b]3.[/b] Spline page → click [b]+ Create New Spline[/b]. The green [b]● SPLINE MODE ACTIVE[/b] banner confirms spline mode is on.
[b]4.[/b] Select the AdvancedSpline in the scene tree. Use the Path3D toolbar in the 3D viewport to draw control points.
[b]5.[/b] Spline page → click [b]Subdivide & Wrap (Exact Shape)[/b] to conform to terrain.
[b]6.[/b] Click [b]+ Deform (Roads)[/b]. Adjust UV Tile X (try 4–8) to fix texture stretching.
[b]7.[/b] Optionally add a [b]+ Scatter (Props)[/b] layer with lamp posts or barriers. For barrier layers with many repeated instances, enable [b]Use MultiMesh[/b] on that layer.
[b]8.[/b] Click [b]BAKE TO NODES (Finalize)[/b] if you need to edit individual pieces, or [b]BAKE TO MULTIMESH (Performance)[/b] if the layout is final and you want maximum runtime performance.
[b]9.[/b] Click [b]✕ Exit Spline Mode[/b] at any time if you want to resume normal asset placement before baking.

[color=#46a0f5][b]Workflow D — Performance Grass with MultiMesh[/b][/color]
[b]1.[/b] Paint page → Enable [b]MultiMesh Mode[/b]. Enable [b]Volumetric Brush[/b] (Radius 5.0, Density 3.0, Falloff 0.3).
[b]2.[/b] Mode bar → [b]Surface[/b]. Transform page → Enable Random Scale (0.7–1.3) + Random Rotation.
[b]3.[/b] Click your grass mesh in the browser.
[b]4.[/b] Hold left-click and drag over terrain. Thousands of instances, high performance.
[b]5.[/b] Click [b]Generate Instance Collision[/b] if physics interaction is needed.

[color=#46a0f5][b]Workflow E — High-Performance Spline Scatter with MultiMesh Bake[/b][/color]
[b]1.[/b] Spline page → click [b]+ Create New Spline[/b].
[b]2.[/b] Draw a path — a forest edge, a fence line, a river bank.
[b]3.[/b] Click [b]+ Scatter (Props)[/b] with your chosen asset. Leave [b]Use MultiMesh[/b] ON (it is on by default).
[b]4.[/b] Adjust Spacing, Rnd Yaw, Scale, and Offset until the preview looks right.
[b]5.[/b] When satisfied, click [b]BAKE TO MULTIMESH (Performance)[/b].
[b]6.[/b] The Path3D is removed and a [b]*_MMBaked[/b] node group appears in the scene tree containing one [b]MultiMeshInstance3D[/b] per scatter mesh type. Godot renders all instances in a single draw call — ideal for forests, rocks, flowers, or any dense scatter.

[color=#46a0f5][b]Workflow F — Settling a Debris Pile with Physics[/b][/color]
[b]1.[/b] Place or paint a handful of crates, rocks, or rubble roughly where you want the pile.
[b]2.[/b] Select all of them, then Physics page → set Height, enable Random Scatter and Random Rotation, click [b]Lift Selected Up[/b].
[b]3.[/b] Click [b]Start Physics[/b]. Watch them fall, tumble, and pile up against each other and the ground in the 3D viewport.
[b]4.[/b] Leave [b]Auto-Stop When Settled[/b] on and it bakes itself the moment everything comes to rest — or click [b]Stop[/b] any time to freeze it early.
[b]5.[/b] Not happy with the result? [b]Ctrl+Z[/b] and try again with a different Bounciness or Random Rotation.
"""

static var TIPS: String = _h("status_info", "TIPS & PERFORMANCE NOTES") + """

• All settings (grid size, mode, scale, shortcuts, groups) save automatically to [b]user://ultimate_asset_placer.cfg[/b] and restore on next launch.
• Assets land best when their pivot point is at the bottom centre of the mesh. If an asset floats or sinks oddly in Surface mode, the original file may have a poorly placed pivot.
• The ghost preview is purely visual and never saved to the scene. Only left-clicking places a real node.
• Use [b]MultiMesh Mode[/b] for any object you will paint more than ~50 copies of (grass, rocks, leaves, small decorations).
• Set thumbnail size smaller (Ctrl+Scroll down in the browser) if you have hundreds of assets — larger thumbnails use more memory.
• Use the [b]Format Filter[/b] to exclude formats you don't use — this speeds up scanning.
• Right-click assets you never use and choose [b]Remove from Asset List[/b] to declutter the browser without touching your files.
• For long spline roads, set UV Tile X = (road length in metres / mesh length in metres) to prevent texture stretching.
• You can switch placement modes while actively placing — the ghost updates instantly.
• [b]Thumbnail cache[/b] is stored in [b]user://uap_thumbnails/[/b]. Delete this folder to force all thumbnails to regenerate. This is useful if you replace an asset file with a different mesh but the old thumbnail is still showing.
• [b]HiDPI / 4K monitors[/b]: the plugin respects Godot's editor scale setting. If the panel looks too small or large, adjust [b]Editor → Editor Settings → Interface → Display → Editor Scale[/b] and restart.
• The Physics tab's temporary collision shapes never get written into your scene file, even if you save while a simulation is running — only real, pre-existing collision (yours) is ever permanent.
"""

static var TROUBLE: String = _h("sec_troubleshoot", "TROUBLESHOOTING FAQ") + """

[color=#f0b834][b]Q: The UAP panel is not showing after enabling the plugin.[/b][/color]
A: Restart the Godot editor. Check that the addon folder is named exactly [b]ultimate_placer[/b] inside [b]res://addons/[/b]. Check the Output panel for errors from plugin.gd.

[color=#f0b834][b]Q: Assets are not appearing in the browser.[/b][/color]
A: Check the Folder field points to a directory containing 3D files. Confirm the correct extensions are enabled in Format Filter. Click Refresh. If you just added files, let Godot's importer finish before scanning. Also check whether the assets were removed via right-click — restore them with [b]Restore Hidden[/b] in the Place page.

[color=#f0b834][b]Q: The ghost appears but clicking does nothing.[/b][/color]
A: Make sure your scene root is a Node3D (or any 3D node). UAP cannot place assets if the scene has a 2D root.

[color=#f0b834][b]Q: In Surface mode, the asset isn't sticking to my terrain.[/b][/color]
A: Add a [b]StaticBody3D[/b] with a [b]CollisionShape3D[/b] to your terrain mesh. Without collision, UAP falls back to Y = 0.

[color=#f0b834][b]Q: I can't add points to my spline / clicking places assets instead of editing the curve.[/b][/color]
A: You need to be in Spline Mode. Create a spline with [b]+ Create New Spline[/b] or select an existing one with [b]Use Selected Spline[/b] — both activate Spline Mode automatically. The green [b]● SPLINE MODE ACTIVE[/b] banner at the top of the Spline page confirms it is on. Then select the AdvancedSpline node in the Scene Tree and use the Path3D point-editing toolbar at the top of the 3D viewport.

[color=#f0b834][b]Q: \"Use Selected Spline\" says no valid node found.[/b][/color]
A: Select the AdvancedSpline [b]Path3D[/b] node itself in the scene tree (not a child). It must have the uap_path.gd script attached — only nodes created by \"+ Create New Spline\" have this automatically.

[color=#f0b834][b]Q: My spline nodes are named @Node123 in the scene tree.[/b][/color]
A: This was a bug in earlier versions. Splines are named AdvancedSpline, AdvancedSpline_2, etc. Placed assets use their filename. If you see old @NodeXXX names, they are from a previous session — you can rename them manually in the Scene Tree.

[color=#f0b834][b]Q: I pressed Ctrl+Z to undo a placed asset but the collision shape stayed in the scene.[/b][/color]
A: This was a bug in v1.4 when using [b]RigidBody3D[/b] auto-collision. Fixed in v1.5: undoing now correctly removes the RigidBody3D wrapper (along with the mesh and collision shapes inside it) as well as any sibling collision bodies for StaticBody3D / Area3D modes. If you have leftover collision nodes from a previous session, delete them manually — they will be named [YourAsset]_RB or [YourAsset]_Collision in the scene tree.

[color=#f0b834][b]Q: Scene thumbnails are not showing / showing the wrong scene.[/b][/color]
A: UAP generates scene thumbnails automatically when you switch away from or close a scene. [b]Open each scene at least once[/b], look at it in the 3D viewport, then switch to another scene. UAP captures a screenshot of the viewport at that moment and saves it permanently. If old wrong thumbnails are cached, delete the folder [b]user://uap_thumbnails/[/b] (found via Project → Open User Data Folder) and reopen your scenes.

[color=#f0b834][b]Q: I get a Trimesh warning in the Collision page.[/b][/color]
A: Trimesh cannot be used with RigidBody3D or CharacterBody3D. Switch the Shape Type to Convex Hull, Box, Sphere, or Capsule.

[color=#f0b834][b]Q: A .tscn card shows an orange warning border.[/b][/color]
A: That scene is currently open in the editor. You cannot place a scene inside itself. Open a different scene to use this asset.

[color=#f0b834][b]Q: Random scale / rotation is not working.[/b][/color]
A: Check the [b]Enable[/b] toggle inside the Random Scale or Random Rotation section is ON (checked). Also make sure Min and Max are different values.

[color=#f0b834][b]Q: Ctrl+Z does not undo a MultiMesh paint stroke.[/b][/color]
A: MultiMesh undo works per stroke (one press+release of left-click = one undo step). A long continuous drag counts as one step. Use regular placement mode for per-instance undo.

[color=#f0b834][b]Q: The plugin panel is too small / too large on my monitor.[/b][/color]
A: UAP scales with Godot's editor scale. Go to [b]Editor → Editor Settings → Interface → Display → Editor Scale[/b], set it to match your monitor DPI (e.g. 150% for 4K), and restart the editor. All UAP text and controls will scale identically to the rest of Godot's UI.

[color=#f0b834][b]Q: Physics — my object fell forever and never landed.[/b][/color]
A: There's nothing solid beneath its fall path. Add a [b]StaticBody3D[/b] with a [b]CollisionShape3D[/b] under it, or increase Max Fall Time if it just needs longer than the current setting. Max Fall Time stops it automatically either way and prints a warning naming the object, so nothing runs forever.

[color=#f0b834][b]Q: Physics — Start Physics is greyed out or does nothing.[/b][/color]
A: Select one or more [b]Node3D[/b] objects in the 3D viewport or Scene tree first — Physics acts on your current selection, the same as Lift Selected Up.

[color=#f0b834][b]Q: Physics — will this add permanent collision to my props?[/b][/color]
A: No. Collision added automatically because an object had none is temporary and is removed the moment you press Stop or Cancel — it never gets an owner, so it isn't written into your scene even if you save mid-simulation. If you want permanent collision on an object, use the Collision page's Enable on Place instead, or add it manually before simulating.

[color=#f0b834][b]Q: Physics — a big drop of Convex Hull objects feels slow to settle.[/b][/color]
A: Convex Hull is the most expensive Auto Shape to simulate — every frame checks each object's hull against everything nearby, and that comparison costs more between two hulls than between two simple shapes. For a large batch, switch Auto Shape to Sphere, Capsule, or Box (whichever actually matches what you're dropping) and simulate in smaller groups; save Convex Hull for batches where the object's real shape genuinely doesn't fit anything simpler.

[color=#f0b834][b]Q: What is the difference between BAKE TO NODES and BAKE TO MULTIMESH?[/b][/color]
A: [b]BAKE TO NODES[/b] unpacks every spline instance into an individual MeshInstance3D — best when you need to select, move, or delete specific pieces after baking. [b]BAKE TO MULTIMESH[/b] packs all instances of each mesh into a MultiMeshInstance3D, giving a single GPU draw call regardless of instance count. Use BAKE TO MULTIMESH for dense scatter layers (grass, rocks, trees) where you will not need to edit individual pieces at runtime.

[center][color=#7e8299]Ultimate Asset Placer  •  v{{VERSION}}  •  by Choco Ted  •  Godot 4.7+[/color][/center]"""

static var WELCOME: String = """[center][font_size=22][b][color=#46a0f5]ULTIMATE ASSET PLACER[/color][/b][/font_size]
[font_size=13][color=#7e8299]Complete Guide  —  v{{VERSION}}  |  Godot 4.7+  |  Made by Choco Ted[/color][/font_size][/center]

[color=#8899aa][img=15x15]res://addons/ultimate_placer/icons/sec_link.svg[/img] Plugin page:[/color] [color=#46a0f5][url=https://choco-ted.itch.io/ultimate-asset-placer-godot-45-gd-script]https://choco-ted.itch.io/ultimate-asset-placer-godot-45-gd-script[/url][/color]
[color=#f2c94c][img=15x15]res://addons/ultimate_placer/icons/feature_favorite.svg[/img] Enjoying the plugin? Please leave a rating:[/color] [color=#46a0f5][url=https://choco-ted.itch.io/ultimate-asset-placer-godot-45-gd-script/rate?source=game]Rate on itch.io[/url][/color]

""" + _h("sec_quickstart", "QUICK START — PLACE YOUR FIRST ASSET") + """

[b]1.[/b] Open a 3D scene (scene root must be a Node3D or any 3D node).
[b]2.[/b] In the [b]Asset Browser[/b] at the bottom, set the [b]Folder[/b] field to a folder that contains your 3D assets and click [b]Refresh[/b].
[b]3.[/b] [b]Left-Click[/b] any thumbnail card in the browser. A glowing blue ghost preview appears in the 3D viewport following your cursor.
[b]4.[/b] Move your mouse over the viewport and [b]Left-Click[/b] to place the asset. It appears with a small springy animation.
[b]5.[/b] [b]Right-Click[/b] or press [b]ESC[/b] to stop placing.

""" + _info("Every placement is fully undoable with Ctrl+Z.") + """

""" + _h("feature_search", "THE INTERFACE AT A GLANCE") + """

[b]Asset Browser (bottom panel)[/b]  — thumbnail cards of all your assets, with the Search & Filters header and the status bar.
[b]Settings panel (right dock)[/b]  — all feature pages live behind a vertical icon rail on the [b]LEFT edge[/b] of the panel, like Blender's toolbar. Hover any icon for its tooltip; click to open that page. No scrolling needed to reach a feature — every page is always one click away.
[b]Docs button (bottom of the rail)[/b]  — opens this documentation window. It is a popup, so your selected feature page stays exactly where you left it when you close the window.
[b]Active buttons are 3D[/b]  — wherever a choice is active (placement mode, scroll target, selected asset, docs chapter), the button is drawn as a solid raised 3D button: full color, a darker lower edge, and a soft drop shadow. Inactive buttons stay flat and dark — nothing semi-transparent.
"""

static var BROWSER: String = _h("sec_browser", "THE ASSET BROWSER") + """

The browser is the large bottom panel showing thumbnail cards of all your 3D assets. It scans your chosen folder automatically on startup.

[color=#46a0f5][b]Folder Controls[/b][/color]
[b]Folder field[/b]  — Shows the folder being scanned. Type a path and press Enter to change it.
[b]... (Browse)[/b]  — Opens a folder picker dialog to choose a folder visually.
[b]Refresh[/b]  — Re-scans the current folder to pick up any new files you have added.
[b]Clear[/b]  — Empties the browser and frees memory. Does not delete any files.

[color=#46a0f5][b]Search & Thumbnails[/b][/color]
[b]Search box[/b]  — Type any part of a filename to filter cards in real-time (case-insensitive).
[b]88px label[/b]  — Shows the current thumbnail size. [b]Ctrl + Scroll Wheel[/b] over the browser to resize thumbnails between 54 px and 200 px.

[color=#46a0f5][b]Group Filter Chips[/b][/color]
The [b]All[/b] / [b]Favorites[/b] / named-group chips under the search row use an [b]inset 3D look[/b]: they are recessed into the panel and darker than it. The active chip is highlighted with a deep blue inset and a light-blue label — you can always see which filter is live.

[color=#46a0f5][b]Selecting & Activating Cards[/b][/color]
[b]Left-Click[/b]  — Activates the asset for placement. The active card is drawn as a raised blue 3D card so you can instantly see what you are placing.
[b]Ctrl + Left Click[/b]  — Toggle-select an individual card (multi-select). Multi-selected cards are raised in amber.
[b]Shift + Left Click[/b]  — Range-selects all cards between the last clicked card and this one.
[b]Add All (multi-select bar)[/b]  — Adds all currently selected assets to the chosen group.
[b]X (multi-select bar)[/b]  — Clears the multi-selection.

[color=#46a0f5][b]Right-Click Menu on Any Card[/b][/color]
Right-clicking a card (or the whole multi-selection) opens a quick-action popup:
• [b]Add to Favorites / Remove from Favorites[/b]  — toggles the star for every targeted asset.
• [b]Add to Group ▸[/b]  — lists every group you have created; pick one to add the targeted assets to it.
• [b]Remove from Asset List[/b]  — hides the targeted assets from the browser. Files are [i]not[/i] deleted — restore them any time via the Place tab → Format Filter → [b]Restore Hidden[/b] button.

""" + _info("If the right-clicked card is part of the current Ctrl/Shift selection, the menu applies to ALL selected cards at once.") + """

[color=#46a0f5][b]Favorites Star[/b][/color]
Every card has a star in its [b]top-right corner[/b]. Click it to favorite an asset; favorited cards show a gold star and appear under the Favorites filter.

[color=#46a0f5][b]Drag & Drop[/b][/color]
Drag 3D asset files directly from Godot's FileSystem panel onto the browser area. UAP adds them even if they are outside your current scan folder. If a group filter is currently active, dragged assets are automatically added to that group as well.

[color=#46a0f5][b]Status Bar & Stop Button[/b][/color]
[b]Status bar[/b]  — Shows what UAP is doing: scanning, building, placing, or idle.
[b]Stop[/b]  — Immediately cancels the current placement session. Same as pressing Escape or right-clicking in the viewport.
"""

static var MODES: String = _h("tab_place", "PLACEMENT MODES") + """

At the top of the Settings panel are [b]four[/b] mode buttons: [b]Free, Grid, Surface, Vertex[/b]. These control [i]where[/i] and [i]how[/i] your asset snaps into the world. The active mode is drawn as a solid raised 3D button in its own color — Free (grey), Grid (blue), Surface (green), Vertex (yellow) — with a darker bottom edge. You can switch modes at any time, even mid-placement.

""" + _info("Spline is not a mode button. It has its own dedicated Spline page in the left rail. Use the Spline page to create or activate a spline — this automatically suspends normal placement so viewport clicks edit the curve instead of placing assets.") + """

[color=#888899][b]── FREE MODE ──[/b][/color]

The simplest mode. Your asset floats on an invisible horizontal plane at the current Grid Y height. No snapping — the asset goes exactly where your mouse is.

[b]Best for:[/b] Placing single objects manually at a precise XZ position, or floating objects at a specific height.

""" + _info("Use Height Offset (Place tab) to raise or lower where objects land on the Y plane.") + """

[color=#46a0f5][b]── GRID MODE ──[/b][/color]

Snaps your asset to a visible XZ grid. Set the cell size (e.g. 1 m, 0.5 m) and every placement snaps to the nearest grid intersection. A blue grid appears in the viewport to guide you.

[b]Best for:[/b] Modular buildings, tile-based layouts, any grid-aligned level design.

[b]Grid Size[/b]  — Cell size in metres (0.0625 m to 200 m). Click [b]1m[/b] to quickly reset to 1 metre.
[b]Grid Y[/b]  — The height of the grid plane. Use the [b]v[/b] and [b]^[/b] buttons to step it by one grid unit.
[b]Show Grid toggle[/b]  — Hides or shows the blue grid lines (snap still works when hidden).
[b]Snap to Grid toggle[/b]  — Disabling this makes the floor behave like Free mode (no XZ snap).
[b]Layer Up / Layer Down keys[/b]  — Default [b]Home[/b] / [b]End[/b]. Moves the grid plane up or down by exactly one grid unit — great for multi-floor buildings.

You can also enable the [b]X Axis Grid[/b] (orange XY wall) and the [b]Z Axis Grid[/b] (green ZY wall) from the Place tab. When several grids are on, whichever plane is closest to the camera under your mouse receives the placement — look at the floor to place on the floor, look at a wall to place on the wall.

[color=#45e055][b]── SURFACE MODE ──[/b][/color]

Fires a physics raycast from your cursor into the scene. Your asset snaps to whatever physics surface is hit — terrain, a floor, a rock face, anything with a collider.

[b]Best for:[/b] Placing props on uneven terrain, populating landscapes, decorating organic surfaces.

[b]Align to Normal (Place tab)[/b]  — When ON, the asset tilts to match the slope of the surface it lands on (like a tree growing on a hillside). When OFF, the asset always stays upright.

""" + _warn("Surface mode requires your terrain to have a StaticBody3D + CollisionShape3D. Without collision, UAP falls back to placing at Y = 0.") + """

[color=#f0b834][b]── VERTEX MODE ──[/b][/color]

Moves freely like Free mode, but magnetically snaps to mesh corners (vertices) when the ghost gets close enough. A precise alignment tool.

[b]Best for:[/b] Snapping furniture to wall corners, aligning modular pieces, placing objects exactly on mesh boundaries.

[b]Magnet px[/b]  — How close in screen pixels the ghost must be before snapping triggers. Default: 42. Higher = stronger magnet.
[b]Mesh Vertex Snap toggle[/b]  — ON: tests actual mesh geometry vertices (more accurate, slower). OFF: tests bounding-box corners (faster).
"""

static var SCROLL: String = _h("sec_scroll", "SCROLL WHEEL CONTROL") + """

Directly below the mode buttons, six buttons decide what the mouse wheel does while placing: [b]Off, Scale, Rot Y, Rot X, Rot Z, Height[/b].

The active choice — [b]including Off[/b] — is always highlighted with the blue raised 3D button style, so the panel never leaves you guessing what the wheel currently does.

[b]Off[/b]  — Scroll wheel is free (default). Use keyboard shortcuts for rotation and scale.
[b]Scale[/b]  — Scroll up = bigger. Scroll down = smaller. Each step changes scale by 0.1.
[b]Rot Y[/b]  — Scroll to spin the ghost around its vertical axis.
[b]Rot X[/b]  — Scroll to pitch the ghost forward or backward.
[b]Rot Z[/b]  — Scroll to roll the ghost left or right.
[b]Height[/b]  — Scroll to raise or lower the Height Offset.

""" + _info("Alt + Scroll Wheel always adjusts Height Offset, regardless of the Scroll Mode setting.")
