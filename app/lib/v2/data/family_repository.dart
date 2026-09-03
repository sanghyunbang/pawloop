// lib/v2/data/family_repository.dart
//
// 가족 그룹 · 오늘의 케어 · 산책 주의사항의 서버 연동 — 이슈 #76.
//
// ## 무엇이 바뀌었나
//
// 홈의 "오늘의 케어" 카드와 `family_screen` 은 `pet.dart` 의 로컬 리스트
// (`kCareToday`·`kFamilyMembers`·`kWalkNotes`)를 그리고 있었다. 그 상태에서는
// 엄마가 밥을 줘도 아빠 화면에는 아무 일도 일어나지 않는다 — 이 이슈가 막으려는
// 사고(이중 급여·산책 누락)가 정확히 거기서 생긴다.
//
// ## 규칙
//
//  1. HTTP 는 `AuthedClient` 하나로만 나간다. `Authorization` 헤더를 여기서 만들지
//     않는다 — 만드는 곳은 앱 전체에서 `authed_client.dart` 한 줄이고
//     `auth_header_single_source_test.dart` 가 그것을 잠근다(#11).
//  2. 실패를 **종류로** 나눈다([FamilyFailure]). 화면이 "네트워크가 없다" 와
//     "이 가족의 멤버가 아니다" 와 "아직 가족이 없다" 를 다르게 그려야 하는데,
//     `null` 하나로 뭉치면 셋이 같은 빈 화면이 된다.
//  3. **토큰 저장소를 건드리지 않는다.** 401 은 `AuthedClient` 가 갱신까지 시도한
//     뒤의 결과라 여기서 할 일이 없다 — 저장소를 비우는 곳은 한 곳이고
//     `token_clear_single_source_test.dart` 가 잠근다(#12).

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:heat_trip_flutter/core/config/env.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';

/// 케어 다섯 종류. 계약(`openapi.yaml` 의 `CareType`)과 **같은 문자열**을 쓴다.
///
/// `pet.dart` 의 `CareType`(물·밥·산책·투약·간식·기타)과 이름이 겹치지만 그쪽은
/// 화면 안에서만 사는 더미 도메인이고, 서버 계약은 이 다섯이다. 둘을 하나로 합치는
/// 것은 `pet.dart` 의 더미를 걷어내는 이슈가 할 일이다.
enum ServerCareType {
  water('water', '물'),
  meal('meal', '밥'),
  walk('walk', '산책'),
  med('med', '투약'),
  vet('vet', '병원');

  /// DB·계약·이 앱이 공유하는 단 하나의 표기.
  final String wire;

  /// 화면에 쓰는 이름.
  final String label;

  const ServerCareType(this.wire, this.label);

  /// 모르는 값이면 `null`. 서버가 종류를 늘렸는데 앱이 낡았을 때 **던지지 않는다** —
  /// 카드 한 칸이 안 그려지는 것과 화면 전체가 죽는 것은 다르다.
  static ServerCareType? tryParse(String? value) {
    for (final type in values) {
      if (type.wire == value) return type;
    }
    return null;
  }
}

/// 케어 기록 한 건 — 계약의 `CareLog`.
class CareLogEntry {
  final int id;
  final ServerCareType type;
  final int doneByUserId;
  final String doneByName;
  final DateTime occurredAt;
  final String? memo;

  const CareLogEntry({
    required this.id,
    required this.type,
    required this.doneByUserId,
    required this.doneByName,
    required this.occurredAt,
    this.memo,
  });

  /// `HH:mm`. 확인 문구와 카드가 같은 표기를 쓰도록 여기 한 곳에서 만든다.
  String get timeLabel =>
      '${occurredAt.hour.toString().padLeft(2, '0')}:'
      '${occurredAt.minute.toString().padLeft(2, '0')}';

  /// 모르는 종류면 `null` — 호출부가 걸러 낸다.
  static CareLogEntry? tryParse(Map<String, dynamic> json) {
    final type = ServerCareType.tryParse(json['type'] as String?);
    // **`.toLocal()` 이 필요하다.** 서버가 오프셋을 붙여 보내면(#209) Dart 는 그것을
    // **UTC** DateTime 으로 돌려준다 — 그대로 `.hour` 를 읽으면 KST 00:30 이 15:30 으로
    // 뜬다. community_repository 가 같은 이유로 같은 자리에서 `.toLocal()` 을 부른다.
    final occurredAt = DateTime.tryParse('${json['occurredAt']}')?.toLocal();
    if (type == null || occurredAt == null) return null;

    final doneBy = json['doneBy'];
    return CareLogEntry(
      id: (json['id'] as num?)?.toInt() ?? 0,
      type: type,
      doneByUserId: doneBy is Map
          ? ((doneBy['userId'] as num?)?.toInt() ?? 0)
          : 0,
      doneByName: doneBy is Map ? '${doneBy['nickname'] ?? ''}' : '',
      occurredAt: occurredAt,
      memo: json['memo'] as String?,
    );
  }
}

/// 산책 주의사항 한 장 — 계약의 `WalkNote`.
///
/// **서버는 메모 한 장을 안다.** 화면이 줄 단위 목록으로 그리는 것은 표현이고,
/// [lines] 와 [fromLines] 가 그 변환을 한 곳에 모은다.
class WalkNoteSheet {
  final String body;
  final String? updatedByName;
  final DateTime? updatedAt;

  const WalkNoteSheet({required this.body, this.updatedByName, this.updatedAt});

  static const WalkNoteSheet empty = WalkNoteSheet(body: '');

  /// 빈 줄은 항목이 아니다 — 사용자가 만든 빈 줄이 화면에서 빈 칸으로 보이면
  /// 지울 수도 없는 유령 항목이 된다.
  List<String> get lines => body
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();

  /// 목록을 서버가 아는 한 장으로 되돌린다.
  static String fromLines(List<String> lines) =>
      lines.map((line) => line.trim()).where((l) => l.isNotEmpty).join('\n');

  factory WalkNoteSheet.fromJson(Map<String, dynamic> json) {
    final updatedBy = json['updatedBy'];
    return WalkNoteSheet(
      body: '${json['body'] ?? ''}',
      updatedByName: updatedBy is Map ? '${updatedBy['nickname'] ?? ''}' : null,
      updatedAt: DateTime.tryParse('${json['updatedAt']}')?.toLocal(),
    );
  }
}

/// 가족 멤버 하나 — 계약의 `GroupMember`.
class FamilyMemberSummary {
  final int userId;
  final String nickname;

  /// `OWNER` 또는 `MEMBER`. 서버 표기 그대로다.
  final String role;

  const FamilyMemberSummary({
    required this.userId,
    required this.nickname,
    required this.role,
  });

  bool get isOwner => role == 'OWNER';

  factory FamilyMemberSummary.fromJson(Map<String, dynamic> json) =>
      FamilyMemberSummary(
        userId: (json['userId'] as num?)?.toInt() ?? 0,
        nickname: '${json['nickname'] ?? ''}',
        role: '${json['role'] ?? 'MEMBER'}',
      );
}

/// 내 가족 그룹 — 계약의 `Group`.
class FamilyGroupSummary {
  final int id;
  final String name;
  final int roomId;
  final List<FamilyMemberSummary> members;

  const FamilyGroupSummary({
    required this.id,
    required this.name,
    required this.roomId,
    required this.members,
  });

  factory FamilyGroupSummary.fromJson(Map<String, dynamic> json) =>
      FamilyGroupSummary(
        id: (json['id'] as num?)?.toInt() ?? 0,
        name: '${json['name'] ?? ''}',
        roomId: (json['roomId'] as num?)?.toInt() ?? 0,
        members: ((json['members'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(FamilyMemberSummary.fromJson)
            .toList(),
      );
}

/// 실패의 **종류**. 화면이 셋을 다르게 그려야 한다.
///
/// `null` 하나로 뭉치면 "비행기 모드" 와 "아직 가족을 안 만들었다" 가 같은 빈 화면이
/// 되고, 사용자는 무엇을 해야 하는지 알 수 없다.
enum FamilyFailureKind {
  /// 아직 가족 그룹이 없다(`GET /api/groups/me` 404). **오류가 아니다** — 만들면 된다.
  noGroup,

  /// 세션이 끝났다(401). `AuthedClient` 가 갱신까지 시도한 뒤의 결과다.
  unauthorized,

  /// 그 가족의 멤버가 아니다(403).
  forbidden,

  /// 이미 가족 그룹에 속해 있다(409). **만들기에서만 난다.**
  ///
  /// 서버가 두 번째 그룹을 막는다 — `GET /api/groups/me` 가 참여 순서로 하나만 돌려주므로
  /// 두 번째는 사용자가 존재도 삭제도 모르는 행이 된다(계약의 `POST /api/groups` 설명).
  ///
  /// [network] 로 뭉치면 "연결이 불안정해요 · 다시 시도" 가 뜬다. 다시 눌러도 영원히 같고,
  /// 사용자가 할 일은 다시 시도가 아니라 **화면을 새로 부르는 것**이다 — 이미 가족이 있으니
  /// 목록이 뜨면 된다.
  alreadyInGroup,

  /// 서버가 입력을 거절했다(400). **다시 시도해도 같은 결과다.**
  ///
  /// 이 네 경로에서 사용자가 실제로 만들 수 있는 400 은 **길이**다 — 주의사항 본문과
  /// 케어 메모가 각각 500자까지고(`CareService.MAX_TEXT_LENGTH`), 서버는 잘라서
  /// 저장하지 않고 거절한다. 케어 종류는 [ServerCareType] 에서만 나가므로 앱이 잘못된
  /// 값을 보낼 길이 없다.
  ///
  /// [network] 로 뭉치면 화면이 "연결이 불안정해요 · 다시 시도" 를 그린다 — 네트워크는
  /// 멀쩡하고 다시 눌러도 영원히 같은 결과라, 사용자가 할 수 있는 일이 화면 어디에도
  /// 없다. 종류를 나누는 이유가 정확히 이것이다.
  invalid,

  /// 요청이 너무 잦다(429).
  rateLimited,

  /// 네트워크·타임아웃·서버 오류. **다시 시도하면 될 수 있다.**
  network,
}

/// 호출부가 화면 상태로 옮기는 실패.
class FamilyFailure implements Exception {
  final FamilyFailureKind kind;
  final String message;

  const FamilyFailure(this.kind, this.message);

  /// 화면에 그대로 띄울 수 있는 문구. 서버 메시지를 쓰지 않는다 —
  /// 사용자에게 서버 내부 문구가 새는 것을 막고, 문구가 한 곳에 모인다.
  static String messageFor(FamilyFailureKind kind) => switch (kind) {
        FamilyFailureKind.noGroup => '아직 가족 그룹이 없어요',
        FamilyFailureKind.unauthorized => '다시 로그인해 주세요',
        FamilyFailureKind.forbidden => '이 가족의 멤버가 아니에요',
        FamilyFailureKind.alreadyInGroup => '이미 가족 그룹에 속해 있어요',
        FamilyFailureKind.invalid =>
          '메모는 모두 합쳐 ${FamilyRepository.maxTextLength}자까지 쓸 수 있어요',
        FamilyFailureKind.rateLimited => '잠시 후 다시 시도해 주세요',
        FamilyFailureKind.network => '연결이 불안정해요 · 다시 시도',
      };

  @override
  String toString() => 'FamilyFailure($kind)';
}

/// 가족 그룹 · 케어 · 주의사항 네 경로의 클라이언트.
class FamilyRepository {
  /// 요청 하나의 상한. 없으면 응답을 주지 않는 서버에서 화면이 영원히 로딩만 돈다 —
  /// `AuthedClient.refreshTimeout` 이 갱신 왕복에 대해 같은 것을 한다.
  static const Duration timeout = Duration(seconds: 12);

  /// 주의사항 본문·케어 메모의 최대 길이. 서버의 `CareService.MAX_TEXT_LENGTH` 와 같은
  /// 값이고 계약(`openapi.yaml` 의 `WalkNoteInput.body.maxLength`)에도 같은 숫자가 있다.
  ///
  /// 화면이 이 숫자를 직접 적지 않고 여기를 가리키는 이유: 숫자가 두 곳에 살면 한쪽만
  /// 늘어나는 날이 오고, 그때 사용자는 "500자까지" 라고 적힌 화면에서 저장에 실패한다.
  static const int maxTextLength = 500;

  final String baseUrl;
  final AuthedClient _authed;

  FamilyRepository({String? baseUrl, AuthedClient? client})
      : baseUrl = _stripTrailingSlash(baseUrl ?? Env.apiBase),
        _authed = client ?? AuthedClient.instance;

  static String _stripTrailingSlash(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  /// 내 가족 그룹. 속한 그룹이 없으면 [FamilyFailureKind.noGroup] 이다.
  /// 그룹 이름의 최대 길이. 서버의 `FamilyGroupService.MAX_NAME_LENGTH` 이자 계약의
  /// `maxLength` 와 같은 수다.
  ///
  /// 여기서 막지 않으면 51자를 쓴 사람이 만들기를 누른 뒤에야 400 을 받는다 —
  /// `create_screen` 이 #161 에서 같은 이유를 적어 뒀다.
  static const int maxGroupNameLength = 50;

  /// 가족 그룹을 만든다 — 이슈 #196.
  ///
  /// **초대 코드는 여기서 안 나온다.** 응답의 [FamilyGroupSummary.roomId] 를 들고
  /// [issueInvite] 를 부른다. 2026-08 이전에는 이 경로가 초대 코드를 함께 줬는데
  /// ADR-0011 이 초대를 방으로 옮기면서 옛 모양이 됐다(#75).
  ///
  /// 이미 가족이 있으면 [FamilyFailureKind.alreadyInGroup] 이다.
  Future<FamilyGroupSummary> createGroup(String name) async {
    final json = await _send(
      () => _authed.postJson(Uri.parse('$baseUrl/api/groups'), body: {'name': name}),
    );
    return FamilyGroupSummary.fromJson(json as Map<String, dynamic>);
  }

  Future<FamilyGroupSummary> myGroup() async {
    final json = await _send(
      () => _authed.getJson(Uri.parse('$baseUrl/api/groups/me')),
      notFoundIs: FamilyFailureKind.noGroup,
    );
    return FamilyGroupSummary.fromJson(json as Map<String, dynamic>);
  }

  /// 그 그룹의 하루치 케어. [date] 를 생략하면 서버가 오늘로 답한다.
  Future<List<CareLogEntry>> careLogs(int groupId, {DateTime? date}) async {
    final query = date == null ? '' : '?date=${_isoDate(date)}';
    final json = await _send(
      () => _authed.getJson(Uri.parse('$baseUrl/api/groups/$groupId/care-logs$query')),
    );
    return (json as List)
        .whereType<Map<String, dynamic>>()
        .map(CareLogEntry.tryParse)
        .whereType<CareLogEntry>()
        .toList();
  }

  /// 케어 한 건 기록. **수행자와 시각은 서버가 정한다** — 보낼 것이 없다.
  Future<CareLogEntry> recordCare(int groupId, ServerCareType type, {String? memo}) async {
    final json = await _send(
      () => _authed.postJson(
        Uri.parse('$baseUrl/api/groups/$groupId/care-logs'),
        body: {'type': type.wire, if (memo != null && memo.isNotEmpty) 'memo': memo},
      ),
    );
    final parsed = CareLogEntry.tryParse(json as Map<String, dynamic>);
    if (parsed == null) {
      throw const FamilyFailure(FamilyFailureKind.network, '응답을 읽지 못했어요');
    }
    return parsed;
  }

  /// 초대코드를 하나 발급한다. **방장만** 부를 수 있고 아니면 403 이다.
  ///
  /// 경로가 `/api/groups` 가 아니라 `/api/chat/rooms/{roomId}/invites` 인 것은
  /// ADR-0011 때문이다 — 초대코드는 그룹이 아니라 **방**에 붙고 만료·사용횟수·회수를
  /// 가진다. `roomId` 는 [FamilyGroupSummary.roomId] 다.
  ///
  /// **발급할 때마다 새 코드가 생기고 이전 코드는 죽지 않는다**(#75 에서 실측으로 확인된
  /// 동작이다). 그래서 화면에서 "새 코드 발급" 을 유출 대응 버튼처럼 광고하면 안 된다.
  Future<String> issueInvite(int roomId) async {
    final json = await _send(
      () => _authed.postJson(Uri.parse('$baseUrl/api/chat/rooms/$roomId/invites')),
    );
    return '${(json as Map)['code'] ?? ''}';
  }

  /// 그 그룹의 산책 주의사항 한 장. 아직 없으면 본문이 빈 문자열이다(404 가 아니다).
  Future<WalkNoteSheet> walkNote(int groupId) async {
    final json = await _send(
      () => _authed.getJson(Uri.parse('$baseUrl/api/groups/$groupId/walk-notes')),
    );
    return WalkNoteSheet.fromJson(json as Map<String, dynamic>);
  }

  /// 주의사항 전체 교체. 화면의 목록을 [WalkNoteSheet.fromLines] 로 한 장에 담아 보낸다.
  Future<WalkNoteSheet> replaceWalkNote(int groupId, String body) async {
    final json = await _send(
      () => _authed.putJson(
        Uri.parse('$baseUrl/api/groups/$groupId/walk-notes'),
        body: {'body': body},
      ),
    );
    return WalkNoteSheet.fromJson(json as Map<String, dynamic>);
  }

  // ── 공통 ────────────────────────────────────────────────────────────────

  static String _isoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// 한 번의 왕복. **상태 코드를 실패의 종류로 옮기는 곳이 여기 하나다.**
  ///
  /// 호출부마다 `res.statusCode` 를 읽게 두면 401 을 로그아웃으로 읽는 곳과
  /// 무시하는 곳이 함께 생긴다.
  Future<Object?> _send(
    Future<http.Response> Function() request, {
    FamilyFailureKind? notFoundIs,
  }) async {
    final http.Response res;
    try {
      res = await request().timeout(timeout);
    } on FamilyFailure {
      rethrow;
    } catch (_) {
      // 예외 메시지에 URL·본문 조각이 섞일 수 있어 타입도 문구도 옮기지 않는다.
      throw FamilyFailure(
        FamilyFailureKind.network,
        FamilyFailure.messageFor(FamilyFailureKind.network),
      );
    }

    if (res.statusCode == 200 || res.statusCode == 201) {
      try {
        return jsonDecode(utf8.decode(res.bodyBytes));
      } catch (_) {
        throw FamilyFailure(
          FamilyFailureKind.network,
          FamilyFailure.messageFor(FamilyFailureKind.network),
        );
      }
    }

    final kind = switch (res.statusCode) {
      // 서버가 입력을 거절했다. 여기가 없으면 `_ => network` 로 떨어져 화면이
      // "연결이 불안정해요 · 다시 시도" 를 그리는데, 다시 눌러도 영원히 같은 결과다.
      400 => FamilyFailureKind.invalid,
      // AuthedClient 가 갱신 + 재시도까지 끝낸 뒤의 401 이다. 세션이 끝났다.
      401 => FamilyFailureKind.unauthorized,
      403 => FamilyFailureKind.forbidden,
      409 => FamilyFailureKind.alreadyInGroup,
      404 => notFoundIs ?? FamilyFailureKind.network,
      429 => FamilyFailureKind.rateLimited,
      _ => FamilyFailureKind.network,
    };
    throw FamilyFailure(kind, FamilyFailure.messageFor(kind));
  }
}
