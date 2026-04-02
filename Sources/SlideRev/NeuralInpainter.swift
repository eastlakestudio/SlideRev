import Foundation
import CoreML
import CoreImage
import Vision
import CoreGraphics

/// NeuralInpainter: 封裝基於 CoreML 的神經網絡修補邏輯 (如 LaMa)
class NeuralInpainter {
    
    private let context = CIContext()
    private var model: MLModel?
    private let targetSize = CGSize(width: 800, height: 800)
    
    init(modelURL: URL?) {
        if let url = modelURL {
            do {
                let config = MLModelConfiguration()
                config.computeUnits = .all 
                self.model = try MLModel(contentsOf: url, configuration: config)
                print("✅ CoreML 模型加载成功: \(url.lastPathComponent)")
            } catch {
                print("❌ 无法加载 CoreML 模型: \(error)")
            }
        }
    }
    
    func inpaint(image: CGImage, mask: CGImage) -> CGImage? {
        guard let model = model else {
            print("⚠️ 未检测到修复模型，请确保已加载 LaMa.mlmodelc")
            return nil
        }
        
        return autoreleasepool {
            let originalSize = CGSize(width: image.width, height: image.height)
            
            // LaMa 需要 800x800
            guard let resizedImage = resize(image: image, to: targetSize),
                  let resizedMask = resize(image: mask, to: targetSize) else {
                print("❌ 缩放失败")
                return nil
            }
            
            do {
                let modelDescription = model.modelDescription
                let inputNames = modelDescription.inputDescriptionsByName.keys
                
                // 转换为模型所需的 PixelBuffer
                guard let imageBuffer = pixelBuffer(from: resizedImage, isMask: false),
                      let maskBuffer = pixelBuffer(from: resizedMask, isMask: true) else {
                    return nil
                }
                
                var inputs: [String: Any] = [:]
                if inputNames.contains("image") { inputs["image"] = imageBuffer }
                if inputNames.contains("mask") { inputs["mask"] = maskBuffer }
                
                let featureProvider = try MLDictionaryFeatureProvider(dictionary: inputs)
                
                // 推理
                let output = try model.prediction(from: featureProvider)
                
                let outputName = modelDescription.outputDescriptionsByName.keys.first ?? "output"
                guard let outputValue = output.featureValue(for: outputName),
                      let outputPixelBuffer = outputValue.imageBufferValue else {
                    print("❌ 模型输出格式不正确")
                    return nil
                }
                
                // 🚀 V31.0: Reuse the class context instead of creating a new one every time!
                let outCGImage = self.context.createCGImage(
                    CIImage(cvPixelBuffer: outputPixelBuffer),
                    from: CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(outputPixelBuffer), height: CVPixelBufferGetHeight(outputPixelBuffer))
                )
                
                // 恢复到原始尺寸
                if let finalCG = outCGImage {
                    return resize(image: finalCG, to: originalSize)
                }
                
                return nil
            } catch {
                print("❌ 推理失败: \(error)")
                return nil
            }
        }
    }
    
    private func resize(image: CGImage, to size: CGSize) -> CGImage? {
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let context = CGContext(data: nil,
                                width: Int(size.width),
                                height: Int(size.height),
                                bitsPerComponent: 8,
                                bytesPerRow: Int(size.width) * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: bitmapInfo)
        context?.interpolationQuality = .high
        context?.draw(image, in: CGRect(origin: .zero, size: size))
        return context?.makeImage()
    }
    
    private func pixelBuffer(from image: CGImage, isMask: Bool) -> CVPixelBuffer? {
        let width = image.width
        let height = image.height
        
        var pixelBuffer: CVPixelBuffer?
        let pixelFormat = isMask ? kCVPixelFormatType_OneComponent8 : kCVPixelFormatType_32BGRA
        
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, pixelFormat, nil, &pixelBuffer)
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        let space = isMask ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = isMask ? CGImageAlphaInfo.none.rawValue : CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        
        let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                                width: width,
                                height: height,
                                bitsPerComponent: 8,
                                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                space: space,
                                bitmapInfo: bitmapInfo)
        
        context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}
