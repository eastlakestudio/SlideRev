import Foundation
import PDFKit
import CoreGraphics
import AppKit

let inputPath = "test_origin.pdf"
let outputDir = "temp_slides"

func renderPDFPages() {
    let inputURL = URL(fileURLWithPath: inputPath)
    guard let document = PDFDocument(url: inputURL) else {
        print("❌ Failed to load PDF")
        return
    }
    
    let fileManager = FileManager.default
    if !fileManager.fileExists(atPath: outputDir) {
        try? fileManager.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
    }
    
    for i in 0..<document.pageCount {
        guard let page = document.page(at: i) else { continue }
        let pageRect = page.bounds(for: .mediaBox)
        
        let dpi: CGFloat = 300.0
        let scale = dpi / 72.0
        let pixelSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
        
        let image = NSImage(size: pixelSize, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setFillColor(NSColor.white.cgColor)
            context.fill(rect)
            context.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context)
            return true
        }
        
        if let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let jpegData = bitmap.representation(using: .jpeg, properties: [:]) {
            let outputPath = "\(outputDir)/page_\(i + 1).jpg"
            try? jpegData.write(to: URL(fileURLWithPath: outputPath))
            print("✅ Rendered Page \(i + 1)")
        }
    }
}

renderPDFPages()
