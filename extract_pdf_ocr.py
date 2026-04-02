import os
import cv2
import numpy as np
import fitz  # PyMuPDF
from paddleocr import PaddleOCR
import json
import logging

# Setup Logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class PDFOCRExtractor:
    def __init__(self, lang='ch', use_gpu=False):
        """
        Init PaddleOCR.
        """
        self.ocr = PaddleOCR(use_angle_cls=True, lang=lang, use_gpu=use_gpu, show_log=False)
        self.dpi = 300

    def get_text_color(self, img_cv, bbox):
        """
        Samples the text color from the bounding box area.
        Simplified approach: find the darkest pixel in the region (assuming text is darker than background).
        """
        x_min, y_min = int(min(p[0] for p in bbox)), int(min(p[1] for p in bbox))
        x_max, y_max = int(max(p[0] for p in bbox)), int(max(p[1] for p in bbox))
        
        # Ensure box is within image
        h_img, w_img = img_cv.shape[:2]
        x_min, y_min = max(0, x_min), max(0, y_min)
        x_max, y_max = min(w_img-1, x_max), min(h_img-1, y_max)

        if x_max <= x_min or y_max <= y_min:
            return "#000000"

        roi = img_cv[y_min:y_max, x_min:x_max]
        
        # Convert to gray to find "intensity"
        gray = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)
        
        # Find the pixel coordinate with the minimum grayscale value (darkest)
        min_val, max_val, min_loc, max_loc = cv2.minMaxLoc(gray)
        
        # Get the color at that location in the original ROI
        # OpenCV is BGR
        color_bgr = roi[min_loc[1], min_loc[0]]
        return "#{:02X}{:02X}{:02X}".format(color_bgr[2], color_bgr[1], color_bgr[0])

    def extract(self, pdf_path):
        if not os.path.exists(pdf_path):
            raise FileNotFoundError(f"PDF not found: {pdf_path}")

        doc = fitz.open(pdf_path)
        all_pages = []

        for i, page in enumerate(doc):
            logger.info(f"Processing Page {i+1}/{len(doc)}")
            
            # Render page to high-dpi image
            matrix = fitz.Matrix(self.dpi / 72.0, self.dpi / 72.0)
            pix = page.get_pixmap(matrix=matrix)
            
            # Convert to OpenCV BGR
            img_np = np.frombuffer(pix.samples, dtype=np.uint8).reshape(pix.h, pix.w, pix.n)
            if pix.n == 4:
                img_cv = cv2.cvtColor(img_np, cv2.COLOR_RGBA2BGR)
            else:
                img_cv = cv2.cvtColor(img_np, cv2.COLOR_RGB2BGR)

            # OCR Recognize
            results = self.ocr.ocr(img_cv, cls=True)
            
            page_data = {
                "page": i + 1,
                "width": page.rect.width,
                "height": page.rect.height,
                "img_width": pix.w,
                "img_height": pix.h,
                "content": []
            }

            if results and results[0]:
                for line in results[0]:
                    bbox = line[0]  # [[x,y], [x,y], [x,y], [x,y]]
                    text = line[1][0]
                    confidence = line[1][1]
                    
                    # Extract color
                    color_hex = self.get_text_color(img_cv, bbox)
                    
                    # Calculate bounding rect for sizing
                    x_list = [p[0] for p in bbox]
                    y_list = [p[1] for p in bbox]
                    w = max(x_list) - min(x_list)
                    h = max(y_list) - min(y_list)
                    
                    # Estimate font size in PDF points
                    # h is in pixels at DPI, convert back to pts (1/72)
                    # font_size = (h / DPI) * 72
                    # simplified: font_size = h * (72 / DPI)
                    font_size = h * (72.0 / self.dpi)

                    page_data["content"].append({
                        "text": text,
                        "confidence": float(confidence),
                        "bbox_pixels": bbox,
                        # Convert bbox to PDF points
                        "bbox_pts": [ [p[0] * (72.0/self.dpi), p[1] * (72.0/self.dpi)] for p in bbox ],
                        "font_size": round(font_size, 2),
                        "color": color_hex
                    })
            
            all_pages.append(page_data)

        doc.close()
        return all_pages

if __name__ == "__main__":
    input_pdf = "test_origin.pdf"
    output_json = "test_origin_extracted.json"
    
    extractor = PDFOCRExtractor()
    try:
        data = extractor.extract(input_pdf)
        with open(output_json, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        logger.info(f"Success! Extracted data saved to {output_json}")
    except Exception as e:
        logger.error(f"Failed: {e}")
