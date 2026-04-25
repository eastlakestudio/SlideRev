import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'dart:io';
import 'dart:convert';

class PptxPageData {
  final Uint8List backgroundImage;
  final List<Map<String, dynamic>> nodes;
  final double width;
  final double height;

  PptxPageData({
    required this.backgroundImage,
    required this.nodes,
    required this.width,
    required this.height,
  });
}

class PptxGenerator {
  static const int EMU_PER_PT = 12700;

  /// 创建与 Mac 版对等的 PPTX 文件
  Future<void> createPptx(String outputPath, List<PptxPageData> pages) async {
    final archive = Archive();

    // 1. 基础骨架
    final contentTypes = utf8.encode(_getContentTypesXml(pages.length));
    archive.addFile(ArchiveFile('[Content_Types].xml', contentTypes.length, contentTypes));
    
    final rels = utf8.encode(_getRelsXml());
    archive.addFile(ArchiveFile('_rels/.rels', rels.length, rels));
    
    // 计算全局最大尺寸 (与 Mac 版逻辑对齐)
    double maxW = 720.0;
    double maxH = 540.0;
    for (var p in pages) {
      if (p.width > maxW) maxW = p.width;
      if (p.height > maxH) maxH = p.height;
    }
    final cxEMU = (maxW * EMU_PER_PT).toInt();
    final cyEMU = (maxH * EMU_PER_PT).toInt();

    final presXml = utf8.encode(_getPresentationXml(pages.length, cxEMU, cyEMU));
    archive.addFile(ArchiveFile('ppt/presentation.xml', presXml.length, presXml));
    
    final presRels = utf8.encode(_getPresentationRelsXml(pages.length));
    archive.addFile(ArchiveFile('ppt/_rels/presentation.xml.rels', presRels.length, presRels));

    // 2. 遍历生成每一页内容
    for (int i = 0; i < pages.length; i++) {
      final pageIndex = i + 1;
      final page = pages[i];
      
      // A. 背景图片
      final imgName = 'image_p$pageIndex.png';
      archive.addFile(ArchiveFile('ppt/media/$imgName', page.backgroundImage.length, page.backgroundImage));

      // B. Slide 关系 (指向背景图)
      final slideRels = utf8.encode(_getSlideRelsXml(imgName));
      archive.addFile(ArchiveFile('ppt/slides/_rels/slide$pageIndex.xml.rels', slideRels.length, slideRels));
      
      // C. Slide 内容
      final slideXml = utf8.encode(_getSlideXml(page, maxW, maxH));
      archive.addFile(ArchiveFile('ppt/slides/slide$pageIndex.xml', slideXml.length, slideXml));
    }

    final zipEncoder = ZipEncoder();
    final zipBytes = zipEncoder.encode(archive);
    if (zipBytes != null) {
      await File(outputPath).writeAsBytes(zipBytes);
    }
  }

  String _getSlideXml(PptxPageData page, double canvasW, double canvasH) {
    // 居中适配缩放逻辑 (与 Mac 版 V9.2 对齐)
    final fitScale = (canvasW / page.width < canvasH / page.height) 
        ? canvasW / page.width 
        : canvasH / page.height;
    
    final offX = (canvasW - page.width * fitScale) / 2.0;
    final offY = (canvasH - page.height * fitScale) / 2.0;

    final offX_EMU = (offX * EMU_PER_PT).toInt();
    final offY_EMU = (offY * EMU_PER_PT).toInt();
    final extX_EMU = (page.width * fitScale * EMU_PER_PT).toInt();
    final extY_EMU = (page.height * fitScale * EMU_PER_PT).toInt();

    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8" standalone="yes"');
    builder.element('p:sld', nest: () {
      builder.attribute('xmlns:a', 'http://schemas.openxmlformats.org/drawingml/2006/main');
      builder.attribute('xmlns:r', 'http://schemas.openxmlformats.org/officeDocument/2006/relationships');
      builder.attribute('xmlns:p', 'http://schemas.openxmlformats.org/presentationml/2006/main');
      builder.element('p:cSld', nest: () {
        builder.element('p:spTree', nest: () {
          // 基础容器
          builder.element('p:nvGrpSpPr', nest: () {
            builder.element('p:cNvPr', nest: () { builder.attribute('id', '1'); builder.attribute('name', ''); });
            builder.element('p:cNvGrpSpPr', nest: () {});
            builder.element('p:nvPr', nest: () {});
          });
          builder.element('p:grpSpPr', nest: () {
            builder.element('a:xfrm', nest: () {
              builder.element('a:off', nest: () { builder.attribute('x', '0'); builder.attribute('y', '0'); });
              builder.element('a:ext', nest: () { builder.attribute('cx', '0'); builder.attribute('cy', '0'); });
            });
          });

          // 1. 背景图层 (p:pic)
          builder.element('p:pic', nest: () {
            builder.element('p:nvPicPr', nest: () {
              builder.element('p:cNvPr', nest: () { builder.attribute('id', '2'); builder.attribute('name', ''); });
              builder.element('p:cNvPicPr', nest: () {});
              builder.element('p:nvPr', nest: () {});
            });
            builder.element('p:blipFill', nest: () {
              builder.element('a:blip', nest: () { builder.attribute('r:embed', 'rId99'); });
              builder.element('a:stretch', nest: () { builder.element('a:fillRect', nest: () {}); });
            });
            builder.element('p:spPr', nest: () {
              builder.element('a:xfrm', nest: () {
                builder.element('a:off', nest: () { builder.attribute('x', offX_EMU); builder.attribute('y', offY_EMU); });
                builder.element('a:ext', nest: () { builder.attribute('cx', extX_EMU); builder.attribute('cy', extY_EMU); });
              });
              builder.element('a:prstGeom', nest: () { builder.attribute('prst', 'rect'); builder.element('a:avLst', nest: () {}); });
            });
          });

          // 2. 文本框图层 (p:sp)
          for (int i = 0; i < page.nodes.length; i++) {
            final node = page.nodes[i];
            final rect = node['rect'] as List<double>;
            final text = node['text'] as String;
            
            // 样式参数 (目前使用默认值，后续可从 OCR 获取)
            final fontSize = (node['fontSize'] ?? 14.0) as double;
            final isBold = (node['isBold'] ?? false) as bool;
            final colorHex = (node['color'] ?? '000000') as String;

            _addTextShape(builder, i + 100, text, rect, page.width, page.height, fitScale, offX, offY, fontSize, isBold, colorHex);
          }
        });
      });
    });
    return builder.buildDocument().toXmlString();
  }

  void _addTextShape(XmlBuilder builder, int id, String text, List<double> rect, double pw, double ph, double fitScale, double offX, double offY, double fontSize, bool isBold, String colorHex) {
    final xPt = offX + (rect[0] * pw * fitScale);
    final yPt = offY + (rect[1] * ph * fitScale);
    final wPt = rect[2] * pw * fitScale;
    final hPt = rect[3] * ph * fitScale;

    final xEMU = (xPt * EMU_PER_PT).toInt();
    final yEMU = (yPt * EMU_PER_PT).toInt();
    final wEMU = (wPt * EMU_PER_PT).toInt();
    final hEMU = (hPt * EMU_PER_PT).toInt();

    // PPTX 字号单位是 1/100 pt
    final sz = (fontSize * 100).toInt();
    final lines = text.split('\n');

    builder.element('p:sp', nest: () {
      builder.element('p:nvSpPr', nest: () {
        builder.element('p:cNvPr', nest: () { builder.attribute('id', id); builder.attribute('name', 'TextBox $id'); });
        builder.element('p:cNvSpPr', nest: () { builder.attribute('txBox', '1'); });
        builder.element('p:nvPr', nest: () {});
      });
      builder.element('p:spPr', nest: () {
        builder.element('a:xfrm', nest: () {
          builder.element('a:off', nest: () { builder.attribute('x', xEMU); builder.attribute('y', yEMU); });
          builder.element('a:ext', nest: () { builder.attribute('cx', wEMU); builder.attribute('cy', hEMU); });
        });
        builder.element('a:prstGeom', nest: () { builder.attribute('prst', 'rect'); builder.element('a:avLst', nest: () {}); });
      });
      builder.element('p:txBody', nest: () {
        builder.element('a:bodyPr', nest: () { builder.attribute('anchor', 'ctr'); builder.attribute('wrap', 'none'); builder.element('a:spAutoFit', nest: () {}); });
        builder.element('a:lstStyle', nest: () {});
        
        for (var line in lines) {
          builder.element('a:p', nest: () {
            builder.element('a:pPr', nest: () { builder.attribute('algn', 'ctr'); });
            builder.element('a:r', nest: () {
              builder.element('a:rPr', nest: () {
                builder.attribute('lang', 'en-US');
                builder.attribute('sz', sz);
                builder.attribute('b', isBold ? '1' : '0');
                builder.element('a:solidFill', nest: () { builder.element('a:srgbClr', nest: () { builder.attribute('val', colorHex); }); });
                builder.element('a:latin', nest: () { builder.attribute('typeface', 'Arial'); });
              });
              builder.element('a:t', nest: () { builder.text(line); });
            });
          });
        }
      });
    });
  }

  // 元数据修补逻辑 (Iron Triangle)
  String _getContentTypesXml(int count) {
    var xml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">';
    xml += '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/>';
    xml += '<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>';
    for (int i = 1; i <= count; i++) {
      xml += '<Override PartName="/ppt/slides/slide$i.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>';
    }
    xml += '</Types>';
    return xml;
  }

  String _getRelsXml() => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/></Relationships>';

  String _getPresentationXml(int count, int cx, int cy) {
    var xml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">';
    xml += '<p:sldIdLst>';
    for (int i = 1; i <= count; i++) {
      xml += '<p:sldId id="${255 + i}" r:id="rId${100 + i}"/>';
    }
    xml += '</p:sldIdLst>';
    xml += '<p:sldSz cx="$cx" cy="$cy"/><p:notesSz cx="6858000" cy="9144000"/></p:presentation>';
    return xml;
  }

  String _getPresentationRelsXml(int count) {
    var xml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">';
    for (int i = 1; i <= count; i++) {
      xml += '<Relationship Id="rId${100 + i}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide$i.xml"/>';
    }
    xml += '</Relationships>';
    return xml;
  }

  String _getSlideRelsXml(String imgName) => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId99" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/$imgName"/></Relationships>';
}
