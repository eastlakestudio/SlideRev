import 'dart:typed_data';
import 'dart:math' as math;
import 'package:onnxruntime/onnxruntime.dart';
import 'package:image/image.dart' as img;
import 'dart:io';
import 'package:path/path.dart' as p;
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
      
      final keysStr = await File(keysPath).readAsString();
      _alphabet = keysStr.split('\n');
      
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
      final double distance = (area * 1.6) / perimeter;
      
      final double scaleX = rawImg.width / 960.0;
      final double scaleY = rawImg.height / 960.0;
      
      final int maskX = ((minX - distance) * scaleX).toInt().clamp(0, rawImg.width);
      final int maskY = ((minY - distance) * scaleY).toInt().clamp(0, rawImg.height);
      final int maskW = ((maxX + distance - (minX - distance)) * scaleX).toInt().clamp(1, rawImg.width - maskX);
      final int maskH = ((maxY + distance - (minY - distance)) * scaleY).toInt().clamp(1, rawImg.height - maskY);

      img.fillRect(maskImg, x1: maskX, y1: maskY, x2: maskX + maskW, y2: maskY + maskH, color: img.ColorRgb8(255, 255, 255));

      final cropX = (minX * scaleX).toInt().clamp(0, rawImg.width - 1);
      final cropY = (minY * scaleY).toInt().clamp(0, rawImg.height - 1);
      final cropW = (width * scaleX).toInt().clamp(1, rawImg.width - cropX);
      final cropH = (height * scaleY).toInt().clamp(1, rawImg.height - cropY);
      
      final crop = img.copyCrop(rawImg, x: cropX, y: cropY, width: cropW, height: cropH);
      final recInput = _preprocessRec(crop);
      final recResults = await _recSession!.runAsync(detRunOptions, {'x': recInput});
      final text = _decodeCtc(recResults![0]!.value);
      AppLogger.d('OCR', 'Recognized Box: [$cropX, $cropY, $cropW, $cropH] -> TEXT: "$text"');
      
      if (text.isNotEmpty) {
        final double fitDist = (area * 1.2) / perimeter;
        final double fitH = (maxY + fitDist - (minY - fitDist)) / 960.0;
        final textColor = _extractTextColor(crop);
        finalNodes.add({
          'text': text,
          'rect': [cropX / rawImg.width, cropY / rawImg.height, cropW / rawImg.width, cropH / rawImg.height],
          'color': textColor,
          'fittingH': fitH,
        });
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

  String _decodeCtc(dynamic output) {
    final List<dynamic> seq = (output as List)[0];
    String result = "";
    int lastIdx = -1;
    for (var probList in seq) {
      int maxIdx = 0;
      double maxProb = -1.0;
      final probs = probList as List;
      for (int j = 0; j < probs.length; j++) {
        final val = probs[j].toDouble();
        if (val > maxProb) { maxProb = val; maxIdx = j; }
      }
      if (maxIdx > 0 && maxIdx <= _alphabet!.length && maxIdx != lastIdx) result += _alphabet![maxIdx - 1].trim();
      lastIdx = maxIdx;
    }
    return result;
  }

  int _extractTextColor(img.Image crop) {
    int r = 0, g = 0, b = 0, count = 0;
    for (int y = crop.height ~/ 4; y < crop.height * 3 ~/ 4; y++) {
      for (int x = crop.width ~/ 4; x < crop.width * 3 ~/ 4; x++) {
        final pixel = crop.getPixel(x, y);
        r += pixel.r.toInt(); g += pixel.g.toInt(); b += pixel.b.toInt();
        count++;
      }
    }
    if (count == 0) return 0xFF000000;
    return (0xFF << 24) | ((r ~/ count) << 16) | ((g ~/ count) << 8) | (b ~/ count);
  }
}
