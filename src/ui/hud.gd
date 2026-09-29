class_name Hud
extends CanvasLayer
## Native UI root (script of scenes/hud.tscn). Builds the whole HUD in code from the components in
## src/ui and the theme of UiTheme; talks to the world only through Simulation / Session / Quality.
##
## Composition (UI at the edges, the centre belongs to the world):
##   top-left     DemoBadge (always visible, also with the HUD hidden)
##   top-centre   ModeBar                       top-right   SettingsMenu
##   left         ForgePanel (FORGE) | UniversePanel (UNIVERSE) | ObservatoryPanel sheet (~38%, OBSERVATORY)
##   right        Inspector (when something is selected; top-right, bottom-right in OBSERVATORY)
##                · EventFeed (FORGE / UNIVERSE, above the transport)
##   bottom       Transport (buttons, timeline, time, phase, speed)
## Mode changes cross-fade the mode panels (Palette.T_BASE in, T_FAST out). `Session.hud_visible`
## (H) fades out everything except the badge. Layout nodes never catch the mouse; only panels do.
## Time/phase text refreshes at Palette.T_UI_REFRESH; lists rebuild on events / world_rebuilt only.

const SIDE_WIDTH := 264.0
const INSPECTOR_WIDTH := 288.0
const TOP_BAND := 64.0

var root: Control
var chrome: Control
var badge: DemoBadge
var mode_bar: ModeBar
var settings: SettingsMenu
var transport: Transport
var feed: EventFeed
var inspector: Inspector
var forge_panel: ForgePanel
var universe_panel: UniversePanel
var observatory_panel: ObservatoryPanel

var _refresh_left := 0.0
## Y (offset from the bottom edge) of the top of the transport, minus the gap.
var _bottom_y := -120.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.name = "Root"
	root.theme = UiTheme.get_theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	chrome = Control.new()
	chrome.name = "Chrome"
	chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chrome.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(chrome)

	var edge := float(Palette.UI_EDGE)

	observatory_panel = ObservatoryPanel.new()
	_anchor(observatory_panel, 0.0, 0.0, Palette.OBSERVATORY_PANEL_SHARE, 1.0)
	observatory_panel.offset_top = TOP_BAND
	chrome.add_child(observatory_panel)

	forge_panel = ForgePanel.new()
	_place_top_left(forge_panel, edge, TOP_BAND + 8.0, SIDE_WIDTH)
	chrome.add_child(forge_panel)

	universe_panel = UniversePanel.new()
	_place_top_left(universe_panel, edge, TOP_BAND + 8.0, SIDE_WIDTH)
	chrome.add_child(universe_panel)

	inspector = Inspector.new()
	inspector.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	inspector.visible = false
	chrome.add_child(inspector)

	feed = EventFeed.new()
	_anchor(feed, 1.0, 1.0, 1.0, 1.0)
	feed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	feed.grow_vertical = Control.GROW_DIRECTION_BEGIN
	feed.offset_right = -edge
	feed.offset_left = -edge - INSPECTOR_WIDTH
	chrome.add_child(feed)

	transport = Transport.new()
	_anchor(transport, 0.0, 1.0, 1.0, 1.0)
	transport.grow_vertical = Control.GROW_DIRECTION_BEGIN
	transport.offset_left = edge
	transport.offset_right = -edge
	transport.offset_bottom = -edge + 4.0
	transport.offset_top = transport.offset_bottom
	transport.resized.connect(_layout_bottom)
	chrome.add_child(transport)

	mode_bar = ModeBar.new()
	_anchor(mode_bar, 0.5, 0.0, 0.5, 0.0)
	mode_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	mode_bar.offset_top = 14.0
	chrome.add_child(mode_bar)

	settings = SettingsMenu.new()
	_anchor(settings, 1.0, 0.0, 1.0, 0.0)
	settings.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	settings.offset_right = -edge
	settings.offset_left = -edge
	settings.offset_top = 14.0
	chrome.add_child(settings)

	# The badge lives outside the chrome: hiding the HUD never hides it.
	badge = DemoBadge.new()
	_place_top_left(badge, edge, 18.0, 0.0)
	root.add_child(badge)

	inspector.visibility_wanted.connect(_on_inspector_wanted)
	Session.mode_changed.connect(_on_mode_changed)
	Session.hud_visibility_changed.connect(_on_hud_visibility_changed)
	_layout_bottom()
	_apply_mode(false)
	_apply_hud_visible(Session.hud_visible, false)
	_on_inspector_wanted(inspector.wants_visible())


func _process(delta: float) -> void:
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = Palette.T_UI_REFRESH
	if chrome.visible:
		transport.refresh()


## Panels shown in `mode` (besides the inspector, which follows the selection).
func mode_panels(mode: SessionState.Mode) -> Array[Control]:
	match mode:
		SessionState.Mode.UNIVERSE:
			return [universe_panel, feed]
		SessionState.Mode.OBSERVATORY:
			return [observatory_panel]
	return [forge_panel, feed]


func _apply_mode(animated: bool) -> void:
	var show := mode_panels(Session.mode)
	for p: Control in [forge_panel, universe_panel, observatory_panel, feed]:
		var on := show.has(p)
		if animated:
			UiKit.fade(p, on, Palette.T_BASE if on else Palette.T_FAST)
		else:
			p.visible = on
			p.modulate.a = 1.0 if on else 0.0


func _on_mode_changed(_m: SessionState.Mode) -> void:
	_apply_mode(true)
	_dock_inspector()
	if inspector.visible:
		inspector.modulate.a = 0.0
		UiKit.fade(inspector, true, Palette.T_BASE)


func _on_inspector_wanted(on: bool) -> void:
	UiKit.fade(inspector, on, Palette.T_BASE if on else Palette.T_FAST)


func _on_hud_visibility_changed(v: bool) -> void:
	_apply_hud_visible(v, true)


func _apply_hud_visible(v: bool, animated: bool) -> void:
	if not v:
		settings.set_open(false)
	if animated:
		UiKit.fade(chrome, v, Palette.T_BASE if v else Palette.T_FAST)
	else:
		chrome.visible = v
		chrome.modulate.a = 1.0 if v else 0.0
	if v:
		transport.refresh()


## Keeps the feed and the OBSERVATORY sheet just above the transport, whatever its height.
func _layout_bottom() -> void:
	var h := maxf(transport.size.y, transport.get_combined_minimum_size().y)
	_bottom_y = transport.offset_bottom - h - Palette.UI_GAP
	feed.offset_bottom = _bottom_y
	feed.offset_top = feed.offset_bottom
	observatory_panel.offset_bottom = _bottom_y
	_dock_inspector()


## The inspector sits top-right; in OBSERVATORY it moves bottom-right, above the transport, so
## it does not cover the structure framed in the free area right of the sheet (the feed, which
## owns that corner in the other modes, is hidden there).
func _dock_inspector() -> void:
	var edge := float(Palette.UI_EDGE)
	var bottom := Session.mode == SessionState.Mode.OBSERVATORY
	_anchor(inspector, 1.0, 1.0 if bottom else 0.0, 1.0, 1.0 if bottom else 0.0)
	inspector.grow_vertical = Control.GROW_DIRECTION_BEGIN if bottom else Control.GROW_DIRECTION_END
	inspector.offset_right = -edge
	inspector.offset_left = -edge - INSPECTOR_WIDTH
	var y := _bottom_y if bottom else TOP_BAND + 8.0
	inspector.offset_top = y
	inspector.offset_bottom = y


static func _anchor(c: Control, left: float, top: float, right: float, bottom: float) -> void:
	c.anchor_left = left
	c.anchor_top = top
	c.anchor_right = right
	c.anchor_bottom = bottom


static func _place_top_left(c: Control, x: float, y: float, width: float) -> void:
	_anchor(c, 0.0, 0.0, 0.0, 0.0)
	c.offset_left = x
	c.offset_top = y
	c.offset_right = x + width
	c.offset_bottom = y
