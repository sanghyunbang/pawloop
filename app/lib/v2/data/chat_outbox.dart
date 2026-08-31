/// 아직 서버가 확정하지 않은 메시지들. **낙관적 전송의 상태를 담는다.** (이슈 #81)
///
/// ## 왜 이런 것이 필요한가
///
/// 보낸 즉시 화면에 넣지 않으면 사용자는 3초(폴링 한 주기)를 기다린다. 그래서 회색으로 먼저
/// 넣고 응답이 오면 확정한다.
///
/// 문제는 **실패했을 때**다. 지우면 사용자가 쓴 글이 사라지고, 그냥 두면 보낸 것처럼 보인다.
/// 둘 다 틀렸다 — 남겨 두고 <b>재전송 버튼</b>을 단다.
///
/// ## 멱등키를 다시 만들지 않는다
///
/// 재전송할 때 키를 새로 만들면 **멱등이 무의미해진다.** 첫 전송이 서버에 닿았는데 응답만
/// 못 받은 경우(타임아웃·비행기 모드 전환), 새 키로 재전송하면 서버에 같은 말이 두 번 남는다.
/// 서버는 `(room_id, sender_user_id, client_msg_id)` UNIQUE 로 두 번째를 거르는데, 키가
/// 다르면 그 그물을 그냥 통과한다.
///
/// 그래서 [PendingMessage] 는 키를 **생성 시점에 한 번** 만들고 [retrying] 은 그것을 그대로
/// 들고 간다.
///
/// ## 새 의존성을 넣지 않는다
///
/// `uuid` 패키지를 쓰지 않는다. `Random.secure()` 16바이트를 base64url 로 적으면 순수 Dart 로
/// 되고, 서버는 이 값을 **불투명 문자열**로만 쓴다(형식을 검사하지 않는다). "신규 의존성 0" 이
/// UUID 형식보다 값지다.
library;

import 'dart:convert';
import 'dart:math';

/// 보낸 메시지 하나의 상태.
enum PendingState {
  /// 서버 응답을 기다리는 중. 화면에서는 회색이다.
  sending,

  /// 실패했다. **지우지 않는다** — 재전송 버튼이 붙는다.
  failed,
}

/// 서버가 아직 확정하지 않은 메시지 하나.
class PendingMessage {
  /// 멱등키. **한 번 만들고 재전송에도 그대로 쓴다.**
  final String clientMsgId;

  final String body;
  final PendingState state;

  /// 화면에서 순서를 잡는 데만 쓴다. 서버가 준 `roomSeq` 와 무관하다 —
  /// **앱은 순서를 추측하지 않는다.** 확정되면 이 객체는 목록에서 빠지고
  /// 서버가 준 메시지가 그 자리에 들어간다.
  final DateTime createdAt;

  const PendingMessage({
    required this.clientMsgId,
    required this.body,
    required this.state,
    required this.createdAt,
  });

  /// 새로 보내는 메시지. **여기서만 키를 만든다.**
  factory PendingMessage.create(String body, {DateTime? now}) {
    return PendingMessage(
      clientMsgId: newClientMsgId(),
      body: body,
      state: PendingState.sending,
      createdAt: now ?? DateTime.now(),
    );
  }

  /// 전송이 실패했다. 키와 본문은 그대로다.
  PendingMessage failed() => PendingMessage(
        clientMsgId: clientMsgId,
        body: body,
        state: PendingState.failed,
        createdAt: createdAt,
      );

  /// 다시 보낸다. **키를 새로 만들지 않는다** — 만들면 서버에 같은 말이 두 번 남는다.
  PendingMessage retrying() => PendingMessage(
        clientMsgId: clientMsgId,
        body: body,
        state: PendingState.sending,
        createdAt: createdAt,
      );

  @override
  String toString() => 'PendingMessage($clientMsgId, ${state.name})';
}

/// 멱등키 하나. `Random.secure()` 16바이트를 base64url 로 적는다.
///
/// 패딩(`=`)을 떼는 이유는 서버 컬럼이 64자이고 이 값이 URL·헤더에 실릴 수도 있어서다.
/// 22자가 되어 여유가 넉넉하다.
String newClientMsgId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}
