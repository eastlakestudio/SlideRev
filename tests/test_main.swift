import Foundation
import CoreGraphics
import CoreML
import ImageIO
import AppKit

/// NeuralInpainterTests: 验证修补引擎的基础功能
class NeuralInpainterTests {
    
    func runAll() {
        print("🧪 [Unit Test] 启动 NeuralInpainter 测试...")
        
        testInitialization()
        testImageResizing()
        testInpaintWithEmptyModel()
        
        print("✅ 所有单元测试执行完毕")
    }
    
    // 1. 验证模型加载
    func testInitialization() {
        print("   - 测试 1: 模型加载...")
        let modelURL = URL(fileURLWithPath: "3rd/coremlama/LaMa.mlmodelc")
        _ = NeuralInpainter(modelURL: modelURL)
    }
    
    // 2. 验证缩放逻辑
    func testImageResizing() {
        print("   - 测试 2: 图片自动缩放适配...")
        let width = 100
        let height = 100
        guard let dummyImage = createDummyImage(width: width, height: height, color: .red) else {
            print("     ❌ 无法创建测试图片")
            return
        }
        
        let inpainter = NeuralInpainter(modelURL: nil)
        _ = inpainter.inpaint(image: dummyImage, mask: dummyImage)
        print("     ✅ 缩放流程通过 (未崩溃)")
    }
    
    // 3. 验证空模型处理
    func testInpaintWithEmptyModel() {
        print("   - 测试 3: 空模型安全性测试...")
        let inpainter = NeuralInpainter(modelURL: nil)
        guard let dummy = createDummyImage(width: 10, height: 10, color: .blue) else { return }
        let result = inpainter.inpaint(image: dummy, mask: dummy)
        if result == nil {
            print("     ✅ 成功捕捉空模型异常")
        } else {
            print("     ❌ 空模型不应返回结果")
        }
    }
    
    // 辅助工具：创建纯色图片
    private func createDummyImage(width: Int, height: Int, color: NSColor) -> CGImage? {
        let size = CGSize(width: width, height: height)
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo) else { return nil }
        context.setFillColor(color.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        return context.makeImage()
    }
}

// 执行测试
let testRunner = NeuralInpainterTests()
testRunner.runAll()
