class DiaryEntry {
  final int? id;
  final int? scheduleId;

  /// 추천 장소에서 기록 진입 시 연결되는 장소 id. (Phase 2 UGC 집계 기준)
  final int? placeId;
  final String authorInitials;
  final String title;
  final DateTime date;
  final String location;
  final String moodLabel;
  final String weatherLabel;
  final List<String> photos;
  final String body;

  const DiaryEntry({
    this.id,
    this.scheduleId,
    this.placeId,
    required this.authorInitials,
    required this.title,
    required this.date,
    required this.location,
    required this.moodLabel,
    required this.weatherLabel,
    required this.photos,
    required this.body,
  });

  /// 표시용 날짜 ("Jan 21")
  String get dateLabel {
    const m = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${m[date.month - 1]} ${date.day}';
  }

  /// JSON → DiaryEntry
  factory DiaryEntry.fromJson(Map<String, dynamic> json) {
    final journey = json['journey'] ?? {};

    return DiaryEntry(
      id: journey['id'] ?? 0,
      scheduleId: journey['scheduleId'],
      placeId: journey['placeId'],
      authorInitials: _initials(journey['userNickname'] ?? ''),
      title: journey['title'] ?? '',
      date: DateTime.tryParse(journey['date'] ?? '') ?? DateTime.now(),
      location: journey['location'] ?? '',
      moodLabel: journey['moodLabel'] ?? '',
      weatherLabel: journey['weatherLabel'] ?? '',
      photos: List<String>.from(journey['photos'] ?? []),
      body: journey['body'] ?? '',
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return parts.map((p) => p.substring(0, 1).toUpperCase()).join();
  }

  /// DiaryEntry → JSON
  Map<String, dynamic> toJson({bool includeId = true}) {
    final map = <String, dynamic>{
      if (scheduleId != null) 'scheduleId': scheduleId,
      if (placeId != null) 'placeId': placeId,
      'authorInitials': authorInitials,
      'title': title,
      'date': date.toIso8601String(),
      'location': location,
      'moodLabel': moodLabel,
      'weatherLabel': weatherLabel,
      'photos': photos,
      'body': body,
    };

    if (includeId) {
      map['id'] = id;
    }

    return map;
  }

  DiaryEntry copyWith({
    int? id,
    int? scheduleId,
    int? placeId,
    String? authorInitials,
    String? title,
    DateTime? date,
    String? location,
    String? moodLabel,
    String? weatherLabel,
    List<String>? photos,
    String? body,
  }) {
    return DiaryEntry(
      id: id ?? this.id,
      scheduleId: scheduleId ?? this.scheduleId,
      placeId: placeId ?? this.placeId,
      authorInitials: authorInitials ?? this.authorInitials,
      title: title ?? this.title,
      date: date ?? this.date,
      location: location ?? this.location,
      moodLabel: moodLabel ?? this.moodLabel,
      weatherLabel: weatherLabel ?? this.weatherLabel,
      photos: photos ?? this.photos,
      body: body ?? this.body,
    );
  }
}
