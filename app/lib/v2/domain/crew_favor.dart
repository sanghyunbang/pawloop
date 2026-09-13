// 품앗이 한 건 — 이슈 #417. 서버는 PR #428.
//
// ## 돈이 안 붙는다
//
// 결제·평점·보증·중개는 없다 — 이슈가 그은 선이다. 돈이 오가면 우리가 중개자가 되고, 사고가
// 나면 배상 책임과 신고 의무가 따라온다. 그래서 이 값에는 금액도 평점도 후기도 없다. 여기서
// 하는 일은 **약속을 적는 것**까지고, 몇 시에 어디서 만날지는 크루 대화방에서 정한다.
//
// ## 시각이 아니라 시간대다
//
// 부탁은 "12/24 **오후**, 보리 두 시간만" 이지 "14시 00분" 이 아니다. 시각을 받으면 부탁하는
// 사람이 없는 정밀도를 지어내고, 맡는 사람은 그 시각에 묶인다.
//
// ## 상태가 둘뿐이다
//
// `open`·`taken`. "끝났다" 는 **일정이 안다** — 맡으면 생기는 크루 일정의 완료 표시다. 여기에
// 또 두면 같은 사실이 두 곳에 살고 한쪽만 고쳐진다. "취소됨" 도 없다 — 거둬들이면 행이
// 사라지므로 목록에서 그냥 빠진다.
import 'package:flutter/foundation.dart';

import 'pet.dart' show kWeekDayLabels;
import 'schedule.dart' show Schedule;

/// 시간대. 화면 문구는 [label], 서버로 나가는 값은 [wire] 다 — 서버의 `CrewFavorSlot` 과 같다.
enum CrewFavorSlot {
  morning('morning', '오전'),
  afternoon('afternoon', '오후'),
  evening('evening', '저녁');

  const CrewFavorSlot(this.wire, this.label);

  final String wire;
  final String label;

  /// 모르는 값이면 `null` 이다 — 셋 중 하나로 **대신 그리지 않는다.** 시간대가 틀린 약속은
  /// 없는 약속보다 나쁘다: 오전에 오기로 한 사람이 저녁에 온다.
  static CrewFavorSlot? tryParse(Object? value) {
    for (final s in values) {
      if (s.wire == value) return s;
    }
    return null;
  }
}

enum CrewFavorStatus {
  open('open'),
  taken('taken');

  const CrewFavorStatus(this.wire);

  final String wire;

  /// 모르는 값은 [taken] 이다 — 좁은 쪽으로. 모르는 것을 열린 것으로 그리면 "제가 할게요" 가
  /// 뜨고 서버가 거절한다. (`CrewVisibility.parse` 가 초대로 떨어지는 것과 같은 판단이다.)
  static CrewFavorStatus parse(Object? value) {
    for (final s in values) {
      if (s.wire == value) return s;
    }
    return CrewFavorStatus.taken;
  }
}

/// 크루에서 사람 하나를 가리키는 최소한 — 계약의 `CrewPerson`.
///
/// `CrewMember` 와 다르다 — 거기에는 역할이 있고 여기에는 없다. 부탁에 적히는 것은 "누가"
/// 이지 "방장인가" 가 아니다.
@immutable
class CrewPerson {
  final int userId;

  /// `users` 의 지금 닉네임. 탈퇴했으면 서버가 `알 수 없음` 을 준다.
  final String nickname;

  const CrewPerson({required this.userId, required this.nickname});

  static CrewPerson? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = json['userId'];
    if (id is! int) return null;
    return CrewPerson(userId: id, nickname: '${json['nickname'] ?? '알 수 없음'}');
  }
}

/// 부탁에 걸린 아이 — **id 와 이름뿐**이다. 품종·나이는 안 온다: 카드가 말해야 하는 것은
/// "누구를 맡기나" 이고, 그 이상은 남의 아이 정보를 크루 전체에 흘리는 것이다.
@immutable
class CrewFavorPet {
  final int dogId;
  final String name;

  const CrewFavorPet({required this.dogId, required this.name});

  static CrewFavorPet? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = json['dogId'];
    if (id is! int) return null;
    return CrewFavorPet(dogId: id, name: '${json['name'] ?? ''}');
  }
}

@immutable
class CrewFavor {
  final int id;

  /// 사람이 고른 날짜. **시:분:초는 0 이고 시간대 변환을 안 지났다** — `Schedule.onDate`
  /// 와 같은 규약이라 읽는 것도 같은 손([Schedule.parseDate])으로 읽는다.
  final DateTime onDate;

  final CrewFavorSlot slot;

  /// "두 시간만 부탁드려요". 없으면 `null` — 빈 문자열을 그리지 않는다.
  final String? note;

  final CrewFavorStatus status;

  /// 부탁한 사람. 탈퇴했으면 `null` 이다.
  final CrewPerson? askedBy;

  /// 맡은 사람. 아직 아무도 안 맡았으면 `null` 이다.
  final CrewPerson? takenBy;

  /// 어느 아이를 맡기나. 없어도 된다 — 아이를 아직 등록 안 한 사람도 부탁할 수 있다.
  final CrewFavorPet? dog;

  /// 내가 올린 부탁인가. **거둬들이기 버튼을 그릴지** 정한다.
  final bool mine;

  /// 내가 맡은 것인가. "제가 할게요" 와 "무르기" 를 가른다.
  final bool takenByMe;

  /// 맡으면 생기는 **크루 소유 일정**의 id. 안 맡았으면 `null` 이다.
  final int? scheduleId;

  final DateTime? createdAt;

  const CrewFavor({
    required this.id,
    required this.onDate,
    required this.slot,
    required this.status,
    required this.mine,
    required this.takenByMe,
    this.note,
    this.askedBy,
    this.takenBy,
    this.dog,
    this.scheduleId,
    this.createdAt,
  });

  bool get isOpen => status == CrewFavorStatus.open;

  /// "9월 20일 (일) 오후" — 카드의 첫 줄. 부탁을 한눈에 가르는 것은 제목이 아니라 **언제**다.
  String get whenLabel => '${dayLabel(onDate)} ${slot.label}';

  /// "보리 · 두 시간만 부탁드려요". 아이도 한 줄도 없으면 `null` — 빈 줄을 안 그린다.
  String? get detailLabel {
    final parts = [
      if (dog case final pet?) pet.name,
      if (note case final text?) text,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// "9월 20일 (일)". 요일 글자는 [kWeekDayLabels] 다 — 달력과 같은 글자다.
  static String dayLabel(DateTime day) =>
      '${day.month}월 ${day.day}일 (${kWeekDayLabels[day.weekday - 1]})';

  /// 모양이 다르면 `null` — 하나가 이상하다고 목록 전체를 잃지 않는다.
  static CrewFavor? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final onDate = Schedule.parseDate(json['onDate']);
    final slot = CrewFavorSlot.tryParse(json['slot']);
    if (id is! int || onDate == null || slot == null) return null;
    final note = json['note'];
    final scheduleId = json['scheduleId'];
    return CrewFavor(
      id: id,
      onDate: onDate,
      slot: slot,
      note: note is String && note.trim().isNotEmpty ? note.trim() : null,
      status: CrewFavorStatus.parse(json['status']),
      askedBy: CrewPerson.tryParse(json['askedBy']),
      takenBy: CrewPerson.tryParse(json['takenBy']),
      dog: CrewFavorPet.tryParse(json['dog']),
      mine: json['mine'] == true,
      takenByMe: json['takenByMe'] == true,
      scheduleId: scheduleId is int ? scheduleId : null,
      // 서버가 찍는 순간이라 오프셋이 붙어 온다 — 기기 시각으로 눕힌다.
      createdAt: DateTime.tryParse('${json['createdAt']}')?.toLocal(),
    );
  }

  static List<CrewFavor> parseList(Object? json) {
    if (json is! List) return const [];
    return [
      for (final raw in json)
        if (CrewFavor.tryParse(raw) case final favor?) favor,
    ];
  }

  /// 날짜 → id. 서버가 이 순서로 주지만 앱도 안다 — 올린 부탁을 목록에 끼워 넣을 때 쓴다.
  static int compare(CrewFavor a, CrewFavor b) {
    final byDate = a.onDate.compareTo(b.onDate);
    return byDate != 0 ? byDate : a.id.compareTo(b.id);
  }
}
