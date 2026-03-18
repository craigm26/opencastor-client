/// Model for a community config/skill/harness from the OpenCastor Hub.
class HubConfig {
  const HubConfig({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.tags,
    required this.hardware,
    required this.rcanVersion,
    required this.provider,
    required this.filename,
    required this.authorName,
    required this.stars,
    required this.installs,
    this.content,
    this.robotRrn,
    this.isPublic = true,
    this.forkedFrom,
    this.commentCount = 0,
    this.forks = 0,
    this.isOfficial = false,
  });

  final String id;
  final String type; // "preset" | "skill" | "harness"
  final String title;
  final String description;
  final List<String> tags;
  final String hardware;
  final String rcanVersion;
  final String provider;
  final String filename;
  final String authorName;
  final int stars;
  final int installs;
  final String? content;
  final String? robotRrn;
  final bool isPublic;
  final String? forkedFrom;
  final int commentCount;
  final int forks;
  final bool isOfficial;

  String get installCmd => 'castor install opencastor.com/config/$id';
  String get webUrl => 'https://opencastor.com/config/$id';

  factory HubConfig.fromMap(Map<String, dynamic> map) => HubConfig(
        id: map['id'] as String? ?? '',
        type: map['type'] as String? ?? 'preset',
        title: map['title'] as String? ?? '',
        description: map['description'] as String? ?? '',
        tags: List<String>.from(map['tags'] as List? ?? []),
        hardware: map['hardware'] as String? ?? '',
        rcanVersion: map['rcan_version'] as String? ?? '?',
        provider: map['provider'] as String? ?? '',
        filename: map['filename'] as String? ?? '',
        authorName: map['author_name'] as String? ?? 'community',
        stars: (map['stars'] as num?)?.toInt() ?? 0,
        installs: (map['installs'] as num?)?.toInt() ?? 0,
        content: map['content'] as String?,
        robotRrn: map['robot_rrn'] as String?,
        isPublic: map['public'] as bool? ?? true,
        forkedFrom: map['forked_from'] as String?,
        commentCount: (map['comment_count'] as num?)?.toInt() ?? 0,
        forks: (map['forks'] as num?)?.toInt() ?? 0,
        isOfficial: map['official'] as bool? ?? false,
      );
}
