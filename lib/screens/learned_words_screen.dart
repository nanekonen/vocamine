import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/material_item.dart';
import '../models/word.dart';
import '../providers/material_library_provider.dart';
import '../services/app_session.dart';
import '../services/vocamine_api_client.dart';
import 'word_list_screen.dart';

String _cefrLabelForTier(int tier) {
  switch (tier) {
    case 1:
      return 'CEFR A1';
    case 2:
      return 'CEFR A2';
    case 3:
      return 'CEFR B1';
    case 4:
      return 'CEFR B2';
    default:
      return 'レベル $tier';
  }
}

const _cefrSourceTypes = {
  1: 'initial_level_a1',
  2: 'initial_level_a2',
  3: 'initial_level_b1',
  4: 'initial_level_b2',
};

class LearnedWordsScreen extends ConsumerStatefulWidget {
  const LearnedWordsScreen({super.key});

  @override
  ConsumerState<LearnedWordsScreen> createState() =>
      _LearnedWordsScreenState();
}

class _LearnedWordsScreenState extends ConsumerState<LearnedWordsScreen> {
  final _api = VocamineApiClient();

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(materialLibraryProvider.notifier).load();
    });
  }

  Future<List<Word>> _loadTierWords(int tier) {
    return _api.fetchWordbook(
      userId: ref.read(appSessionProvider).userId,
      isLearned: true,
      sourceType: _cefrSourceTypes[tier],
    );
  }

  Future<List<Word>> _loadMaterialWords(String materialId) {
    return _api.fetchWordbook(
      userId: ref.read(appSessionProvider).userId,
      isLearned: true,
      sourceMaterialId: materialId,
    );
  }

  void _openWordList(
    BuildContext context,
    String title,
    Future<List<Word>> Function() loadWords,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => WordListScreen(title: title, loadWords: loadWords),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final materials = ref.watch(materialLibraryProvider).materials;

    return Scaffold(
      appBar: AppBar(title: const Text('学習済みの単語')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (final tier in const [1, 2, 3, 4])
                _LearnedTile(
                  icon: Icons.school_outlined,
                  title: _cefrLabelForTier(tier),
                  subtitle: null,
                  accentColor: const Color(0xFFC4934E),
                  onTap: () => _openWordList(
                    context,
                    _cefrLabelForTier(tier),
                    () => _loadTierWords(tier),
                  ),
                ),
              for (final MaterialItem material in materials)
                _LearnedTile(
                  icon: Icons.description_outlined,
                  title: material.title,
                  subtitle: null,
                  accentColor: Theme.of(context).colorScheme.primary,
                  onTap: () => _openWordList(
                    context,
                    material.title,
                    () => _loadMaterialWords(material.id),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LearnedTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color accentColor;
  final VoidCallback onTap;

  const _LearnedTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final tileWidth = width >= 1180
        ? 330.0
        : width >= 760
        ? 300.0
        : width - 48;
    return SizedBox(
      width: tileWidth,
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.26),
                    ),
                  ),
                  child: Icon(icon, color: accentColor, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          subtitle!,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}