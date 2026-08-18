---
logic_id: omniar.pin-onto-tapped-object
status: approved
title: 表情必须钉在用户点中的物体上（点准+深度落点）
aliases:
  - 贴不到对应物体
  - 表情偏了
  - pin miss object
api_fields: []
figma_nodes: []
code_areas:
  - OmniAR/AR/LivingObjectSystem.swift
  - OmniAR/Detection/ObjectDetector.swift
  - OmniAR/AR/SurfaceProjector.swift
  - OmniAR/AR/CharacterEntityFactory.swift
forbidden:
  - 点击未命中任何检测框时，用「全局最完整/最近」冒充用户点中的物体
  - 仅用桌面 plane 命中作为杯身落点且无沿视线抬升
  - 为「贴准」而重新打开贴后每帧 YOLO 重投影（与 world-lock 冲突，除非用户改口）
updated_at: "2026-08-03"
---

# Pin onto the tapped object

## User fragments

- 「不行 现在贴不到对应物体上面去啊」
- `/dev-flow`
- 此前已确认：贴后停识别 + 世界锚点；选物「完整优先、再最近」

## Evidence

- `LivingObjectSystem.swift:94-120`：贴脸用检测框 **中心** `attachPoint` 做 `SurfaceProjector.project`，不是手指落点；桌面 raycast/feature 易打到杯脚桌面。
- `ObjectDetector.pickTapped`：点不中框时 fallback 到**全屏** complete→near，可能贴到非用户所指物体。
- `SurfaceProjector.swift:37-60`：无 LiDAR 时 feature/raycast；raycast 常为支撑平面。
- `LivingObjectSystem` 贴后 `isLocked` 停检：落点错了会**永久错**在错误世界点。
- 与 `omniar.detect-and-world-lock` 并存：保留停检+世界锁；本链只修「钉到点中物体」。
- bugkb：「AR 贴图偏 锚点 不对物体」→ 无同类 case。

## Closed state chain

| State | Precondition | Display | Action | Transition |
|-------|--------------|---------|--------|------------|
| Hunting | unlocked | detect N | YOLO | — |
| Tap-hit | tap ∈ 某检测框 | — | 只在命中集合里按完整→近选；**沿手指射线**投影；沿视线按框高抬升 | Locked |
| Tap-miss | tap ∉ 任何框 | toast「点到物体上」 | **禁止**全局瞎选 | Hunting |
| Locked | world anchor | face 覆盖点中物体视觉 | 停 YOLO；世界固定 | Clear |

## State matrix

| State | UI | Data | Fallback |
|-------|----|------|----------|
| Tap-hit | Locked on {label} | label, tapRay hit, lift | project fail → toast |
| Tap-miss | No object under tap | — | Hunting |
| Locked | detect off | frozen world pose | — |

## Invariants / forbidden

- 只能钉「手指点中的检测框」内的物体；点空不贴。
- 3D 落点优先：手指屏幕点射线 + 深度；再用 bbox 尺寸估抬升，使脸落在物体中部而非桌面。
- 贴后仍停 YOLO（world-lock 不变）。
- 完整→近 排序只在 **含点击点的框** 内生效。

## Golden cases

1. 点杯子中心：脸出现在杯身（非邻桌空位/邻物）。
2. 点空白：不贴、提示点物体。
3. 杯与瓶同框：点谁钉谁。
4. 贴后平移手机：脸相对杯身世界位置稳定。
5. Debug：`pin … tapRay=1 path=… lift=… label=cup`。

## Open decisions

Resolved 2026-08-03 by user 「继续」:

1. **抬升策略：A** — 沿视线抬升 `≈0.30 * bbox_world_extent`（夹在 0.04…0.28m）。
2. **点空：不贴 + toast** — 禁止全局 fallback。
