/// 채팅 답장(인용) — 이슈 #452.
///
/// 카카오톡의 답장처럼 **"어느 말에 대한 답" 하나**다 — 스레드가 아니다. 서버는 원문의 id 만 저장하고
/// 미리보기(보낸 사람 · 첫 줄)는 응답 때마다 원문을 읽어 만든다(`ChatReplyTo` 스키마). 그래서 원문이
/// 지워지면 다음 조회부터 "삭제된 메시지" 이고, 보낸 사람의 이름은 지금 이름이다.
///
/// 여기 있는 것은 그 미리보기의 모양([ChatReplyTo])과, 서버가 확정하기 **전** 화면이 스스로 그릴 때
/// 쓰는 같은 규칙([replyPreviewOf]) — 입력창 위의 인용 띠와 보내는 중인 말풍선이 그것이다. 규칙이
/// 서버(`ChatMessageResponse.ReplyTo`)와 같아야 확정되는 순간 글자가 바뀌지 않는다.
library;

/// 답장의 원문 미리보기. 서버의 `ChatReplyTo` 와 같은 네 값.
class ChatReplyTo {
  /// 원문 메시지의 id.
  final int id;

  /// 원문을 보낸 사람의 **지금** 이름.
  final String senderName;

  /// 첫 [replyPreviewChars]자. 지워졌으면 [deletedPreview], 캡션 없는 사진이면 [photoPreview].
  final String preview;

  /// 원문이 지워졌는가.
  final bool deleted;

  const ChatReplyTo({
    required this.id,
    required this.senderName,
    required this.preview,
    this.deleted = false,
  });

  /// 서버 JSON. 모양이 아니면 null — 답장이 아닌 메시지는 `replyTo: null` 로 온다.
  static ChatReplyTo? tryParse(dynamic json) {
    if (json is! Map) {
      return null;
    }
    final id = json['id'];
    if (id is! int) {
      return null;
    }
    return ChatReplyTo(
      id: id,
      senderName: '${json['senderName'] ?? ''}',
      preview: '${json['preview'] ?? ''}',
      deleted: json['deleted'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ChatReplyTo &&
      other.id == id &&
      other.senderName == senderName &&
      other.preview == preview &&
      other.deleted == deleted;

  @override
  int get hashCode => Object.hash(id, senderName, preview, deleted);

  @override
  String toString() => 'ChatReplyTo($id, $senderName, $preview${deleted ? ', deleted' : ''})';
}

/// 미리보기 길이 — 서버의 `ReplyTo.PREVIEW_CHARS` 와 같다.
const int replyPreviewChars = 80;

/// 지워진 원문의 미리보기 — 서버와 같은 글자.
const String deletedPreview = '삭제된 메시지';

/// 캡션 없는 사진 원문의 미리보기 — 서버와 같은 글자.
const String photoPreview = '사진';

/// 원문 [body] 의 미리보기 — 서버(`ChatMessageResponse.ReplyTo.of`)와 **같은 규칙**.
///
/// 지워졌으면 [deletedPreview]. 공백·줄바꿈은 한 칸으로 접고 앞뒤를 자른다. 그러고도 비었는데
/// 사진([isImage])이면 [photoPreview]. [replyPreviewChars]자를 넘으면 거기서 자르고 `…` — 글자
/// 단위(rune)로 세어 이모지를 반으로 자르지 않는다.
String replyPreviewOf(String body, {required bool isImage, required bool deleted}) {
  if (deleted) {
    return deletedPreview;
  }
  var text = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty && isImage) {
    text = photoPreview;
  }
  final runes = text.runes.toList();
  if (runes.length > replyPreviewChars) {
    text = '${String.fromCharCodes(runes.take(replyPreviewChars))}…';
  }
  return text;
}
