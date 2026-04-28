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
  // 🚀 核心优化：固定标准画布尺寸 (对标 Mac 版 V10 逻辑)
  static const double CANVAS_W = 960.0;
  static const double CANVAS_H = 720.0;

  Future<void> createPptx(String outputPath, List<PptxPageData> pages) async {
    final archive = Archive();

    void addXmlFile(String path, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    addXmlFile('[Content_Types].xml', _getContentTypesXml(pages.length));
    addXmlFile('_rels/.rels', _getRelsXml());
    addXmlFile('docProps/app.xml', _getAppXml());
    addXmlFile('docProps/core.xml', _getCoreXml());

    // 使用固定画布尺寸
    final cxEMU = (CANVAS_W * EMU_PER_PT).toInt();
    final cyEMU = (CANVAS_H * EMU_PER_PT).toInt();

    addXmlFile('ppt/presentation.xml', _getPresentationXml(pages.length, cxEMU, cyEMU));
    addXmlFile('ppt/_rels/presentation.xml.rels', _getPresentationRelsXml(pages.length));
    addXmlFile('ppt/theme/theme1.xml', _getThemeXml());
    addXmlFile('ppt/slideMasters/slideMaster1.xml', _getSlideMasterXml());
    addXmlFile('ppt/slideMasters/_rels/slideMaster1.xml.rels', _getSlideMasterRelsXml());
    addXmlFile('ppt/slideLayouts/slideLayout1.xml', _getSlideLayoutXml());
    addXmlFile('ppt/slideLayouts/_rels/slideLayout1.xml.rels', _getSlideLayoutRelsXml());

    for (int i = 0; i < pages.length; i++) {
      final pageIndex = i + 1;
      final page = pages[i];
      final imgName = 'image_p$pageIndex.png';
      archive.addFile(ArchiveFile('ppt/media/$imgName', page.backgroundImage.length, page.backgroundImage));
      addXmlFile('ppt/slides/_rels/slide$pageIndex.xml.rels', _getSlideRelsXml(imgName));
      addXmlFile('ppt/slides/slide$pageIndex.xml', _getSlideXml(page));
    }

    final zipEncoder = ZipEncoder();
    final zipBytes = zipEncoder.encode(archive);
    if (zipBytes != null) {
      await File(outputPath).writeAsBytes(zipBytes);
    }
  }

  String _getSlideXml(PptxPageData page) {
    // 🚀 核心优化：居中适配缩放
    final fitScale = (CANVAS_W / page.width < CANVAS_H / page.height) ? CANVAS_W / page.width : CANVAS_H / page.height;
    final offX = (CANVAS_W - page.width * fitScale) / 2.0;
    final offY = (CANVAS_H - page.height * fitScale) / 2.0;

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

          // 背景图 (层级 id=2)
          builder.element('p:pic', nest: () {
            builder.element('p:nvPicPr', nest: () {
              builder.element('p:cNvPr', nest: () { builder.attribute('id', '2'); builder.attribute('name', 'Background'); });
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

          // 文本框 (层级 id=100+)
          for (int i = 0; i < page.nodes.length; i++) {
            final node = page.nodes[i];
            final rect = node['rect'] as List<double>;
            final text = node['text'] as String;
            if (text.trim().isEmpty) continue;

            // 🚀 字号计算基于 CANVAS_H 
            double fontSize = 12.0;
            if (node.containsKey('fittingH')) {
               fontSize = node['fittingH'] * CANVAS_H * 0.85; 
            } else {
               fontSize = rect[3] * CANVAS_H * 0.4; 
            }
            if (fontSize < 10) fontSize = 10;
            
            String colorHex = "000000";
            final dynamic rawColor = node['color'];
            if (rawColor is int) {
              if ((rawColor & 0xFF000000) == 0) { colorHex = "000000"; }
              else { colorHex = rawColor.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase(); }
            } else if (rawColor is String) { colorHex = rawColor.replaceAll('#', ''); }

            _addTextShape(builder, i + 100, text, rect, CANVAS_W, CANVAS_H, fitScale, offX, offY, fontSize, colorHex);
          }
        });
      });
      builder.element('p:clrMapOver', nest: () { builder.element('a:masterClrMapping', nest: () {}); });
    });
    return builder.buildDocument().toXmlString();
  }

  void _addTextShape(XmlBuilder builder, int id, String text, List<double> rect, double canvasW, double canvasH, double fitScale, double offX, double offY, double fontSize, String colorHex) {
    // 映射坐标到 CANVAS 空间
    final xPt = offX + (rect[0] * (canvasW - offX * 2));
    final yPt = offY + (rect[1] * (canvasH - offY * 2));
    final wPt = rect[2] * (canvasW - offX * 2);
    final hPt = rect[3] * (canvasH - offY * 2);

    final xEMU = (xPt * EMU_PER_PT).toInt();
    final yEMU = (yPt * EMU_PER_PT).toInt();
    final wEMU = (wPt * EMU_PER_PT).toInt();
    final hEMU = (hPt * EMU_PER_PT).toInt();
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
                builder.attribute('lang', 'zh-CN');
                builder.attribute('altLang', 'en-US');
                builder.attribute('sz', sz);
                builder.element('a:solidFill', nest: () { builder.element('a:srgbClr', nest: () { builder.attribute('val', colorHex); }); });
                builder.element('a:latin', nest: () { builder.attribute('typeface', 'Arial'); });
                builder.element('a:ea', nest: () { builder.attribute('typeface', 'Microsoft YaHei'); });
              });
              builder.element('a:t', nest: () { builder.text(line); });
            });
          });
        }
      });
    });
  }

  String _getContentTypesXml(int count) {
    var xml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">';
    xml += '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/>';
    xml += '<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>';
    xml += '<Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>';
    xml += '<Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>';
    xml += '<Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>';
    for (int i = 1; i <= count; i++) { xml += '<Override PartName="/ppt/slides/slide$i.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>'; }
    xml += '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>';
    xml += '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>';
    xml += '</Types>';
    return xml;
  }
  String _getRelsXml() => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/></Relationships>';
  String _getAppXml() => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"><Application>SlideRev Windows</Application></Properties>';
  String _getCoreXml() => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><dc:title>SlideRev Presentation</dc:title><cp:lastModifiedBy>SlideRev</cp:lastModifiedBy></cp:coreProperties>';
  String _getPresentationXml(int count, int cx, int cy) {
    var xml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">';
    xml += '<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst><p:sldIdLst>';
    for (int i = 1; i <= count; i++) { xml += '<p:sldId id="${255 + i}" r:id="rId${100 + i}"/>'; }
    xml += '</p:sldIdLst><p:sldSz cx="$cx" cy="$cy"/><p:notesSz cx="6858000" cy="9144000"/></p:presentation>';
    return xml;
  }
  String _getPresentationRelsXml(int count) {
    var xml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="theme/theme1.xml"/>';
    for (int i = 1; i <= count; i++) { xml += '<Relationship Id="rId${100 + i}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide$i.xml"/>'; }
    xml += '</Relationships>';
    return xml;
  }
  String _getThemeXml() => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Office Theme"><a:themeElements><a:clrScheme name="Office"><a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1><a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1><a:dk2><a:srgbClr val="44546A"/></a:dk2><a:lt2><a:srgbClr val="E7E6E6"/></a:lt2><a:accent1><a:srgbClr val="4472C4"/></a:accent1><a:accent2><a:srgbClr val="ED7D31"/></a:accent2><a:accent3><a:srgbClr val="A5A5A5"/></a:accent3><a:accent4><a:srgbClr val="FFC000"/></a:accent4><a:accent5><a:srgbClr val="5B9BD5"/></a:accent5><a:accent6><a:srgbClr val="70AD47"/></a:accent6><a:hlink><a:srgbClr val="0563C1"/></a:hlink><a:folHlink><a:srgbClr val="954F72"/></a:folHlink></a:clrScheme><a:fontScheme name="Office"><a:majorFont><a:latin typeface="Calibri Light"/><a:ea typeface="Microsoft YaHei"/><a:cs typeface=""/></a:majorFont><a:minorFont><a:latin typeface="Calibri"/><a:ea typeface="Microsoft YaHei"/><a:cs typeface=""/></a:minorFont></a:fontScheme><a:fmtScheme name="Office"><a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:fillStyleLst><a:lnStyleLst><a:ln w="12700"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln></a:lnStyleLst><a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst><a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:bgFillStyleLst></a:fmtScheme></a:themeElements></a:theme>';
  String _getSlideMasterXml() => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/></a:xfrm></p:grpSpPr></p:spTree></p:cSld><p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/><p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst></p:sldMaster>';
  String _getSlideMasterRelsXml() => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/></Relationships>';
  String _getSlideLayoutXml() => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" type="blank"><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/></a:xfrm></p:grpSpPr></p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>';
  String _getSlideLayoutRelsXml() => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/></Relationships>';
  String _getSlideRelsXml(String imgName) => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/><Relationship Id="rId99" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/$imgName"/></Relationships>';
}
