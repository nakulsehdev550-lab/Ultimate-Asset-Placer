# Ultimate Asset Placer — Changelog

## v2.2.0 — UI polish pass ("carved" groups, square cards, smarter collapse)

A refinement pass over the v2.1 UI, driven by hands-on feedback from a real
editing session. Verified against a **real Godot 4.7.1 editor** with rendered
screenshots of every tab, the browser, both header states, the hover names
and the context menu.

### Fixed / changed
- **No dark text outline on active buttons.** The placement-mode and scroll
  buttons drew their white labels with a dark font outline; labels are now
  plain near-white.
- **Groups are carved in, everywhere, with one design.** Section boxes, group
  chips and group rows share the same recessed style: a fill clearly darker
  than the panel, **no outline border on any side**, and a single darker line
  along the BOTTOM edge — the box reads as chiseled into the panel. The old
  semitransparent blue border and accent-tinted header fill are gone.
- **Square asset cards.** Cards are perfectly square cells with a landscape
  (rectangular) thumbnail area on top and the asset name inside the card at
  the bottom — replacing the old portrait cards whose name rows overflowed
  their grid slot and visually overlapped neighbours.
- **Overlap is now structurally impossible.** The grid column count uses
  exact slot math (`(width + sep) / (card + sep)`), so every row fits the
  visible width precisely; verified programmatically in the editor
  (squareness, zero cell intersections, exact x-positions).
- **Thumbnails never stretch.** Renders keep their aspect ratio inside the
  landscape well (square renders pillarbox neatly). Small editor fallback
  icons now draw at native size instead of being blown up into a blurry
  fill-the-well icon.
- **Favorite star fully inside the card** (top-right corner, small inset) on
  the new square card, at every editor scale.
- **Search & Filters sub-collapse removed.** The folder / search / group rows
  are always visible while the header is expanded.
- **Advanced header collapse.** Collapsing the master bar now moves the group
  chip strip INTO the title bar — title and version hide, and every group
  stays directly clickable in the slim state. Expanding moves the chips back
  below the search row.
- **Rail hover names.** Hovering a left-rail icon instantly pops a small name
  label ("Place", "Transform", … "Docs") beside the rail — no native tooltip
  delay.
- **Active tab title bar.** The name of the active feature tab is written on
  a slim carved bar on top of the tab panel and follows tab changes.

### Internal
- Version bumped to 2.2.0 (plugin.cfg, README).

## v2.1.0 — Full UI Overhaul ("3D tactile" design language)

A ground-up visual overhaul of the plugin's editor UI, plus a new asset-card
context menu and a chapter-based documentation window. As with v2.0, every
change was verified against a **real Godot 4.7.1 editor** with rendered
screenshots of every tab, the docs window, the context menu, and all new
button states.

### New: consistent 3D tactile button language
- **Active buttons are now drawn "raised" in 3D**: a solid, fully-opaque
  color face (no more semitransparent fills), a darker bottom bevel, and a
  soft drop shadow. Inactive buttons are clean flat dark with a subtle
  hover — the harsh white editor-theme highlight is gone everywhere.
- **Placement mode buttons** (Free/Grid/Surface/Vertex): the active mode is
  solid in its own color — Free grey, Grid blue, Surface green, Vertex
  yellow — with white outlined text for readability on bright colors.
- **Scroll Wheel Control buttons**: the active target now uses the blue
  raised 3D style, and **"Off" is highlighted too** — previously the active
  state of Off was invisible. Every active state is now always visible.
- **Selected asset card**: raised blue 3D (solid face + darker bottom edge).
  Multi-selected cards use the same raised treatment in amber. Idle cards
  keep their neutral dark look with no transparency.
- **Left feature rail** (see below): the active feature icon is raised blue.

### New: Blender-style left feature rail
- The horizontal feature tabs (Place, Transform, Paint, Spline, Material,
  Groups, Keys, Collision, Physics) sat at the top of the panel and
  **required horizontal scrolling** in a docked layout to reach them.
- They are now a **vertical icon-only rail on the LEFT edge of the panel**,
  exactly like Blender's editor toolbar: every feature page is permanently
  one click away, with hover tooltips, no scrolling, no clipped tabs.
- The active rail button is highlighted with the blue raised 3D style.

### New: chapter-style Docs window
- The Docs tab is gone from the panel. The rail's **Docs button now opens a
  dedicated documentation window in the center of the screen**.
- The manual was completely rewritten into **15 chapters** (Welcome &
  Quick Start, Asset Browser, Placement Modes, Scroll Wheel, Place,
  Transform, Paint, Spline, Material & Collision, Physics, Groups &
  Favorites, Keys & Shortcuts, Workflow Examples, Tips & Performance,
  Troubleshooting), listed in a **clickable chapter sidebar** on the left.
- The window is fully dark-themed; links stay clickable. Closing it
  restores the rail highlight to the feature page that was selected before —
  the Docs button only ever opens the popup and never steals your place.

### New: right-click context menu on asset cards
- Right-click any card (or any multi-selection) to get quick actions:
  **Add/Remove Favorites**, **Add to Group ▸** (submenu listing your groups),
  and **Remove from Asset List**.
- **Remove from Asset List** hides assets from the browser (with a persisted
  hidden list) **without deleting any files** — restore them any time via
  *Place tab → Format Filter → Restore Hidden*.
- The menu is dark-themed to match; the destructive action's icon is red.

### Groups UI — inset 3D
- Group/filter chips (All / Favorites / named groups) no longer use the
  default pressed-blue-with-outline style. They are now **inset 3D**:
  recessed into the panel, darker than it, with a dark top inner edge.
- The active chip is a deep blue recess with a light-blue label (and a gold
  star when Favorites is active). Fixed a pre-existing bug where every chip
  ever clicked stayed visually pressed — **exactly one chip reads as active
  at any time** now.
- Group rows in the Groups page use the same inset style (icon, name,
  asset count, delete button).

### Fixed: favorite star overflow
- The favorite star button used to be positioned with `position`/`size`
  while its parent still had zero size, baking wrong offsets — the star
  visibly overflowed **outside** the card's top-right corner (see user
  screenshot). It is now anchored with explicit top-right offsets and sits
  cleanly **inside** the corner at every editor scale.

### Fixed: first-import icon race (extended)
- v2.0's `refresh_icons()` re-applied tab icons after Godot finished
  importing the addon's SVGs. The favorite stars, header chevrons, and rail
  icons had the same first-run race but weren't covered — they could stay
  blank until restart on a brand-new install. All of them now refresh too.

### Misc
- Version displayed everywhere is 2.1.0 (single source of truth in
  `plugin.cfg`, unchanged mechanism).
- All v2.0 functionality, shortcuts, and config keys are unchanged; the new
  hidden-assets list persists alongside existing config data and migrates
  safely from older configs.

---

# Ultimate Asset Placer — v2.0 Changelog

Upgrade pass: Godot 4.5+ -> Godot 4.7+, full bug/edge-case sweep, icon system
wiring, and new features.

## Test methodology
Every change below was verified against a **real Godot 4.7.1 editor** (the
exact binary from godotengine/godot's GitHub releases), not just read-through
or guesswork:
1. `--headless --editor --import --quit` on a throwaway test project with the
   addon installed — catches parse errors, missing methods, and plugin
   init/load failures. Run after every single file change.
2. Small `--headless --script test_x.gd` SceneTree scripts that instantiate
   the actual modified classes and assert on real return values/behavior —
   150+ automated checks total across every modified script, all passing.
3. Godot's own official 4.5->4.6 and 4.6->4.7 migration guides, fetched and
   read directly, for the compatibility notes at the bottom of this file.
4. **A hard environment limit, found and disclosed rather than glossed
   over:** `MultiMesh` per-instance transform data is stored in a
   RenderingServer-backed GPU buffer. Verified directly (with a test
   completely isolated from this plugin's own code) that under
   `--headless`'s dummy rendering driver, `MultiMesh.get_buffer()` returns
   **empty** even for a bare MultiMesh with one instance and one transform
   just set on it — so reading instance transforms back to check scale/
   rotation isn't possible in this environment, for any code, not just this
   plugin's. Where this affected verification (the new spline taper/twist
   feature below), the underlying math was instead traced and confirmed
   directly, and the actual visual output should be spot-checked once in a
   real editor session, the same as any MultiMesh-based rendering.

---

## Second pass — bugs found on further review + requested new features

### Material override — a real bug, found, reproduced, and fixed
Not the MultiMesh issue from the first pass — a separate, confirmed bug in
**regular (non-MultiMesh) placement**, reproduced with a real test scene
before touching any code:
- "Override" mode (mode 0, the default): sets `material_override` on the
  placed node directly. Verified this is safe — Godot treats it as a true
  per-instance property, unaffected by resource sharing.
- **"Next Pass" mode (mode 1): confirmed broken.** Godot does not duplicate
  sub-resources on `PackedScene.instantiate()` unless they're marked "local
  to scene" — which imported assets normally are not, and this is
  especially common for glTF/GLB imports, which typically apply their
  materials via a per-surface override slot rather than baking them into
  the Mesh resource. The old code read that pre-existing override and
  mutated its `next_pass` **in place** when one already existed, only
  duplicating when falling back to the mesh's own baked-in material. Since
  every instance of that asset shares the exact same override-material
  object, this silently re-materialized every other placed copy — past
  *and* future — the instant Next Pass override was used on a new one.
  Reproduced with a minimal test scene (confirmed the shared object was
  the same, `==`, on both instances, and that mutating one changed the
  other), fixed by always duplicating before mutating regardless of which
  branch the source material came from, then re-ran the exact same
  reproduction against the fix and confirmed the objects are now
  independent (`==` false) and the untouched instance is provably
  unaffected.

### Asset Zoo nametag bug — fixed
Names were assigned *after* `add_child()`, so Godot's own auto-uniquify
silently kicked in whenever two zoo items shared a basename (e.g. the same
filename present in two different source folders), producing inconsistent
suffixes that didn't match what the Label3D above each item said. Fixed by
resolving a unique name up front, before adding to the tree — the same
pattern already used for regular placement.

### New: Ctrl+A / Cmd+A select-all in the browser
Selects every asset currently visible under the active search/format/group
filter. Scoped to "mouse over the browser" and skips a focused LineEdit/
TextEdit, so it doesn't hijack Ctrl+A from a text field's own select-all-text
behavior, or from other parts of the editor when the browser isn't what
you're looking at. The repeated card-highlight styling logic (previously
duplicated in three places) was also factored into one shared helper while
adding this.

### New: Alt+Click eyedropper / pick-similar
Alt+Click an already-placed object in the viewport to make its source asset
the active one for further placement — the standard "eyedropper" pattern
from most level/DCC tools, previously absent. Walks up from a physics
raycast hit to the nearest ancestor with a `scene_file_path` set. Limitation
worth knowing: like Surface-mode raycasting (which it reuses), it can only
pick objects that have a collision shape — a purely decorative prop placed
with Auto Collision off won't be pickable this way.

### New: Spline scale-along-curve (taper) and twist-along-curve
The most requested item from the feature list — "scale and deformation the
way Blender/professional tools handle curves." Added per-layer `scale_start`
/ `scale_end` (linearly interpolated along the curve — e.g. a fence post
thicker at the base, a road that narrows toward one end) and `twist` (total
rotation in degrees accumulated from start to end, for a screw/rope-twist
effect), for **both** Scatter layers (applied per placed instance) and
Deform/pipe layers (applied per-vertex, in the correct order — taper and
twist happen in local cross-section space before the curve's own sampled
transform is applied). The interpolation math was traced directly and
confirmed correct (see the environment-limitation note above for why the
final MultiMesh-rendered output couldn't also be checked here).

### Thumbnail system overhaul
- **Dynamic resolution tiers** (64/96/128/192/256px) driven by the browser's
  preview-size slider — small previews (many cards visible at once) render
  and cache at a small, fast tier; large previews (fewer cards, each bigger)
  get a sharp, higher-res tier. Each tier caches independently on disk, so
  dragging the slider back to a size you've already visited is instant. Also
  a real performance win on lower-end hardware: most of the time the
  browser is showing small cards, and those now cost meaningfully less to
  generate than a flat 256px did for every single one.
- **Anti-aliasing added** — the offline render viewport previously had no
  `msaa_3d` set at all (aliased/jagged edges by default); now uses 2x for
  small/frequent tiers and 4x for large/rare ones.
- **Tighter, evidence-based camera framing.** The old fit used the AABB's
  full diagonal as a blanket radius — geometrically equivalent to treating
  every object as if bounded by a sphere, which is very conservative for
  long/thin or flat assets (fences, planks, floor tiles — extremely common
  in a level-design library), leaving them small and adrift instead of
  filling the frame. Replaced with a proper projected-extent fit along the
  camera's actual right/up axes for its fixed viewing angle. Verified with
  synthetic shapes: equal or tighter in every case tested, never worse, and
  centering confirmed exact (camera provably looks at the true AABB center).
- **Investigated switching to a transparent thumbnail background and
  decided against it** — not guessed. Searched Godot's own issue tracker
  first: `SubViewport` with `transparent_bg` has a documented, still-open
  premultiplied-alpha bug that darkens anti-aliased edges, plus reported
  inconsistencies across renderer backends. Pursuing "official-style"
  transparency would likely have *introduced* the exact edge artifacts this
  overhaul was meant to remove. Kept the existing solid background, which
  has no such known issues.

---

## plugin.gd
- Fixed stale hardcoded "v1.4" startup print not matching plugin.cfg's real
  version — now reads the version from plugin.cfg at runtime so this can
  never silently drift again.
- **Cache-collision bug (real, verified):** plugin.gd's scene-screenshot
  cache and uap_thumb_gen.gd's asset-thumbnail cache both wrote to
  `user://uap_thumbnails/` keyed by the *same* `md5_text()` of the resource
  path. Any `.tscn` that is both a placeable asset and a scene you sometimes
  open directly would have one cache silently overwrite the other's PNG —
  this is very likely why 3D previews looked wrong/stale for some assets.
  Fixed by splitting into `uap_thumbnails/scenes/` and `uap_thumbnails/assets/`.
- Added orphaned-thumbnail cleanup: previously, renaming/deleting a scene
  left its cached screenshot on disk forever. Now tracked via a small
  manifest and reconciled once per editor session, plus a soft file-count cap.
- Added a one-time migration pass that clears stray PNGs from the old flat
  pre-2.0 cache folder (guaranteed stale under the new split scheme).

## uap_path.gd
- `_get_first_mesh` now also recognizes `MultiMeshInstance3D`-rooted assets,
  not just `MeshInstance3D` — previously an asset whose first renderable was
  a MultiMesh would silently produce an empty scatter/deform layer.
- Terrain-probe raycast distance (`_raycast_down`) is now `@export`-tunable
  (`terrain_probe_up` / `terrain_probe_down`, much larger defaults) instead
  of a hardcoded ±100/-1000 that could miss terrain on large/tall scenes.
- `snap_lowest_to_ground()` / `conform_to_terrain()` now return a
  `{hit, total}` Dictionary instead of `void`, so the panel can report
  partial failures ("6/8 points found ground") instead of failing silently.
- Added a `build_warning(message)` signal, emitted when a scatter/deform
  layer's mesh path can't be resolved — previously a typo'd or moved asset
  path in a spline layer failed completely silently.
- `bake_to_nodes()` / `bake_to_multimesh()` now refuse to run (with a clear
  `push_error`) if no valid scene root can be found, instead of silently
  creating nodes with `owner = null` that would vanish the next time the
  scene was saved and reopened.
- Baked collision now respects a `shape_type` parameter (Trimesh / Convex /
  Box / Sphere / Capsule) shared with the rest of the plugin's collision
  system, instead of always hardcoding Trimesh regardless of the user's
  configured preference.

## uap_thumb_gen.gd
- Same cache-directory split as plugin.gd above (this is the other half of
  that fix).
- **3D thumbnails silently permanent-failed for imported model formats**
  (.glb/.gltf/.obj/.fbx/.dae/...): the offline SubViewport fallback rejected
  any path whose extension wasn't literally "tscn" or "scn" before ever
  trying to load it — even though the very next line already loads it
  generically as a PackedScene and already has a correct type-check safety
  net. If EditorResourcePreview ever failed for one of these formats (which
  happens, e.g. right after a fresh import), the asset was stuck with no
  thumbnail forever, with no fallback. Removed the extension gate; the
  existing `res is PackedScene` check is the real, sufficient guard.
- **CSG shapes (and Sprite3D/Label3D/decals/particles) now use their real,
  computed bounding box** via `VisualInstance3D.get_aabb()`, instead of a
  hardcoded 2x2x2 (or 1x1x1) guess. Verified empirically against a live
  Godot process: `get_aabb()` returns the true box exactly one process frame
  after entering the tree — which is exactly the existing timing in this
  file — so CSG-built assets (and text/sprite-only assets) now frame
  correctly in their thumbnail instead of being mis-scaled.
- Hardened both `await get_tree().process_frame` sites (3D and 2D render
  paths) to also check viewport validity after resuming, not just the
  instance — protects against edge cases where the plugin is disabled or
  the editor is closing mid-render.
- Removed dead `_collect_rect2d_recursive` stub (explicitly superseded by
  `_collect_rect2d_r`, left behind unused).

## ultimate_placer.gd
- **Removed an entire dead spline subsystem** (`_spline_path`, `_spline_instances`,
  `_spline_dirty`, `spline_rebuild()`, `spline_set_closed()`, `spline_commit()`,
  `_spline_add_point()`, `_spline_smooth_tangents()`, `_do_spline_rebuild()`).
  Traced and confirmed every one of these was leftover from an earlier, simpler
  spline implementation and never actually wired to the real Advanced Spline
  System (`uap_path.gd`, driven entirely through `ultimate_panel.gd`'s
  `_active_spline_tool`). None of it did anything; some of it was actively
  harmful (see next point).
- **Fixed a real click-swallowing bug** this dead code caused: if the user had
  an asset actively selected for placement and then switched into Spline mode
  without cancelling first, `_is_placing` stayed true, and every subsequent
  left-click in the viewport was silently consumed and dropped — with zero
  feedback, and with Godot's native Path3D point-editing toolbar never
  receiving the click either. Spline-mode clicks are now explicitly passed
  through untouched.
- Brush mask textures that are VRAM-compressed (Godot's default import mode
  for most textures) now get `.decompress()`'d before pixel sampling —
  previously `get_pixel()` on a still-compressed Image would fail/return
  garbage, silently breaking custom brush masks depending on import settings.
- **Undo/redo correctness bug, fixed:** redoing a Surface-mode placement after
  switching to a different mode used to silently reproduce it wrong (skipping
  the anti-clip normal push), because `_do_place`/`_redo_place` re-read the
  *current* place mode instead of using the mode captured when the placement
  was originally made. The mode is now captured at commit time and threaded
  through explicitly, matching how `align_normal` was already (correctly)
  handled.
- **Vertex-snap performance:** `_hit_vertex` rebuilt the full scene mesh list
  via a recursive tree walk on *every mouse-motion event* while in Vertex
  mode — a severe perf cliff on scenes with thousands of meshes (exactly what
  this plugin advertises itself for). Now cached, invalidated only when the
  scene tree actually changes (via `SceneTree.node_added`/`node_removed`).
- **Brush painting had no time/distance throttle at all** — it fired once per
  raw mouse-motion input event, and OS/driver mouse-move event rates vary
  hugely, so painting slowly (many events, little distance) could deposit
  unbounded amounts of instances in one spot while a fast sweep deposited
  comparatively few. Now gated to a fixed wall-clock interval.
- The per-call attempts cap was a flat 12 regardless of brush radius/density,
  which meant probability saturated to ~1.0 for any reasonably sized brush —
  in practice the density slider stopped doing anything past small brush
  sizes, and big/dense brush configurations couldn't look as dense as
  configured. Raised to 150 (safe now that call *frequency* is separately
  throttled above).
- **MultiMesh material override bug, fixed:** the override material was only
  ever applied at the moment a MultiMeshInstance3D was first created for a
  given asset. If you painted an asset, *then* enabled Material Override, and
  kept painting the same asset, the override never applied to it — the
  function returned the cached instance before ever reaching the override
  check. Now re-synced on every call, and correctly clears back to the
  mesh's own material if the override is later disabled.

## ultimate_panel.gd
- Fixed the caller of the now-removed `spline_clear()` — `_on_stop_pressed()`
  now properly calls `_exit_spline_mode()` for place_mode 4, matching the
  documented non-destructive "Exit Spline Mode" behavior instead of erroring.
- `_enter_spline_mode()` now defensively calls `cancel_placement()` on the
  placer — belt-and-suspenders alongside the placer-side click-swallow fix.
- Fixed the **persisted place_mode==4 bug**: closing the editor while Spline
  mode was active used to reload straight back into place_mode 4 with no
  active spline tool — the plugin looked completely dead (no ghost cursor,
  viewport clicks silently swallowed) with zero indication why, until the
  user happened to click a mode button. Clamped on load now.
- **Icons wired throughout**: all 9 dock tabs (via Godot's native
  `set_tab_icon()`, replacing the emoji baked into tab title text), the
  Favorites star (dropdowns now use `add_icon_item()` instead of emoji-in-
  text, 5 call sites), Exit Spline Mode, the spline status indicator
  (restructured from a plain Label into an icon+label row instead of baking
  a ●/○ character into the text), section-collapse chevrons, pagination
  arrows, the folder browse button, refresh, and the grid-height nudge
  buttons. Centralized through a new `uap_icons.gd` registry
  (`UAPIcons.get_icon()` / `set_button_icon()` / `tint_button()` for
  theme-color tinting instead of shipping colored file duplicates) rather
  than scattering 50+ raw preload paths through the panel.
- **"Resizable tabs" investigated and fixed properly.** Verified against
  Godot's own documentation (not assumption) that `clip_tabs=true` on the
  Settings TabContainer was already correct — it's what lets the dock shrink
  to any width with scroll-arrows as a fallback, rather than forcing a wide
  minimum so all tab headers always fit. The Browser dock's column-reflow-
  on-resize was also already correctly wired. The actual bug: every Settings
  tab's `ScrollContainer` had horizontal scrolling hard-disabled, so at
  narrow dock widths, row content (fixed-width labels + controls) had
  nowhere to go — genuinely unreachable, not just visually cramped. Switched
  to `SCROLL_MODE_AUTO`, which only shows a scrollbar when content actually
  overflows — no visible change at normal dock widths.
- **New feature — Asset Zoo source picker.** The zoo could previously only
  ever be built from every asset ever loaded into the browser. Added a
  Source dropdown: All Loaded Assets / Current Group Filter / Selected
  Assets (using the existing multi-select), each with its own validation
  messaging, persisted across sessions.
- Wired the new `Dictionary`-returning `snap_lowest_to_ground()` /
  `conform_to_terrain()` and the `build_warning` signal (both added in
  uap_path.gd this pass) into real status-bar messages instead of leaving
  them unused — terrain snapping and mesh-load failures now actually tell
  you what happened.

## uap_docs.gd
- Replaced all 17 emoji section-header markers, all 19 tip markers, all 7
  warning markers, and the rating-call-to-action star with real `[img]`
  BBCode tags pointing at the same icon set used in the live UI — verified
  every single one actually resolves to a real resource, not just visually
  spot-checked (43 image tags total).
- Updated the version/engine banner from "v1.5.0 | Godot 4.5.1" to
  "v2.0.0 | Godot 4.7+".
- Documented the new Asset Zoo Source picker.

## plugin.cfg
- Version bumped 1.5.0 -> 2.0.0; description updated to mention Godot 4.7+
  and the Advanced Spline System (which existed in 1.5 but wasn't mentioned
  in the plugin description).

## New icon system
54 SVG icons (24x24, white-on-transparent, tinted at runtime via Godot's
`icon_normal_color`/etc. theme overrides rather than shipped as colored
duplicates) replacing every emoji and raw-text glyph (`v`, `>`, `...`, `<`,
`●`/`○`) previously baked into button text or tab titles. Delivered
separately as `ultimate_placer_icons.zip` earlier in this thread; now fully
wired into the actual UI rather than just generated.

**First-install note, found via testing a genuinely fresh project (not
guessed):** the very first time this addon is dropped into a project, Godot
has to import 54 brand-new .svg files it's never seen before. If the dock UI
finishes building before that import pass completes, buttons show up with
their text label but no icon yet — everything still works, nothing crashes,
it's cosmetic only. `uap_icons.gd` never caches a failed lookup (so a retry
is always free) and `plugin.gd` listens for Godot's own
`resources_reimported` signal to re-apply tab icons once import catches up;
in testing this closes the gap for normal, longer-lived editor sessions, but
a single ultra-short scripted session isn't enough to observe it resolve
end-to-end. **The simple, always-effective fix:** after installing or
updating this addon, do Project -> Reload Current Project once. This is
standard practice for any Godot addon shipping new binary/image assets, not
specific to this one.

## Known limitation (found via testing, disclosed rather than papered over)
`ultimate_panel.gd`'s `_ready()` awaits two process frames before finishing
startup (letting the UI layout settle before measuring control sizes). If
the panel is hard-freed *during* that exact two-frame window — which in
practice means disabling the plugin or closing the editor within a couple
of frames of it loading — Godot logs a "Resumed function after await, but
class instance is gone" error. This is an engine-level detection that fires
*before* any of our own GDScript runs, so there is no code-level guard that
eliminates it in that absolute worst case. It's an extremely narrow window
(discovered via an automated test doing a harder/faster teardown than any
realistic editor interaction produces) and doesn't affect normal use.

## Godot 4.7 compatibility notes
Checked the official 4.5->4.6 and 4.6->4.7 migration guides directly. None
of the documented breaking changes (BlendSpace point handling, the audio
spectrum analyzer API, the mouse/keyboard device-ID numbering scheme,
particle angular-velocity corrections, shader preprocessor restrictions,
OBB Android export removal, scene-file unique-node-ID changes) touch any
API surface this plugin uses — no shaders, no BlendSpace, no audio, no
particles-with-angular-velocity, no Android OBB export. The plugin's core
APIs (EditorPlugin docks, EditorInterface, SubViewport offline rendering,
MultiMesh, Path3D/Curve3D, physics bodies, EditorResourcePreview,
EditorFileDialog, ConfigFile) are not mentioned in either breaking-changes
list. One adjacent data point: a regression was reported in 4.6 for loading
external resources in *editor import* plugins (a different plugin category
than this one, which is a dock-based EditorPlugin) — not something we hit in
testing, but worth a quick smoke test of material/texture loading if you see
anything odd after upgrading a very old project.

---

## Third pass — critical crash fix + deep spline/collision bugs + Favorites overhaul

### CRITICAL: install-location crash, found and fixed at the root
Every script had `res://addons/ultimate_placer/...` hardcoded as an absolute
path. If the addon ends up nested one level deeper than expected (a zip
extracted with a wrapper folder around it, or renamed for organizational
reasons), every one of those loads silently fails with "File not found" and
the whole plugin fails to initialize with a null-instance crash. Fixed at
the root: every script now resolves its own install folder from where
Godot actually loaded it (`get_script().resource_path.get_base_dir()`)
instead of assuming a fixed path. Verified by reproducing the exact crash
in a nested folder, confirming the fix resolves it, then confirming a
second launch (icons already imported) is completely clean.

### Version numbers — now a true single source of truth
Found "1.5.0" still hardcoded in the browser header's own `VERSION`
constant and in the manual's footer, despite `plugin.cfg` already saying
2.0.0. Every version display in the plugin now calls the same
`UAPIcons.get_plugin_version()`, which reads `plugin.cfg` directly — it is
now structurally impossible for these to drift apart again.

### Deform crash investigation
Extensively tested the reported "resize crashes with a vertex/engine
mismatch" scenario: extreme Scale-Z values down to the UI's minimum,
curves up to 200 units long (producing 20,000+ segments), and meshes with
vertex colors + a second UV channel (much closer to a real imported asset
than a bare BoxMesh). Could not reproduce a hard crash in any of these,
but found and hardened a real risk along the way: segment count was
completely unbounded, so an extreme scale/curve-length combination could
request tens of thousands of segments, each duplicating every vertex of
the source mesh — a genuine perf/memory hazard on lower-end hardware.
Capped at 2000 with a status warning if a request would exceed it, rather
than silently truncating.

### Two real, confirmed bugs in Spline → Bake to MultiMesh with collision
Reproduced directly by baking a scatter layer with collision enabled:
- **Buffer-size crash**: `MultiMesh.duplicate()` threw "Cannot set a buffer
  on a Multimesh that is a different size from the Multimesh's existing
  buffer." Replaced with explicit manual reconstruction (new MultiMesh +
  copy instance-by-instance), matching the safer pattern already used
  elsewhere in the same function.
- **The actual "static bodies but no collisions" bug**: `cs.owner = root`
  was being set *before* `sb` (its parent) was added to the tree, so the
  owner assignment failed validation ("Invalid owner. Owner must be an
  ancestor in the tree") — silently, every time. The StaticBody3D itself
  still got added structurally and looked fine right up until the scene
  was saved and reopened, at which point anything without a successfully-
  set owner is dropped — leaving exactly what was reported: StaticBody3D
  nodes with nothing inside them. Fixed by completing both `add_child`
  calls before either owner assignment. Verified end to end: baked a real
  scatter layer and confirmed all 6 instances now have a StaticBody3D with
  a CollisionShape3D with a shape actually set.

### Spline taper/twist UI — actually wired in this time
Found that last pass's taper/twist backend had no UI controls anywhere in
the panel — a real miss, confirmed by grep (zero references to
scale_start/scale_end/twist in ultimate_panel.gd). Added the missing
Taper Start/End and Twist rows to both Scatter and Deform layer sections.

### Favorites — the actual bug, found and fixed everywhere it occurred
"Favorites" was never given real storage. Every code path that touched it
searched `_groups` for a dictionary literally named "Favorites" — which,
by design (per the code's own comments), can never exist there. This
means: filtering by Favorites showed everything (the search always failed,
so the filter fell through to "no filter"), and every "add to Favorites"
action was a silent no-op. Fixed by adding real, separate `_favorite_paths`
storage with its own persistence, and fixing all **six** places that had
this same broken pattern: the shared group-resolution helper, the
browser's own (separate, still-broken) copy of that filter, single-asset
add-to-group, multi-select add-to-group, folder-import-to-group, the
drag-and-drop handler, and smart-remove-from-group. Old configs that had
"Favorites" saved as a regular group are migrated into the new storage
rather than losing that data. Verified with 14 direct checks covering the
originally-reported bug, toggling, persistence, and migration.

### New: clickable favorite star on every asset card
Top-right corner of each card, tinted gold when favorited. Wired directly
to the new `_favorite_paths` storage.

### Groups tab decluttered
Removed "Import Folder to Group" as a separate section (it also had its
own copy of the Favorites bug, and used a less reliable tree-search to
find its dropdown — likely why it was reported as not showing newly
created groups). Consolidated into the single remaining group dropdown:
Add (selected assets) and Browse... (whole folder) now sit side by side,
both acting on whichever group is currently selected there.
Note: kept the "+ Add" new-group-name field — searched specifically for a
duplicate elsewhere and found none, and removing the only way to create a
group would break the feature entirely rather than simplify it.

---

## Third pass — favorite-star click bug, node-naming audit, format filter

### Test methodology additions this pass
Same real-binary, no-guesswork approach as before, plus new techniques
this specific round of bugs required:
- **`Viewport.push_input()` + `InputEventMouseButton`/`InputEventMouseMotion`**
  to simulate genuine mouse clicks against the real, live UI tree (not just
  checking rects) — used to prove click *routing*, i.e. which control an
  event actually resolves to.
- **A real environment limitation found and worked around, not glossed
  over:** `BaseButton`'s internal press → `pressed` signal chain depends on
  Godot's hover-tracking subsystem, which does not initialize in a plain
  `--headless --script` run with no real display — confirmed in total
  isolation (a bare `Button`, no plugin code at all: `mouse_entered` never
  fires no matter what, even after explicit motion events and multiple
  frames). What *does* work correctly headlessly, and is what actually
  matters for the bug in question, is hit-test **dispatch priority** — which
  control an event resolves to, and at what transformed local coordinate —
  verified directly via each control's own `gui_input` signal rather than
  relying on `pressed`, which would give a false negative here despite the
  fix being correct.
- **A working pattern for full editor-context integration tests**, for the
  node-naming bug specifically, since reproducing it needs a real
  `EditorInterface.get_edited_scene_root()` (not available to a plain
  `--script` run at all): a throwaway project with a `@tool`-scripted
  `Node3D` scene set as `run/main_scene`, whose `_ready()` calls
  `EditorInterface.open_scene_from_path(scene_file_path)` on itself, then
  drives the real plugin classes directly and writes results to a file
  before quitting the editor. This is what actually reproduced the
  reported bug end-to-end (not just the isolated mechanism) and confirmed
  the fix against it.
- Caught and fixed a methodology mistake of my own mid-session: GDScript
  lambdas capture outer **local** variables by value, not by reference —
  a `connect(func(): some_local = true)` probe silently never updates the
  caller's copy, giving false negatives. Outer **member** variables on the
  test script's own class don't have this problem. Re-verified every test
  that used this pattern once caught.

### Favorite-star button was eating every click on the card — root cause confirmed, fixed
Diagnosis from the previous session's handoff notes was correct and
verified empirically before touching code: the star `Button` was a direct
child of `card`, a `PanelContainer`. Godot's `Container` base class
force-resizes *every* direct child to fill its own content rect on every
layout pass, silently overriding any manually-set anchors/position/size —
confirmed with an isolated repro (a bare `PanelContainer` + `Button`, no
plugin code) showing the button's actual size snap from the requested
20×20 to the full 96×116 card size the instant it's added as a child.
Fixed by giving each card a plain `Control` wrapper (not a `Container`,
so it does not re-enforce full-rect child sizing): `card` fills it via
`PRESET_FULL_RECT` anchors, and the star sits as a *sibling*, not a child
of `card`, with its own small anchored rect that now actually holds.
`_asset_grid` now receives the wrapper, not the bare card; `_card_map`
still stores the inner `card` unchanged, since every other reader of that
map (style overrides, the eyedropper's scroll-into-view) only ever needed
the panel itself, confirmed by re-reading each call site.

**A second, independent bug in the same feature, found only by testing
the actual resize rather than assuming the size change alone would work:**
the star icon is a 24×24 texture, and `Button`'s own minimum-size
calculation is driven by the icon's native size plus padding —
**32×32, confirmed directly** — regardless of `custom_minimum_size`,
*unless* `expand_icon` is set. Without it, shrinking the button's declared
size would have been silently overridden right back up to 32×32 by
Godot's own layout system, quietly defeating the resize while looking
correct in a code read-through. Fixed by setting `expand_icon = true`
alongside the smaller size.

Net result: the star is now 10×10 (half its old 20×20, as asked), sitting
2px from both the top and right edges of the card (a tight corner inset,
matching the doodle), and — the actual functional fix — its clickable
area now exactly matches that small visual footprint instead of covering
the whole card.

**Verified two ways:**
1. A genuine simulated click at the *center* of a card (away from the
   star) correctly reaches the card's own select handler, not the star —
   proven via the handler's real downstream side effect, not an assumption.
2. A genuine simulated click at the star's own location resolves to the
   star specifically (confirmed via `gui_input`'s locally-transformed
   coordinate landing dead-center in the button, `(5,5)` of a 10×10 rect)
   and does *not* also reach the card underneath, despite the card still
   geometrically covering that same point.
12 automated checks total for this fix, all passing.

### Ugly auto-generated node names — real root cause found, different from the initial hypothesis
The starting hypothesis (from the previous session's handoff notes) was
that some `add_child()` call was missing a `.name` assignment beforehand.
That pattern was audited for across every `add_child(` call in every
script in the addon, as asked, and two genuine instances of it *were*
found (below) — but neither was the Asset Zoo. The Zoo's own node
creation was already correctly ordered: `zoo.name = "AssetZoo"` *was*
being set before `add_child()`.

**The actual mechanism, confirmed directly against this Godot build:**
`Node.add_child()` takes a `force_readable_name` parameter, default
`false`. When the requested name **collides** with an existing sibling —
e.g. pressing "Create Zoo" a second time while an earlier "AssetZoo" is
still in the scene, an entirely normal thing to do — the default behavior
silently **discards** the requested name and substitutes its own
`@ClassName@ID` placeholder instead of the expected numeric-suffix
behavior. Confirmed with an isolated repro, no plugin code involved:
default `add_child()` on a naming collision produced `@Node3D@2`;
`add_child(node, true)` on the exact same collision produced `AssetZoo2`
— which also happens to exactly match the naming scheme asked for
("AssetZoo, AssetZoo2 like these"), a good sign the right mechanism was
found. (Separately confirmed: a *never-set* empty name is ugly regardless
of collision — that part of the original hypothesis was correct, just not
what was happening in the Zoo's case specifically.)

Fixed at the actual root: `(root as Node3D).add_child(zoo, true)`.
**Verified end-to-end, not just the isolated mechanism** — a real editor
session (see methodology note above) that opens an actual scene, presses
"Create Zoo" twice in a row without deleting the first one (the exact
scenario that produces the bug), and confirms the real result:
`["AssetZoo", "AssetZoo2"]`, no ugly names.

**The full systematic audit**, across every `add_child(` in every `.gd`
file, checking each against both failure modes (missing name, and
collision without `force_readable_name`) — restricted to call sites that
actually place a node into the *edited scene tree* (the plugin's own dock
UI construction and the offline thumbnail generator's internal
SubViewport never appear in the Scene panel, confirmed by checking neither
ever sets `.owner`, so they're not in scope for "ugly names in the scene
tree"):
- **Two genuine missing-name bugs, matching the original hypothesis**,
  found and fixed: `uap_path.gd`'s `_add_collision()` (the non-MultiMesh
  spline-bake collision helper) never named either the `StaticBody3D` or
  the `CollisionShape3D` it creates. `ultimate_placer.gd` had the same gap
  in three places: the RigidBody-collision branch's `CollisionShape3D`,
  the plain-body branch's `CollisionShape3D`, and `_attach_body()`'s
  `StaticBody3D`/`_attach_shape()`'s `CollisionShape3D` (the
  `unpack_scenes = true` collision path). `mm_generate_collision()`'s
  per-instance `CollisionShape3D` too. All given clean, descriptive names
  matching the existing "Shape" convention used elsewhere in the file.
- **`force_readable_name = true` added as defense-in-depth** to every
  other scene-affecting `add_child()` call that wasn't already provably
  collision-proof via an existing manual pre-check loop — the Zoo's own
  per-item instance/label creation, the MultiMesh-paint parent node and
  per-asset instances (which can plausibly collide with a same-named node
  left over from a previous editing session, since these rely on an
  in-memory cache rather than checking the live tree — noted below as a
  separate, deeper issue), and every spline scatter/deform/bake node.
  Zero behavioral cost when there's no collision — confirmed directly, the
  parameter only changes anything in the collision case.
- **Deliberately left unchanged**, because each is *already* provably
  collision-safe via its own existing mechanism, re-confirmed by reading
  before touching anything: `_do_place()`'s main placement path and
  `_on_create_spline_node()`'s Path3D creation both pre-check
  `parent.has_node(...)` against the live tree before ever calling
  `add_child()`; the RigidBody-wrapper branch already has its own
  post-hoc self-healing fixup (checks for a "_RB" suffix after add_child
  and manually re-fixes it if Godot's own auto-rename didn't produce one),
  which already correctly handles *both* failure modes on its own.
- **A related latent hazard, fixed to match a pattern the codebase already
  established elsewhere**: `_spawn_ghost()`, `_build_grid()`, and
  `_spawn_brush_ghost()` create their transient preview helpers with
  `queue_free()`-based cleanup, but `queue_free()` is deferred by a frame
  — a rapid recreate (e.g. quickly switching between assets) could
  collide with the not-yet-actually-removed old node. `uap_path.gd`
  already has a defensive pattern for this exact hazard elsewhere
  (renaming a doomed node to something random before `queue_free()`-ing
  it, specifically so it can't collide with its own replacement) — applied
  the same pattern to all three ghost/grid helpers for consistency.
- **A duplicate-accumulation bug found alongside the naming audit, fixed
  since it's the same code path**: `mm_generate_collision()` ("Generate
  Collision" for MultiMesh-painted assets) never removed a previous
  collision body before creating a new one — clicking it twice for the
  same asset would leave two full sets of collision bodies in the scene,
  which was *also* a naming collision in its own right. Fixed by removing
  any existing `"<name>_Collision"` node for that asset first (using the
  same rename-before-`queue_free()` pattern), so re-generating replaces
  rather than accumulates.

**Verified structurally, not just for clean names** — real end-to-end
checks confirming each fixed collision function still produces a valid,
correctly-shaped result: a `StaticBody3D`/`RigidBody3D` with an actual
`CollisionShape3D` child holding a real, non-null `Shape3D` resource, for
every one of: regular single-object placement (both the sibling-collision
and `unpack_scenes=true` branches), RigidBody placement, spline-bake
collision, and MultiMesh-paint collision. 11 checks across these.
Plus 2 checks confirming repeated placement still gets clean, correctly-
incrementing names (`fake_rock`, `fake_rock_2`, ...) with zero ugly names
anywhere — a regression check that this pass's changes didn't disturb the
already-correct core placement path. 23 checks total for this fix.

### Format filter didn't apply inside custom groups or Favorites — confirmed and fixed
Traced as instructed: `_filtered_paths()` turned out to contain *no*
format-filtering logic at all — only the search-text filter. The format
checkboxes (`import_formats`) are applied in exactly two other places:
`_scan_one_dir()` (gates what a full folder scan puts into `_all_paths`)
and `_collect_files()` (gates a folder-to-group import at add-time). Both
only ever touch `_all_paths` or a group's contents *at the moment
something is added* — never at *display* time. Since "All" is rebuilt
from a live disk scan on every single checkbox toggle (confirmed:
`_on_format_toggled()` calls `_scan_folder()`), it looked like the format
filter worked everywhere, when it actually only ever worked for "All",
by a different mechanism than groups/Favorites needed.

Fixed in `_filtered_paths()` itself: the format filter now applies to
whichever `base` array was selected — `_all_paths`, a named group's
stored paths, or `_favorite_paths` — uniformly, before the search-text
filter. This is non-destructive by design: unlike "All" (which is
destructively rebuilt from disk on toggle), a group or Favorites' stored
membership is never modified by this — toggling a format off hides
matching items immediately, and toggling it back on immediately reveals
them again, without needing to re-add anything. Confirmed only one call
site exists for this function, so — unlike the six-copies Favorites bug —
this was a single-point fix, not a repeated pattern.

Also applied the identical fix to the Asset Zoo's "Current Group Filter"
source option, which pulled from the same unfiltered group-paths function
directly — same underlying bug, same fix, for consistency. (The Zoo's
"Selected Assets" source was deliberately left as-is: an explicit,
deliberate multi-select shouldn't be retroactively filtered by an
unrelated checkbox someone happens to toggle later.)

6 direct checks: format exclusion in a named group, in Favorites, and in
"All" (regression check); format + search-text composing correctly
together; re-enabling a format immediately revealing hidden items again;
and confirming the underlying stored group data is never mutated by any
of this.

### A "clean baseline" claim corrected mid-session
Investigated an unexpected batch of icon-loading warnings/errors that
appeared partway through this pass and were briefly suspected as a
regression. They're not: reproduced identically in a completely fresh,
never-before-used test project, and confirmed to fully disappear on a
*second* launch of that same fresh project — this is the already-known,
already-defensively-coded transient state on a true first-ever import
(the warning message's own text says as much), previously verified in
an earlier pass ("confirming a second launch (icons already imported) is
clean"). This session's actual first baseline check earlier had looked
clean only because it was viewed with `tail -60`, which cut off the
earlier, expected transient warnings before they scrolled past — not
because that first launch was actually free of them. Noting this
correction directly rather than letting the earlier "clean baseline"
framing stand uncorrected.

### Known, disclosed limitation from this pass
`BaseButton`'s press-registration depends on Godot's hover-tracking
subsystem, which this headless sandbox's `--script`-only tier cannot
exercise (no real display). Dispatch priority — which control an event
actually resolves to, the part that actually mattered for the reported
bug — was verified directly and is unaffected by this gap; a real click
in the real editor, with real hover tracking, exercises standard,
unmodified `BaseButton` engine behavior this addon's code doesn't touch.
Flagging this the same way the MultiMesh-buffer and EditorInterface-null
limitations were flagged in earlier passes, rather than letting a
headless-only false negative stand unexplained.

---

## Fourth pass — star visibility, master header collapse, MultiMesh paint reattachment

### "I don't see any stars" — investigated as a possible regression, root-caused to contrast, not breakage
Took this seriously as a possible regression from the previous pass's
click-area fix before assuming anything. The star's size, position, and
click-routing were all re-confirmed intact by re-running the previous
pass's automated checks against the current code — the button itself
wasn't broken. Made a real, serious attempt to get actual rendered pixels
to inspect directly rather than reason about it in the abstract: got real
software-GL rendering (Mesa llvmpipe) working under Xvfb in this sandbox
and confirmed it initializes correctly, but the full editor session
proved too unreliable in this container to depend on for a screenshot
(intermittent Vulkan/D-Bus initialization failures unrelated to this
addon's code, not consistently reproducible). Rather than keep spending
time on an increasingly unreliable path, fell back to computing the
actual composited pixel color directly from the real constants in the
code — a rigorous alternative, if a less direct one than a screenshot.

`C_CARD_BG` is `(0.155, 0.165, 0.205)`; the non-favorited star was tinted
white at **32% opacity**. Composited: an effective color around
`(0.43, 0.43, 0.46)`, giving a contrast ratio of roughly **2.2:1** against
the card background — already low by typical UI-legibility standards, as
a deliberate "unobtrusive until favorited" design choice. That was
apparently *just* perceptible at the old 20×20 size; halving the star's
area (per the previous pass's fix, correctly implementing what was asked)
pushed the same low contrast below the threshold of being noticed at a
glance, especially in a compressed screenshot. Structurally nothing was
broken — this was a real, correctly-implemented fix whose *result*
happened to compound with a pre-existing, unrelated design choice.

Fixed by raising the resting-state opacity from 0.32 to **0.6** (~3.3:1
contrast against the card background, computed the same way) — clearly
still dimmer than the solid gold favorited state, but now actually
visible at the smaller size. Hover bumped from 0.7 to 0.78 to keep the
same relative progression; pressed (0.9) and the favorited-state color
were untouched.

**Caveat, stated plainly:** this is the one fix this pass that could not
be confirmed with an actual rendered screenshot, for the sandbox-specific
reason above. The color math is exact (the real constants from the code,
not estimates), and the diagnosis explains the symptom precisely, but
actually looking at it in the real editor is the strongest confirmation
and worth doing.

**Follow-up, confirmed against the real editor:** the opacity diagnosis
was correct — the star *was* now visible, reported back as "a very small
dot." The remaining problem was pure size: a 5-pointed star has concave
notches between its points that stop reading as a recognizable shape
well before a plain circle or square would, and 10×10 (a literal half of
the original 20×20, from the previous pass's fix) was past that point.
Sized up to **16×16** — clearly smaller than the original 20×20 still,
just not so small the shape itself stops resolving. Position math
recalculated for the new size, keeping the same tight ~2px corner inset
(`position.x=-18` for a 16-wide button: right edge sits at `-18+16=-2`).
Re-verified all the geometry and click-routing checks from the previous
pass's fix at the new size — sibling structure, tight corner margins,
center-click still reaching the card, and a click exactly on the star
still dispatching to the star and not the card underneath (confirmed via
`gui_input`'s locally-transformed coordinate landing at `(8,8)`, dead
center of the new 16×16 button) — all still correct at the new size, this
being a genuine size-only follow-up rather than a redo of the underlying
click-area fix.

**One more size bump, again from direct feedback in the real editor:**
16×16 was still reported as a bit small. Sized up again to **18×18** —
the final size — recalculating the same tight ~2px corner inset
(`position.x=-20` for an 18-wide button). Re-verified the full geometry
and click-routing battery once more at this size; all still correct,
including the star-click dispatch check landing at local coordinate
`(9,9)`, dead center of the new button.

### Master collapse for the browser header
Added, as specified: a chevron button in the title row, independent of
the existing "Search & Filters" toggle (which keeps its own state and
behavior unchanged). Collapsing hides the version label, the Search &
Filters toggle button itself, its panel, and — a separate top-level node
from the header, `_build_browser_panel()`'s status-bar `PanelContainer`,
not nested inside the header at all — down to a title-row-only slim strip.
Pagination and the asset grid are untouched either way, since neither is
part of what this affects.

Two design calls, since the spec named specific elements ("just the
title text and a chevron") without settling every edge case:
- The 3px accent `ColorRect` on the left of the title row was kept even
  when collapsed — it reads as border/frame chrome rather than content,
  and removing it made the collapsed row look visually broken rather
  than "slim." Flagging this specific choice in case the ask was for
  literally nothing else at all.
- Collapsing the header does *not* alter the Search & Filters section's
  own expanded/collapsed state — if it was individually collapsed before
  a master-collapse, it stays collapsed after a master-expand. This
  seemed like the more predictable behavior for "separate from the
  existing toggle," rather than always resetting it to expanded.

Persisted via the same `_save_config()`/`_load_config()` path as every
other UI preference, defaulting to `false` (expanded) so first-launch
behavior is unchanged, exactly as asked.

**Verified, including the specific thing asked to verify and not just
assume:** the dock's actual `get_combined_minimum_size()` was measured
before and after collapsing, using the real panel and a real-sized
container (not just checking `.visible` flags) — **338px → 200px, a
genuine 138px reclaimed**, confirming this actually shrinks the layout
rather than just visually tucking content away while reserving the same
space. 21 checks total, also covering: default-expanded on a fresh
install, every affected node's visibility in both states, pagination/grid
staying untouched, the chevron icon swapping correctly, the Search &
Filters state-independence behavior above, and persistence surviving a
fresh panel instance (simulating a reopened project).

### MultiMesh paint — the reattachment issue from last pass's notes, plus a second, more direct bug found alongside it
The observation from the previous pass's summary was real: `_mm_parent`
and `_mm_get_or_create()`'s per-asset instances are tracked purely by an
in-memory reference/dictionary, never cross-checked against what's
actually already in the live scene. That reference is lost on anything
that recreates the placer object — reopening the project, reloading the
plugin — while the actual saved scene content survives. Painting the same
asset again afterward would silently create a second, disconnected
`MultiMeshInstance3D` (and potentially a second `UAP_MultiMeshPaint`
parent) alongside the still-visible old one instead of continuing to add
to it.

Fixed by checking the live scene for a matching, already-valid node
before creating a new one, in both places — `root.get_node_or_null(...)`
for the parent, `par_node.get_node_or_null(...)` for the per-asset
instance. When an existing per-asset `MultiMeshInstance3D` is found, its
in-memory transform list is also rehydrated from the multimesh's actual
instance data, so painting more onto it appends rather than silently
restarting from empty.

**A second, more directly broken bug found while investigating the
first, in the same function area, fixed since it's squarely "the
MultiMesh paint system" too**: `mm_clear()` — the "Clear" button's
handler — only ever reset the in-memory tracking dictionaries. It never
touched the scene at all. Clicking "Clear" gave a confirming status
message and reset internal state, but the painted geometry stayed fully
visible in the scene the entire time, now silently disconnected from the
plugin's own bookkeeping — and painting the same asset afterward would
then hit the exact duplicate-node problem above, except now guaranteed
rather than just possible. Fixed to actually remove the `_mm_parent` node
(and therefore everything under it) from the scene, using the same
rename-before-`queue_free()` pattern as the ghost/grid helpers from the
previous pass, for the same deferred-free reason.

**Verified end-to-end in a real editor session** (same technique as the
Zoo fix), not just the isolated mechanism: painted a real instance,
simulated exactly what a session reset does (dropped every in-memory
reference, left the scene alone), painted again, and confirmed a single
reattached parent and instance rather than a duplicate, a correctly-grown
instance count (2, not a reset-to-1), and a correctly rehydrated
transform list. Then called the real `mm_clear()`, confirmed the node
actually leaves the scene this time (not just the in-memory reference),
and confirmed a subsequent paint starts genuinely fresh. 12 checks total.

One thing intentionally *not* touched, flagged instead: `mm_generate_collision()`
(fixed for naming/accumulation in the previous pass) still won't find a
MultiMesh's collision by matching against a *reattached* node from this
pass's fix in every possible ordering-of-operations sense — the two
fixes weren't cross-tested against each other in combination. Both are
independently verified; worth a combined check if you use both features
together heavily.

### Testing note
Made a genuine attempt this pass to get real GPU-rendered screenshots
working in this sandbox (Xvfb + Mesa software rendering, confirmed
initializing correctly at least once), specifically to verify the star
visibility fix with an actual image rather than color math. It could not
be made reliable enough to depend on here — noting this directly rather
than either silently falling back or overstating the color-math
verification as equivalent to having looked at it.

---

## Fifth pass — the star fix, actually verified with real rendered pixels this time

### "Star is now not visible at all" — got real rendering working, found the actual bug
Reported again after the 16→18 size bump. This time got an actual
screenshot working (the previous pass's blocker was specifically the full
*editor* session's Vulkan/D-Bus init being unreliable under Xvfb in this
sandbox — running the panel in a plain runtime scene instead, with no
editor involved at all, avoids that subsystem entirely and initialized
real software OpenGL — Mesa llvmpipe — cleanly and repeatably). Built
cards with real colored thumbnails, screenshotted the actual rendered
output, and looked at it directly.

**The real bug, invisible to every previous check because none of them
rendered actual pixels:** every previous opacity/contrast fix (this
pass's second, the "0.32 → 0.6" one) was computed against `C_CARD_BG`,
the card's own dark background color. But the star sits in the corner of
the *thumbnail image*, not the bare card — and real asset thumbnails vary
enormously in color and brightness. Confirmed directly: on a reddish-
brown test thumbnail, the white star at 0.6 opacity was nearly
indistinguishable from the thumbnail underneath it, despite the exact
same color having reasonable contrast against the dark card background
it was tuned for. No fixed opacity value can fix this, because the actual
problem is that the background itself is unpredictable, not that any one
opacity is wrong.

Fixed with the standard pattern for icon overlays on arbitrary imagery
(the same reason most photo/video UIs put icons on a small dark scrim
rather than directly on the image): a small dark, semi-transparent
circular backing panel sits behind the star, slightly larger than it
(22×22 behind an 18×18 star), `mouse_filter = IGNORE` so it doesn't
affect the click-area fix from the second pass. This guarantees contrast
regardless of what's under it, rather than depending on the thumbnail's
own color.

**Verified against an actual range of thumbnail colors, not just one** —
tested against reddish-brown, green, near-white (the deliberately
worst-case choice: a plain white star has essentially no way to contrast
against a near-white background without something like this), olive, and
purple test thumbnails, in both the favorited (gold) and non-favorited
states. Every combination produced a clearly visible, correctly-shaped
star. Screenshots of the comparison are what this fix was actually
confirmed against, not a description of them.

**A methodology note worth recording:** while investigating, an early
version of this same screenshot appeared to show the "favorited" test
cards rendering the plain (non-gold) star instead of the expected gold
one. Didn't assume the fix was broken — checked the obvious alternative
first: a stale `user://ultimate_asset_placer.cfg` left over from an
*earlier* screenshot attempt already had those exact two test paths
favorited, so this run's `toggle_favorite()` calls correctly toggled them
back *off* before the screenshot was even taken. Deleted the stale
config, reran, gold stars rendered exactly as expected. Same class of
gotcha as earlier passes' automated tests, now also relevant to visual
testing — worth remembering for any future screenshot-based check in this
project.

Also re-ran the full click-routing/geometry regression battery from the
second pass with the new backing panel in place, to confirm it doesn't
reopen the original click-area bug: center-of-card clicks still reach the
card, clicks on the star still reach the star and not the card, and the
backing panel itself is confirmed non-interactive. Plus a fast re-check
of the master header collapse and group/Favorites format filter (both
untouched this pass, unaffected by any of this) as a final sweep before
packaging.

This is, as of this pass, the one visual fix in the whole engagement
confirmed by actually looking at rendered output rather than by geometry
checks or color computation — and it's also the one that turned out to
need it, since the bug only existed in the interaction between the icon
and unpredictable thumbnail content that neither structural tests nor
color math against the wrong background could have caught.

---

## Sixth pass — the real bug was in the real editor, not the plain scene

### "Circles appear but stars are still not visible at all" — and don't want the circles either
Two things in one report: the previous pass's backing-circle fix wasn't
solving the actual problem (star still invisible), and separately, the
circle itself wasn't wanted regardless. Both needed addressing, but the
first one first — a request to remove the workaround before understanding
why the underlying fix wasn't working would have just meant shipping
something unverified again.

**Got a screenshot of the actual real editor session this time — not a
plain runtime scene standing in for it.** The previous pass's screenshot
technique used a plain game scene specifically because launching the full
editor under this sandbox's virtual display had been unreliable. Revisited
that limitation rather than continuing to work around it, since a plain
scene evidently wasn't sufficient to catch this bug: it uses Godot's bare
default theme, and the real editor has its own, different theme, which
turned out to matter a great deal here. Got it working by NOT calling
`RenderingServer.force_draw()` before capture (which appears to conflict
with the editor's own render loop and was hanging the whole session) and
by capturing `get_tree().root`'s texture rather than `get_viewport()`'s
(the latter resolves to the edited scene's own small internal preview
viewport when called from a script attached to that scene, not the actual
editor window — produced a degenerate 2x2 image on the first attempt).

**Zoomed into the actual real-editor screenshot and the star was a
handful of unrecognizable pixels — not just faint, structurally wrong.**
Every earlier headless check (button size, position, click-routing, icon
assignment) had passed and gave no hint anything was wrong, because none
of them rendered a single real pixel. Root-caused by direct experiment,
not guesswork: built several button configurations side by side in the
real editor and screenshotted all of them together. `expand_icon=true`
shrinking a 24x24 icon into an 18x18 button was broken specifically in
the real editor context; the exact same setup with `expand_icon=false`
(rendering at native size) or a larger button (so no shrinking was
needed) both rendered correctly. It's not a margins issue either —
tested and ruled out first: the real editor's default Button style has
substantial content margins (6px/4.5px, confirmed directly) that do still
apply even with `flat=true` (flat only suppresses the visual background,
not the layout-relevant margins), and zeroing them out was tried first
as the most likely explanation, but the icon was still a tiny blob
afterward — margins turned out to be a real, second, smaller issue, not
the main one.

Root cause, isolated by elimination rather than assumed: `Button.expand_icon`
grows a small icon to fill a larger button reliably, but shrinking a
larger icon into a smaller button is where it broke down in this real
editor context specifically (not reproducible in a plain scene using the
default theme — that's why every earlier check missed it).

**Fixed by not depending on expand_icon's shrink path at all.** `uap_icons.gd`
gained `get_icon_sized()`, which resizes the actual texture data once
(via `Image.resize()`) to the exact target pixel size and caches it — the
icon already *is* the right size, nothing needs to be fit into anything
at draw time. Confirmed correct in the real editor at 18×18.

### Circles removed, contrast kept a different way
Removed the backing chip entirely, as asked. Its actual job — guaranteeing
contrast against whatever's under the star, since real thumbnails range
from near-black to near-white and a flat-color icon has good contrast
against only some of them — still needed solving without a solid shape.

`uap_icons.gd` gained `get_icon_outlined()`: dilates the icon's own alpha
mask outward by a couple pixels (at a higher working resolution for
smoother edges, then downsampled) and fills the new border pixels with a
near-black color, baked directly into the texture. The original star
shape's pixels are untouched, so the existing gold/white tinting via
`icon_normal_color` still works exactly as before — multiplying a
near-black outline pixel by any tint color stays near-black, so one
texture correctly serves every state without regenerating per color,
confirmed directly by rendering both the resting and gold favorited
states side by side. This is the same general approach most UIs use for
icon legibility over arbitrary photos/thumbnails, just without a distinct
background shape — an outline directly on the icon rather than a chip
behind it.

Card construction now calls `UAPIcons.set_button_icon_outlined(fav_btn,
"feature_favorite", 18)` in place of the old `set_button_icon()` +
`expand_icon=true`. The zero-margin stylebox override from earlier in
this pass is kept — no longer the primary fix, but still needed to
correctly center a small pre-sized icon within a small button regardless
of the ambient theme's default margins.

**Verified in the real editor, actual `_add_card()` path, not a
synthetic stand-in** — real colored test thumbnails including the
worst-case near-white one, both resting and favorited (gold) states,
inside the genuine running dock. Every star renders as a clean, clearly
outlined, correctly colored shape, with no circle. Screenshots of this
are what the fix was confirmed against.

Re-ran the full structural/click-routing regression battery afterward —
sibling structure, tight corner margins, center-of-card clicks still
reaching the card, clicks on the star still reaching the star and not the
card, plus the icon now being confirmed pre-sized (18×18) rather than
depending on `expand_icon` — all still correct, alongside a fast recheck
of the master header collapse and group/Favorites format filter.

### Why this one took this many passes
Every fix before this one was checked as thoroughly as the tools available
at the time allowed — structural checks, click-simulation, then color
math, then a real screenshot from a plain scene — and each of those was
a genuine, correct fix for what it could actually see. The gap was
specifically that neither structural correctness nor a plain-scene
screenshot could reveal a real-editor-theme-specific rendering behavior.
Getting a screenshot of the actual editor, not a stand-in for it, is what
finally closed that gap. Worth remembering for anything visual in this
project going forward: a plain runtime scene is a good fast check, but
isn't a substitute for the real editor when the real editor's own theme
is plausibly part of what's being tested.

## Seventh pass — new feature: the Physics Placer

### The request
Select object(s) already in the scene, lift them into the air, drop them
with real physics so they fall and settle naturally, then freeze them in
place — with collision handled automatically for anything that doesn't
already have it, and anything that does have it left completely alone.

### First, a question that decides the whole architecture: does physics
### even run in the editor?
Before writing a line of feature code, tested the load-bearing assumption
directly rather than assuming it: does a `RigidBody3D` actually fall under
gravity while a scene is just open for editing, without pressing Play?
Downloaded the real `4.7.1-stable` Godot editor binary from
`godotengine/godot-builds`'s GitHub releases and drove it headless with a
throwaway EditorPlugin that logs a RigidBody3D's `global_position` every
frame. **Confirmed it does not move at all** — sitting above a floor for
170+ real editor frames, position and `linear_velocity` both exactly
unchanged the entire time, whether the body was parented inside the
edited scene or entirely outside it under the plugin's own node. Godot's
editor process never steps `PhysicsServer3D` dynamics; Play mode is a
separate process where this normally happens instead. This ruled out the
obvious "just add a RigidBody3D and watch it fall" approach entirely —
whatever this feature does, it cannot lean on the engine's own physics
stepping.

The follow-up question, also tested directly rather than assumed:
`PhysicsDirectSpaceState3D` queries — `cast_motion`, `get_rest_info`,
`intersect_ray`, `intersect_shape` — confirmed to work correctly in-editor
same-frame a collision shape is created, no registration delay. That's the
foundation the whole feature is built on: no native dynamics available, so
gravity, sweeping, and collision response are all done by hand each frame
off these query functions, driven by a ticker node the same way the
existing placer's own `_process` already works.

### Design: uap_physics.gd, a new self-contained module
Added as its own file rather than folded into the already-large
`ultimate_placer.gd`, instantiated and wired up in `plugin.gd` exactly the
same way `ultimate_placer.gd` itself is (a child node of the plugin,
`editor_plugin`/`panel` references set before entering the tree). New
"Physics" tab in `ultimate_panel.gd`, between Collision and Docs, with its
own status banner matching the Spline tab's "mode active" banner pattern.

Collision handling matches what was asked for exactly: every object
selected gets scanned for an existing `PhysicsBody3D` with a real
`CollisionShape3D` (walking the whole subtree, so this also catches
collision buried inside an imported/packed scene). Anything that already
has one is used completely as-is — its RID is added to that object's own
self-exclusion list and otherwise never touched. Anything with none gets a
temporary `StaticBody3D` added as a plain, **unowned** child (one
`CollisionShape3D` per mesh part, same per-mesh approach the Collision
tab's own Auto Collision already uses) — unowned specifically so that
saving the scene mid-simulation never writes it into the `.tscn` file,
and it's `queue_free()`'d the instant physics is stopped or cancelled.

### The simulation itself: gravity, sweeps, and several real bugs found
### by actually running it, not by inspecting the code
The core loop integrates gravity into a per-object velocity by hand, sweeps
a bounding-box proxy shape (`PhysicsShapeQueryParameters3D` + `cast_motion`)
along that velocity each frame, and resolves any hit with friction (against
the tangential component) and Bounciness-scaled restitution (against the
normal component). Built a dedicated test scene (flat ground, a tilted
ramp, one object with pre-existing collision, several without) and a
second throwaway EditorPlugin harness that drives the real feature end to
end — selects nodes, calls `lift_selected()` / `start_simulation()` /
`stop_simulation()` / `cancel_simulation()` on the actual running instance,
and logs positions and internal state frame by frame — all against the
same real 4.7.1 binary, not a synthetic stand-in.

That harness caught several real bugs a code read-through did not:

- **Settle detection reset every other frame.** A resting object's own
  tiny bounce-and-resettle cycle meant it alternated between "touching"
  and "just barely clear" from one frame to the next, and the settle-hold
  timer only accumulated on the "touching" frames — so it kept getting
  reset to zero in between and never actually finished settling, even
  though the object was visibly motionless. Fixed by checking velocity
  alone for the settle condition, regardless of which code path produced
  it that frame.

- **Friction that only ever slowed a slide, never stopped it.** The first
  friction model reduced *existing* tangential velocity by a fixed
  fraction on each collision event. On a slope, gravity injects a fresh
  tangential component every single frame in contact, so a fraction-based
  damping can only ever slow the *growth* of sliding speed, never fully
  cancel it — an object landing on a modest incline would slide forever,
  just decelerating asymptotically toward a nonzero speed instead of
  actually reaching zero. Replaced with a bounded deceleration
  (`friction × gravity`, applied every frame in contact, not just on
  fresh collision events) — high enough friction relative to the slope
  now genuinely arrests the slide instead of merely slowing its increase.

- **A bounce that could snowball into flying off a slope entirely.** Even
  modest Bounciness on a tilted surface launches the object away along the
  (also tilted) surface normal, which — unlike bouncing on flat ground —
  carries real horizontal distance before gravity brings it back down.
  Each such landing converts more of the accumulated fall speed into
  *more* sliding speed via that same tilted-normal geometry, and the
  brief, fast "grounded" windows between hops couldn't undo that with
  friction alone: confirmed by direct measurement that a test object's
  tangential speed was measurably *increasing* on each successive landing.
  Fixed with a bounce-speed threshold (impacts softer than roughly 1.5 m/s
  never bounce at all, regardless of Bounciness) — the same technique
  mainstream physics engines use so soft, low-speed contact settles
  instead of chattering.

- **A confirmed `cast_motion` limitation, not a logic bug: an
  already-overlapping query shape can report full clearance.** After the
  above fixes, one specific test object still occasionally fell straight
  through solid ground with `cast_motion` reporting `[1.0, 1.0]` (fully
  clear) the entire time — while a separate direct raycast and
  `intersect_shape` check, run at that exact same position in the same
  frame, both correctly found the ground right there. Isolated by
  comparing `cast_motion`'s result against `intersect_shape`'s at
  identical transforms rather than guessing: once the query shape starts a
  sweep already penetrating another shape (residual overlap left over from
  a prior frame's contact resolution), `cast_motion` cannot be trusted to
  detect further collision along the swept motion. Added a fallback
  safety net: whenever a sweep reports full clearance, a follow-up
  `get_rest_info` check (using a deliberately shrunken stand-in shape, so
  routine margin-level resting contact isn't mistaken for this case) looks
  for an already-overlapping state and, if found, discards that frame's
  sweep result and nudges the object back out along the real contact
  normal instead, with velocity treated as a hard stop rather than trying
  to preserve a bounce or slide through what is, by definition, an already
  ambiguous spot (most often the seam between two separate collision
  bodies, such as a ramp meeting the ground beside it).

Re-verified the full scenario after each fix — an object with no collision
correctly gets one added and it's gone the instant Stop is pressed; a
second object with its own pre-existing `StaticBody3D` is provably
untouched (identical child list before and after); two falling objects
correctly stack on each other and each settle at the expected height; an
object landing on the tilted ramp slides, decelerates, and comes to rest
rather than sliding indefinitely or launching off the far edge; Cancel
correctly restores every object's exact pre-simulation transform; Stop
bakes the current transform as a single coalesced undo action, the same
pattern `_commit_place` already uses elsewhere in this codebase.

### Known limitation
An object settling exactly on the seam between two separate collision
bodies whose surfaces don't perfectly align (e.g. precisely where a ramp
meets the ground beside it) can take visibly longer to fully stop than one
settling on a single continuous surface, since the safety-net path above
is doing extra corrective work in an inherently ambiguous spot. It always
does converge or gets caught by Max Fall Time — it does not hang or slide
away — but for the cleanest results, avoid dropping objects to land
precisely on a seam between two different pieces of level geometry.

## Eighth pass — Physics Placer: a real-world bug report, and why the sweep proxy needed to stop always being a box

### The report
Testing with actual sphere props ("balls"), most of them ended up flying off
the ground during a drop — with confirmation the ground's own collision was
set up correctly, ruling out the obvious first suspect. Requested: an option
to turn off auto-added collision entirely, an option for collision accurate
to the real mesh, and a proper stress-test pass across many scenarios before
calling this commercially solid.

### Reproducing it first
Built a dedicated stress-test project (separate from the existing one) with
real `SphereMesh`/`SphereShape3D` props, a flat platform, and a second
throwaway EditorPlugin harness that drops batches of them through the actual
feature and reports exactly which ones end up off the platform or at an
implausible height afterward — the same "drive the real feature against a
real 4.7.1 binary" methodology as the ramp bug from the previous pass, just
scaled up to dozens of objects at once instead of one.

First finding, before changing anything: a tight stack of 20 balls with no
existing collision, using the previous code exactly as shipped, did not
explode — but it also didn't form a pile. It stacked into a rigid, almost
perfectly vertical tower, which was the first real clue. The reason: the
sweep proxy driving every object's own motion was **always a box**,
regardless of Auto Shape or of what collision (if any) the object already
had — a leftover simplification from the previous pass that was never
revisited once the ramp-sliding bug was fixed. A box standing in for a ball
can rest flush against another box-proxy ball the same way two crates would,
but it can't roll off one the way an actual sphere does, which is exactly
what turns a pile into a tower instead of a heap.

### The real fix: the sweep proxy now matches the object, not a box
- An object with exactly one existing collision shape (Box, Sphere, Capsule,
  Cylinder, or Convex Hull — anything that's safe to use as a *moving* query
  shape) now sweeps using that real shape, sized to its actual world scale.
  This is both the most accurate option available and literally the shape
  the user already set up — a prop with its own `SphereShape3D` now falls
  and rolls like a sphere, not a box standing in for one.
- An object with no usable existing collision (compound/multi-shape existing
  collision falls back to this too, since a single query shape can't
  represent several separate colliders at once) now builds its sweep shape
  from Auto Shape, sized from the real mesh rather than assumed to be a box:
  Sphere and Capsule are computed from the actual bounding geometry, and
  **Convex Hull now builds an actual hull from the mesh's own vertices**
  (capped per mesh part so a dense mesh doesn't hand the physics engine tens
  of thousands of candidate points for what is, after all, a temporary
  per-frame query) — this is the direct answer to "collision accurate to
  the real mesh," not an approximation of it.
- Added an **Auto-Add Missing Collision** toggle. Off, an object with no
  collision of its own is skipped from the simulation entirely (the status
  line reports how many) instead of getting anything added to it — full
  manual control for anyone who wants to handle collision themselves rather
  than let the tool add anything automatically, temporary or not.

### A second, deeper bug the shape fix immediately exposed
Switching the sweep proxy to an actual sphere shape for round objects — and,
separately, testing with a higher Bounciness value, since an actual bouncy
ball is a completely reasonable thing to want to simulate — made the
original ejection bug **worse**, not better: the same 20-ball stack went
from "0 ejected, tower" to "15 of 20 ejected," some ending up over 50 units
away and still falling. The box proxy had been accidentally *masking* this
one, not avoiding it — box-on-box contact in a neat stack mostly produces
vertical normals, so the underlying issue rarely got triggered; ball-on-ball
contact essentially never produces a purely vertical normal, so it triggered
constantly.

The root cause: this system has no real momentum exchange between two
falling objects — every object treats every *other* object as an immovable
obstacle when resolving its own collision, the same simplification that
makes single-object collision tractable to hand-roll at all. That's a
reasonable approximation against genuinely static level geometry (the
environment really isn't moving), but landing on top of *another currently
falling object* has a contact normal that's essentially always off-vertical
in a real pile — mechanically the same situation as the tilted-ramp-normal
bug from the previous pass, except now happening on every single ball-on-ball
contact in the pile rather than only when a ramp happened to be present.
Restitution reflecting a fast fall off a strongly tilted normal converts a
large fraction of that fall speed directly into sideways speed through the
geometry alone, and with no real momentum conservation to check it, that
speed doesn't have to go anywhere in particular — including straight off
the edge of whatever it landed on.

Fixed by treating a collision against another object still in the current
simulation batch as a different kind of contact from one against real level
geometry: it never bounces regardless of Bounciness (the previous pass's
soft-impact threshold already covered genuinely gentle contacts, but a hard
fall onto a pile is not a gentle contact), and on top of that, only a
fraction of its tangential (sideways) speed survives the hit at all —
because that speed was never real momentum being conserved correctly to
begin with, only a geometric artifact of hitting something at an angle,
carrying it forward as if it were real is what let one bad hit compound
into a chain reaction through the rest of the pile. Bounce is still exactly
as configured against the environment itself — a ball dropped onto the
ground bounces the way Bounciness says it should; a ball landing on *other
balls* settles into the pile instead.

### Stress-test sweep, all against the real 4.7.1 binary through the same harness
- 20 balls in a tight vertical stack, no existing collision, default
  settings — previously 0 ejected but an unnatural tower; now 0 ejected and
  a natural, roughly pyramidal pile.
- 20 balls in the same stack with raised Bounciness (0.55) and Sphere Auto
  Shape specifically, the exact combination that first reproduced the
  report — previously 15 of 20 ejected; now 0 ejected.
- 25 balls dropped from varied heights onto a small 6×6 platform (an edge
  close enough that a bad deflection would actually carry a ball off it) —
  0 ejected.
- 16 balls with their own real, pre-existing `SphereShape3D` collision
  (matching a user who already set up collision carefully rather than
  relying on Auto Shape at all) — 0 ejected, existing collision confirmed
  untouched throughout.
- 20 objects of mixed Box and Sphere meshes with no existing collision,
  once with Auto Shape set to Convex Hull and once left at the actual
  shipped default (Box) — 0 ejected either way.
- 60 objects in one batch, for scale — 0 ejected, completed in ~21 real
  seconds of headless simulation with no slowdown or instability.
- Auto-Add Missing Collision switched off against objects with no collision
  of their own — confirmed the simulation correctly starts with nothing to
  simulate and never moves them, rather than silently falling back to
  adding collision anyway.
- 8 capsules dropped tilted at random angles, plus one object built with a
  genuine compound existing collision (two separate shapes on one body, a
  flat top and a leg) — 0 ejected; the compound object's original two
  collision shapes were confirmed untouched before and after, and correctly
  fell back to an Auto-Shape-based sweep proxy since a single hull can't
  represent two separate existing colliders at once.
- 10 objects with strongly non-uniform scale (independently stretched or
  squashed per axis, Convex Hull Auto Shape) — 0 ejected, confirming the
  world-scale extraction holds up under scale that isn't uniform.
- Re-ran the full test suite from the previous pass (flat-ground settling
  and stacking, the tilted ramp, existing-collision preservation, Cancel) —
  all still pass unchanged.

### Known simplification, stated plainly rather than papered over
There is still no simulated torque or angular momentum — an object that
falls in at an angle settles by tilting to match the ground it lands on
(Align to Ground), not by physically toppling and rolling onto its side the
way a real elongated object dropped at an angle would. This is a real
limitation of a hand-rolled, translation-and-contact-response system with
no rotational dynamics, not an oversight; building genuine tipping physics
would mean modeling torque and moment of inertia, a substantially larger
undertaking than this feature's scope. It does not cause instability or
incorrect resting positions — objects always end up sitting still, at a
sensible height, the whole time it was tested — it simply won't tip over on
its own the way a real object might.

## Ninth pass — a real screenshot, a real bug, and a real performance trap it led to

### The report
A drop with a raised platform sitting on the ground and two dozen balls
lifted 17.9m up, Bounciness at 0: some balls ended up resting in positions
that plainly looked wrong. Reasonable, direct pushback followed: the
previous pass's stress-test sweep had said this was solid, so why was a
straightforward real-world setup still producing bad results.

### Reproducing it precisely before touching anything
Rebuilt the reported scene as closely as the screenshot allowed — a flat
ground, a raised box platform sitting on it, two dozen sphere props, the
same 17.9m lift height, the same zero Bounciness — and drove it through the
real feature via the same real-4.7.1-binary harness this whole feature has
been verified against from the start. Reproduced it on the first run: one
ball settled at a height that matched neither the ground, nor the platform
top, nor any clean stack of one ball on another — a physically meaningless
in-between value, sitting right where the platform's vertical corner meets
the ground beside it.

### Root cause #1: a safety-net check that quietly stopped being rare
The previous pass added a "stuck" fallback for a specific, narrow case:
`cast_motion` can fail to detect further collision once a query shape is
already overlapping something, which without a fallback would let an
object fall straight through the floor. That fallback's own overlap probe,
however, was still built as a plain box regardless of what shape the real
object actually was — the same "always a box" habit the eighth pass had
already found and fixed for the main sweep proxy, just missed here. A
flat-faced box probe grazing a curved neighbour mid-pile reads as a simple
"flat, straight up" contact no matter what angle the two shapes actually
meet at, which silently discarded the real contact geometry an off-centre
resting position on a round object depends on. Made the probe match the
real shape (sphere, capsule, cylinder, or a scaled convex hull, not always
a box) the same way the sweep proxy already does.

That alone didn't fully explain the reported ball, though — tracing it
frame by frame turned up something the shape mismatch was only a
contributing factor to:

### Root cause #2: two objects starting the simulation already overlapping
Scattering many objects into a lift, or dropping several props close
together, can easily leave two of them overlapping each other at the very
start — an entirely ordinary thing to happen, not a misuse of the tool.
The existing correction for this pushed the object out by a small fixed
step, once per frame. For a small, incidental overlap that's plenty. For
two objects that started meaningfully embedded in each other — plausible
with a modest lift and scatter — a few centimetres a frame was nowhere
near enough, and since both objects are usually still falling together the
entire way down, they never actually separated: the same correction kept
re-firing at nearly the same relative position for the rest of the drop,
never accumulating the low, steady velocity the settle timer needs, until
the absolute max-fall-time timeout finally forced a commit wherever the
two of them happened to be at that instant — which is exactly the
meaningless in-between height that was reported.

Rewrote this to resolve the full overlap within a single frame — checking
and pushing repeatedly (bounded and cheap once actually converging, not an
unbounded loop) until genuinely clear, rather than one token nudge per
frame spread across however many frames it takes. Re-ran the exact
reported scene repeatedly afterward: the ball that had been hovering
broken now lands in a clean, physically sensible stacked position — resting
on the neighbour that was actually beside it — every time.

### A settle check that was too easily fooled by an ordinary stack
While fixing the above, added a check that verifies an object is actually
touching something before letting it lock in as "settled," specifically to
catch this class of false-equilibrium case. The first version of that
check used a straight-down ray from the object's centre — which works for
an object resting flat on the ground, but not for the single most common
way anything actually settles once it's not alone on flat ground: leaning
at an angle against a neighbour to one side. A ray straight down from
dead-centre sails right past support that isn't directly underneath and
reports a large false gap, rejecting a perfectly good resting position, not
just the genuinely floating one the check was meant to catch. Replaced it
with a proper shape-overlap test (the same shrunk, shape-matched probe from
the fix above) — it finds real contact from any direction, not only
straight down, so an ordinary off-centre stack is correctly recognised as
settled instead of endlessly rejected and re-dropped.

### A second, unrelated bug this whole investigation exposed: Convex Hull's real cost
Chasing the above, a stress-test batch that should have been quick instead
ran for minutes. Timing `_step()` directly (not guessing from symptoms)
showed individual frames taking over half a second once several objects
were in contact — and the newly-added iterative overlap fix, measured the
same way, was not the cause; its own iteration counts stayed in the single
digits per frame throughout. The actual cause turned out to be independent
of anything changed this pass: the eighth pass's Convex Hull option built
its hull from up to 200 raw, unreduced mesh vertices per part, and
matching one such hull against another costs meaningfully more than
matching simple shapes does — cheap for one or two objects, expensive once
a dense pile of them are all checking against each other every frame. This
existed as soon as Convex Hull shipped; it simply took a dense enough
Convex Hull pile to surface it.

Rebuilt Convex Hull's point collection to reuse Godot's own hull-reduction
(the same `create_convex_shape` already used for the temporary per-mesh
collider), instead of a raw vertex sample — fewer points, and a genuinely
closer fit, since real hull vertices describe a shape better than an
arbitrary stride through unreduced ones. A batch that previously ran well
past two minutes without finishing now settles in well under a minute; the
default shape (Box) was unaffected by any of this and remains exactly as
fast as before. Convex Hull is inherently the most expensive of the four
Auto Shape options — that's an honest tradeoff for its accuracy on
irregular meshes, not a bug — and the docs now say so plainly, with a
pointer toward Sphere/Capsule/Box for large batches where one of them
already fits.

### Verification
Re-ran the exact reported scene to confirm the original bad position is
gone; re-ran the full stress-test sweep from the previous pass (tight ball
stacks, a small platform, real pre-existing SphereShape3D collision, mixed
Box/Sphere batches, 60 objects at once, Auto-Add Missing Collision
switched off, tilted capsules, a genuine compound-collision object,
non-uniform scale) to confirm none of it regressed; and separately timed
the 60-object batch under both Box (20s, matching the previous pass's
measurement exactly) and Convex Hull (down from over two minutes to well
under one) to confirm the performance fix without quietly making the
default path slower.

### On the previous pass's confidence
The eighth pass's stress-test sweep was real and its results were accurate
for what it tested — it simply hadn't tested a raised platform with a hard
corner, nor a dense enough Convex Hull pile to expose either issue here.
Both are now part of the standing test set precisely because of that gap,
not despite it.
