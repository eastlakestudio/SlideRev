import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'logger.dart';

class ModelManager {
  static final ModelManager _instance = ModelManager._internal();
  factory ModelManager() => _instance;
  ModelManager._internal();

  /// 将 Asset 中的模型文件提取到本地临时目录
  Future<String> getLocalModelPath(String assetPath) async {
    final tempDir = await getTemporaryDirectory();
    final fileName = p.basename(assetPath);
    final localPath = p.join(tempDir.path, fileName);
    final file = File(localPath);

    // 复制数据
    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

    // 如果文件已存在且大小一致，直接返回；否则覆盖写入
    if (await file.exists()) {
      final existingSize = await file.length();
      if (existingSize == bytes.length) {
        AppLogger.d('ModelManager', 'Cache hit for $fileName (size matches)');
        return localPath;
      }
      AppLogger.w('ModelManager', 'Cache size mismatch for $fileName ($existingSize vs ${bytes.length}). Overwriting...');
    }
    await file.writeAsBytes(bytes);

    return localPath;
  }

  /// 直接获取 Asset 中的模型字节流，避免 Windows 路径乱码问题
  Future<Uint8List> getModelBytes(String assetPath) async {
    AppLogger.d('ModelManager', 'Loading asset: $assetPath');
    try {
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      AppLogger.d('ModelManager', 'Successfully loaded $assetPath, size: ${bytes.length} bytes');
      return bytes;
    } catch (e) {
      AppLogger.e('ModelManager', 'Failed to load asset: $assetPath', e);
      rethrow;
    }
  }
}
