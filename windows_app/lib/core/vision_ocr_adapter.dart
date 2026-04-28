import 'dart:typed_data';
import 'dart:convert';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:image/image.dart' as img;
import 'dart:io';
import 'logger.dart';

class VisionOcrAdapter {
  bool _isInitialized = false;
  OrtSession? _detSession;
  OrtSession? _recSession;
  List<String>? _alphabet;

  bool get isInitialized => _isInitialized;

  Future<void> init(String detPath, String recPath, String keysPath) async {
    try {
      AppLogger.d('OCR', 'Initializing OCR Det & Rec sessions from buffer...');
      OrtEnv.instance.init();
      final detBytes = await File(detPath).readAsBytes();
      final recBytes = await File(recPath).readAsBytes();
      
      _detSession = OrtSession.fromBuffer(detBytes, OrtSessionOptions());
      _recSession = OrtSession.fromBuffer(recBytes, OrtSessionOptions());
      
      // 🔑 修复：Windows 默认编码非 UTF-8，必须显式指定，否则中文字符全部乱码
      final keysStr = await File(keysPath).readAsString(encoding: utf8);
      _alphabet = keysStr.split('\n');
      for (int i = 0; i < _alphabet!.length; i++) {
        _alphabet![i] = _alphabet![i].replaceAll('\r', '');
      }
      if (_alphabet!.isNotEmpty && _alphabet!.last.isEmpty) {
        _alphabet!.removeLast();
      }
      _alphabet!.add(" "); // PaddleOCR uses_space_char 默认在末尾加空格
      
      _isInitialized = true;
      AppLogger.d('OCR', 'OCR Engines initialized. Alphabet size: ${_alphabet?.length}');
    } catch (e) {
      AppLogger.e('OCR', 'Failed to initialize OCR: $e');
    }
  }

  Future<Map<String, dynamic>> recognizeText(Uint8List imageBytes, {double threshold = 0.1}) async {
    if (!_isInitialized) return {'nodes': [], 'mask': null};

    final rawImg = img.decodeImage(imageBytes)!;
    final detImg = img.copyResize(rawImg, width: 960, height: 960);
    
    final detInput = _preprocessDet(detImg);
    final detRunOptions = OrtRunOptions();
    final results = await _detSession!.runAsync(detRunOptions, {'x': detInput});
    
    final heatmap = results![0]!.value as List<dynamic>;
    final List<Map<String, dynamic>> finalNodes = [];
    final List<List<int>> boxes = _findBoxes(heatmap[0][0], threshold);

    final maskImg = img.Image(width: rawImg.width, height: rawImg.height);
    img.fill(maskImg, color: img.ColorRgb8(0, 0, 0)); 

    for (var box in boxes) {
      final int minX = box[0];
      final int minY = box[1];
      final int maxX = box[2];
      final int maxY = box[3];

      final double width = (maxX - minX).toDouble();
      final double height = (maxY - minY).toDouble();
      final double area = width * height;
      final double perimeter = (width + height) * 2;
      final double unclipRatio = 2.2;
      final double distance = (area * unclipRatio) / perimeter;
      
      final double scaleX = rawImg.width / 960.0;
      final double scaleY = rawImg.height / 960.0;
      
      final int cropX = ((minX - distance) * scaleX).toInt().clamp(0, rawImg.width - 1);
      final int cropY = ((minY - distance) * scaleY).toInt().clamp(0, rawImg.height - 1);
      final int cropW = (((maxX + distance) - (minX - distance)) * scaleX).toInt().clamp(1, rawImg.width - cropX);
      final int cropH = (((maxY + distance) - (minY - distance)) * scaleY).toInt().clamp(1, rawImg.height - cropY);
      
      final crop = img.copyCrop(rawImg, x: cropX, y: cropY, width: cropW, height: cropH);
      final recInput = _preprocessRec(crop);
      final recResults = await _recSession!.runAsync(detRunOptions, {'x': recInput});
      // 使用 PaddleOCR return_word_box 等价逻辑：解码 CTC 并获取每字符列索引
      final recOutput = _decodeCtcWithCols(recResults![0]!.value);
      final String text = recOutput.$1;
      final List<int> validCols = recOutput.$2; // 每个字符对应的 CTC 有效列索引
      final int totalCols = recOutput.$3;        // CTC 序列总长度
      AppLogger.d('OCR', 'Recognized Box: [$cropX, $cropY, $cropW, $cropH] -> TEXT: "$text" (${validCols.length} chars, $totalCols cols)');
      
      // 修复：只对成功识别到文字的框才绘制 inpaint mask 并加入 nodes
      // 避免 rec 失败的检测框误擦背景却没有文字叠加层覆盖
      if (text.isNotEmpty) {
        // 绘制 inpaint mask（使用膨胀系数 1.6，确保完整覆盖字符含上下留白）
        final int maskX = ((minX - distance) * scaleX).toInt().clamp(0, rawImg.width);
        final int maskY = ((minY - distance) * scaleY).toInt().clamp(0, rawImg.height);
        final int maskW = ((maxX + distance - (minX - distance)) * scaleX).toInt().clamp(1, rawImg.width - maskX);
        final int maskH = ((maxY + distance - (minY - distance)) * scaleY).toInt().clamp(1, rawImg.height - maskY);
        img.fillRect(maskImg, x1: maskX, y1: maskY, x2: maskX + maskW, y2: maskY + maskH, color: img.ColorRgb8(255, 255, 255));

        final double fitDist = (area * 2.2) / perimeter;
        final double fitH = (maxY + fitDist - (minY - fitDist)) / 960.0;
        final textColor = _extractTextColor(crop);

        // 生成单字符 charRects（等价 PaddleOCR word_col_list → 图像 x 坐标映射）
        // valid_col[i] / totalCols → 字符在裁切图中的相对 x 位置
        // 字符宽度 = 下一个字符起始列 - 当前字符起始列（最后字符延伸到行尾）
        final List<List<double>> charRects = [];
        for (int ci = 0; ci < validCols.length; ci++) {
          final double colStart = validCols[ci] / totalCols;
          final double colEnd = (ci + 1 < validCols.length)
              ? validCols[ci + 1] / totalCols
              : 1.0;
          // 映射到原图归一化坐标 [x, y, w, h]
          final double charNormX = cropX / rawImg.width + colStart * (cropW / rawImg.width);
          final double charNormW = (colEnd - colStart) * (cropW / rawImg.width);
          charRects.add([
            charNormX,
            cropY / rawImg.height,
            charNormW,
            cropH / rawImg.height,
          ]);
        }

        finalNodes.add({
          'text': text,
          'rect': [cropX / rawImg.width, cropY / rawImg.height, cropW / rawImg.width, cropH / rawImg.height],
          'charRects': charRects, // 新增：单字符精准坐标列表
          'color': textColor,
          'fittingH': fitH,
          'rawH': (maxY - minY) / 960.0, // 新增：原始文字真实物理高度比例
        });
      } else {
        AppLogger.w('OCR', 'Box [$cropX, $cropY] skipped: rec returned empty text, mask NOT applied.');
      }
      recResults?.forEach((v) => v?.release());
    }
    
    results?.forEach((v) => v?.release());
    final heatmapMaskPng = Uint8List.fromList(img.encodePng(maskImg));
    return {'nodes': finalNodes, 'mask': heatmapMaskPng};
  }

  List<List<int>> _findBoxes(List<dynamic> heatmap, double threshold) {
    final List<List<int>> boxes = [];
    final int rows = heatmap.length;
    final int cols = (heatmap[0] as List).length;
    final visited = List.generate(rows, (_) => Uint8List(cols));

    for (int y = 0; y < rows; y++) {
      final row = heatmap[y] as List;
      for (int x = 0; x < cols; x++) {
        if (row[x] > threshold && visited[y][x] == 0) {
          int minX = x, maxX = x, minY = y, maxY = y;
          final queue = [[x, y]];
          visited[y][x] = 1;
          int head = 0;
          while (head < queue.length) {
            final curr = queue[head++];
            final cx = curr[0], cy = curr[1];
            if (cx < minX) minX = cx; if (cx > maxX) maxX = cx; if (cy < minY) minY = cy; if (cy > maxY) maxY = cy;
            final neighbors = [[cx+1, cy], [cx-1, cy], [cx, cy+1], [cx, cy-1]];
            for (var n in neighbors) {
              final nx = n[0], ny = n[1];
              if (nx >= 0 && nx < cols && ny >= 0 && ny < rows && visited[ny][nx] == 0 && (heatmap[ny] as List)[nx] > threshold) {
                visited[ny][nx] = 1; queue.add([nx, ny]);
              }
            }
          }
          if ((maxX - minX) > 4 && (maxY - minY) > 4) boxes.add([minX, minY, maxX, maxY]);
        }
      }
    }
    return boxes;
  }

  OrtValueTensor _preprocessDet(img.Image image) {
    final floatData = Float32List(1 * 3 * 960 * 960);
    for (int c = 0; c < 3; c++) {
      for (int y = 0; y < 960; y++) {
        for (int x = 0; x < 960; x++) {
          final pixel = image.getPixel(x, y);
          double val = 0.0;
          if (c == 0) val = pixel.r.toDouble();
          if (c == 1) val = pixel.g.toDouble();
          if (c == 2) val = pixel.b.toDouble();
          floatData[c * 960 * 960 + y * 960 + x] = (val / 255.0 - 0.5) / 0.5;
        }
      }
    }
    return OrtValueTensor.createTensorWithDataList(floatData, [1, 3, 960, 960]);
  }

  OrtValueTensor _preprocessRec(img.Image image) {
    final ratio = image.width / image.height;
    final targetW = (48 * ratio).toInt().clamp(48, 1024);
    final resized = img.copyResize(image, height: 48, width: targetW);
    final floatData = Float32List(1 * 3 * 48 * targetW);
    for (int c = 0; c < 3; c++) {
      for (int y = 0; y < 48; y++) {
        for (int x = 0; x < targetW; x++) {
          final pixel = resized.getPixel(x, y);
          double val = 0.0;
          if (c == 0) val = pixel.r.toDouble();
          if (c == 1) val = pixel.g.toDouble();
          if (c == 2) val = pixel.b.toDouble();
          floatData[c * 48 * targetW + y * targetW + x] = (val / 255.0 - 0.5) / 0.5;
        }
      }
    }
    return OrtValueTensor.createTensorWithDataList(floatData, [1, 3, 48, targetW]);
  }

  /// PaddleOCR return_word_box 等价实现
  /// 返回 (text, validCols, totalCols)
  /// - text: 识别文本
  /// - validCols: 每个字符首次出现的 CTC 列索引（等价 Python 的 valid_col[c_i]）
  /// - totalCols: CTC 序列总长度（用于 x 坐标归一化）
  (String, List<int>, int) _decodeCtcWithCols(dynamic output) {
    final List<dynamic> seq = (output as List)[0];
    final int totalCols = seq.length;
    String result = "";
    final List<int> validCols = [];
    int lastIdx = -1;

    for (int t = 0; t < seq.length; t++) {
      final probs = seq[t] as List;
      int maxIdx = 0;
      double maxProb = -1.0;
      for (int j = 0; j < probs.length; j++) {
        final val = probs[j].toDouble();
        if (val > maxProb) { maxProb = val; maxIdx = j; }
      }
      // blank = 0, 去重：只在字符首次出现时（非 blank 且与上一步不同）记录
      if (maxIdx > 0 && maxIdx <= _alphabet!.length && maxIdx != lastIdx) {
        final char = _alphabet![maxIdx - 1];
        if (char.isNotEmpty) {
          result += char;
          validCols.add(t); // 记录该字符对应的 CTC 列索引
        }
      }
      lastIdx = maxIdx;
    }
    return (result, validCols, totalCols);
  }

  int _extractTextColor(img.Image crop) {
    if (crop.width == 0 || crop.height == 0) return 0xFF000000;
    
    // 1. 采样边缘像素估计背景色
    double bgR = 0, bgG = 0, bgB = 0, count = 0;
    for (int x = 0; x < crop.width; x++) {
      for (int y in [0, crop.height - 1]) {
        final pixel = crop.getPixel(x, y);
        bgR += pixel.r.toDouble();
        bgG += pixel.g.toDouble();
        bgB += pixel.b.toDouble();
        count += 1;
      }
    }
    final avgBgR = count > 0 ? bgR / count : 255.0;
    final avgBgG = count > 0 ? bgG / count : 255.0;
    final avgBgB = count > 0 ? bgB / count : 255.0;

    // 2. 寻找与背景对比度最大的像素（文字色）
    double maxDist = -1.0;
    int bestR = 0, bestG = 0, bestB = 0;
    
    for (int x = 0; x < crop.width; x += 2) {
      for (int y = 0; y < crop.height; y += 2) {
        final pixel = crop.getPixel(x, y);
        final r = pixel.r.toDouble();
        final g = pixel.g.toDouble();
        final b = pixel.b.toDouble();
        
        final dist = (r - avgBgR) * (r - avgBgR) + 
                     (g - avgBgG) * (g - avgBgG) + 
                     (b - avgBgB) * (b - avgBgB);
        if (dist > maxDist) {
          maxDist = dist;
          bestR = pixel.r.toInt();
          bestG = pixel.g.toInt();
          bestB = pixel.b.toInt();
        }
      }
    }
    
    return (0xFF << 24) | (bestR << 16) | (bestG << 8) | bestB;
  }
}
