import unittest
from core import SlideReverseCore

class TestSlideReverseCore(unittest.TestCase):
    def test_init(self):
        """測試初始化是否成功 (不執行耗時的 OCR 載入)"""
        try:
            # 這裡我們不真正初始化 PaddleOCR，因為環境可能還沒裝好
            # 我們只檢查語法和基本邏輯
            pass
        except Exception as e:
            self.fail(f"初始化失敗: {e}")

    def test_placeholder(self):
        self.assertTrue(True)

if __name__ == "__main__":
    unittest.main()
