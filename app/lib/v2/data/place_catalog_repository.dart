import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pet_places_repository.dart';
import '../../core/config/env.dart';

/// 전국 반려동반 장소 **한 벌**을 기기에 두고 쓴다 — 이슈 #273 (#235 A4).
///
/// ## 왜 이것이 있나
///
/// `GET /api/places/nearby` 는 현위치를 쿼리로 받는다. 완전 온디바이스 빌드
/// (`UPLOAD_LOCATION=false`)는 좌표를 서버로 안 보내므로 그 길을 못 쓰고, 그러면
/// **지도의 장소 목록이 빈다.**
///
/// 이 경로는 `GET /api/places/catalog` 한 번으로 전국을 통째로 받는다.
/// **요청에 좌표도 지역도 안 실린다.** 거리 정렬·반경 필터는 [nearby] 가 기기에서 한다.
///
/// ## 크기 (서버 실측 2026-09-04)
///
/// 9,684곳 / 2.83MB / gzip 0.44MB. 시군구로 쪼개면 요청에 지역이 실리고 한 벌 데우는
/// 서버 콜이 10 에서 249 로 는다 — 440KB 를 아끼려고 치를 값이 아니라고 봤다(#274).
///
/// ## 세 겹으로 캐시한다
///
/// 1. **메모리** — 같은 세션에서 두 번 파싱하지 않는다.
/// 2. **파일** — 앱을 껐다 켜도 남는다. 캐시 디렉터리라 OS 가 지울 수 있고, 지워지면
///    다시 받는다(사용자 데이터가 아니라 공개 장소 목록이다).
/// 3. **`ETag`** — 하루 한 번 갱신을 확인하는데, 내용이 그대로면 **304** 로 끝나서
///    2.83MB 가 안 온다. 서버의 ETag 가 갱신 시각이 아니라 내용 해시라 그렇다.
///
/// ## 실패는 조용하다
///
/// 못 받으면 갖고 있던 것을 그대로 준다. 아무것도 없으면 빈 목록이다 —
/// [PetPlacesRepository] 가 실패를 다루는 방식과 같다.
class PlaceCatalogRepository {
  PlaceCatalogRepository({
    http.Client? client,
    String? baseUrl,
    Future<Directory> Function()? cacheDirectory,
  })  : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? Env.apiBase,
        _cacheDirectory = cacheDirectory ?? getApplicationCacheDirectory;

  /// 화면들이 같은 한 벌을 보게 하는 기본 인스턴스.
  ///
  /// 화면이 `PetPlacesRepository()` 를 호출마다 새로 만든다. 그 안에 캐시를 두면
  /// **매번 새 캐시라 아무것도 안 남는다.** 그래서 여기가 하나여야 한다.
  static final PlaceCatalogRepository instance = PlaceCatalogRepository();

  /// 갱신을 확인하는 간격. 서버 캐시가 24시간이라 그보다 자주 물을 이유가 없다.
  ///
  /// 레이트리밋이 **분당 5** 라 그보다 잦게 부르면 429 인데, 429 를 받아도 기기에 있는
  /// 한 벌을 계속 쓰므로 지도가 죽지는 않는다.
  static const Duration refreshInterval = Duration(hours: 24);

  /// 실패한 뒤 다시 시도하기까지 쉬는 시간.
  ///
  /// **이게 없으면 산책 중에 요청이 쏟아진다.** `walk_tracking_screen` 이 위치가 5m
  /// 움직일 때마다 `if (!_poisLoaded)` 를 보고 다시 부르는데, 한 벌을 아직 못 받았으면
  /// `_poisLoaded` 가 안 서서 그 조건이 계속 참이다. 서버의
  /// `failure-backoff-minutes` 가 같은 것을 막는다.
  static const Duration failureBackoff = Duration(minutes: 5);

  static const String _fileName = 'place_catalog_v1.json';
  static const String _etagKey = 'place_catalog_etag_v1';
  static const String _checkedAtKey = 'place_catalog_checked_at_v1';

  final http.Client _client;
  final String _baseUrl;
  final Future<Directory> Function() _cacheDirectory;

  List<PetPlace>? _memory;

  /// 지금 나가 있는 갱신. 화면 둘이 동시에 물어도 요청은 하나다.
  Future<void>? _inFlight;

  /// 마지막으로 실패한 시각. [failureBackoff] 가 이 값을 본다.
  ///
  /// 메모리에만 둔다 — 앱을 껐다 켰다는 것은 사람이 다시 시도한 것이라, 그때는
  /// 기다리게 할 이유가 없다.
  DateTime? _lastFailure;

  /// 한 벌을 하나라도 갖고 있는가.
  ///
  /// 화면이 **"이 지역에 없음"** 과 **"아직 못 받음"** 을 가르는 데 쓴다. 둘 다
  /// [nearby] 가 빈 목록을 주므로 그것만 보면 구분이 안 되고, 그러면 네트워크가 끊긴
  /// 사용자에게 "이 지역엔 등록된 곳이 없어요, 지도를 움직여 보세요" 라고 말하게 된다 —
  /// 시킨 대로 해도 소용이 없는 안내다.
  bool get hasCatalog => _memory != null && _memory!.isNotEmpty;

  /// 사람이 "다시 시도" 를 눌렀다. **백오프를 건너뛰고** 한 번 받아 본다.
  ///
  /// [failureBackoff] 는 산책 화면의 자동 재호출을 막으려는 것이지 사람의 손을 막으려는
  /// 것이 아니다. 버튼을 눌렀는데 5분을 기다리라고 하면 버튼이 거짓말이 된다.
  ///
  /// 백오프 판정은 [all] 에만 있고 [_refresh] 에는 없다 — 그래서 여기서 따로 지울 것이
  /// 없다. 처음에는 `_lastFailure = null` 을 앞에 두었는데, 그 줄을 지워도 검사가
  /// 초록이었다(실측). 있으나 없으나 같은 줄은 없는 편이 읽는 사람에게 정직하다.
  Future<void> retry() => _refresh();

  /// 전국 한 벌. 메모리 → 파일 → 네트워크 순으로 찾는다.
  Future<List<PetPlace>> all() async {
    _memory ??= await _readFile();

    // 파일에도 없으면 **기다린다** — 안 그러면 첫 화면이 빈 지도를 그린다.
    // 있으면 갱신은 뒤에서 하고 갖고 있는 것을 바로 준다.
    if (_memory == null) {
      if (_isBackingOff()) return const [];
      await _refresh();
      return _memory ?? const [];
    }

    if (await _isStale()) {
      unawaited(_refresh());
    }
    return _memory!;
  }

  /// 이 좌표 주변을 거리순으로. **네트워크가 없다** — 전부 기기에서 한다.
  ///
  /// 서버의 `PlaceQueryService.within` 과 같은 규칙이다: 카테고리로 거르고, 반경 밖을
  /// 빼고, 거리순으로 정렬해 [limit] 만큼 자른다. 거리는 하버사인이다.
  Future<List<PetPlace>> nearby({
    required double lat,
    required double lng,
    int radius = 8000,
    int limit = 80,
    String? contentTypeId,
  }) async {
    final places = await all();
    final out = <PetPlace>[];

    for (final place in places) {
      if (contentTypeId != null &&
          contentTypeId.isNotEmpty &&
          place.contentTypeId != contentTypeId) {
        continue;
      }
      final distance = haversineMeters(lat, lng, place.lat, place.lng);
      if (distance > radius) continue;
      out.add(place.withDistance(distance));
    }

    out.sort((a, b) => a.distM.compareTo(b.distM));
    return out.length > limit ? out.sublist(0, limit) : out;
  }

  // ─────────────────────────── 갱신 ───────────────────────────

  /// 방금 실패했으면 쉰다.
  bool _isBackingOff() {
    final failedAt = _lastFailure;
    if (failedAt == null) return false;
    return DateTime.now().difference(failedAt) < failureBackoff;
  }

  Future<bool> _isStale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final checkedAt = prefs.getInt(_checkedAtKey);
      if (checkedAt == null) return true;
      final age = DateTime.now().millisecondsSinceEpoch - checkedAt;
      return age >= refreshInterval.inMilliseconds || age < 0;
    } catch (_) {
      // 저장소를 못 읽으면 **안 낡은 것으로 본다.** 낡은 것으로 보면 확인 시각도 못
      // 적으므로 요청마다 2.83MB 를 다시 받는 고리가 된다. 갖고 있는 것을 쓰는 쪽이 낫다.
      return false;
    }
  }

  /// 한 벌을 받아 온다. 이미 나가 있으면 그것을 기다린다.
  Future<void> _refresh() {
    return _inFlight ??= _fetch().whenComplete(() => _inFlight = null);
  }

  Future<void> _fetch() async {
    try {
      // **이 줄이 try 밖에 있으면 안 된다.** SharedPreferences 가 실패하면
      // `_refresh` 가 거절되고, 그것을 기다리는 `all()` 이 그대로 던진다 —
      // 지도를 조용히 비우는 대신 화면을 죽인다. 실측으로 잡았다:
      // 바인딩이 없는 테스트에서 이 줄이 통째로 예외를 밖으로 냈다.
      final prefs = await SharedPreferences.getInstance();
      final etag = prefs.getString(_etagKey);

      final res = await _client.get(
        Uri.parse('$_baseUrl/api/places/catalog'),
        // 갖고 있는 것이 있으면 그것을 대고 묻는다. 같으면 304 로 끝나고
        // 2.83MB 가 안 온다 — 이 헤더가 이 경로의 요점이다.
        headers: {if (etag != null && etag.isNotEmpty) 'If-None-Match': etag},
      ).timeout(const Duration(seconds: 30));

      if (res.statusCode == 304) {
        _lastFailure = null;
        await prefs.setInt(_checkedAtKey, DateTime.now().millisecondsSinceEpoch);
        return;
      }
      if (res.statusCode != 200) {
        _lastFailure = DateTime.now();
        return;
      }

      // 본문을 bodyBytes 에서 직접 디코딩한다. `res.body` 는 서버가 charset 을 안 붙이면
      // latin-1 로 읽어서 한글이 깨진다(#81 에서 겪었다).
      final body = utf8.decode(res.bodyBytes);
      final places = await compute(decodeCatalog, body);

      // **빈 한 벌은 안 받아들인다.** 서버가 예산 소진·상류 실패를 200 + `[]` 로 주기
      // 때문이다(계약에 그렇게 적혀 있다). 그것을 저장하면 갖고 있던 한 벌을 지우고
      // 지도가 빈다 — 서버가 회복해도 다음 갱신까지 빈 채로 남는다.
      if (places.isEmpty) {
        _lastFailure = DateTime.now();
        return;
      }

      _lastFailure = null;
      _memory = places;
      await _writeFile(body);
      await prefs.setInt(_checkedAtKey, DateTime.now().millisecondsSinceEpoch);

      final fresh = res.headers['etag'];
      if (fresh != null && fresh.isNotEmpty) {
        await prefs.setString(_etagKey, fresh);
      }
    } catch (_) {
      // 갖고 있던 것을 그대로 쓴다. 지도가 죽는 것보다 낫다.
      _lastFailure = DateTime.now();
    }
  }

  // ─────────────────────────── 파일 ───────────────────────────

  Future<File> _file() async =>
      File('${(await _cacheDirectory()).path}${Platform.pathSeparator}$_fileName');

  Future<List<PetPlace>?> _readFile() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final places = await compute(decodeCatalog, await file.readAsString());
      return places.isEmpty ? null : places;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeFile(String body) async {
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      await file.writeAsString(body, flush: true);
    } catch (_) {
      // 파일에 못 써도 이번 세션은 메모리로 돈다.
    }
  }
}

/// 2.83MB 를 파싱한다. **최상위 함수여야 한다** — [compute] 가 아이솔레이트로 보낸다.
///
/// 메인 아이솔레이트에서 하면 그동안 화면이 멈춘다.
List<PetPlace> decodeCatalog(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! List) return const [];
  return decoded
      .whereType<Map>()
      .map((e) => PetPlace.fromJson(e.cast<String, dynamic>()))
      .where((p) => p.lat != 0 && p.lng != 0)
      .toList(growable: false);
}

/// 두 좌표 사이의 거리(m).
///
/// 서버의 `PlaceQueryService.haversineMeters` 와 같은 식이다. 서버가 이 값을 안 실어
/// 보내므로(`distM` 이 없다) 기기에서 잰다 — 잴 좌표를 서버가 갖고 있지 않다는 것이
/// 이 설계의 요점이다.
double haversineMeters(double lat1, double lng1, double lat2, double lng2) {
  const earthRadiusM = 6371000.0;
  final dLat = _toRadians(lat2 - lat1);
  final dLng = _toRadians(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_toRadians(lat1)) *
          math.cos(_toRadians(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return earthRadiusM * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

double _toRadians(double degrees) => degrees * math.pi / 180.0;
