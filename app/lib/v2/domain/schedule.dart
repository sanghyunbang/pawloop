// 일정 하나 — 이슈 #419, 서버는 #418.
//
// ## 날짜와 시각은 시간대를 안 지난다
//
// `onDate` 와 `atTime` 은 **사람이 고른 벽시계**다. "10월 3일 10시 30분 병원" 은 어느
// 시간대에서 보든 그 날 그 시각이라, `DateTime.parse(...).toLocal()` 을 태우면 안 된다 —
// 태우면 밤 일정이 하루 넘어가고 달력이 다른 칸에 그린다. 서버도 같은 이유로 이 둘만
// UTC 로 안 눕힌다(`ScheduleTime` javadoc).
//
// 반대로 `updatedAt` 은 **서버가 찍는 순간**이라 오프셋이 붙어 오고, 여기서 `toLocal()`
// 한다. 두 종류를 한 파일에서 다르게 다루는 것이 헷갈릴 수 있어 여기 적어 둔다.
import 'package:flutter/material.dart';

/// 일정의 주인. `chat_room` 과 같은 방식의 불투명한 쌍이다(ADR-0011).
enum ScheduleOwnerKind {
  dog('dog'),
  group('group'),

  /// 크루(#417). **서버가 아직 400 으로 거절한다** — 값만 열려 있다.
  room('room');

  const ScheduleOwnerKind(this.wire);

  final String wire;

  static ScheduleOwnerKind? tryParse(Object? value) {
    for (final k in values) {
      if (k.wire == value) return k;
    }
    return null;
  }
}

/// 일정의 종류. `wire` 는 DB 의 `CHECK` 가 받는 문자열과 글자까지 같다.
enum ScheduleKind {
  walk('walk', '산책', Icons.directions_walk_rounded, Color(0xFF7FC8A9)),
  vet('vet', '병원', Icons.local_hospital_outlined, Color(0xFFFF8FA3)),
  med('med', '투약', Icons.medication_outlined, Color(0xFFFFB86B)),
  groom('groom', '미용', Icons.content_cut_rounded, Color(0xFFB79BFF)),
  bath('bath', '목욕', Icons.shower_outlined, Color(0xFF7FB3FF)),
  food('food', '사료', Icons.restaurant_rounded, Color(0xFFE0B27A)),
  etc('etc', '그 밖', Icons.event_note_outlined, Color(0xFF9B93B3));

  const ScheduleKind(this.wire, this.label, this.icon, this.color);

  final String wire;
  final String label;
  final IconData icon;
  final Color color;

  /// 모르는 값은 `etc` 다. 서버가 종류를 늘렸을 때 그 줄만 안 보이는 것보다 낫다 —
  /// 안 보이면 사람은 자기가 적은 일정이 사라졌다고 읽는다.
  static ScheduleKind parse(Object? value) {
    for (final k in values) {
      if (k.wire == value) return k;
    }
    return ScheduleKind.etc;
  }
}

enum ScheduleStatus {
  planned('planned'),
  done('done'),

  /// 건너뛴 것은 지운 것과 다르다 — 약을 안 먹인 날이 달력에 남아야 다음에 그것을 본다.
  skipped('skipped');

  const ScheduleStatus(this.wire);

  final String wire;

  bool get isOpen => this == ScheduleStatus.planned;

  static ScheduleStatus parse(Object? value) {
    for (final s in values) {
      if (s.wire == value) return s;
    }
    return ScheduleStatus.planned;
  }
}

/// 사람 한 명 — 계약의 `SchedulePerson`.
class SchedulePerson {
  final int userId;
  final String nickname;

  const SchedulePerson({required this.userId, required this.nickname});

  static SchedulePerson? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = json['userId'];
    final nickname = json['nickname'];
    if (id is! int || nickname is! String) return null;
    return SchedulePerson(userId: id, nickname: nickname);
  }
}

/// 앞으로 할 일 하나 — 계약의 `Schedule`.
class Schedule {
  final int id;
  final ScheduleOwnerKind ownerKind;
  final int ownerRef;

  /// 어느 아이 것인가. **`ownerRef` 와 별개다** — "가족 소유인데 보리 것".
  final int? dogId;

  final ScheduleKind kind;
  final String title;
  final String? memo;

  /// **날짜만** 든다. 시:분:초는 늘 0 이고 시간대 변환을 안 지났다.
  final DateTime onDate;

  /// `null` 이면 **"하루 종일"** 이다. 0시로 채우지 않는다.
  final TimeOfDay? atTime;

  final SchedulePerson? assignee;
  final ScheduleStatus status;

  /// 고칠 때 그대로 되돌려 보내야 하는 값. 다르면 서버가 409 를 준다.
  final int version;

  final SchedulePerson? updatedBy;

  /// 서버가 찍은 순간이라 오프셋이 붙어 오고, 여기서 기기 시각으로 눕힌다.
  final DateTime? updatedAt;

  const Schedule({
    required this.id,
    required this.ownerKind,
    required this.ownerRef,
    required this.kind,
    required this.title,
    required this.onDate,
    required this.status,
    required this.version,
    this.dogId,
    this.memo,
    this.atTime,
    this.assignee,
    this.updatedBy,
    this.updatedAt,
  });

  bool get isAllDay => atTime == null;

  /// 같은 날인가. 달력이 칸마다 묻는 것이라 여기 한 번만 적는다.
  bool isOn(DateTime day) =>
      onDate.year == day.year && onDate.month == day.month && onDate.day == day.day;

  /// 모양이 다르면 `null` — 하나가 이상하다고 그 달 전체를 잃지 않는다.
  static Schedule? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final title = json['title'];
    final ownerKind = ScheduleOwnerKind.tryParse(json['ownerKind']);
    final ownerRef = json['ownerRef'];
    final onDate = parseDate(json['onDate']);
    if (id is! int || title is! String || ownerKind == null || ownerRef is! int ||
        onDate == null) {
      return null;
    }
    return Schedule(
      id: id,
      ownerKind: ownerKind,
      ownerRef: ownerRef,
      dogId: (json['dogId'] as num?)?.toInt(),
      kind: ScheduleKind.parse(json['kind']),
      title: title,
      memo: json['memo'] as String?,
      onDate: onDate,
      atTime: parseTime(json['atTime']),
      assignee: SchedulePerson.tryParse(json['assignee']),
      status: ScheduleStatus.parse(json['status']),
      version: (json['version'] as num?)?.toInt() ?? 0,
      updatedBy: SchedulePerson.tryParse(json['updatedBy']),
      updatedAt: DateTime.tryParse('${json['updatedAt']}')?.toLocal(),
    );
  }

  static List<Schedule> parseList(Object? json) {
    if (json is! List) return const [];
    return json.map(Schedule.tryParse).whereType<Schedule>().toList();
  }

  /// `2026-10-03` → 그 날. **문자열의 날짜 부분만 읽는다.**
  ///
  /// 서버는 지금 날짜만 보낸다(계약이 `format: date` 다). 그래도 손으로 읽는 이유는,
  /// 언젠가 오프셋 붙은 문자열이 오면 `DateTime.parse(...).toLocal()` 이 **그 지역에서
  /// 하루를 넘길 수 있기** 때문이다 — 서울에서 `2026-10-03T20:00:00Z` 는 10월 4일이다.
  /// 달력이 통째로 하루 밀리는데 오류는 안 난다.
  ///
  /// (Dart 의 `DateTime.parse` 는 오프셋 **없는** 문자열을 지역 시각으로 읽는다 —
  /// JavaScript 와 다르다. 그래서 지금 오는 값만으로는 둘이 같은 답을 낸다.)
  static DateTime? parseDate(Object? value) {
    if (value is! String) return null;
    final parts = value.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2].substring(0, parts[2].length.clamp(0, 2)));
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  /// `10:30` 또는 `10:30:00`. 비면 "하루 종일" 이라 `null` 이다.
  static TimeOfDay? parseTime(Object? value) {
    if (value is! String || value.isEmpty) return null;
    final parts = value.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  /// 서버가 받는 `2026-10-03`.
  static String formatDate(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  /// 서버가 받는 `10:30`. 화면에 그리는 것도 같은 모양이다.
  static String formatTime(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  /// 날짜 → 시각 → id. **시각 없는 것("하루 종일")이 그날의 뒤**다.
  ///
  /// 서버가 이미 이 순서로 주지만 앱도 안다 — 만든 일정을 목록에 끼워 넣을 때
  /// 다시 부르지 않고 제자리에 넣기 위해서다.
  static int compare(Schedule a, Schedule b) {
    final date = a.onDate.compareTo(b.onDate);
    if (date != 0) return date;
    if (a.atTime == null || b.atTime == null) {
      if (a.atTime == null && b.atTime == null) return a.id.compareTo(b.id);
      return a.atTime == null ? 1 : -1;
    }
    final minutes = (a.atTime!.hour * 60 + a.atTime!.minute)
        .compareTo(b.atTime!.hour * 60 + b.atTime!.minute);
    return minutes != 0 ? minutes : a.id.compareTo(b.id);
  }
}
