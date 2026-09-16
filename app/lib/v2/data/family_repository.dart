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
import '../../core/net/net_timeouts.dart';

/// 케어 일곱 종류. 계약(`openapi.yaml` 의 `CareType`)과 **같은 문자열**을 쓴다.
///
/// `pet.dart` 의 `CareType`(물·밥·산책·투약·간식·기타)과 이름이 겹치지만 그쪽은
/// 화면 안에서만 사는 더미 도메인이고, 서버 계약은 이 일곱이다. 둘을 하나로 합치는
/// 것은 `pet.dart` 의 더미를 걷어내는 이슈가 할 일이다.
///
/// 뒤의 둘(`poop`·`pee`)은 산책 중 한 탭으로 들어온다(#340) — `WalkMomentKind` 가 그
/// 화면의 값이고 여기로 옮겨 담긴다. **어디서 눴는지는 안 실린다.**
enum ServerCareType {
  water('water', '물'),
  meal('meal', '밥'),
  walk('walk', '산책'),
  med('med', '투약'),
  vet('vet', '병원'),
  poop('poop', '배변'),
  pee('pee', '마킹');

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

  /// 기본 일곱이면 그 종류, **직접 만든 항목이면 `null`**(#560).
  ///
  /// 예전에는 `null` 이면 이 줄을 통째로 버렸다. 그대로 뒀으면 사용자가 만든 "양치" 를
  /// 눌러도 **카드에 아무 일도 안 일어난다** — 서버에는 쌓이는데 화면만 조용한, 이 저장소가
  /// 여러 번 겪은 모양이다.
  final ServerCareType? type;

  /// **어느 칸의 기록인가**(#560). 서버가 풀어서 준다 — 앱이 다시 계산하지 않는다.
  ///
  /// 기본 일곱의 기록은 행에 항목이 안 적혀 있어도 서버가 그 집의 같은 종류 칸을 찾아
  /// 넣는다. 그 갈래를 여기서 다시 적으면 규칙이 서버와 앱 두 곳에 생긴다.
  final int? careItemId;

  final int doneByUserId;
  final String doneByName;
  final DateTime occurredAt;
  final String? memo;

  const CareLogEntry({
    required this.id,
    required this.type,
    required this.careItemId,
    required this.doneByUserId,
    required this.doneByName,
    required this.occurredAt,
    this.memo,
  });

  /// `HH:mm`. 확인 문구와 카드가 같은 표기를 쓰도록 여기 한 곳에서 만든다.
  String get timeLabel =>
      '${occurredAt.hour.toString().padLeft(2, '0')}:'
      '${occurredAt.minute.toString().padLeft(2, '0')}';

  /// 시각을 못 읽으면 `null` — 호출부가 걸러 낸다.
  ///
  /// **종류가 없다고 버리지 않는다.** 직접 만든 항목의 기록은 종류가 비어 있고
  /// `careItemId` 만 든다(#560). 예전 규칙대로 버리면 그 기록이 화면에서 통째로 사라진다.
  static CareLogEntry? tryParse(Map<String, dynamic> json) {
    final type = ServerCareType.tryParse(json['type'] as String?);
    // **`.toLocal()` 이 필요하다.** 서버가 오프셋을 붙여 보내면(#209) Dart 는 그것을
    // **UTC** DateTime 으로 돌려준다 — 그대로 `.hour` 를 읽으면 KST 00:30 이 15:30 으로
    // 뜬다. community_repository 가 같은 이유로 같은 자리에서 `.toLocal()` 을 부른다.
    final occurredAt = DateTime.tryParse('${json['occurredAt']}')?.toLocal();
    if (occurredAt == null) return null;

    final doneBy = json['doneBy'];
    return CareLogEntry(
      id: (json['id'] as num?)?.toInt() ?? 0,
      type: type,
      careItemId: (json['careItemId'] as num?)?.toInt(),
      doneByUserId: doneBy is Map
          ? ((doneBy['userId'] as num?)?.toInt() ?? 0)
          : 0,
      doneByName: doneBy is Map ? '${doneBy['nickname'] ?? ''}' : '',
      occurredAt: occurredAt,
      memo: json['memo'] as String?,
    );
  }
}

/// 그 집이 챙기는 일 하나 — 계약의 `CareItem`. 이슈 #560.
///
/// 홈 카드의 **칸 하나**가 이 객체다. 고치기 화면은 접힌 것까지 같은 목록으로 본다.
class CareItemEntry {
  final int id;

  /// 그 아이에게만 하는 일이면 그 아이, **비어 있으면 모든 아이**.
  final int? dogId;

  final String name;

  /// 그림을 고르는 열쇠말. **모르는 값이면 기본 그림으로 떨어진다** — 서버가 목록을 넓혀도
  /// 옛 앱이 안 깨지게 하려는 것이다.
  final String icon;

  /// 기본 일곱이면 그 종류, 직접 만든 것이면 `null`. **고칠 수 없는 값이다.**
  final ServerCareType? systemType;

  /// 하루 몇 번. 비어 있으면 횟수만 세고, 있으면 `1/2` 로 그린다.
  final int? dailyTarget;

  final int sortOrder;

  /// 접은 시각. **비어 있으면 카드에 뜬다.**
  final DateTime? archivedAt;

  const CareItemEntry({
    required this.id,
    required this.dogId,
    required this.name,
    required this.icon,
    required this.systemType,
    required this.dailyTarget,
    required this.sortOrder,
    required this.archivedAt,
  });

  bool get archived => archivedAt != null;

  /// 기본 일곱인가. **"주변 찾기" 같은 부가 기능이 붙는 자리**이고, 직접 만든 항목은
  /// 단순 투두다(사장님, 2026-09-16).
  bool get isSystem => systemType != null;

  /// 이름이나 아이콘을 못 읽으면 `null` — 그 칸은 그릴 것이 없다.
  static CareItemEntry? tryParse(Map<String, dynamic> json) {
    final id = (json['id'] as num?)?.toInt();
    final name = json['name'] as String?;
    final icon = json['icon'] as String?;
    if (id == null || name == null || name.isEmpty || icon == null) return null;

    // `.toLocal()` 이 필요한 이유는 CareLogEntry.tryParse 와 같다.
    final archivedAt = json['archivedAt'] == null
        ? null
        : DateTime.tryParse('${json['archivedAt']}')?.toLocal();

    return CareItemEntry(
      id: id,
      dogId: (json['dogId'] as num?)?.toInt(),
      name: name,
      icon: icon,
      systemType: ServerCareType.tryParse(json['systemType'] as String?),
      dailyTarget: (json['dailyTarget'] as num?)?.toInt(),
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      archivedAt: archivedAt,
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
  /// **서버에 못 닿았다** — 상한([NetTimeouts.standard]) 안에 아무 답도 안 왔다(#573).
  ///
  /// [network] 와 나누는 이유: `network` 는 5xx 도 담는데, 그건 **서버는 살아 있고 그
  /// 경로만 죽은 것**이라 다른 경로는 될 수 있다. 못 닿은 것이면 다음 요청도 같은 상한을
  /// 통째로 태우고 같은 이유로 죽는다 — 부르는 쪽이 그걸 알아야 두 번 안 기다린다.
  ///
  /// 사용자에게 보이는 문구는 [network] 와 같다. 사람이 할 일은 둘 다 "다시 시도" 다.
  timeout,

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

  /// 지우려는 기록이 이미 없다(`DELETE …/care-logs/{id}` 404) — 벌써 지웠거나 이 그룹의
  /// 것이 아니다. **다시 시도할 일이 아니다** — 목록을 다시 읽으면 된다.
  gone,

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
        // 못 닿은 것과 연결이 불안정한 것은 사람이 할 일이 같다 — 문구도 같다(#573).
        FamilyFailureKind.timeout => '연결이 불안정해요 · 다시 시도',
        FamilyFailureKind.noGroup => '아직 가족 그룹이 없어요',
        FamilyFailureKind.unauthorized => '다시 로그인해 주세요',
        FamilyFailureKind.forbidden => '이 가족의 멤버가 아니에요',
        FamilyFailureKind.alreadyInGroup => '이미 가족 그룹에 속해 있어요',
        FamilyFailureKind.invalid =>
          '메모는 모두 합쳐 ${FamilyRepository.maxTextLength}자까지 쓸 수 있어요',
        FamilyFailureKind.rateLimited => '잠시 후 다시 시도해 주세요',
        FamilyFailureKind.gone => '이미 지워진 기록이에요',
        FamilyFailureKind.network => '연결이 불안정해요 · 다시 시도',
      };

  @override
  String toString() => 'FamilyFailure($kind)';
}

/// 가족 그룹 · 케어 · 주의사항 네 경로의 클라이언트.
class FamilyRepository {
  /// 요청 하나의 상한. 없으면 응답을 주지 않는 서버에서 화면이 영원히 로딩만 돈다 —
  /// `AuthedClient.refreshTimeout` 이 갱신 왕복에 대해 같은 것을 한다.
  static const Duration timeout = NetTimeouts.standard;

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
  ///
  /// [dogId] 를 주면 **그 아이 것과 아이 없는 옛 기록**이 함께 온다(#563). 옛 기록을 빼면
  /// 어제 준 밥이 화면에서 사라지고, 사라지면 "아직" 으로 읽혀 한 번 더 준다 — 이 표가
  /// 막으려는 것이 정확히 그 이중 급여다(#76).
  Future<List<CareLogEntry>> careLogs(int groupId, {DateTime? date, int? dogId}) async {
    final params = <String>[
      if (date != null) 'date=${_isoDate(date)}',
      if (dogId != null) 'dogId=$dogId',
    ];
    final query = params.isEmpty ? '' : '?${params.join('&')}';
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
  ///
  /// [dogId] 는 **어느 아이에게 한 일인가**다(#563). 이 앱의 목적이 업무 분담이라 "해당
  /// 동물을 누르면 누가 무엇을 했는지" 가 보여야 하고, 그러려면 기록에 아이가 붙어야 한다.
  /// 아이를 한 마리도 등록하지 않은 집도 기록하므로 **선택**이다.
  /// **[type] 과 [careItemId] 는 정확히 하나다**(#560). 기본 일곱은 종류로, 직접 만든
  /// 항목은 번호로 보낸다 — 둘 다 없거나 둘 다 있으면 서버가 400 이다. 기본 항목을 종류로
  /// 보내면 서버가 항목까지 붙여 주므로, 옛 집계와 산책 화면의 `type='walk'` 조회가
  /// 그대로 돈다.
  Future<CareLogEntry> recordCare(int groupId, ServerCareType? type,
      {String? memo, int? dogId, int? careItemId}) async {
    final json = await _send(
      () => _authed.postJson(
        Uri.parse('$baseUrl/api/groups/$groupId/care-logs'),
        body: {
          if (type != null) 'type': type.wire,
          if (careItemId != null) 'careItemId': careItemId,
          if (memo != null && memo.isNotEmpty) 'memo': memo,
          if (dogId != null) 'dogId': dogId,
        },
      ),
    );
    final parsed = CareLogEntry.tryParse(json as Map<String, dynamic>);
    if (parsed == null) {
      throw const FamilyFailure(FamilyFailureKind.network, '응답을 읽지 못했어요');
    }
    return parsed;
  }

  /// 그 집이 챙기는 일의 목록 — **접힌 것까지**, 순서대로(#560).
  ///
  /// 접힌 것을 빼지 않는 이유는 고치기 화면이 "다시 켜기" 를 그려야 하기 때문이다. 카드는
  /// [CareItemEntry.archived] 로 거른다 — 조회를 나누면 "접힘" 의 정의가 두 곳에 생긴다.
  Future<List<CareItemEntry>> careItems(int groupId) async {
    final json = await _send(
      () => _authed.getJson(Uri.parse('$baseUrl/api/groups/$groupId/care-items')),
    );
    return (json as List)
        .whereType<Map<String, dynamic>>()
        .map(CareItemEntry.tryParse)
        .whereType<CareItemEntry>()
        .toList();
  }

  /// 항목 하나 만들기 — 목록 **맨 뒤**에 놓인다.
  ///
  /// 이름은 1~20자, 아이콘은 고르는 목록의 값, 목표는 1~20 이거나 없음. 규칙 밖이면 서버가
  /// 400 이고 [FamilyFailureKind.invalid] 로 온다 — 화면이 "다시 시도" 를 그리면 안 되는
  /// 실패다(눌러도 영원히 같은 결과다).
  Future<CareItemEntry> createCareItem(int groupId,
      {required String name,
      required String icon,
      int? dogId,
      int? dailyTarget}) async {
    final json = await _send(
      () => _authed.postJson(
        Uri.parse('$baseUrl/api/groups/$groupId/care-items'),
        body: {
          'name': name,
          'icon': icon,
          if (dogId != null) 'dogId': dogId,
          if (dailyTarget != null) 'dailyTarget': dailyTarget,
        },
      ),
    );
    return _parsedItem(json);
  }

  /// 항목 하나 **전량 교체**.
  ///
  /// 부분 수정이 아니다 — 안 보낸 값은 **비워진다**. 그래야 "모든 아이" 로 되돌리거나 목표를
  /// 지울 수 있다(JSON 에서는 "안 보냄" 과 "비우려고 보냄" 이 둘 다 null 이라 구분이 안 된다).
  Future<CareItemEntry> replaceCareItem(int groupId, int itemId,
      {required String name,
      required String icon,
      int? dogId,
      int? dailyTarget,
      bool archived = false}) async {
    final json = await _send(
      () => _authed.putJson(
        Uri.parse('$baseUrl/api/groups/$groupId/care-items/$itemId'),
        body: {
          'name': name,
          'icon': icon,
          if (dogId != null) 'dogId': dogId,
          if (dailyTarget != null) 'dailyTarget': dailyTarget,
          'archived': archived,
        },
      ),
      notFoundIs: FamilyFailureKind.gone,
    );
    return _parsedItem(json);
  }

  /// 항목 **접기** — 지우는 것이 아니다. 카드에서 사라지고 기록은 그대로 남는다.
  ///
  /// 되살리기는 [replaceCareItem] 에 `archived: false` 다. 이미 접힌 것을 또 접어도 204 라
  /// 화면이 재시도를 걱정하지 않아도 된다.
  Future<void> archiveCareItem(int groupId, int itemId) async {
    await _send(
      () => _authed.deleteJson(
        Uri.parse('$baseUrl/api/groups/$groupId/care-items/$itemId'),
      ),
      notFoundIs: FamilyFailureKind.gone,
    );
  }

  /// 목록 순서 — **그 집 항목 전부**를 화면에 보이는 순서대로.
  ///
  /// 빠지거나 겹치면 서버가 400 이다([FamilyFailureKind.invalid]). 조용히 뒤에 붙이지 않는
  /// 이유는, 두 사람이 동시에 순서를 바꿨을 때 나중 요청이 먼저 요청의 새 항목을 맨 뒤로
  /// 보내기 때문이다 — 거절하면 화면이 목록을 다시 읽는다.
  Future<void> reorderCareItems(int groupId, List<int> itemIds) async {
    await _send(
      () => _authed.putJson(
        Uri.parse('$baseUrl/api/groups/$groupId/care-items/order'),
        body: {'itemIds': itemIds},
      ),
    );
  }

  CareItemEntry _parsedItem(Object? json) {
    final parsed = json is Map<String, dynamic>
        ? CareItemEntry.tryParse(json)
        : null;
    if (parsed == null) {
      throw const FamilyFailure(FamilyFailureKind.network, '응답을 읽지 못했어요');
    }
    return parsed;
  }

  /// 내가 남긴 케어 기록 하나를 지운다(#209). **본인 기록만** — 남의 것은 서버가 403 이라
  /// [FamilyFailureKind.forbidden] 이고, 벌써 지워졌거나 이 그룹에 없는 id 는 404 라
  /// [FamilyFailureKind.gone] 이다. 성공은 204 라 돌려줄 것이 없다.
  Future<void> deleteCareLog(int groupId, int careLogId) async {
    await _send(
      () => _authed.deleteJson(
        Uri.parse('$baseUrl/api/groups/$groupId/care-logs/$careLogId'),
      ),
      notFoundIs: FamilyFailureKind.gone,
    );
  }

  /// 초대코드를 하나 발급한다. **방장만** 부를 수 있고 아니면 403 이다.
  ///
  /// 경로가 `/api/groups` 가 아니라 `/api/chat/rooms/{roomId}/invites` 인 것은
  /// ADR-0011 때문이다 — 초대코드는 그룹이 아니라 **방**에 붙고 만료·사용횟수·회수를
  /// 가진다. `roomId` 는 [FamilyGroupSummary.roomId] 다.
  ///
  /// **발급할 때마다 새 코드가 생기고 이전 코드는 죽지 않는다**(#75 에서 실측으로 확인된
  /// 동작이다). 그래서 화면에서 "새 코드 발급" 을 유출 대응 버튼처럼 광고하면 안 된다.
  ///
  /// 코드만이 아니라 만료·횟수도 돌려준다 — 초대 시트가 그 **사실**로 말한다(#329).
  Future<FamilyInvite> issueInvite(int roomId) async {
    final json = await _send(
      () => _authed.postJson(Uri.parse('$baseUrl/api/chat/rooms/$roomId/invites')),
    );
    return FamilyInvite.fromJson(json as Map);
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
    } on TimeoutException {
      // **못 닿았다.** 부르는 쪽이 이걸 보고 다음 요청을 접을 수 있다(#573).
      throw FamilyFailure(
        FamilyFailureKind.timeout,
        FamilyFailure.messageFor(FamilyFailureKind.timeout),
      );
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
    // 204 는 본문이 없다 — 삭제가 그렇다. 위 분기로 보내면 빈 본문의 jsonDecode 가 죽는다.
    if (res.statusCode == 204) return null;

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
    // 400 만 **서버가 적은 문구**를 쓴다. 여기 박아 둔 문구는 메모 길이 이야기라, 케어
    // 항목을 고치다 거절당한 사람에게 "메모는 500자까지" 라고 말한다 — 화면과 원인이 서로
    // 다른 말을 하는 자리다(#560 에서 실측으로 봤다).
    //
    // 다른 코드에는 안 쓴다. 401·403·404 의 서버 문구는 "왜 막혔는지" 를 알려 주는 쪽이라
    // 그대로 보여 주면 id 를 훑어 남의 것을 세는 데 쓰인다(#209 가 404 를 합친 이유).
    throw FamilyFailure(
      kind,
      kind == FamilyFailureKind.invalid
          ? (_messageOf(res) ?? FamilyFailure.messageFor(kind))
          : FamilyFailure.messageFor(kind),
    );
  }

  /// 오류 본문의 {@code message}. 못 읽으면 {@code null} 이다 — 본문이 JSON 이 아닐 수도 있다.
  static String? _messageOf(http.Response res) {
    try {
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      final message = body is Map ? body['message'] : null;
      return message is String && message.trim().isNotEmpty ? message : null;
    } catch (_) {
      return null;
    }
  }
}

/// 발급된 초대 — 코드와 그 코드의 사실(만료·횟수). 서버 `ChatInviteView` 의 `code`·
/// `expiresAt`·`maxUses` 다. 화면은 이 값으로만 말한다(#329).
class FamilyInvite {
  final String code;

  /// 서버 시각(UTC). null 이면 만료 없음.
  final DateTime? expiresAt;

  /// null 이면 횟수 무제한.
  final int? maxUses;

  const FamilyInvite({required this.code, this.expiresAt, this.maxUses});

  factory FamilyInvite.fromJson(Map json) {
    final expires = json['expiresAt'];
    final uses = json['maxUses'];
    return FamilyInvite(
      code: '${json['code'] ?? ''}',
      expiresAt: expires is String ? DateTime.tryParse(expires) : null,
      maxUses: uses is num ? uses.toInt() : null,
    );
  }
}
