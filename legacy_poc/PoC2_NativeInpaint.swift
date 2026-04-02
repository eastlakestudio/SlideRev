import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins

/// POC 2: 輕量級原生背景修復 (Inpainting)
/// 目標：利用 CoreImage 濾鏡鏈條，在無外部庫情況下抹除文字區域
class NativeInpaintProcessor {
    
    let context = CIContext()
    
    /// 核心修復邏輯：形態學擴張 + 區域模糊 + 遮罩融合
    func inpaint(image: CIImage, maskBoxes: [CGRect], completion: @escaping (CIImage?) -> Void) {
        
        // 1. 生成初始 Mask 圖片 (黑底白字塊)
        var maskImage = CIImage(color: .black).clampedToExtent().cropped(to: image.extent)
        
        for box in maskBoxes {
            let boxImage = CIImage(color: .white).cropped(to: box)
            maskImage = boxImage.composited(over: maskImage)
        }
        
        // 2. 形態學處理：擴張背景像素以「蓋住」文字
        // CIMorphologyMaximum 會取區域內的最大值 (白色)，這裡我們反過來思考
        // 我們需要的是將文字周邊的背景顏色「推」進文字區域
        let backgroundExpansion = CIFilter.morphologyMaximum()
        backgroundExpansion.inputImage = image
        backgroundExpansion.radius = 15.0 // 擴張半徑，應大於字體半徑
        
        guard let expandedBG = backgroundExpansion.outputImage else {
            completion(nil); return
        }
        
        // 3. 區域模糊：讓擴張後的背景與周邊融合更自然
        let blurFilter = CIFilter.gaussianBlur()
        blurFilter.inputImage = expandedBG
        blurFilter.radius = 5.0
        
        guard let blurredBG = blurFilter.outputImage?.cropped(to: image.extent) else {
            completion(nil); return
        }
        
        // 4. 遮罩融合：在 Mask 區域使用模糊後的背景，其餘保留原圖
        let blendFilter = CIFilter.blendWithMask()
        blendFilter.inputImage = blurredBG      // 修復後的背景
        blendFilter.backgroundImage = image    // 原始圖
        blendFilter.maskImage = maskImage      // 文字區域掩碼
        
        let outputImage = blendFilter.outputImage?.cropped(to: image.extent)
        
        completion(outputImage)
    }
    
    /// 輔助方法：將 CIImage 導出為文件以供驗證
    func save(image: CIImage, to url: URL) {
        if let cgImage = context.createCGImage(image, from: image.extent) {
            let nsImage = NSBitmapImageRep(cgImage: cgImage)
            if let data = nsImage.representation(using: .png, properties: [:]) {
                try? data.write(to: url)
                print("💾 修復後的測試圖片已儲存至：\(url.path)")
            }
        }
    }
}

// —— 測試執行邏輯 ——
let inpainter = NativeInpaintProcessor()
// 這裡僅作結構演示：
// inpainter.inpaint(image: sampleImage, maskBoxes: [rect1, rect2]) { result in ... }
print("✅ PoC 2: NativeInpaintProcessor 已就緒")
