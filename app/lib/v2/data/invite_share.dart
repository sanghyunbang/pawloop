// 가족 초대 코드를 OS 공유 시트로 보낸다 (#329).
//
// 전에는 초대 시트가 "코드 복사" 에서 끝났다 — 복사 → 앱 전환 → 붙여넣기 세 단계였다.
// 공유 시트를 띄우는 함수는 갈아 끼울 수 있다: 위젯 테스트는 플러그인이 없는 자리에서
// **어떤 문장이 나가는지**만 본다.
import 'package:share_plus/share_plus.dart';

/// 초대 문장과 공유 시트.
class InviteShare {
  InviteShare._();

  /// 공유 시트를 띄우는 함수. 테스트가 갈아 끼운다.
  static Future<void> Function(String text, {String? subject}) sender = _sharePlus;

  static Future<void> _sharePlus(String text, {String? subject}) async {
    await SharePlus.instance.share(ShareParams(text: text, subject: subject));
  }

  /// 받는 쪽이 앱 없이도 뜻을 알고, 앱이 있으면 어디에 넣을지 아는 문장.
  static String message(String code) =>
      '포루프 가족에 초대해요 · 초대 코드 $code · 앱의 "초대 코드로 참여하기" 에 넣어 주세요';

  static Future<void> send(String code) => sender(message(code), subject: '포루프 가족 초대');

  static void resetForTest() => sender = _sharePlus;
}

/// 초대 시트 아래 줄 — **사실**만 쓴다. 만료·횟수는 서버가 발급 응답에 준 값이다
/// (`chat_room_invite` 의 `expires_at`·`max_uses`). 전에는 "누를 때마다 새 코드가 하나 더
/// 생겨요" 라고 적었는데 그건 사용자가 알아야 할 사실이 아니라 불안이었다.
///
/// [expiresAt] 은 보여 줄 시간대로 이미 바뀐 값이어야 한다(`toLocal()`).
String inviteFactLine({required DateTime? expiresAt, required int? maxUses}) {
  final until = expiresAt == null ? '만료되지 않아요' : '${expiresAt.month}월 ${expiresAt.day}일까지 써요';
  final uses = switch (maxUses) {
    null => '가족 여럿이 같은 코드로 들어올 수 있어요',
    1 => '한 명만 쓸 수 있어요',
    final n => '$n명까지 쓸 수 있어요',
  };
  return '$until · $uses';
}
