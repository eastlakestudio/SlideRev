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
        let centerX = (rect.origin.x + rect.size.width / 2.0) * width
        let centerY = (rect.origin.y + rect.size.height / 2.0) * height
        
        let _ = if item.isErased || hoverItemId == item.id {
            AdvancedSlideProcessor.fileLog("👁️ [Render] Item(\(item.text.prefix(10))...): isErased=\(item.isErased), visible=\(item.isTextVisible), progress=\(String(format: "%.2f", item.refinementProgress)), edited='\(item.editedText)'")
        } else {
            ()
        }
        
        ZStack(alignment: .topLeading) {
            // V0.9.6.1: Only render if item is not erased OR text is explicitly visible
            if item.isErased && !item.isTextVisible {
                EmptyView()
            } else if item.isErased {
                TextField("", text: $item.editedText, axis: item.editedText.contains("\n") ? .vertical : .horizontal)
                    .textFieldStyle(.plain)
                    .font(.custom(item.fontName, size: item.fontSize * zoomScale).weight(item.isBold ? .bold : .regular))
                    .multilineTextAlignment(.center) // Internal Text Centering
                    .foregroundColor(Color(nsColor: NSColor(cgColor: item.color) ?? .black))
                    .accentColor(.orange)
                    .rotationEffect(.degrees(item.rotation))
                    .padding(0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center) 
                    .background(Color.clear)
                    .mask(
                        // 🚀 Scan Reveal: Wipe from left to right
                        HStack(spacing: 0) {
                            let progress = item.refinementProgress
                            // 🚀 TRAIL PROGRESS: Text starts revealing after 25% wipe, then catches up
                            let trailProgress = max(0.0, (progress - 0.25) / 0.75)
                            Rectangle()
                                .fill(Color.white)
                                .frame(width: rect.size.width * width * CGFloat(trailProgress))
                            Spacer(minLength: 0)
                        }
                    )
                    .overlay(
                        ZStack {
                            // Normal Border
                            Rectangle()
                                .stroke(selectedItemId == item.id ? Color.orange : (hoverItemId == item.id ? Color.accentColor.opacity(0.5) : Color.clear), lineWidth: 2)
                            
                            // 🚀 Interactive Hover for Refined Items: Dashed Border
                            if item.isErased && hoverItemId == item.id {
                                Rectangle()
                                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 2, dash: [4]))
                                    .opacity(0.8)
                            }
                        }
                        .shadow(color: selectedItemId == item.id ? .orange.opacity(0.5) : .clear, radius: 4)
                    )
            } else {
                Rectangle()
                    .fill(Color.clear)
                    .overlay(Rectangle().stroke(selectedItemId == item.id || hoverItemId == item.id ? Color.accentColor : Color.clear, lineWidth: (selectedItemId == item.id || hoverItemId == item.id) ? 2 : 1))
            }
            
        }
        .frame(width: rect.size.width * width, height: rect.size.height * height)
        .contentShape(Rectangle())
        .zIndex(selectedItemId == item.id ? 100 : 0)
        .onHover { inside in 
            withAnimation(.easeInOut(duration: 0.1)) { hoverItemId = inside ? item.id : nil } 
        }
        // 🚀 核心優化：ExclusiveGesture 優先等待雙擊，避免單擊干擾
        .gesture(
            TapGesture(count: 2)
                .onEnded { 
                    withAnimation { self.processor.eraseItem(id: item.id) } 
                }
                .exclusively(before: TapGesture(count: 1).onEnded { 
                    self.selectedItemId = item.id 
                })
        )
        .position(x: centerX, y: centerY)
    }
}
