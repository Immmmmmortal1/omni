---
logic_id: omniar.detect-and-world-lock
status: approved
title: 提升杯子识别 + 贴脸后世界锚点锁定（停识别）
aliases:
  - 杯子识别不了
  - 贴图后继续识别
  - 表情跟着手机跑
api_fields: []
figma_nodes: []
code_areas:
  - OmniAR/Detection/ObjectDetector.swift
  - OmniAR/AR/LivingObjectSystem.swift
  - OmniAR/AR/ARLivingView.swift
  - OmniAR/Models/
forbidden:
  - 贴脸成功后仍每帧 YOLO + syncTracks 重投影导致世界位姿漂移
  - 贴脸后因 miss 阈值自动摘掉表情
  - 未修 AR 帧朝向却只盲目换更大模型作为唯一手段（可并行升级）
updated_at: "2026-08-03"
---

# Detect + world-lock after pin

## User fragments

- 问题1: 识别率还是太低了，镜头前面的杯子都识别不了
- 问题2: 点了贴图按钮之后就不应该继续识别了；要将表情贴到已识别的物体上；无论怎么移动手机，表情在空间上的位置和物体绑定，不应该动
- `/dev-flow`

## Evidence

- `ObjectDetector.swift:85-91`：`VNImageRequestHandler(cvPixelBuffer:options:[:])` **未传图像朝向**。ARKit `capturedImage` 多为传感器横向缓冲；竖屏使用时缺 `CGImagePropertyOrientation` 是 Vision+AR 常见漏检/框乱根因。
- `ObjectDetector.swift:59`：阈值 0.25 + `yolo11n`；用户报告近距杯子仍检不到 → 朝向问题优先于再换模型，必要时再升 `yolo11s`。
- `LivingObjectSystem.swift:40-58` + `168-210`：贴脸后仍 `updateDetections` → `syncTracks` **每帧重投影并 `applyPose`**，世界坐标被不断改写 → 手机移动时表情“乱动”，违背“与物体空间绑定”。
- `ARLivingView.swift:55-64`：会话每 ~0.12s 强制跑检测，无“已锁定则停检”开关。
- 旧链 `omniar.living-face.surface-pin` 的 Following 状态与用户问题2 **冲突**；本链 supersede 锁定后行为。
- bugkb：查询「Vision CoreML 检测不到」；无同类 AR 帧朝向/贴脸世界锁 case（DIGEST/无关命中）。

## Closed state chain

| State | Precondition | Display | Action | Transition | Truth owner |
|-------|--------------|---------|--------|------------|-------------|
| Hunting | livingCount==0 | detect count | YOLO on frames | — | ObjectDetector (+正确朝向) |
| Tap-pin | hunting + tap hit | — | project once → world AnchorEntity | Locked | LivingObjectSystem |
| Locked | ≥1 world-locked sticker | alive count；表情世界固定 | **停止 YOLO**；仅 billboard 朝向相机（可选） | Clear | AnchorEntity world pose |
| Clear | user Esc/双击/按钮（若已有）或暂仅“全部清空” | — | remove anchors | Hunting | LivingObjectSystem |
| Detect-fail | hunting 但无框 | Looking… | — | Hunting | detector |

## State matrix

| State | UI | Data | Fallback |
|-------|----|------|----------|
| Hunting | detect N | latestDetections | 空则 Looking |
| Tap miss | toast | — | Hunting |
| Locked | alive N；停检 | tracks 固定 world pose | 不因 miss 删除 |
| Project fail | toast | — | Hunting |

## Invariants / forbidden

- Locked 后禁止再跑 YOLO / syncTracks 重投影。
- Locked 表情世界坐标在钉扎瞬间固定；手机移动时靠 ARKit 世界跟踪保持相对真实场景不动。
- Hunting 检测必须带与 AR 竖屏一致的 Vision orientation。
- 物理物体被搬走后表情仍留在原世界点（用户明确要空间绑定、停识别）——接受，不自动追随物体平移。

## Golden cases

1. 竖屏对准杯子：detect≥1 且含 cup/bottle/wine glass 等饮具类（或用户可见 HUD 上升）。
2. 点杯子贴脸：表情出现在杯附近世界点。
3. 贴脸后 detect 停止增长/停检；平移/转动手机，表情相对杯子世界位置稳定（不跟着屏幕漂）。
4. 贴脸后杯子短暂出画：表情仍在（不因 miss 消失）。
5. Debug：`[OmniAR][pin]` / `[OmniAR][det]` 可见 orientation、rawCount、locked=stop。

## Open decisions

1. **清空方式** — **已确认 A**：点空白 / Esc 清空全部并恢复 Hunting。
2. **模型** — **已确认**：修 orientation；并升 **yolo11s**（用户确认可升级，近距杯在 n 上已失败）。

## Human decision log

- 2026-08-03: 用户回复「确认」→ Proceed；A + 允许升 yolo11s。
