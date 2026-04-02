import Foundation
import Vision
import CoreImage
import PDFKit
import CoreGraphics

/// 封面頁專屬：發光背景修復驗證
class CoverInpaintVerifier {
    
    let pdfPath = "test_origin.pdf"
    let outputImg = "Cover_Inpainted_Verified.png"
    let outputJSON = "Cover_OCR_Verified.json"
    
    func run() {
        print("🔍 啟動「發光背景」封面精修驗證...")
        
        guard let doc = PDFDocument(url: URL(fileURLWithPath: FileManager.default.currentDirectoryPath + "/" + pdfPath)),
              let page = doc.page(at: 0) else {
            print("❌ 失敗：無法加載 \(pdfPath)"); return
        }
        
        // 1. 600 DPI 高清渲染
        let scale: CGFloat = 600.0 / 72.0
        let bounds = page.bounds(for: .mediaBox)
        let pixelSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        
        let renderer = NSImage(size: pixelSize, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setFillColor(NSColor.black.cgColor) // 封面通常是深色
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
            
            var maskRects: [CGRect] = []
            let width = CGFloat(cgImage.width)
            let height = CGFloat(cgImage.height)

            print("📂 偵測到 \(results.count) 個文本塊，正在啟動「光暈感知」修復...")

            for obs in results {
                let box = obs.boundingBox
                let rect = CGRect(x: box.origin.x * width, 
                                  y: box.origin.y * height, 
                                  width: box.size.width * width, 
                                  height: box.size.height * height)
                maskRects.append(rect)
            }
            
            self.advancedInpaint(image: CIImage(cgImage: cgImage), rects: maskRects)
        }
        
        ocrRequest.recognitionLevel = .accurate
        ocrRequest.recognitionLanguages = ["zh-Hans", "en-US"]
        try? handler.perform([ocrRequest])
    }
    
    func advancedInpaint(image: CIImage, rects: [CGRect]) {
        let extent = image.extent
        
        // 生成原始 Mask
        var mask = CIImage(color: .black).clampedToExtent().cropped(to: extent)
        for rect in rects {
            let box = CIImage(color: .white).cropped(to: rect)
            mask = box.composited(over: mask)
        }
        
        // --- 核心改進 1：擴張 Mask 以覆蓋 Glow (光暈) ---
        // 對於封面大字，我們向外擴張 8 像素 (600 DPI 下約 1pt)
        let maskDilation = CIFilter(name: "CIMorphologyMaximum")!
        maskDilation.setValue(mask, forKey: kCIInputImageKey)
        maskDilation.setValue(8.0, forKey: kCIInputRadiusKey)
        let dilatedMask = maskDilation.outputImage!
        
        // --- 核心改進 2：廣域背景提取 ---
        // 使用更大幅度的膨脹來提取背景紋理
        let bgExpansion = CIFilter(name: "CIMorphologyMaximum")!
        bgExpansion.setValue(image, forKey: kCIInputImageKey)
        bgExpansion.setValue(35.0, forKey: kCIInputRadiusKey)
        let backgroundImage = bgExpansion.outputImage!
        
        // 混合
        let blend = CIFilter(name: "CIBlendWithMask")!
        blend.setValue(backgroundImage, forKey: kCIInputImageKey)
        blend.setValue(image, forKey: kCIInputBackgroundImageKey)
        blend.setValue(dilatedMask, forKey: kCIInputMaskImageKey)
        
        let context = CIContext()
        if let outImg = blend.outputImage,
           let finalCG = context.createCGImage(outImg, from: outImg.extent) {
            let res = NSBitmapImageRep(cgImage: finalCG)
            if let data = res.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: outputImg))
                print("✅ 驗證成功！優化後的封面底圖已輸出：\(outputImg)")
            }
        }
    }
}

CoverInpaintVerifier().run()
