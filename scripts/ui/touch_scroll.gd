extends ScrollContainer
## 触摸从按钮/卡片上开始拖动时，也能滚动 ScrollContainer。
## 点击仍交给子按钮；超过阈值后才拦截为滚动，避免按钮按下后滑不动列表。
## 松手后按拖动速度继续滚动，并使用指数阻尼减速，接近边界时自动停住。

const DRAG_THRESHOLD := 12.0
## 惯性速度衰减系数；越大停得越快。
const INERTIA_FRICTION := 5.0
## 低于该速度直接停止，避免列表长时间“爬行”。
const MIN_INERTIA_SPEED := 28.0
## 限制最大甩动速度，防止一划就飞到底。
const MAX_INERTIA_SPEED := 3200.0
## 拖动时速度的平滑系数，避免最后一帧抖动主导方向。
const VELOCITY_SMOOTHING := 0.35

var _touch_index: int = -1
var _start_position: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _velocity: Vector2 = Vector2.ZERO
var _scroll_remainder: Vector2 = Vector2.ZERO
var _last_drag_msec: int = 0
var _inertia_active: bool = false


func _ready() -> void:
	set_process(false)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _inertia_active and not get_global_rect().has_point(event.position):
			_stop_inertia()
		if event.pressed and _touch_index < 0 and get_global_rect().has_point(event.position):
			_touch_index = event.index
			_start_position = event.position
			_dragging = false
			_inertia_active = false
			_velocity = Vector2.ZERO
			_scroll_remainder = Vector2.ZERO
			_last_drag_msec = Time.get_ticks_msec()
			set_process(false)
		elif not event.pressed and event.index == _touch_index:
			if _dragging:
				get_viewport().set_input_as_handled()
				_start_inertia()
			_touch_index = -1
			_dragging = false
	elif event is InputEventScreenDrag and event.index == _touch_index:
		if not _dragging and event.position.distance_to(_start_position) >= DRAG_THRESHOLD:
			_dragging = true
			_velocity = Vector2.ZERO
			_scroll_remainder = Vector2.ZERO
		if _dragging:
			_scroll_remainder -= event.relative
			var step_x := int(_scroll_remainder.x)
			var step_y := int(_scroll_remainder.y)
			if step_x != 0:
				scroll_horizontal += step_x
				_scroll_remainder.x -= float(step_x)
			if step_y != 0:
				scroll_vertical += step_y
				_scroll_remainder.y -= float(step_y)
			_track_velocity(event)
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not _inertia_active or _dragging or _touch_index >= 0:
		return
	var frame_delta := minf(delta, 1.0 / 30.0)
	_scroll_remainder += _velocity * frame_delta
	var step_x := int(_scroll_remainder.x)
	var step_y := int(_scroll_remainder.y)
	var before := Vector2(scroll_horizontal, scroll_vertical)
	if step_x != 0:
		scroll_horizontal += step_x
		_scroll_remainder.x -= float(step_x)
	if step_y != 0:
		scroll_vertical += step_y
		_scroll_remainder.y -= float(step_y)
	# 到达边界后对应轴立即失去速度，避免在尽头继续累积。
	if step_x != 0 and is_equal_approx(scroll_horizontal, int(before.x)):
		_velocity.x = 0.0
		_scroll_remainder.x = 0.0
	if step_y != 0 and is_equal_approx(scroll_vertical, int(before.y)):
		_velocity.y = 0.0
		_scroll_remainder.y = 0.0
	_velocity *= exp(-INERTIA_FRICTION * frame_delta)
	if _velocity.length() < MIN_INERTIA_SPEED:
		_stop_inertia()


func _track_velocity(event: InputEventScreenDrag) -> void:
	var now := Time.get_ticks_msec()
	var seconds := maxf(0.001, float(now - _last_drag_msec) / 1000.0)
	_last_drag_msec = now
	# 优先使用系统给出的拖动速度；部分平台返回 0 时用位移/时间兜底。
	var target := -event.velocity
	if target.length_squared() < 1.0:
		target = -event.relative / seconds
	target = target.limit_length(MAX_INERTIA_SPEED)
	_velocity = _velocity.lerp(target, VELOCITY_SMOOTHING).limit_length(MAX_INERTIA_SPEED)


func _start_inertia() -> void:
	_scroll_remainder = Vector2.ZERO
	# 长按后松手不应把很久以前的拖动速度当成一次甩动。
	if Time.get_ticks_msec() - _last_drag_msec > 120:
		_velocity = Vector2.ZERO
	if _velocity.length() < MIN_INERTIA_SPEED:
		_stop_inertia()
		return
	_velocity = _velocity.limit_length(MAX_INERTIA_SPEED)
	_inertia_active = true
	set_process(true)


func _stop_inertia() -> void:
	_inertia_active = false
	_velocity = Vector2.ZERO
	_scroll_remainder = Vector2.ZERO
	set_process(false)
