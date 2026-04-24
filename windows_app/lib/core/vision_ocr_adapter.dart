import 'dart:io';
import 'dart:typed_data';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:image/image.dart' as img;

class VisionOcrAdapter {
  OrtSession? _session;

  Future<void> init(String modelPath) async {
    OrtEnv.instance.init();
    final sessionOptions = OrtSessionOptions();
    _session = OrtSession.fromFile(File(modelPath), sessionOptions);
  }

  Future<List<Map<String, dynamic>>> recognizeText(Uint8List imageBytes) async {
    if (_session == null) throw Exception("OCR Session not initialized");

    // 1. 图像解码与预处理
    final originalImage = img.decodeImage(imageBytes);
    if (originalImage == null) return [];

    // Resize 为模型典型输入尺寸 (例如 640x640)
    final resizedImage = img.copyResize(originalImage, width: 640, height: 640);
    
    // 2. 转换为 Float32 列表 (RGB 顺序, 归一化)
    final float32List = Float32List(1 * 3 * 640 * 640);
    int bufferIndex = 0;
    
    // CHW 顺序 (Channel, Height, Width)
    for (var c = 0; c < 3; c++) {
      for (var y = 0; y < 640; y++) {
        for (var x = 0; x < 640; x++) {
          final pixel = resizedImage.getPixel(x, y);
          double val = 0;
          if (c == 0) val = pixel.r.toDouble();
          if (c == 1) val = pixel.g.toDouble();
          if (c == 2) val = pixel.b.toDouble();
          
          // 典型归一化: (x / 255.0 - mean) / std
          float32List[bufferIndex++] = (val / 255.0 - 0.5) / 0.5;
        }
      }
    }

    // 3. 运行推理
    final inputShape = [1, 3, 640, 640];
    final inputTensor = OrtValueTensor.createTensorWithDataList(float32List, inputShape);
    final inputs = {'x': inputTensor}; // 注意：输入 Key 取决于模型定义，通常为 'x' 或 'input'
    
    final runOptions = OrtRunOptions();
    final outputs = await _session!.runAsync(runOptions, inputs);

    // 4. 解析结果 (由于 OCR 后处理非常复杂，此处实现逻辑骨架)
    // 实际应包含：DBNet 后处理 (获取概率图 -> 找轮廓 -> 坐标映射)
    if (outputs == null || outputs.isEmpty) return [];

    // 暂时返回模拟数据，直到后处理算法（如矩形框提取）完成
    // 在真实集成中，这里会根据 outputs[0].value 解析出真实的文字坐标
    return [
      {
        'text': 'Detected Title',
        'rect': [0.1, 0.1, 0.4, 0.05], // 归一化坐标 [x, y, w, h]
      }
    ];
  }

  void dispose() {
    _session?.release();
  }
}
