// 공개 코스가 약관에 적혀 있는가 — 이슈 #339.
//
// ## 왜 파일을 읽어 재는가
//
// 코스를 공개하면 그 선이 **다른 사람에게 보인다.** 화면에 그 기능이 있는데 방침에 그 말이
// 없으면, 사용자는 자기가 무엇에 동의했는지 모르는 채로 길을 공개하게 된다. 반대로 방침에만
// 적고 화면이 다르게 굴어도 안 된다 — 그래서 문서와 코드의 상수를 함께 잰다.
//
// `location_terms_match_the_build_test` 가 위치 약관에 대해 같은 일을 한다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `expect` 는 테스트 **안에서만** 쓸 수 있다 — main 본문에서 부르면 로딩 단계에서 죽는다.
/// 그래서 여기서는 던지기만 한다.
String _read(File file) {
  if (!file.existsSync()) {
    throw StateError('${file.path} 가 없다 — 경로가 바뀌었으면 이 테스트도 함께 고친다');
  }
  return file.readAsStringSync();
}

void main() {
  final privacy = _read(File('assets/terms/privacy_ko.md'));

  test('개인정보처리방침이 공개 코스를 말한다 — 무엇이 보이고 무엇이 잘리는지', () {
    expect(privacy, contains('공개 코스는 다른 이용자에게 보입니다'),
        reason: '기능이 화면에 있는데 방침에 없으면 사용자는 무엇에 동의했는지 모른다');
    expect(privacy, contains('기본이 비공개'),
        reason: '공개는 사용자가 하는 일이라는 것이 이 기능의 전제다');
    // 줄바꿈이 문장 가운데 있다 — 두 조각으로 나눠 잰다.
    expect(privacy, contains('시작과 끝'),
        reason: '잘라 내는 것이 곧 "집을 알리지 않는다" 의 내용이다');
    expect(privacy, contains('각각 100m 를 잘라 낸 뒤'));
    expect(privacy, contains('비공개로 바꾸면 지도와 글에서 함께 사라집니다'));
  });

  test('수집 항목에 코스가 있다 — 만든 것을 안 적으면 목록이 거짓이 된다', () {
    expect(privacy, contains('**코스**(산책 경로에서 만든 길·이름·소개)'));
  });

  test('버전이 올랐다 — 내용이 바뀌면 다시 동의를 받는다', () {
    expect(privacy, contains('버전: v1.5'),
        reason: '공개 범위가 늘어난 것은 다시 알려야 하는 변경이다');

    final screen = _read(File('lib/v2/screens/settings/legal_document_screen.dart'));
    expect(screen, contains("ConsentKind.privacy, 'v1.5'"),
        reason: '문서만 올리고 상수를 안 올리면 아무에게도 다시 안 묻는다');
  });
}
