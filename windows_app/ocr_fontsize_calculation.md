# SlideRev OCR 字体大小计算逻辑说明

本文档详细说明了 Windows 版 SlideRev 如何根据 OCR 检测到的原始高度（rawH）计算最终显示的字号（FontSize）。

## 1. 检测阶段 (VisionOcrAdapter)
OCR 使用 **DBNet** 模型，它检测到的是文字的“核心区域”（Kernel），而不是包含上下间距的完整字符框。

- **原始高度 (`rawH`)**: 在图像未进行任何扩张之前，记录检测到的核心矩形的高度（Kernel）。
- **黄金高度 (`fittingH`)**: 在后处理阶段，使用 `unclip_ratio = 1.5` 对核心区域进行扩张，得到最接近字符真实视觉高度的参考值。
- **公式**: `rawH = (maxY - minY) / 960.0`, `fittingH = (maxY + dist - (minY - dist)) / 960.0`

## 2. 渲染阶段 (RefinementPage)
在显示层，我们采用了类似于 Mac 版的“动态试算算法”，以确保不同文本长度下字号的稳定性。

### A. 获取目标高度 (Target Height)
将归一化的 `rawH` 映射到当前 UI 渲染区域的实际像素高度。
- `targetH = rawH * ScreenHeight`

### B. 虚拟试算 (TextPainter Probe)
由于不同字体的字高（Ascent/Descent）各异，我们使用 Flutter 的 `TextPainter` 进行 50 号字体的模拟渲染，获取其测量高度（`measuredHeight`）。

### C. 核心计算公式
最终字号由以下公式决定：

$$FontSize = 50.0 \times \left( \frac{targetH \times 1.1}{measuredHeight} \right) \times 1.2$$

#### 参数说明：
1. **1.1 (补偿系数)**: 
   由于 DBNet 检测的是文字核心（Kernel），通常只占字符实际高度的 80% 左右。1.1 的系数用于补偿这一差距，使文字边框更贴合真实字符。
2. **1.2 (用户偏好缩放)**: 
   根据您的反馈，我们将最终输出又放大了 20%，以达到“饱满”且符合原图感官的效果。
3. **宽度保护**: 
   算法会同时计算高度比例和宽度比例，取两者的**最小值**。这意味着如果文字内容过长，它会自动缩小字号以确保单行不换行。

## 3. 逻辑链路总结
`DBNet (Kernel Height)` -> `rawH (Normalized)` -> `targetH (UI Pixels)` -> `TextPainter试算` -> `FontSize (最终字号)`

---
*注：该逻辑确保了字号仅受原始文字高度影响，而不受我们为了擦除背景而手动扩张的“肥大文本框”影响。*
