import Foundation
import CoreGraphics
import CoreText

func testPDFText() {
    let outputURL = URL(fileURLWithPath: "test_text_only.pdf")
    guard let consumer = CGDataConsumer(url: outputURL as CFURL),
          let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
        return
    }
    
    var pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
    context.beginPage(mediaBox: &pageRect)
    
    // CoreText Draw
    let string = "中国移动 China Mobile"
    let font = CTFontCreateWithName("PingFangSC-Regular" as CFString, 12.0, nil)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.black.cgColor
    ]
    let attrString = NSAttributedString(string: string, attributes: attributes)
    let line = CTLineCreateWithAttributedString(attrString)
    
    context.textPosition = CGPoint(x: 100, y: 100)
    CTLineDraw(line, context)
    
    context.endPage()
    context.closePDF()
    print("✅ Test PDF created")
}

testPDFText()
