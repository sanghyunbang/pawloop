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

  /// 좌표에서 가까운 동 — "현재 위치로 찾기".
  ///
  /// **기기 안에서 고른다.** 좌표를 서버에 보내 물어보지 않는다(#235 A안). 중심점 사이의
  /// 거리라 경계와는 다를 수 있지만, 후보를 **추천**하는 자리라 그것으로 충분하다 —
  /// 고르는 것은 사람이다.
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
    return [for (final s in scored.take(limit)) s.$2];
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
