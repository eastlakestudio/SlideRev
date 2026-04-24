import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

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

    // 如果文件已存在，直接返回（生产环境建议增加校验）
    if (await file.exists()) {
      return localPath;
    }

    // 复制数据
    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    await file.writeAsBytes(bytes);

    return localPath;
  }
}
