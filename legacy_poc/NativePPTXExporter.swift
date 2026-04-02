import Foundation

/// 原生 PPTX 導出器
class NativePPTXExporter {
    
    /// 座標轉換常數
    private let pointsToEMU: Int64 = 12700
    private let dotsPerInch: CGFloat = 72.0
    
    /// 導出 PPTX 主函數
    /// - Parameters:
    ///   - backgroundImagePath: 去字後的背景圖路徑
    ///   - items: 識別到的文字項
    ///   - pageSize: 頁面原始尺寸 (Points)
    ///   - outputPath: 目標存檔位置 (.pptx)
    func export(backgroundImagePath: String, items: [AdvancedSlideProcessor.RecognizedItem], pageSize: CGSize, outputPath: String) {
        print("📁 開始導出 PPTX：\(outputPath)")
        
        let fileManager = FileManager.default
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let slideDir = tempDir.appendingPathComponent("ppt/slides")
        let mediaDir = tempDir.appendingPathComponent("ppt/media")
        
        try? fileManager.createDirectory(at: slideDir, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: mediaDir, withIntermediateDirectories: true)

        // 1. 複製背景圖片到媒體目錄
        let imageURL = URL(fileURLWithPath: backgroundImagePath)
        let targetImageURL = mediaDir.appendingPathComponent("image1.png")
        try? fileManager.copyItem(at: imageURL, to: targetImageURL)

        // 2. 生成幻燈片 XML (ppt/slides/slide1.xml)
        let slideXML = generateSlideXML(items: items, pageSize: pageSize)
        let slideURL = slideDir.appendingPathComponent("slide1.xml")
        try? slideXML.write(to: slideURL, atomically: true, encoding: .utf8)
        
        // 3. 生成關係文件 (ppt/slides/_rels/slide1.xml.rels)
        let relsXML = generateRelsXML()
        let relsDir = slideDir.appendingPathComponent("_rels")
        try? fileManager.createDirectory(at: relsDir, withIntermediateDirectories: true)
        let relsURL = relsDir.appendingPathComponent("slide1.xml.rels")
        try? relsXML.write(to: relsURL, atomically: true, encoding: .utf8)

        // 4. 打包 ZIP (需要 ZIPFoundation 或系統 zip 命令)
        print("📦 正在封裝 OOXML 結構...")
        // 註：此處在具體實作時會調用 ZIP 工具將 tempDir 內的結構打包為 .pptx
        // 為了 PoC 演示，我們目前先生成結構
    }
    
    private func generateSlideXML(items: [AdvancedSlideProcessor.RecognizedItem], pageSize: CGSize) -> String {
        let pageWidthEMU = Int64(pageSize.width * CGFloat(pointsToEMU))
        let pageHeightEMU = Int64(pageSize.height * CGFloat(pointsToEMU))
        
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
            <p:cSld>
                <p:spTree>
                    <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
                    <p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>
                    
                    <!-- 背景圖片層 -->
                    <p:pic>
                        <p:nvPicPr>
                            <p:cNvPr id="2" name="Background Image"/>
                            <p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr>
                            <p:nvPr/>
                        </p:nvPicPr>
                        <p:blipFill>
                            <a:blip r:embed="rId1"/>
                            <a:stretch><a:fillRect/></a:stretch>
                        </p:blipFill>
                        <p:spPr>
                            <a:xfrm>
                                <a:off x="0" y="0"/>
                                <a:ext cx="\(pageWidthEMU)" cy="\(pageHeightEMU)"/>
                            </a:xfrm>
                            <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
                        </p:spPr>
                    </p:pic>
        """
        
        // 注入文字框
        for (index, item) in items.enumerated() {
            let x = Int64(item.rect.origin.x * pageSize.width * CGFloat(pointsToEMU))
            let y = Int64((1 - item.rect.origin.y - item.rect.size.height) * pageSize.height * CGFloat(pointsToEMU))
            let w = Int64(item.rect.size.width * pageSize.width * CGFloat(pointsToEMU))
            let h = Int64(item.rect.size.height * pageSize.height * CGFloat(pointsToEMU))
            
            xml += """
                    <p:sp>
                        <p:nvSpPr>
                            <p:cNvPr id="\(100 + index)" name="Text Box \(index)"/>
                            <p:nvPr/>
                        </p:nvSpPr>
                        <p:spPr>
                            <a:xfrm>
                                <a:off x="\(x)" y="\(y)"/>
                                <a:ext cx="\(w)" cy="\(h)"/>
                            </a:xfrm>
                            <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
                        </p:spPr>
                        <p:txBody>
                            <a:bodyPr rtlCol="0" anchor="ctr"/>
                            <a:lstStyle/>
                            <a:p>
                                <a:r>
                                    <a:rPr lang="zh-CN" sz="1200" b="0"/>
                                    <a:t>\(item.text)</a:t>
                                </a:r>
                            </a:p>
                        </p:txBody>
                    </p:sp>
            """
        }
        
        xml += """
                </p:spTree>
            </p:cSld>
        </p:sld>
        """
        return xml
    }
    
    private func generateRelsXML() -> String {
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image1.png"/>
        </Relationships>
        """
    }
}
