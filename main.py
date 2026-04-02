import sys
import os
from PySide6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout, 
    QPushButton, QLabel, QFileDialog, QProgressBar, QMessageBox
)
from PySide6.QtCore import Qt, QThread, Signal, Slot
from PySide6.QtGui import QDragEnterEvent, QDropEvent, QIcon, QFont

# 導入核心邏輯
from core import SlideReverseCore

class ConversionThread(QThread):
    """
    非同步處理轉換任務的執行緒
    """
    progress_signal = Signal(int, int, str)
    finished_signal = Signal(bool, str)

    def __init__(self, pdf_path, output_path, parent=None):
        super().__init__(parent)
        self.pdf_path = pdf_path
        self.output_path = output_path
        self.core = SlideReverseCore()

    def run(self):
        try:
            success = self.core.process_pdf(
                self.pdf_path, 
                self.output_path, 
                progress_callback=self.update_progress
            )
            if success:
                self.finished_signal.emit(True, f"轉換成功！已儲存至：\n{self.output_path}")
            else:
                self.finished_signal.emit(False, "轉換失敗，請檢查日誌或檔案格式。")
        except Exception as e:
            self.finished_signal.emit(False, f"發生異常：{str(e)}")

    def update_progress(self, current, total, status_text):
        self.progress_signal.emit(current, total, status_text)

class DropArea(QLabel):
    """
    檔案拖曳區域
    """
    file_dropped = Signal(str)

    def __init__(self, parent=None):
        super().__init__("將 PDF 檔案拖曳至此\n或按下方按鈕選擇", parent)
        self.setAlignment(Qt.AlignCenter)
        self.setAcceptDrops(True)
        self.setMinimumSize(400, 200)
        self.setStyleSheet("""
            QLabel {
                border: 2px dashed #999;
                border-radius: 10px;
                background-color: #f9f9f9;
                color: #666;
                font-size: 16px;
                font-family: 'PingFang SC', 'Helvetica Neue', Arial;
            }
            QLabel:hover {
                background-color: #eee;
                border-color: #007AFF;
            }
        """)

    def dragEnterEvent(self, event: QDragEnterEvent):
        if event.mimeData().hasUrls():
            event.accept()
        else:
            event.ignore()

    def dropEvent(self, event: QDropEvent):
        urls = event.mimeData().urls()
        if urls:
            file_path = urls[0].toLocalFile()
            if file_path.lower().endswith('.pdf'):
                self.file_dropped.emit(file_path)
            else:
                QMessageBox.warning(self, "錯誤", "僅支援 PDF 格式！")

class SlideReverseApp(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("SlideReverse - PDF to Editable PPTX")
        self.resize(500, 450)
        self.init_ui()
        self.pdf_path = ""
        self.output_path = ""

    def init_ui(self):
        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        layout = QVBoxLayout(central_widget)
        layout.setContentsMargins(30, 30, 30, 30)
        layout.setSpacing(20)

        # 標題
        title_label = QLabel("SlideReverse")
        title_label.setStyleSheet("font-size: 24px; font-weight: bold; color: #333;")
        title_label.setAlignment(Qt.AlignCenter)
        layout.addWidget(title_label)

        # 說明
        desc_label = QLabel("將 PDF 簡報轉換為背景乾淨、文字可編輯的 PPTX")
        desc_label.setStyleSheet("color: #888; margin-bottom: 10px;")
        desc_label.setAlignment(Qt.AlignCenter)
        layout.addWidget(desc_label)

        # 拖曳區
        self.drop_area = DropArea()
        self.drop_area.file_dropped.connect(self.set_pdf_path)
        layout.addWidget(self.drop_area)

        # 檔案路徑顯示
        self.path_label = QLabel("未選擇檔案")
        self.path_label.setWordWrap(True)
        self.path_label.setStyleSheet("color: #555; font-size: 13px;")
        layout.addWidget(self.path_label)

        # 按鈕列
        btn_layout = QHBoxLayout()
        self.select_btn = QPushButton("選擇 PDF")
        self.select_btn.clicked.connect(self.select_pdf)
        self.select_btn.setFixedHeight(35)
        
        self.output_btn = QPushButton("選擇輸出目錄")
        self.output_btn.clicked.connect(self.select_output_dir)
        self.output_btn.setFixedHeight(35)
        
        btn_layout.addWidget(self.select_btn)
        btn_layout.addWidget(self.output_btn)
        layout.addLayout(btn_layout)

        # 進度區域
        self.progress_bar = QProgressBar()
        self.progress_bar.setVisible(False)
        self.progress_bar.setFixedHeight(6)
        layout.addWidget(self.progress_bar)

        self.status_label = QLabel("")
        self.status_label.setStyleSheet("color: #007AFF; font-size: 12px;")
        layout.addWidget(self.status_label)

        # 開始按鈕
        self.start_btn = QPushButton("開始轉換")
        self.start_btn.clicked.connect(self.start_conversion)
        self.start_btn.setEnabled(False)
        self.start_btn.setFixedHeight(45)
        self.start_btn.setStyleSheet("""
            QPushButton {
                background-color: #007AFF;
                color: white;
                border-radius: 8px;
                font-weight: bold;
                font-size: 16px;
            }
            QPushButton:disabled {
                background-color: #ccc;
            }
            QPushButton:hover {
                background-color: #0063CC;
            }
        """)
        layout.addWidget(self.start_btn)

    def select_pdf(self):
        file_path, _ = QFileDialog.getOpenFileName(self, "選擇 PDF 檔案", "", "PDF 檔案 (*.pdf)")
        if file_path:
            self.set_pdf_path(file_path)

    def set_pdf_path(self, path):
        self.pdf_path = path
        self.path_label.setText(f"已選擇：{os.path.basename(path)}")
        self.drop_area.setText(f"已讀取：{os.path.basename(path)}")
        self.check_ready()

    def select_output_dir(self):
        dir_path = QFileDialog.getExistingDirectory(self, "選擇輸出目錄")
        if dir_path:
            self.output_path = os.path.join(dir_path, os.path.basename(self.pdf_path).replace(".pdf", ".pptx"))
            self.status_label.setText(f"輸出位置：{os.path.basename(self.output_path)}")
            self.check_ready()

    def check_ready(self):
        if self.pdf_path:
            if not self.output_path:
                # 預設路徑：PDF 同目錄
                self.output_path = self.pdf_path.replace(".pdf", "_Slided.pptx")
                self.status_label.setText(f"輸出位置：{os.path.basename(self.output_path)}")
            self.start_btn.setEnabled(True)

    def start_conversion(self):
        if not self.pdf_path or not self.output_path:
            return

        self.start_btn.setEnabled(False)
        self.drop_area.setEnabled(False)
        self.select_btn.setEnabled(False)
        self.output_btn.setEnabled(False)
        
        self.progress_bar.setVisible(True)
        self.progress_bar.setValue(0)
        
        self.thread = ConversionThread(self.pdf_path, self.output_path)
        self.thread.progress_signal.connect(self.update_ui_progress)
        self.thread.finished_signal.connect(self.on_finished)
        self.thread.start()

    @Slot(int, int, str)
    def update_ui_progress(self, current, total, text):
        self.progress_bar.setMaximum(total)
        self.progress_bar.setValue(current)
        self.status_label.setText(f"{text} ({current}/{total})")

    @Slot(bool, str)
    def on_finished(self, success, message):
        self.start_btn.setEnabled(True)
        self.drop_area.setEnabled(True)
        self.select_btn.setEnabled(True)
        self.output_btn.setEnabled(True)
        self.progress_bar.setVisible(False)
        self.status_label.setText("")

        if success:
            QMessageBox.information(self, "完成", message)
        else:
            QMessageBox.critical(self, "錯誤", message)

if __name__ == "__main__":
    app = QApplication(sys.argv)
    window = SlideReverseApp()
    window.show()
    sys.exit(app.exec())
