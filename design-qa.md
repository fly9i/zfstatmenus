# 分享图暖色几何背景 Design QA

## 对比基准

- Source visual truth：用户提供的现有分享图截图 `codex-clipboard-6463c659-6934-42be-a9a1-8c0b578a67e8.png`，以及选定的暖色几何概念图 `exec-d4d94edb-2a1b-4cba-9036-653fc862d7da.png`。
- Implementation screenshot：`/private/tmp/zfstat-share-preview.png`。
- Combined comparison：`/private/tmp/zfstat-share-comparison.png`，从左到右依次为暖色概念图、原分享图、实现结果。
- State：浅色卡片、四家订阅额度、90 天热力图、今日模型与工具列表。

## 尺寸与归一化

- 原分享图：1080 × 2937 px，对应 360 pt 宽、3× 输出。
- 暖色概念图：853 × 1844 px，仅作为配色与规则几何语言参考。
- 实现截图：1080 × 3012 px，对应 360 pt 宽、3× 输出；高度差来自测试数据内容，不属于布局漂移。
- 合并对比时三张图片统一缩放到 540 px 宽并顶部对齐；没有用密度差异评价字体或间距。

## Full-view comparison evidence

- 白色卡片仍为 324 pt 宽，分享图总宽 360 pt，左右各 18 pt，内容占比保持 90%。
- 卡片之间的 14 pt 间距、圆角、阴影和内部布局没有改动。
- 暖色几何只分布在左右窄边及顶部、底部角落，没有进入内容区。
- 深梅紫到炭黑底色与橙、珊瑚红、洋红图形形成明确区分，同时没有压过卡片层级。

## Focused region comparison evidence

无需额外局部裁切：本次改动只涉及约 18 pt 的窄边背景，3× 实现截图中几何边缘、圆角、斜线和卡片遮挡关系均可在全图清晰辨认；卡片内部沿用原实现，未做重绘。

## Required fidelity surfaces

- Fonts and typography：原有字体、字号、字重、截断与费用单行规则保持不变。
- Spacing and layout rhythm：360 pt 总宽、18 pt 外边距、324 pt 卡片宽度和 14 pt 卡片间距保持不变。
- Colors and visual tokens：实现采用深梅紫/炭黑底，搭配橙、珊瑚红、洋红、梅紫及少量奶油色，与选定概念一致。
- Image quality and asset fidelity：背景使用分辨率无关的 SwiftUI Canvas，在 3× 离屏渲染后仍保持清晰；最终继续输出不透明 8-bit sRGB PNG，无透明边缘和彩色噪点。
- Copy and content：生产内容完全复用现有视图；对比截图中的数值差异来自代表性测试数据，不是实现改动。

## Findings

- 未发现 P0、P1 或 P2 问题。
- P3：实现结果的底部角落图形比概念图略克制，这是为了遵守原图 5% 窄边比例，属于可接受差异。

## Comparison history

- 第一次实现即保持原图 90% 内容占比；组合对比未发现需要返工的 P0/P1/P2 差异，因此没有修复循环。

## Implementation checklist

- [x] 保持分享图原有尺寸和卡片比例。
- [x] 使用暖色、高对比、规则几何背景。
- [x] 限制装饰在窄边和角落，不遮挡卡片内容。
- [x] 保持标准动态范围、不透明 sRGB PNG 输出。
- [x] 增加暖色边缘像素回归测试。

final result: passed
