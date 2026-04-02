import Foundation
import Vision
import CoreImage
import PDFKit
import CoreGraphics

/// 全頁面 PoC 驗證執行器
class FullDocumentVerifier {
    
    let pdfPath = "test_origin.pdf"
    let outputDir = "output_poc"
    
    func run() {
        print("🔍 啟動全頁面驗證：SlideReverse 原生 PoC (test_origin.pdf)")
        
        // 1. 建立輸出目錄
        let fm = FileManager.default
        try? fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

        // 2. 加載 PDF
        guard let pdfURL = URL(string: "file://" + fm.currentDirectoryPath + "/" + pdfPath),
              let document = PDFDocument(url: pdfURL) else {
            print("❌ 失敗：無法加載 \(pdfPath)")
            return
        }
        
        let totalPages = document.pageCount
        print("📄 共有 \(totalPages) 頁需要處理...")

        // 3. 逐頁處理
        for i in 0..<totalPages {
            processPage(at: i, document: document)
        }
        
        print("\n✅ 全文件處理完成！請查看 \(outputDir) 目錄。")
    }
    
    func processPage(at index: Int, document: PDFDocument) {
        guard let page = document.page(at: index) else { return }
        let pageNum = index + 1
        print("⏳ 正在處理第 \(pageNum) 頁...", terminator: "")
        
        // 渲染為 CGImage (300 DPI)
        let pageRect = page.bounds(for: .mediaBox)
        let scale = 300.0 / 72.0
        let imageSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
        
        let renderer = NSImage(size: imageSize, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setFillColor(NSColor.white.cgColor)
            context.fill(rect)
            context.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context)
            return true
        }
        
        guard let tiffData = renderer.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let cgImage = bitmap.cgImage else {
            print("❌ 渲染失敗")
            return
        }
        
        // OCR 請求
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let ocrRequest = VNRecognizeTextRequest { (request, error) in
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            
            var maskRects: [CGRect] = []
            let width = CGFloat(cgImage.width)
            let height = CGFloat(cgImage.height)

            for observation in observations {
                let box = observation.boundingBox
                let rect = CGRect(x: box.origin.x * width, 
                                  y: box.origin.y * height, 
                                  width: box.size.width * width, 
                                  height: box.size.height * height)
                maskRects.append(rect)
            }
            
            //背景修復
            self.inpaintAndSave(image: CIImage(cgImage: cgImage), rects: maskRects, pageNum: pageNum)
        }
        
        ocrRequest.recognitionLevel = .accurate
        ocrRequest.recognitionLanguages = ["zh-Hans", "en-US"]
        try? requestHandler.perform([ocrRequest])
    }
    
    func inpaintAndSave(image: CIImage, rects: [CGRect], pageNum: Int) {
        let inpainter = NativeInpaintLogic()
        inpainter.process(image: image, rects: rects) { output in
            guard let output = output else { return }
            let context = CIContext()
            if let cgImage = context.createCGImage(output, from: output.extent) {
                let nsImage = NSBitmapImageRep(cgImage: cgImage)
                if let data = nsImage.representation(using: .png, properties: [:]) {
                    let path = "\(outputDir)/Page_\(pageNum)_Inpainted.png"
                    try? data.write(to: URL(fileURLWithPath: path))
                }
            }
        }
        print(" Done.")
    }
}

// 相同的修補邏輯
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

let verifier = FullDocumentVerifier()
verifier.run()
