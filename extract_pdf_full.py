import fitz  # PyMuPDF
import json
import os

def extract_pdf_info(pdf_path):
    """
    Extracts text, position, size, and color from a PDF file.
    
    Returns:
        A list of dictionaries, one per page.
    """
    if not os.path.exists(pdf_path):
        raise FileNotFoundError(f"PDF file not found at: {pdf_path}")

    doc = fitz.open(pdf_path)
    output_data = []

    for i, page in enumerate(doc):
        page_dict = {
            "page_number": i + 1,
            "width": page.rect.width,
            "height": page.rect.height,
            "blocks": []
        }

        # get_text("dict") returns hierarchical structure: blocks -> lines -> spans
        text_dict = page.get_text("dict")

        for block in text_dict["blocks"]:
            # Only process text blocks (type 0)
            if block["type"] == 0:
                block_info = {
                    "bbox": block["bbox"],  # [x0, y0, x1, y1]
                    "lines": []
                }
                for line in block["lines"]:
                    line_info = {
                        "bbox": line["bbox"],
                        "spans": []
                    }
                    for span in line["spans"]:
                        # Convert integer color to hex #RRGGBB
                        # PyMuPDF color is integer: 0xRRGGBB
                        color_int = span["color"]
                        r = (color_int >> 16) & 0xFF
                        g = (color_int >> 8) & 0xFF
                        b = color_int & 0xFF
                        color_hex = f"#{r:02X}{g:02X}{b:02X}"

                        span_info = {
                            "text": span["text"],
                            "font": span["font"],
                            "size": span["size"],
                            "color": color_hex,
                            "bbox": span["bbox"],
                            "flags": span["flags"],
                            "origin": span["origin"]
                        }
                        line_info["spans"].append(span_info)
                    block_info["lines"].append(line_info)
                page_dict["blocks"].append(block_info)

        output_data.append(page_dict)

    doc.close()
    return output_data

if __name__ == "__main__":
    input_pdf = "test_origin.pdf"
    output_json = "test_origin_extracted.json"

    print(f"Opening {input_pdf}...")
    try:
        data = extract_pdf_info(input_pdf)
        print(f"Extracted info from {len(data)} pages.")

        with open(output_json, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        
        print(f"Saved extracted content to {output_json}")

    except Exception as e:
        print(f"Error during extraction: {e}")
