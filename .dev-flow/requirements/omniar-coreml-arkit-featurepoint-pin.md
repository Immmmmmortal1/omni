---
logic_id: omniar.coreml-arkit-featurepoint-pin
status: approved
title: 采用 CoreML-in-ARKit 的 featurePoint 落点
aliases: [CoreML-in-ARKit, featurePoint pin, hanleyweng]
api_fields: []
figma_nodes: []
code_areas:
  - OmniAR/AR/SurfaceProjector.swift
  - OmniAR/AR/LivingObjectSystem.swift
forbidden:
  - 把整库 Inception 分类替换 YOLO（本链只借落点，不换检测器）
  - featurePoint 命中后仍做大抬升导致脸离开物体表面
updated_at: "2026-08-04"
---

# CoreML-in-ARKit featurePoint pin

## User fragments

- 「https://github.com/hanleyweng/CoreML-in-ARKit 用这个库试下」

## Evidence

- 该仓是模板 App，非 SPM 库；核心落点：`sceneView.hitTest(point, types: [.featurePoint])` → 世界坐标放 Billboard 节点。
- 分类用 Inceptionv3 整图，与本项目 YOLO 检测不同；本链只移植 **featurePoint hitTest** 落点。
- OmniAR 已有自定义 feature 采样；改为优先 ARKit 原生 featurePoint hit（与样例一致）。

## Closed state chain

| State | Action | Note |
|-------|--------|------|
| Hunting | YOLO 检测 | 不变 |
| Tap-hit | 含点框内选物 → SurfaceProjector：depth → **arkit-feature** → 自研 feature → raycast → fallback | 对齐样例 |
| Locked | 世界锚 + 停 YOLO | 不变；arkit-feature/depth/feature 仅微抬升 |

## Golden cases

1. 点杯身：`path=arkit-feature`（或 depth/feature），脸在物体上。
2. 点空：不贴。
3. 贴后世界锁仍生效。
