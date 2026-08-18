---
logic_id: omniar.rive-animated-creature
status: approved
title: Transparent decal face (Rive) with thinking/talking on pinned object
aliases: [会动的表情, 四肢, thinking动作, rive, 动起来, animated creature, 透明贴图, png贴图, 贴图感]
api_fields: []
figma_nodes: []
code_areas:
  - OmniAR/AR/CreatureOverlayView.swift
  - OmniAR/AR/LivingObjectSystem.swift
  - OmniAR/ContentView.swift
  - OmniAR/UI/SpeechBubbleView.swift
  - OmniAR/AR/CharacterEntityFactory.swift
  - project.yml
  - OmniAR/Resources/omni_creature.riv
forbidden:
  - 用不透明粉色整脸/独立角色盘替代透明贴图(betrays 贴图语义)
  - 用独立虚拟人物替代“物体本体活起来”
  - 完整站立小人构图(独立身体/双腿/站姿)
  - 第一版出现胳膊(本版仅脸贴图；胳膊后续另批)
  - 每次父视图刷新就重建 RiveViewModel(导致 setInput/triggerInput 失效, rive-ios #277)
  - DeepSeek 延迟期间无任何“思考”反馈(必须有 thinking 动作)
updated_at: "2026-08-04"
---

# Transparent decal face + thinking/talking (Rive)

## User fragments
- “贴上能动的四肢 还有表情”，但“不如直接给一个虚拟人物”又“背离了让静物活起来的想法”。
- “我更加倾向于 Rive 动画”。
- “deepseek 有加载时间延迟 还要设计一个 思考的动作”。
- 真机反馈: “这个角色是个单独的…表情和四肢应该是和物体贴在一起的感觉”。
- 曾选 B: “只要大脸 + 两侧胳膊，不要腿” —— **已被后续澄清 supersede**：用户不要粉脸独立角色。
- 关键澄清(2026-08-04): “不对现在还是粉色的独立脸加手臂 我要这种 这种png 带透明通道 这个才叫贴图 例如第二张”。

## Visual contract (authoritative)
- **贴图语义**: 只有五官/表情笔画可见；**背景全透明**；**物体表面当皮肤**。
- **素材(已确认)**: 使用用户 `Downloads/18文件夹` 源 MOV（ARGB）导出的 PNG 序列：
  - idle ← 表情装饰元素 (1)
  - thinking ← 表情装饰元素 (4)（Zzz 等待）
  - talking ← 表情装饰元素 (2)（张嘴）
- **禁止**: 不透明粉底、独立角色轮廓、AI 手搓替代用户素材。
- **贴合**: 透明 billboard；全屏坐标与 `ARView.project` 对齐（修 Safe Area 裁半）。
- **状态**: idle / thinking / talking（由 `LivingCreature.isThinking` + `talkNonce` 驱动）。

## Evidence
- 用户提供参考图已复制到 `.dev-flow/requirements/refs/`。
- 当前实现: `OmniAR/Resources/omni_creature.riv` 仍是粉脸椭圆 + 粉胳膊（不透明），`CreatureOverlayView` 全帧渲染 → 读成独立角色。
- `CharacterEntityFactory` 注释写「Face sticker only」但仍有粉色 disc 材质 → 与「透明贴图」也不一致，回退路径需一并改。
- 世界锁定/投影跟随已存在: `LivingObjectSystem.updateAnchors`。
- 无物体网格重建: 仅有 YOLO bbox + featurePoint，**无法**在本阶段做真实圆柱 UV 贴合；第一版用**透明 billboard 贴图**对齐参考读感。

## Rive state-machine control contract (keep)
资源: `OmniAR/Resources/omni_creature.riv`
- Artboard: `creature`；State machine: `omni`
- Inputs: `thinking`(Bool), `talk`(Trigger), `tap`(Trigger)
- States: `idle` / `thinking` / `talking`（视觉改为透明贴图部件动画，接口名不变）

## App-event mapping
| 事件 | 动画输入 | UI |
| --- | --- | --- |
| pin | thinking=true | 透明贴图出现在物体中心, thinking |
| 台词就绪 | thinking=false; talk | 气泡 + talking |
| tickFrame | 更新屏幕坐标+尺寸 | 贴图跟随世界锚点 |
| clear/evict | 移除 | 贴图+气泡消失 |

## Closed state chain
- 未锁定: 无贴图。
- pin → thinking 循环遮住 DeepSeek 延迟（无旧 “…” 点气泡）。
- 台词成功/兜底 → talk → idle；气泡显示文本。
- 移动手机: 贴图投影跟随、按深度缩放。
- clear: 移除贴图+气泡，恢复检测。
- 资源缺失: 回退 RealityKit **透明五官贴图**(非粉盘)，不崩。

## State matrix
- thinking / talking / idle: 同前，视觉部件改为透明贴图笔画。
- 资源缺失: RealityKit 透明五官 fallback。

## Invariants / forbidden
- 贴图层必须透明通道：只画五官(±臂笔画)，物体当皮肤。
- 不得出现不透明粉底/独立角色轮廓。
- RiveViewModel 稳定实例；世界锁定语义不变。
- DeepSeek 等待必须有 thinking 反馈。

## Golden cases
1. 贴杯子 → 看到杯子材质上的五官(无粉脸盘) + thinking → talk+气泡 → idle。
2. 对照参考: 读感接近 `decal-on-cup-jar-example.png`（billboard 近似，非真 UV 包裹）。
3. 兜底台词路径同样有 thinking→talk。
4. 世界锁定跟随；清除干净。
5. 无 .riv → RealityKit 透明五官 fallback，不崩。

## Open decisions (resolved 2026-08-04)
1. **风格**: (B) 黑色极简线条贴图。【用户「继续」+ 先前「例如第二张」】
2. **胳膊**: (1) 第一版只要脸贴图。【同上默认】
3. **贴合**: 透明 billboard。【agent 建议，用户继续】
4. 素材来源: AI 用 Rive MCP 重画透明黑线五官 .riv（接口名不变）。
5. RealityKit 回退: 同步改为透明五官，去掉粉盘。
