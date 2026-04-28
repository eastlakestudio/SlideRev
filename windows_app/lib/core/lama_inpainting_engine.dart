import 'dart:typed_data';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:image/image.dart' as img;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'logger.dart';

class LamaInpaintingEngine {
  bool _isInitialized = false;
  OrtSession? _session;

  bool get isInitialized => _isInitialized;

  Future<void> init(String modelPath) async {
    try {
      AppLogger.d('Lama', 'Initializing LaMa session from $modelPath...');
      OrtEnv.instance.init();
      final modelBytes = await File(modelPath).readAsBytes();
      _session = OrtSession.fromBuffer(modelBytes, OrtSessionOptions());
      _isInitialized = true;
      AppLogger.d('Lama', 'LaMa Engine initialized.');
    } catch (e) {
      AppLogger.e('Lama', 'Failed to initialize LaMa: $e');
    }
  }

  Future<Uint8List?> inpaint(Uint8List imageBytes, Uint8List maskBytes) async {
    if (!_isInitialized) return null;

    final image = img.decodeImage(imageBytes)!;
    final mask = img.decodeImage(maskBytes)!;

    final resizedImage = img.copyResize(image, width: 512, height: 512);
    final resizedMask = img.copyResize(mask, width: 512, height: 512);

    final inputData = await compute(_prepareLamaInput, {
      'image': resizedImage,
      'mask': resizedMask,
    });

    final runOptions = OrtRunOptions();
    final inputs = {
      'image': OrtValueTensor.createTensorWithDataList(inputData['image'] as Float32List, [1, 3, 512, 512]),
      'mask': OrtValueTensor.createTensorWithDataList(inputData['mask'] as Float32List, [1, 1, 512, 512]),
    };

    try {
      final outputs = await _session!.runAsync(runOptions, inputs);
      final outputTensor = outputs![0]!.value;
      
      final result = await compute(_lamaPostProcessTask, {
        'output': outputTensor,
        'original': imageBytes,
        'mask': maskBytes,
      });

      outputs.forEach((v) => v?.release());
      inputs.values.forEach((v) => v.release());
      
      return result;
    } catch (e) {
      AppLogger.e('Lama', 'Inpaint inference failed: $e');
      return null;
    }
  }
}

Map<String, Float32List> _prepareLamaInput(Map<String, dynamic> params) {
  final img.Image resizedImage = params['image'];
  final img.Image resizedMask = params['mask'];
  
  final imgData = Float32List(1 * 3 * 512 * 512);
  final maskData = Float32List(1 * 1 * 512 * 512);

  for (var y = 0; y < 512; y++) {
    for (var x = 0; x < 512; x++) {
      final isMasked = resizedMask.getPixel(x, y).luminanceNormalized > 0.5;
      final pixel = resizedImage.getPixel(x, y);
      
      imgData[0 * 512 * 512 + y * 512 + x] = isMasked ? 0.0 : (pixel.r / 255.0);
      imgData[1 * 512 * 512 + y * 512 + x] = isMasked ? 0.0 : (pixel.g / 255.0);
      imgData[2 * 512 * 512 + y * 512 + x] = isMasked ? 0.0 : (pixel.b / 255.0);
      
      maskData[y * 512 + x] = isMasked ? 1.0 : 0.0;
    }
  }
  return {'image': imgData, 'mask': maskData};
}

Uint8List? _lamaPostProcessTask(Map<String, dynamic> params) {
  final dynamic outputTensor = params['output'];
  final Uint8List originalBytes = params['original'];
  final Uint8List maskBytes = params['mask'];

  List<double> flatData;
  if (outputTensor is List && outputTensor.isNotEmpty && outputTensor[0] is List) {
    flatData = _deepFlatten(outputTensor);
  } else {
    flatData = (outputTensor as List).cast<double>();
  }

  if (flatData.isEmpty) return null;

  double maxVal = -1000000.0;
  for (var v in flatData) { if (v > maxVal) maxVal = v; }
  final double scale = (maxVal <= 1.2) ? 255.0 : 1.0;
  
  final outImg512 = img.Image(width: 512, height: 512);
  for (var y = 0; y < 512; y++) {
    for (var x = 0; x < 512; x++) {
      final rF = flatData[0 * 512 * 512 + y * 512 + x] * scale;
      final gF = flatData[1 * 512 * 512 + y * 512 + x] * scale;
      final bF = flatData[2 * 512 * 512 + y * 512 + x] * scale;
      
      outImg512.setPixelRgb(x, y, 
        rF.clamp(0, 255).toInt(), 
        gF.clamp(0, 255).toInt(), 
        bF.clamp(0, 255).toInt());
    }
  }

  final originalImage = img.decodeImage(originalBytes)!;
  final maskImg = img.decodeImage(maskBytes)!;
  final inpaintedFullSize = img.copyResize(outImg512, width: originalImage.width, height: originalImage.height);

  for (var y = 0; y < originalImage.height; y++) {
    for (var x = 0; x < originalImage.width; x++) {
      final m = maskImg.getPixel(x, y);
      if (m.luminanceNormalized > 0.5) {
        originalImage.setPixel(x, y, inpaintedFullSize.getPixel(x, y));
      }
    }
  }

  return Uint8List.fromList(img.encodePng(originalImage));
}

List<double> _deepFlatten(dynamic list) {
  List<double> result = [];
  _flattenHelper(list, result);
  return result;
}

void _flattenHelper(dynamic item, List<double> result) {
  if (item is List) {
    for (var sub in item) {
      _flattenHelper(sub, result);
    }
  } else if (item is double) {
    result.add(item);
  } else if (item is int) {
    result.add(item.toDouble());
  }
}
