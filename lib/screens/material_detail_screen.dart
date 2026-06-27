import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/material_library_provider.dart';

class MaterialDetailScreen extends ConsumerWidget {
  final String materialId;
  final String title;

  const MaterialDetailScreen({super.key, required this.materialId, required this.title});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final materials = ref.watch(materialLibraryProvider).materials;
    final material = materials.firstWhere((m) => m.id == materialId);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              material.ocrText,
              style: const TextStyle(fontSize: 16, height: 1.8),
            ),
          ),
        ),
      ),
    );
  }
}