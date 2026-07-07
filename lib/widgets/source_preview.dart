import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../models/material_item.dart';

class SourcePreview extends StatelessWidget {
  final Uint8List bytes;
  final String mimeType;
  final List<Uint8List> pageImages;
  final List<SourceWordBox> wordBoxes;
  final ValueChanged<String>? onWordLongPress;

  const SourcePreview({
    super.key,
    required this.bytes,
    required this.mimeType,
    this.pageImages = const [],
    this.wordBoxes = const [],
    this.onWordLongPress,
  });

  @override
  Widget build(BuildContext context) {
    if (mimeType.startsWith('image/')) {
      return InteractiveViewer(
        child: Center(
          child: _PreviewPage(
            imageBytes: bytes,
            boxes: wordBoxes.where((box) => box.pageIndex == 0).toList(),
            onWordLongPress: onWordLongPress,
          ),
        ),
      );
    }
    if (mimeType == 'application/pdf' && pageImages.isNotEmpty) {
      return ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: pageImages.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          return DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade300),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 8,
                  color: Color(0x1F000000),
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: _PreviewPage(
              imageBytes: pageImages[index],
              boxes: wordBoxes.where((box) => box.pageIndex == index).toList(),
              onWordLongPress: onWordLongPress,
            ),
          );
        },
      );
    }
    return const Center(child: Text('PDFプレビューを生成できませんでした'));
  }
}

class _PreviewPage extends StatelessWidget {
  final Uint8List imageBytes;
  final List<SourceWordBox> boxes;
  final ValueChanged<String>? onWordLongPress;

  const _PreviewPage({
    required this.imageBytes,
    required this.boxes,
    required this.onWordLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Image.memory(imageBytes, fit: BoxFit.contain),
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: boxes.map((box) {
                  return Positioned(
                    left: box.left * constraints.maxWidth,
                    top: box.top * constraints.maxHeight,
                    width: box.width * constraints.maxWidth,
                    height: box.height * constraints.maxHeight,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onLongPress: onWordLongPress == null
                          ? null
                          : () => onWordLongPress!(box.text),
                      child: const SizedBox.expand(),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ),
      ],
    );
  }
}
