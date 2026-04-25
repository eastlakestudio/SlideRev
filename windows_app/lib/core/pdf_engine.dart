import 'package:pdfx/pdfx.dart';

class PdfEngine {
  Future<int> getPageCount(String filePath) async {
    final document = await PdfDocument.openFile(filePath);
    final count = document.pagesCount;
    await document.close();
    return count;
  }

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
