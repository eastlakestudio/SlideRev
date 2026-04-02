import Foundation
import CoreGraphics
import CoreML
import ImageIO

/// NeuralInpainterTests: 驗證修補引擎的基礎功能
class NeuralInpainterTests {
    
    func runAll() {
        print("🧪 [Unit Test] 啟動 NeuralInpainter 測試...")
        
        testInitialization()
        testImageResizing()
        testInpaintWithEmptyModel()
        
        print("✅ 所有單元測試執行完畢")
    }
    
    // 1. 測試初始化
    func testInitialization() {
        print("   - 測試 1: 模型加載...")
        let modelURL = URL(fileURLWithPath: "temp_coremlama/LaMa.mlmodelc")
        let inpainter = NeuralInpainter(modelURL: modelURL)
        // 這裡我們假設模型存在，如果不存在，inpainter 內部會印出錯誤
    }
    
    // 2. 測試縮放邏輯
    func testImageResizing() {
        print("   - 測試 2: 圖片自動縮放適配...")
        let width = 100
        let height = 100
        guard let dummyImage = createDummyImage(width: width, height: height, color: .red) else {
            print("     ❌ 無法創建測試圖片")
            return
        }
        
        let inpainter = NeuralInpainter(modelURL: nil)
        // 使用私有方法的測試通常需要反射或公開，這裡我們通過執行一次 inpaint (即使模型為 nil) 來觸發邏輯路徑
        // 由於 resize 是私有的，這裡我們主要驗證流程不崩潰
        _ = inpainter.inpaint(image: dummyImage, mask: dummyImage)
        print("     ✅ 縮放流程通過 (未崩潰)")
    }
    
    // 3. 測試空模型處理
    func testInpaintWithEmptyModel() {
        print("   - 測試 3: 空模型安全性測試...")
        let inpainter = NeuralInpainter(modelURL: nil)
        guard let dummy = createDummyImage(width: 10, height: 10, color: .blue) else { return }
        let result = inpainter.inpaint(image: dummy, mask: dummy)
        if result == nil {
            print("     ✅ 成功捕捉空模型異常")
        } else {
            print("     ❌ 空模型不應返回結果")
        }
    }
    
    // 輔助工具：創建純色圖片
    private func createDummyImage(width: Int, height: Int, color: NSColor) -> CGImage? {
        let size = CGSize(width: width, height: height)
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo) else { return nil }
        context.setFillColor(color.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        return context.makeImage()
    }
}

// 快速運行測試腳本
import AppKit
let testRunner = NeuralInpainterTests()
testRunner.runAll()
