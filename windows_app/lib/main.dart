import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // Required for compute()
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:image/image.dart' as img;
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
  Uint8List? _processingImageBytes;
  bool _isPicking = false; // 防抖标志位

  Future<void> _onImportPdf() async {
    if (_isPicking) return; // 正在选择中，直接拦截
    setState(() => _isPicking = true);

    try {
      AppLogger.d('Main', 'Import PDF/Image button triggered');
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'heic', 'tiff'],
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        AppLogger.d('Main', 'Selected file: $path');
        
        if (!File(path).existsSync()) {
          AppLogger.e('Main', 'File does not exist at path: $path');
          return;
        }

        setState(() {
          _selectedFilePath = path;
          _appState = AppState.processing;
        });
        
        if (!mounted) return;
        await _processDocument();
      }
    } finally {
      if (mounted) {
        setState(() => _isPicking = false); // 无论成败，最后释放锁
      }
    }
  }

  Future<void> _processPage(int pageNumber) async {
    if (_selectedFilePath == null) return;
    try {
      // 1. 初始化模型 (双保险方案：优先文件加载，失败自动降级到内存加载)
      setState(() { _statusText = "Loading AI Models..."; _progress = 0.1; });
      AppLogger.d('Main', 'Step 1: Extracting models to local temp...');
      final detModelPath = await ModelManager().getLocalModelPath('assets/models/ocr_det.onnx');
      final recModelPath = await ModelManager().getLocalModelPath('assets/models/ocr_rec.onnx');
      final keysPath = await ModelManager().getLocalModelPath('assets/models/ppocr_keys_v1.txt');
      final lamaModelPath = await ModelManager().getLocalModelPath('assets/models/lama_fp32.onnx');
      
      final ocrAdapter = VisionOcrAdapter();
      final lamaEngine = LamaInpaintingEngine();
      
      if (!ocrAdapter.isInitialized) await ocrAdapter.init(detModelPath, recModelPath, keysPath);
      if (!lamaEngine.isInitialized) await lamaEngine.init(lamaModelPath);

      // 2. 获取处理所需的图像数据和尺寸
      Uint8List imageBytes;
      double width, height;
      int totalPages = 1;

      final extension = p.extension(_selectedFilePath!).toLowerCase();
      final List<ProcessedPage> processedPages = [];

      if (extension == '.pdf') {
        final pdfEngine = PdfEngine();
        totalPages = await pdfEngine.getPageCount(_selectedFilePath!);
        
        for (int i = 1; i <= totalPages; i++) {
          setState(() { 
            _statusText = "Processing page $i of $totalPages..."; 
            _progress = (i / totalPages) * 0.9; 
          });

          // 1. 渲染当前页
          final pageImage = await pdfEngine.renderPageToImage(_selectedFilePath!, i);
          if (pageImage == null) continue;
          
          setState(() {
            _processingImageBytes = pageImage.bytes;
          });
          
          final pWidth = pageImage.width!.toDouble();
          final pHeight = pageImage.height!.toDouble();

          // 2. OCR 识别与热力图遮罩提取
          final ocrResult = await ocrAdapter.recognizeText(pageImage.bytes);
          final nodes = ocrResult['nodes'] as List<Map<String, dynamic>>;
          final Uint8List? heatmapMask = ocrResult['mask'];
          
          AppLogger.d('Main', 'Page $i OCR finished: Found ${nodes.length} text blocks');

          // 3. 背景修复 (使用 OCR 提供的热力图遮罩)
          Uint8List? inpainted;
          try {
            if (heatmapMask != null) {
              AppLogger.d('Main', 'Page $i: Running LaMa inpainting with heatmap mask (${heatmapMask.length} bytes)');
              inpainted = await lamaEngine.inpaint(pageImage.bytes, heatmapMask);
              AppLogger.d('Main', 'Page $i: Inpainting finished.');
            } else {
              AppLogger.w('Main', 'Page $i: No heatmap mask provided, skipping inpaint.');
            }
          } catch (e) {
            AppLogger.e('Main', 'Page $i inpainting failed: $e');
          }

          processedPages.add(ProcessedPage(
            originalImage: pageImage.bytes,
            inpaintedImage: inpainted,
            nodes: nodes,
            width: pWidth,
            height: pHeight,
          ));
        }
      } else {
        // 单张图片处理
        setState(() { _statusText = "Processing Image..."; _progress = 0.5; });
        final bytes = await File(_selectedFilePath!).readAsBytes();
        final decoded = img.decodeImage(bytes);
        if (decoded != null) {
          setState(() {
            _processingImageBytes = bytes;
          });
          final ocrResult = await ocrAdapter.recognizeText(bytes);
          final nodes = ocrResult['nodes'] as List<Map<String, dynamic>>;
          final Uint8List? heatmapMask = ocrResult['mask'];
          
          Uint8List? inpainted;
          try {
            if (heatmapMask != null) {
              inpainted = await lamaEngine.inpaint(bytes, heatmapMask);
            }
          } catch (_) {}

          processedPages.add(ProcessedPage(
            originalImage: bytes,
            inpaintedImage: inpainted,
            nodes: nodes,
            width: decoded.width.toDouble(),
            height: decoded.height.toDouble(),
          ));
        }
      }

      setState(() { _statusText = "Finalizing Workspace..."; _progress = 1.0; });
      if (!mounted) return;
      
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => RefinementPage(
            pages: processedPages,
            pdfPath: _selectedFilePath!,
            ocrAdapter: ocrAdapter,
            lamaEngine: lamaEngine,
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
      _processingImageBytes = null;
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
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(32),
              child: InkWell(
                onTap: _onImportPdf,
                borderRadius: BorderRadius.circular(32),
                splashColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                highlightColor: Colors.transparent,
                hoverColor: Colors.transparent,
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
                    _buildPlusIcon(),
                  ],
                  ),
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
      child: Container(
        width: 600,
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
            if (_processingImageBytes != null)
              Container(
                height: 300,
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 32),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(_processingImageBytes!, fit: BoxFit.contain),
                      const ScanningOverlay(),
                    ],
                  ),
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.only(bottom: 32),
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
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
}

  // Removed unused _buildFinishedView


  // 辅助函数：在后台 Isolate 生成 Mask
  Future<Uint8List> _generateInpaintMask(Uint8List imageBytes, List<Map<String, dynamic>> nodes, int width, int height) async {
    // 使用 compute 将任务派发到后台 Isolate，避免阻塞 UI 线程
    return await compute(_maskGenerationTask, {
      'nodes': nodes,
      'width': width,
      'height': height,
    });
  }
}

// 必须是顶级函数或静态函数才能被 compute 调用
Uint8List _maskGenerationTask(Map<String, dynamic> params) {
  final List<Map<String, dynamic>> nodes = params['nodes'];
  final int width = params['width'];
  final int height = params['height'];

  final mask = img.Image(width: width, height: height);
  img.fill(mask, color: img.ColorRgb8(0, 0, 0));
  
  for (var node in nodes) {
    final rect = node['rect'] as List<double>;
    final x = (rect[0] * width);
    final y = (rect[1] * height);
    final w = (rect[2] * width);
    final h = (rect[3] * height);
    
    // 进一步扩大 Mask 范围 (增加到 15 像素) 以确保百分之百覆盖文字边缘，彻底杜绝重影
    img.fillRect(mask, 
      x1: (x - 15).toInt().clamp(0, width), 
      y1: (y - 15).toInt().clamp(0, height), 
      x2: (x + w + 15).toInt().clamp(0, width), 
      y2: (y + h + 15).toInt().clamp(0, height), 
      color: img.ColorRgb8(255, 255, 255)
    );
  }
  return Uint8List.fromList(img.encodePng(mask));
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
// 扫描动画叠加层
class ScanningOverlay extends StatefulWidget {
  const ScanningOverlay({super.key});

  @override
  State<ScanningOverlay> createState() => _ScanningOverlayState();
}

class _ScanningOverlayState extends State<ScanningOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _animation = Tween<double>(begin: 0.0, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        return AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            return Stack(
              children: [
                // 扫描线
                Positioned(
                  top: _animation.value * height,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 2,
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(context).colorScheme.primary.withValues(alpha: 0),
                          Theme.of(context).colorScheme.primary,
                          Theme.of(context).colorScheme.primary.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
                // 扫描后的淡蓝色遮罩
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: _animation.value * height,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
                          Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
