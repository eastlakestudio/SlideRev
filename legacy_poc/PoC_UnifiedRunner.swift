import Foundation
import Vision
import CoreImage
import PDFKit
import CoreGraphics

/// 統一 PoC 驗證執行器
class PoCUnifiedVerifier {
    
    let pdfPath = "Petrochemical_IT_Architecture_Blueprint_(2).pdf"
    let outputImagePath = "PoC_Step2_Inpainted.png"
    let outputJSONPath = "PoC_Step1_OCR_Result.json"
    
    func run() {
        print("🔍 啟動專案：SlideReverse 原生 PoC 驗證")
        
        // 1. PDF 頁面渲染驗證
        guard let pdfURL = URL(string: "file://" + FileManager.default.currentDirectoryPath + "/" + pdfPath),
              let document = PDFDocument(url: pdfURL),
              let page = document.page(at: 0) else {
            print("❌ 失敗：無法加載 PDF 文件")
            return
        }
        
        let pageRect = page.bounds(for: .mediaBox)
        let renderer = NSImage(size: pageRect.size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setFillColor(NSColor.white.cgColor)
            context.fill(rect)
            page.draw(with: .mediaBox, to: context)
            return true
        }
        
        guard let tiffData = renderer.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let cgImage = bitmap.cgImage else {
            print("❌ 失敗：無法將 PDF 渲染為 CGImage")
            return
        }
        print("✅ 步驟 0：PDF 頁面渲染完成 (\(cgImage.width)x\(cgImage.height))")

        // 2. PoC 1: Vision OCR 驗證
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let ocrRequest = VNRecognizeTextRequest { (request, error) in
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            
            var ocrMetadata: [[String: Any]] = []
            var maskRects: [CGRect] = []
            
            let width = CGFloat(cgImage.width)
            let height = CGFloat(cgImage.height)

            print("📂 偵測到 \(observations.count) 個文本區塊...")

            for observation in observations {
                guard let candidate = observation.topCandidates(1).first else { continue }
                
                // 座標轉換 (Vision 原生 Y-up)
                // VNRecognizedTextObservation.boundingBox 的 origin 是其左下角
                let box = observation.boundingBox
                let rect = CGRect(x: box.origin.x * width, 
                                  y: box.origin.y * height, 
                                  width: box.size.width * width, 
                                  height: box.size.height * height)
                
                maskRects.append(rect)
                ocrMetadata.append([
                    "text": candidate.string,
                    "confidence": candidate.confidence,
                    "rect": ["x": rect.origin.x, "y": rect.origin.y, "w": rect.size.width, "h": rect.size.height]
                ])
            }
            
            // 寫入 JSON 結果
            if let jsonData = try? JSONSerialization.data(withJSONObject: ocrMetadata, options: .prettyPrinted) {
                try? jsonData.write(to: URL(fileURLWithPath: self.outputJSONPath))
                print("✅ 步驟 1：OCR 驗證成功 (雙語模式)，元數據已輸出")
            }

            // 3. PoC 2: CoreImage 修復驗證
            self.verifyInpaint(image: CIImage(cgImage: cgImage), maskRects: maskRects)
        }
        
        ocrRequest.recognitionLevel = .accurate
        ocrRequest.recognitionLanguages = ["zh-Hans", "en-US"] // 強制設置中英雙語模式
        ocrRequest.usesLanguageCorrection = true
        
        try? requestHandler.perform([ocrRequest])
    }
    
    func verifyInpaint(image: CIImage, maskRects: [CGRect]) {
        let inpainter = NativeInpaintLogic()
        inpainter.process(image: image, rects: maskRects) { output in
            if let output = output {
                let context = CIContext()
                if let cgImage = context.createCGImage(output, from: output.extent) {
                    let nsImage = NSBitmapImageRep(cgImage: cgImage)
                    if let data = nsImage.representation(using: .png, properties: [:]) {
                        try? data.write(to: URL(fileURLWithPath: self.outputImagePath))
                        print("✅ 步驟 2：背景修復驗證成功，圖片已輸出至 \(self.outputImagePath)")
                    }
                }
            }
        }
    }
}

/// 簡化的修復邏輯
class NativeInpaintLogic {
    func process(image: CIImage, rects: [CGRect], completion: (CIImage?) -> Void) {
        var mask = CIImage(color: .black).clampedToExtent().cropped(to: image.extent)
        for rect in rects {
            let box = CIImage(color: .white).cropped(to: rect)
            mask = box.composited(over: mask)
        }
        
        let filter = CIFilter(name: "CIMorphologyMaximum")!
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(10.0, forKey: kCIInputRadiusKey)
        let expanded = filter.outputImage!
        
        let blend = CIFilter(name: "CIBlendWithMask")!
        blend.setValue(expanded, forKey: kCIInputImageKey)
        blend.setValue(image, forKey: kCIInputBackgroundImageKey)
        blend.setValue(mask, forKey: kCIInputMaskImageKey)
        
        completion(blend.outputImage)
    }
}

// 執行
let verifier = PoCUnifiedVerifier()
verifier.run()
