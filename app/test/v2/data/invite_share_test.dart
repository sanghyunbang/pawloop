// 초대 공유 문장과 사실 문구 (#329).
import 'package:flutter_test/flutter_test.dart';

import 'package:heat_trip_flutter/v2/data/invite_share.dart';

void main() {
  tearDown(InviteShare.resetForTest);

  test('공유 문장에 코드와 넣을 곳이 들어 있다', () {
    final text = InviteShare.message('ULKFF-NQCMJ');
    expect(text, contains('ULKFF-NQCMJ'));
    expect(text, contains('초대 코드로 참여하기'), reason: '받는 쪽이 앱에서 어디에 넣을지 알아야 한다');
    expect(text, startsWith('포루프 가족에 초대해요'));
  });

  test('send 는 갈아 끼운 함수로 그 문장을 보낸다', () async {
    String? sent;
    String? subjectSeen;
    InviteShare.sender = (text, {String? subject}) async {
      sent = text;
      subjectSeen = subject;
    };
    await InviteShare.send('PAW-1234');
    expect(sent, InviteShare.message('PAW-1234'));
    expect(subjectSeen, '포루프 가족 초대');
  });

  test('inviteFactLine — 만료일과 횟수는 서버 값 그대로, 없으면 없다고 말한다', () {
    expect(
      inviteFactLine(expiresAt: DateTime(2026, 9, 14, 3, 0), maxUses: null),
      '9월 14일까지 써요 · 가족 여럿이 같은 코드로 들어올 수 있어요',
    );
    expect(
      inviteFactLine(expiresAt: null, maxUses: 1),
      '만료되지 않아요 · 한 명만 쓸 수 있어요',
    );
    expect(
      inviteFactLine(expiresAt: DateTime(2026, 12, 1), maxUses: 3),
      '12월 1일까지 써요 · 3명까지 쓸 수 있어요',
    );
  });
}
