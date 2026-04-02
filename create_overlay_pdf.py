import fitz
import json
import os

def hex_to_rgb_normalized(hex_color):
    """
    Converts #RRGGBB to (r, g, b) floats [0, 1].
    """
    hex_color = hex_color.lstrip('#')
    r = int(hex_color[0:2], 16) / 255.0
    g = int(hex_color[2:4], 16) / 255.0
    b = int(hex_color[4:6], 16) / 255.0
    return (r, g, b)

def invert_color(rgb_normalized):
    """
    Inverts the RGB color.
    """
    return (1.0 - rgb_normalized[0], 1.0 - rgb_normalized[1], 1.0 - rgb_normalized[2])

def create_overlay_pdf(input_pdf_path, input_json_path, output_pdf_path):
    # Load OCR data
    with open(input_json_path, 'r', encoding='utf-8') as f:
        pages_data = json.load(f)
    
    # Open original PDF
    doc = fitz.open(input_pdf_path)
    
    # Check for Chinese font availability on Mac
    # Common path: /System/Library/Fonts/PingFang.ttc
    font_path = "/System/Library/Fonts/PingFang.ttc"
    if not os.path.exists(font_path):
        # Fallback to something else if needed, but on Mac this should exist
        font_path = None 

    for page_data in pages_data:
        page_idx = page_data["pageIndex"] - 1
        if page_idx >= len(doc):
            continue
            
        page = doc[page_idx]
        spans = page_data.get("spans", [])
        
        for span in spans:
            text = span["text"]
            x = span["x"]
            y = span["y"]
            w = span["width"]
            h = span["height"]
            font_size = span["fontSize"]
            color_hex = span["color"]
            
            # 1. Colors
            fg_rgb = hex_to_rgb_normalized(color_hex)
            bg_rgb = invert_color(fg_rgb)
            
            # 2. Draw Background Box (20% transparency)
            # Rect: (x0, y0, x1, y1)
            # Our JSON has x, y as top-left of the text block
            rect = fitz.Rect(x, y, x + w, y + h)
            page.draw_rect(rect, 
                          color=None, 
                          fill=bg_rgb, 
                          fill_opacity=0.2)
            
            # 3. Insert Text
            # We use insert_text. The 'point' is the baseline/origin.
            # Usually y in Vision/PDF points is top or center?
            # In our Swift script, y was (1.0 - (box.origin.y + box.size.height)) * height / scale
            # This corresponds to the TOP of the box.
            # insert_text usually expects a point. We'll use the top-left (x, y) 
            # but font size might shift it. We'll adjust slightly if needed.
            
            # For better alignment, we use insert_textbox
            page.insert_textbox(rect, 
                               text, 
                               fontsize=font_size, 
                               color=fg_rgb, 
                               fontname="china-s" if font_path is None else "font1",
                               fontfile=font_path,
                               align=0) # align=0 is left

    # Save
    doc.save(output_pdf_path)
    doc.close()
    print(f"✅ Successfully created editable PDF: {output_pdf_path}")

if __name__ == "__main__":
    create_overlay_pdf("test_origin.pdf", "test_origin_extracted.json", "test_origin_editable.pdf")
