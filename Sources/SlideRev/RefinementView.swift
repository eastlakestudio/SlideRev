import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct RefinementView: View {
    @StateObject var processor = AdvancedSlideProcessor()
    @State private var zoomScale: CGFloat = 0.8
    @State private var selectedItemId: UUID?
    @State private var viewMode: ViewMode = .edit
    
    // PDF & File States
    @State private var pdfDocument: PDFDocument?
    @State private var originalPath: String? = nil
    @State private var refinedPath: URL? = nil
    @State private var currentPageIndex: Int = 0
    @State private var totalPageCount: Int = 0
    
    // Dialog & Interaction States
    @State private var showSaveAlert = false
    @State private var showResetAlert = false
    @State private var showRegistryAlert = false
    @State private var registryEntry: RefinementRegistry.Entry? = nil
    @State private var hoverItemId: UUID? = nil
    @State private var isExporting: Bool = false
    @State private var isBatchRefining: Bool = false
    @State private var isExportingPPTX: Bool = false
    @State private var batchProgress: (current: Int, total: Int) = (0, 0)
    
    // Watermark Removal
    @State private var selectedWatermark: String = "A NotebookLM"
    @State private var customWatermark: String = ""
    static let presetWatermarks = ["A NotebookLM", "NotebookLM", "Confidential", "DRAFT", "Internal Only", "Custom..."]
    
    // Eraser Tools
    @State private var isEraserMode: Bool = false
    @State private var eraserCursorPos: CGPoint? = nil
    @State private var lastBrushPoint: CGPoint? = nil
    @State private var brushSize: CGFloat = 24
    
    // feedback toasts
    @State private var showSaveToast: Bool = false
    @State private var showExportError: Bool = false
    @State private var exportErrorMessage: String = ""
    
    // 🚀 V0.9.6.1: Interaction State
    @State private var originPanOffset: CGSize = .zero
    @State private var dragStartOffset: CGSize = .zero
    
    // Error Handling
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    
    // 🚀 V30.0: PRE-WARM MODE (Optimizing UI Flow)
    @State private var isPreWarming: Bool = false

    enum ViewMode: String, CaseIterable {
        case original = "Original", edit = "Editable"
    }

    var body: some View {
        ZStack {
            if originalPath == nil {
                startDashboard
            } else if isPreWarming {
                // 🚀 V30.0: Optimize Screen before Editor
                documentPreWarmView
                    .transition(.opacity)
            } else {
                VStack(spacing: 0) {
                    masterRibbon
                    Divider()
                    workspaceView
                    Divider()
                    statusBar
                }
                .onTapGesture(count: 2) { maximizeWindow() } // 🚀 V0.9.6.1: Double tap to maximize
            }
            
            if isExporting || isBatchRefining || isExportingPPTX {
                exportingOverlay
            }

            // Success Toast
            if showSaveToast {
                VStack {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.white)
                        Text("File Saved Successfully!")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 30)
                    .background(
                        RoundedRectangle(cornerRadius: 24)
                            .fill(Color.accentColor.opacity(0.95))
                            .shadow(color: .black.opacity(0.2), radius: 20)
                    )
                    .transition(.scale.combined(with: .opacity))
                }
                .zIndex(200)
            }
        }
        .frame(minWidth: 1200, minHeight: 750)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear { setupScrollWheelMonitor() }
        .alert("Resume Session?", isPresented: $showRegistryAlert) {
            Button("Restore Draft") { 
                if let entry = registryEntry, let metaPath = entry.metadataPath {
                    self.refinedPath = URL(fileURLWithPath: entry.refinedPath)
                    self.processor.loadSession(from: URL(fileURLWithPath: metaPath))
                    loadPage(at: 0, from: self.pdfDocument)
                } else {
                    loadPage(at: 0, from: self.pdfDocument)
                }
            }
            Button("Start Fresh") {
                loadPage(at: 0, from: self.pdfDocument)
            }
            Button("Cancel", role: .cancel) { originalPath = nil; pdfDocument = nil }
        } message: {
            Text("We found a previous version of this document. Would you like to continue editing where you left off?")
        }
        .alert("Unsaved Changes", isPresented: $showSaveAlert) {
            Button("Save and Exit") { saveToNewPDF(); exitSession() }
            Button("Exit without Saving", role: .destructive) { exitSession() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You have unsaved changes. Would you like to save them before leaving?")
        }
        .onChange(of: processor.preWarmedCount) { oldValue, newValue in
            // 🚀 V30.0: Auto-transition when pre-warming is complete (up to 40 pages)
            let targetCount = min(40, totalPageCount)
            if newValue >= targetCount && isPreWarming {
                withAnimation(.spring(response: 0.8, dampingFraction: 0.825)) {
                    isPreWarming = false
                }
            }
        }
        .alert("Export Failed", isPresented: $showExportError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(exportErrorMessage)
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    // 🚀 V28.0: Minimalist Bottom-Right Progress Card (No mask, zero obscuration)
    private var exportingOverlay: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                // The Progress Card
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        // Small Animated Icon
                        ZStack {
                            Circle()
                                .stroke(Color.accentColor.opacity(0.1), lineWidth: 3)
                                .frame(width: 32, height: 32)
                            
                            ProgressView()
                                .controlSize(.small)
                                .tint(.accentColor)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isExportingPPTX ? "Exporting..." : "Visual Refinement")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                            
                            Text("Page \(batchProgress.current) / \(batchProgress.total)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if isBatchRefining {
                        VStack(spacing: 4) {
                            ProgressView(value: Double(batchProgress.current), total: Double(max(1, batchProgress.total)))
                                .progressViewStyle(.linear)
                                .tint(.accentColor)
                                .frame(width: 140)
                            
                            Text(processor.batchStatus)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.accentColor.opacity(0.8))
                                .lineLimit(1)
                                .frame(width: 140)
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(NSColor.windowBackgroundColor).opacity(0.9))
                        .shadow(color: .black.opacity(0.15), radius: 15, x: 0, y: 8)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                )
            }
        }
        .padding(24)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }
    
    // 🚀 V0.9.9.9: Dynamic Scanning Animation for Batch Processing
    struct ScanningPageView: View {
        @State private var scanOffset: CGFloat = -80
        
        var body: some View {
            ZStack {
                // Document Base
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.1))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.3), lineWidth: 2))
                
                // Abstract Content Lines
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(0..<6) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(i % 2 == 0 ? 0.3 : 0.1))
                            .frame(width: i == 0 ? 60 : (i == 5 ? 40 : 80), height: 6)
                    }
                }
                
                // Laser Scanning Line
                Rectangle()
                    .fill(LinearGradient(gradient: Gradient(colors: [.clear, .accentColor, .clear]), startPoint: .top, endPoint: .bottom))
                    .frame(height: 40)
                    .offset(y: scanOffset)
                    .blendMode(.screen)
            }
            .onAppear {
                withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                    scanOffset = 80
                }
            }
        }
    }

    // MARK: - 1. Dashboard
    var startDashboard: some View {
        VStack(spacing: 40) {
            Spacer()
            
            VStack(spacing: 12) {
                Text("SlideRev...")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                VStack(spacing: 6) {
                    Text("Professional AI Slide Reconstructor")
                        .font(.system(size: 18, weight: .semibold)).foregroundColor(.accentColor)
                    
                    Text("Unlock Your NotebookLM Citations & AI Images")
                        .font(.headline).foregroundColor(.primary)
                        
                    Text("Transform flat PDFs and AI-generated snapshots back to professional, fully editable PPTX slides.")
                        .font(.subheadline).foregroundColor(.secondary)
                        .multilineTextAlignment(.center).frame(maxWidth: 540)
                        
                    Text("Seamlessly convert screenshots, mobile captures, and citations into vectorized PPTX elements.")
                        .font(.caption).foregroundColor(.secondary.opacity(0.8)).padding(.top, 4)
                }
            }
            
            Button(action: selectPDF) {
                VStack(spacing: 30) {
                    GraphicProcessView() 
                        .foregroundColor(.primary) // Prevent color override from button
                        .id(UUID()) // Ensure animation starts correctly
                    
                    VStack(spacing: 10) {
                        Text("Import PDF, Images or NotebookLM Citations")
                            .font(.title3.bold())
                        Text("Click to transform your documents and AI snapshots into editable PPTX")
                            .font(.subheadline).foregroundColor(.secondary)
                        Text("Supported: PDF, PNG, JPG, JPEG, HEIC, TIFF")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .opacity(0.5)
                    }
                }
                .frame(width: 600, height: 340)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 24).fill(Color.accentColor.opacity(0.04))
                        RoundedRectangle(cornerRadius: 24).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [8]))
                    }
                )
                .foregroundColor(.accentColor).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor)) 
        .onTapGesture(count: 2) { maximizeWindow() } 
    }

    struct GraphicProcessView: View {
        @State private var animate = false
        var body: some View {
            HStack(spacing: 30) {
                CircleNode(icon: "photo", label: "AI Image", color: .gray)
                ArrowLine(animate: animate)
                CircleNode(icon: "sparkles", label: "SlideRev AI", color: .accentColor, pulse: true)
                ArrowLine(animate: animate)
                CircleNode(icon: "p.square.fill", label: "Editable PPTX", color: .orange)
            }
            .onAppear { withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: false)) { animate = true } }
        }
        
        struct CircleNode: View {
            let icon: String; let label: String; let color: Color; var pulse: Bool = false
            @State private var s: CGFloat = 1.0
            var body: some View {
                VStack(spacing: 10) {
                    ZStack {
                        Circle().fill(color.opacity(0.12)).frame(width: 70, height: 70)
                        Image(systemName: icon).font(.title).foregroundColor(color.opacity(0.9))
                    }
                    .scaleEffect(pulse ? s : 1.0)
                    .onAppear { if pulse { withAnimation(.easeInOut(duration: 1).repeatForever()) { s = 1.1 } } }
                    Text(label).font(.caption2).bold().foregroundColor(.secondary)
                }
            }
        }
        
        struct ArrowLine: View {
            var animate: Bool
            var body: some View {
                ZStack {
                    Rectangle().fill(Color.secondary.opacity(0.2)).frame(width: 50, height: 2)
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold))
                        .foregroundColor(.accentColor)
                        .offset(x: animate ? 25 : -25)
                        .opacity(animate ? 0 : 1)
                }
            }
        }
    }

    private func maximizeWindow() {
        if let window = NSApp.mainWindow { window.setIsZoomed(!window.isZoomed) }
    }
    
    // MARK: - 2. Workspace
    var workspaceView: some View {
        GeometryReader { geo in
            ScrollView([.horizontal, .vertical]) {
                ZStack {
                    if let image = (viewMode == .edit ? (processor.inpaintedImage ?? processor.originalImage) : processor.originalImage) {
                        imageWorkspaceContent(image: image, viewportSize: geo.size)
                    } else {
                        // 🚀 V29.4: LOADING FALLBACK
                        // Prevents 'White Screen' during background rendering or skeleton-hit latency
                        refiningOverlay
                            .frame(width: geo.size.width - 80, height: geo.size.height - 80)
                            .cornerRadius(24)
                    }
                }
                .padding(40)
                .frame(minWidth: geo.size.width, minHeight: geo.size.height)
            }
        }
    }

    @ViewBuilder
    private func imageWorkspaceContent(image: NSImage, viewportSize: CGSize) -> some View {
        let iw = image.size.width * zoomScale
        let ih = image.size.height * zoomScale
        
        let isPanningAllowed = (iw > viewportSize.width - 80) || (ih > viewportSize.height - 80)
        
        ZStack {
            // 1. Base Layer: Images
            ZStack {
                // Bottom: Original Image
                if let original = processor.originalImage {
                    Image(nsImage: original)
                        .resizable().aspectRatio(contentMode: .fit)
                        // 🚀 v37.6: Only hide original IF the inpainted background safely took over.
                        // Prevents the "everything disappeared" blank screen bug.
                        .opacity((viewMode == .edit && processor.inpaintedImage != nil) ? 0 : 1) 
                }
                
                // Top: Inpainted Image
                if viewMode == .edit, let inpainted = processor.inpaintedImage {
                    if processor.isRefinementFinalized {
                        // 🚀 Final State: Full clean background
                        Image(nsImage: inpainted)
                            .resizable().aspectRatio(contentMode: .fit)
                    } else {
                        // ⚡ Animation State: Masked Reveal (Character-level)
                        Image(nsImage: inpainted)
                            .resizable().aspectRatio(contentMode: .fit)
                            .mask(ErasedItemsMask(items: processor.recognizedItems, imageSize: image.size))
                    }
                }
            }
            .frame(width: iw, height: ih)
            
            // 2. Metadata Overlay (Text Boxes)
            if viewMode == .edit {
                metadataOverlay(imageSize: image.size)
                    .allowsHitTesting(!isEraserMode)
            }
            
            // 3. 🚀 TOP-LEVEL ERASER TRACKING LAYER
            if isEraserMode {
                Color.clear
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        if case .active(let point) = phase {
                            eraserCursorPos = point
                        } else {
                            eraserCursorPos = nil
                        }
                    }
                    .gesture(eraserGesture(iw: iw, ih: ih, imageSize: image.size))
            }
            
            // 4. Eraser Visual Cursor
            eraserOverlay.allowsHitTesting(false)
        }
        .frame(width: iw, height: ih)
        .background(Color.white)
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 3)
        .offset(viewMode == .original ? originPanOffset : .zero)
        .gesture(originPanGesture(isAllowed: isPanningAllowed)) 
        .onTapGesture { if !isEraserMode { selectedItemId = nil } }
        .onHover { inside in
            if inside && viewMode == .original { NSCursor.openHand.set() }
        }
        .onChange(of: zoomScale) { old, new in
            if !isPanningAllowed {
                withAnimation(.spring()) {
                    originPanOffset = .zero
                    dragStartOffset = .zero
                }
            }
        }
    }

    @ViewBuilder
    private var refiningOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.accentColor.opacity(0.05))
            
            VStack(spacing: 20) {
                ScanningPageView()
                    .frame(width: 80, height: 110)
                    .scaleEffect(0.8)
                
                Text("AI Refining...")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.accentColor)
            }
        }
        .transition(.opacity)
    }

    // 🚀 V0.9.9.13: Localized Background reveal mask for granular refinement (Character-level)
    struct ErasedItemsMask: Shape {
        var items: [AdvancedSlideProcessor.RecognizedItem]
        var imageSize: CGSize
        
        func path(in rect: CGRect) -> Path {
            var path = Path()
            guard imageSize.width > 0 && imageSize.height > 0 else { return path }
            
            let scaleX = rect.width / imageSize.width
            let scaleY = rect.height / imageSize.height
            
            for item in items {
                guard item.isErased else { continue }
                let progress = item.refinementProgress
                // 🚀 LEAD PROGRESS: Erasure finishes at 75% of total animation time
                let leadProgress = min(1.0, progress * 1.33)
                let pRect = item.pixelRect
                
                let wipeWidth = pRect.width * CGFloat(leadProgress)
                let itemPath = CGRect(x: pRect.origin.x * scaleX, y: pRect.origin.y * scaleY, width: wipeWidth * scaleX, height: pRect.height * scaleY)
                path.addRect(itemPath)
            }
            return path
        }
    }

    @ViewBuilder
    private var eraserOverlay: some View {
        if isEraserMode, let p = eraserCursorPos {
            Rectangle()
                .stroke(Color.red, lineWidth: 1.5)
                .background(Color.red.opacity(0.15))
                .frame(width: brushSize, height: brushSize)
                .position(p)
        }
    }

    private func eraserGesture(iw: CGFloat, ih: CGFloat, imageSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                guard isEraserMode else { return } // 🚀 Strict mode check
                eraserCursorPos = v.location
                let p = v.location
                if let last = lastBrushPoint {
                    let dist = sqrt(pow(p.x - last.x, 2) + pow(p.y - last.y, 2))
                    if dist < brushSize * 0.5 { return }
                }
                let normRect = CGRect(
                    x: (v.location.x - brushSize/2) / iw,
                    y: (v.location.y - brushSize/2) / ih,
                    width: brushSize / iw,
                    height: brushSize / ih
                )
                processor.addEraserPatch(normRect, imageSize: imageSize)
                lastBrushPoint = p
            }
            .onEnded { _ in 
                processor.commitEraserStroke()
                lastBrushPoint = nil
            }
    }
    
    // MARK: - 3. Ribbon Toolbar
    var masterRibbon: some View {
        HStack(spacing: 8) { // 🚀 Reduced from 15 to shift things left
            // LEFT CLUSTER: Navigation, ViewMode, and Watermark Tools
            HStack(spacing: 6) { // 🚀 Reduced from 12 to pull Group 3 left
                // Group 1: Navigation & Basic Controls
                HStack(spacing: 8) {
                    Button(action: { if processor.isDirty { showSaveAlert = true } else { exitSession() } }) {
                        Image(systemName: "house.fill").font(.title3)
                    }
                    .buttonStyle(.plain).foregroundColor(.secondary)
                    .help("Home")
                    
                    Divider().frame(height: 24).padding(.horizontal, 2)
                    
                    Picker("", selection: $viewMode) { 
                        ForEach(ViewMode.allCases, id: \.self) { Text($0.rawValue).tag($0) } 
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                    .controlSize(.small)
                }
                
                Divider().frame(height: 24).padding(.horizontal, 2)
                
                // Group 3: Watermark Tools (Anchord Left V0.9.6.11)
                HStack(spacing: 5) { // 🚀 Narrower internal spacing
                    Image(systemName: "seal.fill").foregroundColor(.orange).font(.system(size: 14))
                    
                    Picker("", selection: $selectedWatermark) {
                        ForEach(Self.presetWatermarks, id: \.self) { Text($0).tag($0) }
                    }
                    .frame(width: 160).controlSize(.small)
                    .help("Select a preset watermark pattern to identify")
                    
                    if selectedWatermark == "Custom..." {
                        TextField("Text", text: $customWatermark)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 320) // 🚀 Larger input box (+20% from 264)
                            .controlSize(.small)
                            .help("Type your custom watermark text here")
                    }
                    
                    Divider().frame(height: 24).padding(.horizontal, 2)
                    
                    let effectiveWatermark = selectedWatermark == "Custom..." ? customWatermark : selectedWatermark
                    
                    Button(action: { 
                        if viewMode == .original { withAnimation { viewMode = .edit } }
                        applyWatermarkToCurrentPage(effectiveWatermark) 
                    }) {
                        Image(systemName: "doc.fill") // 🚀 Single Page Icon
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 32, height: 32)
                            .background(Color.orange.opacity(0.12)).foregroundColor(.orange).cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help("Remove watermark from CURRENT page")
                    .disabled(effectiveWatermark.isEmpty)
                    
                    Button(action: { 
                        if viewMode == .original { withAnimation { viewMode = .edit } }
                        applyWatermarkToAllPages(effectiveWatermark) 
                    }) {
                        Image(systemName: "doc.on.doc.fill") // 🚀 Multi Page Icon
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 32, height: 32)
                            .background(Color.blue.opacity(0.12)).foregroundColor(.blue).cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help("Remove watermark from ALL pages")
                    .disabled(effectiveWatermark.isEmpty)
                }
                .padding(.horizontal, 10).frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.04)))
            }

            Spacer()

            // Group 4: Processing Actions
            HStack(spacing: 8) {
                if isEraserMode {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil.and.outline").font(.caption)
                        Slider(value: $brushSize, in: 10...100).frame(width: 80).controlSize(.mini)
                        Text("\(Int(brushSize))").font(.system(.caption2, design: .monospaced)).frame(width: 25)
                    }
                    .padding(.horizontal, 8).frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.05)))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                
                Button(action: { isEraserMode.toggle(); selectedItemId = nil }) {
                    Image(systemName: isEraserMode ? "eraser.fill" : "eraser")
                        .font(.title3).padding(6)
                        .background(isEraserMode ? Color.accentColor.opacity(0.12) : Color.black.opacity(0.04))
                        .cornerRadius(6)
                        .foregroundColor(isEraserMode ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help("Eraser Tool: Wipe out background content manually")
                
                Divider().frame(height: 24).padding(.horizontal, 2)

                Button(action: { processor.undo() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.uturn.backward").baselineOffset(-1)
                        Text("Undo").fixedSize() // 🚀 Protect label from being squeezed
                    }
                    .font(.subheadline).bold()
                    .frame(height: 32)
                    .padding(.horizontal, 10)
                    .background(Color.primary.opacity(0.08))
                    .foregroundColor(.accentColor)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .help("Undo last action (Cmd+Z)")

                Button(action: resetCurrentPage) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise").baselineOffset(-1)
                        Text("Reset").fixedSize()
                    }
                    .font(.subheadline).bold()
                    .frame(height: 32)
                    .padding(.horizontal, 10)
                    .background(Color.primary.opacity(0.08))
                    .foregroundColor(.primary)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .help("Reset current page to original state")

                Button(action: { 
                    if viewMode == .original { withAnimation { viewMode = .edit } }
                    processor.refinePage { _ in } 
                }) {
                    Label("Refine", systemImage: "sparkles").font(.subheadline).bold()
                        .frame(width: 120, height: 32)
                        .background(Color.accentColor).foregroundColor(.white).cornerRadius(8)
                }
                .buttonStyle(.plain)
                .help("Trigger AI cleanup for this page")

                Button(action: startBatchRefine) {
                    Label("Batch Refine", systemImage: "sparkles.rectangle.stack").font(.subheadline).bold()
                        .frame(width: 120, height: 32)
                        .background(Color.blue).foregroundColor(.white).cornerRadius(8)
                }.buttonStyle(.plain).help("AI Refine ALL pages in doc")

                Divider().frame(height: 24).padding(.horizontal, 2)

                Button(action: saveToNewPDF) {
                    Image(systemName: "doc.fill.badge.plus")
                        .font(.title2)
                        .frame(width: 32, height: 32)
                        .background(Color.accentColor).foregroundColor(.white).cornerRadius(8)
                }.buttonStyle(.plain).help("Save as Refined PDF")

                Button(action: exportToPPTX) {
                    Image(systemName: "square.and.arrow.up.fill")
                        .font(.title2)
                        .frame(width: 32, height: 32)
                        .background(LinearGradient(colors: [.orange, .red], startPoint: .top, endPoint: .bottom))
                        .cornerRadius(8)
                }.buttonStyle(.plain).help("Export to Editable PPTX")
            }
        }
        .padding(.horizontal, 16).padding(.leading, 12).frame(height: 60).background(Color(NSColor.windowBackgroundColor)).shadow(color: .black.opacity(0.05), radius: 1, y: 1)
    }

    var statusBar: some View {
        HStack(spacing: 20) {
            if selectedItemId != nil {
                Label("Selected Text Block", systemImage: "pencil.circle").foregroundColor(.accentColor)
            } else if isEraserMode {
                Label("Eraser Tool Active: Wipe out background content", systemImage: "eraser.fill").foregroundColor(.accentColor)
            } else {
                Label("SlideRev v0.9.6.21 Ready", systemImage: "checkmark.circle.fill").foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "target").font(.caption2).foregroundColor(.secondary)
                    Slider(value: $processor.ocrConfidenceThreshold, in: 0.30...0.95)
                        .frame(width: 70).controlSize(.mini)
                    Text(String(format: "%.2f", processor.ocrConfidenceThreshold))
                        .font(.system(.caption2, design: .monospaced)).foregroundColor(.secondary).frame(width: 32)
                    
                    Button(action: { processor.ocrConfidenceThreshold = 0.50 }) {
                        Image(systemName: "arrow.counterclockwise.circle").font(.caption2)
                    }
                    .buttonStyle(.plain).foregroundColor(.secondary)
                    .help("Reset OCR Threshold to default (0.50)")
                }
                .help("OCR Confidence Threshold: Lower values catch more text, higher values are stricter.")
                
                Divider().frame(height: 16)
                
                HStack(spacing: 8) {
                    Button(action: prevPage) { Image(systemName: "chevron.left") }
                        .disabled(currentPageIndex == 0)
                        .help("Previous Page")
                    Text("\(currentPageIndex + 1) / \(max(1, totalPageCount))")
                        .font(.system(.caption, design: .monospaced).bold())
                    Button(action: nextPage) { Image(systemName: "chevron.right") }
                        .disabled(currentPageIndex >= totalPageCount - 1)
                        .help("Next Page")
                }.padding(.horizontal, 8).padding(.vertical, 4).background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.1)))
                
                HStack(spacing: 4) {
                    Button(action: { zoomScale = max(0.2, zoomScale - 0.2) }) { Image(systemName: "minus.magnifyingglass") }
                        .help("Zoom Out")
                    Slider(value: $zoomScale, in: 0.1...3.0).frame(width: 80).controlSize(.small)
                        .help("Zoom Control")
                    Button(action: { zoomScale = min(3.0, zoomScale + 0.2) }) { Image(systemName: "plus.magnifyingglass") }
                        .help("Zoom In")
                    
                    Button(action: { withAnimation { autoFit() } }) {
                        Text("\(Int(zoomScale * 100))%")
                            .font(.system(.caption, design: .monospaced).bold())
                            .frame(width: 45)
                    }.buttonStyle(.plain).help("Auto Fit / Reset Zoom")
                }
            }
        }.padding(.horizontal, 20).frame(height: 32).background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private func metadataOverlay(imageSize: CGSize) -> some View {
        let width = imageSize.width * zoomScale
        let height = imageSize.height * zoomScale
        ZStack(alignment: .topLeading) {
            ForEach($processor.recognizedItems) { $item in
                RecognizedItemOverlayView(item: $item, width: width, height: height, zoomScale: zoomScale, selectedItemId: $selectedItemId, hoverItemId: $hoverItemId, processor: processor)
                    .zIndex(selectedItemId == item.id ? 1 : 0)
            }
        }.frame(width: width, height: height) 
    }

    // MARK: - 4. Methods
    func selectPDF() {
        print("📂 [UI] Opening File Selection Panel...")
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .png, .jpeg, .tiff, .heic, .image]
        panel.message = "Choose PDF or Image to transform"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        
        panel.begin { result in
            if result == .OK, let url = panel.url {
                self.openDocument(at: url)
            }
        }
    }

    private func openDocument(at url: URL) {
        processor.clearAllStates()
        
        let ext = url.pathExtension.lowercased()
        let isImage = ["png", "jpg", "jpeg", "tiff", "bmp", "heic"].contains(ext)
        
        if isImage {
            guard let image = NSImage(contentsOf: url) else {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to load image at \(url.lastPathComponent)"
                    self.showErrorAlert = true
                }
                return
            }
            
            let pdfDoc = PDFDocument()
            if let pdfPage = PDFPage(image: image) {
                pdfDoc.insert(pdfPage, at: 0)
                DispatchQueue.main.async {
                    self.originalPath = url.path
                    self.pdfDocument = pdfDoc
                    self.totalPageCount = 1
                    loadPage(at: 0, from: pdfDoc)
                }
            }
        } else {
            guard let doc = PDFDocument(url: url) else { return }
            DispatchQueue.main.async {
                self.originalPath = url.path
                self.pdfDocument = doc
                self.totalPageCount = doc.pageCount
                
                if doc.pageCount > 0 {
                    // 🚀 v37.1: Synchronous Waiting Gate for < 40 pages
                    self.processor.preWarmedCount = 0
                    if doc.pageCount <= 40 {
                        withAnimation { self.isPreWarming = true }
                    }
                    
                    loadPage(at: 0, from: doc)
                    preWarmAllPages(doc: doc)
                } else {
                    self.errorMessage = "Loaded PDF has no pages."
                    self.showErrorAlert = true
                }
            }
        }
    }

    private func preWarmAllPages(doc: PDFDocument) {
        let total = doc.pageCount
        let limit = min(total, 40)
        
        // 🚀 v37.2: Start from 0. The processor handles cache hits internally.
        if limit > 0 {
            for i in 0..<limit {
                if let page = doc.page(at: i) {
                    processor.preWarmPage(at: i, page: page)
                }
            }
        }
    }

    func saveToNewPDF() {
        guard let sourcePath = originalPath else { return }
        let sourceURL = URL(fileURLWithPath: sourcePath)
        
        if let targetURL = refinedPath {
            performExport(source: sourceURL, target: targetURL)
        } else {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = sourceURL.deletingPathExtension().lastPathComponent + "_Refined.pdf"
            if panel.runModal() == .OK, let targetURL = panel.url {
                refinedPath = targetURL
                performExport(source: sourceURL, target: targetURL)
                
                let metaURL = targetURL.deletingPathExtension().appendingPathExtension("json")
                processor.saveSession(to: metaURL)
                
                var registry = RefinementRegistry.load()
                registry.register(original: sourceURL, refined: targetURL, metadata: metaURL)
            }
        }
    }

    private func performExport(source: URL, target: URL) {
        processor.syncPageToCache(index: currentPageIndex)
        isExporting = true
        
        let ext = source.pathExtension.lowercased()
        let isImage = ["png", "jpg", "jpeg", "tiff", "bmp", "heic"].contains(ext)
        let sourceDoc = isImage ? self.pdfDocument : nil
        let sourceURL = isImage ? nil : source
        
        processor.saveAsTextPDF(sourceURL: sourceURL, sourceDocument: sourceDoc, destURL: target) { success in
            DispatchQueue.main.async {
                self.isExporting = false
                if success {
                    self.processor.isDirty = false
                    self.showSaveToast = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.showSaveToast = false }
                }
            }
        }
    }
    
    private func exitSession() {
        processor.clearCache()
        
        pdfDocument = nil
        processor.originalImage = nil
        refinedPath = nil
        originalPath = nil
    }

    private func loadPage(at index: Int, from document: PDFDocument? = nil) {
        let docToUse = document ?? self.pdfDocument
        
        guard let doc = docToUse, index < doc.pageCount, let page = doc.page(at: index) else {
            return 
        }
        processor.syncPageToCache(index: currentPageIndex)
        
        self.pdfDocument = doc
        self.totalPageCount = doc.pageCount
        self.currentPageIndex = index
        self.processor.currentPageIndex = index
        self.processor.totalPageCount = doc.pageCount
        
        processor.processPage(page, at: index) { success in 
            if success {
                originPanOffset = .zero
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { autoFit() }
            }
        }
    }
    
    private func prevPage() { if currentPageIndex > 0 { loadPage(at: currentPageIndex - 1) } }
    private func nextPage() { if currentPageIndex < totalPageCount - 1 { loadPage(at: currentPageIndex + 1) } }

    private func exportToPPTX() {
        guard let sourcePath = originalPath else { return }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.presentation]
        savePanel.nameFieldStringValue = URL(fileURLWithPath: sourcePath).deletingPathExtension().lastPathComponent + ".pptx"
        guard savePanel.runModal() == .OK, let targetURL = savePanel.url else { return }
        
        isExportingPPTX = true
        batchProgress = (0, totalPageCount)
        
        DispatchQueue.global(qos: .userInitiated).async {
            let total = self.totalPageCount
            var fullPages = self.processor.pages
            let doc = PDFDocument(url: URL(fileURLWithPath: sourcePath))
            
            for i in 0..<total {
                if fullPages[i] == nil, let page = doc?.page(at: i) {
                    DispatchQueue.main.async { self.batchProgress = (i + 1, total) }
                    let snapshot = self.processor.takeOriginalSnapshot(page: page)
                    fullPages[i] = AdvancedSlideProcessor.PageState(
                        pageIndex: i,
                        pdfPage: page,
                        visualSize: snapshot.size,
                        raw: AdvancedSlideProcessor.RawData(
                            originalImage: snapshot,
                            baseCGImage: snapshot.cgImage(forProposedRect: nil, context: nil, hints: nil),
                            pdfSize: page.bounds(for: .mediaBox).size
                        ),
                        refined: AdvancedSlideProcessor.RefinedBundle(
                            background: nil,
                            textLayers: [],
                            watermarkPattern: nil,
                            isRefined: false
                        ),
                        isOCRComplete: false
                    )
                }
            }
            
            PPTXExporter.shared.export(pages: fullPages, to: targetURL, progress: { current, total in
                DispatchQueue.main.async {
                    self.batchProgress = (current, total)
                }
            }) { success, message in
                DispatchQueue.main.async {
                    self.isExportingPPTX = false
                    if success {
                        self.showSaveToast = true
                        NSWorkspace.shared.activateFileViewerSelecting([targetURL])
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { self.showSaveToast = false }
                    } else {
                        self.exportErrorMessage = message
                        self.showExportError = true
                    }
                }
            }
        }
    }

    private func autoFit() {
        guard let size = processor.originalImage?.size else { return }
        if let window = NSApp.mainWindow {
            let cw = window.frame.width - 60 - 80 
            let ch = window.frame.height - 140 - 80
            zoomScale = min(cw / size.width, ch / size.height, 1.0)
        }
    }

    private func resetCurrentPage() {
        selectedItemId = nil
        processor.resetPage(at: currentPageIndex)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { 
            autoFit() 
        }
    }

    private func startBatchRefine() {
        if viewMode == .original { withAnimation { viewMode = .edit } }
        print("🚀 [Batch] startBatchRefine called. originalPath: \(originalPath ?? "nil")")
        guard let sourcePath = originalPath else { 
            print("❌ [Batch] Aborted: originalPath is nil")
            return 
        }
        let loadURL = URL(fileURLWithPath: sourcePath)
        
        processor.syncPageToCache(index: currentPageIndex)
        
        // 🚀 V27.5.3 Optimization: Start in background, only show UI after total is calculated
        processor.batchStatus = "Scanning PDF Structures..."
        
        DispatchQueue.global(qos: .userInitiated).async {
            guard let doc = PDFDocument(url: loadURL), doc.pageCount > 0 else {
                print("⚠️ [Batch] Not a valid multi-page PDF. Checking if candidate is single image...")
                
                // 🚀 Fallback for single image (PNG/JPG)
                let ext = loadURL.pathExtension.lowercased()
                if ["png", "jpg", "jpeg", "webp"].contains(ext) {
                    print("🖼️ [Batch] Single Image Mode Detected. Refining directly...")
                    DispatchQueue.main.async { 
                        self.batchProgress = (1, 1) 
                        self.isBatchRefining = true
                        self.processor.batchStatus = "Optimizing Image Background..."
                    }
                    self.processor.refinePage { success in
                        DispatchQueue.main.async { 
                            self.isBatchRefining = false
                            self.processor.batchStatus = "Image Refinement Complete."
                        }
                    }
                } else {
                    print("❌ [Batch] Unsupported file format for batch: \(ext)")
                    DispatchQueue.main.async { self.isBatchRefining = false }
                }
                return 
            }
            
            let total = doc.pageCount
            let savedIndex = self.currentPageIndex
            
            // 🚀 Step 1: Pre-initialize PageState skeletons to ensure switchToPage has context for every page
            for i in 0..<total {
                if self.processor.pages[i] == nil, let page = doc.page(at: i) {
                    let pixelSize = page.bounds(for: .mediaBox).size
                    let emptyState = AdvancedSlideProcessor.PageState(
                        pageIndex: i, 
                        pdfPage: page, 
                        visualSize: pixelSize,
                        raw: .init(originalImage: nil, baseCGImage: nil),
                        refined: .init(background: nil, textLayers: [], watermarkPattern: nil, isRefined: false)
                    )
                    DispatchQueue.main.async { self.processor.pages[i] = emptyState }
                }
            }
            
            // 🚀 Step 2: NOW show the progress UI and persist the document
            // 🚀 Fix (v27.6.6): MUST assign to self.pdfDocument to provide a strong reference!
            // This prevents the document and its pages from being released prematurely.
            DispatchQueue.main.async { 
                self.pdfDocument = doc 
                self.processor.activeDocument = doc 
                self.batchProgress = (0, total)
                self.isBatchRefining = true 
                self.processor.batchStatus = "Starting Visual Refinement..."
                self.processor.syncPageToCache(index: self.currentPageIndex)
                
                func processNext(_ index: Int) {
                    if index >= total {
                        DispatchQueue.main.async {
                            self.batchProgress = (total, total)
                            self.isBatchRefining = false
                            self.processor.batchStatus = "Batch Refinement Complete."
                            self.processor.switchToPage(index: savedIndex)
                        }
                        return
                    }
                    
                    DispatchQueue.main.async {
                        self.batchProgress = (index + 1, total)
                        
                        // 🚀 v36.0: Ensure we WAIT for switchToPage to complete before refining
                        self.processor.switchToPage(index: index) { success in
                            guard success else { 
                                print("⚠️ [Batch] Failed to switch to page \(index), skipping...")
                                processNext(index + 1)
                                return 
                            }
                            
                            // 🚀 v36.0: Delay refinement slightly to let Main UI catch up
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                // 🚀 v36.0: autoreleasepool MUST be INSIDE the async block to be effective
                                autoreleasepool {
                                    self.processor.refinePage { _ in
                                        // 🚀 v33.0: Double-safety - force clear undoStack in batch mode
                                        self.processor.clearUndoStack() 
                                        
                                        // 🚀 v36.0: Progressively sync every page to cache during batch
                                        self.processor.syncPageToCache(index: index)
                                        
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                            processNext(index + 1)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
                processNext(0)
            }
        }
    }

    private func applyWatermarkToCurrentPage(_ pattern: String) {
        guard !pattern.isEmpty else { return }
        processor.applyPattern(pattern, toIndex: nil, currentOnly: true)
        processor.refreshInpaintedBackground { _ in
            self.processor.syncPageToCache(index: self.currentPageIndex)
        }
    }

    private func applyWatermarkToAllPages(_ pattern: String) {
        guard !pattern.isEmpty else { return }
        processor.addGlobalErasurePattern(pattern)
        processor.applyPattern(pattern, toIndex: nil, currentOnly: true)
        processor.refreshInpaintedBackground { _ in
            self.processor.syncPageToCache(index: self.currentPageIndex)
        }
    }

    private func setupScrollWheelMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            // 🚀 V0.9.6.14: Support Hand Cursor persistence during scroll
            if self.viewMode == .original {
                NSCursor.openHand.set()
            }
            
            if event.modifierFlags.contains(.control) {
                let delta = event.scrollingDeltaY
                if delta != 0 {
                    DispatchQueue.main.async {
                        let multiplier: CGFloat = delta > 0 ? 1.05 : 0.95
                        zoomScale = max(0.1, min(3.0, zoomScale * multiplier))
                    }
                    return nil
                }
            }
            return event
        }
    }
    
    // MARK: - Origin Mode Pan Gesture
    private func originPanGesture(isAllowed: Bool) -> some Gesture {
        DragGesture(minimumDistance: 1.0) // 🚀 Slightly distance to avoid mis-fire
            .onChanged { value in
                // 🚀 Guard: Only active in original mode, when content overflow AND NOT ERASING
                guard self.viewMode == .original && isAllowed && !isEraserMode else { return }
                
                if dragStartOffset == .zero { dragStartOffset = originPanOffset }
                let delta = value.translation
                // Apply panning based on start position
                originPanOffset = CGSize(
                    width: dragStartOffset.width + delta.width,
                    height: dragStartOffset.height + delta.height
                )
                NSCursor.closedHand.set() // 🚀 Grabbing state
            }
            .onEnded { _ in
                guard self.viewMode == .original && isAllowed else { return }
                dragStartOffset = originPanOffset
                NSCursor.openHand.set() // 🚀 Release to open hand
            }
    }

    // 🚀 V30.0: DOCUMENT PRE-WARM OVERLAY
    var documentPreWarmView: some View {
        ZStack {
            // Premium Gradient Background
            LinearGradient(
                gradient: Gradient(colors: [Color.accentColor.opacity(0.1), Color.black.opacity(0.05)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 40) {
                // Glassmorphism Card
                VStack(spacing: 30) {
                    ProgressView()
                        .scaleEffect(2.0)
                        .padding(.bottom, 10)
                    
                    VStack(spacing: 12) {
                        Text("Optimizing Document")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                        
                        Text("Achieving zero-latency AI access for your slides...")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                    
                    // Progress Bar
                    VStack(spacing: 10) {
                        let target = min(40, totalPageCount)
                        let progress = Double(processor.preWarmedCount) / max(1.0, Double(target))
                        
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .tint(.accentColor)
                            .frame(width: 300)
                        
                        Text("\(processor.preWarmedCount) / \(target) pages ready")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(.accentColor)
                    }
                    .padding(.top, 10)
                }
                .padding(60)
                .background(
                    RoundedRectangle(cornerRadius: 32)
                        .fill(Color(NSColor.windowBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 32)
                                .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.1), radius: 30)
                )
                
                // Bottom Tips
                HStack(spacing: 20) {
                    Label("OCR Priming", systemImage: "text.magnifyingglass")
                    Divider().frame(height: 15)
                    Label("Rendering Engine", systemImage: "cpu")
                    Divider().frame(height: 15)
                    Label("Memory Caching", systemImage: "bolt.fill")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .opacity(0.6)
            }
        }
    }
}
