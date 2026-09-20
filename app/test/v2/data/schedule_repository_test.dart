// 일정표 저장소 — **왕복의 모양**을 잠근다 (이슈 #419, 서버는 #418).
//
// ## 여기서 가장 중요한 것
//
// **409 를 실패로 뭉개지 않는 것**이다. 서버는 편집 충돌에 최신 값을 함께 실어 보내는데,
// 그걸 버리면 화면이 한 번 더 물어야 하고 그 사이에 또 바뀐다. 그리고 그 본문은 평범한
// 오류 봉투가 **아니라** `{error, current}` 라, 일반적인 오류 파서로는 안 읽힌다.
//
// 그다음이 **날짜를 시간대에 태우지 않는 것**이다. `onDate` 는 사람이 고른 벽시계라
// `DateTime.parse(...).toLocal()` 을 태우면 안 된다 — 오프셋 붙은 문자열이 오는 날
// 서울에서 `2026-10-03T20:00:00Z` 가 **10월 4일**이 되고, 달력이 통째로 하루 밀리는데
// 오류는 안 난다.
//
// (Dart 의 `DateTime.parse` 는 오프셋 **없는** 문자열을 지역 시각으로 읽는다 — JavaScript
// 와 다르다. 그래서 지금 서버가 보내는 `2026-10-03` 만으로 재면 되돌려도 초록이다.
// #419 에서 실측했고, 그래서 아래 "날짜 부분만 읽는다" 가 오프셋 붙은 값으로 잰다.)
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/schedule_repository.dart';
import 'package:heat_trip_flutter/v2/domain/schedule.dart';

const _base = 'https://api.example.test';

class _FakeTokenStore implements AuthTokenStore {
  @override
  Future<String?> readAccessToken() async => 'access-token';

  @override
  Future<String?> readRefreshToken() async => 'refresh-token';

  @override
  Future<void> saveTokens({required String accessToken, String? refreshToken}) async {}

  @override
  Future<void> clear() async {}
}

http.Response _json(Object body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, Object?> _schedule({
  int id = 5,
  String kind = 'vet',
  String title = '보리 병원',
  String onDate = '2026-10-03',
  Object? atTime = '10:30:00',
  int version = 0,
  String status = 'planned',
  Object? assignee,
  Object? updatedBy,
}) =>
    {
      'id': id,
      'ownerKind': 'group',
      'ownerRef': 3,
      'dogId': 7,
      'kind': kind,
      'title': title,
      'memo': '광견병 접종',
      'onDate': onDate,
      'atTime': atTime,
      'assignee': assignee,
      'status': status,
      'doneAt': null,
      'version': version,
      'updatedBy': updatedBy,
      'updatedAt': '2026-10-01T05:20:00Z',
    };

({ScheduleRepository repo, List<http.Request> sent}) fixture(
    Future<http.Response> Function(http.Request request) handler) {
  final sent = <http.Request>[];
  final client = AuthedClient(
    inner: MockClient((request) async {
      sent.add(request);
      return handler(request);
    }),
    baseUrl: _base,
    store: _FakeTokenStore(),
  );
  return (repo: ScheduleRepository(baseUrl: _base, client: client), sent: sent);
}

void main() {
  group('기간 조회', () {
    test('from·to 를 날짜로 보내고, 주인을 안 주면 아무 필터도 안 붙는다', () async {
      final f = fixture((_) async => _json([_schedule()]));

      await f.repo.range(from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 31));

      final q = f.sent.single.url.queryParameters;
      expect(q['from'], '2026-10-01');
      expect(q['to'], '2026-10-31');
      expect(q.containsKey('ownerKind'), isFalse,
          reason: '주인을 안 주면 서버가 내가 볼 수 있는 전부를 준다 — 달력의 기본이 합쳐 보기다');
      expect(q.containsKey('dogId'), isFalse);
    });

    test('아이 필터는 주인과 겹쳐 쓸 수 있다 — "우리 가족 일정 중 보리 것"', () async {
      final f = fixture((_) async => _json(const []));

      await f.repo.range(
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 31),
        ownerKind: ScheduleOwnerKind.group,
        ownerRef: 3,
        dogId: 7,
      );

      final q = f.sent.single.url.queryParameters;
      expect(q['ownerKind'], 'group');
      expect(q['ownerRef'], '3');
      expect(q['dogId'], '7');
    });

    test('한 줄이 이상해도 나머지는 산다 — 그 달 전체를 잃지 않는다', () async {
      final f = fixture((_) async => _json([
            _schedule(id: 1),
            {'id': 2}, // 제목도 날짜도 없다
            _schedule(id: 3, title: '심장사상충'),
          ]));

      final items =
          await f.repo.range(from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 31));

      expect(items.map((s) => s.id), [1, 3]);
    });
  });

  group('날짜와 시각', () {
    test('onDate 가 시간대를 안 지난다 — KST 에서 하루 밀리면 달력이 통째로 어긋난다', () async {
      final f = fixture((_) async => _json([_schedule(onDate: '2026-10-03')]));

      final s = (await f.repo.range(from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 31)))
          .single;

      expect(s.onDate, DateTime(2026, 10, 3));
    });

    test('날짜 부분만 읽는다 — 오프셋이 붙어 와도 그 날이다', () {
      // 이 단언이 **시간대에 안 흔들린다**: 값을 통째로 비교하므로, 어느 지역에서 돌려도
      // `DateTime.parse(...).toLocal()` 로 되돌리면 시:분이 남아 빨간불이 된다.
      //
      // (`DateTime.parse('2026-10-03')` 만 두고 재면 안 된다 — Dart 는 오프셋 없는
      // 문자열을 지역 시각으로 읽으므로 되돌려도 초록이다. #419 에서 실측했다.)
      expect(Schedule.parseDate('2026-10-03T20:00:00Z'), DateTime(2026, 10, 3),
          reason: '서울에서 그 순간은 10월 4일이다 — 달력이 통째로 하루 밀린다');
    });

    test('atTime 이 null 이면 하루 종일이다 — 0시로 채우지 않는다', () async {
      final f = fixture((_) async => _json([_schedule(atTime: null)]));

      final s = (await f.repo.range(from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 31)))
          .single;

      expect(s.atTime, isNull);
      expect(s.isAllDay, isTrue);
    });

    test('만들 때 시각을 안 주면 atTime 을 아예 안 보낸다', () async {
      final f = fixture((_) async => _json(_schedule(atTime: null), status: 201));

      await f.repo.create(
        ownerKind: ScheduleOwnerKind.dog,
        ownerRef: 7,
        kind: ScheduleKind.bath,
        title: '이번 주말 목욕',
        onDate: DateTime(2026, 10, 4),
      );

      final body = jsonDecode(f.sent.single.body) as Map;
      expect(body.containsKey('atTime'), isFalse,
          reason: '"00:00" 을 보내면 서버에 사용자가 안 정한 시각이 저장된다');
      expect(body['onDate'], '2026-10-04');
    });
  });

  group('편집 충돌', () {
    test('409 는 최신 값을 든 실패다 — 봉투를 읽되 current 를 버리지 않는다', () async {
      final f = fixture((_) async => _json({
            'error': {'code': 'CONFLICT', 'message': '다른 사람이 먼저 고쳤습니다.'},
            'current': _schedule(
              atTime: '14:00:00',
              version: 1,
              updatedBy: {'userId': 11, 'nickname': '아빠'},
            ),
          }, status: 409));

      await expectLater(
        f.repo.update(
          scheduleId: 5,
          version: 0,
          kind: ScheduleKind.vet,
          title: '보리 병원',
          onDate: DateTime(2026, 10, 3),
        ),
        throwsA(isA<ScheduleFailure>()
            .having((e) => e.kind, 'kind', ScheduleFailureKind.conflict)
            .having((e) => e.current?.version, 'current.version', 1)
            .having((e) => e.current?.atTime, 'current.atTime',
                const TimeOfDay(hour: 14, minute: 0))
            .having((e) => e.current?.updatedBy?.nickname, '누가 고쳤나', '아빠')),
      );
    });

    test('version 은 쿼리로 간다 — 부분 수정 본문에는 필수 필드를 둘 수 없다', () async {
      final f = fixture((_) async => _json(_schedule(version: 1)));

      await f.repo.update(
        scheduleId: 5,
        version: 3,
        kind: ScheduleKind.vet,
        title: '보리 병원',
        onDate: DateTime(2026, 10, 3),
      );

      final request = f.sent.single;
      expect(request.method, 'PATCH');
      expect(request.url.queryParameters['version'], '3');
      expect(jsonDecode(request.body), isNot(contains('version')));
    });

    test('최신 값이 안 오면 current 가 null 이다 — 지어내지 않는다', () async {
      final f = fixture((_) async => _json({'error': {'code': 'CONFLICT'}}, status: 409));

      await expectLater(
        f.repo.update(
            scheduleId: 5,
            version: 0,
            kind: ScheduleKind.vet,
            title: 'x',
            onDate: DateTime(2026, 10, 3)),
        throwsA(isA<ScheduleFailure>().having((e) => e.current, 'current', isNull)),
      );
    });
  });

  group('실패 나누기', () {
    test('404 는 notFound — 남의 것과 없는 것을 서버가 구분하지 않는다', () async {
      final f = fixture((_) async => _json({'error': {}}, status: 404));

      await expectLater(
        f.repo.delete(5),
        throwsA(isA<ScheduleFailure>()
            .having((e) => e.kind, 'kind', ScheduleFailureKind.notFound)),
      );
    });

    test('401 은 unauthorized — 다시 보내면 되는 것이 아니라 로그인이 답이다 (#680)', () async {
      // 갱신(`/auth/token/refresh`)까지 401 이라 AuthedClient 가 세션을 끝낸 뒤의 401 이다.
      final f = fixture((_) async => http.Response('', 401));

      await expectLater(
        f.repo.range(from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 31)),
        throwsA(isA<ScheduleFailure>()
            .having((e) => e.kind, 'kind', ScheduleFailureKind.unauthorized)),
      );
    });

    test('403 은 forbidden — 이것도 "다시 시도" 로 풀리지 않는다 (#680)', () async {
      final f = fixture((_) async => _json({
            'error': {'code': 'FORBIDDEN', 'message': '권한이 없습니다.'}
          }, status: 403));

      await expectLater(
        f.repo.delete(5),
        throwsA(isA<ScheduleFailure>()
            .having((e) => e.kind, 'kind', ScheduleFailureKind.forbidden)),
      );
    });

    test('401·403 의 화면 문구 — 일정 탭과 홈의 케어 카드가 같은 말을 한다 (#741 · #680)', () {
      expect(const ScheduleFailure(ScheduleFailureKind.unauthorized).userMessage,
          '로그인이 필요해요.');
      expect(const ScheduleFailure(ScheduleFailureKind.forbidden).userMessage,
          '이 일정은 고칠 수 없어요.');
    });

    test('400 은 이유를 그대로 옮긴다 — "실패했어요" 로 뭉개지 않는다', () async {
      final f = fixture((_) async => _json({
            'error': {'code': 'VALIDATION', 'message': '크루 일정은 아직 만들 수 없습니다.'}
          }, status: 400));

      await expectLater(
        f.repo.create(
            ownerKind: ScheduleOwnerKind.room,
            ownerRef: 1,
            kind: ScheduleKind.walk,
            title: '합동 산책',
            onDate: DateTime(2026, 10, 10)),
        throwsA(isA<ScheduleFailure>()
            .having((e) => e.kind, 'kind', ScheduleFailureKind.invalid)
            .having((e) => e.message, 'message', '크루 일정은 아직 만들 수 없습니다.')),
      );
    });
  });

  group('정렬', () {
    test('날짜 → 시각 → id 이고, 하루 종일은 그날의 뒤다', () {
      Schedule at(int id, String date, String? time) => Schedule.tryParse(
          _schedule(id: id, onDate: date, atTime: time))!;

      final list = [
        at(3, '2026-10-03', null),
        at(1, '2026-10-03', '14:00'),
        at(2, '2026-10-01', null),
        at(4, '2026-10-03', '09:00'),
      ]..sort(Schedule.compare);

      expect(list.map((s) => s.id), [2, 4, 1, 3]);
    });
  });

group('반복 (#421)', () {
    test('반복을 안 주면 아무것도 안 보낸다 — 서버 기본이 none 이다', () async {
      final f = fixture((_) async => _json(_schedule(), status: 201));

      await f.repo.create(
        ownerKind: ScheduleOwnerKind.group,
        ownerRef: 3,
        kind: ScheduleKind.vet,
        title: '보리 병원',
        onDate: DateTime(2026, 12, 1),
      );

      final body = jsonDecode(f.sent.single.body) as Map;
      expect(body.containsKey('repeatKind'), isFalse);
      expect(body.containsKey('repeatUntil'), isFalse);
    });

    test('종료일은 반복이 켜져 있을 때만 간다 — 안 그러면 서버가 안 쓰는 값이 오간다', () async {
      final f = fixture((_) async => _json(_schedule(), status: 201));

      await f.repo.create(
        ownerKind: ScheduleOwnerKind.group,
        ownerRef: 3,
        kind: ScheduleKind.bath,
        title: '목욕',
        onDate: DateTime(2026, 12, 1),
        repeatKind: ScheduleRepeat.none,
        repeatUntil: DateTime(2026, 12, 31),
      );

      final body = jsonDecode(f.sent.single.body) as Map;
      expect(body.containsKey('repeatUntil'), isFalse);
    });

    test('펼친 하루를 완료하면 그 하루만 — ?date= 가 붙는다', () async {
      final f = fixture((_) async => _json(_schedule()));
      final occurrence = Schedule.tryParse({
        ..._schedule(id: 5, onDate: '2026-12-08'),
        'repeatKind': 'weekly',
        'occurrence': true,
      })!;

      await f.repo.mark(occurrence, ScheduleStatus.done);

      final request = f.sent.single;
      expect(request.url.queryParameters['date'], '2026-12-08',
          reason: '안 붙이면 한 번 먹였다고 앞으로 오는 날이 전부 완료된다');
    });

    test('평범한 일정을 완료하면 ?date= 가 없다', () async {
      final f = fixture((_) async => _json(_schedule()));
      final plain = Schedule.tryParse(_schedule(id: 5))!;

      await f.repo.mark(plain, ScheduleStatus.done);

      expect(f.sent.single.url.queryParameters.containsKey('date'), isFalse);
    });

    test('하루만 건너뛰기는 DELETE 에 ?date= 를 붙인다', () async {
      final f = fixture((_) async => http.Response('', 204));

      await f.repo.delete(5, onlyDay: DateTime(2026, 12, 15));

      final request = f.sent.single;
      expect(request.method, 'DELETE');
      expect(request.url.queryParameters['date'], '2026-12-15');
    });

    test('규칙 통째로 지우기는 ?date= 가 없다', () async {
      final f = fixture((_) async => http.Response('', 204));

      await f.repo.delete(5);

      expect(f.sent.single.url.queryParameters.containsKey('date'), isFalse);
    });

    test('펼친 하루의 키는 id 가 아니라 (id, 날짜) 다', () {
      final first = Schedule.tryParse(
          {..._schedule(id: 5, onDate: '2026-12-01'), 'occurrence': true})!;
      final second = Schedule.tryParse(
          {..._schedule(id: 5, onDate: '2026-12-08'), 'occurrence': true})!;

      expect(first.key, isNot(second.key),
          reason: 'id 만 보면 완료 표시 하나가 그 규칙의 모든 날에 번진다');
    });

    test('모르는 주기는 반복 안 함으로 읽는다 — 목록에서 사라지면 안 된다', () {
      final s = Schedule.tryParse({..._schedule(), 'repeatKind': 'yearly'})!;

      expect(s.repeatKind, ScheduleRepeat.none);
    });
  });

  group('모르는 값', () {
    test('처음 보는 kind 는 "그 밖" 으로 그린다 — 안 보이면 사라진 것으로 읽힌다', () {
      final s = Schedule.tryParse(_schedule(kind: 'training'))!;

      expect(s.kind, ScheduleKind.etc);
    });
  });
}
