// 위치정보 확인자료의 보관 기간을 문서와 약관이 **같은 숫자**로 말하는지 본다.
//
// ## 무엇이 어긋나 있었나 (2026-09-05)
//
// `docs/00-product/legal-lbs-compliance.md` 는 다섯 곳에서 "제16조, 1년 보관 의무" 라고
// 적었고, 배포되는 약관 `location_ko.md` 와 `privacy_ko.md` 는 "제16조제2항에 따라
// 6개월 이상" 이라고 적었다. 같은 조문에 다른 숫자가 붙어 있었다.
//
// ## 법령이 정한 숫자는 없다
//
// 위치정보법 제16조제2항은 "확인자료를 위치정보시스템에 자동으로 기록되고 보존되도록"
// 하라고만 한다. 시행령에도 이 자료의 일반 보존 기간 조문은 없다(제30조의2 의 3개월은
// 수사기관 등의 **제공 요청** 기록에 대한 것이라 다른 자료다). "1년" 은 어디에도 근거가
// 없었다 — 통신비밀보호법의 통신사실확인자료(12개월)와 섞인 것으로 보인다.
//
// 업계는 방통위 표준약관을 따라 전부 "6개월(이상)" 이다 — 카카오 · KT · GS리테일 ·
// 한국관광공사(대한민국 구석구석) 약관이 모두 제16조제2항을 대고 6개월을 적는다.
// 그래서 **6개월 이상**으로 통일한다. 이 검사는 두 문서가 다시 갈라지지 않게 잠근다.
//
// 약관은 앱이 설정 > 약관에서 그대로 읽어 보여 주는 파일이라 여기(app/)에서 잰다.
// 문서는 저장소 루트의 docs/ 라 상대 경로로 올라간다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

File get _locationTerms => File('assets/terms/location_ko.md');
File get _privacy => File('assets/terms/privacy_ko.md');
File get _complianceDoc => File('../docs/00-product/legal-lbs-compliance.md');

String _read(File f) {
  if (!f.existsSync()) {
    fail('${f.path} 가 없습니다. 테스트를 app/ 에서 돌리고 있는지 확인하세요.');
  }
  return f.readAsStringSync();
}

void main() {
  test('약관 둘이 확인자료 보관 기간을 6개월 이상이라고 말한다', () {
    expect(_read(_locationTerms), contains('6개월 이상'),
        reason: '위치기반서비스 약관 제6조3 — 제16조제2항 확인자료');
    expect(_read(_privacy), contains('6개월 이상'),
        reason: '개인정보처리방침의 같은 조항');
  });

  test('컴플라이언스 문서가 약관과 다른 숫자(1년)를 말하지 않는다', () {
    final doc = _read(_complianceDoc);
    final oneYearClaims = RegExp(r'1년(간|\s*보관|\s*보존)').allMatches(doc).length;

    expect(oneYearClaims, 0, reason: '''
같은 조문(제16조제2항)에 약관은 6개월, 문서는 1년을 붙여 두면 어느 쪽이 회사의 약속인지
아무도 모른다. 법령은 숫자를 정하지 않고, 업계 표준약관은 6개월이다 — 문서를 그쪽으로
맞췄다. 다시 1년으로 적으려면 근거 조문을 먼저 대야 한다.''');
    expect(doc, contains('6개월 이상'));
  });
}
