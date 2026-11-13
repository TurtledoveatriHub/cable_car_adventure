class_name TrackGeometry
extends RefCounted
## 单轨过山车的轨道几何。
## 关卡由若干“轨道片段”顺序拼接：
##   straight: 直线
##   arc:      圆弧（角度可正可负，正数为屏幕坐标下的顺时针）
##   loop:     完整环圈（本质是 ±360° 圆弧）
## 本类负责采样、弧长、切线、最近点与包围盒；不处理碰撞、输入或文件。

const MAX_STEP := 14.0
const MAX_PIECES := 300
const MAX_TOTAL_LENGTH := 120000.0

var start_angle_deg: float = 0.0
var pieces: Array[Dictionary] = []
var points: PackedVector2Array = PackedVector2Array()
var cumulative: PackedFloat32Array = PackedFloat32Array()
var total_length: float = 0.0
var piece_ranges: Array[Dictionary] = []
var piece_start_headings: Array[float] = []
var piece_end_headings: Array[float] = []
var seams: Array[Dictionary] = []
var gap_segments: Array[int] = []
var broken_pieces: Array[int] = []
## 每个轨道片段自己的前进方向：+1=向右（默认），-1=向左。
var piece_directions: PackedFloat32Array = PackedFloat32Array()
## 每个折线段所属的片段下标；空档连接线为 -1。
var segment_pieces: PackedInt32Array = PackedInt32Array()
var error_message: String = ""

# ---- 内部加速索引（只读缓存，语义与上面的公开字段完全一致）----
# 公开数组保持原样以便调试与外部读取；这些位图/数组只用于把 O(n) 线性扫描降为 O(1)/O(log n)。
## gap_segments 的位图：下标 = 折线段序号，1 = 该段是空档连接线。
var _gap_mask: PackedByteArray = PackedByteArray()
## broken_pieces 的位图：下标 = 片段序号，1 = 该片段已断裂。
var _broken_mask: PackedByteArray = PackedByteArray()
## piece_ranges 里每片段的 end_s，升序，供 piece_index_at_s 二分查找。
var _piece_end_s: PackedFloat32Array = PackedFloat32Array()
## piece_ranges 里每片段的 start_s，与 _piece_end_s 同序。
var _piece_start_s: PackedFloat32Array = PackedFloat32Array()
## get_track_runs() 的缓存；_runs_cache_valid=false 时下次调用重建。
var _runs_cache: Array[Dictionary] = []
var _runs_cache_valid: bool = false


static func from_track_data(track_data: Dictionary) -> TrackGeometry:
	var track := TrackGeometry.new()
	track.start_angle_deg = float(track_data.get("start_angle_deg", 0.0))
	var raw_pieces: Variant = track_data.get("pieces", [])
	if raw_pieces is Array:
		for item: Variant in raw_pieces:
			if item is Dictionary:
				track.pieces.append((item as Dictionary).duplicate(true))
	track.build()
	return track


## 根据 pieces 生成折线采样、累计弧长与包围盒。
func build() -> void:
	points = PackedVector2Array()
	cumulative = PackedFloat32Array()
	piece_ranges.clear()
	piece_start_headings.clear()
	piece_end_headings.clear()
	seams.clear()
	gap_segments.clear()
	broken_pieces.clear()
	segment_pieces = PackedInt32Array()
	_gap_mask = PackedByteArray()
	_broken_mask = PackedByteArray()
	_piece_start_s = PackedFloat32Array()
	_piece_end_s = PackedFloat32Array()
	_runs_cache_valid = false
	error_message = ""
	total_length = 0.0

	if pieces.is_empty():
		error_message = "轨道至少需要一个片段"
		return
	if pieces.size() > MAX_PIECES:
		error_message = "轨道片段过多（上限 %d）" % MAX_PIECES
		return

	piece_directions.resize(pieces.size())
	for index in pieces.size():
		var piece_data: Dictionary = pieces[index]
		piece_directions[index] = 1.0 if float(piece_data.get("direction", 1.0)) >= 0.0 else -1.0

	var heading := deg_to_rad(start_angle_deg)
	var current := Vector2.ZERO
	var piece_start_index := 0

	for index in pieces.size():
		var piece: Dictionary = pieces[index]
		var piece_start_heading := heading
		var type := str(piece.get("type", "straight"))
		var origin_value: Variant = piece.get("origin", null)
		if origin_value != null:
			var origin := _parse_point(origin_value)
			var origin_heading := deg_to_rad(float(piece.get("heading_deg", 0.0)))
			if points.is_empty():
				_append_unique(origin)
			else:
				var from_point := points[points.size() - 1]
				var gap_distance := from_point.distance_to(origin)
				if gap_distance > 0.01:
					var gap_start_s := cumulative[cumulative.size() - 1]
					var angle_diff := absf(wrapf(origin_heading - heading, -PI, PI))
					_append_unique(origin)
					gap_segments.append(points.size() - 2)
					seams.append({
						"piece": index,
						"start_s": gap_start_s,
						"end_s": cumulative[cumulative.size() - 1],
						"from": from_point,
						"to": origin,
						"distance": gap_distance,
						"angle_diff": angle_diff,
					})
			piece_start_index = points.size() - 1
			current = points[points.size() - 1]
			heading = origin_heading
			piece_start_heading = heading
		elif points.is_empty():
			_append_unique(Vector2.ZERO)
			piece_start_index = 0

		if type == "loop":
			var loop_radius := maxf(4.0, float(piece.get("radius", 90.0)))
			var loop_angle := float(piece.get("angle", -360.0))
			current = _append_arc(current, heading, loop_radius, deg_to_rad(loop_angle), index)
			heading += deg_to_rad(loop_angle)
		elif type == "arc" or type == "curve":
			var radius := maxf(4.0, float(piece.get("radius", 120.0)))
			var angle_deg := float(piece.get("angle", -90.0))
			if absf(angle_deg) < 0.01:
				angle_deg = -90.0
			current = _append_arc(current, heading, radius, deg_to_rad(angle_deg), index)
			heading += deg_to_rad(angle_deg)
		else:
			var length := maxf(0.0, float(piece.get("length", 240.0)))
			current = _append_straight(current, heading, length, index)
		piece_start_headings.append(piece_start_heading)
		piece_end_headings.append(heading)
		piece_ranges.append({
			"index": index,
			"start_index": piece_start_index,
			"end_index": points.size() - 1,
			"start_s": cumulative[piece_start_index] if piece_start_index < cumulative.size() else 0.0,
			"end_s": cumulative[cumulative.size() - 1] if not cumulative.is_empty() else 0.0,
		})
		piece_start_index = points.size() - 1

	_rebuild_cumulative()
	_rebuild_segment_pieces()
	_rebuild_indices()
	if total_length > MAX_TOTAL_LENGTH:
		error_message = "轨道总长度超过上限（%.0f px）" % MAX_TOTAL_LENGTH
	if points.size() < 2:
		error_message = error_message if not error_message.is_empty() else "轨道没有有效长度"


func is_valid() -> bool:
	return error_message.is_empty() and points.size() >= 2 and total_length > 0.0


## 该 run 的起点外侧是否有空档（即可以从起点反向飞出）。
func run_has_gap_at_start(run_index: int) -> bool:
	var runs := get_track_runs()
	if run_index < 0 or run_index >= runs.size():
		return false
	var start_s := float(runs[run_index].get("start_s", 0.0))
	for seam in seams:
		if absf(float(seam.get("end_s", -1.0)) - start_s) < 0.01:
			return true
	return false


## 该 run 的终点外侧是否有空档（即可以从终点正向飞出）。
func run_has_gap_at_end(run_index: int) -> bool:
	var runs := get_track_runs()
	if run_index < 0 or run_index >= runs.size():
		return false
	var end_s := float(runs[run_index].get("end_s", 0.0))
	for seam in seams:
		if absf(float(seam.get("start_s", -1.0)) - end_s) < 0.01:
			return true
	return false


## 最近的可落轨弧长（跳过空档连接线与已断裂片段）。
func nearest_rail_s(world_point: Vector2) -> float:
	if points.size() < 2:
		return 0.0
	var best_distance := INF
	var best_s := 0.0
	for index in range(points.size() - 1):
		if index < _gap_mask.size() and _gap_mask[index] != 0:
			continue
		var piece_index := segment_pieces[index] if index < segment_pieces.size() else -1
		if piece_index >= 0 and is_piece_broken(piece_index):
			continue
		var a := points[index]
		var b := points[index + 1]
		var segment := b - a
		var length_squared := segment.length_squared()
		if length_squared < 0.0001:
			continue
		var t := clampf((world_point - a).dot(segment) / length_squared, 0.0, 1.0)
		var closest := a + segment * t
		var distance := world_point.distance_squared_to(closest)
		if distance < best_distance:
			best_distance = distance
			best_s = cumulative[index] + sqrt(length_squared) * t
	return best_s


func piece_index_at_s(s: float) -> int:
	var piece_count := piece_ranges.size()
	if piece_count == 0:
		return 0
	var distance := clampf(s, 0.0, total_length)
	# 预计算区间数组可用时走二分：找第一个 end_s >= distance 的片段。
	if _piece_end_s.size() == piece_count and _piece_start_s.size() == piece_count:
		var lo := 0
		var hi := piece_count - 1
		while lo < hi:
			var mid := (lo + hi) >> 1
			if _piece_end_s[mid] < distance:
				lo = mid + 1
			else:
				hi = mid
		# lo 是第一个 end_s >= distance 的片段；distance 也 >= 其 start_s 才算真正落在该片段内。
		# 否则 distance 落在 lo 前方的空档里（无片段覆盖），与原实现一致返回最后一个片段。
		if distance >= _piece_start_s[lo]:
			return lo
		return piece_count - 1
	# 索引尚未建立时回退到原线性扫描（语义完全一致）。
	for index in piece_count:
		var range_data: Dictionary = piece_ranges[index]
		if distance >= float(range_data.get("start_s", 0.0)) and distance <= float(range_data.get("end_s", 0.0)):
			return index
	return clampi(piece_count - 1, 0, maxi(0, piece_count - 1))


func break_piece(index: int) -> void:
	if index < 0 or index >= pieces.size():
		return
	if not broken_pieces.has(index):
		broken_pieces.append(index)
	if index < _broken_mask.size():
		_broken_mask[index] = 1


func is_piece_broken(index: int) -> bool:
	if index < 0 or index >= _broken_mask.size():
		return false
	return _broken_mask[index] != 0


func reset_breaks() -> void:
	broken_pieces.clear()
	_broken_mask.fill(0)


func _parse_point(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	if value is Dictionary:
		return Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0)))
	return Vector2.ZERO


func _append_straight(start: Vector2, heading: float, length: float, _piece_index: int) -> Vector2:
	if length <= 0.001:
		return start
	var step_count := clampi(int(ceil(length / MAX_STEP)), 1, 600)
	for step in range(1, step_count + 1):
		var distance := length * float(step) / float(step_count)
		var point := start + Vector2(cos(heading), sin(heading)) * distance
		_append_unique(point)
	_update_running_length()
	return points[points.size() - 1]


func _append_arc(start: Vector2, start_heading: float, radius: float, angle_rad: float, _piece_index: int) -> Vector2:
	if absf(angle_rad) < 0.0001:
		return start
	var sign_value := 1.0 if angle_rad > 0.0 else -1.0
	var normal := Vector2(-sin(start_heading), cos(start_heading))
	var center := start + normal * radius * sign_value
	var start_vector := start - center
	var arc_length := absf(angle_rad) * radius
	var step_count := clampi(int(ceil(arc_length / 12.0)), 6, 360)
	for step in range(1, step_count + 1):
		var t := float(step) / float(step_count)
		var point := center + start_vector.rotated(angle_rad * t)
		_append_unique(point)
	_update_running_length()
	return points[points.size() - 1]


func _append_unique(point: Vector2) -> void:
	if points.is_empty():
		points.append(point)
		cumulative.append(0.0)
		return
	var last := points[points.size() - 1]
	var distance := last.distance_to(point)
	if distance <= 0.0001:
		return
	points.append(point)
	cumulative.append((cumulative[cumulative.size() - 1] if not cumulative.is_empty() else 0.0) + distance)


func _update_running_length() -> void:
	if points.is_empty():
		return
	if cumulative.size() != points.size():
		cumulative.resize(points.size())
		cumulative[0] = 0.0
	for index in range(1, points.size()):
		cumulative[index] = cumulative[index - 1] + points[index].distance_to(points[index - 1])
	total_length = cumulative[cumulative.size() - 1]


func _rebuild_cumulative() -> void:
	cumulative.resize(points.size())
	if points.is_empty():
		total_length = 0.0
		return
	cumulative[0] = 0.0
	for index in range(1, points.size()):
		cumulative[index] = cumulative[index - 1] + points[index].distance_to(points[index - 1])
	total_length = cumulative[cumulative.size() - 1]
	for index in piece_ranges.size():
		var range_data: Dictionary = piece_ranges[index]
		var start_index := int(range_data.get("start_index", 0))
		var end_index := int(range_data.get("end_index", points.size() - 1))
		range_data["start_s"] = cumulative[clampi(start_index, 0, cumulative.size() - 1)]
		range_data["end_s"] = cumulative[clampi(end_index, 0, cumulative.size() - 1)]
		piece_ranges[index] = range_data


## 建立“折线段 -> 片段”的映射：空档连接线不属于任何片段。
func _rebuild_segment_pieces() -> void:
	segment_pieces = PackedInt32Array()
	if points.size() < 2:
		return
	segment_pieces.resize(points.size() - 1)
	segment_pieces.fill(-1)
	for piece_index in piece_ranges.size():
		var range_data: Dictionary = piece_ranges[piece_index]
		var start_index := int(range_data.get("start_index", 0))
		var end_index := int(range_data.get("end_index", points.size() - 1))
		for segment in range(start_index, end_index):
			if segment >= 0 and segment < segment_pieces.size():
				segment_pieces[segment] = piece_index


## 重建内部加速索引：gap 位图、piece 区间数组、broken 位图。
## 只在 build() 末尾调用；公开字段仍是唯一真相来源，索引只是只读副本。
func _rebuild_indices() -> void:
	var segment_count := maxi(0, points.size() - 1)
	_gap_mask = PackedByteArray()
	_gap_mask.resize(segment_count)
	_gap_mask.fill(0)
	for segment_index in gap_segments:
		if segment_index >= 0 and segment_index < segment_count:
			_gap_mask[segment_index] = 1
	var piece_count := piece_ranges.size()
	_piece_start_s = PackedFloat32Array()
	_piece_end_s = PackedFloat32Array()
	_piece_start_s.resize(piece_count)
	_piece_end_s.resize(piece_count)
	for piece_index in piece_count:
		var range_data: Dictionary = piece_ranges[piece_index]
		_piece_start_s[piece_index] = float(range_data.get("start_s", 0.0))
		_piece_end_s[piece_index] = float(range_data.get("end_s", 0.0))
	_rebuild_broken_mask()


## broken 位图与 broken_pieces 数组同步（数组仍是公开真相来源）。
func _rebuild_broken_mask() -> void:
	_broken_mask = PackedByteArray()
	_broken_mask.resize(pieces.size())
	_broken_mask.fill(0)
	for piece_index in broken_pieces:
		if piece_index >= 0 and piece_index < _broken_mask.size():
			_broken_mask[piece_index] = 1


## 按弧长取位置。越界时夹到端点。
func sample_at(s: float) -> Vector2:
	if points.size() < 2:
		return Vector2.ZERO
	var distance := clampf(s, 0.0, total_length)
	var index := _find_segment(distance)
	var seg_len := cumulative[index + 1] - cumulative[index]
	if seg_len <= 0.0001:
		return points[index]
	var t := clampf((distance - cumulative[index]) / seg_len, 0.0, 1.0)
	return points[index].lerp(points[index + 1], t)


## 按弧长取切线（单位向量）。
func tangent_at(s: float) -> Vector2:
	if points.size() < 2:
		return Vector2.RIGHT
	var a := sample_at(clampf(s - 2.0, 0.0, total_length))
	var b := sample_at(clampf(s + 2.0, 0.0, total_length))
	var direction := b - a
	if direction.length_squared() <= 0.000001:
		var index := _find_segment(clampf(s, 0.0, total_length))
		direction = points[index + 1] - points[index]
	return direction.normalized() if direction.length_squared() > 0.000001 else Vector2.RIGHT


## 法线：切线顺时针旋转 90°。
func normal_at(s: float) -> Vector2:
	var tangent := tangent_at(s)
	return Vector2(-tangent.y, tangent.x)


func angle_at(s: float) -> float:
	return tangent_at(s).angle()


func slope_at(s: float) -> float:
	return tangent_at(s).y


func _find_segment(distance: float) -> int:
	if cumulative.size() < 2:
		return 0
	var lo := 0
	var hi := cumulative.size() - 1
	while lo < hi:
		var mid := (lo + hi) >> 1
		if cumulative[mid + 1] < distance:
			lo = mid + 1
		else:
			hi = mid
	return clampi(lo, 0, cumulative.size() - 2)


## 世界坐标最近点对应的弧长（编辑器放置障碍 / 起终点使用）。
func nearest_s(world_point: Vector2) -> float:
	if points.size() < 2:
		return 0.0
	var best_s := 0.0
	var best_distance := INF
	for index in range(points.size() - 1):
		var a := points[index]
		var b := points[index + 1]
		var segment := b - a
		var length_squared := segment.length_squared()
		var t := 0.0
		if length_squared > 0.00001:
			t = clampf((world_point - a).dot(segment) / length_squared, 0.0, 1.0)
		var projected := a.lerp(b, t)
		var distance := projected.distance_squared_to(world_point)
		if distance < best_distance:
			best_distance = distance
			best_s = cumulative[index] + (cumulative[index + 1] - cumulative[index]) * t
	return best_s


func offset_point(s: float, offset: Vector2) -> Vector2:
	return sample_at(s) + offset


func get_bounds(padding: float = 80.0) -> Rect2:
	if points.is_empty():
		return Rect2(-padding, -padding, padding * 2.0, padding * 2.0)
	var rect := Rect2(points[0], Vector2.ZERO)
	for point in points:
		rect = rect.expand(point)
	rect.position -= Vector2(padding, padding)
	rect.size += Vector2(padding * 2.0, padding * 2.0)
	return rect


## 连续轨道段（run）：片段之间没有空档时属于同一段。
## 编辑器只允许在 run 的两个端点吸附，内部片段接缝不允许再链接。
func get_track_runs() -> Array[Dictionary]:
	if _runs_cache_valid:
		return _runs_cache
	var runs: Array[Dictionary] = []
	if piece_ranges.is_empty():
		_runs_cache = runs
		_runs_cache_valid = true
		return runs
	var starts: Array[int] = [0]
	for seam in seams:
		var piece_index := int(seam.get("piece", 0))
		if piece_index > 0 and piece_index < piece_ranges.size():
			starts.append(piece_index)
	for run_index in starts.size():
		var first_piece := starts[run_index]
		var last_piece := (starts[run_index + 1] - 1) if run_index + 1 < starts.size() else piece_ranges.size() - 1
		var first_range: Dictionary = piece_ranges[first_piece]
		var last_range: Dictionary = piece_ranges[last_piece]
		runs.append({
			"first_piece": first_piece,
			"last_piece": last_piece,
			"start_s": float(first_range.get("start_s", 0.0)),
			"end_s": float(last_range.get("end_s", 0.0)),
		})
	# runs 只由 seams 与 piece_ranges 决定，两者都只在 build() 里改动，
	# build() 已将 _runs_cache_valid 置 false，因此缓存不会陈旧。
	_runs_cache = runs
	_runs_cache_valid = true
	return _runs_cache


func is_isolated_piece(piece_index: int) -> bool:
	for run in get_track_runs():
		var first := int(run.get("first_piece", -1))
		var last := int(run.get("last_piece", -2))
		if first == last and first == piece_index:
			return true
	return false


func run_index_for_piece(piece_index: int) -> int:
	var runs := get_track_runs()
	for index in runs.size():
		var run: Dictionary = runs[index]
		var first_piece := int(run.get("first_piece", -1))
		var last_piece := int(run.get("last_piece", -1))
		if piece_index >= first_piece and piece_index <= last_piece:
			return index
	return -1


## 一段连续轨道的“第一段放置轨道”下标；旧关卡没有锚点时回退到段首片段。
func get_run_anchor_piece(run_index: int) -> int:
	var runs := get_track_runs()
	if run_index < 0 or run_index >= runs.size():
		return -1
	var first_piece := int(runs[run_index].get("first_piece", -1))
	var last_piece := int(runs[run_index].get("last_piece", -1))
	for piece_index in range(first_piece, last_piece + 1):
		if piece_index >= 0 and piece_index < pieces.size() and bool(pieces[piece_index].get("direction_anchor", false)):
			return piece_index
	return first_piece


func get_piece_direction(piece_index: int) -> float:
	if piece_index < 0 or piece_index >= piece_directions.size():
		return 1.0
	return piece_directions[piece_index]


## 一段连续轨道（run）的固定前进方向，取“第一段放置轨道”的方向。
func get_run_direction(run_index: int) -> float:
	var anchor_piece := get_run_anchor_piece(run_index)
	return get_piece_direction(anchor_piece)


func get_run_endpoints() -> Array[Dictionary]:
	var endpoints: Array[Dictionary] = []
	for run in get_track_runs():
		var start_s := float(run.get("start_s", 0.0))
		var end_s := float(run.get("end_s", 0.0))
		var last_piece := int(run.get("last_piece", 0))
		var first_piece := int(run.get("first_piece", 0))
		var end_angle := piece_end_headings[clampi(last_piece, 0, piece_end_headings.size() - 1)] if not piece_end_headings.is_empty() else angle_at(end_s)
		endpoints.append({
			"point": sample_at(end_s),
			"angle": end_angle,
			"end": true,
			"s": end_s,
			"piece": int(run.get("last_piece", 0)),
		})
		var start_angle := piece_start_headings[clampi(first_piece, 0, piece_start_headings.size() - 1)] + PI if not piece_start_headings.is_empty() else angle_at(start_s) + PI
		endpoints.append({
			"point": sample_at(start_s),
			"angle": start_angle,
			"end": false,
			"s": start_s,
			"piece": int(run.get("first_piece", 0)),
		})
	return endpoints


func get_piece_range(piece_index: int) -> Dictionary:
	if piece_index < 0 or piece_index >= piece_ranges.size():
		return {}
	return piece_ranges[piece_index].duplicate(true)


func get_piece_start_s(piece_index: int) -> float:
	var range_data := get_piece_range(piece_index)
	return float(range_data.get("start_s", 0.0))


func get_debug_summary() -> Dictionary:
	return {
		"points": points.size(),
		"pieces": pieces.size(),
		"total_length": total_length,
		"bounds": get_bounds(),
	}
