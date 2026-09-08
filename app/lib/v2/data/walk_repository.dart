// lib/v2/data/walk_repository.dart
//
// 산책과 반려동물의 서버 연동 — 이슈 #145.
//
// ## 무엇이 바뀌었나
//
// 산책을 끝내면 아무것도 남지 않았다. `walk_tracking_screen` 은 경로·거리·시간을
// 제대로 쌓는데, 종료 시트의 "기록 저장하기" 가 그걸 버리고 `CreateScreen` 을 열었고
// 그 화면의 저장 버튼은 **스낵바만 띄웠다.** 앱을 껐다 켜면 흔적이 없다.
//
// ## 규칙 (family_repository.dart 와 같다)
//
//  1. HTTP 는 `AuthedClient` 하나로만 나간다. `Authorization` 헤더를 여기서 만들지
//     않는다 — 만드는 곳은 앱 전체에서 `authed_client.dart` 한 줄이고
//     `auth_header_single_source_test.dart` 가 그것을 잠근다(#11).
//  2. 실패를 **종류로** 나눈다. 화면이 "연결이 없다"(다시 시도할 수 있다)와
//     "서버가 거절했다"(다시 눌러도 같다)를 다르게 그려야 한다.
//  3. **토큰 저장소를 건드리지 않는다.** 401 은 `AuthedClient` 가 갱신까지 시도한
//     뒤의 결과다(#12).
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:heat_trip_flutter/core/config/env.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';

import 'location_upload_policy.dart';

/// 반려동물의 종 — 계약의 `PetSpecies`.
///
/// `pet.dart` 의 `PetSpecies` 와 이름이 겹치지만 그쪽은 화면 안에서만 사는 더미
/// 도메인이다. 서버로 나가는 표기는 이 셋이다.
enum ServerPetSpecies {
  dog('dog', '강아지'),
  cat('cat', '고양이'),
  other('other', '기타');

  final String wire;
  final String label;

  const ServerPetSpecies(this.wire, this.label);

  /// 모르는 값이면 [dog]. 서버가 종을 늘렸는데 앱이 낡았을 때 **던지지 않는다** —
  /// 카드 한 칸이 잘못 그려지는 것과 화면 전체가 죽는 것은 다르다.
  static ServerPetSpecies parse(String? value) {
    for (final species in values) {
      if (species.wire == value) return species;
    }
    return dog;
  }
}

/// 몸집 — 계약의 `DogSize`. 이름이 "Dog" 지만 고양이에도 쓴다.
enum ServerPetSize {
  small('small', '소형'),
  medium('medium', '중형'),
  large('large', '대형');

  final String wire;
  final String label;

  const ServerPetSize(this.wire, this.label);

  static ServerPetSize parse(String? value) {
    for (final size in values) {
      if (size.wire == value) return size;
    }
    return small;
  }
}

/// 서버에 등록된 반려동물 하나 — 계약의 `Dog`.
class ServerPet {
  final int id;
  final String name;
  final ServerPetSpecies species;
  final ServerPetSize size;
  final String? breed;

  /// 생일에서 파생한 개월 수. **`null` 은 "생일을 모른다"** 이지 0개월이 아니다.
  final int? ageMonths;

  final bool neutered;

  const ServerPet({
    required this.id,
    required this.name,
    required this.species,
    required this.size,
    required this.neutered,
    this.breed,
    this.ageMonths,
  });

  /// 모양이 계약과 다르면 `null`. 목록 하나가 깨졌다고 화면 전체를 죽이지 않는다.
  static ServerPet? tryParse(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    if (id is! int || name is! String) return null;
    return ServerPet(
      id: id,
      name: name,
      species: ServerPetSpecies.parse(json['species'] as String?),
      size: ServerPetSize.parse(json['size'] as String?),
      breed: json['breed'] as String?,
      ageMonths: json['ageMonths'] as int?,
      neutered: json['neutered'] == true,
    );
  }
}

/// 저장된 산책 하나 — 계약의 `Walk`.
/// 산책에 붙은 장소 — 계약의 `Walk.place` (#338).
///
/// [source] 와 [contentId] 는 **짝이다.** 카탈로그에서 고른 곳이면 둘 다 있고, 이름을 손으로
/// 적었으면 둘 다 없다. 하나만 보내면 서버가 400 을 준다 — 반쪽짜리 참조는 이름만 있는 것과
/// 같으면서 있는 척한다.
class WalkPlaceRef {
  final String? source;
  final String? contentId;
  final String title;

  const WalkPlaceRef({required this.title, this.source, this.contentId});

  /// 카탈로그에서 고른 곳인가 — "자주 가는 곳" 에 잡히는 것은 이것뿐이다.
  bool get isCatalog => source != null && source!.isNotEmpty && contentId != null && contentId!.isNotEmpty;

  static WalkPlaceRef? tryParse(Object? json) {
    if (json is! Map) return null;
    final title = json['title'];
    if (title is! String || title.isEmpty) return null;
    String? text(Object? v) => v is String && v.isNotEmpty ? v : null;
    return WalkPlaceRef(title: title, source: text(json['source']), contentId: text(json['contentId']));
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        if (source != null) 'source': source,
        if (contentId != null) 'contentId': contentId,
      };
}

class ServerWalk {
  final int id;

  /// **대표 아이.** [dogIds] 의 첫 번째와 같다.
  final int dogId;

  /// 함께 나간 아이들 — 이슈 #343. **항상 한 개 이상**이고 첫 번째가 [dogId] 다.
  ///
  /// 옛 서버가 이 필드를 안 주면 `[dogId]` 로 채운다 — 빈 목록을 그대로 두면 화면이
  /// "아이 없는 산책" 이라는, 있을 수 없는 상태를 그린다.
  final List<int> dogIds;

  /// 앱이 만든 멱등키. **전송 대기 큐의 어느 항목이 저장된 것인지 맞춰 보는 데 쓴다.**
  final String clientWalkId;

  final DateTime startedAt;
  final DateTime? endedAt;
  final int distanceM;
  final int durationS;

  /// `[경도, 위도]` 순서. **목록 응답에서는 항상 `null`** 이고 상세에서만 온다.
  final List<List<double>>? path;

  final String? memo;
  final String? weather;

  /// 어디를 걸었나 (#338). 안 붙였으면 `null` 이다 — 빈 객체가 오지 않는다.
  final WalkPlaceRef? place;

  const ServerWalk({
    required this.id,
    required this.dogId,
    this.dogIds = const [],
    required this.clientWalkId,
    required this.startedAt,
    required this.distanceM,
    required this.durationS,
    this.endedAt,
    this.path,
    this.memo,
    this.weather,
    this.place,
  });

  double get km => distanceM / 1000.0;

  int get minutes => durationS ~/ 60;

  static ServerWalk? tryParse(Map<String, dynamic> json) {
    final id = json['id'];
    final dogId = json['dogId'];
    final startedAt = DateTime.tryParse(json['startedAt'] as String? ?? '');
    if (id is! int || dogId is! int || startedAt == null) return null;

    final rawPath = json['path'];
    List<List<double>>? path;
    if (rawPath is List) {
      path = rawPath
          .whereType<List>()
          .map((point) => point.whereType<num>().map((n) => n.toDouble()).toList())
          .where((point) => point.length == 2)
          .toList();
    }

    final rawDogIds = json['dogIds'];
    final dogIds = rawDogIds is List
        ? rawDogIds.whereType<num>().map((n) => n.toInt()).toList()
        : <int>[];

    return ServerWalk(
      id: id,
      dogId: dogId,
      // 첫 번째가 대표 아이라는 것이 계약이다. 서버가 안 줬으면 그 아이 하나로 둔다.
      dogIds: dogIds.isEmpty ? [dogId] : dogIds,
      clientWalkId: json['clientWalkId'] as String? ?? '',
      // 서버는 UTC 로 준다. 화면에 그릴 때 기기 시간대로 돌린다.
      startedAt: startedAt.toLocal(),
      endedAt: DateTime.tryParse(json['endedAt'] as String? ?? '')?.toLocal(),
      distanceM: (json['distanceM'] as num?)?.toInt() ?? 0,
      durationS: (json['durationS'] as num?)?.toInt() ?? 0,
      path: path,
      memo: json['memo'] as String?,
      weather: json['weather'] as String?,
      place: WalkPlaceRef.tryParse(json['place']),
    );
  }
}

/// 목록 한 장 — 계약의 `Page` 봉투.
class ServerWalkPage {
  final List<ServerWalk> items;
  final String? nextCursor;
  final bool hasMore;

  const ServerWalkPage({
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });
}

/// 통계 — 계약의 `WalkStats`. **이번 주와 전체 기간이 한 응답에 있다.**
class ServerWalkStats {
  /// **월요일부터** 길이 7. 주 경계는 KST 다(서버가 자른다).
  final List<double> weekKm;

  /// 같은 요일 축의 **분**, 길이 7 (#341). 목표가 분 단위라 거리와 나란히 읽는다.
  final List<int> weekMinutes;

  final double totalKm;

  /// 이번 주 산책 **건수**다. "산책한 날 수" 가 아니다.
  final int walkCount;

  final double avgKm;
  final double allTimeKm;
  final int allTimeCount;
  final int allTimeMinutes;

  /// 자주 간 곳 상위 다섯, 전체 기간 (#338). **카탈로그에서 고른 곳만 센다** —
  /// 손으로 적은 이름은 서버가 `PlaceRef` 를 만들 수 없어 여기 안 들어간다.
  final List<WalkTopPlace> topPlaces;

  const ServerWalkStats({
    required this.weekKm,
    this.weekMinutes = const [0, 0, 0, 0, 0, 0, 0],
    required this.totalKm,
    required this.walkCount,
    required this.avgKm,
    required this.allTimeKm,
    required this.allTimeCount,
    required this.allTimeMinutes,
    this.topPlaces = const [],
  });

  /// 아무것도 없는 상태. 서버를 못 부른 화면이 그릴 값이다.
  static const empty = ServerWalkStats(
    weekKm: [0, 0, 0, 0, 0, 0, 0],
    weekMinutes: [0, 0, 0, 0, 0, 0, 0],
    totalKm: 0,
    walkCount: 0,
    avgKm: 0,
    allTimeKm: 0,
    allTimeCount: 0,
    allTimeMinutes: 0,
  );

  static ServerWalkStats parse(Map<String, dynamic> json) {
    final raw = json['weekKm'];
    final week = raw is List
        ? raw.whereType<num>().map((n) => n.toDouble()).toList()
        : <double>[];
    // 길이 7 을 여기서 보장한다. 화면이 `weekKm[i]` 를 도는데 짧으면 범위 예외로 죽는다.
    while (week.length < 7) {
      week.add(0);
    }

    // 분도 같은 방식으로 길이 7 을 보장한다 — 화면이 요일을 돌면서 읽는다.
    final rawMinutes = json['weekMinutes'];
    final minutes = rawMinutes is List
        ? rawMinutes.whereType<num>().map((n) => n.toInt()).toList()
        : <int>[];
    while (minutes.length < 7) {
      minutes.add(0);
    }

    return ServerWalkStats(
      weekKm: week.take(7).toList(),
      weekMinutes: minutes.take(7).toList(),
      totalKm: (json['totalKm'] as num?)?.toDouble() ?? 0,
      walkCount: (json['walkCount'] as num?)?.toInt() ?? 0,
      avgKm: (json['avgKm'] as num?)?.toDouble() ?? 0,
      allTimeKm: (json['allTimeKm'] as num?)?.toDouble() ?? 0,
      allTimeCount: (json['allTimeCount'] as num?)?.toInt() ?? 0,
      allTimeMinutes: (json['allTimeMinutes'] as num?)?.toInt() ?? 0,
      topPlaces: WalkTopPlace.parseList(json['topPlaces']),
    );
  }
}

/// "자주 가는 곳" 한 줄 — 계약의 `WalkStats.topPlaces[]` (#338).
class WalkTopPlace {
  final WalkPlaceRef place;
  final int count;

  const WalkTopPlace({required this.place, required this.count});

  /// 모양이 다른 항목은 **버린다.** 하나가 이상하다고 목록 전체를 잃지 않는다.
  static List<WalkTopPlace> parseList(Object? json) {
    if (json is! List) return const [];
    final out = <WalkTopPlace>[];
    for (final item in json) {
      if (item is! Map) continue;
      final place = WalkPlaceRef.tryParse(item['place']);
      final count = item['count'];
      if (place == null || count is! num) continue;
      out.add(WalkTopPlace(place: place, count: count.toInt()));
    }
    return out;
  }
}

/// 실패의 종류. **다시 보내면 되는 것과 그러면 안 되는 것을 가른다.**
///
/// 이 구분이 없으면 전송 대기 큐가 영구 거절 요청을 영원히 재시도하면서
/// 정상 기록을 밀어낸다.
enum WalkFailureKind {
  /// 연결이 없다. **다시 보내면 된다.**
  network,

  /// 세션이 끝났다(401). `AuthedClient` 가 갱신까지 시도한 뒤의 결과다.
  /// 로그인하면 **다시 보내면 된다.**
  unauthorized,

  /// 서버가 잠시 그만 보내라고 했다(429). **나중에 다시 보내면 된다.**
  rateLimited,

  /// 서버가 입력을 거절했다(400). **다시 보내도 같다** — 큐에서 빼야 한다.
  rejected,

  /// 그 반려동물이 없거나 내 것이 아니다(404). **다시 보내도 같다.**
  notFound,
}

extension WalkFailureKindX on WalkFailureKind {
  /// 다시 보내면 될 수도 있는가. 전송 대기 큐가 이 값으로 갈린다.
  bool get retryable => switch (this) {
        WalkFailureKind.network => true,
        WalkFailureKind.unauthorized => true,
        WalkFailureKind.rateLimited => true,
        WalkFailureKind.rejected => false,
        WalkFailureKind.notFound => false,
      };

  String get message => switch (this) {
        WalkFailureKind.network => '연결이 불안정해요 · 나중에 다시 보낼게요',
        WalkFailureKind.unauthorized => '다시 로그인하면 저장할게요',
        WalkFailureKind.rateLimited => '잠시 후 다시 보낼게요',
        WalkFailureKind.rejected => '기록을 저장할 수 없어요',
        WalkFailureKind.notFound => '반려동물을 찾을 수 없어요',
      };
}

class WalkFailure implements Exception {
  final WalkFailureKind kind;

  const WalkFailure(this.kind);

  bool get retryable => kind.retryable;

  String get message => kind.message;

  @override
  String toString() => 'WalkFailure($kind)';
}

/// `/api/dogs` 와 `/api/walks` 의 클라이언트.
class WalkRepository {
  /// 요청 하나의 상한. 없으면 응답을 주지 않는 서버에서 화면이 영원히 로딩만 돈다.
  static const Duration timeout = Duration(seconds: 12);

  /// 메모의 최대 길이. 서버의 `walk.memo` 컬럼 폭이자 계약의 `maxLength` 와 같다.
  static const int maxMemoLength = 500;

  final String baseUrl;
  final AuthedClient _authed;

  WalkRepository({String? baseUrl, AuthedClient? client})
      : baseUrl = _stripTrailingSlash(baseUrl ?? Env.apiBase),
        _authed = client ?? AuthedClient.instance;

  static String _stripTrailingSlash(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  // ─────────────────────────── 반려동물 ───────────────────────────

  /// 내 반려동물 목록. 등록순이라 첫 마리가 기본 선택이다.
  Future<List<ServerPet>> pets() async {
    final json = await _send(() => _authed.getJson(Uri.parse('$baseUrl/api/dogs')));
    return (json as List)
        .whereType<Map<String, dynamic>>()
        .map(ServerPet.tryParse)
        .whereType<ServerPet>()
        .toList();
  }

  /// 반려동물 등록. 산책을 저장하려면 **적어도 한 마리가 있어야 한다.**
  Future<ServerPet> registerPet({
    required String name,
    required ServerPetSpecies species,
    required ServerPetSize size,
    String? breed,
  }) async {
    final json = await _send(
      () => _authed.postJson(
        Uri.parse('$baseUrl/api/dogs'),
        body: {
          'name': name,
          'species': species.wire,
          'size': size.wire,
          if (breed != null && breed.isNotEmpty) 'breed': breed,
        },
      ),
    );
    final pet = ServerPet.tryParse(json as Map<String, dynamic>);
    if (pet == null) throw const WalkFailure(WalkFailureKind.network);
    return pet;
  }

  // ─────────────────────────── 산책 ───────────────────────────

  /// 산책 하나를 저장한다.
  ///
  /// **재전송은 새 줄을 만들지 않는다** — 같은 [clientWalkId] 면 서버가 200 과 함께
  /// 이미 저장된 행을 준다. 부르는 쪽은 201 과 200 을 같게 취급하면 된다.
  ///
  /// [path] 는 **`[경도, 위도]`** 순서다. 앱의 `NLatLng(위도, 경도)` 를 그대로 실으면
  /// 서버가 400 으로 거절한다(계약이 그렇게 선언했고 서버가 검사한다).
  Future<ServerWalk> saveWalk({
    required int dogId,

    /// 함께 나간 아이들 (#343). **비어 있으면 안 보낸다** — 계약이 선택으로 받고,
    /// 서버가 `[dogId]` 로 채운다. 빈 배열을 보내도 같은 뜻이지만, 안 보내는 쪽이
    /// "이 앱은 여러 마리를 모른다" 와 같은 모양이라 서버 쪽 갈래가 하나 준다.
    List<int> dogIds = const [],
    required String clientWalkId,
    required DateTime startedAt,
    DateTime? endedAt,
    required int distanceM,
    required int durationS,
    List<List<double>>? path,

    /// 각 점의 시각 — 시작 기준 델타 초. **`path` 와 길이가 같아야 한다** (#155).
    List<int>? pathT,
    String? memo,
    String? weather,

    /// 어디를 걸었나 (#338). 카탈로그에서 고른 곳이면 출처·id 가 함께 간다.
    WalkPlaceRef? place,
  }) async {
    final uploadPath = LocationUploadPolicy.pathForUpload(path);
    final uploadPathT = LocationUploadPolicy.pathTimesForUpload(pathT);

    final json = await _send(
      () => _authed.postJson(
        Uri.parse('$baseUrl/api/walks'),
        body: {
          'dogId': dogId,
          if (dogIds.isNotEmpty) 'dogIds': dogIds,
          'clientWalkId': clientWalkId,
          // 서버는 오프셋이 있는 값을 요구한다. toUtc() 를 빼면 Dart 가 오프셋 없는
          // 문자열을 만들고 서버가 400 을 준다.
          'startedAt': startedAt.toUtc().toIso8601String(),
          if (endedAt != null) 'endedAt': endedAt.toUtc().toIso8601String(),
          'distanceM': distanceM,
          'durationS': durationS,
          // 좌표가 기기를 떠나도 되는지는 **여기서 안 정한다** — 정책 한 곳이 정한다(#235).
          // 꺼져 있으면 null 이 되어 아래 조건이 통째로 거짓이 되고, 산책은 경로 없이
          // 저장된다(서버가 path 를 optional 로 받는다).
          if (uploadPath != null && uploadPath.length >= 2) 'path': uploadPath,
          // path 를 실을 때만 함께 싣는다. 길이가 다르면 서버가 400 이고, path 를 뺀
          // 채로 pathT 만 보내도 400 이다 — 경로 없는 시각은 뜻이 없다. (#155)
          if (uploadPath != null &&
              uploadPath.length >= 2 &&
              uploadPathT != null &&
              uploadPathT.length == uploadPath.length)
            'pathT': uploadPathT,
          if (memo != null && memo.isNotEmpty) 'memo': memo,
          if (weather != null && weather.isNotEmpty) 'weather': weather,
          // 장소는 좌표가 아니다 — 카탈로그의 이름·식별자라 정책(#235)과 무관하다.
          if (place != null) 'placeName': place.title,
          if (place != null && place.isCatalog) 'placeSource': place.source,
          if (place != null && place.isCatalog) 'placeContentId': place.contentId,
        },
      ),
    );
    final walk = ServerWalk.tryParse(json as Map<String, dynamic>);
    if (walk == null) throw const WalkFailure(WalkFailureKind.network);
    return walk;
  }

  /// 내 산책 목록. **경로는 실려 오지 않는다** — 상세에서만 온다.
  Future<ServerWalkPage> walks({int? dogId, String? cursor, int? limit}) async {
    final query = <String, String>{
      if (dogId != null) 'dogId': '$dogId',
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      if (limit != null) 'limit': '$limit',
    };
    final uri = Uri.parse('$baseUrl/api/walks').replace(
      queryParameters: query.isEmpty ? null : query,
    );

    final json = await _send(() => _authed.getJson(uri)) as Map<String, dynamic>;
    return ServerWalkPage(
      items: (json['items'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ServerWalk.tryParse)
          .whereType<ServerWalk>()
          .toList(),
      nextCursor: json['nextCursor'] as String?,
      hasMore: json['hasMore'] == true,
    );
  }

  /// 산책 하나. **경로가 여기에만 있다.**
  Future<ServerWalk> walk(int walkId) async {
    final json = await _send(
      () => _authed.getJson(Uri.parse('$baseUrl/api/walks/$walkId')),
    );
    final walk = ServerWalk.tryParse(json as Map<String, dynamic>);
    if (walk == null) throw const WalkFailure(WalkFailureKind.network);
    return walk;
  }

  /// 반려동물 프로필을 지운다 — 서버는 **소프트 삭제**라 산책 기록은 남는다(#156).
  /// 성공은 본문 없는 204. 이미 지웠거나 내 것이 아니면 404 → [WalkFailureKind.notFound].
  Future<void> deletePet(int dogId) async {
    await _send(() => _authed.deleteJson(Uri.parse('$baseUrl/api/dogs/$dogId')));
  }

  Future<void> deleteWalk(int walkId) async {
    await _send(() => _authed.deleteJson(Uri.parse('$baseUrl/api/walks/$walkId')));
  }

  /// 회고 글을 통째로 바꾼다 — 이슈 #187.
  ///
  /// **하위 리소스 PUT 이라 뜻이 하나다** — "메모를 이 값으로 바꾼다". `PATCH` 로 두면
  /// "필드를 안 보냈다" 와 "null 로 지워라" 를 구분해야 하는데 바꿀 필드가 하나뿐이라
  /// 그 복잡도가 값을 못 한다.
  ///
  /// 빈 문자열은 **"다 지웠다" 는 정상 요청**이다. 서버가 그것을 `null` 로 눕혀 저장하고,
  /// 바뀐 뒤의 산책을 돌려준다 — 화면이 다시 조회하지 않아도 갱신할 수 있다.
  Future<ServerWalk> rewriteMemo(int walkId, String memo) async {
    final json = await _send(() => _authed.putJson(
          Uri.parse('$baseUrl/api/walks/$walkId/memo'),
          body: {'memo': memo},
        ));
    final walk = ServerWalk.tryParse(json as Map<String, dynamic>);
    if (walk == null) throw const WalkFailure(WalkFailureKind.network);
    return walk;
  }

  /// 이번 주 + 전체 기간. **한 번에 온다** — 화면이 두 번 부르지 않는다.
  Future<ServerWalkStats> stats({int? dogId}) async {
    final uri = Uri.parse('$baseUrl/api/walks/stats/weekly').replace(
      queryParameters: dogId == null ? null : {'dogId': '$dogId'},
    );
    final json = await _send(() => _authed.getJson(uri));
    return ServerWalkStats.parse(json as Map<String, dynamic>);
  }

  // ─────────────────────────── 지그 ───────────────────────────

  /// 한 번의 왕복. **상태 코드를 실패의 종류로 옮기는 곳이 여기 하나다.**
  ///
  /// 호출부마다 `res.statusCode` 를 읽게 두면 "다시 보내도 되는 실패" 와 "그러면
  /// 안 되는 실패" 의 판정이 여러 곳에 생기고, 그 중 한 곳만 틀려도 전송 대기 큐가
  /// 영원히 같은 요청을 재시도한다.
  Future<Object?> _send(Future<http.Response> Function() request) async {
    final http.Response res;
    try {
      res = await request().timeout(timeout);
    } on WalkFailure {
      rethrow;
    } catch (_) {
      // 예외 메시지에 URL·본문 조각이 섞일 수 있어 타입도 문구도 옮기지 않는다.
      throw const WalkFailure(WalkFailureKind.network);
    }

    // 204 는 본문이 없다(삭제). 200·201 은 재전송과 첫 저장이라 같게 다룬다.
    if (res.statusCode == 204) return null;
    if (res.statusCode == 200 || res.statusCode == 201) {
      if (res.bodyBytes.isEmpty) return null;
      try {
        // bodyBytes + utf8 로 읽는다. `res.body` 는 charset 이 없는 응답을 latin-1 로
        // 읽어 한글이 깨진다.
        return jsonDecode(utf8.decode(res.bodyBytes));
      } catch (_) {
        throw const WalkFailure(WalkFailureKind.network);
      }
    }

    throw WalkFailure(switch (res.statusCode) {
      400 => WalkFailureKind.rejected,
      401 => WalkFailureKind.unauthorized,
      404 => WalkFailureKind.notFound,
      409 => WalkFailureKind.rejected,
      429 => WalkFailureKind.rateLimited,
      _ => WalkFailureKind.network,
    });
  }
}
