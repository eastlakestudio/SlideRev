import Foundation
import CoreGraphics
import CoreImage
import Vision

// 導入 PoC1 和 PoC2 的邏輯
// 提示：如果在命令行運行，需要將多個文件一起編譯，或者直接在這裡貼入必要的代碼

/// Demo 腳本：加載圖片 -> 識別文字 -> 消除文字 -> 保存結果
func runDemo(inputPath: String, outputPath: String) {
    let imageURL = URL(fileURLWithPath: inputPath)
    
    guard let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
        print("❌ 無法加載輸入圖片: \(inputPath)")
        return
    }
    
    print("🔍 正在識別文字...")
    let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    
    do {
        try requestHandler.perform([request])
        guard let observations = request.results else {
            print("❌ 未發現文字")
            return
        }
        
        print("🧹 正在消除 \(observations.count) 處文字區域 (幾何模式)...")
        let eraser = TextEraser()
        if let result = eraser.erase(from: cgImage, observations: observations, strategy: .geometric, padding: 3.0) {
            
            let outputURL = URL(fileURLWithPath: outputPath)
            TextEraser.save(result.outputImage, to: outputURL)
            print("✨ 處理完成！結果已保存至: \(outputPath)")
            
        } else {
            print("❌ 消除失敗")
        }
    } catch {
        print("❌ 執行出錯: \(error)")
    }
}

@main
struct EraseTextDemo {
    static func main() {
        let input = "debug_page1.png"
        let output = "debug_page1_cleaned.png"

        if FileManager.default.fileExists(atPath: input) {
            runDemo(inputPath: input, outputPath: output)
        } else {
            print("⚠️ 未找到 debug_page1.png，請提供一個有效的測試圖片。")
        }
    }
}
