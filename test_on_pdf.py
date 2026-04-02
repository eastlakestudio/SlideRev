import os
from core import SlideReverseCore

def test_specific_pdf():
    pdf_file = "Petrochemical_IT_Architecture_Blueprint_(2).pdf"
    output_file = "Petrochemical_Architecture_Test.pptx"
    
    if not os.path.exists(pdf_file):
        print(f"❌ 找不到文件: {pdf_file}")
        return

    print(f"🚀 開始測試文件: {pdf_file}")
    core = SlideReverseCore(lang='ch') # 針對中文專案
    
    def progress(curr, total, msg):
        print(f"⏳ [{curr}/{total}] {msg}")

    success = core.process_pdf(pdf_file, output_file, progress_callback=progress)
    
    if success:
        print(f"✅ 測試完成！生成文件於: {os.path.abspath(output_file)}")
    else:
        print("❌ 測試過程出錯，請檢查終端日誌。")

if __name__ == "__main__":
    test_specific_pdf()
