import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/dashboard_summary.dart';
import '../models/lexical_analysis.dart';
import '../models/material_item.dart';
import '../providers/material_library_provider.dart';
import '../services/app_session.dart';
import '../services/vocamine_api_client.dart';
import '../widgets/square_progress_indicator.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  final VoidCallback onImportMaterial;
  final int refreshRequest;

  const DashboardScreen({
    super.key,
    required this.onImportMaterial,
    required this.refreshRequest,
  });

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  final _api = VocamineApiClient();
  DashboardSummary? _summary;
  String? _recentMaterialId;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshRequest != oldWidget.refreshRequest) {
      _load();
    }
  }

  Future<void> _load() async {
    final userId = ref.read(appSessionProvider).userId;
    if (userId.isEmpty || userId == 'guest') return;
    if (mounted) setState(() => _loading = true);
    try {
      await ref.read(materialLibraryProvider.notifier).load();
      final summary = await _api.fetchDashboard(userId: userId);
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _recentMaterialId = summary.recentMaterialId;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(appSessionProvider);
    final library = ref.watch(materialLibraryProvider);
    MaterialItem? recentMaterial;
    for (final material in library.materials) {
      if (material.id == _recentMaterialId) {
        recentMaterial = material;
        break;
      }
    }
    final name = session.username?.trim().isNotEmpty == true
        ? session.username!.trim()
        : 'ユーザー';

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        return Scaffold(
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  compact ? 16 : 32,
                  compact ? 20 : 30,
                  compact ? 16 : 32,
                  48,
                ),
                children: [
                  Text(
                    'こんにちは、$nameさん',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A2B3C),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '今日も、ことばを少しずつ積み重ねていきましょう。',
                    style: TextStyle(color: Color(0xFF626970)),
                  ),
                  const SizedBox(height: 30),
                  if (_error != null && _summary == null)
                    _ErrorCard(onRetry: _load)
                  else
                    _ProgressCard(summary: _summary, isLoading: _loading),
                  const SizedBox(height: 28),
                  Text(
                    '直近で開いた教材',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A2B3C),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (recentMaterial == null && _loading)
                    const _LoadingMaterialCard()
                  else if (recentMaterial == null)
                    _EmptyMaterialCard(onImport: widget.onImportMaterial)
                  else
                    _RecentMaterialCard(
                      material: recentMaterial,
                      analysis: library.analyses[recentMaterial.id]?.value,
                      onTap: () => context.push(
                        '/materials/detail',
                        extra: {
                          'materialId': recentMaterial!.id,
                          'title': recentMaterial.title,
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ProgressCard extends StatelessWidget {
  final DashboardSummary? summary;
  final bool isLoading;

  const _ProgressCard({required this.summary, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 760;
    final learned = _WordHistory(
      title: '最近学習済みにした単語',
      countLabel: '学習済み単語',
      count: summary?.learnedCount,
      words: summary?.recentLearned ?? const [],
      isLoading: isLoading && summary == null,
      accent: const Color(0xFF1A5C94),
    );
    final registered = _WordHistory(
      title: '最近登録した単語',
      countLabel: '単語帳への登録語彙',
      count: summary?.registeredCount,
      words: summary?.recentRegistered ?? const [],
      isLoading: isLoading && summary == null,
      accent: const Color(0xFFC9A900),
    );
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFD7DCE1)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x160B1C2C),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: narrow
          ? Column(children: [learned, const SizedBox(height: 28), registered])
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: learned),
                const SizedBox(width: 28),
                Container(
                  width: 1,
                  height: 230,
                  color: const Color(0xFFE0E4E8),
                ),
                const SizedBox(width: 28),
                Expanded(child: registered),
              ],
            ),
    );
  }
}

class _WordHistory extends StatelessWidget {
  final String title;
  final String countLabel;
  final int? count;
  final List<DashboardWord> words;
  final Color accent;
  final bool isLoading;

  const _WordHistory({
    required this.title,
    required this.countLabel,
    required this.count,
    required this.words,
    required this.accent,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(countLabel, style: const TextStyle(color: Color(0xFF626970))),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              count == null ? '--' : '$count',
              style: TextStyle(
                fontSize: 38,
                height: 1.1,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(left: 6, bottom: 5),
              child: Text('語'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 25),
            child: LinearProgressIndicator(minHeight: 3),
          )
        else if (words.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Text('まだありません', style: TextStyle(color: Color(0xFF777D84))),
          )
        else
          ...words
              .take(3)
              .map(
                (word) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          word.headword,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        flex: 3,
                        child: Text(
                          word.meaningJa,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Color(0xFF626970)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ],
    );
  }
}

class _RecentMaterialCard extends StatelessWidget {
  final MaterialItem material;
  final ExtractWordsResult? analysis;
  final VoidCallback onTap;

  const _RecentMaterialCard({
    required this.material,
    required this.analysis,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final preview = material.sourcePageImages.isEmpty
        ? null
        : material.sourcePageImages.first;
    final coverage = analysis == null
        ? null
        : (analysis!.coverageRate * 100).round();
    final decoration = BoxDecoration(
      color: Colors.white,
      border: Border.all(color: const Color(0xFFD2D8DE)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x180B1C2C),
          blurRadius: 20,
          offset: Offset(0, 7),
        ),
      ],
    );
    final meter = SquareProgressIndicator(
      value: (coverage ?? 0) / 100,
      size: 126,
      strokeWidth: 10,
      color: const Color(0xFF68ABFF),
      backgroundColor: const Color(0xFFD3DCE6),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: coverage == null ? '--' : '$coverage',
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w800,
                color: Color(0xFF68ABFF),
              ),
            ),
            const TextSpan(
              text: '%',
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A2B3C),
              ),
            ),
          ],
        ),
      ),
    );
    const coverageLabel = Text(
      '習得語彙率',
      style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF1A2B3C)),
    );
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'RECENT MATERIAL',
          style: TextStyle(
            fontSize: 12,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A5C94),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          material.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final previewWidth = (constraints.maxWidth * .42).clamp(280.0, 500.0);
        final meterWidth = constraints.maxWidth < 1100 ? 180.0 : 220.0;
        final compactPreviewHeight = (constraints.maxWidth * .56).clamp(
          160.0,
          240.0,
        );
        return InkWell(
          onTap: onTap,
          child: Container(
            height: compact ? null : 250,
            decoration: decoration,
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: compactPreviewHeight,
                        child: _MaterialPreview(bytes: preview),
                      ),
                      Padding(padding: const EdgeInsets.all(20), child: title),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Transform.scale(scale: .82, child: meter),
                            const SizedBox(width: 8),
                            coverageLabel,
                          ],
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      SizedBox(
                        width: previewWidth,
                        child: _MaterialPreview(bytes: preview),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(30),
                          child: title,
                        ),
                      ),
                      Container(
                        width: meterWidth,
                        height: double.infinity,
                        color: Colors.white,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            meter,
                            const SizedBox(height: 14),
                            coverageLabel,
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _MaterialPreview extends StatelessWidget {
  final Uint8List? bytes;

  const _MaterialPreview({this.bytes});

  @override
  Widget build(BuildContext context) {
    if (bytes == null) {
      return const ColoredBox(
        color: Color(0xFFD4E3FF),
        child: Center(
          child: Text(
            'MATERIAL',
            style: TextStyle(letterSpacing: 2, color: Color(0xFF1A2B3C)),
          ),
        ),
      );
    }
    return ClipRect(
      child: Image.memory(
        bytes!,
        fit: BoxFit.cover,
        alignment: Alignment.topLeft,
      ),
    );
  }
}

class _EmptyMaterialCard extends StatelessWidget {
  final VoidCallback onImport;

  const _EmptyMaterialCard({required this.onImport});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 34),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F7FA),
          border: Border.all(color: const Color(0xFFD2D8DE)),
        ),
        child: constraints.maxWidth < 600
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _EmptyMaterialMessage(),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: onImport,
                    child: const Text('教材を読み込む'),
                  ),
                ],
              )
            : Row(
                children: [
                  const Expanded(child: _EmptyMaterialMessage()),
                  const SizedBox(width: 24),
                  FilledButton(
                    onPressed: onImport,
                    child: const Text('教材を読み込む'),
                  ),
                ],
              ),
      ),
    );
  }
}

class _EmptyMaterialMessage extends StatelessWidget {
  const _EmptyMaterialMessage();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '最初の教材を読み込みましょう',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 8),
        Text(
          'PDFまたは画像から教材を登録すると、語彙の抽出と学習を始められます。',
          style: TextStyle(color: Color(0xFF626970)),
        ),
      ],
    );
  }
}

class _LoadingMaterialCard extends StatelessWidget {
  const _LoadingMaterialCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 250,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFD2D8DE)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x180B1C2C),
            blurRadius: 20,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'RECENT MATERIAL',
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A5C94),
            ),
          ),
          SizedBox(height: 20),
          LinearProgressIndicator(minHeight: 3),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final Future<void> Function() onRetry;

  const _ErrorCard({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFD2D8DE)),
      ),
      child: Row(
        children: [
          const Expanded(child: Text('学習状況を読み込めませんでした。')),
          TextButton(onPressed: onRetry, child: const Text('再読み込み')),
        ],
      ),
    );
  }
}
