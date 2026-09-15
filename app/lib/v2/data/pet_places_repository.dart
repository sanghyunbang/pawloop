import 'dart:convert';
import 'package:http/http.dart' as http;

import 'location_upload_policy.dart';
import 'place_catalog_repository.dart';
import '../../core/config/env.dart';
import '../domain/pet.dart';

/// 반려동반 가능 장소 하나. 계약(`openapi.yaml`)의 `Place` 를 그대로 옮긴다.
///
/// **관광공사를 앱이 직접 부르지 않는다** (이슈 #40). 서비스키가 앱 바이너리 안에 있어야
/// 하는 구조였고, `--dart-define` 으로 옮겨도 문자열은 남아서 `strings` 한 번이면 나온다.
/// 키는 쿼터·과금이 걸린 자격증명이고 폐기하려면 앱을 새로 배포해야 한다 — 즉 즉시 대응이
/// 불가능하다. 지금은 서버가 대신 부르고 결과를 캐시한다.
class PetPlace {
  final String contentId;
  final String title;

  /// 계약의 `source` — `kto` · `vet` · `shop` · `trail` (#291).
  final String source;

  /// 계약의 `category`. KTO 는 여섯 숫자 중 하나이거나 비어 있고(모르는 타입),
  /// 공공데이터 레이어는 `source` 와 같은 값이다.
  final String category;
  final String contentTypeId;

  /// 카드 한 줄 — 산책로 "2.6km · 약 40분 · 쉬움", 판매업 "동물판매업". 없으면 빈 문자열.
  final String summary;

  /// **코스 길이(m)** — 산책로만 온다. 모르면 `null` (#539).
  ///
  /// [summary] 안에 이미 "2.6km" 가 있지만 **문장이라 셈에 못 쓴다.** 오늘의 코스가
  /// "목표 2.0km" 에 가까운 코스를 고르는 데 쓰는 값이 이것이다 — 이 값이 안 오던 동안
  /// 점수의 길이 항이 죽어 있어서 추천이 그냥 **가까운 순**이었다.
  final int? courseM;
  final String addr;
  final String image;
  final String tel;
  final double lat;
  final double lng;
  final double distM; // locationBasedList2의 거리(m)

  const PetPlace({
    required this.contentId,
    required this.title,
    this.source = 'kto',
    this.category = '',
    required this.contentTypeId,
    this.summary = '',
    this.courseM,
    required this.addr,
    required this.image,
    required this.tel,
    required this.lat,
    required this.lng,
    this.distM = 0,
  });

  /// 필터와 아이콘이 보는 키 — `contentTypeId` 가 있으면 그것, 없으면 `category` (#291).
  ///
  /// 서버의 `PlaceDto.categoryKey()` 와 같은 규칙이다. 갈리면 서버가 거른 것과 앱이
  /// 그리는 것이 다른 칩이 된다. KTO 는 전자, 병원·펫샵·산책로는 후자다.
  String get categoryKey => contentTypeId.isNotEmpty ? contentTypeId : category;

  PetCategory get petCategory => petCatByType(categoryKey);

  /// 산책로인가 — 두루누비와 동네 길(#346)이 같은 칩을 쓴다.
  bool get isTrail => source == 'trail';

  /// 동네 길인가 — 전국길관광정보표준데이터에서 온 것(#346). `contentId` 가 `trail:lt…` 다.
  bool get isLocalTrail => contentId.startsWith('trail:lt');

  /// **선을 받을 수 있는가.** 두루누비만 GPX 가 있다.
  ///
  /// 동네 길의 원본에는 좌표가 아예 없고 경로가 `보신각 → 보성사 터` 꼴의 **글**이라
  /// 그릴 선이 없다. 이걸 안 가르면 "지도에서 보기" 를 눌렀을 때 서버가 404 를 준다 —
  /// 2026-09-08 에뮬레이터에서 실제로 그랬다.
  bool get hasTrailRoute => isTrail && !isLocalTrail;

  /// 산책로 선을 받을 때 쓰는 코스 번호 — `contentId` 의 `trail:` 뒤.
  String get trailCourseId =>
      contentId.startsWith('trail:') ? contentId.substring('trail:'.length) : contentId;

  /// 출처 배지 문구. 데이터를 어디서 가져왔는지 사용자에게 말한다.
  String get sourceLabel => switch (source) {
        'vet' => '동물병원 · 행정안전부 인허가',
        'shop' => '동물판매업 · 행정안전부 인허가',
        'trail' => isLocalTrail
            ? '동네 길 · 지자체(공공데이터포털)'
            : '걷기여행길 · 두루누비(한국관광공사)',
        'playground' => '반려견 놀이터 · 지자체(공공데이터포털)',
        _ => '반려동물 동반 가능 (관광공사)',
      };

  /// 거리를 채운 사본. **기기에서 잰 값을 담는 자리다** (이슈 #273).
  ///
  /// 서버의 `PlaceDto.withDistance` 와 짝이다. 카탈로그 응답에는 `distM` 이 아예 없다 —
  /// 서버가 그 값을 계산할 좌표를 갖고 있지 않기 때문이다.
  PetPlace withDistance(double meters) => PetPlace(
        contentId: contentId,
        title: title,
        source: source,
        category: category,
        contentTypeId: contentTypeId,
        summary: summary,
        // 여기서 떨어뜨리면 카탈로그에는 있는데 추천에는 안 가는 값이 된다 — 서버의
        // `PlaceDto.withDistance` 도 같은 자리에서 같은 실수를 할 수 있다(#539).
        courseM: courseM,
        addr: addr,
        image: image,
        tel: tel,
        lat: lat,
        lng: lng,
        distM: meters,
      );

  String get distLabel =>
      distM <= 0 ? '' : (distM < 1000 ? '${distM.round()}m' : '${(distM / 1000).toStringAsFixed(1)}km');

  /// 서버 응답 하나를 읽는다.
  ///
  /// **키 이름이 KTO 의 것이 아니라 우리 계약의 것이다** — `contentid`/`mapx`/`firstimage`
  /// 가 아니라 `contentId`/`lng`/`image` 다. KTO 의 모양을 해석하는 일은 서버가 한다
  /// (이슈 #40). 여기서 그것을 또 알면 해석이 두 곳에 살게 되고, 한쪽만 고치면 조용히
  /// 갈라진다.
  factory PetPlace.fromJson(Map<String, dynamic> j) => PetPlace(
        contentId: '${j['contentId'] ?? ''}',
        title: '${j['title'] ?? ''}',
        source: '${j['source'] ?? 'kto'}',
        category: '${j['category'] ?? ''}',
        contentTypeId: '${j['contentTypeId'] ?? ''}',
        summary: '${j['summary'] ?? ''}',
        courseM: _toIntOrNull(j['courseM']),
        addr: '${j['addr'] ?? ''}',
        image: '${j['image'] ?? ''}',
        tel: '${j['tel'] ?? ''}',
        lat: _toDouble(j['lat']),
        lng: _toDouble(j['lng']),
        distM: _toDouble(j['distM']),
      );

  /// 계약에 없거나 `null` 이면 `null` — 0 으로 눕히면 "길이가 0인 코스" 가 된다.
  static int? _toIntOrNull(Object? value) {
    if (value is num) return value.round();
    return int.tryParse('${value ?? ''}');
  }

  /// 숫자가 JSON 에서 `int` 로 올 수도 `double` 로 올 수도 있다.
  static double _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? 0;
  }
}

/// 주변 장소를 **우리 백엔드에서** 받아 온다 — 이슈 #40.
///
/// ## 서비스키를 안 읽는다
///
/// 예전에는 서비스키가 비면 빈 목록을 돌려줬다. 그 줄이 남아 있으면
/// **키 없는 빌드에서 지도가 영구히 빈 화면**이 된다 — 완료 조건 4("서비스키 없이 앱을
/// 빌드해도 지도가 정상 표시된다")가 정확히 거기서 깨진다.
///
/// ## 실패를 빈 목록으로 다룬다
///
/// 예전 동작 그대로다. 서버도 예산이 소진되면 200 + 빈 배열을 주므로, 앱에서는
/// "한도 초과" 와 "이 주변에 장소가 없음" 이 같게 보인다. **한계를 그대로 적는다** —
/// 그 둘을 구분해 보여 주는 것은 별건이고, 그전까지 오류 신호는 서버 지표에만 있다.
/// 장소를 못 받은 이유 — 이슈 #515.
///
/// **빈 목록으로 뭉치지 않는다.** 빈 목록은 화면에서 "이 지역엔 등록된 곳이 없어요" 가 되고,
/// 그건 서버가 죽었을 때 하는 거짓말이다. `pet.dart` 가 같은 문장을 커뮤니티 더미 앞에
/// 적어 뒀다 — "화면이 서버를 못 불렀을 때 그릴 것은 빈 목록이 아니라 '불러오지 못했어요' 다."
///
/// 모양은 [CommunityFailure] 를 따른다. 화면이 실패를 다루는 법이 도메인마다 다르면
/// 그때마다 새로 익혀야 한다.
enum PlaceFailureKind {
  /// 연결이 없거나 시간이 다 됐다. **다시 시도하면 된다.**
  network,

  /// 서버가 잠시 그만 보내라고 했다(429).
  rateLimited,

  /// 서버가 못 준다(5xx) 또는 계약과 다른 본문이 왔다. 다시 시도해 볼 수는 있다.
  unavailable,
}

extension PlaceFailureKindX on PlaceFailureKind {
  /// 화면에 그대로 그리는 문구.
  String get message => switch (this) {
        PlaceFailureKind.network => '연결이 불안정해요 · 다시 시도해 주세요',
        PlaceFailureKind.rateLimited => '요청이 많아요 · 잠시 뒤 다시 시도해 주세요',
        PlaceFailureKind.unavailable => '장소 목록을 못 받았어요 · 잠시 뒤 다시 시도해 주세요',
      };
}

class PlaceFailure implements Exception {
  final PlaceFailureKind kind;

  const PlaceFailure(this.kind);

  String get message => kind.message;

  @override
  String toString() => 'PlaceFailure($kind)';
}

class PetPlacesRepository {
  PetPlacesRepository({
    http.Client? client,
    String? baseUrl,
    PlaceCatalogRepository? catalog,
  })  : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? Env.apiBase,
        _catalog = catalog ?? PlaceCatalogRepository.instance;

  final http.Client _client;
  final String _baseUrl;

  /// A안 빌드가 쓰는 길 (이슈 #273).
  ///
  /// 기본값이 [PlaceCatalogRepository.instance] 인 것은 화면들이 **같은 한 벌**을 봐야
  /// 하기 때문이다 — 화면이 `PetPlacesRepository()` 를 호출마다 새로 만든다.
  /// 주입을 열어 두는 것은 테스트가 진짜 네트워크와 플러그인에 닿지 않게 하려는 것이다.
  final PlaceCatalogRepository _catalog;

  /// 내 주변 반려동반 가능 장소(거리순).
  ///
  /// [radius] 의 상한은 계약이 18,000m 로 정한다 — 서버가 셀 중심에서 20km 를 받아 두고
  /// 셀 반지름(약 1.4km)을 뺀 값이다. 넘겨도 서버가 거절하지 않고 자른다.
  Future<List<PetPlace>> fetchNearby({
    required double lat,
    required double lng,
    int radius = 8000,
    int numOfRows = 80,
    // 카테고리 키 — KTO contentTypeId 또는 vet/shop/trail (#291). 이름은 옛 것을 남긴다.
    String? contentTypeId,
  }) async {
    // 좌표가 기기를 떠나는 자리다. 정책이 꺼져 있으면 **요청 자체를 안 만든다**(#235).
    //
    // 예전에는 여기서 빈 목록을 줬고, 그래서 A안 빌드는 **지도의 장소 목록이 빈 채로**
    // 돌았다. 지금은 좌표를 안 보내는 다른 길이 있다 — 전국 한 벌을 받아 두고 거리를
    // 기기에서 재는 [PlaceCatalogRepository] 다(#273 · #274).
    //
    // 두 길이 같은 답을 준다. 다른 것은 **거리를 누가 재는가** 뿐이다.
    if (!LocationUploadPolicy.canQueryNearbyPlaces) {
      return _catalog.nearby(
        lat: lat,
        lng: lng,
        radius: radius,
        limit: numOfRows,
        contentTypeId: contentTypeId,
      );
    }

    final uri = Uri.parse('$_baseUrl/api/places/nearby').replace(queryParameters: {
      'lat': '$lat',
      'lng': '$lng',
      'radius': '$radius',
      'limit': '$numOfRows',
      if (contentTypeId != null && contentTypeId.isNotEmpty) 'category': contentTypeId,
    });

    try {
      final res = await _client.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode == 429) throw const PlaceFailure(PlaceFailureKind.rateLimited);
      if (res.statusCode != 200) throw const PlaceFailure(PlaceFailureKind.unavailable);
      return _parse(res.bodyBytes);
    } on PlaceFailure {
      rethrow; // 아래 catch 가 이유를 network 로 뭉개지 않게
    } catch (_) {
      throw const PlaceFailure(PlaceFailureKind.network);
    }
  }

  /// 계약은 `Place` 배열이다 — KTO 의 `response.body.items.item` 중첩이 아니다.
  ///
  /// 본문을 `bodyBytes` 에서 직접 디코딩한다. `res.body` 는 서버가 charset 을 안 붙이면
  /// latin-1 로 읽어서 한글이 깨진다(#81 에서 겪었다).
  List<PetPlace> _parse(List<int> bodyBytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bodyBytes));
      // 200 인데 배열이 아니다 — 계약 위반이다. 빈 목록으로 돌려주면 화면이 "없어요" 라고
      // 말하고, 그러면 계약이 깨진 것을 아무도 못 본다(#515).
      if (decoded is! List) throw const PlaceFailure(PlaceFailureKind.unavailable);
      return decoded
          .whereType<Map>()
          .map((e) => PetPlace.fromJson(e.cast<String, dynamic>()))
          .where((p) => p.lat != 0 && p.lng != 0)
          .toList();
    } on PlaceFailure {
      rethrow;
    } catch (_) {
      throw const PlaceFailure(PlaceFailureKind.unavailable);
    }
  }
}
