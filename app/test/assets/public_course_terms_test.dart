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
    // v1.5 가 공개 코스(#339), v1.6 이 동네(#342), v1.7 이 지도 SDK 의 위치 처리(#483), v1.8 이 AI 주간
    // 요약의 국외 처리위탁(OpenAI, #486)이다. 수집 항목이나 처리 주체가 늘 때마다 올린다.
    // v1.9 는 수집 항목이 아니라 **12항의 법정 기재사항**이다(#682) — 개인정보 보호책임자의
    // 성명·직위·전화번호 자리를 만들었다. 이용자가 7항의 권리를 행사할 때 찾아가는 자리라
    // 같은 규칙으로 올린다. v1.10 은 기기 알림 토큰(#83) — 수집 항목이 하나 늘고, 전달을 맡는
    // Google(FCM) 이 4·5항에 들어갔다. v1.11 은 신고·차단 알림이 지나는 Slack(#715 · #780) — 처리
    // 주체가 하나 늘었다. 신고 알림은 2026-09-20 부터 나갔는데 방침이 그때 안 따라갔다.
    expect(privacy, contains('버전: v1.11'),
        reason: '수집 항목이나 처리 주체가 늘어난 것은 다시 알려야 하는 변경이다');

    final screen = _read(File('lib/v2/screens/settings/legal_document_screen.dart'));
    expect(screen, contains("ConsentKind.privacy, 'v1.11'"),
        reason: '문서만 올리고 상수를 안 올리면 아무에게도 다시 안 묻는다');
  });

  test('기기 알림 토큰이 수집 항목에 있고, 어디를 거쳐 가는지 적혀 있다 (#83)', () {
    expect(privacy, contains('기기 알림 토큰(로그인한 기기, 푸시 알림용)'),
        reason: '앱이 PUT /api/push/tokens 로 보내는 것을 방침이 말해야 한다');
    expect(privacy, contains('로그인하지 않은 기기의 토큰은 수집하지 않습니다'),
        reason: 'push_registrar 의 규칙 1 이 곧 이 문장이다');
    expect(privacy, contains('로그아웃하면 즉시 폐기'),
        reason: '서버의 UserSessionsRevoked → revokeAllOf 가 이 문장이다');
    expect(privacy, contains('Firebase Cloud Messaging 을 거쳐'),
        reason: '제목·본문이 Google 을 지난다 — 처리위탁·국외 이전 항목이 있어야 한다');
  });

  test('신고·차단 알림이 Slack 을 거쳐 간다고 4·5항에 적혀 있다 (#715 · #780)', () {
    expect(privacy, contains('Slack 으로 운영자에게 알림을 보냅니다'),
        reason: '신고된 글의 본문 앞부분과 닉네임이 Slack 을 지난다 — 처리위탁 항목이 있어야 한다');
    expect(privacy, contains('이전받는 자 Slack Technologies, LLC(미국)'),
        reason: '미국 회사의 서비스라 국외 이전 항목도 있어야 한다');

    // 방침이 말하는 길이와 서버가 실제로 자르는 길이가 같아야 한다 — 서버가 늘리면 방침이 거짓이 된다.
    final reportFiled = _read(File(
        '../backend/src/main/java/com/heattrip/heat_trip_backend/moderation/ReportFiled.java'));
    final cut = RegExp(r'BODY_PREVIEW_LENGTH = (\d+);').firstMatch(reportFiled)?.group(1);
    expect(cut, isNotNull, reason: 'ReportFiled 에서 미리보기 길이를 못 읽었다 — 이름이 바뀌었으면 함께 고친다');
    expect(privacy, contains('본문의 앞 $cut자'), reason: '서버는 본문을 앞 $cut자까지 보낸다');
    expect(privacy, contains('신고 메모의 앞 $cut자'), reason: '서버는 메모를 앞 $cut자까지 보낸다');
  });

  test('동네가 수집 항목에 있고, 보이는 단위가 구까지라고 적혀 있다 (#342)', () {
    expect(privacy, contains('동네(읍·면·동, 선택)'),
        reason: '서버가 드는 값을 안 적으면 목록이 거짓이 된다');
    expect(privacy, contains('단말이 측정한 좌표가 아닙니다'),
        reason: '이 기능이 위치기반서비스 신고 전에도 사는 이유가 그 한 문장이다');
    expect(privacy, contains('시·군·구 단위로만'),
        reason: '남에게 보이는 범위를 방침이 말해야 한다');
  });
}
