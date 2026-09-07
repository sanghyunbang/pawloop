// lib/v2/domain/neighborhood.dart
//
// 내가 고른 동네 — 이슈 #342.
//
// ## 왜 좌표가 아니라 코드인가
//
// 위치기반서비스 신고 전이라(#235, A안) 서버가 사용자 위치를 알 수 없다. 그런데 이 앱의
// 이름값은 "동네" 다 — 커뮤니티가 전국 한 줄이면 옆 동네 산책로 후기를 볼 수 없다.
//
// **사용자가 스스로 고른 행정동은 위치정보가 아니다.** 단말이 잰 값이 아니라 사람이 목록에서
// 고른 텍스트이기 때문이다. 서버로는 **코드 열 자리만** 나가고, 중심 좌표는 이 앱이 자기
// 자산에서 읽어 지도에만 쓴다.
//
// ## 어디까지 보이나
//
// 글 카드에는 **구(區)까지만** 보인다. 동까지 보이면 사는 곳이 그만큼 좁혀진다 —
// 서버의 응답에도 동 이름이 없다(`NeighborhoodCatalog`).
library;

/// 행정동 하나. 자산(`assets/regions/hangjeongdong.json`)의 한 줄이다.
class Neighborhood {
  const Neighborhood({
    required this.code,
    required this.sigunguCode,
    required this.sido,
    required this.sigungu,
    required this.dong,
    required this.lat,
    required this.lng,
  });

  /// 통계청 행정동 코드 **열 자리**. 서버로 나가는 유일한 값이다.
  final String code;

  /// 앞 다섯 자리. 커뮤니티의 "우리 동네" 단위다.
  final String sigunguCode;

  final String sido;    // 서울특별시
  final String sigungu; // 성동구
  final String dong;    // 왕십리2동

  /// 중심 좌표. **기기 안에서만 쓴다** — 지도의 첫 화면이 여기로 온다.
  final double lat;
  final double lng;

  /// 화면에 보이는 이름 — "성동구 왕십리2동".
  String get label => '$sigungu $dong';

  /// 남에게 보이는 단위 — "성동구". 글 카드가 이것만 쓴다.
  String get districtLabel => sigungu;

  /// 검색용 — 시도까지 붙인 전체 이름.
  String get fullLabel => '$sido $sigungu $dong';

  Map<String, dynamic> toJson() => {
        'code': code,
        'sigunguCode': sigunguCode,
        'sido': sido,
        'sigungu': sigungu,
        'dong': dong,
        'lat': lat,
        'lng': lng,
      };

  /// 모양이 다르면 `null`. 저장 형식이 바뀌어도 지도가 죽지 않아야 한다.
  static Neighborhood? tryParse(Object? json) {
    if (json is! Map) return null;
    final code = json['code'];
    if (code is! String || code.length != 10) return null;
    final lat = (json['lat'] as num?)?.toDouble();
    final lng = (json['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return Neighborhood(
      code: code,
      sigunguCode: json['sigunguCode'] as String? ?? code.substring(0, 5),
      sido: json['sido'] as String? ?? '',
      sigungu: json['sigungu'] as String? ?? '',
      dong: json['dong'] as String? ?? '',
      lat: lat,
      lng: lng,
    );
  }

  @override
  bool operator ==(Object other) => other is Neighborhood && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'Neighborhood($code $fullLabel)';
}
