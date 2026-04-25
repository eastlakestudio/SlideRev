import 'dart:typed_data';
// import 'dart:io'; // Removed unused import
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../core/pptx_generator.dart';
import '../core/pdf_generator.dart';

class RefinementPage extends StatefulWidget {
  final Uint8List imageBytes;
  final List<Map<String, dynamic>> initialNodes;
  final double width;
  final double height;

  const RefinementPage({
    super.key,
    required this.imageBytes,
    required this.initialNodes,
    required this.width,
    required this.height,
  });

  @override
  State<RefinementPage> createState() => _RefinementPageState();
}

class _RefinementPageState extends State<RefinementPage> {
  late List<Map<String, dynamic>> _nodes;

  @override
  void initState() {
    super.initState();
    _nodes = List.from(widget.initialNodes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      appBar: AppBar(
        title: const Text("Refinement Workspace"),
        actions: [
          ElevatedButton.icon(
            onPressed: _exportPptx,
            icon: const Icon(Icons.file_download),
            label: const Text("Export PPTX"),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _exportPdf,
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text("Export PDF"),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white70),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Row(
        children: [
          // 左侧：实时预览区
          Expanded(
            flex: 3,
            child: Container(
              margin: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 20)],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    Image.memory(widget.imageBytes, fit: BoxFit.contain),
                    // 绘制 OCR 矩形框
                    Positioned.fill(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return Stack(
                            children: _nodes.map((node) {
                              final rect = node['rect'] as List<double>;
                              // 转换归一化坐标为像素坐标
                              return Positioned(
                                left: rect[0] * constraints.maxWidth,
                                top: rect[1] * constraints.maxHeight,
                                width: rect[2] * constraints.maxWidth,
                                height: rect[3] * constraints.maxHeight,
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.blueAccent, width: 1),
                                    color: Colors.blueAccent.withValues(alpha: 0.1),
                                  ),
                                ),
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

          // 右侧：属性编辑区
          Container(
            width: 350,
            color: const Color(0xFF252525),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text("Detected Elements", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _nodes.length,
                    itemBuilder: (context, index) {
                      return ListTile(
                        title: TextFormField(
                          initialValue: _nodes[index]['text'],
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (val) {
                            _nodes[index]['text'] = val;
                          },
                        ),
                        subtitle: Text("Position: ${_nodes[index]['rect']}", style: const TextStyle(fontSize: 10, color: Colors.grey)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, size: 18, color: Colors.redAccent),
                          onPressed: () => setState(() => _nodes.removeAt(index)),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
          backgroundImage: widget.imageBytes,
          nodes: _nodes,
          width: widget.width,
          height: widget.height,
        ),
      ]);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PPTX Exported: $outputPath')));
      }
    }
  }

  Future<void> _exportPdf() async {
    String? outputPath = await FilePicker.saveFile(
      dialogTitle: 'Save PDF',
      fileName: 'refined_slides.pdf',
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (outputPath != null) {
      if (!outputPath.endsWith('.pdf')) outputPath += '.pdf';
      final generator = PdfGenerator();
      await generator.createPdf(outputPath, widget.imageBytes, _nodes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF Exported: $outputPath')));
      }
    }
  }
}
