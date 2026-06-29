/// 감정 지도용 장소 (백엔드 `GET /api/curation/places/emotion-map` 응답 1건).
class EmotionMapPlace {
  final int placeId;
  final String name;
  final double lat;
  final double lng;
  final String? cat3;
  final String? firstImageUrl;

  /// 지배 감정(한글 SSOT 키). null이면 지도에 표시하지 않음.
  final String? dominantEmotion;

  /// true=UGC(사용자 기록 집계) 기반, false=시드(공공데이터) 기반.
  final bool exposable;
  final int ugcCount;

  /// 검색/거리 응답에만 채워짐(없으면 null).
  final double? distanceKm;
  final double? moodScore;

  const EmotionMapPlace({
    required this.placeId,
    required this.name,
    required this.lat,
    required this.lng,
    required this.dominantEmotion,
    required this.exposable,
    required this.ugcCount,
    this.cat3,
    this.firstImageUrl,
    this.distanceKm,
    this.moodScore,
  });

  factory EmotionMapPlace.fromJson(Map<String, dynamic> j) => EmotionMapPlace(
        placeId: (j['placeId'] as num).toInt(),
        name: (j['name'] ?? '') as String,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        cat3: j['cat3'] as String?,
        firstImageUrl: j['firstImageUrl'] as String?,
        dominantEmotion: j['dominantEmotion'] as String?,
        exposable: j['exposable'] == true,
        ugcCount: (j['ugcCount'] as num?)?.toInt() ?? 0,
        distanceKm: (j['distanceKm'] as num?)?.toDouble(),
        moodScore: (j['moodScore'] as num?)?.toDouble(),
      );
}
