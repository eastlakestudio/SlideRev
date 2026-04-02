import Foundation

class PPTXInjector {
    
    let pointsToEMU: Int64 = 12700
    let templateFile = "Maoming Petrochemical Safety Command_HighFidelity.pptx"
    let workingDir = URL(fileURLWithPath: "pptx_work")
    
    struct OCRSpan: Codable {
        let text: String
        let x, y, width, height, fontSize: Double
        let color: String
    }
    
    struct OCRPage: Codable {
        let pageIndex: Int
        let width, height: Double
        let spans: [OCRSpan]
    }
    
    func hexToRGB(_ hex: String) -> (Int, Int, Int) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)
        return (Int((rgb & 0xFF0000) >> 16), Int((rgb & 0x00FF00) >> 8), Int(rgb & 0x0000FF))
    }
    
    func invertRGB(_ rgb: (Int, Int, Int)) -> (Int, Int, Int) {
        return (255 - rgb.0, 255 - rgb.1, 255 - rgb.2)
    }
    
    func escapeXML(_ text: String) -> String {
        return text.replacingOccurrences(of: "&", with: "&amp;")
                   .replacingOccurrences(of: "<", with: "&lt;")
                   .replacingOccurrences(of: ">", with: "&gt;")
                   .replacingOccurrences(of: "\"", with: "&quot;")
                   .replacingOccurrences(of: "'", with: "&apos;")
    }

    /// 动态估算最优字号，优先适配宽度并兼顾高度
    func calculateOptimalFS(text: String, w: Double, h: Double, origFS: Double) -> Int {
        var totalUnits: Double = 0
        for char in text {
            if char.isASCII {
                totalUnits += 0.52 // 英文字符相对宽度较小
            } else {
                totalUnits += 0.95 // 中文字符接近 1:1，0.95 增加安全边际
            }
        }
        
        // 基于宽度估算的字号 (Width Fit)
        let fsByWidth = (w * 0.94) / max(totalUnits, 0.5) // 留 6% 安全边际
        
        // 基于高度估算的字号 (Height Fit)
        let fsByHeight = h * 0.85 // 留 15% 安全边际，防止上下溢出
        
        // 最终字号：取三者最小值 (OCR 原始字号, 宽度自适应, 高度自适应)
        let finalFS = min(origFS, fsByWidth, fsByHeight)
        
        return Int(finalFS * 100) // PPT sz 是以 0.01 pt 为单位
    }

    func run(jsonPath: String, imagesDir: String, outputPath: String) {
        let fileManager = FileManager.default
        
        // 1. Unzip Template
        print("📦 Extracting template shell...")
        try? fileManager.removeItem(at: workingDir)
        try! fileManager.createDirectory(at: workingDir, withIntermediateDirectories: true)
        
        let unzipTask = Process()
        unzipTask.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzipTask.arguments = [templateFile, "-d", workingDir.path]
        try! unzipTask.run()
        unzipTask.waitUntilExit()
        
        // 2. Load Metadata
        let jsonData = try! Data(contentsOf: URL(fileURLWithPath: jsonPath))
        let pages = try! JSONDecoder().decode([OCRPage].self, from: jsonData)
        
        let wEMU = Int64(pages[0].width * Double(pointsToEMU))
        let hEMU = Int64(pages[0].height * Double(pointsToEMU))
        
        // 3. Update Global Sizing
        let presPath = workingDir.appendingPathComponent("ppt/presentation.xml")
        if let presContent = try? String(contentsOf: presPath, encoding: .utf8) {
            var newPres = presContent
            let pattern = "<p:sldSz [^>]*/>"
            let target = "<p:sldSz cx=\"\(wEMU)\" cy=\"\(hEMU)\"/>"
            if let range = newPres.range(of: pattern, options: .regularExpression) {
                newPres.replaceSubrange(range, with: target)
                try! newPres.write(to: presPath, atomically: true, encoding: .utf8)
            }
        }
        
        // 4. Page Injection
        for (i, page) in pages.enumerated() {
            let slideIdx = i + 1
            print("🖋 Calculating & Injecting Slide \(slideIdx)...")
            
            // A. Replace Image (Sync correctly)
            let targetImgPath = workingDir.appendingPathComponent("ppt/media/Slide-\(slideIdx)-image-1.png")
            let sourceImgPath = URL(fileURLWithPath: "\(imagesDir)/page_\(slideIdx).jpg")
            if fileManager.fileExists(atPath: sourceImgPath.path) {
                try? fileManager.removeItem(at: targetImgPath)
                try? fileManager.copyItem(at: sourceImgPath, to: targetImgPath)
            }
            
            // B. Reconstruct Slide XML
            let slidePath = workingDir.appendingPathComponent("ppt/slides/slide\(slideIdx).xml")
            guard let slideContent = try? String(contentsOf: slidePath, encoding: .utf8) else { continue }
            
            var spTreeContent = """
            <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvPr></p:nvGrpSpPr>
            <p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>
            """
            
            for (j, span) in page.spans.enumerated() {
                let x = Int64(span.x * Double(pointsToEMU))
                let y = Int64(span.y * Double(pointsToEMU))
                let w = Int64(span.width * Double(pointsToEMU))
                let h = Int64(span.height * Double(pointsToEMU))
                
                let textColor = hexToRGB(span.color)
                let bgColor = invertRGB(textColor)
                let textHex = String(format: "%02X%02X%02X", textColor.0, textColor.1, textColor.2)
                let bgHex = String(format: "%02X%02X%02X", bgColor.0, bgColor.1, bgColor.2)
                
                // DYNAMIC FONT SIZE CALCULATION
                let szValue = calculateOptimalFS(text: span.text, w: span.width, h: span.height, origFS: span.fontSize)
                
                spTreeContent += """
                <p:sp>
                    <p:nvSpPr><p:cNvPr id="\(1000 + j)" name="Span \(j)"/><p:nvPr/></p:nvSpPr>
                    <p:spPr>
                        <a:xfrm><a:off x="\(x)" y="\(y)"/><a:ext cx="\(w)" cy="\(h)"/></a:xfrm>
                        <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
                        <a:solidFill><a:srgbClr val="\(bgHex)"/></a:solidFill>
                    </p:spPr>
                    <p:txBody>
                        <a:bodyPr lIns="0" tIns="0" rIns="0" bIns="0" anchor="ctr" wrap="none">
                            <a:normAutofit fontScale="95000" lnSpcReduction="10000"/>
                        </a:bodyPr>
                        <a:p>
                            <a:pPr algn="ctr"/>
                            <a:r>
                                <a:rPr lang="zh-CN" sz="\(szValue)">
                                    <a:solidFill><a:srgbClr val="\(textHex)"/></a:solidFill>
                                    <a:latin typeface="PingFang SC"/>
                                    <a:ea typeface="PingFang SC"/>
                                </a:rPr>
                                <a:t>\(escapeXML(span.text))</a:t>
                            </a:r>
                        </a:p>
                    </p:txBody>
                </p:sp>
                """
            }
            
            if let startRange = slideContent.range(of: "<p:spTree>"),
               let endRange = slideContent.range(of: "</p:spTree>") {
                var newContent = slideContent
                newContent.replaceSubrange(startRange.upperBound..<endRange.lowerBound, with: spTreeContent)
                try! newContent.write(to: slidePath, atomically: true, encoding: .utf8)
            }
        }
        
        // 5. Wrap Zip
        print("📦 Final Archiving...")
        let zipTask = Process()
        zipTask.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zipTask.arguments = ["-r", "../\(outputPath)", "."]
        zipTask.currentDirectoryURL = workingDir
        try! zipTask.run()
        zipTask.waitUntilExit()
        
        print("✅ SUCCESS! Optimized PPTX with DYNAMIC FONT SIZES created at \(outputPath)")
    }
}

let gen = PPTXInjector()
gen.run(jsonPath: "test_origin_extracted.json", imagesDir: "temp_slides", outputPath: "test_origin_final.pptx")
