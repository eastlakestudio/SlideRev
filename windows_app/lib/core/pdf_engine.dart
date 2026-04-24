import 'dart:io';
import 'package:pdfx/pdfx.dart';

class PdfEngine {
  /// 加载并渲染 PDF 文件的某一页为图片
  Future<PdfPageImage?> renderPageToImage(String pdfPath, int pageNumber) async {
    final document = await PdfDocument.openFile(pdfPath);
    final page = await document.getPage(pageNumber);
    // 渲染页面，这里以较高分辨率渲染
    final pageImage = await page.render(
      width: page.width * 2,
      height: page.height * 2,
      format: PdfPageImageFormat.png,
    );
    await page.close();
    await document.close();
    return pageImage;
  }
}
