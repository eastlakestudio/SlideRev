import Foundation
import AppKit
import Quartz

class PPTXStructuralValidator {
    let fileManager = FileManager.default
    let tempDir = URL(fileURLWithPath: "/tmp/SlideReverse_Test")
    let targetPPTX = URL(fileURLWithPath: "./automated_test.pptx")
    let pdfURL = URL(fileURLWithPath: "./test_files/test_origin.pdf")
    
    func run() {
        print("🚀 [Validator] Starting Clean XML Generation (v8.7)...")
        
        do {
            try? fileManager.removeItem(at: tempDir)
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            
            // 1. Load PDF
            guard let pdfDoc = PDFDocument(url: pdfURL) else {
                print("❌ [Error] Failed to load \(pdfURL.path)"); return
            }
            let pageCount = pdfDoc.pageCount

            // 2. Unzip Template
            let templateUrl = URL(fileURLWithPath: "./empty.pptx")
            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzip.arguments = [templateUrl.path, "-d", tempDir.path]
            try unzip.run(); unzip.waitUntilExit()

            // 3. 🛡️ 核心：从 presentation.xml 获取真实画布尺寸 (EMU)
            var cx: Int64 = 12192000 // Default 16:9
            var cy: Int64 = 6858000
            let presURL = tempDir.appendingPathComponent("ppt/presentation.xml")
            let presContent = try String(contentsOf: presURL, encoding: .utf8)
            if let cxRange = presContent.range(of: "cx=\"(\\d+)\"", options: .regularExpression),
               let cyRange = presContent.range(of: "cy=\"(\\d+)\"", options: .regularExpression) {
                let cxStr = presContent[cxRange].replacingOccurrences(of: "cx=\"", with: "").replacingOccurrences(of: "\"", with: "")
                let cyStr = presContent[cyRange].replacingOccurrences(of: "cy=\"", with: "").replacingOccurrences(of: "\"", with: "")
                cx = Int64(cxStr) ?? cx
                cy = Int64(cyStr) ?? cy
                print("📐 [Validator] Detected Canvas Size from Template: \(cx) x \(cy) EMUs")
            }

            // 4. 准备媒体目录
            let mediaDir = tempDir.appendingPathComponent("ppt/media")
            try? fileManager.createDirectory(at: mediaDir, withIntermediateDirectories: true)

            // 5. 🚀 核心：真机渲染 17 页并生成纯净 XML
            for i in 1...pageCount {
                let slideIndex = i
                let slidePath = tempDir.appendingPathComponent("ppt/slides/slide\(slideIndex).xml")
                let relPath = tempDir.appendingPathComponent("ppt/slides/_rels/slide\(slideIndex).xml.rels")
                
                // 渲染 PDF 页面为 PNG
                if let page = pdfDoc.page(at: i - 1) {
                    let rect = page.bounds(for: .mediaBox)
                    let img = NSImage(size: rect.size)
                    img.lockFocus()
                    if let context = NSGraphicsContext.current?.cgContext {
                        page.draw(with: .mediaBox, to: context)
                    }
                    img.unlockFocus()
                    
                    if let tiff = img.tiffRepresentation, 
                       let bitmap = NSBitmapImageRep(data: tiff),
                       let png = bitmap.representation(using: .png, properties: [:]) {
                        try png.write(to: mediaDir.appendingPathComponent("image_p\(slideIndex).png"))
                    }
                }

                // A. 生成纯净 Slide 关系 (.rels)
                let relStr = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
    <Relationship Id="rId99" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image_p\(slideIndex).png"/>
</Relationships>
"""
                try relStr.write(to: relPath, atomically: true, encoding: .utf8)
                
                // B. 生成纯净 Slide XML (彻底防止旧页面内容污染)
                let slideXML = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
    <p:cSld>
        <p:spTree>
            <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
            <p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>
            <p:pic>
                <p:nvPicPr><p:cNvPr id="2" name="Background"/><p:cNvPicPr/><p:nvPr/></p:nvPr></p:nvPicPr>
                <p:blipFill><a:blip r:embed="rId99"/><a:stretch><a:fillRect/></a:stretch></p:blipFill>
                <p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>
            </p:pic>
        </p:spTree>
    </p:cSld>
</p:sld>
"""
                try slideXML.write(to: slidePath, atomically: true, encoding: .utf8)
            }

            // 6. 黄金接龙逻辑 (同前)
            try patchIronTriangle(tempDir: tempDir, pageCount: pageCount)

            // 7. 打包
            try? fileManager.removeItem(at: targetPPTX)
            let zip = Process()
            zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            zip.arguments = ["-r", targetPPTX.path, "."]
            zip.currentDirectoryURL = tempDir
            try zip.run(); zip.waitUntilExit()
            
            print("✨ [Success] Final automated_test.pptx generated. Structure: Clean, Scaling: Full.")
            
        } catch {
            print("❌ [Error] Crash: \(error)")
        }
    }
    
    private func patchIronTriangle(tempDir: URL, pageCount: Int) throws {
        let presURL = tempDir.appendingPathComponent("ppt/presentation.xml")
        var presXML = try String(contentsOf: presURL, encoding: .utf8)
        var sldList = "<p:sldIdLst>"
        for i in 1...pageCount { sldList += "<p:sldId id=\"\(256+i-1)\" r:id=\"rId\(2000+i)\"/>" }
        sldList += "</p:sldIdLst>"
        if let range = presXML.range(of: "<p:sldIdLst[\\s\\S]*?<\\/p:sldIdLst>", options: .regularExpression) {
            presXML.replaceSubrange(range, with: sldList)
        }
        try presXML.write(to: presURL, atomically: true, encoding: .utf8)

        let relsURL = tempDir.appendingPathComponent("ppt/_rels/presentation.xml.rels")
        var relsStr = "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        relsStr += "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster\" Target=\"slideMasters/slideMaster1.xml\"/>"
        for i in 1...pageCount { relsStr += "<Relationship Id=\"rId\(2000+i)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide\" Target=\"slides/slide\(i).xml\"/>" }
        relsStr += "<Relationship Id=\"rId3001\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/presProps\" Target=\"presProps.xml\"/>"
        relsStr += "<Relationship Id=\"rId3002\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/viewProps\" Target=\"viewProps.xml\"/>"
        relsStr += "<Relationship Id=\"rId3003\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme\" Target=\"theme/theme1.xml\"/>"
        relsStr += "<Relationship Id=\"rId3004\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/tableStyles\" Target=\"tableStyles.xml\"/>"
        relsStr += "</Relationships>"
        try relsStr.write(to: relsURL, atomically: true, encoding: .utf8)

        let typesURL = tempDir.appendingPathComponent("[Content_Types].xml")
        var typesXML = try String(contentsOf: typesURL, encoding: .utf8)
        typesXML = typesXML.replacingOccurrences(of: "<Override PartName=\"/ppt/slides/slide\\d+\\.xml\"[\\s\\S]*?\\/>", with: "", options: [.regularExpression])
        var slideTypes = ""
        for i in 1...pageCount { slideTypes += "<Override PartName=\"/ppt/slides/slide\(i).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slide+xml\"/>" }
        typesXML = typesXML.replacingOccurrences(of: "</Types>", with: "\(slideTypes)</Types>")
        try typesXML.write(to: typesURL, atomically: true, encoding: .utf8)
    }
}

// PPTXStructuralValidator().run()
