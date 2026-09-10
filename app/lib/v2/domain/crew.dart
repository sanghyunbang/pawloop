// 크루 하나 — 이슈 #417. 서버는 PR #426.
//
// ## 멤버십이 여기 없다
//
// `crew_member` 표가 없다. 크루의 멤버는 **그 크루 방의 멤버**이고, 그것은
// `chat_room_member` 다(ADR-0011). 그래서 이 도메인에는 "크루를 나간다" 와 "방을 나간다"
// 를 가르는 값이 없다 — 나갈 곳이 하나뿐이다.
//
// ## 방장도 필드가 아니라 답이다
//
// `owner` 는 저장된 값이 아니라 **그 방의 `OWNER` 멤버인가**를 서버가 읽어 준 답이다.
// 앱은 그것으로 고치기·강퇴 버튼을 그릴지만 정한다 — 권한은 서버가 다시 잰다.
import 'package:flutter/material.dart';

/// 누가 이 크루를 찾을 수 있나.
///
/// **기본은 [invite]** 다 — 처음부터 아무나 들어오면 관리가 안 된다. 동네 모임은 아는
/// 사람 몇으로 시작해서 열리는 것이지, 열어 놓고 사람을 거르는 것이 아니다.
enum CrewVisibility {
  invite('invite', '초대', '코드를 받은 사람만 들어옵니다'),
  public('public', '공개', '우리 동네 목록에 뜨고 누구나 들어옵니다');

  const CrewVisibility(this.wire, this.label, this.hint);

  final String wire;

  /// 화면 문구. 서버로 나가는 값은 [wire] 다.
  final String label;

  /// 만들기 시트가 고른 값 아래에 한 줄로 말해 주는 것.
  final String hint;

  bool get isPublic => this == CrewVisibility.public;

  /// 모르는 값이면 [invite] 다 — 서버가 값을 늘려도 화면이 안 깨진다. 좁은 쪽으로
  /// 떨어지는 것이 맞다: 모르는 것을 공개로 그리면 안 열린 모임이 열린 것처럼 보인다.
  static CrewVisibility parse(Object? value) {
    for (final v in values) {
      if (v.wire == value) return v;
    }
    return CrewVisibility.invite;
  }
}

/// 크루에 든 사람 하나.
@immutable
class CrewMember {
  final int userId;

  /// `users` 의 지금 닉네임. 탈퇴했으면 서버가 `알 수 없음` 을 준다.
  final String nickname;

  /// `OWNER` 또는 `MEMBER`. 서버가 주는 그대로 든다 — 화면 문구는 [isOwner] 로 만든다.
  final String role;

  const CrewMember({
    required this.userId,
    required this.nickname,
    required this.role,
  });

  bool get isOwner => role == 'OWNER';

  static CrewMember? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = json['userId'];
    if (id is! int) return null;
    return CrewMember(
      userId: id,
      nickname: '${json['nickname'] ?? '알 수 없음'}',
      role: '${json['role'] ?? 'MEMBER'}',
    );
  }
}

@immutable
class Crew {
  final int id;

  /// 이 크루의 대화방. **늘 함께 온다** — 화면이 방으로 가려고 한 번 더 묻지 않는다.
  final int roomId;

  final String name;
  final String? intro;

  /// 행정동 코드 열 자리. **좌표가 아니다**(#342 · A안 #235). 없을 수 있다.
  final String? neighborhoodCode;

  final CrewVisibility visibility;

  /// 방장이 정한 정원. 방의 정원(서비스 전체 상한)과 다른 숫자다.
  final int capacity;

  /// 지금 든 사람 수. 나간 사람·강퇴된 사람은 안 센다.
  final int memberCount;

  /// 내가 든 크루인가. 카드가 "참여" 와 "들어가기" 를 가르는 값이다.
  final bool mine;

  /// 내가 방장인가.
  final bool owner;

  /// **목록에서는 비어 있다** — 상세에서만 채워진다. 공개 크루를 안 든 사람이 볼 때도
  /// 비어 있다(인원 수까지가 공개다).
  final List<CrewMember> members;

  final DateTime? createdAt;

  const Crew({
    required this.id,
    required this.roomId,
    required this.name,
    required this.visibility,
    required this.capacity,
    required this.memberCount,
    required this.mine,
    required this.owner,
    this.intro,
    this.neighborhoodCode,
    this.members = const [],
    this.createdAt,
  });

  /// 자리가 남았는가. **[mine] 이면 물어볼 필요가 없다** — 이미 든 사람은 자리를 쓴다.
  bool get isFull => !mine && memberCount >= capacity;

  /// "12 / 20" 처럼 카드에 적을 한 줄.
  String get headcount => '$memberCount / $capacity';

  static Crew? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final roomId = json['roomId'];
    if (id is! int || roomId is! int) return null;

    return Crew(
      id: id,
      roomId: roomId,
      name: '${json['name'] ?? ''}',
      intro: _text(json['intro']),
      neighborhoodCode: _text(json['neighborhoodCode']),
      visibility: CrewVisibility.parse(json['visibility']),
      capacity: json['capacity'] is int ? json['capacity'] as int : 20,
      memberCount: json['memberCount'] is int ? json['memberCount'] as int : 0,
      mine: json['mine'] == true,
      owner: json['owner'] == true,
      members: [
        for (final raw in (json['members'] is List ? json['members'] as List : const []))
          if (CrewMember.tryParse(raw) case final m?) m,
      ],
      // 서버가 찍는 순간이라 오프셋이 붙어 온다 — 여기서 기기 시각으로 눕힌다.
      createdAt: DateTime.tryParse('${json['createdAt']}')?.toLocal(),
    );
  }

  static List<Crew> parseList(Object? json) {
    if (json is! List) return const [];
    return [
      for (final raw in json)
        if (Crew.tryParse(raw) case final crew?) crew,
    ];
  }

  /// 빈 문자열은 `null` 과 같다 — 화면이 "" 를 소개로 그리지 않게 한다.
  static String? _text(Object? value) {
    if (value == null) return null;
    final text = '$value'.trim();
    return text.isEmpty ? null : text;
  }
}
