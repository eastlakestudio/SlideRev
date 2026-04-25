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
        fontFamily: 'Segoe UI', // Windows default modern font
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

enum AppState { dashboard, processing, finished }

class _MainDesktopWindowState extends State<MainDesktopWindow> {
  bool _isHoveringDashboard = false;
  String? _selectedFilePath;
  AppState _appState = AppState.dashboard;
  String _statusText = "Initializing AI Engine...";
  double _progress = 0.0;

  Future<void> _onImportPdf() async {
    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'heic', 'tiff'],
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        _selectedFilePath = result.files.single.path;
        _appState = AppState.processing;
      });
      AppLogger.d('Main', 'Selected file: $_selectedFilePath');
      if (!mounted) return;
      // 真正开始处理流程
      await _processDocument();
    }
  }

  Future<void> _processDocument() async {
    if (_selectedFilePath == null) return;

    try {
      // 1. 初始化模型 (双保险方案：优先文件加载，失败自动降级到内存加载)
      setState(() { _statusText = "Loading AI Models..."; _progress = 0.1; });
      AppLogger.d('Main', 'Step 1: Extracting models to local temp...');
      final ocrModelPath = await ModelManager().getLocalModelPath('assets/models/ocr_model.onnx');
      final lamaModelPath = await ModelManager().getLocalModelPath('assets/models/lama_fp32.onnx');
      
      final ocrAdapter = VisionOcrAdapter();
      final lamaEngine = LamaInpaintingEngine();
      
      await ocrAdapter.init(ocrModelPath);
      await lamaEngine.init(lamaModelPath);

      // 2. 渲染 PDF 页面
      setState(() { _statusText = "Rendering Document..."; _progress = 0.3; });
      final pdfEngine = PdfEngine();
      final pageImage = await pdfEngine.renderPageToImage(_selectedFilePath!, 1);
      if (pageImage == null) throw Exception("Failed to render PDF");

      // 3. 执行 OCR 识别
      setState(() { _statusText = "Running OCR Recognition..."; _progress = 0.6; });
      final nodes = await ocrAdapter.recognizeText(pageImage.bytes);

      // 4. 执行背景修复 (暂时跳过复杂的 Mask 构造逻辑，直接进入功能页)
      setState(() { _statusText = "Finalizing Workspace..."; _progress = 0.9; });
      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;
      
      // 5. 跳转到功能编辑页面
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => RefinementPage(
            imageBytes: pageImage.bytes,
            initialNodes: nodes,
            width: pageImage.width!.toDouble(),
            height: pageImage.height!.toDouble(),
          ),
        ),
      );

      setState(() {
        _appState = AppState.dashboard; // 回到首页状态，因为已经 Push 了新页面
      });
      AppLogger.d('Main', 'Process finished and pushed RefinementPage');
      
    } catch (e, stack) {
      AppLogger.e('Main', 'Error in _processDocument', e, stack);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Processing Error: $e'), backgroundColor: Colors.red),
      );
      _reset();
    }
  }

  void _reset() {
    setState(() {
      _appState = AppState.dashboard;
      _selectedFilePath = null;
      _progress = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Stack(
        children: [
          // 背景装饰
          Positioned.fill(
            child: Opacity(
              opacity: 0.03,
              child: CustomPaint(painter: GridPainter()),
            ),
          ),

          if (_appState == AppState.dashboard)
            _buildDashboard()
          else if (_appState == AppState.processing)
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
          // 标题区
          _buildHeader(),
          const SizedBox(height: 40),

          // 核心引导卡片
          MouseRegion(
            onEnter: (_) => setState(() => _isHoveringDashboard = true),
            onExit: (_) => setState(() => _isHoveringDashboard = false),
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: _onImportPdf,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
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
                    // 顶部视觉连线动画
                    Positioned(
                      top: 40,
                      left: 0,
                      right: 0,
                      child: AnimatedOpacity(
                        opacity: _isHoveringDashboard ? 0.4 : 0.6,
                        duration: const Duration(milliseconds: 300),
                        child: Transform.scale(
                          scale: 0.9,
                          child: const GraphicProcessView(),
                        ),
                      ),
                    ),

                    // 中间文字描述
                    _buildDashboardText(),

                    // 底部大圆圈 Plus 图标
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
        const Text(
          "SlideRev...",
          style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Column(
          children: [
            Text(
              "Professional AI Slide Reconstructor",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "Unlock Your NotebookLM Citations & AI Images",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 540,
              child: Text(
                "Transform flat PDFs and AI-generated snapshots back to professional, fully editable PPTX slides.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Seamlessly convert screenshots, mobile captures, and citations into vectorized PPTX elements.",
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDashboardText() {
    return Positioned(
      bottom: 120,
      left: 0,
      right: 0,
      child: Column(
        children: [
          Text(
            "Import PDF, Images or NotebookLM Citations",
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.touch_app, size: 16, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
              const SizedBox(width: 6),
              Text(
                "Click to transform your documents into editable PPTX",
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              "Supported: PDF, PNG, JPG, JPEG, HEIC, TIFF",
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'Consolas',
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlusIcon() {
    return Positioned(
      bottom: 30,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutBack,
          transform: Matrix4.diagonal3Values(
            _isHoveringDashboard ? 1.1 : 1.0,
            _isHoveringDashboard ? 1.1 : 1.0,
            1.0,
          ),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Theme.of(context).colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: _isHoveringDashboard ? 0.3 : 0.1),
                blurRadius: _isHoveringDashboard ? 15 : 5,
                spreadRadius: 2,
              )
            ],
          ),
          child: Icon(
            Icons.add_circle,
            size: 80,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildProcessingView() {
    return Center(
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 40,
              offset: const Offset(0, 20),
            )
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(strokeWidth: 3),
            const SizedBox(height: 32),
            Text(
              _statusText,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              _selectedFilePath?.split('\\').last ?? "File",
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
            ),
            const SizedBox(height: 32),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _progress,
                minHeight: 8,
                backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Removed unused _buildFinishedView


  Widget _buildActionButton({required IconData icon, required String label, required VoidCallback onPressed, bool primary = false}) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        backgroundColor: primary ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surface,
        foregroundColor: primary ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 0.5;

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

// 模拟原生的三个圆圈动画连接图
class GraphicProcessView extends StatefulWidget {
  const GraphicProcessView({super.key});

  @override
  State<GraphicProcessView> createState() => _GraphicProcessViewState();
}

class _GraphicProcessViewState extends State<GraphicProcessView> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _CircleNode(icon: Icons.image, label: "AI Image", color: Colors.grey),
        _ArrowLine(animation: _controller),
        _CircleNode(icon: Icons.auto_awesome, label: "SlideRev AI", color: Colors.blueAccent, pulse: true),
        _ArrowLine(animation: _controller),
        _CircleNode(icon: Icons.slideshow, label: "Editable PPTX", color: Colors.orange),
      ],
    );
  }
}

class _CircleNode extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool pulse;

  const _CircleNode({required this.icon, required this.label, required this.color, this.pulse = false});

  @override
  State<_CircleNode> createState() => _CircleNodeState();
}

class _CircleNodeState extends State<_CircleNode> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 1));
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
    if (widget.pulse) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ScaleTransition(
          scale: _scaleAnimation,
          child: Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withValues(alpha: 0.12),
            ),
            child: Icon(widget.icon, size: 32, color: widget.color.withValues(alpha: 0.9)),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          widget.label,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade500),
        ),
      ],
    );
  }
}

class _ArrowLine extends StatelessWidget {
  final Animation<double> animation;

  const _ArrowLine({required this.animation});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      width: 50,
      height: 70,
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(width: 50, height: 2, color: Colors.grey.withValues(alpha: 0.2)),
            AnimatedBuilder(
              animation: animation,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(-25 + (animation.value * 50), 0),
                  child: Opacity(
                    opacity: 1.0 - animation.value,
                    child: const Icon(Icons.chevron_right, size: 16, color: Colors.blueAccent),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
