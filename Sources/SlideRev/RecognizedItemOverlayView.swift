import SwiftUI
import AppKit

struct RecognizedItemOverlayView: View {
    @Binding var item: AdvancedSlideProcessor.RecognizedItem
    let width: CGFloat
    let height: CGFloat
    let zoomScale: CGFloat
    @Binding var selectedItemId: UUID?
    @Binding var hoverItemId: UUID?
    @ObservedObject var processor: AdvancedSlideProcessor
    @State private var startRect: CGRect? = nil

    var body: some View {
        let rect = item.rect
        let boxWidth = rect.size.width * width
        let boxHeight = rect.size.height * height
        let centerX = (rect.origin.x + rect.size.width / 2.0) * width
        let centerY = (rect.origin.y + rect.size.height / 2.0) * height
        
        // 🚀 V39.5: Instant Toggle - No Delay. UI hides immediately on mouse exit/blur.
        let shouldShowUI = hoverItemId == item.id || selectedItemId == item.id

        ZStack(alignment: .topTrailing) {
            // Main Text Box (Interactive Container)
            ZStack(alignment: .topLeading) {
                // 🚀 V39.9: Hit-test fix - Nearly invisible layer to ensure macOS hover events are captured
                Color.white.opacity(0.001)
                
                // 🚀 V41.0: Original Image Crop Layer (Deep Logic)
                // If item is set to .original, we overlay the actual original pixels from base image 
                // on top of the clean inpainted background but under interaction layers.
                if item.viewState == .original, let slice = processor.getOriginalSlice(for: item.rect) {
                    Image(nsImage: NSImage(cgImage: slice, size: CGSize(width: boxWidth, height: boxHeight)))
                        .resizable()
                        .frame(width: boxWidth, height: boxHeight)
                }

                // Hover/Selection Background (Subtle indicator)
                if shouldShowUI {
                    Rectangle()
                        .fill(selectedItemId == item.id ? Color.orange.opacity(0.04) : Color.accentColor.opacity(0.06))
                }

                // Text Content (Only in Refined mode)
                // 🚀 V58.4: GHOSTING FIX - Hide text if background is not ready yet
                let isTextReady = item.isTextVisible && (processor.inpaintedImage != nil)
                if isTextReady {
                    let isMultiLine = item.editedText.contains("\n")
                    
                    let txtAlignment: TextAlignment = {
                        if item.textAlignment == "l" { return .leading }
                        if item.textAlignment == "r" { return .trailing }
                        return .center
                    }()
                    
                    let boxAlignment: Alignment = {
                        if item.textAlignment == "l" { return isMultiLine ? .topLeading : .leading }
                        if item.textAlignment == "r" { return isMultiLine ? .topTrailing : .trailing }
                        return isMultiLine ? .top : .center
                    }()

                    TextField("", text: $item.editedText, axis: isMultiLine ? .vertical : .horizontal)
                        .textFieldStyle(.plain)
                        .font(.custom(item.fontName, size: item.fontSize * zoomScale).weight(item.isBold ? .bold : .regular))
                        .multilineTextAlignment(txtAlignment)
                        .foregroundColor(Color(nsColor: NSColor(cgColor: item.color) ?? .black))
                        .accentColor(.orange)
                        .rotationEffect(.degrees(item.rotation))
                        .padding(0)
                        .frame(maxWidth: .infinity, maxHeight: .infinity,
                               alignment: boxAlignment)
                        .background(Color.clear)
                }
                
                // Status/Selection Border
                Rectangle()
                    .stroke(selectedItemId == item.id ? Color.orange : (shouldShowUI ? Color.accentColor : Color.clear), 
                            style: StrokeStyle(lineWidth: (selectedItemId == item.id || shouldShowUI) ? 2 : 0, 
                                               dash: (item.viewState == .cleaned && shouldShowUI) ? [4, 2] : []))
                    .shadow(color: selectedItemId == item.id ? .orange.opacity(0.4) : (shouldShowUI ? .accentColor.opacity(0.3) : .clear), radius: 4)
            }
            .frame(width: boxWidth, height: boxHeight)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(_):
                    hoverItemId = item.id
                case .ended:
                    hoverItemId = nil
                }
            }
            .gesture(
                TapGesture(count: 2)
                    .onEnded { 
                        withAnimation { processor.setItemState(id: item.id, to: .refined) }
                    }
            )
            .gesture(
                TapGesture(count: 1)
                    .onEnded { 
                        self.selectedItemId = item.id 
                    }
            )
            .contextMenu {
                // 🚀 V58.0: Right-click Menu for Mode Switching (English Only)
                Button(action: { 
                    withAnimation { processor.setItemState(id: item.id, to: .original) }
                }) {
                    Label("Original Image", systemImage: "photo")
                }
                Button(action: { 
                    withAnimation { processor.setItemState(id: item.id, to: .cleaned) }
                }) {
                    Label("Background Only", systemImage: "eye.slash")
                }
                Button(action: { 
                    withAnimation { processor.setItemState(id: item.id, to: .refined) }
                }) {
                    Label("Refine Text", systemImage: "sparkles")
                }
            }
        }
        .position(x: centerX, y: centerY)
        .zIndex(selectedItemId == item.id ? 100 : 0)
    }
}
