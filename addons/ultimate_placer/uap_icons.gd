@tool
extends RefCounted
class_name UAPIcons
## Centralized icon loader/cache for the Ultimate Asset Placer addon.
##
## All icons are single-tone (white) flat SVGs at a 24x24 design grid, the
## same convention Godot's own EditorIcons use. Godot rasterizes SVGs on
## import and has no CSS "currentColor", so tint them at RUNTIME instead of
## shipping colored duplicates — see tint_button() below.

const ICON_DIR_FALLBACK := "res://addons/ultimate_placer/icons/"

static var _cache: Dictionary = {}
static var _warned: Dictionary = {}
static var _addon_root_cache: String = ""

## Resolves the addon's actual install folder by asking Godot where THIS
## script itself was loaded from, rather than assuming a fixed folder name.
## This is the fix for a real crash: if the addon is nested one level
## deeper than expected (e.g. a zip extracted with an extra wrapper folder,
## or the addon renamed for organizational reasons), every hardcoded
## "res://addons/ultimate_placer/..." path silently fails to load with
## "File not found" — which is exactly what happened. Every script in this
## addon resolves its own folder the same way instead of hardcoding it.
static func get_addon_root() -> String:
	if not _addon_root_cache.is_empty(): return _addon_root_cache
	var tmp := UAPIcons.new()
	var p: String = tmp.get_script().resource_path
	_addon_root_cache = (p.get_base_dir() + "/") if not p.is_empty() else ICON_DIR_FALLBACK.get_base_dir().get_base_dir() + "/"
	return _addon_root_cache

static func get_icon_dir() -> String:
	return get_addon_root() + "icons/"

## Returns a cached Texture2D for the given icon name (no ".svg", no path —
## e.g. UAPIcons.get_icon("action_add")). Returns null if missing, and never
## throws, so a missing icon degrades to "no icon" rather than a load error.
##
## NOTE: only successful loads are cached. On a brand new install, Godot may
## still be importing the freshly-added icon .svg files when this plugin
## first initializes (a real race — verified via testing a genuinely fresh
## project import, not assumed). If we cached a failed lookup permanently,
## the icon would stay missing forever even after Godot finished importing
## it moments later. Leaving failures uncached means the next call (e.g. via
## refresh_icons() below, or simply reopening a tab) tries again for free.
static func get_icon(icon_name: String) -> Texture2D:
	if _cache.has(icon_name):
		return _cache[icon_name]
	var path := get_icon_dir() + icon_name + ".svg"
	if not ResourceLoader.exists(path):
		if not _warned.has(icon_name):
			_warned[icon_name] = true
			push_warning("Ultimate Asset Placer: icon '%s' not found at %s (this is expected transiently on a brand-new install until Godot finishes importing; if it persists, the icon name is likely wrong)" % [icon_name, path])
		return null
	var tex := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE) as Texture2D
	if tex != null:
		_cache[icon_name] = tex
	return tex

## Clears the successful-load cache, forcing the next get_icon() call per
## icon to hit ResourceLoader again. Used after Godot confirms it has
## finished importing resources, in case some icons were requested (and
## came back null) before their import finished.
static func clear_cache() -> void:
	_cache.clear()

## Convenience: set a Button's icon by name in one call.
static func set_button_icon(btn: Button, icon_name: String) -> void:
	var tex := get_icon(icon_name)
	if tex != null: btn.icon = tex

## Returns a Texture2D pre-resized to an exact pixel size, cached per
## (icon_name, size) pair.
##
## Use this instead of Button.expand_icon when a button needs to be smaller
## than the icon's native 24x24 design size. expand_icon is meant for
## growing a small icon to fill a larger button and is the right tool for
## that; asked to do the opposite — shrink a 24x24 icon into an 18x18 or
## smaller button — it was found, via an actual rendered screenshot inside
## the real editor (not just a headless size/rect check, which had already
## passed and gave no hint anything was wrong), to sometimes render the
## icon at only a few pixels rather than the computed fit size, collapsing
## a star into an unrecognizable blob. Pre-resizing the actual texture data
## once here sidesteps that at-a-distance layout computation entirely — the
## icon IS the target size, nothing needs to "fit" it into anything.
static func get_icon_sized(icon_name: String, size: int) -> Texture2D:
	var key := "%s@%d" % [icon_name, size]
	if _cache.has(key):
		return _cache[key]
	var base_tex := get_icon(icon_name)
	if base_tex == null: return null
	var img := base_tex.get_image()
	if img == null: return null
	img = img.duplicate()
	img.resize(size, size, Image.INTERPOLATE_LANCZOS)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

## Convenience: set a Button's icon to a pre-resized texture by name and
## exact pixel size in one call — see get_icon_sized() above for why this
## exists instead of just setting .icon plus expand_icon.
static func set_button_icon_sized(btn: Button, icon_name: String, size: int) -> void:
	var tex := get_icon_sized(icon_name, size)
	if tex != null: btn.icon = tex

## Returns a Texture2D like get_icon_sized(), but with a solid dark outline
## baked directly into the pixel data around the icon's silhouette, cached
## per (icon_name, size).
##
## Small icons overlaid on asset thumbnails have no reliable background —
## real thumbnails range from near-black to near-white, and a flat-color
## icon (tinted via icon_normal_color, which only multiplies the existing
## pixel colors) has good contrast against some and none at all against
## others; confirmed directly against a real near-white test thumbnail.
## Baking a dark, mostly-opaque outline into the texture itself guarantees
## a visible edge regardless of what's underneath, without needing a
## separate solid backing shape behind it. It also means every tint stays
## correct automatically: outline pixels are near-black, and multiplying
## near-black by any tint color (white, gold, whatever a future state
## needs) stays near-black, so the same one texture works for every
## favorited/hover/pressed state without regenerating it per color.
##
## Works by dilating the icon's alpha mask outward by outline_px at a
## higher working resolution (smoother edges than dilating the small final
## size directly, confirmed by comparing both directly), then downsampling
## to the requested size: any pixel within outline_px of an opaque source
## pixel, but not itself opaque, becomes part of the outline layer.
static func get_icon_outlined(icon_name: String, size: int, outline_color: Color = Color(0.05, 0.05, 0.07, 0.95), outline_px: int = 2) -> Texture2D:
	var key := "outline:%s@%d" % [icon_name, size]
	if _cache.has(key):
		return _cache[key]
	var base_tex := get_icon(icon_name)
	if base_tex == null: return null
	var src := base_tex.get_image()
	if src == null: return null
	src = src.duplicate()
	var work_size := size * 3
	src.resize(work_size, work_size, Image.INTERPOLATE_LANCZOS)

	var out := Image.create(work_size, work_size, false, Image.FORMAT_RGBA8)
	var alpha_threshold := 0.35
	# Dilate: mark every pixel within outline_px (scaled to the working
	# resolution) of an opaque source pixel.
	var radius: int = outline_px * 3
	for y in work_size:
		for x in work_size:
			var src_px := src.get_pixel(x, y)
			if src_px.a > alpha_threshold:
				out.set_pixel(x, y, src_px)
				continue
			var found := false
			var rr: int = radius * radius
			var y_min: int = maxi(0, y - radius)
			var y_max: int = mini(work_size - 1, y + radius)
			var x_min: int = maxi(0, x - radius)
			var x_max: int = mini(work_size - 1, x + radius)
			var yy: int = y_min
			while yy <= y_max and not found:
				var xx: int = x_min
				while xx <= x_max and not found:
					var dx: int = xx - x
					var dy: int = yy - y
					if dx * dx + dy * dy <= rr and src.get_pixel(xx, yy).a > alpha_threshold:
						found = true
					xx += 1
				yy += 1
			if found:
				out.set_pixel(x, y, outline_color)
			else:
				out.set_pixel(x, y, Color(0, 0, 0, 0))

	out.resize(size, size, Image.INTERPOLATE_LANCZOS)
	var tex := ImageTexture.create_from_image(out)
	_cache[key] = tex
	return tex

## Convenience: set a Button's icon to an outlined, exact-size texture in
## one call — see get_icon_outlined() above.
static func set_button_icon_outlined(btn: Button, icon_name: String, size: int) -> void:
	var tex := get_icon_outlined(icon_name, size)
	if tex != null: btn.icon = tex

## Tints a button's icon via theme color overrides (normal/hover/pressed/
## disabled) instead of needing a separately-colored SVG per state/mode.
## `base` is used for the resting state; hover/pressed are auto-derived
## unless explicitly provided.
static func tint_button(btn: Button, base: Color, hover: Variant = null, pressed: Variant = null) -> void:
	var hover_c: Color = hover if hover is Color else base.lightened(0.18)
	var pressed_c: Color = pressed if pressed is Color else base
	btn.add_theme_color_override("icon_normal_color", base)
	btn.add_theme_color_override("icon_hover_color", hover_c)
	btn.add_theme_color_override("icon_pressed_color", pressed_c)
	btn.add_theme_color_override("icon_focus_color", hover_c)

## Sets a TextureRect's texture by icon name and optionally tints it via
## self_modulate (TextureRect has no per-state theme colors, so a flat
## modulate is the equivalent for a static icon display).
static func set_texture_rect(tr: TextureRect, icon_name: String, tint: Variant = null) -> void:
	var tex := get_icon(icon_name)
	if tex != null: tr.texture = tex
	if tint is Color: tr.self_modulate = tint

## Returns a small inline BBCode [img] tag for embedding an icon in a
## RichTextLabel (used by uap_docs.gd's section headers).
static func bbcode_img(icon_name: String, size: int = 15) -> String:
	return "[img=%dx%d]%s%s.svg[/img]" % [size, size, get_icon_dir(), icon_name]

## Single source of truth for the plugin's version number, read directly
## from plugin.cfg every time (cheap — ConfigFile parsing a tiny file) so it
## can never drift out of sync in any of the several places it's displayed
## (the browser header, the manual's title banner and footer, the startup
## log line) the way "1.5.0" was found hardcoded in more than one of them.
static func get_plugin_version() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(get_addon_root() + "plugin.cfg") == OK:
		return str(cfg.get_value("plugin", "version", "?"))
	return "?"
