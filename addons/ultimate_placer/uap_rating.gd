extends Control

## Ultimate Asset Placer — Rating Stars (2.5)
##
## Five golden stars with crisp black borders that live at the end of the
## group/filter chip strip in the asset browser header. The strip is a
## FlowContainer, so the chips wrap BEFORE the stars on the first line and
## the stars hop onto the second line as one atomic block (they never split).
##
## The stars run two continuous, always-smooth animations:
##   1. BOB WAVE   — every star floats up and down on a sine wave, phase-
##                   shifted left to right, so the row ripples like a wave.
##   2. COLOR WAVE — the stars light up from white to gold one by one, left
##                   to right; once all five are gold they hold for a beat,
##                   then the whole row fades back to white together and the
##                   wave starts over.
##
## Clicking ANYWHERE inside the stars area opens the plugin's ratings page
## (see RATING_URL in ultimate_panel.gd). The whole control is the button —
## no per-star hit testing needed.
##
## Performance: this is one tiny Control. _process only queues a redraw while
## the control is actually visible in the tree, and each redraw draws 5 ten-
## vertex polygons + 5 polylines — utterly negligible per frame.

signal activated                                   # fired on click (left button)

const STAR_COUNT := 5

# ── Geometry (recomputed when the control is resized) ─────────────────────────
var _star_pts: PackedVector2Array = PackedVector2Array()  # unit star polygon
var _centers: PackedVector2Array = PackedVector2Array()   # resting center per star
var _base_r: float = 8.0                                  # resting star radius (px)

# ── Animation state ────────────────────────────────────────────────────────────
var _t: float = 0.0
var _hover_amt: float = 0.0        # 0..1, eased towards the real hover state
var _hovered: bool = false         # tracked via mouse_entered/mouse_exited
var _click_pulse: float = 0.0      # 1.0 right after a click, decays to 0

# Bob wave tuning (seconds / pixels are scaled by _es in the panel)
const BOB_SPEED := 2.7             # rad/s — full bob cycle ≈ 2.3 s
const BOB_PHASE_STEP := 0.62       # rad between neighbours — the wave travel
const BOB_AMP := 2.6               # px at 100%

# Color wave timeline (seconds)
const C_STEP := 0.24               # start delay between neighbouring stars
const C_RAMP := 0.34               # per-star white→gold ramp duration
const C_HOLD := 0.85               # all-gold hold before the reset
const C_RESET := 0.30              # all-together gold→white fade
const C_PAUSE := 0.45              # all-white breather before the next wave

# Palette
const GOLD := Color(1.0, 0.845, 0.05)
const WHITE := Color(0.965, 0.965, 0.975)
const BORDER := Color(0.035, 0.035, 0.05)
const BORDER_HOVER := Color(0.0, 0.0, 0.0)

var _es: float = 1.0

func _init(es: float = 1.0) -> void:
        _es = maxf(0.6, es)
        mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
        size_flags_vertical = Control.SIZE_FILL          # stretch to the chip row height
        tooltip_text = "Rate Ultimate Asset Placer — click to open the ratings page"
        # Height floor: the FlowContainer line already matches the chip height, but
        # a zero min-height child could be collapsed by some layout paths — the
        # floor keeps the stars visible (and RESIZED re-fits if the line is taller).
        custom_minimum_size = Vector2(_total_width(), _min_height())

func _min_height() -> float: return 24.0 * _es

func _total_width() -> float:
        var star_d := 2.0 * _base_r
        return (STAR_COUNT * star_d + (STAR_COUNT - 1) * _gap()) + 2.0 * _pad_x()

func _gap() -> float: return 3.0 * _es
func _pad_x() -> float: return 2.0 * _es

## Full duration of one color-wave cycle.
func _cycle_len() -> float:
        return (STAR_COUNT - 1) * C_STEP + C_RAMP + C_HOLD + C_RESET + C_PAUSE

func _notification(what: int) -> void:
        if what == NOTIFICATION_RESIZED:
                _rebuild_geometry()

## Rebuilds the cached unit-star polygon and resting centers for the current
## size. Kept allocation-free per frame by only running on resize/init.
func _rebuild_geometry() -> void:
        var h := size.y
        if h <= 0.0: h = _min_height()
        # Fit the stars to whatever row height the FlowContainer gives us (the
        # collapsed header row is shorter than the chip strip) but never let them
        # grow beyond the designed resting size.
        var r: float = minf((h - 6.0 * _es) * 0.5, 9.2 * _es)
        r = maxf(r, 4.0)
        _base_r = r
        var cy := h * 0.5
        var star_d := 2.0 * _base_r
        _centers = PackedVector2Array()
        _centers.resize(STAR_COUNT)
        var x := _pad_x() + _base_r
        for i in STAR_COUNT:
                _centers[i] = Vector2(x, cy)
                x += star_d + _gap()
        custom_minimum_size = Vector2(_total_width(), _min_height())
        # Unit star polygon at radius 1.0 — scaled per draw. 10 vertices,
        # alternating outer/inner, starting at the top point.
        _star_pts = PackedVector2Array()
        _star_pts.resize(10)
        var inner := 0.47   # chunky, friendly star (classic pentagram is 0.382)
        for k in 10:
                var ang := -PI * 0.5 + float(k) * PI * 0.2
                var rad := 1.0 if (k % 2) == 0 else inner
                _star_pts[k] = Vector2(cos(ang), sin(ang)) * rad

func _ready() -> void:
        _rebuild_geometry()
        focus_mode = Control.FOCUS_NONE
        mouse_entered.connect(func(): _hovered = true)
        mouse_exited.connect(func(): _hovered = false)

func _process(delta: float) -> void:
        # Zero cost while the browser panel is hidden/collapsed away.
        if not is_visible_in_tree():
                return
        _t += delta
        _hover_amt = move_toward(_hover_amt, 1.0 if _hovered else 0.0, delta * 7.0)
        if _click_pulse > 0.0: _click_pulse = move_toward(_click_pulse, 0.0, delta * 3.5)
        queue_redraw()

## Per-star fill factor 0 (white) .. 1 (gold) for the current cycle time.
func _gold_factor(i: int, t: float) -> float:
        var start: float = i * C_STEP
        if t < start:
                return 0.0
        var up: float = t - start
        if up < C_RAMP:
                # smoothstep — silky white→gold per star
                var k := up / C_RAMP
                return k * k * (3.0 - 2.0 * k)
        var all_done: float = (STAR_COUNT - 1) * C_STEP + C_RAMP
        if t < all_done + C_HOLD:
                return 1.0                                  # hold, all gold
        if t < all_done + C_HOLD + C_RESET:
                # all stars fade back to white TOGETHER (this is the "then all turned
                # white" beat the wave is named for)
                var k2 := (t - all_done - C_HOLD) / C_RESET
                return 1.0 - (k2 * k2 * (3.0 - 2.0 * k2))
        return 0.0                                      # white pause until loop

func _draw() -> void:
        if _star_pts.is_empty() or _centers.is_empty():
                _rebuild_geometry()
                if _star_pts.is_empty(): return
        var hover_boost: float = _hover_amt * 0.9 + _click_pulse
        for i in STAR_COUNT:
                var c: Vector2 = _centers[i]
                # Bob wave — sine keeps the motion perfectly smooth; phase steps left
                # to right so the row ripples sequentially. Hover gently raises the
                # amplitude; the click pulse adds a quick extra hop.
                var yoff := sin(_t * BOB_SPEED - float(i) * BOB_PHASE_STEP) \
                                * (BOB_AMP * _es * (1.0 + hover_boost))
                var r := _base_r * (1.0 + 0.06 * hover_boost)
                var gold: float = clampf(_gold_factor(i, fmod(_t, _cycle_len())) + _hover_amt * 0.25, 0.0, 1.0)
                var fill: Color = WHITE.lerp(GOLD, gold)
                # Fill
                var pts := PackedVector2Array()
                pts.resize(_star_pts.size())
                for k in _star_pts.size():
                        pts[k] = c + _star_pts[k] * r + Vector2(0.0, yoff)
                draw_colored_polygon(pts, fill)
                # Crisp black border on top (closed polyline = loop back to vertex 0)
                var line := pts.duplicate()
                line.append(pts[0])
                draw_polyline(line, BORDER_HOVER if _hover_amt > 0.5 else BORDER, maxf(1.4, 1.7 * _es), true)
        # Soft golden glow underlay while hovered — drawn as a wide translucent
        # polyline behind the fill would require reordering; instead a subtle
        # second pass on the TOP star row is skipped to keep the draw lean.

func _gui_input(event: InputEvent) -> void:
        if event is InputEventMouseButton:
                var mb := event as InputEventMouseButton
                if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
                        _click_pulse = 1.0
                        accept_event()
                        activated.emit()
        elif event is InputEventMouseMotion:
                # redraw on hover-in/out is handled per-frame; nothing needed here
                pass
