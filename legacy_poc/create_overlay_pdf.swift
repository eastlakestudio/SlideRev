import Foundation
import PDFKit
import CoreGraphics
import CoreText

// MARK: - Data Models

struct OCRSpan: Codable {
    let text: String
    let confidence: Float
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let angle: Double
    let color: String
    let fontSize: Double
}

struct OCRPage: Codable {
    let pageIndex: Int
    let width: Double
    let height: Double
    let spans: [OCRSpan]
}

// MARK: - Helper Functions

func hexToCGColor(_ hex: String) -> CGColor {
    var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

    var rgb: UInt64 = 0
    Scanner(string: hexSanitized).scanHexInt64(&rgb)

    let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
    let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
    let b = CGFloat(rgb & 0x0000FF) / 255.0

    return CGColor(red: r, green: g, blue: b, alpha: 1.0)
}

func invertCGColor(_ color: CGColor, alpha: CGFloat = 1.0) -> CGColor {
    guard let components = color.components, components.count >= 3 else {
        return CGColor(red: 1, green: 1, blue: 1, alpha: alpha)
    }
    return CGColor(red: 1.0 - components[0],
                   green: 1.0 - components[1],
                   blue: 1.0 - components[2],
                   alpha: alpha)
}

// MARK: - PDF Generation

class PDFCreator {
    
    // Fine-tuning factor for OCR height to Font Point Size
    let fontSizeScale: CGFloat = 1.08
    
    func createOverlayPDF(inputPDFPath: String, inputJSONPath: String, outputPDFPath: String) {
        let inputURL = URL(fileURLWithPath: inputPDFPath)
        guard let document = PDFDocument(url: inputURL) else {
            print("❌ Failed to load original PDF")
            return
        }
        
        let jsonURL = URL(fileURLWithPath: inputJSONPath)
        guard let jsonData = try? Data(contentsOf: jsonURL),
              let pagesData = try? JSONDecoder().decode([OCRPage].self, from: jsonData) else {
            print("❌ Failed to load OCR JSON")
            return
        }
        
        let outputURL = URL(fileURLWithPath: outputPDFPath)
        guard let consumer = CGDataConsumer(url: outputURL as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            print("❌ Failed to create PDF context")
            return
        }
        
        for (pageIndex, pageData) in pagesData.enumerated() {
            guard pageIndex < document.pageCount,
                  let originalPage = document.page(at: pageIndex) else { continue }
            
            let mediaBox = originalPage.bounds(for: .mediaBox)
            var mutableMediaBox = mediaBox
            context.beginPage(mediaBox: &mutableMediaBox)
            
            // 1. Draw Original PDF Content as Background
            originalPage.draw(with: .mediaBox, to: context)
            
            // 2. Overlay OCR Spans
            for span in pageData.spans {
                // rect.origin.y is the bottom of the box for CG context
                let rect = CGRect(x: span.x, 
                                  y: Double(mediaBox.height) - span.y - span.height, 
                                  width: span.width, 
                                  height: span.height)
                
                let textColor = hexToCGColor(span.color)
                let bgColor = invertCGColor(textColor, alpha: 1.0) // Opaque as requested
                
                // Draw Opaque Background Box
                context.saveGState()
                context.setFillColor(bgColor)
                context.fill(rect.insetBy(dx: -0.5, dy: -0.5)) 
                context.restoreGState()
                
                // Draw Vector Text (CoreText)
                context.saveGState()
                
                let fontName = "PingFangSC-Regular" as CFString
                // APPLY SCALE FACTOR
                let adjustedFontSize = CGFloat(span.fontSize) * fontSizeScale
                let font = CTFontCreateWithName(fontName, adjustedFontSize, nil)
                
                // VERTICAL CENTERING LOGIC
                let ascent = CTFontGetAscent(font)
                let descent = CTFontGetDescent(font)
                let textHeight = ascent + descent
                let yOffset = (rect.height - textHeight) / 2.0
                
                let attributes: [CFString: Any] = [
                    kCTFontAttributeName: font,
                    kCTForegroundColorAttributeName: textColor
                ]
                
                let attrString = NSAttributedString(string: span.text, attributes: attributes as [NSAttributedString.Key : Any])
                let line = CTLineCreateWithAttributedString(attrString)
                
                // Baseline calculation for centering: rect.y + bottom_padding + descent
                context.textMatrix = .identity
                context.textPosition = CGPoint(x: rect.origin.x, y: rect.origin.y + yOffset + descent)
                
                CTLineDraw(line, context)
                context.restoreGState()
            }
            
            context.endPage()
        }
        
        context.closePDF()
        print("✅ Success! V3 Editable PDF (Scale: \(fontSizeScale)) created at \(outputPDFPath)")
    }
}

// MARK: - Main Execution

let args = CommandLine.arguments
if args.count < 4 {
    print("Usage: swift create_overlay_pdf.swift <input_pdf> <input_json> <output_pdf>")
    exit(1)
}

let creator = PDFCreator()
creator.createOverlayPDF(inputPDFPath: args[1], 
                         inputJSONPath: args[2], 
                         outputPDFPath: args[3])
