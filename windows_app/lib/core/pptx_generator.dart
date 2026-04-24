import 'package:archive/archive_io.dart';
import 'package:xml/xml.dart';

class PptxGenerator {
  /// 创建 PPTX
  Future<void> createPptx(String outputPath, List<Map<String, dynamic>> slideDataList) async {
    // 1. 解压一个 Empty.pptx 模板 (或在内存中构造)
    // 2. 解析 slide.xml
    // 3. 将 OCR 识别的文字节点注入到 slide.xml
    // 4. 将背景图片替换
    // 5. 重新打包为 zip (pptx)
    

    
    final archive = Archive();
    
    // 构造一些基础的 XML
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8" standalone="yes"');
    builder.element('p:sld', nest: () {
      builder.attribute('xmlns:a', 'http://schemas.openxmlformats.org/drawingml/2006/main');
      builder.attribute('xmlns:p', 'http://schemas.openxmlformats.org/presentationml/2006/main');
      builder.element('p:cSld', nest: () {
        builder.element('p:spTree', nest: () {
          // 在这里插入文本框
        });
      });
    });
    
    final slideXmlStr = builder.buildDocument().toXmlString();
    
    // 将文件添加到压缩包
    archive.addFile(ArchiveFile('ppt/slides/slide1.xml', slideXmlStr.length, slideXmlStr.codeUnits));
    
    // 写入本地
    final encoder = ZipFileEncoder();
    encoder.create(outputPath);

    for (final file in archive) {
      if (file.isFile) {
         // 注意：实际应用中需要借助 Dart IO 处理真正的写文件逻辑
      }
    }
    encoder.close();
  }
}
