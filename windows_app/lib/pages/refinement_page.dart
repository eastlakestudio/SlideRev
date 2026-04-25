import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../core/pptx_generator.dart';
import '../core/pdf_generator.dart';
import '../core/pdf_engine.dart';
import '../core/vision_ocr_adapter.dart';
import '../core/lama_inpainting_engine.dart';
import '../core/model_manager.dart';
import '../core/logger.dart';
import 'dart:ui' as ui;

class RefinementPage extends StatefulWidget {
  final String pdfFilePath;
  final int initialPageNumber;
  final int totalPageCount;
  final Uint8List initialImageBytes;
  final List<Map<String, dynamic>> initialNodes;
  final double initialWidth;
  final double initialHeight;

  const RefinementPage({
    super.key,
    required this.pdfFilePath,
    required this.initialPageNumber,
    required this.totalPageCount,
    required this.initialImageBytes,
    required this.initialNodes,
    required this.initialWidth,
    required this.initialHeight,
  });

  @override
  State<RefinementPage> createState() => _RefinementPageState();
}

class _RefinementPageState extends State<RefinementPage> {
  late List<Map<String, dynamic>> _nodes;
  late Uint8List _currentImageBytes;
  late int _currentPage;
  late double _currentWidth;
  late double _currentHeight;

  Uint8List? _inpaintedImage;
  bool _isProcessing = false;
  bool _showInpainted = false;
  int? _editingIndex;

  @override
  void initState() {
    super.initState();
    _nodes = List.from(widget.initialNodes);
    _currentImageBytes = widget.initialImageBytes;
    _currentPage = widget.initialPageNumber;
    _currentWidth = widget.initialWidth;
    _currentHeight = widget.initialHeight;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Row(
          children: [
            const Text("SlideRev Workspace", style: TextStyle(fontSize: 16)),
            const SizedBox(width: 32),
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: _currentPage > 1 ? () => _goToPage(_currentPage - 1) : null,
            ),
            Text("$_currentPage / ${widget.totalPageCount}", style: const TextStyle(fontSize: 14)),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: _currentPage < widget.totalPageCount ? () => _goToPage(_currentPage + 1) : null,
            ),
          ],
        ),
        actions: [
          if (_inpaintedImage == null)
            TextButton.icon(
              onPressed: _isProcessing ? null : _runInpainting,
              icon: _isProcessing ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_fix_high, size: 18),
              label: Text(_isProcessing ? "AI Processing..." : "AI Remove Text"),
              style: TextButton.styleFrom(foregroundColor: Colors.orangeAccent),
            ),
          if (_inpaintedImage != null)
            Row(
              children: [
                const Text("AI Background", style: TextStyle(fontSize: 12, color: Colors.grey)),
                Switch(
                  value: _showInpainted,
                  onChanged: (v) => setState(() => _showInpainted = v),
                  activeColor: Colors.orangeAccent,
                ),
              ],
            ),
          const VerticalDivider(width: 32, indent: 12, endIndent: 12),
          ElevatedButton.icon(
            onPressed: _exportPptx,
            icon: const Icon(Icons.file_download),
            label: const Text("Export PPTX"),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: GestureDetector(
        onTap: () => setState(() => _editingIndex = null),
        child: Center(
          child: Container(
            margin: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 40)],
            ),
            child: ClipRRect(
              child: Stack(
                children: [
                  // 底图
                  Image.memory(
                    (_showInpainted && _inpaintedImage != null) ? _inpaintedImage! : _currentImageBytes,
                    fit: BoxFit.contain,
                  ),
                  
                  // 文本编辑层
                  Positioned.fill(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return Stack(
                          children: _nodes.asMap().entries.map((entry) {
                            final index = entry.key;
                            final node = entry.value;
                            final rect = node['rect'] as List<double>;
                            final isEditing = _editingIndex == index;

                            return Positioned(
                              left: rect[0] * constraints.maxWidth,
                              top: rect[1] * constraints.maxHeight,
                              width: rect[2] * constraints.maxWidth,
                              height: rect[3] * constraints.maxHeight,
                              child: isEditing 
                                ? _buildInlineEditor(index)
                                : _buildTappableNode(index, node['text']),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTappableNode(int index, String text) {
    return GestureDetector(
      onTap: () => setState(() => _editingIndex = index),
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3), width: 0.5),
            color: Colors.blueAccent.withValues(alpha: 0.05),
          ),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            text,
            style: const TextStyle(color: Colors.white, fontSize: 10, overflow: TextOverflow.ellipsis),
          ),
        ),
      ),
    );
  }

  Widget _buildInlineEditor(int index) {
    return Container(
      color: Colors.blueAccent.withValues(alpha: 0.9),
      child: TextFormField(
        initialValue: _nodes[index]['text'],
        autofocus: true,
        style: const TextStyle(color: Colors.white, fontSize: 12),
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 0),
          isDense: true,
        ),
        onChanged: (val) => _nodes[index]['text'] = val,
        onFieldSubmitted: (_) => setState(() => _editingIndex = null),
      ),
    );
  }

  Future<void> _goToPage(int pageNumber) async {
    setState(() => _isProcessing = true);
    try {
      final pdfEngine = PdfEngine();
      final pageImage = await pdfEngine.renderPageToImage(widget.pdfFilePath, pageNumber);
      if (pageImage == null) return;

      final ocrModelPath = await ModelManager().getLocalModelPath('assets/models/ocr_model.onnx');
      final ocrAdapter = VisionOcrAdapter();
      await ocrAdapter.init(ocrModelPath);
      final nodes = await ocrAdapter.recognizeText(pageImage.bytes);

      setState(() {
        _currentPage = pageNumber;
        _currentImageBytes = pageImage.bytes;
        _currentWidth = pageImage.width!.toDouble();
        _currentHeight = pageImage.height!.toDouble();
        _nodes = nodes;
        _inpaintedImage = null;
        _showInpainted = false;
        _isProcessing = false;
        _editingIndex = null;
      });
    } catch (e) {
      AppLogger.e('Workspace', 'Failed to switch page', e);
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _runInpainting() async {
    setState(() => _isProcessing = true);
    try {
      final maskBytes = await _generateMask();
      final modelPath = await ModelManager().getLocalModelPath('assets/models/lama_fp32.onnx');
      final lama = LamaInpaintingEngine();
      await lama.init(modelPath);
      final result = await lama.inpaintImage(_currentImageBytes, maskBytes);
      
      setState(() {
        _inpaintedImage = result;
        _showInpainted = true;
        _isProcessing = false;
      });
    } catch (e) {
      AppLogger.e('Workspace', 'Inpainting failed', e);
      setState(() => _isProcessing = false);
    }
  }

  Future<Uint8List> _generateMask() async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder, ui.Rect.fromLTWH(0, 0, 512, 512));
    canvas.drawRect(ui.Rect.fromLTWH(0, 0, 512, 512), ui.Paint()..color = Colors.black);
    final paint = ui.Paint()..color = Colors.white;
    for (var node in _nodes) {
      final rect = node['rect'] as List<double>;
      canvas.drawRect(ui.Rect.fromLTWH(rect[0] * 512, rect[1] * 512, rect[2] * 512, rect[3] * 512), paint);
    }
    final img = await recorder.endRecording().toImage(512, 512);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<void> _exportPptx() async {
    String? outputPath = await FilePicker.saveFile(
      dialogTitle: 'Save PPTX',
      fileName: 'refined_slides.pptx',
      type: FileType.custom,
      allowedExtensions: ['pptx'],
    );
    if (outputPath != null) {
      if (!outputPath.endsWith('.pptx')) outputPath += '.pptx';
      final generator = PptxGenerator();
      await generator.createPptx(outputPath, [
        PptxPageData(
          backgroundImage: _inpaintedImage ?? _currentImageBytes,
          nodes: _nodes,
          width: _currentWidth,
          height: _currentHeight,
        ),
      ]);
    }
  }
}
