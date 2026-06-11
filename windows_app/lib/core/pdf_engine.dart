import 'dart:io';
import 'package:pdfx/pdfx.dart';

class PdfEngine {
  /// 获取 PDF 文档的总页数
  Future<int> getPageCount(String pdfPath) async {
    final bytes = await File(pdfPath).readAsBytes();
    final document = await PdfDocument.openData(bytes);
    final count = document.pagesCount;
    await document.close();
    return count;
  }

  /// 加载并渲染 PDF 文件的某一页为图片
  Future<PdfPageImage?> renderPageToImage(
    String pdfPath,
    int pageNumber,
  ) async {
    // 使用 File 方式读取字节流，绕过 native 层的路径编码问题
    final bytes = await File(pdfPath).readAsBytes();
    final document = await PdfDocument.openData(bytes);
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
