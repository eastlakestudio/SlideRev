import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:image/image.dart' as img;
import '../core/pptx_generator.dart';
import '../core/pdf_generator.dart';
import '../core/vision_ocr_adapter.dart';
import '../core/lama_inpainting_engine.dart';
import '../core/logger.dart';

class ProcessedPage {
  final Uint8List originalImage;
  final Uint8List? inpaintedImage;
  final List<Map<String, dynamic>> nodes;
  final double width;
  final double height;

  ProcessedPage({
    required this.originalImage,
    this.inpaintedImage,
    required this.nodes,
    required this.width,
    required this.height,
  });
}

class RefinementPage extends StatefulWidget {
  final List<ProcessedPage> pages;
  final String pdfPath;
  final VisionOcrAdapter ocrAdapter;
  final LamaInpaintingEngine lamaEngine;

  const RefinementPage({
    super.key,
    required this.pages,
    required this.pdfPath,
    required this.ocrAdapter,
    required this.lamaEngine,
  });

  @override
  State<RefinementPage> createState() => _RefinementPageState();
}

enum ViewMode { original, editable }

class _RefinementPageState extends State<RefinementPage> {
  int _currentIndex = 0;
  ViewMode _viewMode = ViewMode.editable;
  double _zoom = 1.0;
  double _ocrThreshold = 0.10;
  String _selectedWatermark = "A NotebookLM";
  int? _hoveredIndex;
  int? _focusedIndex;
  bool _isTextVisible = true;
  final TransformationController _transformationController = TransformationController();

  late List<List<TextEditingController>> _allControllers;

  @override
  void initState() {
    super.initState();
    _allControllers = widget.pages.map((page) {
      return page.nodes.map((n) => TextEditingController(text: n['text'] ?? "")).toList();
    }).toList();
    _transformationController.addListener(_onTransformationChanged);
  }

  void _onTransformationChanged() {
    final double scale = _transformationController.value.storage[0];
    if ((scale - _zoom).abs() > 0.01) {
      setState(() {
        _zoom = scale.clamp(0.1, 5.0);
      });
    }
  }

  void _updateZoom(double newZoom) {
    final double targetZoom = newZoom.clamp(0.1, 5.0);
    setState(() {
      _zoom = targetZoom;
    });
    final double currentScale = _transformationController.value.storage[0];
    final double scaleRatio = targetZoom / currentScale;
    _transformationController.value = _transformationController.value.clone()
      ..scale(scaleRatio, scaleRatio, 1.0);
  }

  @override
  void dispose() {
    for (var pageControllers in _allControllers) {
      for (var c in pageControllers) {
        c.dispose();
      }
    }
    _transformationController.dispose();
    super.dispose();
  }

  void _changePage(int newIndex) {
    if (newIndex < 0 || newIndex >= widget.pages.length) return;
    setState(() {
      _currentIndex = newIndex;
      _focusedIndex = null;
    });
  }

  void _ensureEditable() {
    if (_viewMode == ViewMode.original) setState(() => _viewMode = ViewMode.editable);
  }

  ProcessedPage get _currentPage => widget.pages[_currentIndex];
  List<TextEditingController> get _currentControllers => _allControllers[_currentIndex];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: Column(
        children: [
          _buildTopToolbar(),
          Expanded(child: _buildCanvasArea()),
          _buildBottomStatusBar(),
        ],
      ),
    );
  }

  Widget _buildTopToolbar() {
    return Container(
      height: 64, padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.black.withValues(alpha: 0.1), width: 0.5))),
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.home_filled, color: Colors.grey), onPressed: () => Navigator.pop(context)),
          const VerticalDivider(width: 20, indent: 20, endIndent: 20),
          Container(
            decoration: BoxDecoration(color: const Color(0xFFE3E3E3), borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.all(2),
            child: Row(children: [_buildModeTab("Original", ViewMode.original), _buildModeTab("Editable", ViewMode.editable)]),
          ),
          const SizedBox(width: 12),
          _buildWatermarkGroup(),
          const Spacer(),
          _buildToolbarTextButton("Reset", Icons.refresh, onPressed: () { 
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Restoring original OCR state...')));
          }),
          const SizedBox(width: 12),
          const VerticalDivider(width: 1, indent: 20, endIndent: 20),
          const SizedBox(width: 12),
          _buildToolbarToggleButton("Show Text", _isTextVisible ? Icons.visibility : Icons.visibility_off, _isTextVisible, onPressed: () {
            _ensureEditable();
            setState(() => _isTextVisible = !_isTextVisible);
          }),
          const SizedBox(width: 12),
          const VerticalDivider(width: 1, indent: 20, endIndent: 20),
          const SizedBox(width: 12),
          _buildPrimaryActionButton("Export PPTX", Icons.ios_share, onPressed: _exportPptx),
        ],
      ),
    );
  }

  Widget _buildWatermarkGroup() {
    return Container(
      height: 36, padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04), 
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cleaning_services, size: 14, color: Colors.orange),
          const SizedBox(width: 8),
          Theme(
            data: Theme.of(context).copyWith(
              hoverColor: Colors.transparent,
              splashColor: Colors.transparent,
            ),
            child: PopupMenuButton<String>(
              initialValue: _selectedWatermark,
              tooltip: "Select Watermark Keyword",
              offset: const Offset(0, 40),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onSelected: (String val) {
                setState(() => _selectedWatermark = val);
              },
              child: Row(
                children: [
                  Text(_selectedWatermark, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black)),
                  const Icon(Icons.arrow_drop_down, size: 16, color: Colors.black54),
                ],
              ),
              itemBuilder: (context) => ["A NotebookLM", "NotebookLM", "Confidential", "DRAFT", "2026-3-17"]
                  .map((s) => PopupMenuItem(
                        value: s,
                        height: 32,
                        child: Text(s, style: const TextStyle(fontSize: 12)),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(width: 8),
          _buildWatermarkActionButton("本页", _handleWatermarkRemovalForCurrentPage),
          const SizedBox(width: 4),
          _buildWatermarkActionButton("全部", _handleWatermarkRemovalForAllPages),
        ],
      ),
    );
  }

  Widget _buildWatermarkActionButton(String text, VoidCallback onPressed) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
        ),
        child: Text(text, style: const TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.bold)),
      ),
    );
  }

  void _handleWatermarkRemovalForCurrentPage() {
    final keyword = _selectedWatermark;
    final page = widget.pages[_currentIndex];
    final controllers = _allControllers[_currentIndex];
    
    List<int> toRemove = [];
    for (int i = page.nodes.length - 1; i >= 0; i--) {
      final text = page.nodes[i]['text'] as String;
      if (text.contains(keyword)) {
        toRemove.add(i);
      }
    }

    if (toRemove.isEmpty) {
       ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text('No watermark matching "$keyword" found on this page.'), duration: const Duration(seconds: 1))
       );
       return;
    }

    setState(() {
      for (var idx in toRemove) {
        page.nodes.removeAt(idx);
        controllers[idx].dispose();
        controllers.removeAt(idx);
      }
      _focusedIndex = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Removed ${toRemove.length} watermark nodes from this page.'), backgroundColor: Colors.green),
    );
  }

  void _handleWatermarkRemovalForAllPages() {
    final keyword = _selectedWatermark;
    int totalRemoved = 0;

    setState(() {
      for (int p = 0; p < widget.pages.length; p++) {
        final page = widget.pages[p];
        final controllers = _allControllers[p];
        
        List<int> toRemove = [];
        for (int i = page.nodes.length - 1; i >= 0; i--) {
          final text = page.nodes[i]['text'] as String;
          if (text.contains(keyword)) {
            toRemove.add(i);
          }
        }

        for (var idx in toRemove) {
          page.nodes.removeAt(idx);
          if (p == _currentIndex) {
            controllers[idx].dispose();
          }
          controllers.removeAt(idx);
        }
        totalRemoved += toRemove.length;
      }
      _focusedIndex = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Removed $totalRemoved watermark nodes across all pages.'), backgroundColor: Colors.green),
    );
  }

  void _handleWatermarkRemoval(String keyword) {
    // 🚀 去水印核心逻辑：节点过滤
    final page = widget.pages[_currentIndex];
    final controllers = _allControllers[_currentIndex];
    
    // 找出所有匹配的节点索引（倒序删除，防止索引错乱）
    List<int> toRemove = [];
    for (int i = page.nodes.length - 1; i >= 0; i--) {
      final text = page.nodes[i]['text'] as String;
      if (text.contains(keyword)) {
        toRemove.add(i);
      }
    }

    if (toRemove.isEmpty) {
       ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text('No watermark matching "$keyword" found on this page.'), duration: const Duration(seconds: 1))
       );
       return;
    }

    setState(() {
      for (var idx in toRemove) {
        page.nodes.removeAt(idx);
        controllers[idx].dispose();
        controllers.removeAt(idx);
      }
      _focusedIndex = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Removed ${toRemove.length} watermark nodes.'), backgroundColor: Colors.green.withValues(alpha: 0.8)),
    );
  }

  Widget _buildModeTab(String label, ViewMode mode) {
    final isSelected = _viewMode == mode;
    return GestureDetector(
      onTap: () => setState(() => _viewMode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: isSelected ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 2, offset: const Offset(0, 1))] : null,
        ),
        child: Text(label, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400, color: isSelected ? Colors.black : Colors.grey.shade600)),
      ),
    );
  }

  Widget _buildToolbarIconButton(IconData icon, {Color? color, Color? iconColor, VoidCallback? onPressed}) {
    return GestureDetector(onTap: onPressed, child: Container(width: 32, height: 32, decoration: BoxDecoration(color: color ?? Colors.transparent, borderRadius: BorderRadius.circular(6)), child: Icon(icon, size: 18, color: iconColor ?? Colors.grey.shade700)));
  }

  Widget _buildToolbarTextButton(String label, IconData icon, {required VoidCallback onPressed}) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 32, padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(8)),
        child: Row(children: [Icon(icon, size: 14, color: const Color(0xFF007AFF)), const SizedBox(width: 6), Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF007AFF)))]),
      ),
    );
  }

  Widget _buildToolbarToggleButton(String label, IconData icon, bool isActive, {required VoidCallback onPressed}) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 32, width: 100,
        decoration: BoxDecoration(color: isActive ? const Color(0xFF007AFF) : Colors.black.withValues(alpha: 0.04), borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 14, color: isActive ? Colors.white : Colors.black87), const SizedBox(width: 6), Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isActive ? Colors.white : Colors.black87))]),
      ),
    );
  }

  Widget _buildPrimaryActionButton(String label, IconData icon, {VoidCallback? onPressed}) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: 32, width: 100,
        decoration: BoxDecoration(color: const Color(0xFF007AFF), borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 14, color: Colors.white), const SizedBox(width: 6), Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white))]),
      ),
    );
  }

  Widget _buildCanvasArea() {
    return InteractiveViewer(
      key: const ValueKey("main_viewer"),
      minScale: 0.1, maxScale: 5.0, scaleEnabled: true,
      boundaryMargin: const EdgeInsets.all(1000),
      transformationController: _transformationController,
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(10), // 缩小边距，让图片显示更大
          decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 30, offset: const Offset(0, 10))]),
          child: AspectRatio(
            aspectRatio: _currentPage.width / _currentPage.height,
            child: LayoutBuilder(builder: (context, constraints) {
              final cw = constraints.maxWidth;
              final ch = constraints.maxHeight;
              
              final bgImage = (_viewMode == ViewMode.editable && _currentPage.inpaintedImage != null) 
                  ? _currentPage.inpaintedImage! : _currentPage.originalImage;
              
              if (_viewMode == ViewMode.editable) {
                AppLogger.d('UI', 'Canvas build: Using ${_currentPage.inpaintedImage != null ? "INPAINTED" : "ORIGINAL"} image (Bytes: ${bgImage.length})');
              }

              return Stack(
                children: [
                  Image.memory(bgImage, width: cw, height: ch, fit: BoxFit.fill, gaplessPlayback: true, key: ValueKey("img_$_currentIndex")),
                  
                  if (_viewMode == ViewMode.editable && _isTextVisible)
                    Positioned.fill(
                      child: Stack(
                        key: ValueKey("nodes_$_currentIndex"),
                        children: List.generate(_currentPage.nodes.length, (idx) {
                          final node = _currentPage.nodes[idx];
                          final rect = node['rect'] as List<double>;
                          final text = node['text'] as String;
                          final currentText = _currentControllers[idx].text;
                          final textColor = Color(node['color'] as int? ?? 0xFF000000);
                          final isFocused = _focusedIndex == idx;
                          final isHovered = _hoveredIndex == idx;

                          // 🚀 使用 OCR 计算出的“黄金高度” (fittingH) 进行拟合
                          double _calculateFittingFontSize() {
                            final hasFittingH = node.containsKey('fittingH');
                            // 如果有黄金高度，直接用它；否则用原始核心高度的 1.5 倍作为 fallback
                            final double targetH = (hasFittingH ? node['fittingH'] : (node['rawH'] ?? rect[3] / 2.5) * 1.5) * ch;
                            final double targetW = rect[2] * cw; 
                            
                            const double testSize = 50.0;
                            final textPainter = TextPainter(
                              text: TextSpan(
                                text: currentText,
                                style: TextStyle(fontSize: testSize, fontFamily: 'Segoe UI'),
                              ),
                              textDirection: TextDirection.ltr,
                            )..layout();
                            
                            // 补偿系数调至 1.1 (更保守)
                            final double heightRatio = (targetH * 1.1) / textPainter.height;
                            final double widthRatio = (targetW * 0.85) / textPainter.width;
                            
                            final double finalSize = testSize * (heightRatio < widthRatio ? heightRatio : widthRatio) * 1.0;
                            
                            
                            return finalSize;
                          }

                          final double fontSize = _calculateFittingFontSize();
                          final double rawH = rect[3] * ch;
                          final double uiHeight = ((node.containsKey('fittingH') ? (node['fittingH'] as double) : rect[3]) * ch) * 1.2;
                          final double hDiff = uiHeight - rawH;

                          final double uiLeft = rect[0] * cw;
                          final double uiTop = rect[1] * ch - (hDiff / 2);
                          final double uiWidth = rect[2] * cw;

                          // if (idx == 0) AppLogger.d('UI', '--- Page $_currentIndex Layout ---');
                          // AppLogger.d('UI', 'Text: "$text"');
                          // AppLogger.d('UI', '  - UI Pos: [L:${uiLeft.toStringAsFixed(1)}, T:${uiTop.toStringAsFixed(1)}, W:${uiWidth.toStringAsFixed(1)}, H:${uiHeight.toStringAsFixed(1)}]');
                          // AppLogger.d('UI', '  - FontSize: ${fontSize.toStringAsFixed(1)}');
                          
                          if (text.contains("复合风险")) {
                            AppLogger.d('TRACE', '>>> TRACING UI: "复合风险"');
                            AppLogger.d('TRACE', '  - UI Pos: [L:${uiLeft.toStringAsFixed(1)}, T:${uiTop.toStringAsFixed(1)}, W:${uiWidth.toStringAsFixed(1)}, H:${uiHeight.toStringAsFixed(1)}]');
                            AppLogger.d('TRACE', '  - FontSize: ${fontSize.toStringAsFixed(1)}');
                          }

                          final controller = _currentControllers[idx];

                          return Positioned(
                            left: uiLeft, top: uiTop, width: uiWidth, height: uiHeight,
                            child: MouseRegion(
                              onEnter: (_) => setState(() => _hoveredIndex = idx),
                              onExit: (_) => setState(() => _hoveredIndex = null),
                              child: Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: isFocused 
                                          ? const Color(0xFF007AFF) 
                                          : (isHovered ? const Color(0xFF007AFF).withValues(alpha: 0.3) : Colors.transparent),
                                      width: isFocused ? 1.0 : 0.5,
                                    ),
                                    color: isFocused 
                                        ? Colors.white.withValues(alpha: 0.8) 
                                        : (isHovered ? Colors.white.withValues(alpha: 0.1) : Colors.transparent),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                  child: TextField(
                                    controller: controller,
                                    maxLines: 1,
                                    expands: false,
                                    textAlign: TextAlign.center,
                                    textAlignVertical: TextAlignVertical.center,
                                    style: TextStyle(
                                      fontSize: fontSize, 
                                      color: textColor.withValues(alpha: isFocused ? 1.0 : 0.9), 
                                      fontWeight: FontWeight.w600,
                                    ),
                                    decoration: InputDecoration(
                                      border: InputBorder.none, 
                                      contentPadding: EdgeInsets.only(
                                        bottom: ((uiHeight - fontSize) / 2).clamp(0.0, uiHeight),
                                      ), 
                                      isDense: true,
                                    ),
                                    onChanged: (val) => _currentPage.nodes[idx]['text'] = val,
                                    onTap: () => setState(() => _focusedIndex = idx),
                                  ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomStatusBar() {
    return Container(
      height: 48, padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.black.withValues(alpha: 0.1), width: 0.5))),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, size: 14, color: Colors.grey),
          const SizedBox(width: 8),
          const Text("SlideRev v0.9.6.21 Ready", style: TextStyle(fontSize: 11, color: Colors.grey)),
          const Spacer(),
          const Icon(Icons.auto_fix_normal, size: 14, color: Colors.grey),
          const SizedBox(width: 4),
          const Text("OCR High Sensitivity Active", style: TextStyle(fontSize: 10, color: Colors.grey)),
          const VerticalDivider(width: 32, indent: 12, endIndent: 12),
          const SizedBox(width: 16),
          _buildStatusBarIconButton(Icons.chevron_left, onPressed: () => _changePage(_currentIndex - 1)),
          const SizedBox(width: 8),
          Text("${_currentIndex + 1} / ${widget.pages.length}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          const SizedBox(width: 8),
          _buildStatusBarIconButton(Icons.chevron_right, onPressed: () => _changePage(_currentIndex + 1)),
          const SizedBox(width: 16),
          _buildStatusBarIconButton(Icons.remove_circle_outline, onPressed: () => _updateZoom(_zoom - 0.1)),
          SizedBox(width: 80, child: Slider(value: _zoom.clamp(0.1, 3.0), min: 0.1, max: 3.0, onChanged: (v) => _updateZoom(v))),
          _buildStatusBarIconButton(Icons.add_circle_outline, onPressed: () => _updateZoom(_zoom + 0.1)),
          const SizedBox(width: 8),
          GestureDetector(onTap: () => _updateZoom(1.0), child: Text("${(_zoom * 100).toInt()}%", style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Widget _buildStatusBarIconButton(IconData icon, {VoidCallback? onPressed}) {
    return GestureDetector(onTap: onPressed, child: Container(width: 24, height: 24, decoration: BoxDecoration(color: const Color(0xFFF0F0F0), borderRadius: BorderRadius.circular(4)), child: Icon(icon, size: 14, color: Colors.grey.shade700)));
  }

  Future<void> _exportPptx() async {
    final originalName = p.basenameWithoutExtension(widget.pdfPath);
    final defaultName = "$originalName.pptx";
    String? outputPath = await FilePicker.saveFile(dialogTitle: 'Save PPTX', fileName: defaultName, type: FileType.custom, allowedExtensions: ['pptx']);
    if (outputPath != null) {
      if (!outputPath.endsWith('.pptx')) outputPath += '.pptx';
      final generator = PptxGenerator();
      final pagesData = widget.pages.map((p) => PptxPageData(
        backgroundImage: p.inpaintedImage ?? p.originalImage, 
        nodes: p.nodes, 
        width: p.width, 
        height: p.height
      )).toList();
      await generator.createPptx(outputPath, pagesData);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PPTX Exported: $outputPath')));
    }
  }

  Future<void> _exportPdf() async {
    final originalName = p.basenameWithoutExtension(widget.pdfPath);
    final defaultName = "${originalName}_Refined.pdf";
    String? outputPath = await FilePicker.saveFile(dialogTitle: 'Save PDF', fileName: defaultName, type: FileType.custom, allowedExtensions: ['pdf']);
    if (outputPath != null) {
      if (!outputPath.endsWith('.pdf')) outputPath += '.pdf';
      final generator = PdfGenerator();
      await generator.createPdf(outputPath, _currentPage.originalImage, _currentPage.nodes);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF Exported: $outputPath')));
    }
  }
}
