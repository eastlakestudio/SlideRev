import Foundation
import Vision
import CoreImage
import PDFKit
import CoreGraphics
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

class AdvancedSlideProcessor: ObservableObject {
    
    enum ItemViewState: Int, Codable {
        case original = 0  // 原始：保留底图文字，不绘制新层
        case cleaned = 1   // 仅背景：擦除底图文字，但不显示新层
        case refined = 2   // 最终还原：擦除底图文字，并渲染重绘出的文本
    }

    @Published var preferredViewState: ItemViewState = .refined

    struct RecognizedItem: Identifiable, Equatable, Codable {
        var id = UUID()
        let text: String
        var editedText: String
        var rect: CGRect 
        var pixelRect: CGRect 
        var charRects: [CGRect] = []
        var fontSize: CGFloat 
        var fontName: String = "Helvetica"
        var colorComponents: [CGFloat]
        var isBold: Bool = false
        var rotation: Double = 0.0 
        var isVisible: Bool = true
        var viewState: ItemViewState = .original
        var isManualEraser: Bool = false
        var refinementProgress: Double = 0.0 // 🚀 V0.9.9.22: Progress for horizontal scan animation (0.0 to 1.0)
        /// 🆕 Paragraph Grouping: 标记该 item 所属的段落合并组，由 ParagraphGrouper 在 OCR 后写入
        var groupId: UUID? = nil
        var textAlignment: String = "l" // "l", "ctr", "r"
        
        var isErased: Bool { viewState != .original }
        var isTextVisible: Bool { viewState == .refined }
        
        var color: CGColor {
            get { 
                // 🚀 核心修复：必须确保有4个分量，否则会 Index Out of Range
                let comps = colorComponents.count >= 4 ? colorComponents : [0,0,0,1]
                return CGColor(red: comps[0], green: comps[1], blue: comps[2], alpha: comps[3])
            }
            set { 
                // 🚀 核心修复：存储时统一转为 sRGB 空间，确保 4 分量
                if let converted = newValue.converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil) {
                    colorComponents = converted.components ?? [0,0,0,1]
                } else {
                    colorComponents = newValue.components ?? [0,0,0,1]
                }
            }
        }

        enum CodingKeys: String, CodingKey {
            case id, text, editedText, rect, pixelRect, charRects, fontSize, fontName, colorComponents, isBold, rotation, isVisible, viewState, isManualEraser, groupId, textAlignment
        }
        
        init(text: String, editedText: String, rect: CGRect, pixelRect: CGRect, charRects: [CGRect], fontSize: CGFloat, color: CGColor, viewState: ItemViewState = .original, isManualEraser: Bool = false, isBold: Bool = false, groupId: UUID? = nil, textAlignment: String = "l") {
            self.text = text; self.editedText = editedText; self.rect = rect; self.pixelRect = pixelRect
            self.charRects = charRects; self.fontSize = fontSize
            let rgbColor = color.converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil) ?? color
            self.colorComponents = rgbColor.components ?? [0,0,0,1]
            if self.colorComponents.count < 4 { self.colorComponents = [0,0,0,1] }
            self.viewState = viewState
            self.isManualEraser = isManualEraser
            self.refinementProgress = (viewState != .original) ? 1.0 : 0.0 // Set initial progress based on erased state
            self.isBold = isBold
            self.groupId = groupId
            self.textAlignment = textAlignment
        }
    }


    // MARK: - PageState: Full data structure for each page
    // MARK: - V0.9.9: Structured Layer Model
    /// 🚀 V39.0: Single-Active-Page Bitmap Model (Choices 2: Low-Memory, Robust)
    /// High-res bitmaps are held ONLY for the current page and cleared on navigation.

    struct RawData: Codable {
        var pdfSize: CGSize = .zero
        
        enum CodingKeys: String, CodingKey {
            case pdfSize
        }
    }
    
    struct RefinedBundle: Codable {
        var textLayers: [RecognizedItem]  // 用户可操作的文字层
        var watermarkPattern: String?     // 指向该页应用的匹配模式
        var isRefined: Bool = false       // 是否已成功执行 AI 重绘
        var ocrThresholdUsed: Float? = nil 
 
        enum CodingKeys: String, CodingKey {
            case textLayers, watermarkPattern, isRefined, ocrThresholdUsed
        }
    }

    struct PageState: Codable {
        var pageIndex: Int
        var visualSize: CGSize = .zero
        var raw: RawData
        var refined: RefinedBundle
        var isOCRComplete: Bool = false
        
        enum CodingKeys: String, CodingKey {
            case pageIndex, visualSize, raw, refined, isOCRComplete
        }
    }

    @Published var recognizedItems: [RecognizedItem] = []
    @Published var inpaintedImage: NSImage?
    @Published var originalImage: NSImage?
    @Published var totalPageCount: Int = 0
    @Published var currentPageIndex: Int = 0 
    
    // 🚀 V55.0: Blocking Pre-warm State
    @Published var isDocumentReady: Bool = false
    @Published var preWarmedCount: Int = 0
    
    // 🚀 v39.0: Concurrency & Safety - Task Versioning
    @Published var activeSessionID = UUID()

    // 🚀 V27.9.3: Explicit Document Reference 
    @Published var activeDocument: PDFDocument?
    @Published var isDirty: Bool = false
    @Published var isRefining: Bool = false 
    @Published var isRefinementFinalized: Bool = false
    @Published var hoverItemId: UUID? = nil
    @Published var currentlyPreWarmingImage: NSImage? = nil // 🚀 V39.8: Visual Pre-warm Feedback
    @Published var isBatchProcessing: Bool = false
    @Published var batchProgress: (current: Int, total: Int) = (0, 0)
    @Published var batchStatus: String = "Idle"
    @Published var currentFileName: String? = nil
    @Published var isExporting: Bool = false // 🚀 V39.9: Track global exporting state
    
    // 🚀 V39.7: Task Lifecycle Management
    private var preWarmTask: Task<Void, Never>?
    private var currentPageTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private let cache = SlideImageCache.shared
    
    /// 🚀 V55.0: Simplified Unified Rendering Helper
    private func renderPageThumbnail(at index: Int, resolution: CGSize) -> CGImage? {
        guard let page = self.activeDocument?.page(at: index) else { return nil }
        let thumb = page.thumbnail(of: resolution, for: .mediaBox)
        return thumb.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    func startPreWarmSequence(doc: PDFDocument) {
        preWarmTask?.cancel()
        
        // 🚀 Synchronous Reset: Prevent UI from seeing 'Ready' from previous sessions
        self.activeDocument = doc // 🚀 BINGO: Added missing document initialization
        self.isDocumentReady = false
        self.preWarmedCount = 0
        self.currentlyPreWarmingImage = nil
        
        // 🚀 V39.9: Capture filename from URL if available
        if let url = doc.documentURL {
            self.currentFileName = url.lastPathComponent
        }
        
        preWarmTask = Task(priority: .utility) {
            let total = doc.pageCount
            for i in 0..<total {
                guard !Task.isCancelled else { break }
                await preWarmPage(at: i, doc: doc)
                
                await MainActor.run {
                    self.preWarmedCount = i + 1
                }
            }
            
            await MainActor.run {
                self.isDocumentReady = true
                self.currentlyPreWarmingImage = nil
                self.switchToPage(index: 0) // Auto-enter first page
            }
        }
    }
    
    // 🚀 v39.8: Sequential Pre-warming (OCR + Background Inpainting)
    // Refactored to async for strictly ordered execution and visual sync.
    private func preWarmPage(at index: Int, doc: PDFDocument) async {
        guard let page = doc.page(at: index) else { return }
        
        let rotation = page.rotation
        let rawBounds = page.bounds(for: .mediaBox)
        var bounds = rawBounds
        if rotation == 90 || rotation == 270 {
            bounds = CGRect(x: 0, y: 0, width: rawBounds.height, height: rawBounds.width)
        }
        
        let scale: CGFloat = 200.0 / 72.0
        let pixelSize = CGSize(width: round(bounds.width * scale), height: round(bounds.height * scale))
        let cacheKey = "bg_\(index)_\(Int(pixelSize.width))x\(Int(pixelSize.height))"
        
        // 🚀 Always push the thumbnail for visual carousel immediately
        if let cg = renderPageThumbnail(at: index, resolution: pixelSize) {
            let thumb = NSImage(cgImage: cg, size: pixelSize)
            await MainActor.run { self.currentlyPreWarmingImage = thumb }
        }
        
        // 1. Initial Metadata / OCR
        var isOCRComplete = getPage(at: index)?.isOCRComplete ?? false
        var currentItems = getPage(at: index)?.refined.textLayers ?? []
        
        if !isOCRComplete {
            if let cg = renderPageThumbnail(at: index, resolution: pixelSize) {
                
                let rawItems = await self.performOCR(on: cg, pixelSize: pixelSize)
                let items = ParagraphGrouper.groupAndMerge(items: rawItems)
                
                currentItems = items
                isOCRComplete = true
                
                let pageState = PageState(
                    pageIndex: index, visualSize: pixelSize,
                    raw: RawData(pdfSize: bounds.size),
                    refined: RefinedBundle(textLayers: items, watermarkPattern: nil, isRefined: false, ocrThresholdUsed: nil),
                    isOCRComplete: true
                )
                self.setPage(at: index, pageState)
            }
        }
        
        // 2. Background Inpainting (Strictly sequential)
        if !currentItems.isEmpty {
            if let base = renderPageThumbnail(at: index, resolution: pixelSize),
               let cleaned = syncInpaint(image: base, items: currentItems) {
                let cleanedNS = NSImage(cgImage: cleaned, size: pixelSize)
                SlideImageCache.shared.store(cleanedNS, for: cacheKey)
                
                // Only mark as Refined AFTER successful cache store
                updatePage(at: index) { p in
                    p.refined.isRefined = true
                }
            }
        }
    }
    
    // ML/AI Inpainter for watermark removal
    static let defaultOCRThreshold: Float = 0.20
    @Published var ocrConfidenceThreshold: Float = defaultOCRThreshold
    /// 🚀 批量处理标志：true 时 processPage 不更新 UI，只写缓存
    // var isBatchProcessing: Bool = false // Removed redeclaration
    
    // 核心數據：每頁完整狀態 (Thread-Safe Access via pagesLock)
    private var _pages: [Int: PageState] = [:]
    private let pagesLock = NSLock() // 🚀 V37.22: 原子锁 - 保护核心字典，防止并发读写崩溃
    
    /// Thread-safe getter for a specific page state
    func getPage(at index: Int) -> PageState? {
        pagesLock.lock()
        defer { pagesLock.unlock() }
        return _pages[index]
    }
    
    /// Thread-safe update for a specific page state
    func updatePage(at index: Int, action: (inout PageState) -> Void) {
        pagesLock.lock()
        let page = _pages[index]
        if var p = page {
            action(&p)
            _pages[index] = p
        }
        pagesLock.unlock()
    }
    
    /// Thread-safe setter for a whole page (use carefully)
    func setPage(at index: Int, _ state: PageState) {
        pagesLock.lock()
        _pages[index] = state
        pagesLock.unlock()
    }

    /// Publicly accessible indices (thread-safe)
    var pageIndices: [Int] {
        pagesLock.lock()
        defer { pagesLock.unlock() }
        return Array(_pages.keys).sorted()
    }

    /// 🚀 V37.23: Thread-safe snapshot of all pages - returns a copy of the dictionary
    var pages: [Int: PageState] {
        pagesLock.lock()
        defer { pagesLock.unlock() }
        return _pages
    }

    private var undoStack: [([RecognizedItem], NSImage?)] = []
    private let context = CIContext()
    private let inpainter: NeuralInpainter = {
        // 1. App Bundle (Standard macOS Resource)
        if let bundleURL = Bundle.main.url(forResource: "LaMa", withExtension: "mlmodelc") {
            return NeuralInpainter(modelURL: bundleURL)
        }
        
        // 2. Resolve relative to the source file (Development environment using #file)
        // This works because the app is being run on the same machine where it was compiled.
        let sourceURL = URL(fileURLWithPath: #file)
        let projectRoot = sourceURL
            .deletingLastPathComponent() // SlideRev/
            .deletingLastPathComponent() // Sources/
            .deletingLastPathComponent() // root/
        
        let devPath = projectRoot.appendingPathComponent("3rd/coremlama/LaMa.mlmodelc")
        if FileManager.default.fileExists(atPath: devPath.path) {
            return NeuralInpainter(modelURL: devPath)
        }

        // 3. Last fallback to hardcoded relative path (Current Working Directory)
        let fallbackPath = "3rd/coremlama/LaMa.mlmodelc"
        return NeuralInpainter(modelURL: URL(fileURLWithPath: fallbackPath))
    }()
    private var baseCGImage: CGImage?  // 当前頁的 CGImage
    private var currentOCRRequestId: Int = 0 // 🚀 V0.9.9.45: 并发控制 - 识别请求版本号
    
    // MARK: - Persistence (V0.9.6.22)
    struct SessionData: Codable {
        let pages: [Int: PageSession]
        let globalPatterns: [String]
    }
    
    struct PageSession: Codable {
        let recognizedItems: [RecognizedItem]
        let isRefined: Bool
    }
    
    func saveSession(to url: URL) {
        let indices = pageIndices
        var sessionPages: [Int: PageSession] = [:]
        for idx in indices {
            if let p = getPage(at: idx) {
                sessionPages[idx] = PageSession(recognizedItems: p.refined.textLayers, isRefined: p.refined.isRefined)
            }
        }
        let session = SessionData(pages: sessionPages, globalPatterns: [])
        do {
            let data = try JSONEncoder().encode(session)
            try data.write(to: url)
        } catch {
        }
    }
    
    func loadSession(from url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let session = try JSONDecoder().decode(SessionData.self, from: data)
            // 🚀 V58.8: Global patterns are no longer stored/loaded to enforce independence
            
            // 🚀 Deep merge: we update the metadata. 
            // The actual images will be re-processed or loaded from the original PDF on demand.
            for (index, pageSession) in session.pages {
                if var existing = getPage(at: index) {
                    existing.refined.textLayers = pageSession.recognizedItems
                    existing.refined.isRefined = pageSession.isRefined
                    setPage(at: index, existing)
                } else {
                    setPage(at: index, PageState(
                        pageIndex: index,
                        visualSize: .zero,
                        raw: RawData(pdfSize: .zero),
                        refined: RefinedBundle(textLayers: pageSession.recognizedItems, watermarkPattern: nil, isRefined: pageSession.isRefined, ocrThresholdUsed: nil),
                        isOCRComplete: true
                    ))
                }
            }
            self.isDirty = false
        } catch {
        }
    }

    // 🚀 V0.9.6.20: Clear all internal states (important for opening new documents)
    func clearAllStates() {
        pagesLock.lock()
        _pages.removeAll()
        pagesLock.unlock()
        
        DispatchQueue.main.async {
            self.recognizedItems.removeAll()
            self.undoStack.removeAll()
            self.isDirty = false
            self.currentPageIndex = 0
            self.totalPageCount = 0
            // 🚀 V53.0: Atomically reset images if needed, but not individually during navigation
            self.baseCGImage = nil
            self.originalImage = nil
            self.inpaintedImage = nil
        }
    }

    // 🚀 V31.0: MEMORY GOVERNANCE - Clear all cached images and session data
    func clearCache() {
        pagesLock.lock()
        _pages.removeAll()
        pagesLock.unlock()
        
        DispatchQueue.main.async {
            self.clearUndoStack() 
            self.recognizedItems.removeAll()
            self.originalImage = nil
            self.baseCGImage = nil
            self.inpaintedImage = nil
            self.activeDocument = nil 
            self.isRefinementFinalized = false
            self.preWarmedCount = 0
            self.totalPageCount = 0
            self.currentPageIndex = 0
        }
    }
    
    // 🚀 V33.0: Atomic cleanup for batch processing
    func clearUndoStack() {
        self.undoStack.removeAll()
    }

    private func saveSnapshot() {
        undoStack.append((recognizedItems, inpaintedImage))
        if undoStack.count > 20 { undoStack.removeFirst() }
    }
    
    func undo() {
        guard let last = undoStack.popLast() else { return }
        DispatchQueue.main.async { 
            self.recognizedItems = last.0; self.inpaintedImage = last.1 
            self.syncCacheFromCurrentUI() // 🚀 V0.9.8.31: Keep cache aligned on undo
        }
    }
    
    /// 🚀 UI-Cache Bridge: Ensure current visual state is synced to the underlying page store
    private func syncCacheFromCurrentUI() {
        updatePage(at: currentPageIndex) { p in
            p.refined.textLayers = self.recognizedItems
        }
    }
    
    /// 🚀 UI-Cache Bridge: Refresh the UI (@Published) array from the target page cache
    private func syncUIFromCache(index: Int) {
        guard index == currentPageIndex, let cached = getPage(at: index) else { return }
        DispatchQueue.main.async {
            self.recognizedItems = cached.refined.textLayers
        }
    }
    
    /// Core Entry: Switch current page (v55.0 Deterministic Flow)
    func switchToPage(index: Int, from document: PDFDocument? = nil) {
        currentPageTask?.cancel()
        let session = UUID()
        self.activeSessionID = session
        self.currentPageIndex = index 
        
        // 🚀 v56.4: Safety Sync
        if let doc = document { self.activeDocument = doc }
        
        currentPageTask = Task {
            guard let pageState = getPage(at: index),
                  let doc = self.activeDocument,
                  index < doc.pageCount else { return }
            
            let pixelSize = pageState.visualSize
            let cacheKey = "bg_\(index)_\(Int(pixelSize.width))x\(Int(pixelSize.height))"
            
            // 1. Render Original
            guard let cg = renderPageThumbnail(at: index, resolution: pixelSize), !Task.isCancelled else { return }
            let originalImg = NSImage(cgImage: cg, size: pixelSize)
            
            // 2. Fetch Inpainted (Should be in cache due to blocking pre-warm)
            let cachedBG: NSImage? = await withCheckedContinuation { (continuation: CheckedContinuation<NSImage?, Never>) in
                cache.retrieve(for: cacheKey) { continuation.resume(returning: $0) }
            }
            
            // 🚀 V58.9: REMOVED global preference override. 
            // We now strictly respect the per-page state stored in the cache. 
            // This fixes the "Reset jump-back" issue and aligns with "No Sharing" philosophy.
            let finalItems = pageState.refined.textLayers

            await commitPageUpdate(
                index: index, 
                session: session, 
                base: cg, 
                original: originalImg, 
                inpainted: cachedBG ?? originalImg, // Fallback to original if cache missing (shouldn't happen with blocking)
                items: finalItems, 
                isFinalized: pageState.refined.isRefined
            )
        }
    }

    // 🚀 V55.2: Unified Async OCR
    private func performOCR(on cgImage: CGImage, pixelSize: CGSize) async -> [RecognizedItem] {
        let threshold = self.ocrConfidenceThreshold
        return await withCheckedContinuation { continuation in
            let ocrRequest = VNRecognizeTextRequest { (request, error) in
                if let _ = error { continuation.resume(returning: []); return }
                guard let observations = request.results as? [VNRecognizedTextObservation] else { continuation.resume(returning: []); return }
                
                var items: [RecognizedItem] = []
                for obs in observations {
                    guard let top = obs.topCandidates(1).first else { continue }
                    guard top.confidence >= threshold, top.string.count >= 1 else { continue }
                    let visionRect = obs.boundingBox
                    let normalizedRect = CGRect(x: visionRect.origin.x, y: 1.0 - visionRect.origin.y - visionRect.size.height, width: visionRect.size.width, height: visionRect.size.height * 1.05)
                    let pixelRect = CGRect(x: normalizedRect.origin.x * pixelSize.width, y: normalizedRect.origin.y * pixelSize.height, width: normalizedRect.size.width * pixelSize.width, height: normalizedRect.size.height * pixelSize.height)
                    
                    let charRects = self.extractEraseRects(from: top, fullBox: obs.boundingBox, pixelSize: pixelSize)
                    let fontSize = self.calculateFittingFontSize(text: top.string, fontName: "Helvetica", targetWidth: pixelRect.width, targetHeight: pixelRect.height)
                    let itemColor = self.samplePrimaryColor(cgImage: cgImage, rect: pixelRect, imageHeight: pixelSize.height)
                    
                    items.append(RecognizedItem(text: top.string, editedText: top.string, rect: normalizedRect, pixelRect: pixelRect, charRects: charRects, fontSize: fontSize, color: itemColor, viewState: .refined, isBold: false))
                }
                // 返回原始单行 items；段落合并在 refinePage() 中执行
                continuation.resume(returning: items)
            }
            ocrRequest.recognitionLevel = .accurate
            ocrRequest.recognitionLanguages = ["zh-Hans", "en-US"]
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([ocrRequest])
        }
    }
    
    // MARK: - Helpers for OCR and Inpainting
    private func containsCJK(_ text: String) -> Bool {
        return text.unicodeScalars.contains { scalar in
            (scalar.value >= 0x4E00 && scalar.value <= 0x9FFF) || // Unified
            (scalar.value >= 0x3400 && scalar.value <= 0x4DBF) || // Ext A
            (scalar.value >= 0x3040 && scalar.value <= 0x309F) || // Hiragana
            (scalar.value >= 0x30A0 && scalar.value <= 0x30FF) || // Katakana
            (scalar.value >= 0xAC00 && scalar.value <= 0xD7AF)    // Hangul
        }
    }
    
    private func extractEraseRects(from top: VNRecognizedText, fullBox: CGRect, pixelSize: CGSize) -> [CGRect] {
        let text = top.string
        let isCJK = containsCJK(text)
        var rects: [CGRect] = []
        
        if isCJK {
            // CJK: Character-level extraction
            for i in 0..<text.count {
                let range = text.index(text.startIndex, offsetBy: i)..<text.index(text.startIndex, offsetBy: i+1)
                if let box = try? top.boundingBox(for: range) {
                    let vRect = box.boundingBox
                    let norm = CGRect(x: vRect.origin.x, y: 1.0 - vRect.origin.y - vRect.size.height, width: vRect.size.width, height: vRect.size.height)
                    rects.append(CGRect(x: norm.origin.x * pixelSize.width, y: norm.origin.y * pixelSize.height, width: norm.size.width * pixelSize.width, height: norm.size.height * pixelSize.height))
                }
            }
        } else {
            // Alphabetic: Full String Range (🚀 Fixed: Including symbols and punctuation)
            // 针对英文直接获取全文字串范围的包围盒，确保括号 ()、分号 ; 等符号被完整覆盖。
            if let box = try? top.boundingBox(for: text.startIndex..<text.endIndex) {
                let union = box.boundingBox
                let norm = CGRect(x: union.origin.x, y: 1.0 - union.origin.y - union.size.height, width: union.size.width, height: union.size.height)
                // 🚀 V0.9.9.32: 加固 Padding 参数，既能遮住笔画，又能防止背景溢出
                let paddedNorm = norm.insetBy(dx: -norm.width * 0.012, dy: -norm.height * 0.035)
                rects.append(CGRect(x: paddedNorm.origin.x * pixelSize.width, y: paddedNorm.origin.y * pixelSize.height, width: paddedNorm.size.width * pixelSize.width, height: paddedNorm.size.height * pixelSize.height))
            }
        }
        
        if rects.isEmpty {
            let vRect = fullBox
            let norm = CGRect(x: vRect.origin.x, y: 1.0 - vRect.origin.y - vRect.size.height, width: vRect.size.width, height: vRect.size.height * 1.05)
            rects = [CGRect(x: norm.origin.x * pixelSize.width, y: norm.origin.y * pixelSize.height, width: norm.size.width * pixelSize.width, height: norm.size.height * pixelSize.height)]
        }
        return rects
    }

    private func samplePrimaryColor(cgImage: CGImage, rect: CGRect, imageHeight: CGFloat) -> CGColor {
        // 🚀 核心修復：確保與 Mask 相同的 Y 軸翻轉邏輯
        let flippedY = imageHeight - rect.origin.y - rect.size.height
        let flippedRect = CGRect(x: rect.origin.x, y: flippedY, width: rect.size.width, height: rect.size.height)
        
        guard let pixels = getPixelData(from: cgImage, rect: flippedRect), pixels.count >= 4 else {
            return NSColor.black.cgColor
        }
        
        let w = Int(flippedRect.width)
        let h = Int(flippedRect.height)
        
        // 1. 採樣邊緣像素估計背景色
        var bgR: Double = 0, bgG: Double = 0, bgB: Double = 0, count: Double = 0
        for x in 0..<w {
            for y in [0, h-1] {
                let i = (y * w + x) * 4
                if i + 2 < pixels.count {
                    bgR += Double(pixels[i]); bgG += Double(pixels[i+1]); bgB += Double(pixels[i+2]); count += 1
                }
            }
        }
        let avgBg = (r: bgR/count, g: bgG/count, b: bgB/count)
        
        // 2. 尋找與背景對比度最大的像素（文字色）
        var maxDist: Double = -1
        var bestColor = NSColor.black.cgColor
        
        for x in stride(from: 0, to: w, by: 2) {
            for y in stride(from: 0, to: h, by: 2) {
                let i = (y * w + x) * 4
                if i + 2 < pixels.count {
                    let r = Double(pixels[i]), g = Double(pixels[i+1]), b = Double(pixels[i+2])
                    let dist = pow(r - avgBg.r, 2) + pow(g - avgBg.g, 2) + pow(b - avgBg.b, 2)
                    if dist > maxDist {
                        maxDist = dist
                        bestColor = NSColor(red: r/255.0, green: g/255.0, blue: b/255.0, alpha: 1.0).cgColor
                    }
                }
            }
        }
        return bestColor
    }

    private func getPixelData(from cgImage: CGImage, rect: CGRect) -> [UInt8]? {
        let w = Int(max(1, rect.width)), h = Int(max(1, rect.height))
        var data = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: -rect.origin.x, y: -rect.origin.y, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
        return data
    }

    static func fileLog(_ message: String) {
        let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("SlideRev_Trace.log")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logURL) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: logURL)
            }
        }
        print(message)
    }

    // MARK: - 重置当前页（清除 refine 结果，从原始重新开始）
    func resetPage(at index: Int) {
        let session = self.activeSessionID
        updatePage(at: index) { page in
            print("♻️ [resetPage] 第\(index+1)頁已重置 (保留文字层，清除精炼结果)")
            
            // 1. Reset Refined Bundle
            page.refined.isRefined = false
            page.refined.watermarkPattern = ""
            
            // 2. Reset Text Layers states
            for i in 0..<page.refined.textLayers.count {
                page.refined.textLayers[i].viewState = .original
                page.refined.textLayers[i].editedText = page.refined.textLayers[i].text // Restore original OCR
                page.refined.textLayers[i].isManualEraser = false
                page.refined.textLayers[i].refinementProgress = 0.0
            }
        }
        
        // 3. UI Sync (if current)
        if index == self.currentPageIndex {
            DispatchQueue.main.async {
                self.isDirty = false
                
                // 🚀 V53.0: Atomic Refresh using commitPageUpdate
                guard let currentCG = self.baseCGImage, let originalImg = self.originalImage else { return }
                let items = self.getPage(at: index)?.refined.textLayers ?? []
                
                Task {
                    await self.commitPageUpdate(
                        index: index, session: session,
                        base: currentCG, original: originalImg,
                        inpainted: nil, // 🚀 V58.0: CRITICAL - Clear inpaint to prevent ghosting
                        items: items,
                        isFinalized: false
                    )
                }
            }
        }
        
        // 🚀 V58.1: Always clear image cache for this page since we reset it, regardless of focus
        if let page = self.getPage(at: index) {
            let pixelSize = page.visualSize
            let cacheKey = "bg_\(index)_\(Int(pixelSize.width))x\(Int(pixelSize.height))"
            SlideImageCache.shared.remove(for: cacheKey)
            
            // Clear current published state if we are still on this page
            if index == self.currentPageIndex {
                DispatchQueue.main.async {
                    self.inpaintedImage = nil
                }
            }
        }
    }
    /// 🚀 V55.2: Atomic Background Refresh (Sequential)
    private func refreshCurrentPageBackground() async {
        let index = currentPageIndex
        let session = self.activeSessionID
        
        guard let pageState = getPage(at: index) else { return }
        let pixelSize = pageState.visualSize
        let cacheKey = "bg_\(index)_\(Int(pixelSize.width))x\(Int(pixelSize.height))"
        let currentItems = self.recognizedItems
        
        // 1. Perform Inpaint (Strictly Sequential)
        if let cg = renderPageThumbnail(at: index, resolution: pixelSize),
           let cleaned = syncInpaint(image: cg, items: currentItems) {
            
            let cleanedNS = NSImage(cgImage: cleaned, size: pixelSize)
            SlideImageCache.shared.store(cleanedNS, for: cacheKey)
            
            // 2. Update Metadata
            updatePage(at: index) { p in
                p.refined.textLayers = currentItems
                p.refined.isRefined = true
            }
            
            // 3. ATOMIC UI Update
            await commitPageUpdate(
                index: index, session: session,
                base: cg, original: NSImage(cgImage: cg, size: pixelSize),
                inpainted: cleanedNS, items: currentItems, isFinalized: true
            )
        }
    }

    /// 🚀 V39.9: Atomic Refine Logic (In-Sync Background + Text)
    func refinePage() async {
        await MainActor.run {
            self.isRefining = true
            self.saveSnapshot()
        }
        
        let session = self.activeSessionID
        let index = self.currentPageIndex
        let pixelSize = self.getPage(at: index)?.visualSize ?? CGSize(width: 800, height: 600)
        
        guard let base = renderPageThumbnail(at: index, resolution: pixelSize) else { 
            await MainActor.run { self.isRefining = false }
            return 
        }

        // 🚀 V58.6: DYNAMIC OCR RE-SCAN
        // 1. Perform fresh OCR using current user-defined threshold
        let freshItems = await performOCR(on: base, pixelSize: pixelSize)

        // 🆕 Paragraph Merging: Refine 阶段执行段落合并，多行以 \n 分隔
        let mergedItems = ParagraphGrouper.groupAndMerge(items: freshItems)

        // 2. Prepare items for refined state
        let targetItems = mergedItems.map { item -> RecognizedItem in
            var newItem = item
            newItem.viewState = .refined
            return newItem
        }
        
        // 3. Perform background inpainting with the NEW items
        let cleanedCG = syncInpaint(image: base, items: targetItems)
        
        // 4. ATOMIC COMMIT: Update UI AND Cache simultaneously
        await MainActor.run {
            guard session == self.activeSessionID && index == self.currentPageIndex else { return }
            
            self.recognizedItems = targetItems
            
            if let cg = cleanedCG {
                let cleanedNS = NSImage(cgImage: cg, size: pixelSize)
                self.inpaintedImage = cleanedNS
                
                // 5. Update Cache for export consistency (Immediate persistence)
                let cacheKey = "bg_\(index)_\(Int(pixelSize.width))x\(Int(pixelSize.height))"
                SlideImageCache.shared.store(cleanedNS, for: cacheKey)
            } else {
                self.inpaintedImage = nil
            }
            
            self.updatePage(at: index) { p in
                p.refined.textLayers = targetItems
                p.refined.isRefined = (cleanedCG != nil)
                p.refined.ocrThresholdUsed = Float(self.ocrConfidenceThreshold)
            }
            
            self.preferredViewState = .refined 
            self.isRefining = false
            self.isDirty = true
            self.objectWillChange.send()
        }
    }

    func cycleItemState(id: UUID) {
        guard let index = recognizedItems.firstIndex(where: { $0.id == id }) else { return }
        let current = recognizedItems[index].viewState
        let next: ItemViewState
        switch current {
            case .original: next = .cleaned
            case .cleaned: next = .refined
            case .refined: next = .original
        }
        
        saveSnapshot()
        withAnimation(.easeInOut(duration: 0.3)) {
            recognizedItems[index].viewState = next
            recognizedItems[index].refinementProgress = (next != .original) ? 1.0 : 0.0
            isDirty = true
            objectWillChange.send()
        }
        Task { await refreshCurrentPageBackground() }
    }
    
    func batchSetViewState(to state: ItemViewState) {
        saveSnapshot()
        self.preferredViewState = state // 🚀 V39.9: Persist preference globally
        for i in 0..<recognizedItems.count {
            recognizedItems[i].viewState = state
            recognizedItems[i].refinementProgress = (state != .original) ? 1.0 : 0.0
        }
        isDirty = true
        objectWillChange.send()
        Task { await refreshCurrentPageBackground() }
    }

    func eraseItem(id: UUID) {
        cycleItemState(id: id)
    }

    func getHydratedImages(for index: Int) -> (base: CGImage?, refined: CGImage?) {
        guard let pageState = getPage(at: index),
              self.activeDocument != nil else { return (nil, nil) }
        
        let pixelSize = pageState.visualSize
        guard let baseCG = renderPageThumbnail(at: index, resolution: pixelSize) else { return (nil, nil) }
        
        if !pageState.refined.isRefined { return (baseCG, baseCG) }
        
        // 🚀 V58.0: PERFORMANCE FIX - Synchronous Cache Retrieval (Simplified)
        let cacheKey = "bg_\(index)_\(Int(pixelSize.width))x\(Int(pixelSize.height))"
        if let cachedNS = SlideImageCache.shared.retrieveSync(for: cacheKey),
           let cached = cachedNS.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return (baseCG, cached)
        }
        
        // Fallback to inpainting and then CACHE it
        if let res = syncInpaint(image: baseCG, items: pageState.refined.textLayers) {
            let resNS = NSImage(cgImage: res, size: pixelSize)
            SlideImageCache.shared.store(resNS, for: cacheKey)
            return (baseCG, res)
        }
        
        return (baseCG, baseCG)
    }

    func saveAsTextPDF(sourceURL: URL?, sourceDocument: PDFDocument?, destURL: URL, completion: @escaping (Bool) -> Void) {
        if FileManager.default.fileExists(atPath: destURL.path) { try? FileManager.default.removeItem(at: destURL) }
        var document: PDFDocument?
        if let sourceDoc = sourceDocument { document = sourceDoc }
        else if let url = sourceURL {
            do { try FileManager.default.copyItem(at: url, to: destURL); document = PDFDocument(url: destURL) }
            catch { completion(false); return }
        }
        
        guard let doc = document else { completion(false); return }
        let total = doc.pageCount
        
        // 🚀 V58.0: Run export in background to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async {
            for pageIndex in 0..<total {
                autoreleasepool {
                    // Update Progress
                    DispatchQueue.main.async {
                        self.batchProgress = (pageIndex + 1, total)
                        self.batchStatus = "Exporting Page \(pageIndex + 1) of \(total)..."
                    }
                    
                    guard let originalPage = doc.page(at: pageIndex) else { return }
                    
                    let rotation = originalPage.rotation
                    let originalBox = originalPage.bounds(for: .mediaBox)
                    var visualBox = originalBox
                    if rotation == 90 || rotation == 270 { visualBox = CGRect(x: 0, y: 0, width: originalBox.height, height: originalBox.width) }
                    
                    // 🚀 v58.0: On-demand hydration (Synchronous)
                    let result = self.getHydratedImages(for: pageIndex)
                    if let finalBG = result.refined {
                        let textLayers = self.getPage(at: pageIndex)?.refined.textLayers ?? []
                        let renderer = UIBasedPDFPage(background: finalBG, items: textLayers, bounds: visualBox)
                        doc.insert(renderer, at: pageIndex)
                        doc.removePage(at: pageIndex + 1)
                    }
                }
            }
            
            let success = doc.write(to: destURL)
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }

    private func renderPDFPageToCGImage(_ page: PDFPage) -> CGImage? {
        let rotation = page.rotation
        let box = page.bounds(for: .mediaBox)
        var visualSize = box.size
        if rotation == 90 || rotation == 270 { visualSize = CGSize(width: box.height, height: box.width) }
        let scale: CGFloat = 2.0
        let pixelSize = CGSize(width: visualSize.width * scale, height: visualSize.height * scale)
        let thumb = page.thumbnail(of: pixelSize, for: .mediaBox)
        var rect = NSRect(origin: .zero, size: pixelSize)
        return thumb.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private func calculateFittingFontSize(text: String, fontName: String, targetWidth: CGFloat, targetHeight: CGFloat) -> CGFloat {
        let testSize: CGFloat = 50.0
        let testFont = NSFont(name: fontName, size: testSize) ?? NSFont.systemFont(ofSize: testSize)
        let metrics = (text as NSString).size(withAttributes: [.font: testFont])
        let bestRatio = min(targetHeight / metrics.height, targetWidth / metrics.width)
        return testSize * bestRatio * 0.94
    }

    func syncPageToCache(index: Int) {
        updatePage(at: index) { page in
            page.refined.textLayers = self.recognizedItems
            page.refined.isRefined = (self.inpaintedImage != nil)
        }
        isDirty = recognizedItems.contains { $0.isErased }
    }

    // 🚀 V58.8: Global Patterns removed in favor of explicit per-page actions

    /// 🚀 Enhanced Matching: Apply pattern to specified cached page using trimming and robust comparison
    private func applyPattern(_ pattern: String, toPageAt index: Int) {
        let lp = pattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lp.isEmpty else { return }
        
        updatePage(at: index) { page in
            for i in page.refined.textLayers.indices {
                let lt = page.refined.textLayers[i].text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let le = page.refined.textLayers[i].editedText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                // Robust check: bidirectional inclusion
                if lt.contains(lp) || le.contains(lp) || lp.contains(lt) || lp.contains(le) {
                    page.refined.textLayers[i].viewState = .cleaned
                }
            }
        }
    }

    // 🚀 V58.8: Matches and Patterns logic removed to enforce per-page independence.

    // 🚀 V58.8: Global and shared pattern logic removed.
    // Watermark removal is now strictly manual via applyWatermarkToCurrentPage or applyWatermarkToAllPages.

    // 🚀 v39.0: restoreFromCache is DELETED. Use switchToPage(..., forced: true).

    /// 橡皮檫笔刷：增加一个小色块（不触发立即重绘，由外部 commit 或内部防抖触发）
    func addEraserPatch(_ normalizedRect: CGRect, imageSize: CGSize) {
        let pixelRect = CGRect(
            x: normalizedRect.origin.x * imageSize.width,
            y: normalizedRect.origin.y * imageSize.height,
            width: normalizedRect.size.width * imageSize.width,
            height: normalizedRect.size.height * imageSize.height
        )
        let newItem = RecognizedItem(
            text: "", 
            editedText: "", 
            rect: normalizedRect, 
            pixelRect: pixelRect, 
            charRects: [pixelRect], 
            fontSize: 0, 
            color: NSColor.black.cgColor, 
            viewState: .cleaned, 
            isManualEraser: true // 🚀 核心优化：标记为手动橡皮擦，防止在 Refine 时反弹
        )
        // 🚀 核心修复：直接修改数组，并触发防抖重绘
        DispatchQueue.main.async {
            self.recognizedItems.append(newItem)
            self.isDirty = true
            self.triggerDebouncedInpaint()
        }
    }

    /// 🚀 v55.0: Sequential Batch Refinement (Replaces legacy parallel loops)
    func batchRefineAll() {
        guard !isBatchProcessing, let doc = activeDocument else { return }
        let total = doc.pageCount
        
        isBatchProcessing = true
        batchStatus = "Initializing Batch Refinement..."
        batchProgress = (0, total)
        
        // Use a Task for non-blocking UI entry
        Task {
            for i in 0..<total {
                guard self.isBatchProcessing else { break }
                
                await MainActor.run {
                    self.batchProgress = (i + 1, total)
                    self.batchStatus = "Processing Page \(i + 1) of \(total)..."
                    self.currentPageIndex = i // Visually track progress
                }
                
                // 1. Ensure OCR
                guard let pageState = getPage(at: i) else { continue }
                if !pageState.isOCRComplete {
                    await preWarmPage(at: i, doc: doc)
                }
                
                // 2. Perform Single Page Refine logic sequentially
                await MainActor.run {
                    // Update metadata to refined state for the page we are batch refining
                    self.updatePage(at: i) { p in
                        for idx in 0..<p.refined.textLayers.count {
                            p.refined.textLayers[idx].viewState = .refined
                        }
                        p.refined.isRefined = true
                    }
                }
                
                // 3. Trigger actual background render using the pre-warm logic
                // This writes to disk cache sequentially
                await preWarmPage(at: i, doc: doc)
            }
            
            await MainActor.run {
                self.isBatchProcessing = false
                self.batchStatus = "Process Complete"
                self.switchToPage(index: self.currentPageIndex) // Refresh current view
            }
        }
    }

    /// 🚀 V39.9 Cleanup: Removed batchRefineAll as it is replaced by per-page Refine for quality control.

    /// 精确设置单个项的状态并触发重绘
    func setItemState(id: UUID, to state: ItemViewState) {
        if let index = recognizedItems.firstIndex(where: { $0.id == id }) {
            recognizedItems[index].viewState = state
            isDirty = true
            Task { await self.refreshCurrentPageBackground() }
        }
    }

    /// 开启防抖重绘
    private func triggerDebouncedInpaint() {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
            if !Task.isCancelled {
                await self.refreshCurrentPageBackground()
            }
        }
    }

    /// 手动提交笔刷（如在 Lift 鼠标时）
    func commitEraserStroke() {
        saveSnapshot()
        Task { await self.refreshCurrentPageBackground() }
    }

    func updateItemRect(id: UUID, newNormalizedRect: CGRect) {
        guard let index = recognizedItems.firstIndex(where: { $0.id == id }), let base = baseCGImage else { return }
        let pixelSize = CGSize(width: base.width, height: base.height)
        recognizedItems[index].rect = newNormalizedRect
        let newPixelRect = CGRect(x: newNormalizedRect.origin.x * pixelSize.width, y: newNormalizedRect.origin.y * pixelSize.height, width: newNormalizedRect.size.width * pixelSize.width, height: newNormalizedRect.size.height * pixelSize.height)
        recognizedItems[index].pixelRect = newPixelRect
        if recognizedItems[index].charRects.count <= 1 { recognizedItems[index].charRects = [newPixelRect] }
    }
    func commitRectChange() { saveSnapshot() }
    
    /// 🚀 V0.9.6: 为全量导出未精修页面提供截图支持
    func takeOriginalSnapshot(page: PDFPage) -> NSImage {
        let box = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0 // 使用 2x 缩放以保证 PPT 清晰度
        let pixelSize = CGSize(width: box.width * scale, height: box.height * scale)
        
        let image = NSImage(size: pixelSize)
        image.lockFocus()
        if let context = NSGraphicsContext.current?.cgContext {
            // 背景涂白，防止透明 PDF 导出黑底
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(origin: .zero, size: pixelSize))
            
            context.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context)
        }
        image.unlockFocus()
        return image
    }

    // MARK: - 🚀 V0.9.9.50: Watermark Refinement
    
    /// Batch apply watermark removal to all pages
    func applyWatermarkToAllPages(pattern: String) {
        let indices = pageIndices
        guard !indices.isEmpty else { return }
        
        isBatchProcessing = true
        batchStatus = "Detecting and refining watermarks..."
        batchProgress = (0, indices.count)
        
        DispatchQueue.global(qos: .userInitiated).async {
            for i in 0..<indices.count {
                autoreleasepool {
                    let currentProgress = i + 1
                    let total = indices.count
                    DispatchQueue.main.async {
                        self.batchProgress = (currentProgress, total)
                    self.batchStatus = "Refining watermark on page \(currentProgress)..."
                    }
                    self.applyWatermarkToPageSilently(pattern: pattern, at: indices[i])
                    
                    // 🚀 V58.4: Sync current page metadata immediately
                    if indices[i] == self.currentPageIndex {
                        let updatedState = self.getPage(at: indices[i])?.refined.textLayers ?? []
                        DispatchQueue.main.async {
                            self.recognizedItems = updatedState
                            self.isDirty = true
                            Task {
                                await self.refreshCurrentPageBackground()
                            }
                        }
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.isBatchProcessing = false
                self.batchStatus = "Watermark refinement complete"
                Task { await self.refreshCurrentPageBackground() }
            }
        }
    }
    
    /// Apply watermark removal to current page and update UI immediately
    func applyWatermarkToCurrentPage(pattern: String) {
        let index = self.currentPageIndex
        // 🚀 V58.3: Direct UI synchronization
        DispatchQueue.main.async {
            var anyChanged = false
            for i in 0..<self.recognizedItems.count {
                if self.recognizedItems[i].text.localizedCaseInsensitiveContains(pattern) {
                    self.recognizedItems[i].viewState = .cleaned
                    self.recognizedItems[i].isManualEraser = false // Reset manual flag
                    anyChanged = true
                }
            }
            
            if anyChanged {
                self.isDirty = true
                Task {
                    await self.refreshCurrentPageBackground()
                }
            }
            
            // Also update the background storage if different
            DispatchQueue.global(qos: .userInitiated).async {
                self.applyWatermarkToPageSilently(pattern: pattern, at: index)
            }
        }
    }
    
    /// Internal silent processor for watermark removal
    /// 🚀 V39.0: Apply pattern only to metadata (Choice 2: Minimal Memory)
    private func applyWatermarkToPageSilently(pattern: String, at index: Int) {
        guard var updatedPage = getPage(at: index) else { return }
        
        let watermarkIndices = updatedPage.refined.textLayers.indices.filter { 
            updatedPage.refined.textLayers[$0].text.localizedCaseInsensitiveContains(pattern) 
        }
        guard !watermarkIndices.isEmpty else { return }
        
        for i in watermarkIndices {
            updatedPage.refined.textLayers[i].viewState = .cleaned
            updatedPage.refined.textLayers[i].isVisible = false
        }
        
        updatedPage.refined.isRefined = true
        setPage(at: index, updatedPage)
    }

    /// 🚀 V37.16: Synchronous inpaint helper for background tasks
    private func syncInpaint(image: CGImage, items: [RecognizedItem]) -> CGImage? {
        let itemsToErase = items.filter { $0.isErased }
        if itemsToErase.isEmpty { 
            // 🚀 V58.5: Return nil to signal NO REFINED BACKGROUND exists
            return nil 
        }
        
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width, space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return image }
        
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        ctx.setFillColor(NSColor.white.cgColor)
        
        for item in itemsToErase {
            for r in item.charRects {
                let flippedY = CGFloat(image.height) - r.origin.y - r.size.height
                let flippedRect = CGRect(x: r.origin.x, y: flippedY, width: r.size.width, height: r.size.height)
                ctx.fill(flippedRect)
            }
        }
        
        guard let mask = ctx.makeImage() else { return image }
        return inpainter.inpaint(image: image, mask: mask)
    }
    
    // 🚀 V53.0: Atomic UI Commit - Ensure all page layers refresh in a single tick
    @MainActor
    private func commitPageUpdate(index: Int, session: UUID, base: CGImage?, original: NSImage?, inpainted: NSImage?, items: [RecognizedItem], isFinalized: Bool) async {
        // Strict Session Gate: Only update if we are still on the intended page
        guard self.currentPageIndex == index && self.activeSessionID == session else { return }
        
        self.baseCGImage = base
        self.originalImage = original
        self.inpaintedImage = inpainted
        self.recognizedItems = items
        self.isRefinementFinalized = isFinalized
        
        self.objectWillChange.send()
    }
    
    /// 🚀 V41.0: Atomic Slice Extraction for .original mode overlays
    func getOriginalSlice(for rect: CGRect) -> CGImage? {
        guard let original = baseCGImage else { return nil }
        let w = CGFloat(original.width)
        let h = CGFloat(original.height)
        
        let pixelRect = CGRect(
            x: rect.origin.x * w,
            y: rect.origin.y * h,
            width: rect.size.width * w,
            height: rect.size.height * h
        )
        return original.cropping(to: pixelRect)
    }
}

// MARK: - Custom PDFPage Class for Text Layers (Moved to Top Level)
class UIBasedPDFPage: PDFPage {
    let background: CGImage
    let items: [AdvancedSlideProcessor.RecognizedItem]
    
    init(background: CGImage, items: [AdvancedSlideProcessor.RecognizedItem], bounds: CGRect) {
        self.background = background
        self.items = items
        super.init()
        self.setBounds(bounds, for: .mediaBox)
    }
    
    override func draw(with box: PDFDisplayBox, to context: CGContext) {
        let mediaBox = self.bounds(for: box)
        context.saveGState()
        context.draw(background, in: mediaBox)
        context.restoreGState()
        
        let imageWidth = CGFloat(background.width)
        let scaleFactor = mediaBox.width / imageWidth
        
        for item in items {
            if !item.isErased || !item.isTextVisible { continue }
            let text = item.editedText.isEmpty ? item.text : item.editedText
            let rect = CGRect(
                x: mediaBox.origin.x + (item.rect.origin.x * mediaBox.width),
                y: mediaBox.origin.y + (1.0 - item.rect.origin.y - item.rect.size.height) * mediaBox.height,
                width: item.rect.size.width * mediaBox.width,
                height: item.rect.size.height * mediaBox.height
            )
            let pdfFontSize = item.fontSize * scaleFactor
            drawText(text, in: rect, context: context, item: item, fontSize: pdfFontSize)
        }
    }
    
    private func drawText(_ text: String, in rect: CGRect, context: CGContext, item: AdvancedSlideProcessor.RecognizedItem, fontSize: CGFloat) {
        context.saveGState()
        let fontName = item.fontName as CFString
        let font = CTFontCreateWithName(fontName, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(cgColor: item.color) ?? .black
        ]
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attrString)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let xOffset = (rect.width - lineWidth) / 2.0
        let yOffset = (rect.height - (ascent + descent)) / 2.0 + descent
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: rect.origin.x + xOffset, y: rect.origin.y + yOffset)
        CTLineDraw(line, context)
        context.restoreGState()
    }
}

extension AdvancedSlideProcessor.PageState {
    mutating func hydrate() {
        // 🚀 V38.0: Logic removed - direct bitmap access is inherently hydrated
    }
    
    mutating func compress() {
        // 🚀 V38.0: Logic removed - background compression disabled for stability
    }
}
