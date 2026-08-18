---
logic_id: omniar.living-face.surface-pin
status: approved
title: OmniAR 活物脸必须贴在检测物体上（非整身独立角色）
aliases:
  - 贴到物体表面
  - 虚拟角色漂浮
  - AR face pin
api_fields: []
figma_nodes: []
code_areas:
  - OmniAR/AR/LivingObjectSystem.swift
  - OmniAR/AR/CharacterEntityFactory.swift
  - OmniAR/AR/SurfaceProjector.swift
  - OmniAR/AR/ARLivingView.swift
  - OmniAR/Detection/ObjectDetector.swift
  - OmniAR/Detection/DetectionMatch.swift
forbidden:
  - 在世界坐标一次性生成后不再跟随检测框的独立站立角色
  - 用桌面平面 raycast 命中代替物体表面却仍展示四肢站立体
  - 无 displayTransform 的图像框与屏幕点击混用
  - Release 包打明文敏感诊断日志
updated_at: "2026-08-03"
---

# OmniAR surface-pin living face

## User fragments

- 「这个实现不对啊 怎么单独显示一个虚拟的角色呢 没有贴到物体表面上啊」
- 「/dev-flow 运行调试」

## Evidence

- `CharacterEntityFactory.swift` L56–76：生成独立站立体（face + left/right arm/leg），视觉上是单独角色而非贴面贴纸。
- `LivingObjectSystem.swift` L94–148 / L153–196：点选后用 `SurfaceProjector.project` 得世界点，挂 `AnchorEntity`；虽有 IoU 重匹配与重投影，但默认视觉仍是 3D 站立角色。
- `SurfaceProjector.swift` L31–44：无 scene depth 时优先 `estimatedPlane` raycast；杯子等物体常命中桌面，角色落在桌面附近 → 「没贴在物体上」。
- `ARLivingView.swift`：已尝试开启 `sceneDepth` / `smoothedSceneDepth`（需真机支持）；iPhone 11 无 LiDAR，大概率走 plane raycast 路径。
- bugkb：关键词「AR 虚拟角色贴合物体表面」「ARKit raycast 角色漂浮」检索；命中多为无关审核/onboarding DIGEST，**无同类 AR 贴面案例**（query + 无相似结论已记录）。

## Closed state chain

| State | Precondition | Display | Action | Transition | Truth owner |
|-------|--------------|---------|--------|------------|-------------|
| Detecting | 相机授权 + AR session running | HUD detect count | — | detections 更新 | `ObjectDetector` |
| Idle-no-lock | livingCount=0 | 提示 tap to stick | tap 空白 | 保持 / No-hit | `LivingObjectSystem` |
| Locking | tap 落在检测框 | — | pick smallest containing box | Locked 或 No-hit | `ObjectDetector.pickTapped` |
| Locked-on-object | track 存在且匹配成功 | **脸贴纸贴在物体 bbox 区域**（非整身站立） | — | 跟随 / Lost | track + projector |
| Following | YOLO rematch IoU/label OK | 脸中心≈bbox 中心，尺寸跟 bbox | 物体移动/缩放 | 持续 Locked | `DetectionMatch` + sync |
| Lost | misses≥阈值 | 移除贴纸 | — | Idle | `lostAfterMisses` |
| Retap-same | 同类+IoU 重叠 | 刷新钉扎 | tap | Locked | handleTap |
| Project-fail | 无法得到深度/射线 | 提示靠近重试 | — | Idle | `SurfaceProjector` |
| Debug-run | Debug build + 真机 | HUD + DEBUG 日志 | 跑通 tap→lock→follow | — | `#if DEBUG` markers |

## State matrix

| State | UI | Data | Fallback |
|-------|----|------|----------|
| Detecting | detect N | latestDetections | 空则 Looking… |
| Locked-on-object | alive N + status Alive on {label} | track(label,box,pose) | project fail → toast |
| Following | 脸贴合 | EMA 平滑位姿 | miss++ |
| Lost | Object left view | remove anchor | — |
| No-hit | No object under tap | — | — |

## Invariants / forbidden

- 活物视觉必须读作「贴在物体上的脸」，禁止以四肢站立独立角色作为主呈现。
- 锁定后每一检测周期必须用**当前匹配框中心**重投影；禁止只钉一次世界点后永久不动（相对物体）。
- 屏幕点击与框必须经同一 `displayTransform`。
- 诊断仅 Debug；禁止默认 Release 日志。

## Golden cases

1. 点杯子：脸出现在杯身区域（非桌面远处独立小人）。
2. 缓慢平移手机：脸跟随杯子 bbox。
3. 杯子出画：约 1s 内移除。
4. 再点同一杯：刷新钉扎，不叠多个。
5. 无深度机型（iPhone 11）：仍应贴在投影到物体的深度/特征点近似位置；若只能打到桌面，脸仍应以 bbox 屏幕覆盖为主读作贴合（见下方决策）。
6. Debug：日志可见 project path（depth|raycast|feature|fail）、label、bbox、livingCount。

## Open decisions

1. **贴附呈现策略** — **已选 A（2026-08-03）**：屏幕对齐的脸贴纸；仅脸（可极短装饰），按 bbox 比例缩放，每帧重投影，读作贴在物体上。**B 不做。**
2. **运行调试设备**：计划用已连接 `iPhone 11 (00008101-000138A41131003A)` 做 `build_run_device`。待用户 **Proceed** 后执行。

## Human decision log

- 2026-08-03: 用户回复 `a` → 选定策略 A。
- 2026-08-03: 用户回复 `继续` → 视为 Proceed；已 `confirm-plan`，artifact 置 `approved`，开始实现并真机调试。
