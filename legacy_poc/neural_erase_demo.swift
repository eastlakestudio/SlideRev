import Foundation
import CoreGraphics
import CoreImage
import Vision

/// AI 消除示範腳本 (Neural Eraser Demo)
/// 使用方式: swift neural_erase_demo.swift
func runNeuralDemo() {
    let input = "debug_page1.png"
    let output = "debug_page1_ai_cleaned.png"
    let modelPath = "models/LaMa.mlmodelc" // 假設模型放置在此
    
    let imageURL = URL(fileURLWithPath: input)
    guard let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
        print("⚠️ 未找到輸入圖片: \(input)")
        return
    }
    
    // 1. 初始化神經網絡修補器
    let modelURL = URL(fileURLWithPath: modelPath)
    let inpainter = NeuralInpainter(modelURL: modelURL)
    
    // 2. 初始化文字消除器並配置 AI 引擎
    let eraser = TextEraser()
    eraser.neuralInpainter = inpainter
    
    // 3. 識別文字
    print("🔍 正在識別文字區域...")
    let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    
    do {
        try requestHandler.perform([request])
        guard let observations = request.results else { return }
        
        // 4. 執行消除 (優先使用神經網絡)
        print("🧠 正在使用 AI 模型進行高保真修補...")
        if let result = eraser.erase(from: cgImage, 
                                     observations: observations, 
                                     strategy: .neural, 
                                     padding: 5.0) {
            
            let outputURL = URL(fileURLWithPath: output)
            TextEraser.save(result.outputImage, to: outputURL)
            print("✨ AI 處理完成！結果已保存至: \(output)")
            print("💡 提示：如果背景仍然模糊，請檢查模型是否已正確加載，或增加 padding 像素。")
        }
        
    } catch {
        print("❌ 執行失敗: \(error)")
    }
}

@main
struct NeuralEraseDemo {
    static func main() {
        runNeuralDemo()
    }
}
