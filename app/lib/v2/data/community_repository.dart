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

// 신고 사유는 채팅과 같은 어휘다 — 값이 두 벌이 되면 앱이 분기를 두 번 짜고
// 운영자가 세는 숫자가 두 표에서 다른 뜻이 된다(#166). 계약도 ReportReason 을
// 컴포넌트로 뽑아 두 경로가 함께 참조한다.
import 'chat_repository.dart' show ChatReportReason;

import 'package:heat_trip_flutter/core/config/env.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'location_upload_policy.dart';
import '../domain/post_media.dart';

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
/// 글에 붙은 코스 — 계약의 `Post.course` (#339).
///
/// [path] 는 **이미 잘라 낸 선을 더 줄인 것**(최대 40점)이다. 카드에 그릴 그림용이고, 온전한
/// 선이 필요하면 `CourseRepository.one` 을 부른다.
class PostCourse {
  final int id;
  final String name;
  final int distanceM;
  final List<List<double>> path;

  const PostCourse({
    required this.id,
    required this.name,
    required this.distanceM,
    this.path = const [],
  });

  double get km => distanceM / 1000.0;

  /// 선이 되려면 점이 둘은 있어야 한다.
  bool get drawable => path.length >= 2;

  static PostCourse? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final name = json['name'];
    if (id is! int || name is! String) return null;
    final rawPath = json['path'];
    return PostCourse(
      id: id,
      name: name,
      distanceM: (json['distanceM'] as num?)?.toInt() ?? 0,
      path: rawPath is List
          ? rawPath
              .whereType<List>()
              .map((p) => p.whereType<num>().map((n) => n.toDouble()).toList())
              .where((p) => p.length == 2)
              .toList()
          : const [],
    );
  }
}

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

  /// 붙어 있는 코스 (#339). 안 붙였거나, 붙인 뒤 **비공개로 되돌렸거나**, 코스를 지웠으면
  /// `null` 이다 — 셋을 구분하지 않는다. 화면에는 "그림이 없다" 로 같다.
  final PostCourse? course;

  final int commentCount;
  final ReactionSummary reactions;
  final DateTime createdAt;

  /// 읽는 사람이 이 작성자를 가렸는가 — 이슈 #166.
  ///
  /// **목록에서 빠지지 않는다.** 빼면 커서가 그 글을 건너뛰어 페이지 경계가 어긋나고,
  /// 가린 자리에 '보기' 를 두려면 본문이 이미 와 있어야 한다. 접는 것은 화면의 일이다 —
  /// 채팅의 `hiddenByBlock` 과 같은 규약이다.
  final bool hiddenByBlock;

  /// 글쓴이의 동네 — **구까지만** (#342). 안 골랐으면 `null` 이다.
  ///
  /// 동 이름은 계약에 아예 없다. 남의 사는 곳을 구보다 좁히면 그것만으로 사람을 찾아갈 수 있다.
  final String? authorDistrict;

  /// 마지막 수정 시각. **`null` 이면 한 번도 안 고친 글이다**(#211).
  ///
  /// 서버가 `createdAt` 을 복사해 채우지 않는다 — 그러면 모든 글에 '수정됨' 이 붙는다.
  /// 같은 값을 다시 보낸 `PATCH` 도 이 값을 안 만든다. 즉 이 값이 있으면 **내용이
  /// 실제로 달라졌다**는 뜻이고, 그래서 화면이 그것을 표시할 근거가 된다.
  final DateTime? updatedAt;

  /// 붙은 사진·영상 (#429). **항상 있다** — 없으면 빈 목록. 순서는 올린 순서다.
  final List<PostMedia> media;

  const CommunityPost({
    required this.id,
    required this.author,
    required this.board,
    required this.title,
    required this.body,
    required this.commentCount,
    required this.reactions,
    required this.createdAt,
    this.updatedAt,
    this.hiddenByBlock = false,
    this.loc,
    this.contentId,
    this.course,
    this.authorDistrict,
    this.media = const [],
  });

  /// 한 자리만 바꾼 사본.
  ///
  /// **화면이 손으로 베끼지 않게 한다.** `post_detail_screen` 이 댓글 수와 반응을 각각
  /// 베끼는 헬퍼 둘을 들고 있었는데, `updatedAt` 을 더하자 그중 하나가 그것을 조용히
  /// 흘렸다 — 반응만 눌러도 '수정됨' 이 사라졌다. 필드가 늘 때 고칠 자리를 **선언 옆
  /// 한 곳**으로 모은다.
  CommunityPost copyWith({int? commentCount, ReactionSummary? reactions}) =>
      CommunityPost(
        id: id,
        author: author,
        board: board,
        title: title,
        body: body,
        loc: loc,
        contentId: contentId,
        course: course,
        commentCount: commentCount ?? this.commentCount,
        reactions: reactions ?? this.reactions,
        createdAt: createdAt,
        updatedAt: updatedAt,
        hiddenByBlock: hiddenByBlock,
        authorDistrict: authorDistrict,
        media: media,
      );

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
      course: PostCourse.tryParse(json['course']),
      commentCount: ReactionSummary._int(json['commentCount']),
      reactions: ReactionSummary.parse(json['reactions']),
      createdAt: createdAt,
      updatedAt: _dateTime(json['updatedAt']),
      hiddenByBlock: json['hiddenByBlock'] == true,
      authorDistrict: json['authorDistrict'] as String?,
      media: PostMedia.parseList(json['media']),
    );
  }
}

/// 댓글 한 건 — 계약의 `Comment`.
class CommunityComment {
  final int id;
  final PersonRef author;
  final String body;
  final DateTime createdAt;

  /// 읽는 사람이 이 작성자를 가렸는가 — #166. 규칙은 `CommunityPost.hiddenByBlock` 과 같다.
  final bool hiddenByBlock;

  const CommunityComment({
    required this.id,
    required this.author,
    required this.body,
    required this.createdAt,
    this.hiddenByBlock = false,
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
      hiddenByBlock: json['hiddenByBlock'] == true,
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

  /// 내 것이 아니다(403). 삭제와 수정에서 난다.
  ///
  /// **커뮤니티는 404 로 합치지 않는다.** `Dogs`·`Walks` 는 남의 것을 없는 것과 같게
  /// 보이지만(ADR-0017 규약 3) 글은 누구나 읽을 수 있어서 존재가 이미 공개다 — 404 로
  /// 숨겨도 방금 목록에서 본 것을 숨기는 셈이고, 사용자는 "지웠는데 안 사라졌다" 로 읽는다.
  ///
  /// [network] 로 뭉치면 "연결을 확인해 주세요" 가 뜬다. 연결은 멀쩡하고 다시 눌러도
  /// 영원히 같다.
  forbidden,

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
        CommunityFailureKind.forbidden => '내가 쓴 것만 고치거나 지울 수 있어요',
        CommunityFailureKind.notFound => '글을 찾을 수 없어요',
      };

  /// 다시 눌러 볼 만한가. 재시도 버튼을 그릴지가 이 값으로 갈린다.
  bool get retryable => switch (this) {
        CommunityFailureKind.network => true,
        CommunityFailureKind.rateLimited => true,
        CommunityFailureKind.unauthorized => false,
        CommunityFailureKind.rejected => false,
        CommunityFailureKind.forbidden => false,
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
  ///
  /// [myNeighborhood] 를 켜면 **내가 고른 구**의 글만 온다(#342). 구 코드를 보내지 않는다 —
  /// 서버가 내 저장된 동네로만 좁힌다. 동네를 안 골랐으면 서버가 400 이므로, 화면은 동네가
  /// 있을 때만 이 토글을 보여 준다.
  Future<CommunityPage<CommunityPost>> feed({
    CommunityBoard? board,
    String? cursor,
    int? limit,
    bool myNeighborhood = false,
  }) async {
    final uri = Uri.parse('$baseUrl/api/community/posts').replace(
      queryParameters: <String, String>{
        if (board != null) 'board': board.wire,
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
        if (limit != null) 'limit': '$limit',
        if (myNeighborhood) 'neighborhood': 'mine',
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

    /// 붙일 코스 (#339). **내 것이면서 공개된 코스**만 붙는다 — 아니면 서버가 400 이다.
    int? courseId,

    /// 미리 올려 둔 사진의 id — `POST /media` 가 돌려준 값 (#429). 순서는 올린 순서다.
    List<int>? mediaIds,
  }) async {
    final uploadLoc = LocationUploadPolicy.placeNameForUpload(loc);
    final uploadContentId = LocationUploadPolicy.placeIdForUpload(contentId);

    final json = await _send(
      () => _authed.postJson(
        Uri.parse('$baseUrl/api/community/posts'),
        body: {
          'board': board.wire,
          'title': title,
          'body': body,
          // 장소는 정책을 지난다(#235). 사용자가 탭한 공개 장소의 이름·id 지만, 그
          // 목록 자체가 현위치 반경 조회의 결과라 "이 근처에 있었다" 를 함의할 수 있다.
          if (uploadLoc != null && uploadLoc.isNotEmpty) 'loc': uploadLoc,
          if (uploadContentId != null && uploadContentId.isNotEmpty)
            'contentId': uploadContentId,
          // 코스는 좌표가 아니다 — 서버가 이미 양 끝을 자른 선의 식별자다(#339).
          if (courseId != null) 'courseId': courseId,
          if (mediaIds != null && mediaIds.isNotEmpty) 'mediaIds': mediaIds,
        },
      ),
    );
    final post = CommunityPost.tryParse(json);
    if (post == null) throw const CommunityFailure(CommunityFailureKind.network);
    return post;
  }

  /// 이미 쓴 글에 코스를 붙인다 (#339). 붙어 있으면 갈아 끼운다.
  Future<CommunityPost> attachCourse(int postId, int courseId) async {
    final json = await _send(
      () => _authed.putJson(
        Uri.parse('$baseUrl/api/community/posts/$postId/course'),
        body: {'courseId': courseId},
      ),
    );
    final post = CommunityPost.tryParse(json);
    if (post == null) throw const CommunityFailure(CommunityFailureKind.network);
    return post;
  }

  /// 붙은 코스를 뗀다. 코스 자체는 남는다.
  Future<CommunityPost> detachCourse(int postId) async {
    final json = await _send(
      () => _authed.deleteJson(Uri.parse('$baseUrl/api/community/posts/$postId/course')),
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

  /// 내 글을 지운다 — 이슈 #211.
  ///
  /// **댓글과 반응이 함께 사라진다**(FK CASCADE). 남의 글이면 403 이다 — 404 가 아니다.
  /// 글은 누구나 읽을 수 있어서 존재가 이미 공개라, 404 로 숨겨도 방금 목록에서 본 것을
  /// 숨기는 셈이다.
  ///
  /// 탈퇴한 사람의 글도 403 이다 — 주인이 없는 글을 아무나 지우면 그게 관리 권한이다.
  Future<void> deletePost(int postId) async {
    await _send(
      () => _authed.deleteJson(Uri.parse('$baseUrl/api/community/posts/$postId')),
    );
  }

  /// 내 댓글을 지운다. **글 주인이라도 남의 댓글은 못 지운다** — 관리는 별도 결정이다.
  Future<void> deleteComment(int postId, int commentId) async {
    await _send(
      () => _authed.deleteJson(
        Uri.parse('$baseUrl/api/community/posts/$postId/comments/$commentId'),
      ),
    );
  }


  /// 글을 고친다 — 이슈 #243. **보낸 키만 바뀐다.**
  ///
  /// <b>안 바뀐 것은 안 보낸다.</b> 계약이 `PostPatch` 를 `minProperties: 1` 로 두었고,
  /// `PostInput` 을 재사용하면 제목만 고치려는 사람도 본문을 다시 보내야 한다 — 그 사이
  /// 다른 기기에서 고친 본문을 조용히 되돌린다(ADR-0017 규약 4).
  ///
  /// **`loc`·`contentId` 는 못 바꾼다.** 계약이 `PostPatch` 에서 뺐다 — 비우기와 안 바꿈을
  /// 구별할 방법이 아직 없어서다. 화면이 그 칸을 잠근다.
  ///
  /// 셋 다 `null` 이면 **요청을 안 보낸다.** 서버가 400 을 주는데, 그건 사용자가 볼 이유가
  /// 없는 실패다 — 아무것도 안 고친 것은 잘못이 아니다.
  Future<CommunityPost?> updatePost(
    int postId, {
    CommunityBoard? board,
    String? title,
    String? body,

    /// 붙은 사진을 **통째로 갈아 끼운다** (#429). `null` 이면 안 바꾸고, 빈 목록이면 전부 뗀다 —
    /// `PostPatch` 의 "키가 없으면 안 바꿈" 과 같은 규약이다.
    List<int>? mediaIds,
  }) async {
    final patch = <String, Object?>{
      if (board != null) 'board': board.wire,
      if (title != null) 'title': title,
      if (body != null) 'body': body,
      if (mediaIds != null) 'mediaIds': mediaIds,
    };
    if (patch.isEmpty) return null;

    final json = await _send(
      () => _authed.patchJson(
        Uri.parse('$baseUrl/api/community/posts/$postId'),
        body: patch,
      ),
    );
    final post = CommunityPost.tryParse(json);
    if (post == null) throw const CommunityFailure(CommunityFailureKind.network);
    return post;
  }

  /// 글을 신고한다 — 이슈 #166.
  ///
  /// **내 글은 못 신고한다**(서버가 400). 화면이 먼저 막지만, 게스트나 상태가 어긋난
  /// 경우에 대비해 서버도 막는다.
  ///
  /// **같은 글을 여러 번 신고할 수 있다.** 글이 수정되기 때문이다(#211) — 막으면 작성자가
  /// 신고 뒤 본문을 더 나쁜 것으로 고쳤을 때 재신고가 안 된다.
  Future<void> reportPost(int postId, ChatReportReason reason, {String? memo}) async {
    await _send(
      () => _authed.postJson(
        Uri.parse('$baseUrl/api/community/posts/$postId/reports'),
        body: {'reason': reason.wire, if (memo != null && memo.isNotEmpty) 'memo': memo},
      ),
    );
  }

  /// 이 사람을 가린다 — 이슈 #166.
  ///
  /// **채팅과 같은 경로다**(`POST /api/blocks`). 가리기는 처음부터 사람 단위라 방도
  /// 게시판도 안 가린다 — 커뮤니티에서 가린 사람은 채팅에서도 접힌다.
  ///
  /// **이미 가려 뒀어도 성공이다.** 없던 것과 있던 것을 나누면 앱이 두 갈래를 다뤄야
  /// 하는데 사용자에게는 결과가 같다.
  Future<void> blockUser(int userId) async {
    await _send(
      () => _authed.postJson(Uri.parse('$baseUrl/api/blocks'), body: {'userId': userId}),
    );
  }

  /// 댓글을 신고한다. **부모 글이 맥락으로 함께 저장된다** — 서버가 한다.
  Future<void> reportComment(
    int postId,
    int commentId,
    ChatReportReason reason, {
    String? memo,
  }) async {
    await _send(
      () => _authed.postJson(
        Uri.parse('$baseUrl/api/community/posts/$postId/comments/$commentId/reports'),
        body: {'reason': reason.wire, if (memo != null && memo.isNotEmpty) 'memo': memo},
      ),
    );
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

    // 204 는 본문이 없다(삭제). 여기가 없으면 아래 switch 의 `_ => network` 로 떨어져
    // 성공한 삭제가 "연결을 확인해 주세요" 가 된다.
    if (res.statusCode == 204) return null;

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
      403 => CommunityFailureKind.forbidden,
      404 => CommunityFailureKind.notFound,
      429 => CommunityFailureKind.rateLimited,
      _ => CommunityFailureKind.network,
    });
  }
}
