// lib/v2/data/community_repository.dart
//
// 커뮤니티의 서버 연동 — 이슈 #171.
//
// ## 무엇이 바뀌었나
//
// 목록은 `kPetPosts` 상수 4건이었고, 반응은 화면 로컬 토글이었고, 댓글은 `_cmts`
// 리스트에만 쌓여 화면을 나가면 사라졌다. `post_detail_screen.dart:15` 가 스스로
// "화면 로컬 더미 댓글 모델. (추후 백엔드 연동)" 이라고 적고 있었다.
//
// ## 규칙 (walk_repository.dart · family_repository.dart 와 같다)
//
//  1. HTTP 는 `AuthedClient` 하나로만 나간다. `Authorization` 헤더를 여기서 만들지
//     않는다 — 만드는 곳은 앱 전체에서 `authed_client.dart` 한 줄이고
//     `auth_header_single_source_test.dart` 가 그것을 잠근다(#11).
//  2. 실패를 **종류로** 나눈다. 화면이 "연결이 없다"와 "서버가 거절했다"를 다르게
//     그려야 한다.
//  3. **토큰 저장소를 건드리지 않는다.** 401 은 `AuthedClient` 가 갱신까지 시도한
//     뒤의 결과다(#12).
//
// ## 이 도메인에만 있는 것 — 읽기 셋은 토큰이 없어도 된다
//
// ADR-0016 결정 3이 목록·상세·댓글을 게스트에게 열었다. `AuthedClient` 는 토큰이
// 없으면 `Authorization` 을 **안 붙이고 그냥 보낸다**(`_authHeaders`). 그래서 여기서
// 로그인 여부를 묻지 않는다 — 물으면 그 판정이 두 곳이 된다.
//
// 로그인했으면 서버가 `reactions.mine` 을 채워 준다. 게스트에게는 `null` 이고
// 그것이 "누를 수 없는 상태" 다. **`null` 과 `[]` 는 다르다** — `[]` 는 로그인했는데
// 아직 아무것도 안 누른 것이다.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:heat_trip_flutter/core/config/env.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';

/// 게시판 — 계약의 `Board`.
///
/// **값은 ASCII 키이고 한글은 화면 문구다.** 2026-09 이전에는 앱의 `kPetBoards` 가
/// 한글 문자열을 그대로 들고 있었는데, ADR-0016 이 그 문자열을 DB 컬럼과 query
/// 파라미터로 쓰는 것을 그만뒀다. 게시판 이름을 다듬는 날 쌓인 행을 전부 고쳐야
/// 하기 때문이다.
///
/// 그래서 [wire] 를 서버로 보내고 [label] 을 그린다. 둘을 한 자리에 묶어 두는 것이
/// 이 enum 의 일이다 — 갈라 두면 어느 화면에서 라벨을 보냈는지 찾아다녀야 한다.
enum CommunityBoard {
  walkReview('walk_review', '산책로 후기'),
  petPlace('pet_place', '동반장소'),
  health('health', '건강·병원'),
  free('free', '자유'),
  brag('brag', '자랑');

  final String wire;
  final String label;

  const CommunityBoard(this.wire, this.label);

  /// 모르는 값이면 `null`. 서버가 게시판을 늘렸는데 앱이 낡았을 때 **던지지 않는다** —
  /// 칩 하나가 안 그려지는 것과 목록 전체가 죽는 것은 다르다.
  static CommunityBoard? tryParse(String? value) {
    for (final board in values) {
      if (board.wire == value) return board;
    }
    return null;
  }
}

/// 반응 — 계약의 `ReactionType`.
///
/// **셋을 동시에 누를 수 있다**(ADR-0016 결정 2). 서로 배타적인 개념이 아니라서다.
enum CommunityReaction {
  help('help', '도움돼요'),
  cute('cute', '귀여워요'),
  empathy('empathy', '공감');

  final String wire;
  final String label;

  const CommunityReaction(this.wire, this.label);

  static CommunityReaction? tryParse(String? value) {
    for (final reaction in values) {
      if (reaction.wire == value) return reaction;
    }
    return null;
  }
}

/// 사람 한 명을 가리키는 것 — 계약의 `PersonRef`.
///
/// **닉네임만으로는 부족하다.** 2026-09 이전 계약의 `Comment.author` 에는 닉네임뿐이라
/// "내 댓글인가" 를 판별할 수 없었고, 그래서 앱이 문자열 `'나'` 를 표식으로 쓰고
/// 있었다 — 닉네임이 '나' 인 사람이 오면 남의 댓글이 내 것으로 보인다(ADR-0017 규약 5).
class PersonRef {
  final int userId;
  final String nickname;

  const PersonRef({required this.userId, required this.nickname});

  /// 탈퇴한 사람. 서버가 `userId: 0` · `nickname: "알 수 없음"` 을 준다.
  bool get isWithdrawn => userId == 0;

  static PersonRef? tryParse(Object? json) {
    if (json is! Map) return null;
    final userId = json['userId'];
    final nickname = json['nickname'];
    if (userId is! num || nickname is! String) return null;
    return PersonRef(userId: userId.toInt(), nickname: nickname);
  }
}

/// 반응 집계 — 계약의 `ReactionSummary`.
class ReactionSummary {
  final int help;
  final int cute;
  final int empathy;

  /// 내가 누른 것들. **`null` 은 비인증이다** — `{}` 는 로그인했는데 안 누른 것이고,
  /// 그 둘을 뭉개면 게스트에게 "안 눌렀음" 하이라이트를 그리게 된다.
  final Set<CommunityReaction>? mine;

  const ReactionSummary({
    required this.help,
    required this.cute,
    required this.empathy,
    this.mine,
  });

  static const ReactionSummary empty =
      ReactionSummary(help: 0, cute: 0, empathy: 0);

  int countOf(CommunityReaction reaction) => switch (reaction) {
        CommunityReaction.help => help,
        CommunityReaction.cute => cute,
        CommunityReaction.empathy => empathy,
      };

  /// 게스트면 `false`. 누를 수 없는 상태를 "안 누른 상태" 로 그리지 않는다.
  bool isMine(CommunityReaction reaction) => mine?.contains(reaction) ?? false;

  static ReactionSummary parse(Object? json) {
    if (json is! Map) return empty;
    final rawMine = json['mine'];
    return ReactionSummary(
      help: _int(json['help']),
      cute: _int(json['cute']),
      empathy: _int(json['empathy']),
      mine: rawMine is List
          ? rawMine
              .map((value) => CommunityReaction.tryParse(value as String?))
              .whereType<CommunityReaction>()
              .toSet()
          : null,
    );
  }

  static int _int(Object? value) => value is num ? value.toInt() : 0;
}

/// 글 한 건 — 계약의 `Post`.
class CommunityPost {
  final int id;
  final PersonRef author;
  final CommunityBoard? board;
  final String title;
  final String body;

  /// 표시용 장소 이름. 자유 문자열이다.
  final String? loc;

  /// 연결된 장소. **`Place.contentId` 와 같은 키다.**
  ///
  /// 2026-09 이전 계약은 이 자리를 `placeId` 라고 불렀고, 같은 개념이 조회에서는
  /// `contentId` 로 갈려 있었다 — ADR-0017 이 `contentId` 로 통일했다. #171 의 완료
  /// 조건은 `placeId` 라고 적었지만 그 이름은 계약에서 사라졌다.
  final String? contentId;

  final int commentCount;
  final ReactionSummary reactions;
  final DateTime createdAt;

  const CommunityPost({
    required this.id,
    required this.author,
    required this.board,
    required this.title,
    required this.body,
    required this.commentCount,
    required this.reactions,
    required this.createdAt,
    this.loc,
    this.contentId,
  });

  /// 모양이 아니면 `null`. 한 건이 깨졌다고 목록 전체를 버리지 않는다.
  static CommunityPost? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final author = PersonRef.tryParse(json['author']);
    final title = json['title'];
    final body = json['body'];
    final createdAt = _dateTime(json['createdAt']);
    if (id is! num || author == null || title is! String || body is! String ||
        createdAt == null) {
      return null;
    }
    return CommunityPost(
      id: id.toInt(),
      author: author,
      board: CommunityBoard.tryParse(json['board'] as String?),
      title: title,
      body: body,
      loc: json['loc'] as String?,
      contentId: json['contentId'] as String?,
      commentCount: ReactionSummary._int(json['commentCount']),
      reactions: ReactionSummary.parse(json['reactions']),
      createdAt: createdAt,
    );
  }
}

/// 댓글 한 건 — 계약의 `Comment`.
class CommunityComment {
  final int id;
  final PersonRef author;
  final String body;
  final DateTime createdAt;

  const CommunityComment({
    required this.id,
    required this.author,
    required this.body,
    required this.createdAt,
  });

  static CommunityComment? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final author = PersonRef.tryParse(json['author']);
    final body = json['body'];
    final createdAt = _dateTime(json['createdAt']);
    if (id is! num || author == null || body is! String || createdAt == null) {
      return null;
    }
    return CommunityComment(
      id: id.toInt(),
      author: author,
      body: body,
      createdAt: createdAt,
    );
  }
}

/// 커서 한 장 — 계약의 `PostPage` · `CommentPage`.
///
/// 셋 다 `items` 다. 채팅에서 이 키를 `messages` 로 읽어 대화가 **언제나 비어
/// 보였던** 적이 있다(#82). 그래서 목은 계약의 키로만 만든다.
class CommunityPage<T> {
  final List<T> items;
  final String? nextCursor;
  final bool hasMore;

  const CommunityPage({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });
}

DateTime? _dateTime(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toLocal() : null;

/// 실패의 종류. 화면이 이 값으로 문구를 고른다.
enum CommunityFailureKind {
  /// 연결이 없다. **다시 시도하면 된다.**
  network,

  /// 로그인이 필요하다(401). 읽기 셋은 여기 오지 않는다 — 게스트에게 열려 있다.
  unauthorized,

  /// 서버가 잠시 그만 보내라고 했다(429).
  rateLimited,

  /// 서버가 입력을 거절했다(400). **다시 눌러도 같다.**
  rejected,

  /// 그 글이 없다(404). 남이 지웠거나 애초에 없던 id 다.
  notFound,
}

extension CommunityFailureKindX on CommunityFailureKind {
  /// 화면에 그대로 그리는 문구.
  ///
  /// **빈 목록으로 그리지 않는다.** 빈 목록은 "아직 글이 없다" 로 읽히고, 그러면
  /// 서버가 죽은 것을 아무도 모른다 — `pet.dart` 가 산책 더미를 지우며 남긴 것과
  /// 같은 규칙이다.
  String get message => switch (this) {
        CommunityFailureKind.network => '불러오지 못했어요 · 연결을 확인해 주세요',
        CommunityFailureKind.unauthorized => '로그인하면 쓸 수 있어요',
        CommunityFailureKind.rateLimited => '잠시 후 다시 시도해 주세요',
        CommunityFailureKind.rejected => '보낼 수 없는 내용이에요',
        CommunityFailureKind.notFound => '글을 찾을 수 없어요',
      };

  /// 다시 눌러 볼 만한가. 재시도 버튼을 그릴지가 이 값으로 갈린다.
  bool get retryable => switch (this) {
        CommunityFailureKind.network => true,
        CommunityFailureKind.rateLimited => true,
        CommunityFailureKind.unauthorized => false,
        CommunityFailureKind.rejected => false,
        CommunityFailureKind.notFound => false,
      };
}

class CommunityFailure implements Exception {
  final CommunityFailureKind kind;

  const CommunityFailure(this.kind);

  String get message => kind.message;

  bool get retryable => kind.retryable;

  @override
  String toString() => 'CommunityFailure($kind)';
}

/// 커뮤니티 서버 연동의 유일한 입구.
class CommunityRepository {
  /// 요청 하나의 상한. 없으면 응답을 주지 않는 서버에서 화면이 영원히 로딩만 돈다.
  static const Duration timeout = Duration(seconds: 12);

  /// 제목·본문의 최대 길이. 계약의 `maxLength` 이자 서버의 `@Size` 와 같은 수다.
  ///
  /// 여기서 막지 않으면 상한을 넘긴 사람이 **올리기를 누른 뒤에야** 400 을 받는다 —
  /// `create_screen` 이 #161 에서 같은 이유를 적어 뒀다.
  ///
  /// 숫자가 두 곳에 있는 것을 없앨 수는 없다(서버는 자바다). 대신 갈리면
  /// `CommunityContractSpecTest` 가 이 파일을 읽어 빨간불을 낸다.
  ///
  /// 본문 상한은 #172 에서 생겼다. 그전에는 계약에도 서버에도 없었고, `post.body` 가
  /// `TEXT` 라 65535**바이트**까지 들어갔다 — 컬럼 타입이 흘린 수였지 제품이 고른 수가
  /// 아니다.
  static const int maxTitleLength = 200;
  static const int maxBodyLength = 5000;
  static const int maxCommentLength = 1000;

  /// 한 장의 크기. 서버의 기본값과 같은 20 이다.
  static const int pageSize = 20;

  final String baseUrl;
  final AuthedClient _authed;

  CommunityRepository({String? baseUrl, AuthedClient? client})
      : baseUrl = _stripTrailingSlash(baseUrl ?? Env.apiBase),
        _authed = client ?? AuthedClient.instance;

  static String _stripTrailingSlash(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  // ─────────────────────────── 읽기 (게스트도 된다) ───────────────────────────

  /// 글 목록. [board] 가 `null` 이면 전체다.
  Future<CommunityPage<CommunityPost>> feed({
    CommunityBoard? board,
    String? cursor,
    int? limit,
  }) async {
    final uri = Uri.parse('$baseUrl/api/community/posts').replace(
      queryParameters: <String, String>{
        if (board != null) 'board': board.wire,
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
        if (limit != null) 'limit': '$limit',
      },
    );
    final json = await _send(() => _authed.getJson(uri));
    return _page(json, CommunityPost.tryParse);
  }

  /// 글 하나.
  Future<CommunityPost> post(int postId) async {
    final json = await _send(
      () => _authed.getJson(Uri.parse('$baseUrl/api/community/posts/$postId')),
    );
    final post = CommunityPost.tryParse(json);
    if (post == null) throw const CommunityFailure(CommunityFailureKind.network);
    return post;
  }

  /// 댓글 목록. **오래된 것부터**다 — 스레드는 위에서 아래로 읽는다.
  Future<CommunityPage<CommunityComment>> comments(
    int postId, {
    String? cursor,
    int? limit,
  }) async {
    final uri =
        Uri.parse('$baseUrl/api/community/posts/$postId/comments').replace(
      queryParameters: <String, String>{
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
        if (limit != null) 'limit': '$limit',
      },
    );
    final json = await _send(() => _authed.getJson(uri));
    return _page(json, CommunityComment.tryParse);
  }

  // ─────────────────────────── 쓰기 (로그인 필요) ───────────────────────────

  Future<CommunityPost> createPost({
    required CommunityBoard board,
    required String title,
    required String body,
    String? loc,
    String? contentId,
  }) async {
    final json = await _send(
      () => _authed.postJson(
        Uri.parse('$baseUrl/api/community/posts'),
        body: {
          'board': board.wire,
          'title': title,
          'body': body,
          if (loc != null && loc.isNotEmpty) 'loc': loc,
          if (contentId != null && contentId.isNotEmpty) 'contentId': contentId,
        },
      ),
    );
    final post = CommunityPost.tryParse(json);
    if (post == null) throw const CommunityFailure(CommunityFailureKind.network);
    return post;
  }

  Future<CommunityComment> addComment(int postId, String body) async {
    final json = await _send(
      () => _authed.postJson(
        Uri.parse('$baseUrl/api/community/posts/$postId/comments'),
        body: {'body': body},
      ),
    );
    final comment = CommunityComment.tryParse(json);
    if (comment == null) {
      throw const CommunityFailure(CommunityFailureKind.network);
    }
    return comment;
  }

  /// 반응을 누른다. **멱등이다** — 이미 눌러 뒀어도 200 이고 집계가 안 늘어난다.
  ///
  /// 그래서 화면은 낙관적 갱신을 하지 않고 **응답의 집계를 그대로 그린다.** 로컬에서
  /// 세면 남이 같은 시간에 누른 것이 안 보이고, 실패했을 때 되돌릴 자리가 생긴다.
  Future<ReactionSummary> addReaction(
    int postId,
    CommunityReaction reaction,
  ) async {
    final json = await _send(
      () => _authed.postJson(
        Uri.parse(
          '$baseUrl/api/community/posts/$postId/reactions/${reaction.wire}',
        ),
      ),
    );
    return ReactionSummary.parse(json);
  }

  /// 반응을 뗀다. **멱등이다** — 안 눌렀던 것을 취소해도 200 이다.
  Future<ReactionSummary> removeReaction(
    int postId,
    CommunityReaction reaction,
  ) async {
    final json = await _send(
      () => _authed.deleteJson(
        Uri.parse(
          '$baseUrl/api/community/posts/$postId/reactions/${reaction.wire}',
        ),
      ),
    );
    return ReactionSummary.parse(json);
  }

  // ─────────────────────────── 지그 ───────────────────────────

  /// 커서 봉투 하나를 읽는다. 키는 `items`·`nextCursor`·`hasMore` 셋이다.
  static CommunityPage<T> _page<T>(
    Object? json,
    T? Function(Object?) parse,
  ) {
    if (json is! Map) {
      throw const CommunityFailure(CommunityFailureKind.network);
    }
    final rawItems = json['items'];
    return CommunityPage<T>(
      items: rawItems is List
          ? rawItems.map(parse).whereType<T>().toList()
          : const [],
      nextCursor: json['nextCursor'] as String?,
      hasMore: json['hasMore'] == true,
    );
  }

  Future<Object?> _send(Future<http.Response> Function() request) async {
    final http.Response res;
    try {
      res = await request().timeout(timeout);
    } on CommunityFailure {
      rethrow;
    } catch (_) {
      // 예외 메시지에 URL·본문 조각이 섞일 수 있어 타입도 문구도 옮기지 않는다.
      throw const CommunityFailure(CommunityFailureKind.network);
    }

    if (res.statusCode == 200 || res.statusCode == 201) {
      if (res.bodyBytes.isEmpty) return null;
      try {
        // bodyBytes + utf8 로 읽는다. `res.body` 는 charset 이 없는 응답을 latin-1 로
        // 읽어 한글이 깨진다(#81 에서 실제로 깨졌다).
        return jsonDecode(utf8.decode(res.bodyBytes));
      } catch (_) {
        throw const CommunityFailure(CommunityFailureKind.network);
      }
    }

    throw CommunityFailure(switch (res.statusCode) {
      400 => CommunityFailureKind.rejected,
      401 => CommunityFailureKind.unauthorized,
      404 => CommunityFailureKind.notFound,
      429 => CommunityFailureKind.rateLimited,
      _ => CommunityFailureKind.network,
    });
  }
}
