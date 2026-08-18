---
logic_id: omniar.vision-box-coord-and-size
status: approved
title: Vision 框坐标映射修正 + 表情尺寸贴合物体
aliases: [贴到桌子, 表情太大, 坐标错位, box mapping]
api_fields: []
figma_nodes: []
code_areas:
  - OmniAR/Detection/ObjectDetector.swift
  - OmniAR/AR/LivingObjectSystem.swift
  - OmniAR/AR/CharacterEntityFactory.swift
forbidden:
  - Vision oriented 框再叠 displayTransform 造成双重坐标变换
  - 按支撑面/桌子 bbox 缩放表情
  - 点 cup 命中 dining table
updated_at: "2026-08-04"
---

# Vision box coord mapping + size fit

## User fragments

- 「拍桌子上的水杯就识别到桌子，拍椅子就识别到地板」
- 「表情没有贴到物体上」
- 「表情的大小没有贴合物体的大小，杯子不大但表情大，要后移手机才看全」

## Evidence

- 日志 1608→1609：帧含 `cup:1.00`，点击却 `pin label=dining table area=0.749 bbox=1.20`。
- `ObjectDetector.detect` 以 `.right` 喂 Vision → 框在**竖屏 oriented 归一化空间**。
- `DetectedObject.viewNormalizedBox` 又叠 `frame.displayTransform(for:)`（期望**相机原生横向空间**）→ 双重变换，小框错位。
- 因选中桌子 → 贴桌面 + 按桌子 bbox(1.2) 缩放 → 表情巨大、需后退。

## Closed state chain

| State | Action |
|-------|--------|
| Hunting | YOLO 检测（不变） |
| Tap-hit | 用**单一正确映射**（oriented→view，aspect-fill）判定命中框；命中集合内丢桌床沙发→选最小框；沿框投影+按物高抬升 |
| Size | 表情按**选中物体**的 view 框缩放并封顶（≈物体大小，不超屏） |
| Tap-miss | 不贴 |
| Locked | 世界锚 + 停 YOLO（不变） |

## Invariants / forbidden

- 坐标只做一次 oriented→view 映射（aspect-fill，居中裁切），不再叠 displayTransform。
- 表情尺寸来源必须是选中物体的 view 框，禁止桌子/支撑面尺寸。
- 点空不贴；贴后世界锁不变。

## Golden cases

1. 点杯 → `pin label=cup`，表情小且贴杯身。
2. 点椅 → `chair`。
3. 只有点空桌面才 `dining table`。
4. 贴后平移手机世界稳。
5. DEBUG：`tapdump` 打印点击点与各框 view rect / 命中，用于验证映射修对（收尾移除）。

## Open decisions

Resolved 2026-08-04 by user 「修改」: 先加临时 DEBUG `tapdump` 验证映射方向，修对后移除噪声日志。
