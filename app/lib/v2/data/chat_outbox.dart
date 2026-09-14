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
import 'dart:typed_data';

import '../domain/chat_reply.dart';
import '../domain/post_media.dart';

/// 보낸 메시지 하나의 상태.
enum PendingState {
  /// 서버 응답을 기다리는 중. 화면에서는 회색이다.
  sending,

  /// 실패했다. **지우지 않는다** — 재전송 버튼이 붙는다.
  failed,
}

/// 보낼 사진(#452) — 다시 인코딩한 JPEG 바이트와 크기. 말풍선이 자리를 잡는 데 크기를 쓴다.
class PendingPhoto {
  final Uint8List bytes;
  final int width;
  final int height;

  const PendingPhoto({required this.bytes, required this.width, required this.height});

  /// 말풍선의 가로세로비 — 서버 사진([PostMedia.aspectRatio])과 같은 4:5 ~ 1.91:1 규칙.
  double get aspectRatio => width <= 0 || height <= 0
      ? 1
      : (width / height).clamp(PostMedia.minFeedAspectRatio, PostMedia.maxFeedAspectRatio).toDouble();
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

  /// 사진 메시지(#452)의 보낼 사진. 글자 메시지는 null.
  final PendingPhoto? photo;

  /// 올리기가 끝나 서버가 준 사진 id. 있으면 다시 보낼 때 올리기를 건너뛴다 — 같은 사진이
  /// 버킷에 두 번 남지 않는다.
  final int? mediaId;

  /// 답장(#452)이면 원문의 미리보기 — 확정되기 전 말풍선이 이것으로 인용 블록을 그린다. 서버에는
  /// `replyToId` 만 보내고, 확정된 메시지의 `replyTo` 는 서버가 만든 것으로 바뀐다(같은 규칙이라 글자는 같다).
  final ChatReplyTo? replyTo;

  const PendingMessage({
    required this.clientMsgId,
    required this.body,
    required this.state,
    required this.createdAt,
    this.photo,
    this.mediaId,
    this.replyTo,
  });

  bool get isPhoto => photo != null;

  /// 새로 보내는 메시지. **여기서만 키를 만든다.**
  factory PendingMessage.create(String body, {DateTime? now, ChatReplyTo? replyTo}) {
    return PendingMessage(
      clientMsgId: newClientMsgId(),
      body: body,
      state: PendingState.sending,
      createdAt: now ?? DateTime.now(),
      replyTo: replyTo,
    );
  }

  /// 사진 메시지 — 본문은 비어 있다(캡션은 아직 없다). 키는 여기서 만든다.
  factory PendingMessage.photo(PendingPhoto photo, {DateTime? now, ChatReplyTo? replyTo}) {
    return PendingMessage(
      clientMsgId: newClientMsgId(),
      body: '',
      state: PendingState.sending,
      createdAt: now ?? DateTime.now(),
      photo: photo,
      replyTo: replyTo,
    );
  }

  /// 사진을 올렸다 — 서버가 준 id 를 적어 둔다. 상태는 그대로(보내는 중).
  PendingMessage uploaded(int mediaId) => PendingMessage(
        clientMsgId: clientMsgId,
        body: body,
        state: state,
        createdAt: createdAt,
        photo: photo,
        mediaId: mediaId,
        replyTo: replyTo,
      );

  /// 전송이 실패했다. 키와 본문은 그대로다 — 사진과 올린 id 도.
  PendingMessage failed() => PendingMessage(
        clientMsgId: clientMsgId,
        body: body,
        state: PendingState.failed,
        createdAt: createdAt,
        photo: photo,
        mediaId: mediaId,
        replyTo: replyTo,
      );

  /// 다시 보낸다. **키를 새로 만들지 않는다** — 만들면 서버에 같은 말이 두 번 남는다.
  PendingMessage retrying() => PendingMessage(
        clientMsgId: clientMsgId,
        body: body,
        state: PendingState.sending,
        createdAt: createdAt,
        photo: photo,
        mediaId: mediaId,
        replyTo: replyTo,
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
