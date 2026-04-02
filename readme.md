# 🎯 角色与项目愿景

你是一位精通 Swift、macOS 原生底层框架（如 Vision, CoreImage）以及底层文件系统机制的资深苹果生态架构师。
我的终极目标是开发一款名为 "SlideReverse" 的 macOS 原生应用程序，并最终上架 Mac App Store (MAS) 采用应用内购买 (IAP) 变现。
该应用的功能是将包含幻灯片的 PDF 文件逆向转换为“背景干净、文字可编辑”的 PPTX 文件。

考虑到设备内存（需完美向下兼容 8GB 内存的 Mac 环境）以及苹果严苛的 App Sandbox 沙盒审查机制，我们必须 100% 抛弃庞大的 Python 机器学习库和复杂的 C++ 动态库。

# 🛑 核心指令：技术先行验证 (PoC)

为了规避项目风险，在编写任何 SwiftUI 界面代码之前，**你必须先作为 Agent 自主完成以下三个核心技术点的技术验证 (Proof of Concept)**。请逐一编写核心 Swift 函数/类，并评估其可行性。

## 🧪 PoC 1: 原生 Vision OCR 与排版特征提取

- **技术栈**：使用内置的 `Vision` 框架 (`VNRecognizeTextRequest`)。
- **验证目标**：读取一张测试图片，提取文字内容，并根据 `VNRecognizedTextObservation` 返回的四个顶点坐标（`topLeft`, `topRight`, `bottomLeft`, `bottomRight`），计算并输出：
  1. 文本框的准确中心坐标 (x, y)。
  2. 文本块的宽度和高度（用于后续换算 PPT 字号）。
  3. 文本的倾斜角度（通过反三角函数计算）。
- **加分项**：利用 `CoreGraphics`，在计算出的中心点坐标处，获取原图该位置的 RGB 颜色值。

## 🧪 PoC 2: 轻量级原生背景修复 (Inpainting)

- **技术栈**：使用 `CoreImage` 框架。
- **验证目标**：在不引入外部库的前提下，仅利用苹果原生的滤镜组合（例如形态学滤镜 `CIMorphologyMaximum` 结合区域模糊 `CIGaussianBlur`），处理一张带有文字掩码 (Mask) 的图片，实现文字区域的擦除与周围背景色的粗略融合补全。
- **业务妥协**：我们接受复杂背景处修复效果的“不完美”和涂抹感，核心诉求是跑通这条零外部依赖、极低内存消耗的纯原生处理管线。

## 🧪 PoC 3: "Hack" 方式的 PPTX 逆向生成

- **背景**：Swift 生态缺乏完美操作 PPTX 的原生库。而 `.pptx` 本质上是一个包含 XML 文件的 ZIP 压缩包。
- **验证目标**：通过原生 `Foundation` (或极轻量的 `ZIPFoundation`) 进行文件读写与解压缩：
  1. 在代码中解压一个包含单页空白幻灯片的 `template.pptx`。
  2. 使用 Swift 的字符串操作或 `XMLParser`，强行修改 `ppt/slides/slide1.xml`。
  3. 在 XML 结构中注入一个带有特定文本和坐标的 Text Box 节点。
  4. 重新 ZIP 压缩回 `.pptx` 格式，并确保产物能被 macOS 的 Keynote 或 PowerPoint 正常打开。

# 🚀 Agent 执行步骤

1. 请不要一开始就搭建完整的 App 框架或写 UI！
2. 请依次输出上述三个 PoC 的核心 Swift 代码实现。
3. 针对每一个 PoC，给出你对于其性能开销、内存占用以及沙盒合规性的专业评估。
4. 等我确认这三个硬骨头都被啃下来后，我们再进入下一步的完整 SwiftUI 架构整合。请立即开始 PoC 1 的代码编写与评估。
