import Foundation
import PDFKit

func verifyPDF(path: String) {
    let url = URL(fileURLWithPath: path)
    guard let document = PDFDocument(url: url) else {
        print("❌ Cannot load PDF")
        return
    }
    
    var totalTextLength = 0
    for i in 0..<document.pageCount {
        if let page = document.page(at: i), let text = page.string {
            print("Page \(i+1) text: \(text.prefix(50))...")
            totalTextLength += text.count
        }
    }
    
    if totalTextLength > 0 {
        print("✅ Success! Found \(totalTextLength) characters of vector text.")
    } else {
        print("❌ Failure: No selectable text found in PDF.")
    }
}

let args = CommandLine.arguments
if args.count > 1 {
    verifyPDF(path: args[1])
} else {
    print("Usage: swift verify_pdf_text.swift <pdf_path>")
}
