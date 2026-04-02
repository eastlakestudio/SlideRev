import Foundation
import Vision
import CoreImage
import PDFKit
import AppKit

// 辅助数据结构
struct OCRItem {
    let text: String
    let rect: CGRect
    let charRects: [CGRect]
}

print("🚀 [SlideReverse] 全文档技术验证 (LaMa 深度修复模式)")

let pdfPath = "test_origin.pdf"
let pdfURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(pdfPath)

guard let document = PDFDocument(url: pdfURL) else {
    print("❌ 失败：无法加载 \(pdfPath)")
    exit(1)
}

let pageCount = document.pageCount
print("📚 检测到 \(pageCount) 页文档，开始循环优化背景...")

// 初始化 LaMa 引擎
let inpainter = NeuralInpainter(modelURL: URL(fileURLWithPath: "temp_coremlama/LaMa.mlmodelc"))

for i in 0..<pageCount {
    guard let page = document.page(at: i) else { continue }
    print("\n--- 📄 处理第 \(i + 1) / \(pageCount) 页 ---")
    
    // 1. 高精度渲染 (300 DPI)
    let pageRect = page.bounds(for: .mediaBox)
    let dpi: CGFloat = 300.0
    let scale = dpi / 72.0
    let pixelSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
    
    let renderer = NSImage(size: pixelSize, flipped: false) { rect in
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
        print("   ❌ 图像转换失败")
        continue
    }
    
    // 2. Vision OCR (逐字提取)
    let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    var currentOcrItems: [OCRItem] = []
    
    let ocrRequest = VNRecognizeTextRequest { (request, error) in
        guard let results = request.results as? [VNRecognizedTextObservation] else { return }
        for observation in results {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let stringContent = candidate.string
            var charRects: [CGRect] = []
            
            for j in 0..<stringContent.count {
                let index = stringContent.index(stringContent.startIndex, offsetBy: j)
                let charRange = index..<stringContent.index(after: index)
                if let charBox = try? candidate.boundingBox(for: charRange) {
                    charRects.append(charBox.boundingBox)
                }
            }
            if charRects.isEmpty { charRects.append(observation.boundingBox) }
            currentOcrItems.append(OCRItem(text: stringContent, rect: observation.boundingBox, charRects: charRects))
        }
    }
    ocrRequest.recognitionLevel = .accurate
    ocrRequest.recognitionLanguages = ["zh-Hans", "en-US"]
    try? requestHandler.perform([ocrRequest])
    
    // 3. 构造字符掩码
    let colorSpace = CGColorSpaceCreateDeviceGray()
    guard let maskContext = CGContext(data: nil,
                                    width: cgImage.width,
                                    height: cgImage.height,
                                    bitsPerComponent: 8,
                                    bytesPerRow: cgImage.width,
                                    space: colorSpace,
                                    bitmapInfo: CGImageAlphaInfo.none.rawValue) else { continue }
    
    maskContext.setFillColor(NSColor.black.cgColor)
    maskContext.fill(CGRect(origin: .zero, size: pixelSize))
    maskContext.setFillColor(NSColor.white.cgColor)
    
    for item in currentOcrItems {
        for charRect in item.charRects {
            let rect = CGRect(x: charRect.origin.x * pixelSize.width,
                              y: charRect.origin.y * pixelSize.height,
                              width: charRect.size.width * pixelSize.width,
                              height: charRect.size.height * pixelSize.height)
            maskContext.fill(rect.insetBy(dx: -1.5, dy: -1.5))
        }
    }
    
    guard let maskCG = maskContext.makeImage() else { continue }
    
    // 4. LaMa 修复
    if let resultCG = inpainter.inpaint(image: cgImage, mask: maskCG) {
        let resultFilename = "Review_Page_\(i + 1).png"
        let resultURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(resultFilename)
        let nsResult = NSBitmapImageRep(cgImage: resultCG)
        if let data = nsResult.representation(using: .png, properties: [:]) {
            try? data.write(to: resultURL)
            print("   ✅ 成功生成比较图: \(resultFilename)")
        }
    } else {
        print("   ⚠️ LaMa 修复失败")
    }
}

print("\n🎉 全文档处理完毕！请检查目录下的 Review_Page_*.png 进行人工审核。")
