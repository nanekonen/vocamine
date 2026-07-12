class DashboardWord {
  final String id;
  final String headword;
  final String meaningJa;
  final String partOfSpeech;

  const DashboardWord({
    required this.id,
    required this.headword,
    required this.meaningJa,
    required this.partOfSpeech,
  });

  factory DashboardWord.fromJson(Map<String, dynamic> json) {
    return DashboardWord(
      id: json['id'] as String? ?? '',
      headword: json['headword'] as String? ?? '',
      meaningJa: json['meaning_ja'] as String? ?? '',
      partOfSpeech: json['part_of_speech'] as String? ?? '',
    );
  }
}

class DashboardSummary {
  final int learnedCount;
  final int registeredCount;
  final List<DashboardWord> recentLearned;
  final List<DashboardWord> recentRegistered;
  final String? recentMaterialId;

  const DashboardSummary({
    required this.learnedCount,
    required this.registeredCount,
    required this.recentLearned,
    required this.recentRegistered,
    this.recentMaterialId,
  });

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    List<DashboardWord> words(String key) => (json[key] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(DashboardWord.fromJson)
        .toList();

    return DashboardSummary(
      learnedCount: json['learned_count'] as int? ?? 0,
      registeredCount: json['registered_count'] as int? ?? 0,
      recentLearned: words('recent_learned'),
      recentRegistered: words('recent_registered'),
      recentMaterialId: json['recent_material_id'] as String?,
    );
  }
}
