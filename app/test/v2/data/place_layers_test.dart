import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:heat_trip_flutter/v2/data/location_upload_policy.dart';
import 'package:heat_trip_flutter/v2/domain/pet.dart';
import 'package:heat_trip_flutter/v2/data/pet_places_repository.dart';
import 'package:heat_trip_flutter/v2/data/place_catalog_repository.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 병원·펫샵·산책로 항목이 카탈로그 한 벌에 섞여 올 때 — 이슈 #291.
///
/// 계약(`Place`)대로 `kto` 가 아닌 출처는 `contentTypeId` 가 없고 `category`(= `source`)가
/// 칩 키다. 앱이 `contentTypeId` 만 보면 그 셋은 전부 "기타" 가 되고 어느 칩에도 안 잡힌다 —
/// 목은 계약에서 만든다(#82).
void main() {
  /// 계약의 Place 모양 그대로 — 서버 `PlaceDto` 가 내보내는 키다.
  const vetJson = {
    'contentId': 'vet:322000001020260003',
    'title': '늘서울피부과동물병원',
    'source': 'vet',
    'category': 'vet',
    'lat': 37.5079,
    'lng': 127.0333,
    'addr': '서울특별시 강남구 논현로 607',
    'tel': '02-518-3650',
  };
  const trailJson = {
    'contentId': 'trail:T_ROUTE_1',
    'title': '서울숲 둘레길',
    'source': 'trail',
    'category': 'trail',
    'lat': 37.5445,
    'lng': 127.0374,
    'addr': '서울 성동구',
    'summary': '2.6km · 약 40분 · 쉬움 · 순환',
  };
  const ktoJson = {
    'contentId': '2733967',
    'title': '서울숲',
    'source': 'kto',
    'category': '12',
    'contentTypeId': '12',
    'lat': 37.5445,
    'lng': 127.0374,
    'addr': '서울 성동구',
  };

  group('PetPlace 가 출처와 카테고리를 읽는다', () {
    test('kto 는 contentTypeId, 레이어는 category 가 칩 키다', () {
      final kto = PetPlace.fromJson(Map<String, dynamic>.from(ktoJson));
      final vet = PetPlace.fromJson(Map<String, dynamic>.from(vetJson));
      final trail = PetPlace.fromJson(Map<String, dynamic>.from(trailJson));

      expect(kto.categoryKey, '12');
      expect(kto.petCategory.label, '여행지');
      expect(vet.categoryKey, 'vet');
      expect(vet.petCategory.label, '동물병원');
      expect(vet.contentTypeId, isEmpty, reason: 'KTO 체계의 값이라 없다 — 계약대로');
      expect(trail.petCategory.label, '산책로');
    });

    test('산책로는 코스 번호와 요약을 든다', () {
      final trail = PetPlace.fromJson(Map<String, dynamic>.from(trailJson));
      expect(trail.isTrail, isTrue);
      expect(trail.trailCourseId, 'T_ROUTE_1');
      expect(trail.summary, '2.6km · 약 40분 · 쉬움 · 순환');
      expect(PetPlace.fromJson(Map<String, dynamic>.from(vetJson)).isTrail, isFalse);
    });

    test('출처 배지가 출처마다 다르다 — 어디서 온 데이터인지 말한다', () {
      expect(PetPlace.fromJson(Map<String, dynamic>.from(vetJson)).sourceLabel, contains('행정안전부'));
      expect(PetPlace.fromJson(Map<String, dynamic>.from(trailJson)).sourceLabel, contains('두루누비'));
      expect(PetPlace.fromJson(Map<String, dynamic>.from(ktoJson)).sourceLabel, contains('관광공사'));
    });

    test('source 가 없으면 kto 다 — 옛 응답도 읽힌다', () {
      final j = Map<String, dynamic>.from(ktoJson)..remove('source');
      expect(PetPlace.fromJson(j).source, 'kto');
    });
  });

  group('카탈로그가 레이어 키로 거른다', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('place_layers_test');
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() async {
      LocationUploadPolicy.resetForTest();
      try {
        if (await tempDir.exists()) await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    PlaceCatalogRepository repo() => PlaceCatalogRepository(
          client: MockClient((_) async => http.Response.bytes(
                utf8.encode(jsonEncode([ktoJson, vetJson, trailJson])),
                200,
                headers: {'etag': '"e1"', 'content-type': 'application/json'},
              )),
          baseUrl: 'https://example.test',
          cacheDirectory: () async => tempDir,
        );

    test('vet 칩은 병원만, 전체는 셋 다 — 거리는 기기에서 잰다', () async {
      final r = repo();

      final vets = await r.nearby(lat: 37.5079, lng: 127.0333, contentTypeId: 'vet');
      expect(vets.map((p) => p.contentId), ['vet:322000001020260003']);

      final all = await r.nearby(lat: 37.5445, lng: 127.0374, radius: 18000);
      expect(all, hasLength(3));
      expect(all.first.contentId, anyOf('2733967', 'trail:T_ROUTE_1'),
          reason: '서울숲과 그 둘레길 시작점이 같은 자리라 거리 0 이 둘이다');
    });

    test('kto 칩(12)은 병원·산책로를 안 준다', () async {
      final places = await repo().nearby(lat: 37.5445, lng: 127.0374, radius: 18000, contentTypeId: '12');
      expect(places.map((p) => p.contentId), ['2733967']);
    });

    test('산책로 칩은 반경을 안 본다 — 부산에서 물어도 서울숲 둘레길이 거리와 함께 온다 (2026-09-06 결정)', () async {
      final r = repo();

      final trails = await r.nearby(lat: 35.1796, lng: 129.0756, contentTypeId: 'trail');
      expect(trails.map((p) => p.contentId), ['trail:T_ROUTE_1'],
          reason: '코리아둘레길은 해안·접경에만 있어 도심 8km 안은 늘 비었다 — 산책로는 "가는 곳" 이다');
      expect(trails.single.distM, greaterThan(300000));

      final vets = await r.nearby(lat: 35.1796, lng: 129.0756, contentTypeId: 'vet');
      expect(vets, isEmpty, reason: '반경을 푸는 것은 산책로 칩뿐이다 — 병원은 그대로 8km 다');
    });

    /// 북쪽으로 1.1km 씩 벌린 코스 [count]개. 번호가 클수록 멀다.
    PlaceCatalogRepository trailsSpacedNorth(int count, {double from = 37.5445}) {
      final trails = List.generate(count, (i) => {
            ...trailJson,
            'contentId': 'trail:T_ROUTE_$i',
            'title': '코스 $i',
            'lat': from + i * 0.01,
          });
      return PlaceCatalogRepository(
        client: MockClient((_) async => http.Response.bytes(
              utf8.encode(jsonEncode(trails)),
              200,
              headers: {'etag': '"e2"', 'content-type': 'application/json'},
            )),
        baseUrl: 'https://example.test',
        cacheDirectory: () async => tempDir,
      );
    }

    test('산책로도 반경 안이 차 있으면 반경만 본다 — 40km 밖을 "가까운" 이라 안 부른다', () async {
      // #346 전에는 산책로만 반경을 아예 안 봤다. 코리아둘레길이 도심에서 8km 안이 늘
      // 비었기 때문이다. 동네 길 1,302개가 들어와 그 전제가 사라졌다.
      final r = trailsSpacedNorth(kTrailNearestLimit + 5);

      final nearest = await r.nearby(lat: 37.5445, lng: 127.0374, contentTypeId: 'trail');

      expect(nearest.every((p) => p.distM <= 8000), isTrue,
          reason: '반경 안이 비지 않았으면 반경 밖은 안 준다');
      expect(nearest.first.contentId, 'trail:T_ROUTE_0');
      expect(nearest.length, lessThan(kTrailNearestLimit),
          reason: '1.1km 씩 벌렸으니 8km 안은 여덟 남짓이다 — 스무 개를 채우려 넓히면 안 된다');
    });

    test('반경 안이 비면 그때만 넓혀 가까운 순 $kTrailNearestLimit개', () async {
      // 전부 100km 넘게 북쪽에 둔다 — 반경 안이 하나도 없는 상황.
      final r = trailsSpacedNorth(kTrailNearestLimit + 5, from: 38.6);

      final nearest = await r.nearby(lat: 37.5445, lng: 127.0374, contentTypeId: 'trail');

      expect(nearest, hasLength(kTrailNearestLimit),
          reason: '빈 목록을 주는 대신 넓힌다 — 산책로는 "가는 곳" 이다(#291)');
      expect(nearest.first.contentId, 'trail:T_ROUTE_0');
      expect(nearest.last.contentId, 'trail:T_ROUTE_${kTrailNearestLimit - 1}',
          reason: '거리순으로 자른다 — 넓혀도 먼 것이 앞에 오면 안 된다');
      expect(nearest.first.distM, greaterThan(8000),
          reason: '이때 화면이 "가장 가까운 코스는 N km 밖이에요" 를 띄운다(#328)');
    });

    test('한국 밖에서는 넓히지 않는다 — 9,000km 밖 코스를 "가장 가까운" 이라 부르지 않는다', () async {
      // 코스는 서울에 그대로 두고 **보는 자리**를 애플 본사(쿠퍼티노)로 옮긴다.
      // 상한이 없을 때는 8,923km 밖 코스 스무 개가 목록에 뜨고, 화면이 그것을
      // "가장 가까운 코스는 8923.0km 밖이에요" 라고 말하며 지도 카메라가 태평양을 건넜다.
      final r = trailsSpacedNorth(kTrailNearestLimit + 5);

      final abroad =
          await r.nearby(lat: 37.3349, lng: -122.0090, contentTypeId: 'trail');

      expect(abroad, isEmpty, reason: '''
한국 밖에서는 넓혀도 줄 것이 없다. 빈 목록이면 화면이 "이 지역엔 등록된 곳이 없어요" 를
그린다 — 그것이 사실이다.''');
    });

    test('백령도·울릉도만큼 멀어도 넓힌다 — 상한을 좁히면 섬이 죽는다', () async {
      // `local_trails.json` 1,302개와 행정동 3,516개를 맞대어 잰 값: 전국에서 가장 불리한
      // 옹진군 백령면이 가장 가까운 코스까지 137.9km, 울릉읍이 137.6km 다. 거기 사는
      // 사람에게는 넓히기가 바로 그 기능이다.
      //
      // 위도 1도 ≈ 111km 이므로 1.35도면 약 150km — 백령도보다도 불리한 자리다.
      final r = trailsSpacedNorth(kTrailNearestLimit + 5, from: 37.5445 + 1.35);

      final far =
          await r.nearby(lat: 37.5445, lng: 127.0374, contentTypeId: 'trail');

      expect(far, hasLength(kTrailNearestLimit), reason: '''
`kTrailWidenLimitM` 를 150km 밑으로 줄이면 백령도·울릉도에서 산책로 칩이 빈 목록이 된다.
이 검사가 없으면 상한을 10km 로 조여도 위의 국외 검사가 초록이다.''');
      expect(far.first.distM, greaterThan(140000),
          reason: '실제로 상한 근처까지 넓힌 결과여야 이 검사가 의미가 있다');
      expect(far.first.distM, lessThan(kTrailWidenLimitM),
          reason: '상한을 넘은 것이 섞이면 안 된다');
    });
  });
}
