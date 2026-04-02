import Foundation
import Vision
import CoreGraphics
import CoreImage
import PDFKit

// MARK: - Data Models

struct OCRSpan: Codable {
    let text: String
    let confidence: Float
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let angle: Double
    let color: String
    let fontSize: Double
}

struct OCRPage: Codable {
    let pageIndex: Int
    let width: Double
    let height: Double
    let spans: [OCRSpan]
}

// MARK: - Native OCR Processor

class VisionExtractor {
    
    func extract(pdfURL: URL) -> [OCRPage] {
        guard let document = PDFDocument(url: pdfURL) else {
            print("❌ Failed to load PDF at: \(pdfURL.path)")
            return []
        }
        
        var pagesResult: [OCRPage] = []
        let totalPages = document.pageCount
        
        for i in 0..<totalPages {
            print("Processing page \(i + 1) of \(totalPages)...")
            guard let page = document.page(at: i) else { continue }
            
            let pageRect = page.bounds(for: .mediaBox)
            let pageWidth = pageRect.width
            let pageHeight = pageRect.height
            
            // Render PDF Page to CGImage (300 DPI)
            let scale: CGFloat = 300.0 / 72.0
            let pixelWidth = Int(pageWidth * scale)
            let pixelHeight = Int(pageHeight * scale)
            
            guard let context = CGContext(data: nil,
                                        width: pixelWidth,
                                        height: pixelHeight,
                                        bitsPerComponent: 8,
                                        bytesPerRow: 0,
                                        space: CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                continue
            }
            
            context.setFillColor(CGColor.white)
            context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
            context.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: context)
            
            guard let cgImage = context.makeImage() else { continue }
            
            // Perform Visual OCR
            let spans = performVisionOCR(on: cgImage)
            
            // Convert to PDF coordinates and Page structure
            let ocrPage = OCRPage(
                pageIndex: i + 1,
                width: Double(pageWidth),
                height: Double(pageHeight),
                spans: spans
            )
            pagesResult.append(ocrPage)
        }
        
        return pagesResult
    }
    
    private func performVisionOCR(on cgImage: CGImage) -> [OCRSpan] {
        let semaphore = DispatchSemaphore(value: 0)
        var results: [OCRSpan] = []
        
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        let request = VNRecognizeTextRequest { (request, error) in
            defer { semaphore.signal() }
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            
            for observation in observations {
                guard let candidate = observation.topCandidates(1).first else { continue }
                
                let box = observation.boundingBox // Vision coords: 0.0 to 1.0, Origin Bottom-Left
                
                // OCR returns normalized coords
                // Convert Vision normalized (y-up) to Pixel coordinates (initially y-up per Vision design)
                let centerX = (box.origin.x + box.size.width / 2) * width
                let centerY = (box.origin.y + box.size.height / 2) * height
                
                // Color sampling in image space (cgImage is y-down in memory access usually? or y-up?)
                // cgImage pixels are indexed from top-left.
                // Vision Y is bottom-up. So pixel y = height - vision_y
                let pixelY = Int(height) - Int(centerY)
                let pixelX = Int(centerX)
                
                let color = self.getPixelColor(cgImage: cgImage, x: pixelX, y: pixelY)
                
                // Invert Y for Top-Left origin output (Standard JSON / Desktop UI)
                let yTopDown = (1.0 - (box.origin.y + box.size.height)) * height
                
                // Calculate size in pixels
                let wPx = box.size.width * width
                let hPx = box.size.height * height
                
                // Convert back to scale-adjusted "points" (assuming output wants original PDF pts)
                // We'll normalize to 1/72 units here for simplicity
                let scale: Double = (300.0 / 72.0)
                
                results.append(OCRSpan(
                    text: candidate.string,
                    confidence: candidate.confidence,
                    x: Double(box.origin.x * width) / scale,
                    y: Double(yTopDown) / scale,
                    width: Double(wPx) / scale,
                    height: Double(hPx) / scale,
                    angle: 0.0, // Vision doesn't provide individual span rotation as double directly here for simple boxes
                    color: color,
                    fontSize: Double(hPx) / scale
                ))
            }
        }
        
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = true
        
        do {
            try requestHandler.perform([request])
            semaphore.wait()
        } catch {
            print("OCR Request error: \(error)")
        }
        
        return results
    }
    
    private func getPixelColor(cgImage: CGImage, x: Int, y: Int) -> String {
        guard let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data else { return "#000000" }
        
        let bytesPerRow = cgImage.bytesPerRow
        let pixelData = CFDataGetBytePtr(data)
        
        let tx = max(0, min(x, cgImage.width - 1))
        let ty = max(0, min(y, cgImage.height - 1))
        
        let pixelInfo: Int = ((bytesPerRow * ty) + (tx * 4))
        let dataLen = CFDataGetLength(data)
        
        if pixelInfo + 3 < dataLen {
            let r = pixelData![pixelInfo]
            let g = pixelData![pixelInfo + 1]
            let b = pixelData![pixelInfo + 2]
            return String(format: "#%02X%02X%02X", r, g, b)
        }
        
        return "#000000"
    }
}

// MARK: - Main Execution

let args = CommandLine.arguments
if args.count < 3 {
    print("Usage: swift extract_vision_ocr.swift <input_pdf> <output_json>")
    exit(1)
}

let inputPath = args[1]
let outputPath = args[2]

let inputURL = URL(fileURLWithPath: inputPath)
let extractor = VisionExtractor()
let results = extractor.extract(pdfURL: inputURL)

let encoder = JSONEncoder()
encoder.outputFormatting = .prettyPrinted

do {
    let jsonData = try encoder.encode(results)
    try jsonData.write(to: URL(fileURLWithPath: outputPath))
    print("✅ Success! Extracted \(results.count) pages to \(outputPath)")
} catch {
    print("❌ Failed to save JSON: \(error)")
}
