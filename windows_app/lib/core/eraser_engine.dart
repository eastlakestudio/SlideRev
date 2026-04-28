import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'logger.dart';
import 'lama_inpainting_engine.dart';
import 'model_manager.dart';

/// 橡皮擦引擎
///
/// 职责：
/// 1. 积累笔触 patch（归一化矩形列表）
/// 2. commitStroke() 时将笔触绘制成遮罩，调用 LaMa 修复指定区域，
///    并将修复结果混合回原始分辨率图像
class EraserEngine {
  static const String _tag = 'EraserEngine';
  static const int _maskSize = 512;

  // 当前笔触未提交的 patch 列表，格式：[x, y, w, h] 归一化
  final List<List<double>> _pendingPatches = [];

  // 已提交但未清空的历史 patch（合并 stroke 时用）
  final List<List<double>> _committedPatches = [];

  bool get hasPendingPatches => _pendingPatches.isNotEmpty;
  bool get hasAnyPatches =>
      _pendingPatches.isNotEmpty || _committedPatches.isNotEmpty;

  /// 添加一次笔触 patch（鼠标拖动时逐帧调用）
  /// [rect] 格式：[normX, normY, normW, normH]
  void addPatch(List<double> rect) {
    _pendingPatches.add(rect);
  }

  /// 清空当前笔触（单次 stroke 结束时不 commit，仅视觉取消）
  void cancelStroke() {
    _pendingPatches.clear();
  }

  /// 将当前 pending patches 移入 committed 列表（准备提交 LaMa）
  void finalizePendingPatches() {
    _committedPatches.addAll(_pendingPatches);
    _pendingPatches.clear();
    AppLogger.d(_tag, 'Finalized ${_committedPatches.length} total patches');
  }

  /// 获取所有 pending patch 用于实时遮罩预览
  List<List<double>> get allPendingPatches => List.unmodifiable(_pendingPatches);

  /// 获取所有 committed patch（包括当次笔触之前提交的）
  List<List<double>> get allPatches =>
      [..._committedPatches, ..._pendingPatches];

  /// 生成遮罩图像字节（白色 = 修复区域）
  Future<Uint8List> buildMask() async {
    final patches = allPatches;
    final size = _maskSize.toDouble();

    final recorder = ui.PictureRecorder();
    final canvas =
        ui.Canvas(recorder, ui.Rect.fromLTWH(0, 0, size, size));
    canvas.drawRect(
        ui.Rect.fromLTWH(0, 0, size, size), ui.Paint()..color = Colors.black);

    final whitePaint = ui.Paint()..color = Colors.white;
    for (final p in patches) {
      canvas.drawRect(
        ui.Rect.fromLTWH(p[0] * size, p[1] * size, p[2] * size, p[3] * size),
        whitePaint,
      );
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(_maskSize, _maskSize);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// 提交所有 patch 并运行 LaMa 修复
  /// 返回合并回原始分辨率的修复图像
  Future<Uint8List> commitStroke(Uint8List imageBytes) async {
    if (!hasAnyPatches) return imageBytes;

    // 将 pending 移入 committed
    finalizePendingPatches();

    AppLogger.d(_tag,
        'Committing stroke with ${_committedPatches.length} patches to LaMa...');

    final maskBytes = await buildMask();

    final modelPath =
        await ModelManager().getLocalModelPath('assets/models/lama_fp32.onnx');
    final lama = LamaInpaintingEngine();
    await lama.init(modelPath);

    try {
      final repaired512 = await lama.inpaint(imageBytes, maskBytes);
      if (repaired512 == null) throw Exception("Inpainting failed");
      final result = await _blendBack(
        originalBytes: imageBytes,
        repairedBytes: repaired512,
        maskBytes: maskBytes,
      );
      // 提交成功后清空 committed patches
      _committedPatches.clear();
      return result;
    } finally {
      // Engine handles its own resources
    }
  }

  /// 将 512×512 修复结果混合回原图分辨率
  Future<Uint8List> _blendBack({
    required Uint8List originalBytes,
    required Uint8List repairedBytes,
    required Uint8List maskBytes,
  }) async {
    final original = img.decodeImage(originalBytes);
    final repaired = img.decodeImage(repairedBytes);
    final mask = img.decodeImage(maskBytes);

    if (original == null || repaired == null || mask == null) {
      AppLogger.w(_tag, 'blendBack: failed to decode image/mask');
      return originalBytes;
    }

    final origW = original.width;
    final origH = original.height;

    final scaledRepaired =
        img.copyResize(repaired, width: origW, height: origH);
    final scaledMask = img.copyResize(mask, width: origW, height: origH);

    final output = img.Image(width: origW, height: origH);
    for (var y = 0; y < origH; y++) {
      for (var x = 0; x < origW; x++) {
        final m = scaledMask.getPixel(x, y);
        output.setPixel(
          x,
          y,
          m.luminanceNormalized > 0.5
              ? scaledRepaired.getPixel(x, y)
              : original.getPixel(x, y),
        );
      }
    }

    AppLogger.d(_tag, 'blendBack complete');
    return Uint8List.fromList(img.encodePng(output));
  }

  /// 重置所有状态
  void reset() {
    _pendingPatches.clear();
    _committedPatches.clear();
  }
}
