import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'core/vision_ocr_adapter.dart';
import 'core/lama_inpainting_engine.dart';
import 'core/pdf_engine.dart';
import 'core/model_manager.dart';
import 'core/logger.dart';
import 'pages/refinement_page.dart';

void main() {
  runApp(const SlideRevWindowsApp());
}

class SlideRevWindowsApp extends StatelessWidget {
  const SlideRevWindowsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SlideRev',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.blueAccent,
        useMaterial3: true,
        fontFamily: 'Segoe UI',
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

enum AppState { dashboard, processing }

class _MainDesktopWindowState extends State<MainDesktopWindow> {
  bool _isHoveringDashboard = false;
  String? _selectedFilePath;
  AppState _appState = AppState.dashboard;
  String _statusText = "Initializing AI Engine...";
  double _progress = 0.0;
  int _pageCount = 0;

  Future<void> _onImportPdf() async {
    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'heic', 'tiff'],
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      setState(() {
        _selectedFilePath = path;
        _statusText = "Analyzing PDF...";
        _appState = AppState.processing;
        _progress = 0.2;
      });
      AppLogger.d('Main', 'Selected file: $path');
      
      final pdfEngine = PdfEngine();
      final count = await pdfEngine.getPageCount(path);

      setState(() {
        _pageCount = count;
      });
      
      // 直接进入第一页处理
      await _processPage(1);
    }
  }

  Future<void> _processPage(int pageNumber) async {
    if (_selectedFilePath == null) return;
    try {
      setState(() {
        _statusText = "Processing Page $pageNumber...";
        _progress = 0.4;
      });
      
      final ocrModelPath = await ModelManager().getLocalModelPath('assets/models/ocr_model.onnx');
      final ocrAdapter = VisionOcrAdapter();
      await ocrAdapter.init(ocrModelPath);

      final pdfEngine = PdfEngine();
      final pageImage = await pdfEngine.renderPageToImage(_selectedFilePath!, pageNumber);
      if (pageImage == null) throw Exception("Failed to render page");

      final nodes = await ocrAdapter.recognizeText(pageImage.bytes);
      
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => RefinementPage(
            pdfFilePath: _selectedFilePath!,
            initialPageNumber: pageNumber,
            totalPageCount: _pageCount,
            initialImageBytes: pageImage.bytes,
            initialNodes: nodes,
            initialWidth: pageImage.width!.toDouble(),
            initialHeight: pageImage.height!.toDouble(),
          ),
        ),
      );
      _reset();
    } catch (e, stack) {
      AppLogger.e('Main', 'Page processing failed', e, stack);
      _reset();
    }
  }

  void _reset() {
    setState(() {
      _appState = AppState.dashboard;
      _progress = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.03,
              child: CustomPaint(painter: GridPainter()),
            ),
          ),
          if (_appState == AppState.dashboard)
            _buildDashboard()
          else
            _buildProcessingView(),
        ],
      ),
    );
  }

  Widget _buildDashboard() {
    return Center(
      child: Column(
        children: [
          const Spacer(),
          _buildHeader(),
          const SizedBox(height: 40),
          MouseRegion(
            onEnter: (_) => setState(() => _isHoveringDashboard = true),
            onExit: (_) => setState(() => _isHoveringDashboard = false),
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: _onImportPdf,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 640,
                height: 440,
                transform: Matrix4.diagonal3Values(
                  _isHoveringDashboard ? 1.02 : 1.0,
                  _isHoveringDashboard ? 1.02 : 1.0,
                  1.0,
                ),
                transformAlignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: _isHoveringDashboard ? 0.06 : 0.03),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: _isHoveringDashboard ? 1.0 : 0.2),
                    width: _isHoveringDashboard ? 2.5 : 1.5,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: 40, left: 0, right: 0,
                      child: Opacity(opacity: 0.5, child: const GraphicProcessView()),
                    ),
                    _buildDashboardText(),
                    _buildPlusIcon(),
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        const Text("SlideRev...", style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Text("Professional AI Slide Reconstructor", style: TextStyle(fontSize: 18, color: Theme.of(context).colorScheme.primary)),
      ],
    );
  }

  Widget _buildDashboardText() {
    return Positioned(
      bottom: 120, left: 0, right: 0,
      child: Column(
        children: [
          const Text("Drag & Drop or Click to Import", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text("Supports PDF, Images, and Screenshots", style: TextStyle(fontSize: 14, color: Colors.grey[400])),
        ],
      ),
    );
  }

  Widget _buildPlusIcon() {
    return Positioned(
      bottom: 40, left: 0, right: 0,
      child: Center(
        child: Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.add, size: 32, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildProcessingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(_statusText, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SizedBox(
            width: 300,
            child: LinearProgressIndicator(value: _progress),
          ),
        ],
      ),
    );
  }
}

class GraphicProcessView extends StatelessWidget {
  const GraphicProcessView({super.key});
  @override
  Widget build(BuildContext context) {
    return const Icon(Icons.AutoFixHigh, size: 120, color: Colors.blueAccent);
  }
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.1)..strokeWidth = 1;
    for (double i = 0; i < size.width; i += 40) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += 40) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
