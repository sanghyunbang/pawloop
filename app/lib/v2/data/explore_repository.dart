import 'api_client.dart';

/// 공개 탐색 API(/api/explore/places)의 실제 장소.
/// Tour 장소 모델이라 A→B/호전율은 없고 제목·이미지·카테고리·지역만 있다.
class RemotePlace {
  final int contentId;
  final int? contentTypeId;
  final String title;
  final String region; // addr1
  final String? cat;   // cat3Name
  final String image;  // firstimage (빈 문자열 가능)

  const RemotePlace({
    required this.contentId,
    required this.title,
    required this.region,
    required this.image,
    this.contentTypeId,
    this.cat,
  });

  /// 카테고리 표시: cat3Name 우선, 없으면 contentTypeId 라벨.
  String get categoryLabel => (cat != null && cat!.isNotEmpty) ? cat! : _typeLabel(contentTypeId);

  static String _typeLabel(int? t) {
    switch (t) {
      case 12: return '관광지';
      case 14: return '문화시설';
      case 15: return '축제·공연';
      case 25: return '여행코스';
      case 28: return '레포츠';
      case 32: return '숙박';
      case 38: return '쇼핑';
      case 39: return '음식';
      default: return '장소';
    }
  }

  static int? _toInt(dynamic v) => v == null ? null : (v is int ? v : int.tryParse('$v'));

  factory RemotePlace.fromJson(Map<String, dynamic> j) {
    final addr1 = (j['addr1'] as String?)?.trim() ?? '';
    return RemotePlace(
      contentId: _toInt(j['contentid']) ?? 0,
      contentTypeId: _toInt(j['contenttypeid'] ?? j['contentTypeId'] ?? j['content_type_id']),
      title: (j['title'] as String?)?.trim() ?? '',
      region: addr1,
      cat: j['cat3Name'] as String?,
      image: (j['firstimage'] as String?)?.trim() ?? '',
    );
  }
}

/// 탐색 장소 리포지토리 — 공개 API. 실패하면 예외를 던지고, 화면이 더미로 폴백한다.
class ExploreRepository {
  Future<List<RemotePlace>> fetchPlaces({String? cursor, int size = 20}) async {
    final json = await V2Api.getJson('/api/explore/places/scroll', query: {
      'size': '$size',
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    });
    final items = (json is Map && json['items'] is List) ? json['items'] as List : const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(RemotePlace.fromJson)
        .where((p) => p.title.isNotEmpty)
        .toList();
  }
}
