import 'package:flutter/material.dart';

void main() {
  runApp(const SlideRevWindowsApp());
}

class SlideRevWindowsApp extends StatelessWidget {
  const SlideRevWindowsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SlideRev',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.blueAccent,
        useMaterial3: true,
      ),
      home: const MainDesktopWindow(),
    );
  }
}

class MainDesktopWindow extends StatefulWidget {
  const MainDesktopWindow({super.key});

  @override
  State<MainDesktopWindow> createState() => _MainDesktopWindowState();
}

class _MainDesktopWindowState extends State<MainDesktopWindow> {
  String _statusText = 'Ready';

  void _onImportPdf() {
    setState(() {
      _statusText = 'Importing PDF...';
    });
    // 调用 PDFEngine 等
  }

  void _onExportPptx() {
    setState(() {
      _statusText = 'Exporting PPTX...';
    });
    // 调用 PptxGenerator 等
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SlideRev for Windows'),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.picture_as_pdf, size: 80, color: Colors.blueAccent),
            const SizedBox(height: 20),
            Text(
              'Convert Flattened PDF Slides to Editable PPTX',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _onImportPdf,
                  icon: const Icon(Icons.file_upload),
                  label: const Text('Import PDF'),
                ),
                const SizedBox(width: 20),
                FilledButton.icon(
                  onPressed: _onExportPptx,
                  icon: const Icon(Icons.transform),
                  label: const Text('Convert to PPTX'),
                ),
              ],
            ),
            const SizedBox(height: 40),
            Text(
              _statusText,
              style: const TextStyle(color: Colors.grey),
            )
          ],
        ),
      ),
    );
  }
}
