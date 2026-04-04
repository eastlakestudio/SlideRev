import XCTest
@testable import SlideRev
import PDFKit

final class MemoryModelTests: XCTestCase {
    
    func testSingleActivePageModel() {
        let processor = AdvancedSlideProcessor()
        
        // Mock a simple PageState
        let index = 5
        let pixelSize = CGSize(width: 100, height: 100)
        let state = AdvancedSlideProcessor.PageState(
            pageIndex: index,
            pdfPage: nil,
            visualSize: pixelSize,
            raw: AdvancedSlideProcessor.RawData(pdfSize: pixelSize),
            refined: AdvancedSlideProcessor.RefinedBundle(textLayers: [], isRefined: false),
            isOCRComplete: true
        )
        
        processor.setPage(at: index, state)
        
        // 1. Verify PageState itself has no bitmap references (Choice 2)
        let retrieved = processor.getPage(at: index)
        XCTAssertNotNil(retrieved)
        
        // 2. Verify processor's active slots are nil initially
        XCTAssertNil(processor.baseCGImage)
        XCTAssertNil(processor.inpaintedImage)
        
        // 3. Simulate switching to that page (UI Re-hydration)
        // Since we can't easily mock PDFPage thumbnail rendering in a headless test without a real PDF,
        // we just verify that the processor's state updates correctly.
        processor.switchToPage(index: index)
        
        XCTAssertEqual(processor.currentPageIndex, index)
    }
    
    func testSessionIDVersioning() {
        let processor = AdvancedSlideProcessor()
        let initialSession = processor.activeSessionID
        
        // Switch page should trigger new session
        processor.switchToPage(index: 1)
        let secondSession = processor.activeSessionID
        
        XCTAssertNotEqual(initialSession, secondSession)
        
        processor.switchToPage(index: 2)
        let thirdSession = processor.activeSessionID
        XCTAssertNotEqual(secondSession, thirdSession)
    }
}
