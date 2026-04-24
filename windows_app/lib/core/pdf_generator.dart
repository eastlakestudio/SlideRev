import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class PdfGenerator {
  /// 将处理后的图片和文本导出为 PDF
  Future<void> createPdf(String outputPath, Uint8List imageBytes, List<Map<String, dynamic>> nodes) async {
    final pdf = pw.Document();
    final image = pw.MemoryImage(imageBytes);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.undefined, // 自动适配图片比例
        build: (pw.Context context) {
          return pw.Stack(
            children: [
              pw.Image(image),
              // 在图片上方覆盖 OCR 文本层 (可选，为了保持搜索能力)
              ...nodes.map((node) {
                final rect = node['rect'] as List<double>;
                return pw.Positioned(
                  left: rect[0] * 500, // 这里的 500 是模拟比例，实际应取页面宽度
                  top: rect[1] * 350,
                  child: pw.Opacity(
                    opacity: 0.0, // 透明文字层，仅用于搜索
                    child: pw.Text(node['text']),
                  ),
                );
              }).toList(),
            ],
          );
        },
      ),
    );

    final file = File(outputPath);
    await file.writeAsBytes(await pdf.save());
  }
}
