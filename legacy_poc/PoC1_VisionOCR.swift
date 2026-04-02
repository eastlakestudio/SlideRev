import Foundation
import Vision
import CoreGraphics
import CoreImage

/// POC 1: Vision OCR 與排版特征提取
/// 目標：從圖片中提取文字、座標、旋轉角度以及中心背景色
class NativeOCRProcessor {
    
    struct TextObservationResult {
        let text: String
        let confidence: Float
        let center: CGPoint
        let size: CGSize
        let angle: Double
        let hexColor: String
    }
    
    func performOCR(on imageURL: URL, completion: @escaping ([TextObservationResult]) -> Void) {
        guard let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            print("❌ 無法讀取圖片")
            return
        }
        
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        let request = VNRecognizeTextRequest { (request, error) in
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            
            var results: [TextObservationResult] = []
            
            for observation in observations {
                guard let candidate = observation.topCandidates(1).first else { continue }
                
                // 1. 獲取四個頂點 (Vision 座標系：0,0 在左下角，規範化 0-1)
                let topLeft = observation.topLeft
                let topRight = observation.topRight
                let bottomLeft = observation.bottomLeft
                let bottomRight = observation.bottomRight
                
                // 2. 計算中心點 (轉換為圖片像素座標，並適配 Y-down 系統)
                let centerX = (topLeft.x + topRight.x + bottomLeft.x + bottomRight.x) / 4 * width
                let centerY = (1 - (topLeft.y + topRight.y + bottomLeft.y + bottomRight.y) / 4) * height
                
                // 3. 計算寬度與高度
                let boxWidth = sqrt(pow(topRight.x - topLeft.x, 2) + pow(topRight.y - topLeft.y, 2)) * width
                let boxHeight = sqrt(pow(topLeft.x - bottomLeft.x, 2) + pow(topLeft.y - bottomLeft.y, 2)) * height
                
                // 4. 計算角度 (弧度 -> 角度)
                // Vision 的坐標是 y-up，PPT 是 y-down
                let radians = atan2(topRight.y - topLeft.y, topRight.x - topLeft.x)
                let angle = radians * (180.0 / .pi)
                
                // 5. 採樣中心點色彩
                let color = self.getPixelColor(cgImage: cgImage, x: Int(centerX), y: Int(centerY))
                
                results.append(TextObservationResult(
                    text: candidate.string,
                    confidence: candidate.confidence,
                    center: CGPoint(x: centerX, y: centerY),
                    size: CGSize(width: boxWidth, height: boxHeight),
                    angle: -angle, // PPT 的角度方向通常與 Vision 相反
                    hexColor: color
                ))
            }
            completion(results)
        }
        
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        
        try? requestHandler.perform([request])
    }
    
    /// 獲取指定像素的 Hex 顏色值
    private func getPixelColor(cgImage: CGImage, x: Int, y: Int) -> String {
        guard let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data else { return "#FFFFFF" }
        
        let bytesPerRow = cgImage.bytesPerRow
        let pixelData = CFDataGetBytePtr(data)
        
        let pixelInfo: Int = ((bytesPerRow * y) + (x * 4))
        
        if pixelInfo + 3 < CFDataGetLength(data) {
            let r = pixelData![pixelInfo]
            let g = pixelData![pixelInfo + 1]
            let b = pixelData![pixelInfo + 2]
            return String(format: "#%02X%02X%02X", r, g, b)
        }
        
        return "#FFFFFF"
    }
}

// —— 測試執行邏輯 ——
let processor = NativeOCRProcessor()
// 這裡假設有一個測試樣張 test.png
// processor.performOCR(on: URL(fileURLWithPath: "test.png")) { results in ... }
print("✅ PoC 1: NativeOCRProcessor 已就緒")
