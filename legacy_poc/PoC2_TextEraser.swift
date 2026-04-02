import Foundation
import CoreGraphics
import CoreImage
import Vision

/// 文字消除策略
enum EraseStrategy {
    case geometric // 基於邊緣採樣的幾何填充 (適合純色背景)
    case neural    // 基於 CoreML 的神經網絡修補 (適合複雜背景)
}

/// POC 2: Text Eraser (基於 Vision + CoreImage + AI)
class TextEraser {
    
    struct EraseResult {
        let outputImage: CGImage
    }
    
    var neuralInpainter: NeuralInpainter?
    
    /// 執行文字消除
    /// - Parameters:
    ///   - cgImage: 原始圖片
    ///   - observations: Vision 檢測出的文字觀測結果
    ///   - strategy: 消除策略，默認為幾何填充
    ///   - padding: 向外擴展像素
    func erase(from cgImage: CGImage, 
               observations: [VNRecognizedTextObservation], 
               strategy: EraseStrategy = .geometric,
               padding: CGFloat = 5.0) -> EraseResult? {
        
        switch strategy {
        case .geometric:
            return eraseGeometric(from: cgImage, observations: observations, padding: padding)
        case .neural:
            return eraseNeural(from: cgImage, observations: observations, padding: padding)
        }
    }
    
    // MARK: - 幾何填充 (幾何模式)
    
    // MARK: - 幾何填充 (增強版：智能採樣與均勻化)
    
    private func eraseGeometric(from cgImage: CGImage, observations: [VNRecognizedTextObservation], padding: CGFloat) -> EraseResult? {
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        
        guard let context = CGContext(data: nil,
                                     width: Int(width),
                                     height: Int(height),
                                     bitsPerComponent: 8,
                                     bytesPerRow: 0,
                                     space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        for observation in observations {
            let p1 = CGPoint(x: observation.topLeft.x * width, y: (1 - observation.topLeft.y) * height)
            let p2 = CGPoint(x: observation.topRight.x * width, y: (1 - observation.topRight.y) * height)
            let p3 = CGPoint(x: observation.bottomRight.x * width, y: (1 - observation.bottomRight.y) * height)
            let p4 = CGPoint(x: observation.bottomLeft.x * width, y: (1 - observation.bottomLeft.y) * height)
            
            // 構建多邊形路徑
            let path = CGMutablePath()
            path.move(to: p1)
            path.addLine(to: p2)
            path.addLine(to: p3)
            path.addLine(to: p4)
            path.closeSubpath()
            
            // 1. 周邊採樣：採樣四個角落的顏色以處理漸變
            let c1 = getPixelColor(cgImage: cgImage, x: Int(max(0, min(width-1, p1.x - 5))), y: Int(max(0, min(height-1, height - p1.y))))
            let c2 = getPixelColor(cgImage: cgImage, x: Int(max(0, min(width-1, p2.x + 5))), y: Int(max(0, min(height-1, height - p2.y))))
            let c3 = getPixelColor(cgImage: cgImage, x: Int(max(0, min(width-1, p3.x + 5))), y: Int(max(0, min(height-1, height - p3.y))))
            let c4 = getPixelColor(cgImage: cgImage, x: Int(max(0, min(width-1, p4.x - 5))), y: Int(max(0, min(height-1, height - p4.y))))
            
            // 2. 計算平均背景色 (簡單幾何模式下取平均值足以應對大多數 PPT 漸變)
            let avgColor = averageColors([c1, c2, c3, c4])
            
            context.saveGState()
            
            // 使用模糊邊緣處理，避免填色生硬
            context.addPath(path)
            context.setLineWidth(padding * 2)
            context.setLineJoin(.round)
            context.setLineCap(.round)
            context.setStrokeColor(avgColor)
            context.strokePath()
            
            context.addPath(path)
            context.setFillColor(avgColor)
            context.fillPath()
            
            context.restoreGState()
        }
        
        guard let output = context.makeImage() else { return nil }
        return EraseResult(outputImage: output)
    }

    private func averageColors(_ colors: [CGColor]) -> CGColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        for color in colors {
            if let comps = color.components, comps.count >= 3 {
                r += comps[0]
                g += comps[1]
                b += comps[2]
            }
        }
        let count = CGFloat(colors.count)
        return CGColor(red: r/count, green: g/count, blue: b/count, alpha: 1.0)
    }
    
    // MARK: - 神經網絡填充 (AI 模式)
    
    private func eraseNeural(from cgImage: CGImage, observations: [VNRecognizedTextObservation], padding: CGFloat) -> EraseResult? {
        guard let inpainter = neuralInpainter else {
            print("⚠️ NeuralInpainter 未初始化，降級為幾何模式")
            return eraseGeometric(from: cgImage, observations: observations, padding: padding)
        }
        
        // 1. 生成掩碼圖 (Black/White Mask)
        guard let mask = generateMask(for: cgImage, observations: observations, padding: padding) else {
            return nil
        }
        
        // 2. 調用 AI 修復模型
        guard let output = inpainter.inpaint(image: cgImage, mask: mask) else {
            return nil
        }
        
        return EraseResult(outputImage: output)
    }
    
    /// 生成黑白掩碼圖
    private func generateMask(for cgImage: CGImage, observations: [VNRecognizedTextObservation], padding: CGFloat) -> CGImage? {
        let width = cgImage.width
        let height = cgImage.height
        
        guard let context = CGContext(data: nil,
                                     width: width,
                                     height: height,
                                     bitsPerComponent: 8,
                                     bytesPerRow: 0,
                                     space: CGColorSpaceCreateDeviceGray(),
                                     bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return nil
        }
        
        // 背景塗黑
        context.setFillColor(gray: 0.0, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        
        // 文字區域塗白
        context.setFillColor(gray: 1.0, alpha: 1.0)
        context.setStrokeColor(gray: 1.0, alpha: 1.0)
        
        for observation in observations {
            let p1 = CGPoint(x: observation.topLeft.x * CGFloat(width), y: observation.topLeft.y * CGFloat(height))
            let p2 = CGPoint(x: observation.topRight.x * CGFloat(width), y: observation.topRight.y * CGFloat(height))
            let p3 = CGPoint(x: observation.bottomRight.x * CGFloat(width), y: observation.bottomRight.y * CGFloat(height))
            let p4 = CGPoint(x: observation.bottomLeft.x * CGFloat(width), y: observation.bottomLeft.y * CGFloat(height))
            
            let path = CGMutablePath()
            path.move(to: p1)
            path.addLine(to: p2)
            path.addLine(to: p3)
            path.addLine(to: p4)
            path.closeSubpath()
            
            context.saveGState()
            context.addPath(path)
            context.setLineWidth(padding * 2)
            context.setLineJoin(.round)
            context.strokePath()
            
            context.addPath(path)
            context.fillPath()
            context.restoreGState()
        }
        
        return context.makeImage()
    }
    
    // MARK: - 輔助方法
    private func getPixelColor(cgImage: CGImage, x: Int, y: Int) -> CGColor {
        // 為了簡單起見，直接調用外部封裝的組件或使用 CGContext 採樣
        // 這裡直接讀取 Byte Pointer
        guard let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data else {
            return CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        }
        
        let bytesPerRow = cgImage.bytesPerRow
        let ptr = CFDataGetBytePtr(data)
        
        // 注意：CGImage 可能有不同的 Pixel Format，這裡假設是 RGBA/BGRA 4字節
        let pixelInfo: Int = ((bytesPerRow * y) + (x * 4))
        
        if pixelInfo + 3 < CFDataGetLength(data) {
            // 通常是 R, G, B, A 或 B, G, R, A (取決於 bitmapInfo)
            // 這裡簡單採樣
            let b = CGFloat(ptr![pixelInfo]) / 255.0
            let g = CGFloat(ptr![pixelInfo+1]) / 255.0
            let r = CGFloat(ptr![pixelInfo+2]) / 255.0
            return CGColor(red: r, green: g, blue: b, alpha: 1.0)
        }
        
        return CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    }
    // MARK: - 輔助方法 (靜態)
    
    /// 保存 CGImage 到文件
    static func save(_ image: CGImage, to url: URL) {
        let ciImage = CIImage(cgImage: image)
        let context = CIContext()
        if let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) {
            try? context.writePNGRepresentation(of: ciImage, to: url, format: .RGBA8, colorSpace: colorSpace)
        }
    }
}
