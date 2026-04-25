import 'package:flutter/foundation.dart';

class AppLogger {
  static void d(String tag, String message) {
    if (kDebugMode || true) { // 强制开启方便用户在 Release 测试版也能看到部分日志
      final timestamp = DateTime.now().toIso8601String().split('T').last;
      print('DEBUG [$timestamp] [$tag] $message');
    }
  }

  static void w(String tag, String message) {
    final timestamp = DateTime.now().toIso8601String().split('T').last;
    print('WARN  [$timestamp] [$tag] $message');
  }

  static void e(String tag, String message, [dynamic error, StackTrace? stack]) {
    final timestamp = DateTime.now().toIso8601String().split('T').last;
    print('ERROR [$timestamp] [$tag] $message');
    if (error != null) print('Cause: $error');
    if (stack != null) print(stack);
  }
}
