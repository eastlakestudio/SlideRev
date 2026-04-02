import Foundation
import Vision
import CoreImage
import PDFKit
import CoreGraphics
import SwiftUI

class AdvancedSlideProcessor: ObservableObject {
    
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
        var isErased: Bool = false
        var isTextVisible: Bool = false 
        var isManualEraser: Bool = false
        var refinementProgress: Double = 0.0 // 🚀 V0.9.9.22: Progress for horizontal scan animation (0.0 to 1.0)
        
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
            case id, text, editedText, rect, pixelRect, charRects, fontSize, fontName, colorComponents, isBold, rotation, isVisible, isErased, isTextVisible, isManualEraser
        }
        
        init(text: String, editedText: String, rect: CGRect, pixelRect: CGRect, charRects: [CGRect], fontSize: CGFloat, color: CGColor, isErased: Bool = false, isTextVisible: Bool = false, isManualEraser: Bool = false, isBold: Bool = false) {
            self.text = text; self.editedText = editedText; self.rect = rect; self.pixelRect = pixelRect
            self.charRects = charRects; self.fontSize = fontSize
            // 🚀 核心修复：初始化时就转为 sRGB
            let rgbColor = color.converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil) ?? color
            self.colorComponents = rgbColor.components ?? [0,0,0,1]
            if self.colorComponents.count < 4 { self.colorComponents = [0,0,0,1] }
            self.isErased = isErased
            self.isTextVisible = isTextVisible
            self.isManualEraser = isManualEraser
            self.refinementProgress = isErased ? 1.0 : 0.0 // Set initial progress based on erased state
            self.isBold = isBold
        }
    }


    // MARK: - PageState: Full data structure for each page
    // MARK: - V0.9.9: Structured Layer Model
    struct RawData: Codable {
        var originalImage: NSImage?
        var baseCGImage: CGImage?
        var pdfSize: CGSize = .zero
        
        enum CodingKeys: String, CodingKey {
            case pdfSize
        }
    }
    
    struct RefinedBundle: Codable {
        var background: NSImage?          // 擦除文字后的底图
        var textLayers: [RecognizedItem]  // 用户可操作的文字层
        var watermarkPattern: String?     // 指向该页应用的匹配模式
        var isRefined: Bool = false       // 是否已成功执行 AI 重绘
        
        enum CodingKeys: String, CodingKey {
            case textLayers, watermarkPattern, isRefined
        }
    }

    struct PageState {
        var pageIndex: Int
        var pdfPage: PDFPage?
        var visualSize: CGSize = .zero
        var raw: RawData
        var refined: RefinedBundle
        var isOCRComplete: Bool = false
    }

    @Published var recognizedItems: [RecognizedItem] = []
    @Published var inpaintedImage: NSImage?
    @Published var originalImage: NSImage?
    @Published var totalPageCount: Int = 0
    @Published var currentPageIndex: Int = 0
    
    // 🚀 V30.0: TASK LOCKING & PRE-WARM PROGRESS
    @Published var preWarmedCount: Int = 0
    private var readyPages: Set<Int> = [] // 🚀 v37.3: Track specifically which ones are 100% ready
    private var activeTasks: Set<Int> = []
    
    // 🚀 v37.3: Centralized state reporter for progress
    private func markPageReady(index: Int) {
        DispatchQueue.main.async {
            self.readyPages.insert(index)
            self.preWarmedCount = self.readyPages.count
            self.objectWillChange.send()
        }
    }
    
    // 🚀 V27.9.3: Explicit Document Reference to prevent premature deallocation
    var activeDocument: PDFDocument?
    
    @Published var isDirty: Bool = false
    @Published var isRefining: Bool = false // 🚀 V0.9.9.10: Active refinement signal for UI
    @Published var isRefinementFinalized: Bool = false // 🚀 V0.9.9.14: Final state indicator indicating inpaint is fully active background
    @Published var batchStatus: String = "Idle"
    
    // 🚀 V28.4: Internal helper to ensure a page's raw data (baseCGImage) is ready.
    // If it's a skeleton page, we render it on the fly instead of failing.
    private func ensurePageRawData(at index: Int) -> Bool {
        if let cached = pages[index], cached.raw.baseCGImage != nil {
            return true 
        }
        
        guard let page = pages[index]?.pdfPage else {
            print("❌ [Render] Error: No PDFPage found for index \(index)")
            return false 
        }
        
        let rotation = page.rotation
        let rawBounds = page.bounds(for: .mediaBox)
        var bounds = rawBounds
        if rotation == 90 || rotation == 270 {
            bounds = CGRect(x: 0, y: 0, width: rawBounds.height, height: rawBounds.width)
        }
        
        // Use standard 200 DPI scale (2.77)
        let scale: CGFloat = 200.0 / 72.0
        let pixelSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        
        let thumbImage = page.thumbnail(of: pixelSize, for: .mediaBox)
        guard let cgImage = thumbImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return false
        }
        
        // Update the cache immediately
        if var cached = pages[index] {
            cached.raw.baseCGImage = cgImage
            cached.raw.originalImage = NSImage(cgImage: cgImage, size: pixelSize)
            cached.visualSize = pixelSize
            pages[index] = cached
            
            // Also sync global context if this is the current page
            if index == self.currentPageIndex {
                DispatchQueue.main.async {
                    self.baseCGImage = cgImage
                    self.originalImage = cached.raw.originalImage
                }
            }
        }
        
        return true
    }
    
    // 🚀 v37.1: Eager Deep Pre-warming (Render + OCR)
    // Synchronously (inside background thread) waits for OCR before incrementing preWarmedCount.
    func preWarmPage(at index: Int, page: PDFPage) {
        if self.pages[index] != nil && self.pages[index]?.isOCRComplete == true { 
            DispatchQueue.main.async { self.preWarmedCount += 1 }
            return 
        }
        if activeTasks.contains(index) { return }
        
        activeTasks.insert(index)
        
        DispatchQueue.global(qos: .utility).async {
            autoreleasepool {
                // 1. Render Thumbnail (200 DPI)
                let rotation = page.rotation
                let rawBounds = page.bounds(for: .mediaBox)
                var bounds = rawBounds
                if rotation == 90 || rotation == 270 {
                    bounds = CGRect(x: 0, y: 0, width: rawBounds.height, height: rawBounds.width)
                }
                let scale: CGFloat = 200.0 / 72.0
                let pixelSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
                
                let thumbImage = page.thumbnail(of: pixelSize, for: .mediaBox)
                guard let cgImage = thumbImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    print("⚠️ [PreWarm] Failed to render thumbnail for page \(index). Skipping.")
                    DispatchQueue.main.async { 
                        self.activeTasks.remove(index)
                        self.preWarmedCount += 1 // 🚀 v37.2: Increment even on failure to avoid UI hang
                    }
                    return
                }
                
                let originalImage = NSImage(cgImage: cgImage, size: pixelSize)
                
                // 2. Perform Deep OCR (Silent/Background)
                self.performOCRSilently(on: cgImage, pixelSize: pixelSize) { items in
                    DispatchQueue.main.async {
                        self.activeTasks.remove(index)
                        
                        // 3. Atomically populate PageState with OCR Results
                        self.pages[index] = PageState(
                            pageIndex: index, pdfPage: page, visualSize: pixelSize,
                            raw: RawData(originalImage: originalImage, baseCGImage: cgImage, pdfSize: bounds.size),
                            refined: RefinedBundle(background: nil, textLayers: items, watermarkPattern: nil, isRefined: false),
                            isOCRComplete: true
                        )
                        
                        // 🚀 v37.3: Signal one more page is FULLY ready (Centralized)
                        self.markPageReady(index: index)
                        print("✅ [PreWarm] Page \(index) Ready (OCR Found \(items.count) items)")
                    }
                }
            }
        }
    }
    
    // ML/AI Inpainter for watermark removal
    static let defaultOCRThreshold: Float = 0.50
    @Published var ocrConfidenceThreshold: Float = defaultOCRThreshold
    /// 🚀 批量处理标志：true 时 processPage 不更新 UI，只写缓存
    var isBatchProcessing: Bool = false
    
    // 核心數據：每頁完整狀態
    var pages: [Int: PageState] = [:]
    private var undoStack: [([RecognizedItem], NSImage?)] = []
    private let context = CIContext()
    private let inpainter: NeuralInpainter = {
        if let bundleURL = Bundle.main.url(forResource: "LaMa", withExtension: "mlmodelc") {
            return NeuralInpainter(modelURL: bundleURL)
        }
        let devPath = "3rd/coremlama/LaMa.mlmodelc"
        return NeuralInpainter(modelURL: URL(fileURLWithPath: devPath))
    }()
    private var baseCGImage: CGImage?  // 当前頁的 CGImage
    private var debounceTask: Task<Void, Never>? = nil
    
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
        let sessionPages = pages.mapValues { PageSession(recognizedItems: $0.refined.textLayers, isRefined: $0.refined.isRefined) }
        let session = SessionData(pages: sessionPages, globalPatterns: Array(globalErasurePatterns))
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
            self.globalErasurePatterns = Set(session.globalPatterns)
            
            // 🚀 Deep merge: we update the metadata. 
            // The actual images will be re-processed or loaded from the original PDF on demand.
            for (index, pageSession) in session.pages {
                if var existing = self.pages[index] {
                    existing.refined.textLayers = pageSession.recognizedItems
                    existing.refined.isRefined = pageSession.isRefined
                    self.pages[index] = existing
                } else {
                    self.pages[index] = PageState(
                        pageIndex: index,
                        pdfPage: nil,
                        visualSize: .zero,
                        raw: RawData(originalImage: nil, baseCGImage: nil, pdfSize: .zero),
                        refined: RefinedBundle(background: nil, textLayers: pageSession.recognizedItems, watermarkPattern: nil, isRefined: pageSession.isRefined),
                        isOCRComplete: true
                    )
                }
            }
            self.isDirty = false
        } catch {
        }
    }

    // 🚀 V0.9.6.20: Clear all internal states (important for opening new documents)
    func clearAllStates() {
        DispatchQueue.main.async {
            self.pages.removeAll()
            self.recognizedItems.removeAll()
            self.inpaintedImage = nil
            self.originalImage = nil
            self.undoStack.removeAll()
            self.globalErasurePatterns.removeAll()
            self.isDirty = false
            self.currentPageIndex = 0
            self.totalPageCount = 0
        }
    }

    // 🚀 V31.0: MEMORY GOVERNANCE - Clear all cached images and session data
    func clearCache() {
        self.pages.removeAll()
        self.activeTasks.removeAll()
        self.clearUndoStack() // 🚀 V32.1: CRITICAL - Clear the history to recover ~1GB memory
        self.recognizedItems.removeAll()
        self.originalImage = nil
        self.baseCGImage = nil
        self.inpaintedImage = nil
        self.activeDocument = nil // 🚀 Release the PDFDocument reference
        self.isRefinementFinalized = false
        self.preWarmedCount = 0
        self.totalPageCount = 0
        self.currentPageIndex = 0
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
        if var page = pages[currentPageIndex] {
            page.refined.textLayers = self.recognizedItems
            pages[currentPageIndex] = page
        }
    }
    
    /// 🚀 UI-Cache Bridge: Refresh the UI (@Published) array from the target page cache
    private func syncUIFromCache(index: Int) {
        guard index == currentPageIndex, let cached = pages[index] else { return }
        DispatchQueue.main.async {
            self.recognizedItems = cached.refined.textLayers
        }
    }
    
    /// Core Entry: Switch current page (Prioritize loading from cache)
    func switchToPage(index: Int, forced: Bool = false, completion: ((Bool) -> Void)? = nil) {
        // 1. Check Cache
        // 🚀 V0.9.8.50: Priority Loading. 
        // HIT if: (not forced OR already refined) AND (raw image is rendered OR already refined)
        // If it's just a 'Skeleton' (baseCGImage == nil), we must fall through to render it.
        if let cached = pages[index], (!forced || cached.refined.isRefined), (cached.raw.baseCGImage != nil || cached.refined.isRefined) {
            DispatchQueue.main.async {
                self.currentPageIndex = index
                self.baseCGImage = cached.raw.baseCGImage
                self.recognizedItems = cached.refined.textLayers
                self.inpaintedImage = cached.refined.background
                self.originalImage = cached.raw.originalImage
                self.isRefinementFinalized = cached.refined.isRefined 
                
                self.objectWillChange.send()
                completion?(true)
            }
            return
        }
        
        // 2. Cache miss or skeleton/forced refresh
        // 🚀 V27.9.3: Fallback to activeDocument if the page's parent reference is weak/lost
        let docCandidate = pages[index]?.pdfPage?.document ?? self.activeDocument
        
        guard let doc = docCandidate else {
            completion?(false)
            return
        }
        
        guard let page = doc.page(at: index) else {
            completion?(false)
            return
        }
        
        processPage(page, at: index) { success in
            completion?(success)
        }
    }

    func processPage(_ page: PDFPage, at index: Int, completion: @escaping (Bool) -> Void) {
        
        if isBatchProcessing {
            processSilently(page, at: index, completion: completion)
            return
        }
        
        // 1. 同步加载缓存（如果存在且已渲染图像，且非静默模式）
        if let cached = self.pages[index], cached.raw.baseCGImage != nil {
            // 🚀 Fix (v29.4): ONLY HIT CACHED IF IMAGE IS PRESENT.
            // Skeletons from pre-warm/batch-init will now correctly fall through to processPage.
            self.baseCGImage = cached.raw.baseCGImage
            self.recognizedItems = cached.refined.textLayers
            self.inpaintedImage = cached.refined.background
            self.originalImage = cached.raw.originalImage
            self.currentPageIndex = index
            completion(true)
            return
        }

        // 2. Cache miss, execute full loading flow
        if activeTasks.contains(index) {
            return
        }
        activeTasks.insert(index)

        DispatchQueue.main.async {
            self.isRefinementFinalized = false // 🚀 NEW: Start clean for fresh page
            
            // Calculate dimensions
            let rotation = page.rotation
            let rawBounds = page.bounds(for: .mediaBox)
            var bounds = rawBounds
            if rotation == 90 || rotation == 270 {
                bounds = CGRect(x: 0, y: 0, width: rawBounds.height, height: rawBounds.width)
            }
            
            let scale: CGFloat = 200.0 / 72.0
            let pixelSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            
            // 3. Async background render
            DispatchQueue.global(qos: .userInitiated).async {
                autoreleasepool {
                    let thumbImage = page.thumbnail(of: pixelSize, for: .mediaBox)
                    guard let cgImage = thumbImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                        DispatchQueue.main.async { 
                            self.activeTasks.remove(index)
                            completion(false) 
                        }
                        return
                    }
                    
                    // 4. Update state on main thread and trigger OCR
                    DispatchQueue.main.async {
                        self.activeTasks.remove(index)
                        self.baseCGImage = cgImage
                        self.totalPageCount = page.document?.pageCount ?? 1
                        self.currentPageIndex = index
                        self.originalImage = NSImage(cgImage: cgImage, size: pixelSize)
                        
                        self.pages[index] = PageState(
                            pageIndex: index, pdfPage: page, visualSize: pixelSize,
                            raw: RawData(originalImage: self.originalImage, baseCGImage: cgImage, pdfSize: bounds.size),
                            refined: RefinedBundle(background: nil, textLayers: [], watermarkPattern: nil, isRefined: false),
                            isOCRComplete: false
                        )
                        
                        self.performOCR(on: cgImage, pixelSize: pixelSize, pageIndex: index) { success in
                            completion(success)
                        }
                    }
                }
            }
        }
    }

    /// Process page silently (Batch mode only), doesn't update UI properties
    func processSilently(_ page: PDFPage, at index: Int, completion: @escaping (Bool) -> Void) {
        // 🚀 V0.9.9.8: Deep Refine Batch Mode
        // Perform 'Full Refine': Erase all text, then restore non-patterns
        
        let rotation = page.rotation
        let rawBounds = page.bounds(for: .mediaBox)
        var bounds = rawBounds
        if rotation == 90 || rotation == 270 {
            bounds = CGRect(x: 0, y: 0, width: rawBounds.height, height: rawBounds.width)
        }
        let scale: CGFloat = 200.0 / 72.0
        let pixelSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)

        func finalizeProcess(items: [RecognizedItem], cg: CGImage) {
            var processedItems = items
            
            // 1. Full Refine Logic: Erase everything by default
            for i in 0..<processedItems.count {
                processedItems[i].isErased = true
                let isPrivacy = self.matchesAnyGlobalPattern(item: processedItems[i])
                processedItems[i].isTextVisible = !isPrivacy
                // 🚀 V29.1: MUST set refinementProgress to 1.0 to reveal the text in the UI mask!
                processedItems[i].refinementProgress = 1.0
            }
            
            DispatchQueue.main.async {
                let newState = PageState(
                    pageIndex: index, pdfPage: page, visualSize: pixelSize,
                    raw: RawData(originalImage: NSImage(cgImage: cg, size: pixelSize), baseCGImage: cg, pdfSize: bounds.size),
                    refined: RefinedBundle(background: nil, textLayers: processedItems, watermarkPattern: nil, isRefined: false),
                    isOCRComplete: true
                )
                self.pages[index] = newState
                
                // 3. Trigger Inpainting (Silent)
                self.refreshInpaintedBackgroundSilently(index: index) { success in
                    completion(success)
                }
            }
        }

        if let cached = self.pages[index], cached.isOCRComplete, let cg = cached.raw.baseCGImage {
            finalizeProcess(items: cached.refined.textLayers, cg: cg)
        } else {
            DispatchQueue.global(qos: .userInitiated).async {
                autoreleasepool {
                    let thumbImage = page.thumbnail(of: pixelSize, for: .mediaBox)
                    guard let cgImage = thumbImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                        DispatchQueue.main.async { completion(false) }
                        return
                    }
                    self.performOCRSilently(on: cgImage, pixelSize: pixelSize) { items in
                        finalizeProcess(items: items, cg: cgImage)
                    }
                }
            }
        }
    }

    private func performOCRSilently(on cgImage: CGImage, pixelSize: CGSize, completion: @escaping ([RecognizedItem]) -> Void) {
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let threshold = self.ocrConfidenceThreshold
        let ocrRequest = VNRecognizeTextRequest { (request, error) in
            if let _ = error { completion([]); return }
            guard let observations = request.results as? [VNRecognizedTextObservation] else { completion([]); return }
            
            var items: [RecognizedItem] = []
            for obs in observations {
                guard let top = obs.topCandidates(1).first else { continue }
                guard top.confidence >= threshold, top.string.count >= 1 else { continue }
                let visionRect = obs.boundingBox
                let normalizedRect = CGRect(x: visionRect.origin.x, y: 1.0 - visionRect.origin.y - visionRect.size.height, width: visionRect.size.width, height: visionRect.size.height * 1.05)
                let pixelRect = CGRect(x: normalizedRect.origin.x * pixelSize.width, y: normalizedRect.origin.y * pixelSize.height, width: normalizedRect.size.width * pixelSize.width, height: normalizedRect.size.height * pixelSize.height)
                
                // 🚀 V0.9.9.25: Smart Rect Extraction (Word-level for Alpha, Char-level for CJK)
                let charRects = self.extractEraseRects(from: top, fullBox: obs.boundingBox, pixelSize: pixelSize)
                
                let fontSize = self.calculateFittingFontSize(text: top.string, fontName: "Helvetica", targetWidth: pixelRect.width, targetHeight: pixelRect.height)
                let itemColor = self.samplePrimaryColor(cgImage: cgImage, rect: pixelRect, imageHeight: pixelSize.height)
                
                items.append(RecognizedItem(text: top.string, editedText: top.string, rect: normalizedRect, pixelRect: pixelRect, charRects: charRects, fontSize: fontSize, color: itemColor, isBold: false))
            }
            completion(items)
        }
        ocrRequest.recognitionLevel = .accurate
        ocrRequest.recognitionLanguages = ["zh-Hans", "en-US"]
        try? handler.perform([ocrRequest])
    }

    /// Inpainting in silent mode: Doesn't modify self.inpaintedImage
    func refreshInpaintedBackgroundSilently(index: Int, completion: @escaping (Bool) -> Void) {
        guard let pageData = pages[index], let base = pageData.raw.baseCGImage else { completion(false); return }
        let pixelSize = pageData.visualSize 
        
        let itemsToErase = pageData.refined.textLayers.filter { $0.isErased }
        if itemsToErase.isEmpty {
            self.pages[index]?.refined.background = pageData.raw.originalImage
            self.pages[index]?.refined.isRefined = true
            completion(true); return
        }
        
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(data: nil, width: base.width, height: base.height, bitsPerComponent: 8, bytesPerRow: base.width, space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            completion(false); return
        }
        
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: base.width, height: base.height))
        ctx.setFillColor(NSColor.white.cgColor)
        
        for item in itemsToErase {
            for r in item.charRects {
                let flippedY = CGFloat(base.height) - r.origin.y - r.size.height
                let flippedRect = CGRect(x: r.origin.x, y: flippedY, width: r.size.width, height: r.size.height)
                ctx.fill(flippedRect)
            }
        }
        
        
        if let maskCG = ctx.makeImage() {
            // 🚀 V0.9.9.32: 质量优化 - 遮罩羽化 (Mask Feathering)
            // 对遮罩生成 3.0 半径的高斯模糊，使背景修复过渡更自然，消除边缘噪点。
            let ciMask = CIImage(cgImage: maskCG)
            let blurFilter = CIFilter(name: "CIGaussianBlur")
            blurFilter?.setValue(ciMask, forKey: kCIInputImageKey)
            blurFilter?.setValue(3.0, forKey: kCIInputRadiusKey)
            
            var finalMask: CGImage? = maskCG
            if let output = blurFilter?.outputImage,
               let softMask = self.context.createCGImage(output, from: ciMask.extent) {
                finalMask = softMask
            }
            
            if let targetMask = finalMask, let res = inpainter.inpaint(image: base, mask: targetMask) {
                DispatchQueue.main.async {
                    if var page = self.pages[index] {
                        page.refined.background = NSImage(cgImage: res, size: pixelSize)
                        page.refined.isRefined = true
                        self.pages[index] = page
                    }
                    completion(true)
                }
            } else {
                completion(false)
            }
        } else {
            completion(false)
        }
    }
    
    private func performOCR(on cgImage: CGImage, pixelSize: CGSize, pageIndex: Int, completion: @escaping (Bool) -> Void) {
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let threshold :Float = self.ocrConfidenceThreshold
        let ocrRequest = VNRecognizeTextRequest { [weak self] (request, error) in
            if let _ = error {
                completion(false)
                return
            }
            guard let self = self, let observations = request.results as? [VNRecognizedTextObservation] else { 
                completion(false); 
                return 
            }
            
            var items: [RecognizedItem] = []
            for obs in observations {
                guard let top = obs.topCandidates(1).first else { continue }
                // 置信度过滤：低于阈值或过短的识别结果（小图形误识别）直接丢弃
                guard top.confidence >= threshold, top.string.count >= 1 else {
                    continue
                }
                let visionRect = obs.boundingBox
                let normalizedRect = CGRect(x: visionRect.origin.x, y: 1.0 - visionRect.origin.y - visionRect.size.height, width: visionRect.size.width, height: visionRect.size.height * 1.05)
                let pixelRect = CGRect(x: normalizedRect.origin.x * pixelSize.width, y: normalizedRect.origin.y * pixelSize.height, width: normalizedRect.size.width * pixelSize.width, height: normalizedRect.size.height * pixelSize.height)
                
                let fontSize = self.calculateFittingFontSize(text: top.string, fontName: "Helvetica", targetWidth: pixelRect.width, targetHeight: pixelRect.height)
                let itemColor = self.samplePrimaryColor(cgImage: cgImage, rect: pixelRect, imageHeight: pixelSize.height)
                
                // 🚀 V0.9.9.25: Sync word-level erasure to UI OCR as well
                let charRects = self.extractEraseRects(from: top, fullBox: obs.boundingBox, pixelSize: pixelSize)
                
                items.append(RecognizedItem(text: top.string, editedText: top.string, rect: normalizedRect, pixelRect: pixelRect, charRects: charRects, fontSize: fontSize, color: itemColor, isBold: false))
            }
            print("🔠 [OCR] 识别完成: \(items.count) 项（阈值=\(String(format:"%.2f", threshold))）")
            DispatchQueue.main.async { 
                // Always persist OCR results to page cache first
                if self.pages[pageIndex] != nil {
                    self.pages[pageIndex]?.refined.textLayers = items
                    self.pages[pageIndex]?.isOCRComplete = true
                    print("💾 [OCR] Cached Page \(pageIndex + 1) with \(items.count) items")
                }
                
                // 🚀 Sync to UI ONLY if we are on the current page and NOT in batch mode
                if self.currentPageIndex == pageIndex && !self.isBatchProcessing {
                    self.recognizedItems = items
                }
                
                // Automatic global pattern application for seamless erasure persistence
                self.applyGlobalPatterns(toIndex: pageIndex)
                
                // 🚀 v37.3: Centralized completion signal
                self.markPageReady(index: pageIndex)
                completion(true) 
            }
        }
        
        ocrRequest.recognitionLevel = VNRequestTextRecognitionLevel.accurate
        
        ocrRequest.automaticallyDetectsLanguage = true
        ocrRequest.usesLanguageCorrection = true
        //ocrRequest.recognitionLanguages = ["zh-Hans", "en-US"]
        try? handler.perform([ocrRequest])
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

    func eraseItem(id: UUID) {
        guard let index = recognizedItems.firstIndex(where: { $0.id == id }) else { return }
        let item = recognizedItems[index]
        AdvancedSlideProcessor.fileLog("🖱️ [UI] Manual Erase Triggered: id=\(id), text='\(item.text)', isErased=\(item.isErased)")
        saveSnapshot()
        
        DispatchQueue.main.async {
            let isErased = self.recognizedItems[index].isErased
            let isErasing = !isErased
            
            self.recognizedItems[index].isErased = isErasing
            self.isDirty = true
            
            if isErasing {
                AdvancedSlideProcessor.fileLog("🏁 [UI] Starting Manual Scan: progress=0.0")
                self.recognizedItems[index].refinementProgress = 0.0
                self.recognizedItems[index].isTextVisible = true 
                self.refreshInpaintedBackground { success in
                    AdvancedSlideProcessor.fileLog("✅ [UI] Manual Inpaint Request Finish: success=\(success)")
                }
                
                // 🚀 v37.9: Sequence: Background mask disappears first (isErased=true above), 
                // Then after a short gap, overlay the vector text with the scanning wipe.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        self.recognizedItems[index].refinementProgress = 1.0
                    }
                }
            } else {
                AdvancedSlideProcessor.fileLog("🔙 [UI] Restoring original item")
                self.recognizedItems[index].isTextVisible = false
                self.recognizedItems[index].refinementProgress = 0.0
                self.refreshInpaintedBackground { _ in }
            }
            self.objectWillChange.send()
        }
    }

    func refinePage(completion: @escaping (Bool) -> Void = { _ in }) {
        let index = currentPageIndex
        
        // 🚀 V28.4: SELF-HEALING PAGESTATE
        // If image is missing, render it on-demand instead of erroring out.
        guard ensurePageRawData(at: index) else {
            print("❌ [Refine] Abort: Page \(index + 1) image data could not be recovered.")
            completion(false)
            return
        }
        
        guard let pdfPage = pages[index]?.pdfPage else {
            print("❌ [Refine] Abort: No PDFPage found for index \(index)")
            completion(false)
            return
        }
        
        print("🎭 [Animation] Starting PageState-driven Refinement (v28.4)...")
        saveSnapshot()
        
        func executeSequence() {
            // 🚀 V29.2: CRITICAL SYNC - If items are empty (e.g. from pre-warm), try to pull from cache first
            if self.recognizedItems.isEmpty, let cachedItems = self.pages[index]?.refined.textLayers, !cachedItems.isEmpty {
                print("🔄 [Refine] Re-syncing items from cache for Page \(index + 1)")
                self.recognizedItems = cachedItems
            }
            
            if self.recognizedItems.isEmpty {
                print("⚠️ [Refine] No items to refine on Page \(index + 1), completing.")
                completion(true)
                return
            }

            // 🚀 Phase 1: SET ALL ITEMS TO ERASED to trigger full background cleaning
            DispatchQueue.main.async {
                for i in 0..<self.recognizedItems.count {
                    self.recognizedItems[i].isErased = true
                }
                
                // 2. Trigger Inpainting (since all are set, it will clean the whole page)
                self.refreshInpaintedBackground { success in
                    guard success else { completion(false); return }
                    
                    // 3. Reset visual states for the staggered reveal animation
                    DispatchQueue.main.async {
                        for i in 0..<self.recognizedItems.count {
                            self.recognizedItems[i].isErased = false
                            self.recognizedItems[i].isTextVisible = false
                        }
                        
                        // 4. Staggered Reveal Loop
                        let itemsCount = self.recognizedItems.count
                        let interval = max(0.015, min(0.03, 1.0 / Double(max(1, itemsCount)))) 
                        
                        for i in 0..<itemsCount {
                            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * interval) {
                                let item = self.recognizedItems[i]
                                let isPatternHide = self.matchesAnyGlobalPattern(item: item)
                                
                                // 🚀 NEW SCAN ANIMATION: Horizontal wipe reveal
                                withAnimation(.easeOut(duration: 0.05)) {
                                    self.recognizedItems[i].isErased = true
                                    self.recognizedItems[i].isTextVisible = !isPatternHide
                                    self.recognizedItems[i].refinementProgress = 0.0
                                }
                                
                                withAnimation(.easeInOut(duration: 0.45)) {
                                    self.recognizedItems[i].refinementProgress = 1.0
                                }
                                
                                if i == itemsCount - 1 {
                                    // 🚀 V29.2: PERSISTENCE SYNC - Save refinement states (isErased, isTextVisible) back to cache!
                                    if var page = self.pages[index] {
                                        page.refined.textLayers = self.recognizedItems
                                        page.refined.isRefined = true
                                        self.pages[index] = page
                                        print("💾 [Refine] Persistent metadata saved for Page \(index + 1)")
                                    }
                                    
                                    self.clearUndoStack() // 🚀 V32.2: CRITICAL - Purge undo snapshots after full-page refine to save memory
                                    self.isRefinementFinalized = true // 🚀 UNLOCK FULL CLEAN BACKGROUND
                                    completion(true)
                                }
                            }
                        }
                        if itemsCount == 0 { 
                            self.clearUndoStack()
                            completion(true) 
                        }
                    }
                }
            }
        }

        if pages[index]?.isOCRComplete != true {
            processPage(pdfPage, at: index) { _ in executeSequence() }
        } else {
            executeSequence()
        }
    }

    func refreshInpaintedBackground(completion: @escaping (Bool) -> Void) {
        let currentPage = self.currentPageIndex
        
        // 🚀 V28.4: SELF-HEALING PAGESTATE
        // Ensure PageState has base image source before AI process.
        guard ensurePageRawData(at: currentPage) else {
            print("❌ [Inpaint] Abort: Page \(currentPage + 1) has no recoverable base image.")
            completion(false)
            return
        }
        
        // Extract stable data from confirmed PageState
        guard let cached = self.pages[currentPage], let base = cached.raw.baseCGImage else {
            completion(false)
            return
        }
        
        // 🚀 V0.9.9.5: Snapshot relevant items on the calling thread (usually main)
        let snapshotItems = self.recognizedItems
        let originalImg = self.originalImage
        
        DispatchQueue.global(qos: .userInitiated).async {
            autoreleasepool {
                let itemsToErase = snapshotItems.filter { $0.isErased }
                if itemsToErase.isEmpty { 
                    DispatchQueue.main.async { 
                        self.inpaintedImage = originalImg 
                        if var page = self.pages[currentPage] {
                            page.refined.background = originalImg
                            page.refined.textLayers = snapshotItems
                            page.refined.isRefined = true
                            self.pages[currentPage] = page
                        }
                        
                        print("✨ [Inpaint] 异步重写完成 (空路径): page=\(currentPage + 1)")
                        self.isRefinementFinalized = true // 🚀 V27.6.5: Ensure UI knows refinement is active
                        self.recognizedItems = snapshotItems // 🚀 Sync latest text layers
                        self.objectWillChange.send()
                        completion(true) 
                    }
                    return 
                }
                
                let colorSpace = CGColorSpaceCreateDeviceGray()
                guard let ctx = CGContext(data: nil, width: base.width, height: base.height, bitsPerComponent: 8, bytesPerRow: base.width, space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { 
                    DispatchQueue.main.async { completion(false) }
                    return 
                }
                
                ctx.setFillColor(NSColor.black.cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: base.width, height: base.height))
                ctx.setFillColor(NSColor.white.cgColor)
                
                for item in itemsToErase {
                    for r in item.charRects {
                        let flippedY = CGFloat(base.height) - r.origin.y - r.size.height
                        let flippedRect = CGRect(x: r.origin.x, y: flippedY, width: r.size.width, height: r.size.height)
                        ctx.fill(flippedRect)
                    }
                }
                
                if let maskCG = ctx.makeImage(), let res = self.inpainter.inpaint(image: base, mask: maskCG) {
                    DispatchQueue.main.async { 
                        let pixelSize = originalImg?.size ?? .zero
                        let resultImage = NSImage(cgImage: res, size: pixelSize)
                        self.inpaintedImage = resultImage
                        
                        // 🚀 V37.7: Fix STALE UI RESET.
                        // We must ensure as items complete erasure, they maintain 1.0 progress.
                        var updatedItems = snapshotItems
                        AdvancedSlideProcessor.fileLog("📝 [Sync] Finalizing Inpaint Sync: \(updatedItems.count) items snapshots")
                        for i in 0..<updatedItems.count {
                            if updatedItems[i].isErased {
                                updatedItems[i].refinementProgress = 1.0
                                updatedItems[i].isTextVisible = true
                                AdvancedSlideProcessor.fileLog("✨ [Sync] Persisting fixed state for item [\(i)]: '\(updatedItems[i].text)', progress=1.0")
                            }
                        }
                        
                        if var page = self.pages[currentPage] {
                            page.refined.background = resultImage
                            page.refined.isRefined = true
                            page.refined.textLayers = updatedItems
                            self.pages[currentPage] = page
                        }
                        
                        AdvancedSlideProcessor.fileLog("🚀 [Inpaint] UI UPDATE: Syncing \(updatedItems.count) items to recognizedItems")
                        self.isRefinementFinalized = true 
                        self.recognizedItems = updatedItems 
                        self.objectWillChange.send()
                        completion(true)
                    }
                } else {
                    DispatchQueue.main.async { completion(false) }
                }
            }
        }
    }

    // MARK: - PDF Export Implementation
    
    func saveAsTextPDF(sourceURL: URL?, sourceDocument: PDFDocument?, destURL: URL, completion: @escaping (Bool) -> Void) {
        if FileManager.default.fileExists(atPath: destURL.path) { try? FileManager.default.removeItem(at: destURL) }
        
        var document: PDFDocument?
        
        if let sourceDoc = sourceDocument {
            // 🚀 V0.9.6.17: Use provided memory document (e.g. from Image)
            document = sourceDoc
        } else if let url = sourceURL {
            // 🚀 Standard PDF Mode: Copy from source URL
            do { 
                try FileManager.default.copyItem(at: url, to: destURL)
                document = PDFDocument(url: destURL)
            } catch { 
                completion(false)
                return 
            }
        }
        
        guard let document = document else { completion(false); return }
        // 🚀 V29.4: Use 'isRefined' flag for robust targeting, ensuring all batch-refined pages are caught
        let modifiedIndices = pages.keys.filter { pages[$0]?.refined.isRefined == true }.sorted(by: >)
        print("💾 [saveAsTextPDF] 開始導出，總頁數=\(document.pageCount), 已修改頁=\(modifiedIndices)")
        
        for pageIndex in modifiedIndices {
            guard let pageState = pages[pageIndex], pageIndex < document.pageCount else { continue }
            let items = pageState.refined.textLayers

            
            guard let originalPage = document.page(at: pageIndex) else { continue }
            let rotation = originalPage.rotation
            let originalBox = originalPage.bounds(for: PDFDisplayBox.mediaBox)
            
            // 獲取視覺上的 MediaBox 大小（考慮旋轉）
            var visualBox = originalBox
            if rotation == 90 || rotation == 270 {
                visualBox = CGRect(x: 0, y: 0, width: originalBox.height, height: originalBox.width)
            }
            print("📐 [saveAsTextPDF] 第\(pageIndex)頁: rotation=\(rotation), originalBox=\(originalBox), visualBox=\(visualBox)")
            
            // 获取底图：优先使用 PageState 中保存的 inpaintedImage
            var bgCG: CGImage? = nil
            let sourceImage = pageState.refined.background ?? pageState.raw.originalImage
            if let nsImg = sourceImage {
                print("🖼️ [saveAsTextPDF] 第\(pageIndex)頁使用 PageState 圖, isRefined=\(pageState.refined.isRefined), size=\(nsImg.size)")
                var rect = NSRect(origin: .zero, size: nsImg.size)
                bgCG = nsImg.cgImage(forProposedRect: &rect,
                                     context: nil as NSGraphicsContext?,
                                     hints: nil as [NSImageRep.HintKey : Any]?)
            } else {
                print("🔄 [saveAsTextPDF] 第\(pageIndex)頁即時渲染底圖")
                if let pageImage = self.renderPDFPageToCGImage(originalPage) {
                    print("✅ [saveAsTextPDF] 渲染底圖成功: \(pageImage.width)x\(pageImage.height)")
                    bgCG = self.syncInpaint(image: pageImage, items: items)
                }
            }
            
            guard let finalBG = bgCG else {
                print("❌ [saveAsTextPDF] 第\(pageIndex)頁 bgCG 為空，跳過")
                continue 
            }
            print("✅ [saveAsTextPDF] 最終底圖: \(finalBG.width)x\(finalBG.height), 目標 visualBox=\(visualBox)")
            
            let renderer = UIBasedPDFPage(background: finalBG, items: items, bounds: visualBox)
            document.insert(renderer, at: pageIndex)
            document.removePage(at: pageIndex + 1)
            print("📄 [saveAsTextPDF] 第\(pageIndex)頁替換完成")
        }
        
        let success = document.write(to: destURL)
        completion(success)
    }

    private func syncInpaint(image: CGImage, items: [RecognizedItem]) -> CGImage? {
        let itemsToErase = items.filter { $0.isErased }
        if itemsToErase.isEmpty { return image }
        
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width, space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return image }
        
        ctx.setFillColor(NSColor.black.cgColor); ctx.fill(CGRect(x:0, y:0, width:image.width, height:image.height))
        ctx.setFillColor(NSColor.white.cgColor)
        for item in itemsToErase {
            // 🚀 Dilation: Add 2px padding to the mask to ensure full erasure of original text edges
            let padding: CGFloat = 2.0
            let dilatedRect = CGRect(
                x: item.pixelRect.origin.x - padding,
                y: item.pixelRect.origin.y - padding,
                width: item.pixelRect.size.width + padding * 2,
                height: item.pixelRect.size.height + padding * 2
            )
            let flippedY = CGFloat(image.height) - dilatedRect.origin.y - dilatedRect.size.height
            ctx.fill(CGRect(x: dilatedRect.origin.x, y: flippedY, width: dilatedRect.size.width, height: dilatedRect.size.height))
        }
        guard let mask = ctx.makeImage() else { return image }
        return inpainter.inpaint(image: image, mask: mask)
    }

    private func renderPDFPageToCGImage(_ page: PDFPage) -> CGImage? {
        let rotation = page.rotation
        let box = page.bounds(for: .mediaBox)
        
        var visualSize = box.size
        if rotation == 90 || rotation == 270 {
            visualSize = CGSize(width: box.height, height: box.width)
        }
        
        let scale: CGFloat = 2.0
        let pixelSize = CGSize(width: visualSize.width * scale, height: visualSize.height * scale)
        
        print("🔍 [renderPDFPageToCGImage] rotation=\(rotation), box=\(box), visualSize=\(visualSize), pixelSize=\(pixelSize)")
        
        let thumb = page.thumbnail(of: pixelSize, for: .mediaBox)
        print("📸 [renderPDFPageToCGImage] thumbnail.size=\(thumb.size)")
        var rect = NSRect(origin: .zero, size: pixelSize)
        let result = thumb.cgImage(forProposedRect: &rect, context: nil as NSGraphicsContext?, hints: nil as [NSImageRep.HintKey : Any]?)
        if let r = result { print("✅ [renderPDFPageToCGImage] cgImage=\(r.width)x\(r.height)") }
        else { print("❌ [renderPDFPageToCGImage] cgImage 轉換失敗") }
        return result
    }

    private func calculateFittingFontSize(text: String, fontName: String, targetWidth: CGFloat, targetHeight: CGFloat) -> CGFloat {
        // 🚀 V0.9.6.2: 动态拟合算法 (Dynamic Fitting)
        // 计算文本在基础字号下的实际比例，并反推能最饱满填充框体的最优字号
        let testSize: CGFloat = 50.0
        // 🛡️ 遵循用户建议：不使用默认加粗
        let testFont = NSFont(name: fontName, size: testSize) ?? NSFont.systemFont(ofSize: testSize)
        let metrics = (text as NSString).size(withAttributes: [.font: testFont])
        
        let hRatio = targetHeight / metrics.height
        let wRatio = targetWidth / metrics.width
        
        // 🎯 核心逻辑：取宽/高缩放比的小者，应用 0.94 的填充系数（防宽度溢出）
        let bestRatio = min(hRatio, wRatio)
        return testSize * bestRatio * 0.94
    }

    /// 翻頁時調用：保存當前頁所有狀態到 PageState
    func syncPageToCache(index: Int) {
        pages[index]?.raw.baseCGImage = baseCGImage
        if let img = originalImage { pages[index]?.raw.originalImage = img }
        
        pages[index]?.refined.textLayers = recognizedItems
        pages[index]?.refined.background = inpaintedImage
        pages[index]?.refined.isRefined = (inpaintedImage != nil)
        
        isDirty = recognizedItems.contains { $0.isErased }
        print("💾 [syncPageToCache] 第\(index+1)頁已保存: isRefined=\(pages[index]?.refined.isRefined ?? false)")
    }

    // MARK: - 重置当前页（清除 refine 结果，从原始重新开始）
    func resetPage(at index: Int) {
        guard var page = pages[index] else { return }
        
        print("♻️ [resetPage] 第\(index+1)頁已重置 (保留文字层，清除精炼结果)")
        
        // 1. Reset Refined Bundle
        page.refined.background = nil
        page.refined.isRefined = false
        page.refined.watermarkPattern = ""
        
        // 2. Reset Text Layers states
        for i in 0..<page.refined.textLayers.count {
            page.refined.textLayers[i].isErased = false
            page.refined.textLayers[i].isTextVisible = false // Back to "blue box" mode
            page.refined.textLayers[i].editedText = page.refined.textLayers[i].text // Restore original OCR
            page.refined.textLayers[i].isManualEraser = false
        }
        
        pages[index] = page
        
        // 3. UI Sync (if current)
        if index == currentPageIndex {
            DispatchQueue.main.async {
                self.inpaintedImage = nil
                self.isRefinementFinalized = false // 🚀 CRITICAL FIX: Reset finalized state
                self.recognizedItems = page.refined.textLayers
                self.isDirty = false
                print("📺 [resetPage] UI 同步完成: recognizedItems=\(self.recognizedItems.count), inpaintedImage=nil")
            }
        }
    }

    // MARK: - 全局水印模式
    private(set) var globalErasurePatterns: Set<String> = []

    /// 添加全局水印文字（模糊匹配，标记所有已缓存页的匹配项）
    func addGlobalErasurePattern(_ pattern: String) {
        globalErasurePatterns.insert(pattern)
        print("🚫 [Watermark] 添加全局模式: '\(pattern)'，当前共 \(globalErasurePatterns.count) 个")
        // 立即对所有已缓存页应用
        for index in pages.keys {
            applyPattern(pattern, toPageAt: index)
        }
        // Apply patterns to current page and trigger UI update
        applyGlobalPatterns()
        isDirty = true
    }

    /// 🚀 Enhanced Matching: Apply pattern to specified cached page using trimming and robust comparison
    private func applyPattern(_ pattern: String, toPageAt index: Int) {
        guard var page = pages[index] else { return }
        let lp = pattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lp.isEmpty else { return }
        
        for i in page.refined.textLayers.indices {
            let lt = page.refined.textLayers[i].text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let le = page.refined.textLayers[i].editedText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            // Robust check: bidirectional inclusion
            if lt.contains(lp) || le.contains(lp) || lp.contains(lt) || lp.contains(le) {
                page.refined.textLayers[i].isErased = true
                page.refined.textLayers[i].isTextVisible = false
            }
        }
        pages[index] = page
    }

    /// 🚀 Enhanced Matching: Multi-vector check against global erasure patterns
    func matchesAnyGlobalPattern(item: RecognizedItem) -> Bool {
        guard !globalErasurePatterns.isEmpty else { return false }
        let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let edited = item.editedText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        for pattern in globalErasurePatterns {
            let lp = pattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if lp.isEmpty { continue }
            if text.contains(lp) || edited.contains(lp) || lp.contains(text) || lp.contains(edited) {
                return true
            }
        }
        return false
    }
    
    func applyGlobalPatterns(toIndex: Int? = nil) {
        guard !globalErasurePatterns.isEmpty else { return }
        for pattern in globalErasurePatterns {
            applyPattern(pattern, toIndex: toIndex, currentOnly: true)
        }
    }

    /// Apply specified pattern to current page OR target index cache
    func applyPattern(_ pattern: String, toIndex: Int? = nil, currentOnly: Bool) {
        let lp = pattern.lowercased()
        
        if currentOnly {
            let targetIdx = toIndex ?? self.currentPageIndex
            
            // 🚀 Atomic Update: Apply to UI array if it's the current active page
            if targetIdx == self.currentPageIndex {
                for i in recognizedItems.indices {
                    let lt = recognizedItems[i].text.lowercased()
                    let le = recognizedItems[i].editedText.lowercased()
                    if lt.contains(lp) || le.contains(lp) || lp.contains(lt) || lp.contains(le) {
                        recognizedItems[i].isErased = true
                        recognizedItems[i].isTextVisible = false
                    }
                }
            }
            
            // 🚀 Cache Persistence: Always apply to the page state cache
            if var pageData = pages[targetIdx] {
                var foundInCache = 0
                for i in pageData.refined.textLayers.indices {
                    let lt = pageData.refined.textLayers[i].text.lowercased()
                    let le = pageData.refined.textLayers[i].editedText.lowercased()
                    if lt.contains(lp) || le.contains(lp) || lp.contains(lt) || lp.contains(le) {
                        pageData.refined.textLayers[i].isErased = true
                        pageData.refined.textLayers[i].isTextVisible = false
                        foundInCache += 1
                    }
                }
                pages[targetIdx] = pageData
                if foundInCache > 0 { 
                    print("🚫 [Watermark] Applied to Page \(targetIdx + 1) cache: \(foundInCache) items")
                }
            }
        } else {
            addGlobalErasurePattern(pattern)
        }
    }

    /// 直接从 PageState 缓存恢复指定页（不保存当前状态，安全用于 batch 结束）
    func restoreFromCache(index: Int, completion: @escaping () -> Void) {
        guard let cached = pages[index] else {
            print("⚠️ [restoreFromCache] 第\(index)頁無緩存，跳過")
            completion()
            return
        }
        self.baseCGImage = cached.raw.baseCGImage
        DispatchQueue.main.async {
            self.recognizedItems = cached.refined.textLayers
            self.inpaintedImage = cached.refined.background
            self.originalImage = cached.raw.originalImage
            self.currentPageIndex = index
            print("✅ [restoreFromCache] 第\(index+1)頁恢復: isRefined=\(cached.refined.isRefined)")
            completion()
        }
    }

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
            isErased: true, 
            isTextVisible: false,
            isManualEraser: true // 🚀 核心优化：标记为手动橡皮擦，防止在 Refine 时反弹
        )
        // 🚀 核心修复：直接修改数组，并触发防抖重绘
        DispatchQueue.main.async {
            self.recognizedItems.append(newItem)
            self.isDirty = true
            self.triggerDebouncedInpaint()
        }
    }

    /// 开启防抖重绘，防止画笔移动太快导致频繁调用模型崩溃
    private func triggerDebouncedInpaint() {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
            if !Task.isCancelled {
                self.refreshInpaintedBackground { _ in }
            }
        }
    }

    /// 手动提交笔刷（如在 Lift 鼠标时）
    func commitEraserStroke() {
        saveSnapshot()
        refreshInpaintedBackground { _ in }
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
}
// MARK: - Custom PDFPage Class for Text Layers
class UIBasedPDFPage: PDFPage {
    let background: CGImage
    let items: [AdvancedSlideProcessor.RecognizedItem]
    
    init(background: CGImage, items: [AdvancedSlideProcessor.RecognizedItem], bounds: CGRect) {
        self.background = background
        self.items = items
        super.init()
        // 🔑 關鍵修復：必須顯式設置 bounds，否則 draw() 中 self.bounds(for:) 返回 zero
        self.setBounds(bounds, for: .mediaBox)
    }
    
    override func draw(with box: PDFDisplayBox, to context: CGContext) {
        let mediaBox = self.bounds(for: box)
        
        // 1. 繪製背景圖 (注意：CGContext 繪製 CGImage 的默認坐標系翻轉處理)
        context.saveGState()
        // PDFKit 的 draw 會自動處理一些上下文變換，但為了保險，我們直接在 mediaBox 內繪製
        context.draw(background, in: mediaBox)
        context.restoreGState()
        
        // 2. 獲取底圖與 PDF 的比例，用於縮放字體
        let imageWidth = CGFloat(background.width)
        let scaleFactor = mediaBox.width / imageWidth
        
        for item in items {
            // 💡 只有被标为“擦除”的项才会转为矢量层。水印项(isTextVisible=false)即便擦除了也不绘制文字层。
            if !item.isErased || !item.isTextVisible { continue }
            
            let text = item.editedText.isEmpty ? item.text : item.editedText
            
            // 🚀 核心修復：結合 mediaBox 的 Origin 和 Scale 计算准确坐标
            let rect = CGRect(
                x: mediaBox.origin.x + (item.rect.origin.x * mediaBox.width),
                y: mediaBox.origin.y + (1.0 - item.rect.origin.y - item.rect.size.height) * mediaBox.height,
                width: item.rect.size.width * mediaBox.width,
                height: item.rect.size.height * mediaBox.height
            )
            
            // 🚀 核心修復：將像素級字体大小縮放為 PDF Point 單位
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
        
        // 🚀 精准居中逻辑：计算文字的实际排版边界
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        
        // 水平居中偏移
        let xOffset = (rect.width - lineWidth) / 2.0
        // 垂直居中偏移 (PDF 坐标系 y 轴向上，Baseline 需额外加回 descent)
        let yOffset = (rect.height - (ascent + descent)) / 2.0 + descent
        
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: rect.origin.x + xOffset, y: rect.origin.y + yOffset)
        
        CTLineDraw(line, context)
        context.restoreGState()
    }
}
