// lib/v2/data/region_catalog.dart
//
// 전국 행정동 3,516개를 기기 안에서 뒤진다 — 이슈 #342.
//
// ## 네트워크가 없다
//
// 이 파일은 `package:http` 도 `AuthedClient` 도 import 하지 않는다. 목록은 앱에 들어 있고
// (`assets/regions/hangjeongdong.json`, 285KB), 검색도 "현재 위치로 찾기" 도 여기서 끝난다 —
// **좌표가 이 파일을 지나 어디로도 가지 않는다.** `route_image.dart` 가 같은 이유로 같은
// 규칙을 지킨다.
//
// 서버로 나가는 것은 사용자가 고른 뒤의 **코드 열 자리**뿐이고, 그 전송은
// `neighborhood_store.dart` 한 곳에서만 일어난다.
//
// ## 왜 미리 안 읽나
//
// 285KB 를 앱 시작마다 파싱하면 첫 화면이 그만큼 늦는다. 목록이 필요한 자리는 동네 고르기
// 화면 하나뿐이라 **열 때 읽고 그 뒤로는 들고 있는다**.
//
// ## 출처 (CC BY 4.0 — 지우면 안 된다)
//
// 원자료는 통계청 SGIS 행정동 경계(공공누리 제1유형), 가공본은 vuski/admdongkor 이고
// CC BY 4.0 이다. 파생물에도 출처 표시 의무가 남으므로 [attribution] 이 화면에 보인다.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;

import '../domain/neighborhood.dart';

class RegionCatalog {
  RegionCatalog._(this._all, this.attribution);

  /// 화면 아래에 그대로 보이는 한 줄. 라이선스가 요구하는 표시다.
  final String attribution;

  final List<Neighborhood> _all;

  static RegionCatalog? _cached;

  static const String assetPath = 'assets/regions/hangjeongdong.json';

  /// 한 번 읽고 들고 있는다. 두 화면이 동시에 열어도 파싱은 한 번이다.
  static Future<RegionCatalog> load() async {
    final cached = _cached;
    if (cached != null) return cached;
    final raw = await rootBundle.loadString(assetPath);
    final catalog = parse(raw);
    _cached = catalog;
    return catalog;
  }

  /// 테스트가 문자열을 그대로 넣는 자리. 자산을 안 거친다.
  static RegionCatalog parse(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;

    final sido = {
      for (final row in (json['sido'] as List? ?? const []))
        (row as Map)['c'] as String: row['n'] as String,
    };
    final sigungu = {
      for (final row in (json['sigungu'] as List? ?? const []))
        (row as Map)['c'] as String: (
          sido: sido[row['s']] ?? '',
          name: row['n'] as String,
        ),
    };

    final all = <Neighborhood>[];
    for (final row in (json['dong'] as List? ?? const [])) {
      final map = row as Map;
      final code = map['c'] as String?;
      final sgg = map['g'] as String?;
      if (code == null || sgg == null) continue;
      final parent = sigungu[sgg];
      all.add(Neighborhood(
        code: code,
        sigunguCode: sgg,
        sido: parent?.sido ?? '',
        sigungu: parent?.name ?? '',
        dong: map['n'] as String? ?? '',
        lat: (map['lat'] as num?)?.toDouble() ?? 0,
        lng: (map['lng'] as num?)?.toDouble() ?? 0,
      ));
    }

    return RegionCatalog._(all, json['source'] as String? ?? '');
  }

  /// 전부. 테스트와 개수 확인용이다.
  List<Neighborhood> get all => List.unmodifiable(_all);

  /// 시도 이름 목록 — 화면의 첫 단계.
  List<String> get sidos {
    final seen = <String>{};
    return [
      for (final n in _all)
        if (seen.add(n.sido)) n.sido,
    ];
  }

  /// 그 시도의 시군구 이름들 — 두 번째 단계.
  List<String> sigungusOf(String sido) {
    final seen = <String>{};
    return [
      for (final n in _all)
        if (n.sido == sido && seen.add(n.sigungu)) n.sigungu,
    ];
  }

  /// 그 시군구의 동들 — 세 번째 단계.
  List<Neighborhood> dongsOf({required String sido, required String sigungu}) => [
        for (final n in _all)
          if (n.sido == sido && n.sigungu == sigungu) n,
      ];

  /// 이름으로 찾는다. **띄어쓰기를 지운 뒤** 견준다 — "성동구왕십리" 로도 찾아야 한다.
  ///
  /// 시작이 일치하는 것을 앞에 둔다. "중구" 를 쳤을 때 "서울 중구" 보다 "종로구 중림동" 이
  /// 먼저 나오면 찾는 사람이 목록을 끝까지 훑게 된다.
  List<Neighborhood> search(String query, {int limit = 30}) {
    final q = query.replaceAll(' ', '').trim();
    if (q.isEmpty) return const [];

    final starts = <Neighborhood>[];
    final contains = <Neighborhood>[];
    for (final n in _all) {
      final full = n.fullLabel.replaceAll(' ', '');
      if (full.contains(q)) {
        if (n.dong.startsWith(q) || n.sigungu.startsWith(q) || n.sido.startsWith(q)) {
          starts.add(n);
        } else {
          contains.add(n);
        }
      }
      if (starts.length >= limit) break;
    }
    return [...starts, ...contains].take(limit).toList();
  }

  /// "현재 위치 근처" 라고 부를 수 있는 한계(km).
  ///
  /// **한국 밖에서 눌러 보고 넣은 값이다.** 예전에는 상한이 없어서 전국 3,516개를 거리순으로
  /// 정렬하고 **무조건** 위 다섯을 돌려줬다. 애플 심사자가 있는 쿠퍼티노(37.33, -122.01)에서
  /// "현재 위치로 찾기" 를 누르면 화면이 **"현재 위치 근처"** 라는 제목 아래 인천 옹진군
  /// 백령면(9,210km)·대청면(9,218km)·전남 신안군 흑산면(9,407km)을 그렸다. 화면은 그것이
  /// 근처가 아니라는 말을 한 마디도 하지 않았다.
  ///
  /// **100km 는 재서 고른 값이다.** 이 목록은 "내가 지금 어느 동에 있나" 를 묻는다. 그래서
  /// 상한은 "동 중심점이 얼마나 성기게 있나" 로 정해야 한다. 3,516개를 서로 맞대어 각 동에서
  /// 가장 가까운 다른 동까지의 거리를 전부 쟀다.
  ///
  /// | 어디 | 가장 가까운 다른 동 |
  /// |:---|---:|
  /// | 신안군 흑산면 (전국 최악) | 48.4 km |
  /// | 옹진군 연평면 | 42.8 km |
  /// | 여수시 삼산면 | 41.3 km |
  /// | 쿠퍼티노에서 가장 가까운 동 | 9,210 km |
  ///
  /// 처음에 50km 로 잡았다가 이 표를 보고 고쳤다 — **최악의 빈틈과 같은 값이라 여유가 없었다.**
  /// 다도해 끝자락에 서 있으면 자기 동 중심점이 그 절반 너머일 수 있고, 그러면 화면이 아무것도
  /// 못 준다. 100km 면 그 빈틈의 두 배고, 국외(9,210km)와는 92배가 벌어진다.
  ///
  /// 넘으면 한국에 있지 않다는 뜻이고, 그때는 빈 목록이 맞다 — 화면은 시·도 목록을 그대로
  /// 띄우고 있으므로 사람은 손으로 고를 수 있다.
  static const double nearestLimitKm = 100;

  /// 좌표에서 가까운 동 — "현재 위치로 찾기".
  ///
  /// **기기 안에서 고른다.** 좌표를 서버에 보내 물어보지 않는다(#235 A안). 중심점 사이의
  /// 거리라 경계와는 다를 수 있지만, 후보를 **추천**하는 자리라 그것으로 충분하다 —
  /// 고르는 것은 사람이다.
  ///
  /// [nearestLimitKm] 를 넘는 것은 주지 않는다. 빈 목록이 나올 수 있다.
  List<Neighborhood> nearest(double lat, double lng, {int limit = 5}) {
    final scored = <(double, Neighborhood)>[];
    for (final n in _all) {
      // 위도 1도와 경도 1도의 길이가 다르다. 한국 위도에서 경도를 0.79 배로 눌러 준다 —
      // 정확한 거리가 아니라 **순서**만 맞으면 되는 자리다.
      final dLat = n.lat - lat;
      final dLng = (n.lng - lng) * math.cos(lat * math.pi / 180);
      scored.add((dLat * dLat + dLng * dLng, n));
    }
    scored.sort((a, b) => a.$1.compareTo(b.$1));

    // 위의 점수는 **순서**를 위한 평면 근사다. 자르는 자리에서는 그것을 쓰면 안 된다 —
    // 한국 밖에서는 근사와 실제가 크게 어긋난다(쿠퍼티노에서 근사 21,778km, 실제 9,210km).
    // 여기서만 진짜 거리를 잰다. 어차피 다섯 개를 채우면 멈춘다.
    final out = <Neighborhood>[];
    for (final (_, n) in scored) {
      if (out.length >= limit) break;
      if (kmBetween(lat, lng, n.lat, n.lng) <= nearestLimitKm) out.add(n);
    }
    return out;
  }

  /// 두 점 사이의 실제 거리(km). 하버사인.
  ///
  /// `place_catalog_repository.dart` 에 같은 계산이 있지만 그 파일은 `http` 와
  /// `path_provider` 를 import 한다. **이 파일은 네트워크를 모르는 채로 둔다**(머리말) —
  /// 열 줄을 다시 쓰는 편이 그 규칙을 지키는 값으로 싸다.
  @visibleForTesting
  static double kmBetween(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0088;
    final p1 = lat1 * math.pi / 180;
    final p2 = lat2 * math.pi / 180;
    final dPhi = (lat2 - lat1) * math.pi / 180;
    final dLambda = (lng2 - lng1) * math.pi / 180;
    final h = math.sin(dPhi / 2) * math.sin(dPhi / 2) +
        math.cos(p1) * math.cos(p2) * math.sin(dLambda / 2) * math.sin(dLambda / 2);
    return 2 * r * math.asin(math.sqrt(h));
  }

  /// 코드로 하나. 서버가 준 코드를 이름으로 되돌릴 때 쓴다.
  Neighborhood? byCode(String? code) {
    if (code == null) return null;
    for (final n in _all) {
      if (n.code == code) return n;
    }
    return null;
  }
}
