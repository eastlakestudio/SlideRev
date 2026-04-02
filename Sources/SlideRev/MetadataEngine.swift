import Foundation
import Vision
import CoreImage
import PDFKit
import CoreGraphics

/// 高保真結構化數據提取器
class FullSpectrumMetadataEngine {
    
    let pdfPath = "test_origin.pdf"
    let outputJSON = "Metadata_Cover_Result.json"
    
    func run() {
        print("🔍 啟動「高保真文本提取」核心任務...")
        
        guard let doc = PDFDocument(url: URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/" + pdfPath)),
              let page = doc.page(at: 0) else {
            print("❌ 失敗：無法加載 \(pdfPath)"); return
        }
        
        let bounds = page.bounds(for: .mediaBox)
        let pageWidth = bounds.width
        let pageHeight = bounds.height
        
        // 渲染為 300 DPI 用於 OCR
        let scale: CGFloat = 300.0 / 72.0
        let pixelSize = CGSize(width: pageWidth * scale, height: pageHeight * scale)
        
        let renderer = NSImage(size: pixelSize, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fill(rect)
            ctx.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: ctx)
            return true
        }
        
        guard let tiff = renderer.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let cgImage = bitmap.cgImage else { return }
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let ocrRequest = VNRecognizeTextRequest { [weak self] (request, error) in
            guard let results = request.results as? [VNRecognizedTextObservation],
                  let self = self else { return }
            
            var metadata: [String: Any] = [
                "page": 1,
                "canvas_size": ["w": pageWidth, "h": pageHeight],
                "items": []
            ]
            
            var items: [[String: Any]] = []

            for obs in results {
                guard let candidate = obs.topCandidates(1).first else { continue }
                
                let box = obs.boundingBox
                
                // 1. 位置轉換 (Normalized -> PDF Points, Y-down from Top-Left)
                let x = box.origin.x * pageWidth
                let y = (1 - box.origin.y - box.size.height) * pageHeight
                let w = box.size.width * pageWidth
                let h = box.size.height * pageHeight
                
                // 2. 字體大小估算 (pt)
                // 在 PDF 中，1 pt = 1/72 inch. 
                // Vision 回報的是文字在當前視圖中的相對高度
                let fontSize = h * 0.85 // 經驗公式調整：Vision 的 Box 包含上下行間距
                
                // 3. 旋轉角度 (雖然 Cover 通常是 0，但我們保留檢查能力)
                // 暫定為 0，未來可透過特徵點計算
                let angle: Double = 0.0
                
                // 4. 顏色採樣 (在渲染出的 Bitmap 中取樣)
                let colorHex = self.sampleColorAt(bitmap: bitmap, box: box, pixelSize: pixelSize)
                
                items.append([
                    "text": candidate.string,
                    "rect": ["x": Double(x), "y": Double(y), "w": Double(w), "h": Double(h)],
                    "font_size": Double(fontSize),
                    "color": colorHex,
                    "angle": angle,
                    "confidence": candidate.confidence
                ])
            }
            
            metadata["items"] = items
            
            // 輸出 JSON
            if let data = try? JSONSerialization.data(withJSONObject: metadata, options: .prettyPrinted) {
                try? data.write(to: URL(fileURLWithPath: self.outputJSON))
                print("✅ 結構化數據導出成功：\(self.outputJSON)")
            }
        }
        
        ocrRequest.recognitionLevel = .accurate
        ocrRequest.recognitionLanguages = ["zh-Hans", "en-US"]
        try? handler.perform([ocrRequest])
    }
    
    private func sampleColorAt(bitmap: NSBitmapImageRep, box: CGRect, pixelSize: CGSize) -> String {
        // 取文字觀測塊的中點像素（物理像素）
        let px = Int(box.origin.x * pixelSize.width + (box.size.width * pixelSize.width) / 2)
        let py = Int((1 - box.origin.y - box.size.height) * pixelSize.height + (box.size.height * pixelSize.height) / 2)
        
        guard let color = bitmap.colorAt(x: px, y: py) else { return "#FFFFFF" }
        
        let r = Int(color.redComponent * 255)
        let g = Int(color.greenComponent * 255)
        let b = Int(color.blueComponent * 255)
        
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// FullSpectrumMetadataEngine().run()
