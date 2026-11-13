class_name TrackRenderer
extends Node2D
## 单轨轨道绘制器。负责把 TrackGeometry 画成钢轨、枕木、支柱、起点和终点。
## 不参与碰撞，不读取文件；编辑器与游戏共用，通过 edit_mode 切换辅助标记。

var _track: TrackGeometry
var _theme: Dictionary = {}
var _start_s: float = 0.0
var _finish_s: float = 0.0
var _edit_mode: bool = false
var _selected_piece: int = -1
var _accent: Color = Color(1.0, 0.82, 0.25)
var _warning_pieces: Dictionary = {}
var _broken_states: Dictionary = {}
var _piece_quads_cache: Dictionary = {}
var _fx_accum: float = 0.0
var _warning_time: float = 0.0
var _warning_layer: TrackFxLayer
var _fall_layer: TrackFxLayer

# ---- 分块裁剪 ----
## 单个块的目标弧长。以 piece 为原子单位打包：块内 piece 累计弧长超过此值就另起一块，
## 因此每个 piece 只属于一个块，断缝边界与块边界天然对齐，绘制路径可完全复用。
const CHUNK_TARGET_LENGTH := 640.0
## 块 AABB 的外扩余量。需覆盖轨道半高、枕木（±9）与 fallback 的粗 polyline（半宽 6.5）。
const CHUNK_AABB_MARGIN := 32.0

var _chunks: Array[TrackChunk] = []
## 块索引 → 该块包含的 piece 索引数组。
var _chunk_pieces: Array = []
## 块索引 → 该块的包围盒（世界坐标，已外扩余量）。
var _chunk_rects: Array[Rect2] = []
## piece 索引 → 块索引；预警/断裂时只重绘受影响的块，而不是整条轨道。
var _piece_chunk: Dictionary = {}
## 是否启用裁剪。编辑器需要看到全貌且自带缩放，一律关闭。
var _cull_enabled: bool = false
## 上一帧的视口矩形；未变化时跳过整轮可见性计算。
var _last_view_rect := Rect2()
var _has_last_view_rect: bool = false


func _ready() -> void:
	_prepare_layers()


## 预警/断裂只重绘独立子层，静态轨道不参与每帧重绘。
func _prepare_layers() -> void:
	if _warning_layer == null:
		_warning_layer = TrackFxLayer.new()
		_warning_layer.name = "WarningLayer"
		_warning_layer.target = self
		_warning_layer.kind = 0
		add_child(_warning_layer)
	if _fall_layer == null:
		_fall_layer = TrackFxLayer.new()
		_fall_layer.name = "FallLayer"
		_fall_layer.target = self
		_fall_layer.kind = 1
		add_child(_fall_layer)



func configure(
	level: LevelData,
	edit_mode: bool = false,
	selected_piece: int = -1
) -> void:
	_prepare_layers()
	_track = level.track
	_theme = level.theme.duplicate(true)
	_start_s = level.start_s
	_finish_s = level.finish_s
	_edit_mode = edit_mode
	_selected_piece = selected_piece
	_accent = level.get_theme_color("accent", Color(1.0, 0.82, 0.25))
	_warning_pieces.clear()
	_broken_states.clear()
	_piece_quads_cache.clear()
	_fx_accum = 0.0
	_warning_time = 0.0
	# 编辑器需要看到整条轨道且自带缩放平移，关闭裁剪；游戏内启用分块裁剪。
	_cull_enabled = not edit_mode
	_has_last_view_rect = false
	_build_chunks()
	# 裁剪模式需要每帧更新块可见性，因此保持帧处理开启。
	set_process(_cull_enabled)
	queue_redraw()
	_refresh_fx_layers()


## 以 piece 为原子单位把整条轨道打包成若干块，为每块建一个独立 CanvasItem。
## 块内 piece 累计弧长超过 CHUNK_TARGET_LENGTH 就另起一块，断缝边界与块边界天然对齐。
func _build_chunks() -> void:
	_clear_chunks()
	if _track == null or _track.points.size() < 2 or not _cull_enabled:
		return
	var piece_count := _track.piece_ranges.size()
	if piece_count == 0:
		return
	var current_pieces: Array = []
	var current_start_s := -1.0
	var current_end_s := 0.0
	for index in piece_count:
		var range_data: Dictionary = _track.piece_ranges[index]
		var piece_index := int(range_data.get("index", index))
		var p_start := float(range_data.get("start_s", 0.0))
		var p_end := float(range_data.get("end_s", 0.0))
		if current_pieces.is_empty():
			current_start_s = p_start
			current_end_s = p_end
		current_pieces.append(piece_index)
		# 累计弧长超过目标就封块；current_end_s 先更新为本 piece 末尾。
		current_end_s = p_end
		if current_end_s - current_start_s >= CHUNK_TARGET_LENGTH or index == piece_count - 1:
			_commit_chunk(current_pieces, current_start_s, current_end_s)
			current_pieces = []
			current_start_s = -1.0


func _commit_chunk(pieces: Array, start_s: float, end_s: float) -> void:
	if pieces.is_empty():
		return
	var chunk := TrackChunk.new()
	var chunk_index := _chunks.size()
	chunk.name = "Chunk%d" % chunk_index
	chunk.target = self
	chunk.chunk_index = chunk_index
	chunk.start_s = start_s
	chunk.end_s = end_s
	# 计算该块的世界包围盒：遍历块内每个 piece 采样点的 min/max，外扩余量。
	var rect := _compute_chunk_rect(pieces)
	add_child(chunk)
	_chunks.append(chunk)
	_chunk_pieces.append(pieces)
	_chunk_rects.append(rect)
	for piece_index in pieces:
		_piece_chunk[int(piece_index)] = chunk_index


## 块包围盒：按 piece 采样点求 min/max 再加余量。用原始控制点足够（轨道是平滑折线）。
func _compute_chunk_rect(pieces: Array) -> Rect2:
	var min_v := Vector2(INF, INF)
	var max_v := Vector2(-INF, -INF)
	var any := false
	for piece_index in pieces:
		var range_data := _track.get_piece_range(int(piece_index))
		if range_data.is_empty():
			continue
		var start_index := clampi(int(range_data.get("start_index", 0)), 0, _track.points.size() - 1)
		var end_index := clampi(int(range_data.get("end_index", _track.points.size() - 1)), 0, _track.points.size() - 1)
		for pi in range(start_index, end_index + 1):
			var pt: Vector2 = _track.points[pi]
			min_v.x = minf(min_v.x, pt.x)
			min_v.y = minf(min_v.y, pt.y)
			max_v.x = maxf(max_v.x, pt.x)
			max_v.y = maxf(max_v.y, pt.y)
			any = true
	if not any:
		return Rect2()
	return Rect2(
		min_v - Vector2(CHUNK_AABB_MARGIN, CHUNK_AABB_MARGIN),
		(max_v - min_v) + Vector2(CHUNK_AABB_MARGIN * 2.0, CHUNK_AABB_MARGIN * 2.0)
	)


func _clear_chunks() -> void:
	for chunk in _chunks:
		if is_instance_valid(chunk):
			chunk.queue_free()
	_chunks.clear()
	_chunk_pieces.clear()
	_chunk_rects.clear()
	_piece_chunk.clear()


## 每帧按视口可见性切换块的 visible；不可见的块整段跳过命令提交。
func _update_chunk_visibility() -> void:
	if not _cull_enabled or _chunks.is_empty():
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var camera := viewport.get_camera_2d()
	if camera == null:
		# 没有相机（例如静态预览）时全部显示，避免误隐藏。
		for chunk in _chunks:
			if is_instance_valid(chunk):
				chunk.visible = true
		return
	var view_rect := _camera_world_rect(camera)
	if _has_last_view_rect and view_rect == _last_view_rect:
		return
	_last_view_rect = view_rect
	_has_last_view_rect = true
	for index in _chunks.size():
		var chunk := _chunks[index]
		if not is_instance_valid(chunk):
			continue
		if index < _chunk_rects.size():
			chunk.visible = view_rect.intersects(_chunk_rects[index])


func _camera_world_rect(camera: Camera2D) -> Rect2:
	var viewport_size := get_viewport_rect().size
	var zoom := camera.zoom
	var half := viewport_size * 0.5
	if zoom.x != 0.0:
		half.x /= zoom.x
	if zoom.y != 0.0:
		half.y /= zoom.y
	return Rect2(camera.global_position - half, half * 2.0)


func _refresh_fx_layers() -> void:
	if _warning_layer != null:
		_warning_layer.queue_redraw()
	if _fall_layer != null:
		_fall_layer.queue_redraw()


## 定时断轨进入预警：轨道轻微抖动。
func set_warning(piece_index: int, enabled: bool) -> void:
	if enabled:
		_warning_pieces[piece_index] = true
		set_process(true)
	else:
		_warning_pieces.erase(piece_index)
	# 静态层需要把该片段让给预警层（或收回）。
	_redraw_static_for_piece(piece_index)
	_refresh_fx_layers()


## 断裂后片段下落并淡出，而不是立即消失。
func notify_piece_broken(piece_index: int) -> void:
	_broken_states[piece_index] = {"offset": 0.0, "alpha": 1.0, "elapsed": 0.0}
	set_process(true)
	# 静态层不再绘制该片段；下落由 FallLayer 负责。
	_redraw_static_for_piece(piece_index)
	_refresh_fx_layers()


## 重绘承载该 piece 的静态轨道内容。
## 非裁剪模式下整条轨道画在渲染器自身，直接 queue_redraw；
## 裁剪模式下轨道分散在各 Chunk，必须重绘所属 Chunk，否则画面不会变化。
func _redraw_static_for_piece(piece_index: int) -> void:
	if not _cull_enabled or _chunks.is_empty():
		queue_redraw()
		return
	var chunk_index := int(_piece_chunk.get(piece_index, -1))
	if chunk_index >= 0 and chunk_index < _chunks.size():
		var chunk := _chunks[chunk_index]
		if is_instance_valid(chunk):
			chunk.queue_redraw()
			return
	# 找不到所属块时兜底重绘全部，宁多勿漏。
	queue_redraw()
	for chunk in _chunks:
		if is_instance_valid(chunk):
			chunk.queue_redraw()


func _process(delta: float) -> void:
	# 分块可见性每帧跟随相机更新；这是裁剪模式下本节点唯一需要常开 _process 的原因。
	if _cull_enabled:
		_update_chunk_visibility()
	_warning_time += delta
	# 预警抖动改为平移整个预警层，不再每帧按片段重新采样/重绘轨道。
	if not _warning_pieces.is_empty() and _warning_layer != null:
		_warning_layer.position = _warning_offset(0.0, 0)
	for index in _broken_states.keys():
		var state: Dictionary = _broken_states[index]
		state["elapsed"] = float(state.get("elapsed", 0.0)) + delta
		state["offset"] = float(state.get("offset", 0.0)) + 180.0 * delta
		state["alpha"] = maxf(0.0, 1.0 - float(state.get("elapsed", 0.0)) / 2.2)
		_broken_states[index] = state
		if float(state["alpha"]) <= 0.0:
			_broken_states.erase(index)
	if _broken_states.is_empty():
		if _warning_pieces.is_empty():
			# 裁剪模式必须保持帧处理常开，否则相机移动后块的可见性不再更新。
			if not _cull_enabled:
				set_process(false)
			_fx_accum = 0.0
			if _warning_layer != null:
				_warning_layer.position = Vector2.ZERO
		return
	_fx_accum += delta
	if _fx_accum < 1.0 / 30.0:
		return
	_fx_accum = 0.0
	if _fall_layer != null:
		_fall_layer.queue_redraw()


func _draw() -> void:
	if _track == null or _track.points.size() < 2:
		return
	# 选中轨道片段高亮。
	if _edit_mode and _selected_piece >= 0:
		var range_data := _track.get_piece_range(_selected_piece)
		if not range_data.is_empty():
			var points := _slice_points(float(range_data.get("start_s", 0.0)), float(range_data.get("end_s", 0.0)))
			if points.size() >= 2:
				draw_polyline(points, Color(_accent, 0.22), 26.0, true)

	# 轨道底梁、两条钢轨；逐片段绘制，避免把断缝连成一条轨道。
	# 启用分块裁剪时，轨道本体由各 Chunk 自行绘制，这里只剩起点/终点等少量装饰，
	# 自身 CanvasItem 的命令量因此从「整条轨道」降到几十条。
	if not _cull_enabled:
		var assets := VisualRegistry.get_assets()
		var all_pieces: Array = []
		for index in _track.piece_ranges.size():
			all_pieces.append(int((_track.piece_ranges[index] as Dictionary).get("index", index)))
		_draw_pieces_on(self, all_pieces, assets)

	_draw_station()
	_draw_finish()
	if _edit_mode:
		_draw_edit_markers()


## 分块绘制入口：只画本块包含的 piece。由 TrackChunk._draw() 回调。
func draw_chunk(layer: CanvasItem, chunk_index: int) -> void:
	if _track == null or _track.points.size() < 2:
		return
	if chunk_index < 0 or chunk_index >= _chunk_pieces.size():
		return
	_draw_pieces_on(layer, _chunk_pieces[chunk_index], VisualRegistry.get_assets())


## 在指定 CanvasItem 上绘制一组 piece；纹理与 fallback 两条路径在此统一分流。
## 编辑器整轨与游戏内分块共用本函数，确保两种路径的画面完全一致。
func _draw_pieces_on(target: CanvasItem, pieces: Array, assets: VisualAssets) -> void:
	if assets != null and assets.track_texture != null:
		target.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		target.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		for entry in pieces:
			var piece_index := int(entry)
			if _track.is_piece_broken(piece_index):
				continue
			# 预警片段交给 WarningLayer 绘制，静态层不再重复绘制。
			if _warning_pieces.has(piece_index):
				continue
			_draw_piece(target, assets, piece_index, Vector2.ZERO, 1.0, false)
		return
	var ink := _color("track", Color(0.18, 0.29, 0.4))
	var highlight := _color("track_highlight", Color(0.73, 0.84, 0.9))
	var dark_tie := ink.darkened(0.35)
	for entry in pieces:
		var piece_index := int(entry)
		if _track.is_piece_broken(piece_index):
			continue
		if _warning_pieces.has(piece_index):
			continue
		var range_data := _track.get_piece_range(piece_index)
		if range_data.is_empty():
			continue
		var piece_points := _piece_points(range_data)
		if piece_points.size() < 2:
			continue
		target.draw_polyline(piece_points, dark_tie, 13.0, true)
		target.draw_polyline(_offset_points_from(piece_points, 5.0), ink, 4.0, true)
		target.draw_polyline(_offset_points_from(piece_points, -5.0), ink, 4.0, true)
		target.draw_polyline(_offset_points_from(piece_points, 5.0), highlight, 1.4, true)
		target.draw_polyline(_offset_points_from(piece_points, -5.0), highlight, 1.4, true)

		var start_s := float(range_data.get("start_s", 0.0))
		var end_s := float(range_data.get("end_s", 0.0))
		var tie_s := start_s
		while tie_s <= end_s:
			var p := _track.sample_at(tie_s)
			var n := _track.normal_at(tie_s)
			target.draw_line(p + n * -9.0, p + n * 9.0, highlight.darkened(0.2), 2.0, true)
			tie_s += 26.0

		var arrow_s := start_s + 60.0
		while arrow_s < end_s - 40.0:
			var arrow_p := _track.sample_at(arrow_s)
			var tangent := _track.tangent_at(arrow_s)
			var normal := _track.normal_at(arrow_s)
			var arrow := PackedVector2Array([
				arrow_p + tangent * 7.0,
				arrow_p - tangent * 5.0 + normal * 5.0,
				arrow_p - tangent * 5.0 - normal * 5.0,
			])
			target.draw_colored_polygon(arrow, Color(1, 1, 1, 0.24))
			arrow_s += 320.0


## 预警抖动：整段轨道做同一个轻微平移，避免沿弧长形成波浪。
func _warning_offset(_s: float, _piece_index: int) -> Vector2:
	# 低频、整层统一的轻微抖动；多个断口共用一个偏移，避免相位混乱。
	return Vector2(
		sin(_warning_time * 14.0) * 1.8,
		cos(_warning_time * 17.0) * 1.3
	)


## 动态层入口：kind 0=预警，1=断裂下落。
func draw_fx(layer: CanvasItem, kind: int) -> void:
	if _track == null or _track.points.size() < 2:
		return
	var assets := VisualRegistry.get_assets()
	if kind == 0:
		for piece_index in _warning_pieces.keys():
			if _track.is_piece_broken(int(piece_index)):
				continue
			_draw_piece(layer, assets, int(piece_index), Vector2.ZERO, 1.0, false)
	else:
		for piece_index in _broken_states.keys():
			var state: Dictionary = _broken_states[piece_index]
			var alpha := float(state.get("alpha", 0.0))
			if alpha <= 0.01:
				continue
			var drop := Vector2(0, float(state.get("offset", 0.0)))
			_draw_piece(layer, assets, int(piece_index), drop, alpha, false)





## 绘制单个片段；有轨道贴图时用与正常轨道相同的宽度，断裂下落也保持同宽。
func _draw_piece(target: CanvasItem, assets: VisualAssets, piece_index: int, drop: Vector2, alpha: float, jitter: bool) -> void:
	var range_data := _track.get_piece_range(piece_index)
	if range_data.is_empty():
		return
	if assets != null and assets.track_texture != null:
		_draw_piece_texture(target, assets, piece_index, drop, alpha, jitter)
	else:
		_draw_piece_fallback(target, piece_index, drop, alpha, jitter)


## 缓存断裂/静态片段的四边形，避免下落层每帧重新采样整段轨道。
func _get_piece_quads(piece_index: int) -> Array:
	if _piece_quads_cache.has(piece_index):
		return _piece_quads_cache[piece_index]
	var range_data := _track.get_piece_range(piece_index)
	var quads: Array = []
	if range_data.is_empty():
		_piece_quads_cache[piece_index] = quads
		return quads
	var start_s := float(range_data.get("start_s", 0.0))
	var end_s := float(range_data.get("end_s", 0.0))
	var assets := VisualRegistry.get_assets()
	if assets == null or assets.track_texture == null or end_s <= start_s:
		_piece_quads_cache[piece_index] = quads
		return quads
	var width_scale := 1.0 if _edit_mode else assets.track_width_scale
	var half_height := maxf(4.0, assets.track_texture_height * width_scale) * 0.5
	var tile_width := maxf(1.0, assets.track_texture_width)
	var step := 18.0
	var s := start_s
	while s < end_s - 0.01:
		var s1 := minf(end_s, s + step)
		var c0 := _track.sample_at(s)
		var c1 := _track.sample_at(s1)
		var n0 := _track.normal_at(s)
		var n1 := _track.normal_at(s1)
		var a0 := c0 + n0 * half_height
		var b0 := c0 - n0 * half_height
		var a1 := c1 + n1 * half_height
		var b1 := c1 - n1 * half_height
		if _is_drawable_quad(a0, a1, b1, b0):
			quads.append({
				"a0": a0, "a1": a1, "b1": b1, "b0": b0,
				"uvs": PackedVector2Array([
					Vector2(s / tile_width, 0), Vector2(s1 / tile_width, 0),
					Vector2(s1 / tile_width, 1), Vector2(s / tile_width, 1),
				]),
			})
		s = s1
	_piece_quads_cache[piece_index] = quads
	return quads


func _draw_piece_texture(target: CanvasItem, assets: VisualAssets, piece_index: int, drop: Vector2, alpha: float, jitter: bool) -> void:
	var range_data := _track.get_piece_range(piece_index)
	var start_s := float(range_data.get("start_s", 0.0))
	var end_s := float(range_data.get("end_s", 0.0))
	if end_s <= start_s:
		return
	if not jitter:
		var track_color := Color(assets.track_brightness, assets.track_brightness, assets.track_brightness, alpha)
		var colors := PackedColorArray([track_color, track_color, track_color, track_color])
		for quad in _get_piece_quads(piece_index):
			var points := PackedVector2Array([
				quad["a0"] + drop, quad["a1"] + drop, quad["b1"] + drop, quad["b0"] + drop
			])
			target.draw_polygon(points, colors, quad["uvs"], assets.track_texture)
		return
	var width_scale := 1.0 if _edit_mode else assets.track_width_scale
	var height := maxf(4.0, assets.track_texture_height * width_scale)
	var half_height := height * 0.5
	var step := 14.0
	var tile_width := maxf(1.0, assets.track_texture_width)
	var s := start_s
	while s < end_s - 0.01:
		var s1 := minf(end_s, s + step)
		var c0 := _track.sample_at(s) + drop
		var c1 := _track.sample_at(s1) + drop
		var n0 := _track.normal_at(s)
		var n1 := _track.normal_at(s1)
		if jitter:
			c0 += _warning_offset(s, piece_index)
			c1 += _warning_offset(s1, piece_index)
		var a0 := c0 + n0 * half_height
		var b0 := c0 - n0 * half_height
		var a1 := c1 + n1 * half_height
		var b1 := c1 - n1 * half_height
		var points := PackedVector2Array([a0, a1, b1, b0])
		var u0 := s / tile_width
		var u1 := s1 / tile_width
		var uvs := PackedVector2Array([
			Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, 1), Vector2(u0, 1)
		])
		var track_color := Color(assets.track_brightness, assets.track_brightness, assets.track_brightness, alpha)
		var colors := PackedColorArray([track_color, track_color, track_color, track_color])
		if _is_drawable_quad(a0, a1, b1, b0):
			target.draw_polygon(points, colors, uvs, assets.track_texture)
		else:
			target.draw_line(c0, c1, Color(0.66, 0.76, 0.82, 0.8 * alpha), maxf(3.0, height * 0.65), true)
		s = s1


func _draw_piece_fallback(target: CanvasItem, piece_index: int, drop: Vector2, alpha: float, jitter: bool) -> void:
	var range_data := _track.get_piece_range(piece_index)
	if range_data.is_empty():
		return
	var points := _piece_points(range_data)
	if points.size() < 2:
		return
	if drop != Vector2.ZERO or jitter:
		var shifted := PackedVector2Array()
		for index in points.size():
			var p := points[index] + drop
			if jitter:
				p += _warning_offset(float(index), piece_index)
			shifted.append(p)
		points = shifted
	var ink := _color("track", Color(0.18, 0.29, 0.4))
	var highlight := _color("track_highlight", Color(0.73, 0.84, 0.9))
	target.draw_polyline(points, Color(ink.darkened(0.35), alpha), 13.0, true)
	target.draw_polyline(_offset_points_from(points, 5.0), Color(ink, alpha), 4.0, true)
	target.draw_polyline(_offset_points_from(points, -5.0), Color(ink, alpha), 4.0, true)
	target.draw_polyline(_offset_points_from(points, 5.0), Color(highlight, alpha * 0.55), 1.4, true)
	target.draw_polyline(_offset_points_from(points, -5.0), Color(highlight, alpha * 0.55), 1.4, true)


## 返回纹理“外侧”相对法线的符号：+1 为右法线方向，-1 为左法线方向。
## 直线没有曲率时沿用传统“白色在上”，曲线用三点外接圆判断真正的外侧。
func _is_drawable_quad(a0: Vector2, a1: Vector2, b1: Vector2, b0: Vector2) -> bool:
	var area := 0.0
	var pts := [a0, a1, b1, b0]
	for index in 4:
		var p: Vector2 = pts[index]
		var q: Vector2 = pts[(index + 1) % 4]
		area += p.x * q.y - q.x * p.y
	if absf(area) < 6.0:
		return false
	if a0.distance_squared_to(a1) < 0.01 or b0.distance_squared_to(b1) < 0.01:
		return false
	if Geometry2D.segment_intersects_segment(a0, a1, b0, b1):
		return false
	var points := PackedVector2Array([a0, a1, b1, b0])
	return not Geometry2D.triangulate_polygon(points).is_empty()


func _draw_station() -> void:
	var start_point := _track.sample_at(_start_s)
	var tangent := _track.tangent_at(_start_s)
	var angle := tangent.angle()
	var ink := _color("track", Color(0.18, 0.29, 0.4))
	# 起点站台纹理由 StartGate 场景的 Sprite2D 绘制；这里保留程序化站台兜底。
	var station_assets := VisualRegistry.get_assets()
	if station_assets != null and station_assets.start_gate_texture != null:
		return
	draw_set_transform(start_point, angle)
	var roof := PackedVector2Array([
		Vector2(-76, -66),
		Vector2(-50, -90),
		Vector2(52, -90),
		Vector2(70, -66),
	])
	draw_colored_polygon(roof, _accent)
	draw_polyline(PackedVector2Array([roof[0], roof[1], roof[2], roof[3], roof[0]]), ink, 3.0, true)
	draw_line(Vector2(-62, -66), Vector2(-62, 18), ink, 4.0, true)
	draw_line(Vector2(58, -66), Vector2(58, 18), ink, 4.0, true)
	draw_rect(Rect2(-78, 12, 146, 16), Color(0.97, 0.84, 0.55))
	draw_rect(Rect2(-78, 12, 146, 16), ink, false, 2.5)
	draw_string(ThemeDB.fallback_font, Vector2(-33, -8), "起点", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, ink)
	draw_set_transform(Vector2.ZERO, 0.0)


func _draw_finish() -> void:
	var finish_point := _track.sample_at(_finish_s)
	var normal := _track.normal_at(_finish_s)
	var tangent := _track.tangent_at(_finish_s)
	var ink := _color("track", Color(0.18, 0.29, 0.4))
	# 终点牌纹理由 FinishGate 场景的 Sprite2D 绘制；这里保留程序化终点线兜底。
	var finish_assets := VisualRegistry.get_assets()
	if finish_assets != null and finish_assets.finish_gate_texture != null:
		return
	# 跨轨终点线。
	draw_line(finish_point - normal * 44.0, finish_point + normal * 44.0, _accent, 6.0, true)
	for index in 7:
		var side := -44.0 + index * 12.5
		var color := Color(0.1, 0.16, 0.22) if index % 2 == 0 else Color(1, 1, 1)
		draw_line(finish_point + normal * side, finish_point + normal * (side + 12.5), color, 4.0, true)
	# 终点牌。
	var sign_center := finish_point + tangent * 10.0 + Vector2(0, -106)
	var sign_rect := Rect2(sign_center - Vector2(64, 24), Vector2(128, 48))
	draw_rect(sign_rect, _accent)
	draw_rect(sign_rect, ink, false, 3.0)
	draw_string(ThemeDB.fallback_font, sign_center + Vector2(-33, 8), "终点", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, ink)
	draw_line(finish_point + Vector2(0, -74), sign_center, ink, 3.0, true)


func _draw_edit_markers() -> void:
	var start_point := _track.sample_at(_start_s)
	var finish_point := _track.sample_at(_finish_s)
	draw_circle(start_point, 13.0, Color(0.31, 0.85, 0.53))
	draw_arc(start_point, 13.0, 0, TAU, 24, Color(0.06, 0.16, 0.2), 2.5, true)
	draw_string(ThemeDB.fallback_font, start_point + Vector2(-12, -20), "起点", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	draw_circle(finish_point, 13.0, _accent)
	draw_arc(finish_point, 13.0, 0, TAU, 24, Color(0.06, 0.16, 0.2), 2.5, true)
	draw_string(ThemeDB.fallback_font, finish_point + Vector2(-12, -20), "终点", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)


func _piece_points(range_data: Dictionary) -> PackedVector2Array:
	var result := PackedVector2Array()
	var start_index := clampi(int(range_data.get("start_index", 0)), 0, _track.points.size() - 1)
	var end_index := clampi(int(range_data.get("end_index", _track.points.size() - 1)), 0, _track.points.size() - 1)
	for index in range(start_index, end_index + 1):
		result.append(_track.points[index])
	return result


func _offset_points_from(points: PackedVector2Array, offset: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for index in points.size():
		var normal: Vector2
		if index == 0:
			var direction := points[1] - points[0]
			normal = Vector2(-direction.y, direction.x).normalized()
		elif index == points.size() - 1:
			var direction := points[index] - points[index - 1]
			normal = Vector2(-direction.y, direction.x).normalized()
		else:
			var direction := (points[index + 1] - points[index - 1]).normalized()
			normal = Vector2(-direction.y, direction.x)
		result.append(points[index] + normal * offset)
	return result


func _slice_points(from_s: float, to_s: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	var s := clampf(from_s, 0.0, _track.total_length)
	var end_s := clampf(to_s, 0.0, _track.total_length)
	var step := maxf(8.0, (end_s - s) / 120.0)
	while s <= end_s:
		result.append(_track.sample_at(s))
		s += step
	if result.is_empty() or result[result.size() - 1].distance_to(_track.sample_at(end_s)) > 1.0:
		result.append(_track.sample_at(end_s))
	return result


func _color(key: String, fallback: Color) -> Color:
	var raw := str(_theme.get(key, ""))
	return Color.from_string(raw, fallback) if not raw.is_empty() else fallback
