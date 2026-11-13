extends CanvasLayer
## 启动作者声明小动画。素材放在 CutsceneSprite 的 SpriteFrames 中。
## 没有动画帧时立即隐藏，不阻塞启动。

signal intro_finished
signal cutscene_finished

## 是否启用启动动画。
@export var enabled: bool = true
## 进场动画名；留空时自动使用 SpriteFrames 的第一个动画。
@export var intro_animation: StringName = &""
## 进场动画播完后的停留时间。
@export var intro_hold_duration: float = 0.0
## 总时长兜底，避免素材异常导致卡死。
@export var max_total_duration: float = 6.0

@onready var cutscene_sprite: AnimatedSprite2D = $CutsceneSprite

var _playing: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not enabled or _animation_name().is_empty():
		_hide_now()
		return
	_fit_to_viewport()
	get_viewport().size_changed.connect(_fit_to_viewport)
	_run_cutscene()


## 开场动画固定 1280×720，手机更宽时右侧会露出游戏画面。
## 按视口做 cover 缩放，保证任何横屏比例都铺满。
func _fit_to_viewport() -> void:
	if cutscene_sprite == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var frame_size := Vector2(256, 144)
	var frames := cutscene_sprite.sprite_frames
	var animation := _animation_name()
	if frames != null and not animation.is_empty() and frames.get_frame_count(animation) > 0:
		var texture := frames.get_frame_texture(animation, 0)
		if texture != null and texture.get_size().x > 0.0:
			frame_size = texture.get_size()
	var cover_scale := maxf(viewport_size.x / frame_size.x, viewport_size.y / frame_size.y)
	cutscene_sprite.scale = Vector2(cover_scale, cover_scale)
	cutscene_sprite.position = viewport_size * 0.5


func _animation_name() -> StringName:
	if cutscene_sprite == null or cutscene_sprite.sprite_frames == null:
		return &""
	var frames := cutscene_sprite.sprite_frames
	if not intro_animation.is_empty() and frames.has_animation(intro_animation) and frames.get_frame_count(intro_animation) > 0:
		return intro_animation
	for anim_name in frames.get_animation_names():
		if frames.get_frame_count(anim_name) > 0:
			return StringName(anim_name)
	return &""


func _hide_now() -> void:
	_playing = false
	if cutscene_sprite != null:
		cutscene_sprite.stop()
		cutscene_sprite.visible = false
	set_process(false)


func _run_cutscene() -> void:
	if _playing:
		return
	var animation := _animation_name()
	if animation.is_empty():
		_hide_now()
		return
	_playing = true
	var budget := maxf(0.1, max_total_duration)
	cutscene_sprite.visible = true
	cutscene_sprite.modulate.a = 1.0
	cutscene_sprite.play(animation)
	var frames := cutscene_sprite.sprite_frames
	var fps := maxf(1.0, frames.get_animation_speed(animation) * maxf(0.01, cutscene_sprite.speed_scale))
	var duration := minf(budget, float(frames.get_frame_count(animation)) / fps)
	await get_tree().create_timer(duration, true, false, false).timeout
	if not _playing:
		return
	if intro_hold_duration > 0.0:
		await get_tree().create_timer(minf(intro_hold_duration, budget), true, false, false).timeout
	if not _playing:
		return
	intro_finished.emit()
	_hide_now()
	cutscene_finished.emit()


func replay() -> void:
	if not enabled or _animation_name().is_empty():
		return
	_hide_now()
	_run_cutscene()
