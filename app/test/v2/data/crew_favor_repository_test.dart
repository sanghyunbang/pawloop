// 품앗이 · 방장 넘기기 · 크루 지우기의 왕복 — 이슈 #417, 서버는 PR #428.
//
// ## 여기서 가장 중요한 것
//
// **409 를 경로로 가르는 것**이다. 정원이 찬 것(참여) · 이미 맡은 것(맡기) · 혼자가 아닌
// 것(지우기)이 전부 같은 `CONFLICT` 코드로 온다. 셋 다 사용자가 할 일이 다르다 — 기다리기 ·
// 목록 새로 받기 · 넘기고 나가기. 하나로 뭉치면 "정원이 찼어요" 를 보고 크루를 못 지우는
// 사람이 생긴다.
//
// 그다음이 **날짜를 시간대 변환 없이 읽는 것**이다. `2026-09-20` 은 어디서 보든 9월 20일이다 —
// `DateTime.parse(...).toLocal()` 을 태우면 달력이 하루 밀리는데 오류는 안 난다.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/core/net/authed_client.dart';
import 'package:heat_trip_flutter/v2/data/crew_repository.dart';
import 'package:heat_trip_flutter/v2/domain/crew_favor.dart';

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

http.Response _error(int status, String code, String message) =>
    _json({'error': {'code': code, 'message': message, 'traceId': null}}, status: status);

Map<String, Object?> _favor({
  int id = 12,
  String onDate = '2026-09-20',
  String slot = 'afternoon',
  Object? note = '두 시간만 부탁드려요',
  String status = 'open',
  Object? askedBy = const {'userId': 1, 'nickname': '성수아빠'},
  Object? takenBy,
  Object? dog = const {'dogId': 7, 'name': '보리'},
  bool mine = false,
  bool takenByMe = false,
  Object? scheduleId,
}) =>
    {
      'id': id,
      'onDate': onDate,
      'slot': slot,
      'note': note,
      'status': status,
      'askedBy': askedBy,
      'takenBy': takenBy,
      'dog': dog,
      'mine': mine,
      'takenByMe': takenByMe,
      'scheduleId': scheduleId,
      'createdAt': '2026-09-13T02:20:00Z',
    };

Map<String, Object?> _crew({bool owner = false}) => {
      'id': 4,
      'roomId': 9,
      'name': '성수동 아침 산책',
      'intro': null,
      'neighborhoodCode': '1120052000',
      'visibility': 'invite',
      'capacity': 20,
      'memberCount': 2,
      'mine': true,
      'owner': owner,
      'members': const [],
      'createdAt': '2026-09-10T02:20:00Z',
    };

({CrewRepository repo, List<http.Request> sent}) fixture(
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
  return (repo: CrewRepository(baseUrl: _base, client: client), sent: sent);
}

void main() {
  group('목록', () {
    test('크루 경로 밑의 favors 로 묻고, 온 순서 그대로 돌려준다', () async {
      final f = fixture((_) async => _json([_favor(id: 12), _favor(id: 13, onDate: '2026-09-21')]));

      final favors = await f.repo.favors(4);

      expect(f.sent.single.method, 'GET');
      expect(f.sent.single.url.path, '/api/crews/4/favors');
      expect(favors.map((x) => x.id), [12, 13]);
    });

    test('안 든 사람에게는 404 다 — 공개 크루라도 notFound 다', () async {
      final f = fixture((_) async => _error(404, 'NOT_FOUND', '크루를 찾을 수 없습니다.'));

      await expectLater(
        f.repo.favors(4),
        throwsA(isA<CrewFailure>().having((e) => e.kind, 'kind', CrewFailureKind.notFound)),
      );
    });

    test('한 건이 이상해도 나머지는 산다 — 모르는 시간대는 그리지 않고 뺀다', () async {
      final f = fixture((_) async => _json([
            _favor(id: 1),
            _favor(id: 2, slot: 'night'),
            {'id': 3, 'slot': 'morning'}, // onDate 가 없다
            _favor(id: 4),
          ]));

      final favors = await f.repo.favors(4);

      expect(favors.map((x) => x.id), [1, 4],
          reason: '시간대가 틀린 약속은 없는 약속보다 나쁘다 — 오전에 오기로 한 사람이 저녁에 온다');
    });
  });

  group('올리기', () {
    test('날짜는 2026-09-20 모양, 시간대는 wire 값, 아이와 한 줄은 있을 때만 싣는다', () async {
      final f = fixture((_) async => _json(_favor(mine: true), status: 201));

      await f.repo.postFavor(4,
          onDate: DateTime(2026, 9, 20, 15, 30),
          slot: CrewFavorSlot.afternoon,
          dogId: 7,
          note: '  두 시간만 부탁드려요  ');
      await f.repo.postFavor(4,
          onDate: DateTime(2026, 9, 20), slot: CrewFavorSlot.morning, note: '   ');

      expect(f.sent[0].method, 'POST');
      expect(f.sent[0].url.path, '/api/crews/4/favors');
      expect(jsonDecode(f.sent[0].body), {
        'onDate': '2026-09-20',
        'slot': 'afternoon',
        'dogId': 7,
        'note': '두 시간만 부탁드려요',
      }, reason: '시:분은 안 나간다 — 품앗이는 시간대지 시각이 아니다');
      expect(jsonDecode(f.sent[1].body), {'onDate': '2026-09-20', 'slot': 'morning'},
          reason: '아이 없는 부탁도 있다 — 빈 값을 보내면 서버가 "없는 아이" 로 읽을 여지가 생긴다');
    });

    test('지난 날짜는 400 이고 invalid 다 — 서버 문구를 그대로 든다', () async {
      final f = fixture((_) async => _error(400, 'VALIDATION', '지난 날짜로는 부탁할 수 없습니다.'));

      await expectLater(
        f.repo.postFavor(4, onDate: DateTime(2020, 1, 1), slot: CrewFavorSlot.morning),
        throwsA(isA<CrewFailure>()
            .having((e) => e.kind, 'kind', CrewFailureKind.invalid)
            .having((e) => e.message, 'message', '지난 날짜로는 부탁할 수 없습니다.')),
      );
    });

    test('남의 아이는 404 다', () async {
      final f = fixture((_) async => _error(404, 'NOT_FOUND', '반려동물을 찾을 수 없습니다.'));

      await expectLater(
        f.repo.postFavor(4, onDate: DateTime(2026, 9, 20), slot: CrewFavorSlot.morning, dogId: 99),
        throwsA(isA<CrewFailure>().having((e) => e.kind, 'kind', CrewFailureKind.notFound)),
      );
    });
  });

  group('맡기 · 무르기 · 거둬들이기', () {
    test('경로가 셋 다 다르다 — 맡기·무르기는 take, 거둬들이기는 부탁 자체다', () async {
      final f = fixture((request) async => request.method == 'DELETE' &&
              !request.url.path.endsWith('/take')
          ? http.Response('', 204)
          : _json(_favor()));

      await f.repo.takeFavor(4, 12);
      await f.repo.releaseFavor(4, 12);
      await f.repo.cancelFavor(4, 12);

      expect(f.sent[0].method, 'POST');
      expect(f.sent[0].url.path, '/api/crews/4/favors/12/take');
      expect(f.sent[1].method, 'DELETE');
      expect(f.sent[1].url.path, '/api/crews/4/favors/12/take');
      expect(f.sent[2].method, 'DELETE');
      expect(f.sent[2].url.path, '/api/crews/4/favors/12',
          reason: '무르기와 거둬들이기는 권한도 결과도 다르다 — 한 경로에 조건문으로 섞이면 그 차이가 숨는다');
    });

    test('맡으면 달력 줄의 id 가 함께 온다', () async {
      final f = fixture((_) async => _json(_favor(status: 'taken', takenByMe: true, scheduleId: 99)));

      final taken = await f.repo.takeFavor(4, 12);

      expect(taken.takenByMe, isTrue);
      expect(taken.scheduleId, 99);
      expect(taken.isOpen, isFalse);
    });

    test('이미 맡은 409 는 taken 이다 — 정원이 찬 것(full)이 아니다', () async {
      final f = fixture((_) async => _error(409, 'CONFLICT', '이미 다른 분이 맡았습니다.'));

      await expectLater(
        f.repo.takeFavor(4, 12),
        throwsA(isA<CrewFailure>().having((e) => e.kind, 'kind', CrewFailureKind.taken)),
      );
    });

    test('내 부탁을 내가 맡으면 400 이고 invalid 다', () async {
      final f = fixture((_) async => _error(400, 'VALIDATION', '내가 올린 부탁은 내가 맡을 수 없습니다.'));

      await expectLater(
        f.repo.takeFavor(4, 12),
        throwsA(isA<CrewFailure>()
            .having((e) => e.kind, 'kind', CrewFailureKind.invalid)
            .having((e) => e.message, 'message', '내가 올린 부탁은 내가 맡을 수 없습니다.')),
      );
    });

    test('맡은 사람이 아니면 무르기가 403, 올린 사람이 아니면 거둬들이기가 403 이다', () async {
      final release = fixture((_) async => _error(403, 'FORBIDDEN', '맡은 분만 무를 수 있습니다.'));
      final cancel = fixture((_) async => _error(403, 'FORBIDDEN', '올린 분만 지울 수 있습니다.'));

      await expectLater(
        release.repo.releaseFavor(4, 12),
        throwsA(isA<CrewFailure>()
            .having((e) => e.kind, 'kind', CrewFailureKind.forbidden)
            .having((e) => e.message, 'message', '맡은 분만 무를 수 있습니다.')),
      );
      await expectLater(
        cancel.repo.cancelFavor(4, 12),
        throwsA(isA<CrewFailure>()
            .having((e) => e.kind, 'kind', CrewFailureKind.forbidden)
            .having((e) => e.message, 'message', '올린 분만 지울 수 있습니다.')),
      );
    });
  });

  group('넘기기 · 지우기', () {
    test('넘기기는 PUT 이고 본문이 없다 — 돌아온 크루의 owner 는 false 다', () async {
      final f = fixture((_) async => _json(_crew(owner: false)));

      final crew = await f.repo.transferOwner(4, 2);

      expect(f.sent.single.method, 'PUT');
      expect(f.sent.single.url.path, '/api/crews/4/owner/2');
      expect(crew.owner, isFalse, reason: '넘긴 뒤의 나는 평범한 멤버다 — 그래서 나갈 수 있다');
    });

    test('자기 자신에게 넘기면 400, 그 방에 없는 사람이면 404 다', () async {
      final self = fixture((_) async => _error(400, 'VALIDATION', '자기 자신에게 넘길 수 없습니다.'));
      final stranger = fixture((_) async => _error(404, 'NOT_FOUND', '그 방의 멤버가 아닙니다.'));

      await expectLater(
        self.repo.transferOwner(4, 1),
        throwsA(isA<CrewFailure>().having((e) => e.kind, 'kind', CrewFailureKind.invalid)),
      );
      await expectLater(
        stranger.repo.transferOwner(4, 77),
        throwsA(isA<CrewFailure>().having((e) => e.kind, 'kind', CrewFailureKind.notFound)),
      );
    });

    test('지우기는 DELETE /api/crews/{id} 이고 204 로 끝난다', () async {
      final f = fixture((_) async => http.Response('', 204));

      await f.repo.delete(4);

      expect(f.sent.single.method, 'DELETE');
      expect(f.sent.single.url.path, '/api/crews/4');
    });

    test('혼자가 아니면 409 이고 notAlone 이다 — full 이 아니다', () async {
      final f = fixture((_) async => _error(409, 'CONFLICT', '혼자 남았을 때만 지울 수 있습니다.'));

      await expectLater(
        f.repo.delete(4),
        throwsA(isA<CrewFailure>().having((e) => e.kind, 'kind', CrewFailureKind.notAlone)),
      );
    });

    test('참여의 409 는 여전히 full 이다 — 경로로 가르는 것이 참여를 안 바꿨다', () async {
      final f = fixture((_) async => _error(409, 'CONFLICT', '크루 정원이 찼습니다.'));

      await expectLater(
        f.repo.join(4),
        throwsA(isA<CrewFailure>().having((e) => e.kind, 'kind', CrewFailureKind.full)),
      );
    });
  });

  group('파싱', () {
    test('날짜를 시간대 변환 없이 읽는다 — 9월 20일은 어디서 보든 9월 20일이다', () {
      final favor = CrewFavor.tryParse(_favor(onDate: '2026-09-20'))!;

      expect(favor.onDate, DateTime(2026, 9, 20));
      expect(favor.onDate.isUtc, isFalse);
      expect(favor.whenLabel, '9월 20일 (일) 오후');
    });

    test('모르는 상태는 taken 이다 — 열린 것으로 그리면 서버가 거절할 버튼이 뜬다', () {
      expect(CrewFavor.tryParse(_favor(status: 'done'))!.isOpen, isFalse);
      expect(CrewFavor.tryParse(_favor(status: 'open'))!.isOpen, isTrue);
    });

    test('탈퇴한 사람은 null 이고 부탁은 산다', () {
      final favor = CrewFavor.tryParse(_favor(askedBy: null, takenBy: null))!;

      expect(favor.askedBy, isNull);
      expect(favor.takenBy, isNull);
      expect(favor.id, 12);
    });

    test('아이와 한 줄이 둘 다 없으면 둘째 줄이 없다 — 빈 줄을 그리지 않는다', () {
      expect(CrewFavor.tryParse(_favor())!.detailLabel, '보리 · 두 시간만 부탁드려요');
      expect(CrewFavor.tryParse(_favor(note: '  '))!.detailLabel, '보리');
      expect(CrewFavor.tryParse(_favor(dog: null, note: null))!.detailLabel, isNull);
    });

    test('createdAt 은 오프셋을 읽어 기기 시각으로 눕힌다 — onDate 와 다른 종류다', () {
      final favor = CrewFavor.tryParse(_favor())!;

      expect(favor.createdAt!.toUtc(), DateTime.utc(2026, 9, 13, 2, 20));
    });

    test('날짜 → id 순서다 — 올린 부탁을 목록에 끼워 넣을 때 서버와 같은 자리다', () {
      final a = CrewFavor.tryParse(_favor(id: 5, onDate: '2026-09-21'))!;
      final b = CrewFavor.tryParse(_favor(id: 9, onDate: '2026-09-20'))!;
      final c = CrewFavor.tryParse(_favor(id: 3, onDate: '2026-09-20'))!;

      expect(([a, b, c]..sort(CrewFavor.compare)).map((f) => f.id), [3, 9, 5]);
    });
  });
}
