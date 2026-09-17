// 지도를 옮기면 그 지역을 다시 찾을 수 있는가, 뭉친 곳이 개수를 말하는가 — 이슈 #628.
//
// 2026-09-17 실기기: 목록에는 80곳인데 **지도에는 하나만** 떴고, 지도를 끌어도 아무 일이
// 없었다. 원인이 둘이었다.
//
//   - `_clusterMarker` 가 개수를 안 적었다. 패키지 기본 빌더는 적는데, 아이콘을 쓰려고
//     빌더를 덮으면서 같이 잃었다 — 80곳이 한 점으로 뭉쳐도 숫자가 없다
//   - `onCameraIdle` 을 아예 안 듣고 있었다. 다시 받는 코드가 한 줄도 없었다
//
// 지도 SDK 는 위젯 테스트에 없다. 그래서 **판단만** 잰다 — 화면은 사장님이 실기기에서
// 본다. 여기서 지키는 것은 "숫자가 조용히 바뀌지 않는 것" 이다.
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/data/location_upload_policy.dart';
import 'package:heat_trip_flutter/v2/screens/explore_screen.dart';

void main() {
  // 노원구 중계동 — 사장님이 걸어 본 자리.
  const here = NLatLng(37.6447, 127.0654);

  group('이 지역에서 다시 찾기', () {
    test('조금 움직인 것으로는 안 띄운다 — 같은 답을 다시 받게 된다', () {
      // 위도 0.001° ≈ 111m. 0.008° ≈ 890m 로 문턱(1km) 아래다.
      expect(ExploreMap.researchTarget(here, const NLatLng(37.6527, 127.0654)), isNull);
    });

    test('1km 넘게 옮기면 그 지점을 준다 — 다른 동네를 보는 중이다', () {
      const moved = NLatLng(37.6647, 127.0654); // 0.02° ≈ 2.2km
      expect(ExploreMap.researchTarget(here, moved), moved);
    });

    test('경도로 움직여도 잰다 — 위도만 보면 옆으로 간 것을 못 본다', () {
      // 위도 37.64 에서 경도 0.02° ≈ 1.76km.
      const sideways = NLatLng(37.6447, 127.0854);
      expect(ExploreMap.researchTarget(here, sideways), sideways);
    });

    test('제자리면 안 띄운다', () {
      expect(ExploreMap.researchTarget(here, here), isNull);
    });
  });

  group('드래그하면 바로 거를 것인가', () {
    tearDown(LocationUploadPolicy.resetForTest);

    test('기기 안에서 거르는 빌드는 바로 한다 — 부를 서버가 없다', () {
      LocationUploadPolicy.setForTest(false);
      expect(ExploreMap.refiltersOnDrag, isTrue,
          reason: '전국 한 벌이 기기에 있는데 버튼을 눌러 달라고 할 이유가 없다');
    });

    test('서버를 부르는 빌드는 버튼으로 묻는다 — 끄는 동안 계속 부르면 안 된다', () {
      LocationUploadPolicy.setForTest(true);
      expect(ExploreMap.refiltersOnDrag, isFalse);
    });

    test('기본값은 기기 안 — UPLOAD_LOCATION 을 안 켠 빌드다', () {
      LocationUploadPolicy.resetForTest();
      expect(ExploreMap.refiltersOnDrag, isTrue);
    });
  });

  group('뭉친 곳의 개수', () {
    test('숫자를 그대로 적는다', () {
      expect(ExploreMap.clusterCaption(80).text, '80');
      expect(ExploreMap.clusterCaption(2).text, '2');
    });

    test('흰 글자에 테두리는 없다 — 코랄 원 안에 놓인다', () {
      final caption = ExploreMap.clusterCaption(12);
      expect(caption.color.toARGB32(), 0xFFFFFFFF);
      expect(caption.haloColor.a, 0, reason: '테두리가 있으면 원 안에서 지저분하다');
    });
  });
}
