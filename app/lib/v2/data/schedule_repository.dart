// 일정표 — 서버 왕복 (#419, 서버는 #418).
//
// ## 409 는 실패가 아니라 "값이 달라졌다" 다
//
// 가족 여럿이 같은 일정을 고친다. 뒤에 온 쪽이 409 를 받는데, 그 본문에는 **지금 서버에
// 있는 값**이 함께 온다. 그걸 버리고 "실패했어요" 로 뭉개면 화면이 한 번 더 물어야 하고
// 그 사이에 또 바뀔 수 있다 — 그래서 이 저장소는 409 를 최신 값을 **든** 실패로 던진다.
//
// ## version 은 쿼리로 간다
//
// `PATCH /api/schedules/{id}?version=3`. 본문이 아닌 이유는 부분 수정 본문에 필수 필드를
// 둘 수 없기 때문이다(ADR-0017 규약 4) — 자세한 것은 `docs/04-api/api-spec.md` §16.3.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/config/env.dart';
import '../../core/net/authed_client.dart';
import '../domain/schedule.dart';
import '../../core/net/net_timeouts.dart';

/// 일정을 못 다룬 이유. 화면이 그대로 말한다 — "실패했어요" 로 뭉개지 않는다.
enum ScheduleFailureKind {
  /// 남이 먼저 고쳤다. **[ScheduleFailure.current] 에 최신 값이 있다.**
  conflict,

  /// 내 아이·내 그룹이 아니거나 없다. 서버는 둘을 구분하지 않는다.
  notFound,

  /// 기간이 92일을 넘었거나, 아직 못 만드는 크루 일정이다.
  invalid,

  /// 연결이 없다. 다시 보내면 된다.
  network,
}

class ScheduleFailure implements Exception {
  final ScheduleFailureKind kind;

  /// 409 일 때만 채워진다 — 지금 서버에 있는 값.
  final Schedule? current;

  final String? message;

  const ScheduleFailure(this.kind, {this.current, this.message});

  @override
  String toString() => 'ScheduleFailure($kind, $message)';
}

class ScheduleRepository {
  static const Duration timeout = NetTimeouts.standard;

  /// 한 번에 볼 수 있는 최대 기간. 서버의 `ScheduleService.MAX_RANGE_DAYS` 와 같은 값이다.
  static const int maxRangeDays = 92;

  static const int maxTitleLength = 100;
  static const int maxMemoLength = 500;

  final String baseUrl;
  final AuthedClient _authed;

  ScheduleRepository({String? baseUrl, AuthedClient? client})
      : baseUrl = (baseUrl ?? Env.apiBase).replaceAll(RegExp(r'/+$'), ''),
        _authed = client ?? AuthedClient.instance;

  /// 기간 안의 일정.
  ///
  /// [ownerKind] 를 안 주면 **내가 볼 수 있는 전부**가 한 목록으로 온다 — 달력의 기본이
  /// 합쳐 보기라 화면이 두 번 부르지 않는다. [dogId] 는 그것과 **겹쳐 쓸 수 있다**.
  Future<List<Schedule>> range({
    required DateTime from,
    required DateTime to,
    ScheduleOwnerKind? ownerKind,
    int? ownerRef,
    int? dogId,
  }) async {
    final uri = Uri.parse('$baseUrl/api/schedules').replace(queryParameters: {
      'from': Schedule.formatDate(from),
      'to': Schedule.formatDate(to),
      if (ownerKind != null) 'ownerKind': ownerKind.wire,
      if (ownerRef != null) 'ownerRef': '$ownerRef',
      if (dogId != null) 'dogId': '$dogId',
    });
    return Schedule.parseList(await _send(() => _authed.getJson(uri)));
  }

  Future<Schedule> create({
    required ScheduleOwnerKind ownerKind,
    required int ownerRef,
    required ScheduleKind kind,
    required String title,
    required DateTime onDate,
    int? dogId,
    String? memo,
    TimeOfDay? atTime,
    int? assignee,
    ScheduleRepeat repeatKind = ScheduleRepeat.none,
    DateTime? repeatUntil,
  }) async {
    final json = await _send(() => _authed.postJson(
          Uri.parse('$baseUrl/api/schedules'),
          body: {
            'ownerKind': ownerKind.wire,
            'ownerRef': ownerRef,
            'kind': kind.wire,
            'title': title,
            'onDate': Schedule.formatDate(onDate),
            if (dogId != null) 'dogId': dogId,
            if (memo != null && memo.isNotEmpty) 'memo': memo,
            if (atTime != null) 'atTime': Schedule.formatTime(atTime),
            if (assignee != null) 'assignee': assignee,
            if (repeatKind.repeats) 'repeatKind': repeatKind.wire,
            if (repeatKind.repeats && repeatUntil != null)
              'repeatUntil': Schedule.formatDate(repeatUntil),
          },
        ));
    final schedule = Schedule.tryParse(json);
    if (schedule == null) throw const ScheduleFailure(ScheduleFailureKind.network);
    return schedule;
  }

  /// 고친다.
  ///
  /// **`memo`·`atTime`·`dogId`·`assignee` 는 안 보내면 비운다** — 그것이 서버의 계약이라
  /// 화면은 늘 전체를 보낸다. 그래서 이 메서드도 그 넷을 `null` 로 두면 지우는 뜻이다.
  ///
  /// [version] 이 서버의 것과 다르면 [ScheduleFailureKind.conflict] 이고
  /// [ScheduleFailure.current] 에 최신 값이 들어 있다.
  Future<Schedule> update({
    required int scheduleId,
    required int version,
    required ScheduleKind kind,
    required String title,
    required DateTime onDate,
    int? dogId,
    String? memo,
    TimeOfDay? atTime,
    int? assignee,
    ScheduleStatus? status,
    ScheduleRepeat? repeatKind,
    DateTime? repeatUntil,
    DateTime? onlyDay,
  }) async {
    final uri = Uri.parse('$baseUrl/api/schedules/$scheduleId').replace(queryParameters: {
      'version': '$version',
      if (onlyDay != null) 'date': Schedule.formatDate(onlyDay),
    });
    final json = await _send(() => _authed.patchJson(uri, body: {
          'kind': kind.wire,
          'title': title,
          'onDate': Schedule.formatDate(onDate),
          if (dogId != null) 'dogId': dogId,
          if (memo != null && memo.isNotEmpty) 'memo': memo,
          if (atTime != null) 'atTime': Schedule.formatTime(atTime),
          if (assignee != null) 'assignee': assignee,
          if (status != null) 'status': status.wire,
          if (repeatKind != null) 'repeatKind': repeatKind.wire,
          if (repeatKind != null && repeatKind.repeats && repeatUntil != null)
            'repeatUntil': Schedule.formatDate(repeatUntil),
        }));
    final schedule = Schedule.tryParse(json);
    if (schedule == null) throw const ScheduleFailure(ScheduleFailureKind.network);
    return schedule;
  }

  /// 완료·건너뜀 표시. 한 칸만 바꾸지만 계약이 부분 수정이라 나머지도 함께 보낸다.
  /// 완료·건너뜀 표시. 한 칸만 바꾸지만 계약이 부분 수정이라 나머지도 함께 보낸다.
  ///
  /// **펼쳐 낸 하루면 그 하루만** 바꾼다(`?date=`, #421) — 서버가 그때 행을 만든다. 안
  /// 그러면 한 번 먹였다고 앞으로 오는 날이 전부 완료된다.
  Future<Schedule> mark(Schedule schedule, ScheduleStatus next) => update(
        scheduleId: schedule.id,
        version: schedule.version,
        kind: schedule.kind,
        title: schedule.title,
        onDate: schedule.onDate,
        dogId: schedule.dogId,
        memo: schedule.memo,
        atTime: schedule.atTime,
        assignee: schedule.assignee?.userId,
        status: next,
        onlyDay: schedule.occurrence ? schedule.onDate : null,
      );

  /// 지운다.
  ///
  /// [onlyDay] 를 주면 **그 하루만 건너뛴다**(#421) — 규칙은 그대로다. "이번 주만 안 함"
  /// 이 반복을 지우는 일이 되면 안 된다.
  Future<void> delete(int scheduleId, {DateTime? onlyDay}) async {
    final uri = Uri.parse('$baseUrl/api/schedules/$scheduleId').replace(
        queryParameters:
            onlyDay == null ? null : {'date': Schedule.formatDate(onlyDay)});
    await _send(() => _authed.deleteJson(uri));
  }

  /// 한 번의 왕복. **상태 코드를 실패의 종류로 옮기는 곳이 여기 하나다.**
  Future<Object?> _send(Future<http.Response> Function() request) async {
    final http.Response res;
    try {
      res = await request().timeout(timeout);
    } catch (_) {
      throw const ScheduleFailure(ScheduleFailureKind.network);
    }

    if (res.statusCode == 409) {
      final body = _decode(res.bodyBytes);
      throw ScheduleFailure(
        ScheduleFailureKind.conflict,
        // 최신 값이 없으면 `null` 이다 — 화면이 "다시 불러오기" 로 떨어진다.
        current: body is Map ? Schedule.tryParse(body['current']) : null,
        message: _messageOf(body),
      );
    }
    if (res.statusCode == 404) throw const ScheduleFailure(ScheduleFailureKind.notFound);
    if (res.statusCode == 400) {
      throw ScheduleFailure(ScheduleFailureKind.invalid,
          message: _messageOf(_decode(res.bodyBytes)));
    }
    if (res.statusCode >= 400) throw const ScheduleFailure(ScheduleFailureKind.network);
    if (res.bodyBytes.isEmpty) return null;
    return _decode(res.bodyBytes);
  }

  static Object? _decode(List<int> bodyBytes) {
    if (bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(bodyBytes));
    } catch (_) {
      return null;
    }
  }

  static String? _messageOf(Object? body) {
    if (body is Map && body['error'] is Map) {
      return (body['error'] as Map)['message'] as String?;
    }
    // 본문이 계약과 다르면 이유를 모르는 것이다 — 지어내지 않는다.
    return null;
  }
}
