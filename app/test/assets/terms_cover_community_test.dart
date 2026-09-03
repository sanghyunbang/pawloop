// 약관과 방침이 **커뮤니티에 대해 참인 말**을 하는지 본다 — 이슈 #253.
//
// ## #253 의 구멍은 "언제 물었나" 가 아니었다
//
// 이슈는 "커뮤니티에 UGC 약관 게이트가 없다" 였는데, 실측하니 시점 요건은 이미
// 충족돼 있었다 — `auth_redirect.dart` 가 로그인한 사람을 다른 어떤 규칙보다 먼저
// `/consent` 로 붙잡고, 커뮤니티 글쓰기는 로그인이 필요하다.
//
// 비어 있던 것은 **무엇에 동의했는가** 다. 2026-09-04 이전 약관·방침에는
// '공개'·'누구나'·'비회원'·'신고'·'가리기' 가 커뮤니티에 대해 한 줄도 없었다.
//
// ## 그리고 세 군데가 거짓을 말하고 있었다
//
// `post`·`comment`·`reaction` 의 `user_id` 는 `ON DELETE SET NULL` 이다
// (`backend/mysql/post-start/14_community.sql:212·225·236`). 즉 탈퇴해도 남는다.
// 그런데
//
//  - `privacy_ko.md` 는 "본인이 남긴 기록은 파기합니다" 라고만 적고 채팅만 예외로 뒀다
//  - `privacy_ko.md` 수집 항목에 커뮤니티 글·댓글·반응이 **아예 없었다**
//  - 탈퇴 화면은 "내가 남긴 기록이 삭제되며" 라고 말했다
//
// 지키지 못할 약속을 화면에 띄우는 것이 정책 위반보다 더 위험하다 —
// `account_delete_screen.dart` 가 #82 때 스스로 적어 둔 문장이고, 커뮤니티가 붙으면서
// 같은 자리에서 두 번째로 깨졌다.
//
// ## 왜 조 번호로 재는가
//
// 문자열만 grep 하면 **조문을 지우고 다른 데 같은 말을 흘려 놔도 초록불**이 된다.
// 그래서 조 제목과 함께 잰다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 이용약관. 앱이 설정 > 약관에서 이 파일을 그대로 읽어 보여 준다.
File get _terms => File('assets/terms/terms_ko.md');

/// 개인정보처리방침.
File get _privacy => File('assets/terms/privacy_ko.md');

String _read(File file) {
  if (!file.existsSync()) {
    fail('${file.path} 가 없습니다. 테스트를 app/ 에서 돌리고 있는지 확인하세요.');
  }
  return file.readAsStringSync();
}

/// 그 조 아래의 본문만. 다음 `제N조` 전까지다.
///
/// 조를 지목해 재는 것이 이 파일의 요점이다 — 문서 아무 데나 같은 낱말이 있으면
/// 통과하는 검사는 조문이 사라져도 초록불이다.
String _article(String document, String heading) {
  final start = document.indexOf(heading);
  if (start < 0) {
    fail('$heading 가 문서에 없습니다. 조 번호를 바꿨다면 이 테스트도 함께 고치세요.');
  }
  final next = RegExp(r'\n제\d+조').firstMatch(document.substring(start + heading.length));
  return next == null
      ? document.substring(start)
      : document.substring(start, start + heading.length + next.start);
}

void main() {
  group('이용약관', () {
    test('제7조가 커뮤니티 글의 공개 범위를 적는다 — 게스트도 읽는다', () {
      final article = _article(_read(_terms), '제7조(콘텐츠의 권리)');

      expect(
        article,
        contains('로그인하지 않은 사람에게도 공개'),
        reason: 'SecurityConfig 가 커뮤니티 GET 셋을 permitAll 로 열어 뒀습니다. '
            '약관이 그 사실을 말하지 않으면, 이용자는 로그인한 사람만 본다고 믿고 씁니다.',
      );
      expect(
        article,
        contains('닉네임'),
        reason: '공개되는 것은 글만이 아닙니다 — 작성자 닉네임이 함께 나갑니다 '
            '(PersonRefResponse).',
      );
    });

    test('제7조의2가 신고와 가리기를 적는다 — Google Play UGC 정책이 요구하는 수단이다', () {
      final article = _article(_read(_terms), '제7조의2(신고와 가리기)');

      expect(article, contains('신고'));
      expect(
        article,
        contains('가리기는 삭제가 아닙니다'),
        reason: '가리기를 삭제로 오해하면, 가려 놓고 "지웠다" 고 믿습니다. '
            '실제로는 다른 이용자에게 그대로 보입니다.',
      );
      expect(
        article,
        contains('알리지 않습니다'),
        reason: '신고 사실이 상대에게 가는지는 신고할지 말지를 정하는 데 결정적입니다.',
      );
    });

    test('제9조가 탈퇴해도 커뮤니티 글이 남는다고 적는다', () {
      final article = _article(_read(_terms), '제9조(계약 해지)');

      expect(
        article,
        contains('커뮤니티'),
        reason: '14_community.sql 이 post·comment·reaction 을 ON DELETE SET NULL 로 둡니다. '
            '탈퇴해도 남는데 약관이 안 적으면 그 자체가 거짓 약속입니다.',
      );
      expect(article, contains('알 수 없음'));
      expect(
        article,
        contains('탈퇴하기 전에'),
        reason: '남는다는 사실만 적고 지우는 방법을 안 적으면, 지우고 싶은 사람이 '
            '방법을 못 찾습니다. 탈퇴 후에는 그 계정으로 못 지웁니다.',
      );
    });
  });

  group('개인정보처리방침', () {
    test('수집 항목에 커뮤니티 글·댓글·반응이 있다 — 통째로 빠져 있었다', () {
      final document = _read(_privacy);
      final section = document.substring(
        document.indexOf('1. 처리하는 개인정보 항목'),
        document.indexOf('2.'),
      );

      expect(
        section,
        contains('커뮤니티'),
        reason: '2026-09-04 이전 목록은 "산책 회고 글, 채팅 메시지, 가족 그룹의 산책 '
            '주의사항" 셋뿐이었습니다. 커뮤니티가 통째로 없었습니다.',
      );
      expect(section, contains('댓글'));
      expect(
        section,
        contains('반응'),
        reason: 'reaction 도 user_id 를 갖는 표입니다(14_community.sql:236). '
            '셋 중 하나만 빠뜨리면 그 항목이 근거 없이 수집됩니다.',
      );
    });

    test('신고 사본을 수집 항목에 적는다 — 원본이 지워져도 남는 것이다', () {
      final document = _read(_privacy);
      // **수집 항목 절 안에서** 재야 합니다. 문서 아무 데나 '신고' 가 있으면 통과하는
      // 검사는 옛 방침에서도 초록불이었습니다 — 거기 '신고' 는 채팅 파기 문장 안의
      // 낱말이었고, 수집 항목에는 사본에 대한 말이 한 줄도 없었습니다.
      final section = document.substring(
        document.indexOf('1. 처리하는 개인정보 항목'),
        document.indexOf('2.'),
      );

      expect(
        section,
        contains('신고'),
        reason: 'report_snapshot 이 본문·작성자·작성 시각을 사본으로 남깁니다. '
            '수집 항목이 안 적으면 그 사본은 근거 없는 보관입니다.',
      );
      expect(
        section,
        contains('사본'),
        reason: '신고 "사유" 만 받는 것과 글의 "사본" 을 남기는 것은 다른 수집입니다.',
      );
    });

    test('파기 조항이 커뮤니티도 남는다고 적는다 — 채팅만 예외로 적혀 있었다', () {
      final document = _read(_privacy);
      final section = document.substring(document.indexOf('3. 보유 및 파기'));

      expect(
        section,
        contains('커뮤니티'),
        reason: '"본인이 남긴 기록은 파기합니다" 는 커뮤니티에 대해 거짓이었습니다. '
            'ON DELETE SET NULL 이라 글·댓글·반응이 남습니다.',
      );
      expect(section, contains('알 수 없음'));
    });
  });

  group('두 문서와 화면', () {
    test('약관이 개정되면 버전과 시행일이 함께 오른다 — 사전 공지가 자기 조문이다', () {
      // 제3조2 가 "변경 시 사전 공지합니다" 라고 적어 뒀습니다. 게시일과 시행일을
      // 나눠 적지 않으면 첫 개정부터 자기 조문을 어깁니다.
      for (final file in [_terms, _privacy]) {
        final head = _read(file).split('\n')[1];
        expect(
          head,
          contains('게시일'),
          reason: '${file.path} 의 머리줄에 게시일이 없습니다. 시행일 하나만 적으면 '
              '"언제 알렸는가" 를 말할 수 없습니다.',
        );
        expect(head, contains('시행일'));
      }
    });

    test('탈퇴 화면이 커뮤니티 잔존을 말한다 — 약관과 다른 말을 하면 안 된다', () {
      final screen = _read(
          File('lib/v2/screens/settings/account_delete_screen.dart'));

      expect(
        screen,
        contains('커뮤니티에 쓴 글·댓글·반응은 커뮤니티에 남고'),
        reason: '이 화면은 #82 때 "지키지 못할 약속을 화면에 띄우는 것이 정책 위반보다 '
            '더 위험하다" 고 스스로 적어 뒀습니다. 커뮤니티가 붙으면서 같은 자리가 '
            '두 번째로 깨졌습니다.',
      );
      expect(
        screen,
        isNot(contains('내가 남긴 기록이 삭제되며')),
        reason: '옛 문구입니다. 커뮤니티 글은 안 지워집니다.',
      );
    });
  });
}
