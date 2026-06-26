import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class MaterialReaderScreen extends StatefulWidget {
  const MaterialReaderScreen({super.key});

  @override
  State<MaterialReaderScreen> createState() => _MaterialReaderScreenState();
}

class _MaterialReaderScreenState extends State<MaterialReaderScreen> {
  String? _ocrText;
  bool _loading = false;

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;
    setState(() => _loading = true);
    // TODO: OCR APIに画像を送信してテキストを取得
    await Future.delayed(const Duration(seconds: 1)); // 仮
    setState(() {
      _ocrText = '（ここにOCR結果が表示されます）';
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('教材を読み込む')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _pickImage,
                  icon: const Icon(Icons.photo_library),
                  label: const Text('写真を選ぶ'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () {}, // TODO: PDF選択
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('PDFを選ぶ'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_loading) const CircularProgressIndicator(),
            if (_ocrText != null)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    _ocrText!,
                    style: const TextStyle(fontSize: 16, height: 1.8),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}