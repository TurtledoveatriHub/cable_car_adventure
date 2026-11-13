"""Move inline ## comments above @export vars and fill missing documentation.

Run from the project root:
  python tools/add_export_comments.py
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
FILES = sorted(list((ROOT / "scripts").rglob("*.gd")) + list((ROOT / "tools").rglob("*.gd")))

COMMENTS = {
    "id": "唯一标识（保存到 JSON 的稳定 id）",
    "display_name": "在工坊和 UI 中显示的名称",
    "type": "类型枚举",
    "radius": "碰撞半径（像素）",
    "damage": "碰撞时扣除的乘客数",
    "motion_type": "运动模式：static / oscillate_x / oscillate_y / circle / ellipse",
    "amplitude": "运动振幅（像素）",
    "motion_speed": "运动速度倍率",
    "motion_phase": "运动初始相位（弧度）",
    "collision_offsets": "多个碰撞体相对障碍中心的偏移",
    "collision_radii": "每个碰撞体的半径；留空时使用默认半径",
    "interval_enabled": "是否启用间隔生效的碰撞体",
    "interval_period": "间隔循环周期（秒）",
    "interval_active": "每个周期内碰撞体生效时长（秒）",
    "trigger_enabled": "是否只有缆车进入范围才启动",
    "trigger_radius": "触发检测半径（像素）",
    "length": "直线长度或曲线弧长（像素）",
    "angle_deg": "圆弧角度（度）；环圈使用 -360",
    "free_origin": "是否使用自由起点；勾选后 origin 生效",
    "origin": "自由片段的世界坐标起点",
    "heading_deg": "自由片段的起始朝向（度）",
    "break_after": "缆车通过该片段后，等待多少秒断开；0 表示不断开",
    "play_on_ready": "运行该场景时是否自动进入游戏",
    "custom": "是否为玩家自制关卡",
    "level_id": "关卡稳定 id",
    "level_name": "关卡显示名称",
    "subtitle": "关卡副标题",
    "description": "关卡描述",
    "starting_passengers": "开局乘客数",
    "max_passengers": "最大乘客数",
    "difficulty": "难度等级",
    "speed_limit": "前进速度上限（像素/秒）",
    "reverse_speed_limit": "后退速度上限（像素/秒）",
    "engine_acceleration": "前进引擎加速度（像素/秒²）",
    "reverse_acceleration": "后退引擎加速度（像素/秒²）",
    "gravity_accel": "沿轨道方向的重力加速度",
    "uphill_engine_assist": "上坡时引擎抵消重力的比例",
    "rolling_friction": "松手时的滚动摩擦减速度",
    "air_drag": "空气阻力系数（每秒比例）",
    "par_time": "参考通关时间（秒）",
    "theme_id": "关卡主题：sky / sunset / night / forest / gray",
    "start_s": "起点在轨道上的弧长",
    "finish_s": "终点在轨道上的弧长",
    "camera_bounds": "相机活动范围；空 Rect2 时按轨道自动计算",
    "track_pieces": "轨道片段资源数组（TrackPieceDefinition）",
    "scene": "对应的独立障碍/乘客场景",
    "prefab_id": "关卡 JSON 中记录的预制体 id",
    "track_s": "在轨道上的弧长位置",
    "offset": "相对轨道点的偏移",
    "bonus": "拾取后增加的乘客数",
    "max_speed": "前进最高速度（像素/秒）",
    "max_reverse_speed": "后退最高速度（像素/秒）",
    "air_gravity": "脱轨飞行重力",
    "magnet_radius": "飞行中吸附回轨道的半径",
    "min_attach_speed": "吸附所需最小沿轨速度",
    "body_offset_y": "吊厢中心相对轨道点的下移距离",
    "wheel_offset": "两个轮子沿切线方向的间距",
    "wheel_radius": "车轮半径",
    "countdown_seconds": "开局倒计时（秒）",
    "finish_delay_seconds": "终点/失败后进入结算的延迟（秒）",
    "hit_invulnerability_seconds": "碰撞后的短暂无敌时间（秒）",
    "auto_route_to_result": "结束后是否自动进入结算",
    "save_results": "是否由本控制器写入存档；双人分屏由父控制器统一保存",
    "input_prefix": "输入前缀：solo / p1 / p2",
    "hud_enabled": "是否显示本控制器内的独立 HUD",
    "handle_pause_input": "是否由本控制器处理 Esc；分屏时由父控制器统一处理",
    "player_label": "玩家显示名称",
    "camera_offset": "镜头相对吊厢中心的偏移",
    "camera_smoothing_speed": "镜头跟随平滑速度",
    "camera_deadzone": "吊厢在屏幕中心的死区半径",
    "camera_shake_strength": "碰撞震动强度",
    "camera_shake_seconds": "碰撞震动时长（秒）",
    "definition": "旧版 .tres 障碍定义；独立场景不再需要，仅兼容旧关卡",
    "use_scene_settings": "是否使用本场景 Inspector 中的障碍参数",
    "obstacle_type": "障碍视觉类型",
    "phase": "运动/动画相位（弧度）",
    "collision_radius": "单碰撞体默认半径（像素）",
    "chart_title": "图表标题",
    "chart_type": "图表类型：line / bar",
    "accent": "图表或预览的强调色",
    "value_suffix": "数值后缀，例如 % 或 秒",
    "active": "是否播放彩纸效果",
    "piece_count": "彩纸数量",
    "fall_speed": "彩纸基础下落速度",
    "head_radius": "乘客头像半径",
    "head_spacing": "乘客头像间距",
    "filled_color": "有乘客时的头像颜色",
    "accent_color": "乘客脸部/强调色",
    "hover_scale": "鼠标悬停时的缩放比例",
    "play_hover_sound": "是否播放悬停音效",
    "top_color": "天空顶部颜色",
    "bottom_color": "天空底部颜色",
    "far_mountain_color": "远山颜色",
    "near_mountain_color": "近山颜色",
    "game_mode": "游戏内模式会减少前景装饰",
    "camera_x": "游戏内相机水平坐标，用于视差",
    "auto_scroll_speed": "菜单背景自动滚动速度",
    "cart_texture": "过山车整车贴图",
    "cart_draw_size": "整车目标绘制尺寸",
    "cart_draw_offset": "整车相对轨道点的绘制中心",
    "bird_texture": "海鸥贴图",
    "storm_texture": "风暴贴图",
    "barrier_texture": "路障贴图",
    "crate_texture": "木箱贴图",
    "fan_texture": "风扇贴图",
    "obstacle_draw_size": "障碍默认绘制尺寸",
    "pickup_texture": "乘客点贴图",
    "pickup_draw_size": "乘客点绘制尺寸",
    "pickup_draw_offset": "乘客点绘制偏移",
    "track_texture": "轨道贴图，沿轨道重复铺设",
    "track_texture_segment_length": "单段贴图覆盖的弧长",
    "track_texture_height": "轨道贴图法向高度",
    "start_gate_texture": "起点站台贴图",
    "finish_gate_texture": "终点牌贴图",
}

PATTERN = re.compile(r"^(\s*)(@export(?:_enum\([^)]*\))?\s+var\s+([A-Za-z_][A-Za-z0-9_]*)\b.*?)(?:\s*##\s*(.*))?$")


def main():
    changed = 0
    for path in FILES:
        lines = path.read_text(encoding="utf-8").splitlines()
        out = []
        for line in lines:
            m = PATTERN.match(line)
            if not m:
                out.append(line)
                continue
            indent, code, name, inline = m.groups()
            code = code.rstrip()
            previous = out[-1].strip() if out else ""
            if inline:
                comment = inline.strip()
            elif previous.startswith("##"):
                out.append(code)
                continue
            else:
                comment = COMMENTS.get(name, f"{name} 配置项")
            if not previous.startswith("##"):
                out.append(f"{indent}## {comment}")
            out.append(code)
            changed += 1
        text = "\n".join(out) + "\n"
        if text != path.read_text(encoding="utf-8"):
            path.write_text(text, encoding="utf-8")
    print(f"processed {len(FILES)} files, {changed} export vars")


if __name__ == "__main__":
    main()
