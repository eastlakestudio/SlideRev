import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'logger.dart';
import 'lama_inpainting_engine.dart';
import 'model_manager.dart';

/// 水印去除引擎
/// 职责：根据水印文字模式，在 OCR 节点列表中找出匹配节点，
/// 生成二值遮罩，然后调用 LaMa Inpainting 修复图像。
class WatermarkRemover {
  static const String _tag = 'WatermarkRemover';

  /// 判断单个 OCR 节点是否包含目标水印模式（不区分大小写子串匹配）
  static bool _nodeMatchesPattern(String nodeText, String pattern) {
    if (pattern.isEmpty) return false;
    return nodeText.toLowerCase().contains(pattern.toLowerCase());
  }

  /// 根据 OCR 节点 + 水印模式，生成 512×512 遮罩图像字节
  /// 白色 = 需要修复的区域，黑色 = 保留区域
  static Future<Uint8List> buildMask({
    required List<Map<String, dynamic>> nodes,
    required String pattern,
    int maskSize = 512,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
        recorder, ui.Rect.fromLTWH(0, 0, maskSize.toDouble(), maskSize.toDouble()));

    // 全黑背景
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, maskSize.toDouble(), maskSize.toDouble()),
      ui.Paint()..color = Colors.black,
    );

    final whitePaint = ui.Paint()..color = Colors.white;
    int matchCount = 0;

    for (final node in nodes) {
      final text = (node['text'] as String? ?? '');
      if (!_nodeMatchesPattern(text, pattern)) continue;

      final rect = node['rect'] as List<double>;
      // rect = [x, y, w, h] 归一化坐标
      canvas.drawRect(
        ui.Rect.fromLTWH(
          rect[0] * maskSize,
          rect[1] * maskSize,
          rect[2] * maskSize,
          rect[3] * maskSize,
        ),
        whitePaint,
      );
      matchCount++;
    }

    AppLogger.d(_tag, 'Built mask: $matchCount node(s) matched pattern "$pattern"');

    final picture = recorder.endRecording();
    final image = await picture.toImage(maskSize, maskSize);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// 对单帧图像运行水印去除，返回修复后图像字节
  /// 如果没有节点匹配，直接返回原始图像（不调用 LaMa 节省时间）
  static Future<Uint8List> removeWatermark({
    required Uint8List imageBytes,
    required List<Map<String, dynamic>> nodes,
    required String pattern,
  }) async {
    // 检查是否有匹配的节点
    final hasMatch = nodes.any(
        (n) => _nodeMatchesPattern(n['text'] as String? ?? '', pattern));
    if (!hasMatch) {
      AppLogger.d(_tag, 'No nodes matched "$pattern", skipping LaMa');
      return imageBytes;
    }

    final maskBytes = await buildMask(nodes: nodes, pattern: pattern);

    final modelPath =
        await ModelManager().getLocalModelPath('assets/models/lama_fp32.onnx');
    final lama = LamaInpaintingEngine();
    await lama.init(modelPath);

    try {
      final result = await lama.inpaintImage(imageBytes, maskBytes);
      AppLogger.d(_tag, 'LaMa inpainting complete for pattern "$pattern"');
      return result;
    } finally {
      lama.dispose();
    }
  }

  /// 将修复结果合成回原始尺寸图像
  /// LaMa 输出是 512×512，需要缩放回原图尺寸后 alpha 混合
  static Future<Uint8List> blendBackToOriginalSize({
    required Uint8List originalBytes,
    required Uint8List repairedBytes,
    required Uint8List maskBytes,
  }) async {
    final original = img.decodeImage(originalBytes);
    final repaired = img.decodeImage(repairedBytes);
    final mask = img.decodeImage(maskBytes);

    if (original == null || repaired == null || mask == null) {
      return originalBytes;
    }

    final origW = original.width;
    final origH = original.height;

    // 将修复图缩放至原图尺寸
    final scaledRepaired =
        img.copyResize(repaired, width: origW, height: origH);
    final scaledMask = img.copyResize(mask, width: origW, height: origH);

    // 像素级混合：mask 白色区域使用 repaired，其余保留 original
    final output = img.Image(width: origW, height: origH);
    for (var y = 0; y < origH; y++) {
      for (var x = 0; x < origW; x++) {
        final m = scaledMask.getPixel(x, y);
        if (m.luminanceNormalized > 0.5) {
          output.setPixel(x, y, scaledRepaired.getPixel(x, y));
        } else {
          output.setPixel(x, y, original.getPixel(x, y));
        }
      }
    }

    return Uint8List.fromList(img.encodePng(output));
  }

  /// 完整流程：去除水印并混合回原尺寸
  static Future<Uint8List> removeAndBlend({
    required Uint8List imageBytes,
    required List<Map<String, dynamic>> nodes,
    required String pattern,
  }) async {
    final hasMatch = nodes.any(
        (n) => _nodeMatchesPattern(n['text'] as String? ?? '', pattern));
    if (!hasMatch) {
      AppLogger.d(_tag, 'No nodes matched "$pattern"');
      return imageBytes;
    }

    final maskBytes = await buildMask(nodes: nodes, pattern: pattern);

    final modelPath =
        await ModelManager().getLocalModelPath('assets/models/lama_fp32.onnx');
    final lama = LamaInpaintingEngine();
    await lama.init(modelPath);

    try {
      final repaired512 = await lama.inpaintImage(imageBytes, maskBytes);
      return blendBackToOriginalSize(
        originalBytes: imageBytes,
        repairedBytes: repaired512,
        maskBytes: maskBytes,
      );
    } finally {
      lama.dispose();
    }
  }
}
