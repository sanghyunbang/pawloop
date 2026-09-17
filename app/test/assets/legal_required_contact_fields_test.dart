// 두 문서가 **법이 이름을 대어 요구하는 칸**을 들고 있는가 — 이슈 #682.
//
// ## 무엇이 빠져 있었나
//
// `privacy_ko.md` 12항은 이메일 두 줄뿐이었다. 「개인정보 보호법」 제30조제1항제6호는
// 개인정보 보호책임자의 **성명**(또는 개인정보 보호업무 및 관련 고충사항을 처리하는 부서의
// 명칭)과 **전화번호 등 연락처**를 처리방침에 적도록 한다. 이메일만으로는 "성명 또는
// 부서의 명칭" 이 없다.
//
// `location_ko.md` 제11조는 상호·서비스명·이메일뿐이었다. 「위치정보의 보호 및 이용 등에
// 관한 법률」 제19조제1항제1호는 위치기반서비스사업자의 **상호·주소·전화번호 그 밖의
// 연락처**를 이용약관에 명시하도록 한다. 주소와 전화번호가 없었다.
//
// ## 왜 "값" 이 아니라 "칸" 을 재는가
//
// 성명·전화번호·주소는 사장님이 정하는 값이라 지금 저장소에 없다. 없는 값을 지어 넣으면
// 심사자와 이용자에게 **거짓말이 된다** — 연락이 안 닿는 번호가 적힌 처리방침은 아예 없는
// 것보다 나쁘다. 그래서 자리를 만들고 비어 있다는 것을 문서가 스스로 말하게 했다.
//
// 이 검사가 잠그는 것은 셋이다.
//
// 1. **칸이 사라지지 않는다.** 나중에 12항·제11조를 손보다가 성명이나 주소 줄을 지우면
//    법정 기재사항이 조용히 다시 빠진다.
// 2. **빈 칸이 조용히 비어 있지 않는다.** `- 성명:` 뒤가 아무것도 없는 줄이면 이용자는
//    문서가 깨진 줄 안다. 값이 없으면 [kBlank] 표시가 있어야 한다.
// 3. **가짜 값이 못 들어온다.** `홍길동` · `000-0000-0000` 같은 견본이 들어오면 빨간불이다.
//
// 값이 다 채워져도 이 검사는 초록이다 — 자리표시가 사라지고 진짜 값이 그 자리에 오면
// 1·2·3 이 모두 만족된다. **값이 들어오는 날 고칠 것은 이 파일이 아니라 문서의 버전이다.**

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 값이 아직 없는 칸에 적는 **단 하나의** 표시.
///
/// 두 문서가 같은 말을 써야 출시 전에 `grep` 한 번으로 남은 칸을 전부 찾는다.
const String kBlank = '(아직 비어 있습니다)';

File get _privacy => File('assets/terms/privacy_ko.md');
File get _location => File('assets/terms/location_ko.md');

String _read(File f) {
  if (!f.existsSync()) {
    fail('${f.path} 가 없습니다. 테스트를 app/ 에서 돌리고 있는지 확인하세요.');
  }
  return f.readAsStringSync();
}

/// `- 라벨: 값` 줄에서 값만 꺼낸다. 그런 줄이 없으면 `null` — 칸 자체가 없다는 뜻이다.
///
/// 공백을 `\s` 가 아니라 **`[ \t]` 로** 잡는다. `\s` 는 줄바꿈도 먹어서 `- 주소:` 처럼 값이
/// 빈 줄이면 다음 줄의 값을 끌어다 붙인다 — 그러면 "빈 칸" 을 재는 검사가 늘 초록이다.
/// 실제로 그랬다: 값을 지우는 변형을 넣었는데 통과했다.
String? _field(String source, String label) {
  final match =
      RegExp('^-[ \\t]*$label:[ \\t]*(.*)\$', multiLine: true).firstMatch(source);
  return match?.group(1)?.trim();
}

/// 한 문서의 칸들을 한꺼번에 잰다 — 있는가, 그리고 비어 있지 않은가.
void _expectFields(File file, List<String> labels, {required String law}) {
  final source = _read(file);
  for (final label in labels) {
    final value = _field(source, label);
    expect(value, isNotNull, reason: '''
${file.path} 에 "- $label:" 줄이 없습니다. $law 가 이름을 대어 요구하는 칸이라,
지우면 법정 기재사항이 다시 빠집니다.''');
    expect(value, isNotEmpty, reason: '''
${file.path} 의 "- $label:" 이 빈 줄입니다. 값이 아직 없으면 $kBlank 라고 적어
**비어 있다는 사실을 문서가 말하게** 해야 합니다 — 빈 줄은 문서가 깨진 것으로 읽힙니다.''');
  }
}

void main() {
  group('개인정보처리방침 12항 — 개인정보 보호법 제30조제1항제6호', () {
    test('보호책임자의 직위·성명·전화번호·이메일 칸이 있고 비어 있지 않다', () {
      _expectFields(
        _privacy,
        const ['직위', '성명', '전화번호', '이메일'],
        law: '개인정보 보호법 제30조제1항제6호',
      );
    });

    test('문서가 근거 조문을 스스로 댄다', () {
      // 근거를 안 적으면 다음에 이 절을 손대는 사람이 "이메일만 있으면 되지 않나" 로
      // 되돌린다. 실제로 되돌아가 있던 것이 #682 다.
      expect(_read(_privacy), contains('제30조제1항제6호'));
    });

    test('비어 있는 칸이 있다는 것을 본문이 말한다', () {
      final source = _read(_privacy);
      if (!source.contains(kBlank)) return; // 값이 다 채워졌다 — 설명할 칸이 없다.

      expect(source, contains('아직 비어 있습니다'), reason: '''
자리표시만 있고 왜 비어 있는지·언제 채우는지·그동안 어디로 연락하면 되는지를 안 적으면,
이용자는 회사가 연락처를 숨긴 것으로 읽습니다.''');
      expect(source, contains('위 이메일로'),
          reason: '칸이 비어 있어도 연락이 닿는 길은 있어야 합니다');
    });
  });

  group('위치기반서비스 이용약관 제11조 — 위치정보법 제19조제1항제1호', () {
    test('사업자의 상호·주소·전화번호·이메일 칸이 있고 비어 있지 않다', () {
      _expectFields(
        _location,
        const ['상호', '주소', '전화번호', '이메일'],
        law: '위치정보법 제19조제1항제1호',
      );
    });

    test('위치정보관리책임자의 직위·성명·연락처 칸이 있다', () {
      _expectFields(
        _location,
        const ['직위', '성명', '연락처'],
        law: '위치기반서비스사업 신고서의 관리책임자 기재사항',
      );
    });

    test('문서가 근거 조문을 스스로 댄다', () {
      expect(_read(_location), contains('제19조제1항제1호'));
    });

    test('비어 있는 칸이 있다는 것을 본문이 말한다', () {
      final source = _read(_location);
      if (!source.contains(kBlank)) return;

      expect(source, contains('아직 비어 있습니다'));
      expect(source, contains('위 이메일로'),
          reason: '칸이 비어 있어도 제7조의 권리를 행사할 길은 있어야 합니다');
    });
  });

  group('빈 칸과 가짜 값', () {
    test('빈 칸 표시는 두 문서가 같은 한 가지만 쓴다', () {
      // 표시가 여러 꼴로 갈리면 출시 전에 "남은 칸" 을 한 번에 못 찾는다.
      for (final file in [_privacy, _location]) {
        final drifted = RegExp(r'\(아직[^)]*\)')
            .allMatches(_read(file))
            .map((m) => m.group(0)!)
            .where((s) => s != kBlank)
            .toSet();

        expect(drifted, isEmpty, reason: '''
${file.path} 가 $kBlank 말고 다른 꼴의 빈 칸 표시를 씁니다: $drifted''');
      }
    });

    test('견본 값이 문서에 들어와 있지 않다', () {
      // 자리를 만들어 두면 "일단 아무거나" 가 들어오기 쉽다. 연락이 안 닿는 번호가 적힌
      // 처리방침은 칸이 비어 있는 것보다 나쁘다 — 이용자는 그 번호로 걸어 본다.
      const fakes = [
        '홍길동',
        '아무개',
        'TBD',
        'TODO',
        'example.com',
        '000-0000-0000',
        '010-0000-0000',
        '02-0000-0000',
        '1234-5678',
      ];
      for (final file in [_privacy, _location]) {
        final source = _read(file);
        for (final fake in fakes) {
          expect(source, isNot(contains(fake)), reason: '''
${file.path} 에 견본 값 "$fake" 가 있습니다. 값이 없으면 $kBlank 로 두십시오 —
가짜 연락처는 빠진 연락처보다 나쁩니다.''');
        }
      }
    });
  });
}
