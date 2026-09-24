# Ultimate Asset Placer

**Professional 3D asset placement tool for Godot 4.7+** — place, paint, scatter, spline, and physics-drop your assets with a fast, tactile editor UI. Optimised for thousands of assets.

![Godot 4.7](https://img.shields.io/badge/Godot-4.7%2B-478cbf) ![Version](https://img.shields.io/badge/version-2.5.0-blue) ![License](https://img.shields.io/badge/license-MIT-green)

![Ultimate Asset Placer in the Godot editor](screenshots/editor_overview.png)

## Highlights

- **Four placement modes** — Free, Grid, Surface (physics raycast), and Vertex (mesh magnet snap).
- **Axis wall grids** — optional X/Z vertical snap planes (orange XY wall / green ZY wall), each with its own size, position and on/off toggle; objects snap onto whichever enabled plane is under the mouse.
- **Paint & volumetric brush** — drag-paint, circular brush with density/falloff, and mask textures.
- **MultiMesh painting** — thousands of instances in a single draw call.
- **Advanced spline system** — scatter props along curves or deform meshes into roads/rivers; terrain snapping; bake to nodes or MultiMesh.
- **Random transforms** — random rotation, tilt, and scale, per placement.
- **Groups & Favorites** — organise assets into named collections, random group placement.
- **Material override & auto collision** — Replace/Next-Pass materials, Static/Rigid/Character/Area bodies with five shape types.
- **Physics tab** — lift, drop, tumble and settle existing scene objects entirely inside the editor.
- **Asset Zoo** — lays out your whole library in a 3D grid for inspection.

## What's new in v2.5.0 — the star, fixed for real; quieter, tighter panel

### Update (rev 7) — axis wall grids (X / Z) + retractable rating stars

**Vertical snap grids are here.** Grid mode now supports two optional wall
grids alongside the blue floor grid, each toggled on/off individually from
the **Grid & Snapping** group in the Place tab: the **X Axis Grid** is the XY
plane drawn in orange (snaps X + Y, locks Z to its Pos Z), and the **Z Axis
Grid** is the ZY plane drawn in green (snaps Z + Y, locks X to its Pos X).
Every wall customises its **Size** (half-extent), **Pos** (depth along the
perpendicular axis) and **Center Y** (vertical centre). With several grids
enabled, whichever plane is **closest to the camera under your mouse**
receives the placement — look at the floor to place on the floor, look at a
wall to place on the wall. Perfect for windows, wall torches, shelves, signs
and any other vertical-surface work.

**The rating stars are now retractable.** A small arrow button just left of
the stars tucks them away or brings them back, without ever disturbing their
pinned right-corner spot. Hiding is manual and session-only: opening or
expanding the asset browser **always shows the stars again by default**.

**Also fixed:** the **Snap to Grid** checkbox used to be a dead control —
Grid mode always snapped regardless of its state. It now genuinely toggles
floor snapping, exactly as documented (default ON behaviour is unchanged).

![Axis wall grids in the Godot viewport](screenshots/axis_grids.png)

### Update (rev 6) — rating stars pinned to the header corner; version next to the title

**The rating stars now live permanently in the panel header's right corner.**
They are no longer part of the group chip strip: instead of wrapping around
with the group buttons, the five golden stars sit **always pinned to the
right corner of the title row** — exactly where the version label used to be,
just left of the collapse chevron. Add as many groups as you like: the chips
wrap onto extra lines while the stars never move, and toggling the panel
collapse doesn't move them either (the chip strip slides into the same title
row around them). Clicking the stars opens the plugin's **itch.io ratings
page** so you can leave a rating.

**The version label moved next to the title.** The header now reads
"Ultimate Asset Placer  2.5.0" on the left edge, freeing the right corner for
the stars.

![Rating stars pinned to the header corner](screenshots/rating_stars.png)

### Update (rev 5) — animated rating stars, tab reorder, material-error fix

**Animated rating stars.** Five golden stars with crisp black borders in the
asset browser header run two continuous animations: the row **bobs up and
down like a wave** (each star phase-shifted after its left neighbour), and
the stars **light up from white to gold one by one, left to right** — once
all five are gold they hold for a beat, **turn white together**, and the wave
starts over. Clicking anywhere in the stars area opens the plugin's ratings
page (`RATING_URL` in `ultimate_panel.gd` — one constant to repoint). The
stars scale with the editor scale and redraw only while visible. *(rev 6
update: they moved from the chip strip to the header's right corner.)*

**Collision & Physics tabs moved up; Groups & Keys are now the last tabs.**
The tab rail order is now Place, Transform, Paint, Spline, Material,
**Collision, Physics, Groups, Keys**, with the Docs button still last on the
rail. Every per-tab **(i)** help button follows the tabs to their new
positions automatically.

**"Parameter material is null" error spam — addressed.** Those four repeating
rendering errors are Godot engine bug `godotengine/godot#85817`: geometry
that references a **shared material through override slots** (a
`material_override` shared with other meshes plus per-surface overrides)
spams the errors when it is deleted, on Forward+. The plugin now removes
every condition it controlled that can trigger it:

- Every plugin teardown path (ghost removal, placed-asset delete, MultiMesh
  temp instances, thumbnail studio evictions) **wipes override slots while
  the nodes are still alive**, so the renderer never processes dangling
  material handles.
- **Replace material mode now truly replaces** — the asset's own per-surface
  overrides are cleared too (as the docs always promised), which also
  eliminates the exact override + surface-override combination the engine
  bug needs.
- A **duplicate-copy guard**: if a second copy of the addon is left in the
  project (an old folder or stray zip extract — visible as the plugin
  printing "Ready." twice at startup), the duplicate now refuses to boot
  with a clear message telling you which path to remove, instead of running
  a second panel + thumbnail studio alongside the real one.

### The favorite star — pinned to the corner, fully inside the card
Every previous round moved the star and it still looked wrong. Two real root
causes were found and eliminated:

1. An icon-only `Button` inherits the editor theme's Button **minimum size
   (32×28 px)**, so Godot silently grew the star's 16 px rect and drew the
   icon inside that oversized box. The star is now a `TextureButton` whose
   rect is **pixel-exact on every editor theme**.
2. The earlier "half outside the card" badge design let the star float in the
   gap between cards. Per the final mockup, the star is now **pinned ON the
   thumbnail's top-right corner, fully INSIDE the card** — top edge aligned
   with the thumbnail's top edge, right edge with its right edge. It can
   never overflow the card, at any card size (verified by a geometry probe
   on rendered screenshots at five different card sizes).

- Favorited stars are **gold**; unfavorited stars are dim white and brighten
  on hover.

![Asset cards with corner stars](screenshots/asset_cards.png)

### Thumbnails rebuilt: rectangular, sharp, fast — no more black bars
The whole thumbnail pipeline was rebuilt around the card's rectangular
thumbnail area:

- **Generated at the exact well aspect ratio** — every thumbnail is rendered
  by the plugin's own isolated studio SubViewport sized precisely like the
  card's thumbnail area, so images **fill the frame edge-to-edge**: no black
  bars, no letterboxing, no cropping, at any card size.
- **Resolution scales with the card size** — the render is ~1.5× the on-screen
  size (snapped to quality tiers up to 320 px), so enlarged cards show genuinely
  sharper thumbnails instead of upscaled blurry squares.
- **Every format gets the same studio treatment** — scenes (.tscn), imported
  models (.glb/.gltf/.fbx) and bare meshes (.obj/.dae) are all lit by the same
  three-point studio rig on one consistent background. The editor's small
  square previews are no longer used for the browser.
- **Faster and cache-friendly** — renders are disk-cached per size
  (`user://uap_thumbnails/assets_r3/`), so each asset renders once per size;
  later visits and sessions load instantly. The old square cache is cleaned up
  automatically. The queue stays throttled (one render at a time, off the
  interaction path) so browsing never stutters.
- Thumbnail drawing stays **clipped to its well**, and a centre-cover stretch
  makes bar-shaped artifacts structurally impossible even for stale textures.

### Docs always opens at the Welcome chapter
The **Docs button on the rail** now always opens **“Welcome & Quick Start”** —
previously it re-opened whatever chapter the last per-tab “(i)” button had
shown. The per-tab **(i)** buttons still deep-link straight to their tab's
chapter.

### Long tab descriptions removed
The paragraph blocks at the top of the Spline and Physics tabs (and the
drag-and-drop / auto-shape hints) are gone — every tab has the **(i)** help
button and the Docs window now, so the controls moved back up where you can
reach them.

### Standalone action buttons now read as buttons
The button fix now follows one precise rule: a button wears the **raised 3D
face** only when it sits **directly on the panel** — not inside any group
section — and would otherwise melt into the background. That covers Start
Physics (and its Stop / Cancel companions), **+ Create New Spline**, Exit
Spline Mode, Reset All to Defaults, and the Groups-tab action cluster:
**+ Add**, **Add**, the folder-import button, and **Remove from Group**,
which now carries a dark-red destructive face with white text. Steel blue is
the standard action color, dark red marks destructive actions, and amber
marks Stop while a simulation runs.

**Buttons inside a group section keep the quiet idle look** — Use Selected
Spline, Smooth / Sharpen, the terrain tools, the bake buttons, Lift Selected
Up, Reset X Y Z, Create Asset Zoo, the MultiMesh tools — so a raised face
always means "a real panel-level action", not just decoration.

On the Spline tab **+ Create New Spline was pulled out of the group** and now
sits directly **above Exit Spline Mode** — and neither button lives inside the
"1. Spline Node Setup" section.

![Physics tab with the raised Start Physics action](screenshots/physics_tab.png)

![Spline tab with Create New Spline above Exit Spline Mode](screenshots/spline_tab.png)

### Silent by default
The `[Ultimate Asset Placer] Theme pass dressed …` debug lines that were
printed to the Output dock on every panel build are gone. The plugin now only
announces that it is ready.

## What's new in v2.4.0 — carved asset cards, Open Scene / View Model

- **Asset cards are now dark inset 3D.** Resting cards are carved into the
  panel exactly like the group chips — a clearly darker face with a single
  darker line along the bottom edge, no border on any other side. No more
  cards blending into the background.
- **Selection frames the thumbnail.** A selected card is raised in blue 3D
  and its thumbnail gets a **blue ring** on top of the blue tint; Ctrl/Shift
  multi-select does the same in amber. The active color reads AROUND the
  image, not just under it.
- **White card names with a black outline** for crisp legibility over any
  thumbnail (asset browser card names only).
- **"Opened" chip.** The scene that is currently open in the editor is
  marked with an amber "Opened" tag in the bottom-left corner of its
  thumbnail (and keeps its warm card tint).
- **Roomier rows.** The asset grid now keeps a clearly larger vertical
  margin between rows than between columns, so rows no longer read cramped.
- **Open Scene / View Model in the card context menu.** Right-click a single
  card to open that scene in the editor, or view a model: mesh resources
  (obj/mesh) and imported scene formats (glb/gltf/fbx/blend) are shown in
  the Inspector with an interactive 3D mesh preview.

## What's new in v2.3.0 — borderless cards, whole-card clicks, per-tab help

### Resting cards: no outline, period
Unselected asset cards are now a **clean solid dark surface with nothing drawn around them** — the thin border (and the "open scene" amber ring) are gone. The thumbnail sits on its carved dark well; nothing else competes for attention.

### Click anywhere on a card
Clicking a card's **thumbnail now selects it** — previously only the name row worked because the thumbnail well silently swallowed mouse clicks. Thumbnail, name or padding: the entire card is one big click target.

### Selection that reads around the thumbnail
- **Single selection** — the whole card raises in **blue 3D** (solid face, darker bottom bevel, drop shadow) and the **thumbnail well is tinted blue**, so the highlight wraps the image.
- **Multi-selection (Ctrl/Shift)** — the same raised 3D treatment in **amber**, with an amber-tinted well. No more flat highlight box.

![Selection states](screenshots/asset_cards.png)

### Help (i) button on every tab title bar
The tab-name bar now carries an **info button** that opens the documentation window **directly at that tab's chapter** — Place opens "Place Tab", Groups opens "Groups & Favorites", and so on.

### Every last bright control re-themed
A new global dressing pass sweeps the entire panel and themes anything the explicit styles missed: **Create Asset Zoo**, the Zoo **Source dropdown** (and its popup list), the group dropdown, key rebinding controls, LineEdits — the whole panel now speaks one visual language.

## What's new in v2.2.0 — polish pass

### Carved-in 3D groups (everywhere, one design)
All groups — section boxes, group chips, group rows — now share a single **carved-in** look: a fill clearly **darker than the panel**, **no outline border on any side**, and a single darker **line along the bottom edge** that makes the surface read as chiseled into the panel.

![Carved-in groups](screenshots/carved_groups.png)

### Square asset cards with landscape thumbnails
Cards are now **perfectly square cells** with a **rectangular (landscape) thumbnail area** on top and the **name inside the card** at the bottom. The grid uses exact slot math, so cards **can never overlap or clip** again, and thumbnails keep their aspect ratio — never stretched, never cropped.

![Square asset cards](screenshots/square_cards.png)

### Advanced header collapse — groups stay on the bar
The **Search & Filters sub-collapse is gone** (folder/search/groups are always visible while expanded). The master bar collapse got smarter: expanded it shows the "Ultimate Asset Placer" title; **collapsed it moves the group chips into the bar** so every group remains one click away in the slim state.

![Collapsed bar with groups](screenshots/collapsed_groups_bar.png)

### Rail hover names + active tab title
Hovering a rail icon pops an **instant name label** (Place, Transform, Paint…) right next to the rail — no editor-tooltip delay. The **active tab's name is also written on a header bar on top of the tab panel**.

![Rail hover names](screenshots/rail_hover_names.png)

### No more dark text outline
Active button labels are plain near-white — the dark font outline around the text of the placement-mode and scroll buttons was removed.

## What's new in v2.1.0 — the "3D tactile" UI overhaul

### Tactile raised buttons
Every active control is now a **solid, raised 3D button** — full color, a darker bottom bevel, and a soft drop shadow. No semitransparency anywhere. Inactive buttons are clean flat dark with no harsh white highlight.

- Placement modes light up in their own color (Free grey / Grid blue / Surface green / Vertex yellow)
- Scroll Wheel Control's active target is highlighted blue — **including "Off"**, which previously had no visible active state

![Tactile 3D buttons](screenshots/tactile_buttons.png)

### Blender-style left feature rail
All nine feature pages live on a **vertical icon rail on the left edge of the panel** — like Blender's toolbar. Every feature is permanently one click away; no horizontal scrolling, no clipped tabs.

### Chapter-style Docs window
The Docs button opens a **dedicated documentation window in the center of the screen** with **15 clickable chapters** in a sidebar. Closing it returns you to exactly the feature page you were on.

![Documentation window](screenshots/docs_window.png)

### Right-click menu on asset cards
Right-click any card (or a whole multi-selection) to **add/remove favorites**, **add to any group**, or **remove assets from the browser list** (reversible — nothing is deleted from disk).

![Context menu](screenshots/context_menu.png)

### Inset 3D groups
Group chips (All / Favorites / your groups) are recessed **into** the panel — darker than the panel, no border, with a dark bottom line; the active chip is a deep blue recess with a gold star for Favorites.

![Group chips](screenshots/group_chips.png)

### Fixed favorite star overflow
The favorite star sits cleanly **inside** each card's top-right corner at every editor scale (it previously overflowed outside the card).

![Asset cards with favorite stars](screenshots/asset_cards.png)

See [CHANGELOG.md](CHANGELOG.md) for the complete, detailed change history.

## Installation

### Option A — from a release zip
1. Download `ultimate_asset_placer_v2.5.0.zip` from the [Releases](../../releases) page.
2. Extract it into your project folder so you end up with `res://addons/ultimate_placer/`.
3. Open **Project → Project Settings → Plugins** and enable **Ultimate Asset Placer**.
4. The **Asset Browser** appears as a bottom panel and the **settings panel** docks to the right.

### Option B — this repository
Clone the repository and open it directly in Godot 4.7+ — the plugin is pre-enabled and a `demo_assets/` folder with sample `.obj` models and a 3D scene is included for a quick test drive.

## Quick start

1. Open (or create) a **3D scene**.
2. In the **Asset Browser**, point **Folder** at a directory containing your 3D assets (`GLB, GLTF, FBX, OBJ, DAE, BLEND, TSCN, SCN, RES, MESH`) and click **Refresh**.
3. **Left-click** a thumbnail card — a ghost preview follows your cursor in the viewport.
4. **Left-click** in the viewport to place. **Right-click / ESC** stops placing.
5. Everything is undoable with **Ctrl+Z**.

Tip: switch the scroll wheel target with the blue buttons (Scale, Rot Y/X/Z, Height — or Off), and use the **left rail** to reach any feature page in one click.

## Feature tour

| Area | What it does |
|---|---|
| **Placement modes** | Free, Grid, Surface, Vertex — switchable any time, even mid-placement |
| **Scroll Wheel Control** | Assign the wheel to Scale / Rot Y / Rot X / Rot Z / Height, or turn it off |
| **Place tab** | Parent node, grid snapping, height offset, format filter, hidden-asset restore, Asset Zoo |
| **Transform tab** | Rotation snap, live rotation sliders, 8 orient presets, random rotation/tilt/scale |
| **Paint tab** | Drag painting, volumetric brush with mask textures, Random Group Placer, MultiMesh painter |
| **Spline tab** | Curve scattering & mesh deformation, terrain snapping, bake to nodes or MultiMesh |
| **Material tab** | Automatic material override (Replace or Next Pass) |
| **Groups tab** | Named collections, folder import, smart multi-remove |
| **Keys tab** | Rebind every placement shortcut |
| **Collision tab** | Auto collision: 4 body types × 5 shape types |
| **Physics tab** | Editor-side physics simulation to drop and settle objects |
| **Docs button** | Opens the chapter-style documentation window |

## Documentation

The full manual ships inside the plugin — click the **Docs** button at the bottom of the left rail (the book icon) or the **(i) button on any tab's title bar** to jump straight to that tab's chapter. It covers every setting, all keyboard shortcuts, six workflow walkthroughs, performance notes, and a troubleshooting FAQ.

## System requirements

- **Godot 4.7 or newer** (standard build — no .NET required)
- Works with any project that can open a 3D scene
- HiDPI-ready: respects **Editor Settings → Interface → Editor Scale**

## Repository layout

```
├── addons/ultimate_placer/   # the plugin (drop this folder into any project)
│   ├── plugin.gd             # EditorPlugin entry point
│   ├── ultimate_panel.gd     # editor UI (browser, rail, tabs, docs window)
│   ├── ultimate_placer.gd    # placement engine
│   ├── uap_physics.gd        # editor-side physics simulator
│   ├── uap_path.gd           # advanced spline system
│   ├── uap_docs.gd           # chapter-based documentation source
│   ├── uap_icons.gd          # icon loader/cache
│   ├── uap_thumb_gen.gd      # offline thumbnail renderer
│   └── icons/                # flat SVG icon set
├── demo_assets/              # sample .obj models + a demo 3D scene
├── screenshots/              # images used in this README
├── CHANGELOG.md              # full version history
└── project.godot             # ready-to-open Godot 4.7 project
```

## Contributing & support

Found a bug or have a feature request? Open an issue here on GitHub. The plugin is also available on [itch.io](https://choco-ted.itch.io/ultimate-asset-placer-godot-45-gd-script).

## License

MIT — see [LICENSE](LICENSE).
