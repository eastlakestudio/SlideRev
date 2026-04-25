import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:windows_app/core/pptx_generator.dart';

void main() {
  group('PptxGenerator Tests', () {
    test('createPptx should generate a zip/pptx file', () async {
      final generator = PptxGenerator();
      final outputPath = 'test_output.pptx';
      
      // Clean up before test
      if (File(outputPath).existsSync()) {
        File(outputPath).deleteSync();
      }

      await generator.createPptx(outputPath, [
        PptxPageData(
          backgroundImage: Uint8List(0),
          nodes: [
            {'text': 'Test Slide', 'rect': [0.0, 0.0, 100.0, 50.0]}
          ],
          width: 720,
          height: 540,
        )
      ]);

      final file = File(outputPath);
      expect(file.existsSync(), isTrue);
      
      // Clean up after test
      if (file.existsSync()) {
        file.deleteSync();
      }
    });
  });
}
