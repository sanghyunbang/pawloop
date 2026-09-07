// 위치기반서비스 약관이 **이 빌드에 대해 참인 말**을 하는지 본다 — 이슈 #273.
//
// ## 왜 필요한가
//
// v1.0 은 "현재 위치를 기준으로 가까운 장소를 찾아 보여 줍니다" 라고 적고, 파기 조항에
// "주변 장소 안내를 위해 조회한 현재 위치는 응답을 만드는 데에만 쓰이며" 라고 적었다.
// **그건 서버가 좌표를 받는 빌드의 이야기다.** 배포본은 A안(완전 온디바이스)이라
// 좌표를 보내지 않는데, 약관이 보낸다고 말하고 있었다.
//
// 지금은 반대 방향의 위험이 생겼다 — v1.1 이 "보내지 않습니다" 라고 **단언**한다.
// 신고를 마치고 `--dart-define=UPLOAD_LOCATION=true` 로 켜는 날(#200), 코드는 한 줄도
// 안 고치고 그 단언이 거짓이 된다.
//
// 지키지 못할 약속을 화면에 띄우는 것이 정책 위반보다 더 위험하다 —
// `account_delete_screen.dart` 가 #82 때 적어 둔 문장이고, 여기가 세 번째 자리다.
//
// ## 어떻게 재는가
//
// [LocationUploadPolicy.resetForTest] 는 **빌드에 박힌 값**으로 되돌린다. 그래서 그
// 뒤의 `uploadsLocation` 이 곧 이 빌드의 진실이고, 약관이 그것과 같은 말을 하는지 본다.
//
// `flutter test --dart-define=UPLOAD_LOCATION=true` 로 돌리면 이 검사가 반대쪽을 잰다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/data/location_upload_policy.dart';

/// 위치기반서비스 이용약관. 앱이 설정 > 약관에서 이 파일을 그대로 읽어 보여 준다.
File get _location => File('assets/terms/location_ko.md');

/// 약관이 "서버로 안 보낸다" 고 단언하는 문장들.
const List<String> _onDeviceClaims = [
  '현재 위치를 회사\n   서버로 보내지 않습니다',
  '개인위치정보가 기기를 떠나지 않습니다',
];

String _read() {
  if (!_location.existsSync()) {
    fail('${_location.path} 가 없습니다. 테스트를 app/ 에서 돌리고 있는지 확인하세요.');
  }
  // 줄바꿈으로 끊긴 문장을 한 줄로 본다 — 문서가 80칸에서 접혀 있다.
  return _location.readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
}

void main() {
  setUp(() {
    // 이 검사만은 **빌드에 박힌 값**을 봐야 한다. 다른 테스트가 갈아끼워 놓은 것을
    // 물려받으면 배포본이 아니라 그 테스트에 대해 재게 된다.
    LocationUploadPolicy.resetForTest();
  });

  group('위치 약관이 이 빌드를 설명한다', () {
    test('A안 빌드면 "서버로 안 보낸다" 고 적혀 있어야 한다', () {
      if (LocationUploadPolicy.uploadsLocation) {
        return; // 아래 검사가 이 경우를 맡는다.
      }
      final text = _read();

      for (final claim in _onDeviceClaims) {
        expect(
          text,
          contains(claim.replaceAll(RegExp(r'\s+'), ' ')),
          reason: '''
좌표를 안 보내는 빌드인데 약관이 그 말을 안 하면, 이용자는 자기 위치가 서버에 있다고
읽는다. 실제보다 나쁜 쪽으로 읽히는 것도 부정확한 고지다.''',
        );
      }
    });

    test('B안 빌드면 그 단언이 남아 있으면 안 된다 — 켜는 순간 거짓이 된다', () {
      if (!LocationUploadPolicy.uploadsLocation) {
        return; // 위 검사가 이 경우를 맡는다.
      }
      final text = _read();

      for (final claim in _onDeviceClaims) {
        expect(
          text,
          isNot(contains(claim.replaceAll(RegExp(r'\s+'), ' '))),
          reason: '''
--dart-define=UPLOAD_LOCATION=true 로 켜면 좌표가 서버로 나간다(#200). 코드는 한 줄도
안 고치고 이 문장이 거짓이 되므로, 그 빌드를 만들 때 약관도 함께 개정해야 한다.
이 검사가 그것을 잊지 못하게 한다.''',
        );
      }
    });

    test('버전과 시행일이 적혀 있다 — 개정 이력이 없으면 어느 것에 동의했는지 모른다', () {
      expect(_read(), contains('버전: v1.3'));
      expect(_read(), contains('시행일: 2026-09-14'));
    });

    test('안전 지수가 공공 API 를 기기에서 직접 부르고 위경도는 안 보낸다고 적혀 있다(#336)', () {
      expect(_read(), contains('산책 안전 지수'));
      expect(_read(), contains('기기에서 직접'));
      expect(_read(), contains('위경도 자체는 보내지 않으며'));
    });

    test('화면이 꺼져 있어도 기록 중에는 읽는다고 적혀 있다 — 포그라운드 서비스를 넣은 빌드다(#335)', () {
      expect(_read(), contains('화면이 꺼져 있거나 다른 앱을 보고 있어도'));
      expect(_read(), contains('기록을 끝내면 읽기를 멈춥니다'));
    });
  });
}
