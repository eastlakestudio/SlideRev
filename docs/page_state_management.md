# SlideRev 页面状态内存管理技术文档

本手册详细说明了 SlideRev (v0.9.9+) 中核心的“页面状态内存管理”机制。该机制旨在确保 PDF 页面在处理过程中，其原始数据、OCR 识别项、AI 重绘背景以及用户编辑状态能够在内存中高效流转并保持同步。

---

## 1. 核心数据结构 (Data Structures)

SlideRev 采用了三层嵌套的数据模型来实现页面状态的完全解耦。

### 1.1 PageState (顶层容器)
`PageState` 是每一页 PDF 在内存中的唯一状态容器。

```swift
struct PageState {
    var pageIndex: Int          // 0-based 索引
    var pdfPage: PDFPage?       // 对应的 PDFKit 页面引用
    var visualSize: CGSize      // 用于 UI 渲染的缩放后尺寸
    var raw: RawData            // 原始层（见 1.2）
    var refined: RefinedBundle  // 精炼层（见 1.3）
    var isOCRComplete: Bool = false
}
```

### 1.2 RawData (原始层)
存储不可变的原始图像数据。当 UI 需要“还原”或 PDF 导出需要基础像素时调用。

- `originalImage`: 用于展示的 `NSImage`。
- `baseCGImage`: 用于算法处理（OCR/Inpaint）的核心 `CGImage`。
- `pdfSize`: 原始 PDF 页面的点（points）尺寸。

### 1.3 RefinedBundle (精炼层)
存储所有经过处理或人工干预的动态数据。

- `background`: 执行 AI Inpainting（擦除）后的底图。
- `textLayers`: 包含所有 `RecognizedItem` 的数组，记录了文字内容、位置、颜色及“是否擦除”状态。
- `watermarkPattern`: 该页匹配到的全局水印模式。
- `isRefined`: 布尔标志位，标记该页是否已成功执行 AI 重绘。

---

## 2. 内存缓存机制 (Memory Cache)

`AdvancedSlideProcessor` 通过一个私有字典维护所有已处理页面的状态，实现“即时切换”。

```swift
private(set) var pages: [Int: PageState] = [:]
```

### 2.1 缓存优先加载策略 (Cache-First)
在切换页面（`switchToPage`）时，系统首先检索 `pages` 字典。
- **Cache Hit**: 直接解包 `PageState` 并更新 `@Published` 属性，UI 瞬间切换。
- **Cache Miss**: 调用 `processPage` 执行完整的渲染 -> OCR -> 缓存 流程。

---

## 2.3 UI 与缓存同步逻辑 (UI-Cache Bridge)

由于 SwiftUI 依赖于 `@Published` 属性驱动视图，而底层数据存储在 `pages` 中，因此需要维护双向同步：

### A. 从 UI 同步到缓存 (Push)
当用户在当前页执行操作（如：点击擦除文字、UNDO、手动编辑文字）时，调用 `syncCacheFromCurrentUI()`。
> [!IMPORTANT]
> 必须确保在切换到下一页或保存之前，将当前视觉状态（`recognizedItems`）回写到对应的 `pages[index].refined.textLayers` 中。

### B. 从缓存同步到 UI (Pull)
当切换回已处理页面时，调用 `syncUIFromCache(index:)`。
系统会将 `pages[index]` 中的 `textLayers` 赋值给 `@Published var recognizedItems`，触发 UI 刷新。

---

## 3. 批量静默处理 (Batch Silent Processing)

在 v0.9.8+ 版本中引入了“批量模式”，允许在不中断用户当前操作的情况下处理其他页面。

- **标志位**：`isBatchProcessing` (Bool)。
- **核心逻辑**：
    1. 使用 `processSilently` 进行异步 OCR，结果直接写入 `pages` 字典，而不修改全局的 `@Published` 变量。
    2. 使用 `refreshInpaintedBackgroundSilently` 执行后台 AI 重绘。
- **优势**：避免了在处理非当前页时导致的 UI 闪烁或状态污染。

---

## 4. 持久化与快照 (Persistence & Snapshots)

### 4.1 序列化方案
`SessionData` 结构体用于将内存中的元数据持久化为 JSON 文件。

- **保存 (`saveSession`)**：抽取 `pages` 中的任务关键数据（文字层、Refined 状态）进行编码。
- **加载 (`loadSession`)**：执行 **Deep Merge**。如果内存中已有页面，则仅更新 metadata；如果缺失，则重建 placeholder。

### 4.2 Undo 机制
```swift
private var undoStack: [([RecognizedItem], NSImage?)] = []
```
每次关键修改前，系统会将当前的文字数组和底图快照存入堆栈。执行 `undo()` 时，会从堆栈弹出并重新执行 UI-Cache 同步。

---

## 5. 开发建议

> [!TIP]
> 1. **频繁同步**：在执行任何可能导致数据丢失的操作（如：批量重绘）前，先调用 `syncCacheFromCurrentUI()`。
> 2. **异步队列**：所有涉及 `baseCGImage` 的计算应在 `DispatchQueue.global(qos: .userInitiated)` 中执行，完成后回主线程更新。
> 3. **内存管理**：对于超长文档，可以考虑在 `clearAllStates` 中释放不常用的 `baseCGImage`。
