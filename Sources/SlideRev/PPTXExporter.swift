import Foundation
import AppKit
import ZIPFoundation

class PPTXExporter {
    static let shared = PPTXExporter()
    
    // Physical Constants
    private let EMU_PER_PT: Double = 12700
    
    func export(processor: AdvancedSlideProcessor,
                pages: [Int: AdvancedSlideProcessor.PageState], 
                to targetURL: URL, 
                progress: ((Int, Int) -> Void)? = nil, 
                completion: @escaping (Bool, String) -> Void) {
        AdvancedSlideProcessor.fileLog("🚀 [PPTXExporter] Starting native export to: \(targetURL.path)")
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        
        do {
            // 🚀 v37.6: Remove pre-creation of tempDir. 
            // FileManager.copyItem requires the destination to NOT exist; it creates it as a copy of the source.
            // This fixes the "PPTXTemplate couldn't be copied because item already exists" error.
            
            // 🚀 v37.5: 100% Sandbox-Safe Template Preparation.
            // Instead of unzipping at runtime (which is restricted), we bundle the expanded folder 'PPTXTemplate'.
            let templateUrl = Bundle.main.url(forResource: "PPTXTemplate", withExtension: nil)
            AdvancedSlideProcessor.fileLog("🔍 [PPTXExporter] Bundle Resolved Template URL: \(templateUrl?.path ?? "N/A")")
            
            guard let finalTemplate = templateUrl else {
                let errorMsg = "Critical Error: 'PPTXTemplate' folder missing from bundle Resources. PPTX export blocked."
                AdvancedSlideProcessor.fileLog("❌ [PPTXExporter] \(errorMsg)")
                completion(false, errorMsg); return
            }
            
            // Native copy is 100% reliable in sandbox
            AdvancedSlideProcessor.fileLog("📁 [PPTXExporter] Attempting to copy template from \(finalTemplate.path) to \(tempDir.path)")
            try fileManager.copyItem(at: finalTemplate, to: tempDir)
            AdvancedSlideProcessor.fileLog("✅ [PPTXExporter] Template copied successfully.")
            
            let sortedIndices = pages.keys.sorted()
            let pageCount = sortedIndices.count
            
            // 🚀 2. 🛡️ 核心：V9.2 全球最大值对齐 (Max-Bound Scaling)
            let pdfWidths = pages.values.map { $0.raw.pdfSize.width }
            let pdfHeights = pages.values.map { $0.raw.pdfSize.height }
            let globalW = pdfWidths.max() ?? 720.0
            let globalH = pdfHeights.max() ?? 540.0
            
            let cxEMU = Int64(globalW * EMU_PER_PT)
            let cyEMU = Int64(globalH * EMU_PER_PT)
            print("📐 [PPTXExporter] Global Max Canvas: \(globalW)x\(globalH) pts (\(cxEMU)x\(cyEMU) EMUs)")

            // 3. Prepare Media
            let mediaDir = tempDir.appendingPathComponent("ppt/media")
            try fileManager.createDirectory(at: mediaDir, withIntermediateDirectories: true)
            
            // 4. Generate Slides
            let slidesDir = tempDir.appendingPathComponent("ppt/slides")
            let slidesRelsDir = slidesDir.appendingPathComponent("_rels")
            try fileManager.createDirectory(at: slidesRelsDir, withIntermediateDirectories: true)
            
            for i in 1...pageCount {
                let slideIndex = i
                let slidePath = slidesDir.appendingPathComponent("slide\(slideIndex).xml")
                let relPath = slidesRelsDir.appendingPathComponent("slide\(slideIndex).xml.rels")
                
                guard let pageIndex = sortedIndices.safeGet(i-1), let page = pages[pageIndex] else { continue }

                // Image Injection
                let imgName = "image_p\(slideIndex).png"
                let imgPath = mediaDir.appendingPathComponent(imgName)
                
                // 🚀 v58.0: On-demand hydration (NOW SYNCHRONOUS & CACHE-AWARE)
                let result = processor.getHydratedImages(for: pageIndex)
                if let bgCG = result.refined,
                   let tiff = NSImage(cgImage: bgCG, size: page.visualSize).tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiff),
                   let png = bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) {
                    try png.write(to: imgPath)
                }
                
                // 🚀 V0.9.6.15: Report Progress
                DispatchQueue.main.async {
                    progress?(slideIndex, pageCount)
                }

                // 🧠 V9.2 fitScale Logic
                let pageW = page.raw.pdfSize.width
                let pageH = page.raw.pdfSize.height
                let fitScale = min(globalW / pageW, globalH / pageH)
                let offX = (globalW - pageW * fitScale) / 2.0
                let offY = (globalH - pageH * fitScale) / 2.0
                
                let offX_EMU = Int64(offX * EMU_PER_PT)
                let offY_EMU = Int64(offY * EMU_PER_PT)
                let extX_EMU = Int64(pageW * fitScale * EMU_PER_PT)
                let extY_EMU = Int64(pageH * fitScale * EMU_PER_PT)

                // A. Relationship XML
                let relStr = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
    <Relationship Id="rId99" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/\(imgName)"/>
</Relationships>
"""
                try relStr.write(to: relPath, atomically: true, encoding: .utf8)
                
                // B. Slide XML
                let shapesXML = generateShapesXML(page: page, fitScale: fitScale, offX: offX, offY: offY)
                let slideXML = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
    <p:cSld>
        <p:spTree>
            <p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
            <p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>
            <p:pic>
                <p:nvPicPr><p:cNvPr id="2" name=""/><p:cNvPicPr/><p:nvPr/></p:nvPicPr>
                <p:blipFill><a:blip r:embed="rId99"/><a:stretch><a:fillRect/></a:stretch></p:blipFill>
                <p:spPr><a:xfrm><a:off x="\(offX_EMU)" y="\(offY_EMU)"/><a:ext cx="\(extX_EMU)" cy="\(extY_EMU)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>
            </p:pic>
            \(shapesXML)
        </p:spTree>
    </p:cSld>
</p:sld>
"""
                try slideXML.write(to: slidePath, atomically: true, encoding: .utf8)
            }
            
            AdvancedSlideProcessor.fileLog("🔗 [PPTXExporter] Starting patchIronTriangleGolden...")
            try patchIronTriangleGolden(tempDir: tempDir, pageCount: pageCount, w: cxEMU, h: cyEMU)
            AdvancedSlideProcessor.fileLog("✅ [PPTXExporter] Metadata patching complete.")

            // Packaging
            // 🚀 v38.5: Native ZIP using ZIPFoundation (SPM Integration)
            // No more zip_tool binary needed!
            
            // Remove existing if any
            if fileManager.fileExists(atPath: targetURL.path) {
                AdvancedSlideProcessor.fileLog("🧹 [PPTXExporter] Removing existing target file at: \(targetURL.path)")
                try fileManager.removeItem(at: targetURL)
            }
            
            // ZIP up from tempDir
            let localZipURL = fileManager.temporaryDirectory.appendingPathComponent("SlideRev_Export_Native_\(UUID().uuidString).pptx")
            AdvancedSlideProcessor.fileLog("📦 [PPTXExporter] Initializing native ZIP archive at: \(localZipURL.path)")
            
            let archive = try Archive(url: localZipURL, accessMode: .create)
            
            // Recursively add everything in tempDir to archive
            let enumerator = fileManager.enumerator(at: tempDir, includingPropertiesForKeys: [.isDirectoryKey], options: [])
            while let fileURL = enumerator?.nextObject() as? URL {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
                if resourceValues.isDirectory ?? false { continue } // Skip directory entries
                
                let relativePath = fileURL.path.replacingOccurrences(of: tempDir.path + "/", with: "")
                if relativePath.isEmpty || relativePath == tempDir.path { continue }
                
                try archive.addEntry(with: relativePath, fileURL: fileURL)
            }
            
            AdvancedSlideProcessor.fileLog("🚚 [PPTXExporter] Moving native package to final destination: \(targetURL.path)")
            try fileManager.moveItem(at: localZipURL, to: targetURL)
            
            AdvancedSlideProcessor.fileLog("✨ [PPTXExporter] Native Export SUCCESS to \(targetURL.lastPathComponent)")
            completion(true, "Successfully exported to \(targetURL.lastPathComponent)")
            
        } catch {
            AdvancedSlideProcessor.fileLog("💥 [PPTXExporter] FATAL EXCEPTION: \(error.localizedDescription)")
            completion(false, error.localizedDescription)
        }
    }
    
    private func generateShapesXML(page: AdvancedSlideProcessor.PageState, fitScale: Double, offX: Double, offY: Double) -> String {
        var xml = ""
        let pw = page.raw.pdfSize.width
        let ph = page.raw.pdfSize.height
        
        for (i, item) in page.refined.textLayers.enumerated() {
            // 🚀 V58.8: EXPORT FILTER - Only export text boxes that are meant to be visible
            if !item.isErased || !item.isTextVisible { continue }
            let text = escapeXML(item.editedText.isEmpty ? item.text : item.editedText)
            
            let xPt = offX + (item.rect.origin.x * pw * fitScale)
            let yPt = offY + (item.rect.origin.y * ph * fitScale)
            let wPt = item.rect.size.width * pw * fitScale
            let hPt = item.rect.size.height * ph * fitScale
            
            let xEMU = Int64(xPt * EMU_PER_PT)
            let yEMU = Int64(yPt * EMU_PER_PT)
            let wEMU = Int64(wPt * EMU_PER_PT)
            let hEMU = Int64(hPt * EMU_PER_PT)
            
            let finalSizePt = (item.fontSize / (200.0 / 72.0)) * fitScale
            let sz = Int(finalSizePt * 100)
            
            let hex = hexString(from: item.color)
            let shapeId = 1000 + i
            
            xml += """
            <p:sp>
                <p:nvSpPr><p:cNvPr id="\(shapeId)" name=""/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>
                <p:spPr>
                    <a:xfrm><a:off x="\(xEMU)" y="\(yEMU)"/><a:ext cx="\(wEMU)" cy="\(hEMU)"/></a:xfrm>
                    <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
                </p:spPr>
                <p:txBody>
                    <a:bodyPr anchor="ctr" wrap="none" lIns="0" tIns="0" rIns="0" bIns="0">
                        <a:spAutoFit/>
                    </a:bodyPr>
                    <a:lstStyle/>
                    <a:p>
                        <a:pPr algn="ctr" rtl="0"/>
                        <a:r>
                            <a:rPr lang="en-US" sz="\(sz)" b="\(item.isBold ? "1" : "0")">
                                <a:solidFill><a:srgbClr val="\(hex)"/></a:solidFill>
                                <a:latin typeface="\(item.fontName)"/>
                                <a:ea typeface="\(item.fontName)"/>
                            </a:rPr>
                            <a:t>\(text)</a:t>
                        </a:r>
                    </a:p>
                </p:txBody>
            </p:sp>
            """
        }
        return xml
    }
    
    private func patchIronTriangleGolden(tempDir: URL, pageCount: Int, w: Int64, h: Int64) throws {
        // 1. [Content_Types].xml: Replace existing slide overrides
        let ctPath = tempDir.appendingPathComponent("[Content_Types].xml")
        var ct = try String(contentsOf: ctPath, encoding: .utf8)
        
        // Remove all current slide overrides to prevent duplicates
        let ctPattern = "<Override PartName=\"/ppt/slides/slide\\d+\\.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slide\\+xml\"/>"
        ct = ct.replacingOccurrences(of: ctPattern, with: "", options: .regularExpression)
        
        var overrides = ""
        for i in 1...pageCount {
            overrides += "<Override PartName=\"/ppt/slides/slide\(i).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slide+xml\"/>\n"
        }
        if let range = ct.range(of: "</Types>") {
            ct.insert(contentsOf: overrides, at: range.lowerBound)
            try ct.write(to: ctPath, atomically: true, encoding: .utf8)
        }
        
        // 2. ppt/_rels/presentation.xml.rels: Replace slide relationships
        let presRelsPath = tempDir.appendingPathComponent("ppt/_rels/presentation.xml.rels")
        var pr = try String(contentsOf: presRelsPath, encoding: .utf8)
        
        // Remove all slide relationships (rId...) to prevent collision
        let relPattern = "<Relationship Id=\"rId\\d+\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide\" Target=\"slides/slide\\d+\\.xml\"/>"
        pr = pr.replacingOccurrences(of: relPattern, with: "", options: .regularExpression)
        
        var rels = ""
        for i in 1...pageCount {
            rels += "<Relationship Id=\"rId\(100+i)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide\" Target=\"slides/slide\(i).xml\"/>\n"
        }
        if let range = pr.range(of: "</Relationships>") {
            pr.insert(contentsOf: rels, at: range.lowerBound)
            try pr.write(to: presRelsPath, atomically: true, encoding: .utf8)
        }
        
        // 3. ppt/presentation.xml: Replace slide ID list and size
        let presPath = tempDir.appendingPathComponent("ppt/presentation.xml")
        var pXML = try String(contentsOf: presPath, encoding: .utf8)
        
        // Update Canvas Size
        let sizeTag = "<p:sldSz cx=\"\(w)\" cy=\"\(h)\"/>"
        if let range = pXML.range(of: "<p:sldSz[^>]*/>", options: .regularExpression) {
            pXML.replaceSubrange(range, with: sizeTag)
        }
        
        // Replace sldIdLst entirely
        var sldIds = "<p:sldIdLst>\n"
        for i in 1...pageCount {
            sldIds += "<p:sldId id=\"\(255+i)\" r:id=\"rId\(100+i)\"/>\n"
        }
        sldIds += "</p:sldIdLst>"
        
        if let startRange = pXML.range(of: "<p:sldIdLst>"),
           let endRange = pXML.range(of: "</p:sldIdLst>", range: startRange.upperBound..<pXML.endIndex) {
            let fullRange = startRange.lowerBound..<endRange.upperBound
            pXML.replaceSubrange(fullRange, with: sldIds)
        } else if let range = pXML.range(of: "<p:sldIdLst/>") {
            pXML.replaceSubrange(range, with: sldIds)
        }
        
        try pXML.write(to: presPath, atomically: true, encoding: .utf8)
    }
}

extension Array {
    func safeGet(_ index: Int) -> Element? {
        return (index >= 0 && index < count) ? self[index] : nil
    }
}

private func escapeXML(_ string: String) -> String {
    return string.replacingOccurrences(of: "&", with: "&amp;")
                 .replacingOccurrences(of: "<", with: "&lt;")
                 .replacingOccurrences(of: ">", with: "&gt;")
}

private func hexString(from color: CGColor) -> String {
    let components = color.components ?? [0,0,0,1]
    let r = Int(components[0] * 255)
    let g = Int(components[1] * 255)
    let b = Int(components[2] * 255)
    return String(format: "%02X%02X%02X", r, g, b)
}
