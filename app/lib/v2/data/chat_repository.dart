/// 채팅 서버 연동. (이슈 #81 · 계약은 ADR-0011 · 엔드포인트는 #79)
///
/// ## 규약 (family_repository 와 같다)
///
///  1. HTTP 는 `AuthedClient` 하나로만 나간다. `Authorization` 헤더를 여기서 만들지 않는다.
///  2. 화면은 `http` 를 모른다 — 실패는 [ChatFailure] 로만 나간다.
///  3. **토큰 저장소를 건드리지 않는다.** 401 은 `AuthedClient` 가 갱신까지 시도한 뒤의 결과다.
///
/// ## 델타 폴링
///
/// 마지막으로 받은 `roomSeq` 를 `afterSeq` 로 보낸다. **`id` 를 보내지 않는다** — `id` 는 전역
/// 시퀀스라 방 안에서 연속이 아니고, 그것을 커서로 쓰면 다른 방의 메시지가 끼어든 만큼 건너뛴다
/// (ADR-0011).
///
/// ## ETag
///
/// 서버가 준 `ETag` 를 다음 요청의 `If-None-Match` 로 되돌려 보낸다. 새 메시지가 없으면 서버가
/// **304** 를 주고 본문이 아예 안 온다 — 빈 배열을 직렬화해 보내는 것보다 싸다.
///
/// **304 를 오류로 다루지 않는다.** 빈 응답과 같은 뜻이고, 폴링에서는 그게 정상이다.
library;

import 'dart:convert';

import 'package:heat_trip_flutter/core/config/env.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:http/http.dart' as http;

import '../domain/chat_reply.dart';
import '../domain/post_media.dart';

/// 채팅 요청이 실패한 이유.
enum ChatFailureKind {
  /// 세션이 끝났다(401). `AuthedClient` 가 갱신까지 시도한 뒤의 결과다.
  unauthorized,

  /// 이 방의 멤버가 아니다(403).
  forbidden,

  /// 방이나 초대코드가 없다(404).
  notFound,

  /// 초대코드가 만료됐다(410 · `INVITE_EXPIRED`).
  inviteExpired,

  /// 초대코드가 회수됐다(410 · `INVITE_REVOKED`).
  inviteRevoked,

  /// 초대코드의 사용 횟수를 다 썼다(409 · `INVITE_USES_EXHAUSTED`).
  inviteExhausted,

  /// 방 정원이 찼다(409 · `ROOM_MEMBER_LIMIT`).
  roomFull,

  /// 서버가 입력을 거절했다(400). **다시 시도해도 같은 결과다.**
  invalid,

  /// 한도를 넘겼다(429). 채팅 버킷은 사용자 단위로 센다 (#80).
  rateLimited,

  /// 신고할 메시지를 안 골랐다(400 · `REPORT_EMPTY`).
  reportEmpty,

  /// 세 개를 넘겨 골랐다(400 · `REPORT_MESSAGE_LIMIT`).
  reportTooMany,

  /// 고른 메시지의 발신자가 여럿이다(400 · `REPORT_MIXED_SENDERS`).
  reportMixedSenders,

  /// 자기 메시지를 골랐다(400 · `REPORT_SELF`).
  reportSelf,

  /// 그 밖의 실패. 연결·타임아웃·5xx.
  network,
}

/// 신고 사유. **서버가 닫힌 목록으로 받는다** — 계약(`openapi.yaml`)이 어휘의 출처다.
///
/// 여기에 없는 값을 보내면 서버가 400 `REPORT_REASON_UNKNOWN` 을 낸다. 서버가 모르는 값을
/// `other` 로 눕히지 않기 때문인데, 그래야 운영자가 세는 숫자가 소리 없이 틀어지지 않는다.
enum ChatReportReason {
  spam('spam', '광고 · 도배'),
  abuse('abuse', '욕설 · 괴롭힘'),
  sexual('sexual', '성적인 내용'),
  fraud('fraud', '사기 · 금전 요구'),
  other('other', '기타');

  const ChatReportReason(this.wire, this.label);

  /// 서버로 보내는 값. **화면 문구와 분리한다** — 문구를 다듬는다고 저장된 뜻이 바뀌면 안 된다.
  final String wire;

  /// 사용자가 고를 때 읽는 말.
  final String label;
}

/// 화면에 그대로 띄울 수 있는 실패 하나.
class ChatFailure implements Exception {
  final ChatFailureKind kind;
  final String message;

  const ChatFailure(this.kind, this.message);

  /// 사용자가 읽을 문구. **초대 실패 네 가지를 각각 다르게 말한다** — 완료 조건 4다.
  /// 하나로 뭉치면 사용자는 "코드를 다시 받아야 하는지" 와 "방장에게 자리를 비워 달라고
  /// 해야 하는지" 를 구분하지 못한다.
  static String messageFor(ChatFailureKind kind) => switch (kind) {
        ChatFailureKind.unauthorized => '로그인이 필요해요',
        ChatFailureKind.forbidden => '이 방에 들어올 수 없어요',
        ChatFailureKind.notFound => '없는 방이거나 잘못된 코드예요',
        ChatFailureKind.inviteExpired => '만료된 초대코드예요. 새 코드를 받아 주세요',
        ChatFailureKind.inviteRevoked => '회수된 초대코드예요. 방장에게 새 코드를 받아 주세요',
        ChatFailureKind.inviteExhausted => '이 코드는 사용 횟수를 다 썼어요. 새 코드를 받아 주세요',
        ChatFailureKind.roomFull => '방 정원이 가득 찼어요',
        ChatFailureKind.invalid => '보낼 수 없는 내용이에요',
        ChatFailureKind.reportEmpty => '신고할 메시지를 하나 이상 골라 주세요',
        ChatFailureKind.reportTooMany => '메시지는 세 개까지 고를 수 있어요',
        ChatFailureKind.reportMixedSenders => '한 번에 한 사람만 신고할 수 있어요',
        ChatFailureKind.reportSelf => '내가 쓴 메시지는 신고할 수 없어요',
        ChatFailureKind.rateLimited => '너무 잦아요. 잠시 후 다시 시도해 주세요',
        ChatFailureKind.network => '연결이 불안정해요',
      };

  @override
  String toString() => 'ChatFailure(${kind.name}: $message)';
}

/// 방 하나. 서버의 `ChatRoomResponse` 를 그대로 옮긴다.
class ChatRoomSummary {
  final int id;
  final String title;

  /// 방 종류를 화면에 그리는 값. **가족방과 산책 크루가 같은 코드로 돈다** (ADR-0011).
  final String tag;

  final int lastSeq;
  final int lastReadSeq;
  final int unread;
  final int memberCount;
  final String? lastMessageBody;
  final String? lastMessageSender;

  /// 마지막 말이 사진 메시지(#452)다 — 본문(캡션)이 비어 있으면 목록은 "사진" 이라고 말한다.
  final bool lastMessageIsImage;

  /// 마지막 말의 시각(#452 목록 시각) — 계약의 `lastMessage.createdAt`. 말이 없으면 null.
  final DateTime? lastMessageAt;

  /// 이 방에서의 내 역할. `OWNER` 면 방장이라 강퇴할 수 있다.
  ///
  /// 서버가 늘 주지만 모르는 값이 올 수 있어 문자열 그대로 든다 — [isOwner] 로만 읽는다.
  final String myRole;

  /// 미리보기의 발신자를 내가 가렸다. 방 안에서 접어 놓고 목록에서 그대로 보여 주면 샌다.
  final bool lastMessageHidden;

  /// 음소거한 방 — 목록의 개수 뱃지는 그대로고, 탭 바의 점(#452)만 안 켠다.
  final bool muted;

  const ChatRoomSummary({
    required this.id,
    required this.title,
    required this.tag,
    required this.lastSeq,
    required this.lastReadSeq,
    required this.unread,
    required this.memberCount,
    this.lastMessageBody,
    this.lastMessageSender,
    this.lastMessageHidden = false,
    this.lastMessageIsImage = false,
    this.lastMessageAt,
    this.myRole = '',
    this.muted = false,
  });

  /// 내가 이 방의 방장인가. 강퇴 버튼을 띄울지의 유일한 근거다.
  bool get isOwner => myRole == 'OWNER';

  static ChatRoomSummary? tryParse(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! int) {
      return null;
    }
    final last = json['lastMessage'];
    return ChatRoomSummary(
      id: id,
      title: '${json['title'] ?? ''}',
      tag: '${json['tag'] ?? ''}',
      lastSeq: _asInt(json['lastSeq']),
      lastReadSeq: _asInt(json['lastReadSeq']),
      unread: _asInt(json['unread']),
      memberCount: _asInt(json['memberCount']),
      lastMessageBody: last is Map ? last['body']?.toString() : null,
      lastMessageSender: last is Map ? last['senderName']?.toString() : null,
      lastMessageHidden: last is Map && last['hiddenByBlock'] == true,
      lastMessageIsImage: last is Map && last['contentType'] == 'image',
      lastMessageAt: last is Map ? DateTime.tryParse('${last['createdAt'] ?? ''}') : null,
      myRole: '${json['myRole'] ?? ''}',
      muted: json['muted'] == true,
    );
  }
}

/// 메시지 하나.
/// 말풍선 아래 반응 한 종류의 집계 — #452. 계약의 `ChatReaction`.
///
/// [count] 는 **"몇 번" 이지 "몇 명" 이 아니다** — 한 사람이 한 말에 여러 종류를 누를 수 있고,
/// 탈퇴한 사람의 반응도 세어진다. [mine] 은 [ChatMessageItem.hiddenByBlock] 과 같은 종류의 값이라
/// 읽는 사람마다 다르다 — 캐시하면 남의 화면에 내 상태가 보인다.
class ChatReaction {
  final String kind;
  final int count;
  final bool mine;

  const ChatReaction({required this.kind, required this.count, required this.mine});

  static ChatReaction? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) {
      return null;
    }
    final kind = json['kind'];
    if (kind is! String || kind.isEmpty) {
      return null;
    }
    return ChatReaction(kind: kind, count: _asInt(json['count']), mine: json['mine'] == true);
  }

  /// 응답의 배열을 **순서 그대로**. 순서는 서버가 정한다 — 앱이 다시 정렬하면 같은 말이
  /// 기기마다 다르게 보인다.
  static List<ChatReaction> parseAll(Object? json) {
    if (json is! List) {
      return const [];
    }
    return json.map(ChatReaction.tryParse).whereType<ChatReaction>().toList(growable: false);
  }
}

class ChatMessageItem {
  final int id;

  /// 방 안에서의 순서. **앱은 순서를 추측하지 않는다** — 서버가 배정한 이 값이 진실이다.
  final int roomSeq;

  final int senderUserId;
  final String senderName;
  final String body;
  final DateTime? createdAt;
  final bool deleted;

  /// 내가 이 사람을 가렸다. **읽는 사람마다 다른 값이다** — 같은 메시지가 남에게는 false 다.
  ///
  /// 목록에서 빠지지 않고 [body] 도 그대로 온다. 빼면 그 [roomSeq] 가 도달하지 않아
  /// 미읽음 뱃지가 영원히 남고, 본문을 지워 내리면 "보기" 를 누를 때 요청이 한 번 더 필요하다.
  final bool hiddenByBlock;

  /// 메시지 종류 — `text` 아니면 `image`(#452). 서버는 자유 문자열이라 모르는 값은 글자로 그린다.
  final String contentType;

  /// 사진 메시지의 사진(#452) — 글의 [PostMedia] 와 같은 모양. 글자 메시지 · 지워진 사진 메시지는 null.
  final PostMedia? media;

  /// 답장(#452)이면 원문의 미리보기(보낸 사람의 지금 이름 · 첫 줄). 답장이 아니면 null.
  /// 서버가 응답 때마다 원문을 읽어 만든다 — 원문이 지워지면 다음 조회부터 `deleted` 다.
  final ChatReplyTo? replyTo;

  /// 이 말에 붙은 반응(#452) — 0 인 종류는 안 온다. **빈 배열이지 null 이 아니다.**
  /// 옛 서버(키 없음)도 빈 배열이라 앱은 같은 코드로 그린다.
  final List<ChatReaction> reactions;

  bool get isImage => contentType == 'image';

  const ChatMessageItem({
    required this.id,
    required this.roomSeq,
    required this.senderUserId,
    required this.senderName,
    required this.body,
    required this.createdAt,
    required this.deleted,
    this.hiddenByBlock = false,
    this.contentType = 'text',
    this.media,
    this.replyTo,
    this.reactions = const [],
  });

  /// 반응만 바꾼 사본 — 누른 직후 그 말풍선 하나만 다시 그린다. 나머지는 서버가 준 그대로다.
  ChatMessageItem withReactions(List<ChatReaction> updated) => ChatMessageItem(
        id: id,
        roomSeq: roomSeq,
        senderUserId: senderUserId,
        senderName: senderName,
        body: body,
        createdAt: createdAt,
        deleted: deleted,
        hiddenByBlock: hiddenByBlock,
        contentType: contentType,
        media: media,
        replyTo: replyTo,
        reactions: updated,
      );

  static ChatMessageItem? tryParse(Map<String, dynamic> json) {
    final id = json['id'];
    final seq = json['roomSeq'];
    if (id is! int || seq is! int) {
      return null;
    }
    return ChatMessageItem(
      id: id,
      roomSeq: seq,
      senderUserId: _asInt(json['senderUserId']),
      senderName: '${json['senderName'] ?? ''}',
      body: '${json['body'] ?? ''}',
      createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}'),
      deleted: json['deletedAt'] != null,
      hiddenByBlock: json['hiddenByBlock'] == true,
      contentType: '${json['contentType'] ?? 'text'}',
      media: PostMedia.tryParse(json['media']),
      replyTo: ChatReplyTo.tryParse(json['replyTo']),
      reactions: ChatReaction.parseAll(json['reactions']),
    );
  }
}

/// 메시지 한 장과 그때의 `ETag`.
class ChatMessagePage {
  final List<ChatMessageItem> messages;
  final int lastSeq;
  final bool hasMore;

  /// **이미 받은 말의 새 모양**(ADR-0023, #500). 새 말([messages])과 섞지 않는다 — 섞으면 지워진 말이
  /// 대화 맨 아래에 새 말처럼 올라온다. 화면은 같은 `id` 의 자리에 덮어쓴다.
  final List<ChatMessageItem> changed;

  /// 방의 현재 **변경 번호**. 다음 폴링에 `afterChangeSeq` 로 그대로 되돌려 보낸다.
  final int lastChangeSeq;

  /// 다음 요청에 `If-None-Match` 로 실어 보낼 값. 서버가 안 줬으면 null.
  final String? etag;

  /// 서버가 304 로 답했다. **오류가 아니다** — 빈 응답과 같은 뜻이다.
  final bool notModified;

  const ChatMessagePage({
    required this.messages,
    required this.lastSeq,
    required this.hasMore,
    this.changed = const [],
    this.lastChangeSeq = 0,
    this.etag,
    this.notModified = false,
  });

  /// 이번 폴링이 빈손이었나. 폴링 간격을 늘릴지의 입력이다 ([ChatPollingPolicy]).
  ///
  /// **바뀐 말도 활동이다** — 남이 방금 말을 지웠으면 그 방은 조용한 방이 아니다.
  bool get isEmpty => messages.isEmpty && changed.isEmpty;
}

int _asInt(Object? value) => value is int ? value : int.tryParse('$value') ?? 0;

/// 채팅 API.
class ChatRepository {
  /// `AuthedClient.refreshTimeout` 이 갱신 왕복에 대해 같은 것을 한다.
  static const Duration timeout = Duration(seconds: 15);

  final String baseUrl;
  final AuthedClient _authed;

  ChatRepository({String? baseUrl, AuthedClient? client})
      : baseUrl = _stripTrailingSlash(baseUrl ?? Env.apiBase),
        _authed = client ?? AuthedClient.instance;

  static String _stripTrailingSlash(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  /// 내가 속한 방들. 미읽음 뱃지는 서버가 계산한 `unread` 를 그대로 쓴다 —
  /// 앱이 빼기를 다시 하면 두 곳이 갈린다.
  Future<List<ChatRoomSummary>> rooms() async {
    final json = await _send(() => _authed.getJson(Uri.parse('$baseUrl/api/chat/rooms')));
    return (json as List)
        .whereType<Map<String, dynamic>>()
        .map(ChatRoomSummary.tryParse)
        .whereType<ChatRoomSummary>()
        .toList();
  }

  /// 메시지 한 장.
  ///
  /// [afterSeq] 를 주면 그다음부터(폴링), [beforeSeq] 를 주면 그 앞부터(과거 페이지) 읽는다.
  /// [etag] 를 주면 `If-None-Match` 로 나가고, 새 것이 없으면 서버가 304 를 준다.
  ///
  /// [afterChangeSeq] 는 **이미 받은 말의 변화**를 어디까지 봤는가다(ADR-0023, #500). 주면 그 뒤에 바뀐 말이
  /// [ChatMessagePage.changed] 로 온다 — 지금은 남이 지운 말이고 앞으로 반응이 붙는다.
  Future<ChatMessagePage> messages(
    int roomId, {
    int? afterSeq,
    int? beforeSeq,
    int? limit,
    int? afterChangeSeq,
    String? etag,
  }) async {
    final query = <String, String>{
      if (afterSeq != null) 'afterSeq': '$afterSeq',
      if (beforeSeq != null) 'beforeSeq': '$beforeSeq',
      if (limit != null) 'limit': '$limit',
      if (afterChangeSeq != null) 'afterChangeSeq': '$afterChangeSeq',
    };
    final uri = Uri.parse('$baseUrl/api/chat/rooms/$roomId/messages')
        .replace(queryParameters: query.isEmpty ? null : query);

    final res = await _request(
      () => _authed.getJson(uri, headers: etag == null ? null : {'If-None-Match': etag}),
    );

    // 304 는 오류가 아니다. 폴링에서는 이게 정상이고, 본문이 아예 안 온다.
    if (res.statusCode == 304) {
      return ChatMessagePage(
        messages: const [],
        lastSeq: afterSeq ?? 0,
        hasMore: false,
        // 304 는 "그대로다" 라 커서도 그대로다 — 0 으로 되돌리면 다음 폴링이 옛 변화를 다시 받는다.
        lastChangeSeq: afterChangeSeq ?? 0,
        etag: etag,
        notModified: true,
      );
    }

    final json = _decodeOrThrow(res) as Map<String, dynamic>;
    return ChatMessagePage(
      // 서버가 주는 키는 items 다 (`ChatMessagePageResponse` · 계약의 `ChatMessagePage`).
      // 여기가 한동안 messages 였다 — 서버가 그 키를 주지 않으니 목록이 **언제나 비었다**.
      // 테스트도 messages 로 흉내 내고 있어서 초록불이었다. 그래서 계약의 키 이름을
      // 테스트가 직접 단언한다(chat_repository_test.dart).
      messages: (json['items'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ChatMessageItem.tryParse)
          .whereType<ChatMessageItem>()
          .toList(),
      lastSeq: _asInt(json['lastSeq']),
      hasMore: json['hasMore'] == true,
      // 바뀐 말(ADR-0023) — 옛 서버는 이 키가 없고, 그때는 빈 목록이라 예전처럼 움직인다.
      changed: (json['changed'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ChatMessageItem.tryParse)
          .whereType<ChatMessageItem>()
          .toList(),
      lastChangeSeq: _asInt(json['lastChangeSeq']),
      etag: res.headers['etag'],
    );
  }

  /// 메시지 하나를 보낸다.
  ///
  /// [clientMsgId] 는 멱등키다. **재전송에는 같은 키를 다시 쓴다** — 새로 만들면 서버의
  /// `(room_id, sender_user_id, client_msg_id)` UNIQUE 그물을 통과해 같은 말이 두 번 남는다
  /// ([PendingMessage] 참조).
  ///
  /// [mediaId] 가 있으면 사진 메시지(#452)다 — `POST /media` 에 `CHAT_IMAGE` 로 올린 id. 종류는
  /// `image` 이고 [body] 는 캡션이라 비어도 된다. 사진 하나에 메시지 하나.
  ///
  /// [replyToId] 가 있으면 답장(#452)이다 — 같은 방의 원문 메시지 id. 서버가 응답에 원문 미리보기
  /// (`replyTo`)를 실어 준다. 다른 방의 id 는 400 이다.
  Future<ChatMessageItem> send(int roomId, String body, String clientMsgId,
      {int? mediaId, int? replyToId}) async {
    final json = await _send(
      () => _authed.postJson(
        Uri.parse('$baseUrl/api/chat/rooms/$roomId/messages'),
        body: {
          'body': body,
          'clientMsgId': clientMsgId,
          'contentType': mediaId == null ? 'text' : 'image',
          if (mediaId != null) 'mediaId': mediaId,
          if (replyToId != null) 'replyToId': replyToId,
        },
      ),
    );
    final parsed = ChatMessageItem.tryParse(json as Map<String, dynamic>);
    if (parsed == null) {
      throw const ChatFailure(ChatFailureKind.network, '응답을 읽지 못했어요');
    }
    return parsed;
  }

  /// 여기까지 읽었다고 알린다. 서버가 `GREATEST` 로 올리므로 뒤로 가는 값은 무시된다.
  Future<void> markRead(int roomId, int lastReadSeq) async {
    await _send(
      () => _authed.postJson(
        Uri.parse('$baseUrl/api/chat/rooms/$roomId/read'),
        body: {'lastReadSeq': lastReadSeq},
      ),
    );
  }

  /// 초대코드로 방에 들어간다. 실패 네 가지를 각각 다른 [ChatFailureKind] 로 돌려준다.
  Future<int> joinByInviteCode(String code) async {
    final json = await _send(
      () => _authed.postJson(Uri.parse('$baseUrl/api/chat/invites/$code/join')),
    );
    return _asInt((json as Map)['roomId'] ?? json['id']);
  }

  /// 메시지 몇 개를 신고한다. **하나 이상 세 개 이하.**
  ///
  /// 서버가 본문 사본·발신자·발신 시각과 앞뒤 각 5개의 `roomSeq` 범위를 스냅샷으로 남긴다 —
  /// 원본이 지워진 뒤에도 읽을 수 있어야 하기 때문이다.
  ///
  /// **가리기와 방 나가기를 여기서 하지 않는다.** 신고 화면의 체크박스를 켰으면 화면이
  /// [block] 을 따로 부른다. 신고에 자동 차단을 묶으면 가족방에서 되돌릴 수 없는 사고가 된다.
  Future<int> report(
    int roomId,
    List<int> roomSeqs,
    ChatReportReason reason, {
    String? memo,
  }) async {
    final json = await _send(
      () => _authed.postJson(
        Uri.parse('$baseUrl/api/chat/rooms/$roomId/reports'),
        body: {
          'roomSeqs': roomSeqs,
          'reason': reason.wire,
          if (memo != null && memo.trim().isNotEmpty) 'memo': memo.trim(),
        },
      ),
    );
    return _asInt((json as Map?)?['reportId']);
  }

  /// 이 사람을 가린다. **삭제가 아니다** — 내 화면에서만 접힌다.
  ///
  /// 이미 가려 뒀어도 성공이다. 방 단위가 아니라 사람 단위라 모든 방에서 접힌다.
  Future<void> block(int userId) async {
    await _send(
      () => _authed.postJson(
        Uri.parse('$baseUrl/api/blocks'),
        body: {'userId': userId},
      ),
    );
  }

  /// 가리기를 푼다. 가린 적 없어도 성공이다.
  Future<void> unblock(int userId) async {
    await _send(() => _authed.deleteJson(Uri.parse('$baseUrl/api/blocks/$userId')));
  }

  /// 내 메시지를 지운다 — 이슈 #197.
  ///
  /// 소프트 삭제다. 자리는 남고 본문만 비며, 다음 응답부터 `deletedAt` 이 실린다. 이미 지운
  /// 메시지에 다시 불러도 성공(204)이다. 남의 메시지는 403 이라 [ChatFailure] 다.
  Future<void> deleteMessage(int messageId) async {
    await _send(() => _authed.deleteJson(Uri.parse('$baseUrl/api/chat/messages/$messageId')));
  }

  /// 이 말에 반응을 켠다 — #452. 돌아오는 것은 **그 말의 최신 집계**다.
  ///
  /// **멱등이다** — 이미 눌러 뒀어도 200 이고 숫자가 안 는다. 그래서 네트워크가 끊겼을 때 그냥 다시
  /// 부르면 된다(토글 하나였다면 재시도가 내 반응을 조용히 껐을 것이다).
  ///
  /// 누르면 방의 변경 번호가 올라 **같은 말이 다른 사람의 다음 폴링에 `changed` 로** 간다
  /// (ADR-0023) — 그래서 여기서 돌아온 값은 "먼저 보여 주는 것" 이지 유일한 경로가 아니다.
  /// 지워진 말에는 못 켠다(409 — [ChatFailureKind] 의 일반 실패로 온다).
  Future<List<ChatReaction>> react(int messageId, String kind) async {
    final json = await _send(() => _authed.postJson(
        Uri.parse('$baseUrl/api/chat/messages/$messageId/reactions/$kind')));
    return ChatReaction.parseAll((json as Map<String, dynamic>?)?['reactions']);
  }

  /// 반응을 끈다. **멱등이다** — 안 눌렀던 것을 취소해도 200 이고, 지워진 말에도 통한다.
  Future<List<ChatReaction>> unreact(int messageId, String kind) async {
    final json = await _send(() => _authed.deleteJson(
        Uri.parse('$baseUrl/api/chat/messages/$messageId/reactions/$kind')));
    return ChatReaction.parseAll((json as Map<String, dynamic>?)?['reactions']);
  }

  /// 이 사람을 방에서 내보낸다. **방장만.**
  ///
  /// 멤버 행은 남고 재입장이 금지된다 — 유효한 초대코드로도 못 들어온다. 그 사람이 쓴
  /// 메시지는 방에 남는다.
  Future<void> removeMember(int roomId, int userId) async {
    await _send(
      () => _authed.deleteJson(Uri.parse('$baseUrl/api/chat/rooms/$roomId/members/$userId')),
    );
  }

  /// 재입장 금지를 푼다. **방장만.**
  ///
  /// 푸는 것은 금지뿐이다 — 그 사람이 초대코드로 다시 들어와야 방에 돌아온다.
  Future<void> allowRejoin(int roomId, int userId) async {
    await _send(
      () => _authed.deleteJson(Uri.parse('$baseUrl/api/chat/rooms/$roomId/bans/$userId')),
    );
  }

  // ─────────────────────────── 내부 ───────────────────────────

  Future<http.Response> _request(Future<http.Response> Function() send) async {
    try {
      return await send().timeout(timeout);
    } on ChatFailure {
      rethrow;
    } catch (_) {
      // 예외 메시지에 URL·본문 조각이 섞일 수 있어 타입도 문구도 옮기지 않는다.
      throw ChatFailure(
        ChatFailureKind.network,
        ChatFailure.messageFor(ChatFailureKind.network),
      );
    }
  }

  Future<Object?> _send(Future<http.Response> Function() send) async {
    return _decodeOrThrow(await _request(send));
  }

  Object? _decodeOrThrow(http.Response res) {
    if (res.statusCode == 200 || res.statusCode == 201) {
      if (res.bodyBytes.isEmpty) {
        return null;
      }
      try {
        return jsonDecode(utf8.decode(res.bodyBytes));
      } catch (_) {
        throw ChatFailure(
          ChatFailureKind.network,
          ChatFailure.messageFor(ChatFailureKind.network),
        );
      }
    }
    if (res.statusCode == 204) {
      return null;
    }

    final kind = _kindOf(res);
    throw ChatFailure(kind, ChatFailure.messageFor(kind));
  }

  /// 상태 코드와 `error.code` 를 함께 본다.
  ///
  /// **코드를 안 보면 410 두 가지와 409 두 가지가 각각 하나로 뭉친다.** 그러면 사용자는
  /// "코드를 다시 받아야 하는지" 와 "자리가 나기를 기다려야 하는지" 를 구분하지 못한다
  /// (완료 조건 4).
  ChatFailureKind _kindOf(http.Response res) {
    final code = _errorCode(res);
    return switch (code) {
      'INVITE_EXPIRED' => ChatFailureKind.inviteExpired,
      'INVITE_REVOKED' => ChatFailureKind.inviteRevoked,
      'INVITE_USES_EXHAUSTED' => ChatFailureKind.inviteExhausted,
      'ROOM_MEMBER_LIMIT' => ChatFailureKind.roomFull,
      'REPORT_EMPTY' => ChatFailureKind.reportEmpty,
      'REPORT_MESSAGE_LIMIT' => ChatFailureKind.reportTooMany,
      'REPORT_MIXED_SENDERS' => ChatFailureKind.reportMixedSenders,
      'REPORT_SELF' => ChatFailureKind.reportSelf,
      // REPORT_MESSAGE_NOT_FOUND · REPORT_REASON_UNKNOWN 은 따로 안 가른다 —
      // 둘 다 앱이 잘못 보낸 것이라 사용자가 할 수 있는 일이 없다. invalid 로 떨어진다.
      _ => switch (res.statusCode) {
          400 => ChatFailureKind.invalid,
          401 => ChatFailureKind.unauthorized,
          403 => ChatFailureKind.forbidden,
          404 => ChatFailureKind.notFound,
          // 코드를 못 읽었을 때의 보수적인 기본값. 410 은 "그 코드로는 이제 안 된다" 이고
          // 409 는 "지금은 안 된다" 라 사용자가 할 일이 다르다.
          410 => ChatFailureKind.inviteExpired,
          409 => ChatFailureKind.roomFull,
          429 => ChatFailureKind.rateLimited,
          _ => ChatFailureKind.network,
        },
    };
  }

  String? _errorCode(http.Response res) {
    if (res.bodyBytes.isEmpty) {
      return null;
    }
    try {
      final json = jsonDecode(utf8.decode(res.bodyBytes));
      final error = json is Map ? json['error'] : null;
      return error is Map ? error['code']?.toString() : null;
    } catch (_) {
      return null;
    }
  }
}
