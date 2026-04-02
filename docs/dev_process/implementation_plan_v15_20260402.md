# SlideRev 逐项重绘与视觉减负计划 (v15.0)

## 问题分析
- **反馈**：之前的遮罩（Blur + Scanner）过于厚重，掩盖了原本精炼过程的“黑科技感”。
- **目标**：实现“原位转换”效果——逐个文本框擦除原图背景，并同步浮现矢量文字。
- **性能**：利用局部遮罩（Masking）技术实现“分毫秒级”的视觉刷新。

## 拟执行的变更

### 1. 局部重绘层 (RefinementView.swift)
- **[NEW] `ErasedItemsMask`**: 一个 SwiftUI Shape，它会根据 `recognizedItems` 中 `isErased == true` 的矩形区域动态生成一个路径。
- **[MODIFY] `imageWorkspaceContent`**:
    - 保持 `originalImage` 在最底层。
    - 在其上方叠加 `inpaintedImage`（如果存在），但为其应用 `.mask(ErasedItemsMask(...))`。
    - 这样，只有被标记为“已擦除”的部分，才会透出干净的 AI 重绘底图。

### 2. 逐项流式动效 (AdvancedSlideProcessor.swift)
- **[MODIFY] `refinePage`**:
    - **第一步**：立即通过静默重构（Inpainter）计算出完整的无字底图（约 1s）。
    - **第二步**：不等待重绘完成动画，而是通过一个**快速循环**（Staggered Loop，每项间隔 0.02s - 0.05s）逐个切换状态。
    - **效果**：在极短的时间内，文本框会像“多米诺骨牌”一样从旧图像转变为矢量文本，同时背景也随之逐个变干净。

### 3. UI 简化
- **[DELETE]** 移除 `refiningOverlay`。
- **[ADD]** 在工具栏 Refine 按钮旁增加一个极简的 AI 脉冲灯 (Pulsing Light)，表示正在思考。

## 验证方案
1. **流畅度测试**：确保 100 个文本框的页面在 1 秒内完成全量转换。
2. **视觉沉浸感**：检查是否实现了“局部擦除+同步刷新”的效果，即背景的干净程度是跟随文本框的显示同步出现的。
