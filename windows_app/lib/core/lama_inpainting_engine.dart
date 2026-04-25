import 'dart:io';
import 'dart:typed_data';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:image/image.dart' as img;
import 'logger.dart';

class LamaInpaintingEngine {
  OrtSession? _session;

  Future<void> init(String modelPath) async {
    AppLogger.d('Inpainting', 'Attempting to initialize LaMa from file: $modelPath');
    final sessionOptions = OrtSessionOptions();
    
    try {
      _session = OrtSession.fromFile(File(modelPath), sessionOptions);
      AppLogger.d('Inpainting', 'LaMa successfully initialized from file');
    } catch (e) {
      AppLogger.w('Inpainting', 'LaMa file loading failed. Falling back to memory...');
      try {
        final modelData = await File(modelPath).readAsBytes();
        _session = OrtSession.fromBuffer(modelData, sessionOptions);
        AppLogger.d('Inpainting', 'LaMa successfully initialized from memory');
      } catch (e2) {
        AppLogger.e('Inpainting', 'LaMa all loading methods failed', e2);
        rethrow;
      }
    }
  }

  Future<Uint8List> inpaintImage(Uint8List imageBytes, Uint8List maskBytes) async {
    if (_session == null) throw Exception("LaMa Session not initialized");

    final image = img.decodeImage(imageBytes);
    final mask = img.decodeImage(maskBytes);
    if (image == null || mask == null) return imageBytes;

    // 1. Preprocessing: Resize to 512x512
    final resizedImg = img.copyResize(image, width: 512, height: 512);
    final resizedMask = img.copyResize(mask, width: 512, height: 512);

    // 2. Prepare Tensors
    final imgData = Float32List(1 * 3 * 512 * 512);
    final maskData = Float32List(1 * 1 * 512 * 512);

    for (var c = 0; c < 3; c++) {
      for (var y = 0; y < 512; y++) {
        for (var x = 0; x < 512; x++) {
          final p = resizedImg.getPixel(x, y);
          double val = (c == 0 ? p.r : (c == 1 ? p.g : p.b)).toDouble() / 255.0;
          imgData[c * 512 * 512 + y * 512 + x] = val;
        }
      }
    }

    for (var y = 0; y < 512; y++) {
      for (var x = 0; x < 512; x++) {
        final p = resizedMask.getPixel(x, y);
        // Mask: 1.0 for inpainting area, 0.0 for background
        maskData[y * 512 + x] = p.luminanceNormalized > 0.5 ? 1.0 : 0.0;
      }
    }

    // 3. Inference
    final inputs = {
      'image': OrtValueTensor.createTensorWithDataList(imgData, [1, 3, 512, 512]),
      'mask': OrtValueTensor.createTensorWithDataList(maskData, [1, 1, 512, 512]),
    };

    AppLogger.d('Inpainting', 'Running LaMa inference...');
    final startTime = DateTime.now();
    final outputs = await _session!.runAsync(OrtRunOptions(), inputs);
    final duration = DateTime.now().difference(startTime).inMilliseconds;
    AppLogger.d('Inpainting', 'LaMa inference finished in ${duration}ms');
    if (outputs == null || outputs.isEmpty) return imageBytes;

    // 4. Postprocessing: Convert output tensor back to Image
    // (Assuming output is [1, 3, 512, 512] RGB)
    final outputData = outputs[0]?.value as List<List<List<List<double>>>>;
    final outImg = img.Image(width: 512, height: 512);
    
    for (var y = 0; y < 512; y++) {
      for (var x = 0; x < 512; x++) {
        final r = (outputData[0][0][y][x] * 255).clamp(0, 255).toInt();
        final g = (outputData[0][1][y][x] * 255).clamp(0, 255).toInt();
        final b = (outputData[0][2][y][x] * 255).clamp(0, 255).toInt();
        outImg.setPixelRgb(x, y, r, g, b);
      }
    }

    return Uint8List.fromList(img.encodePng(outImg));
  }

  void dispose() {
    _session?.release();
  }
}
