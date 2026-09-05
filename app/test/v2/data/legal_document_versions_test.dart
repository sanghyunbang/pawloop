// `LegalDocument.version` 이 문서 파일 머리의 `버전:` 과 같은지 본다 — 이슈 #190.
//
// ## 왜 필요한가
//
// 동의는 서버에 버전과 함께 남고, 재동의는 앱이 "지금 문서 버전 == 서버가 적어 둔 버전"
// 을 견줘서 정한다(ADR-0020). 그 "지금 문서 버전" 이 코드의 상수라, 문서를 고치고 상수를
// 안 올리면 **아무도 다시 동의하지 않는다** — 약관을 v1.2 로 올렸는데 키에 버전이 없어
// 아무도 새 조항을 안 본 것이 #190 의 출발점이었다. 반대로 상수만 올리고 문서를 안 고치면
// 아무 이유 없이 전원이 다시 동의 화면을 본다.
//
// 그래서 문서 파일과 상수를 함께 잰다. 값을 재는 것이지 모양만 재는 것이 아니다 —
// 형식 검사는 값 오차를 못 잡는다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/data/consent_repository.dart';
import 'package:heat_trip_flutter/v2/screens/settings/legal_document_screen.dart';

String _versionInFile(String assetPath) {
  final file = File(assetPath);
  if (!file.existsSync()) {
    fail('$assetPath 가 없습니다. 테스트를 app/ 에서 돌리고 있는지 확인하세요.');
  }
  final match = RegExp(r'^버전:\s*(v\d+\.\d+)', multiLine: true)
      .firstMatch(file.readAsStringSync());
  if (match == null) {
    fail('$assetPath 머리에 "버전: vX.Y" 줄이 없습니다 — 다른 문서 셋과 같은 모양이어야 합니다');
  }
  return match.group(1)!;
}

void main() {
  for (final doc in LegalDocument.values) {
    test('${doc.name} 의 코드 버전이 문서 파일의 버전과 같다', () {
      expect(doc.version, _versionInFile(doc.assetPath), reason: '''
${doc.assetPath} 를 고쳤으면 LegalDocument.${doc.name} 의 버전도 올려야 한다(그래야 전원이
다시 동의한다). 반대로 상수만 올렸으면 문서도 그 버전으로 게시해야 한다.''');
    });
  }

  test('버전은 서버 계약의 모양(vX.Y)이다 — 아니면 서버가 400 으로 거절한다', () {
    for (final doc in LegalDocument.values) {
      expect(doc.version, matches(RegExp(r'^v\d+\.\d+$')));
    }
  });

  test('문서 넷이 서버의 문서 이름 넷과 일대일이다', () {
    final kinds = LegalDocument.values.map((d) => d.kind).toSet();
    expect(kinds, ConsentKind.values.toSet(),
        reason: '한쪽에만 있는 문서는 동의를 받을 수도, 적을 수도 없다');
  });
}
